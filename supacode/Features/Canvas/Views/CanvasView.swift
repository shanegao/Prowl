import AppKit
import Sharing
import SwiftUI

struct CanvasView: View {
  @Environment(CommandKeyObserver.self) var commandKeyObserver
  @Environment(\.resolvedKeybindings) var resolvedKeybindings

  let terminalManager: WorktreeTerminalManager

  /// When non-nil, the canvas is in per-worktree scope and shows only panes
  /// from this worktree. The three canvas scopes are mutually exclusive:
  /// - `scopedWorktreeID` set, `scopedWorktreeIDs` nil → per-worktree
  /// - `scopedWorktreeID` nil, `scopedWorktreeIDs` set → per-repository
  /// - both nil → overall canvas (every active worktree's panes)
  var scopedWorktreeID: Worktree.ID?
  /// When non-nil, the canvas is in per-repository scope and shows only panes
  /// from worktrees whose IDs are in this set. See `scopedWorktreeID` doc for
  /// the full mode matrix.
  var scopedWorktreeIDs: Set<Worktree.ID>?
  /// When non-nil, restricts the rendered cards to tabs whose ID is in this
  /// set — used by the active-agents canvas to show only tabs that currently
  /// have a live agent. Applies on top of the worktree-scope filters (the
  /// active-agents canvas leaves both worktree filters nil, so this is the
  /// sole filter for that mode). `nil` renders every tab (all other modes).
  var scopedTabIDs: Set<TerminalTabID>?
  /// Optional pane ordering. The closure returns a (primary, secondary) string
  /// pair used to sort `WorktreeTerminalState`s after scope filtering. Pass
  /// `(repoName, worktreeName)` to group panes by repository, then alphabetize
  /// within each repo. `nil` keeps the natural order from `terminalManager`.
  var sortKey: ((WorktreeTerminalState) -> (String, String))?

  /// Per-repo display titles resolved by the parent reducer. Used to
  /// override the folder-derived `Repository.name` on each card title
  /// bar without subscribing to per-repo settings files on the
  /// per-frame canvas hot path.
  var repositoryCustomTitles: [Repository.ID: String] = [:]
  var focusRequest: CanvasFocusRequest?
  /// A one-shot, reducer-driven request to run a view-local canvas command
  /// (expand/arrange/organize/select-all), e.g. from the command palette.
  var commandRequest: CanvasCommandRequest?
  /// Exit-to-tab callback. The associated worktree ID is non-nil for
  /// expand-to-pane (jump to that card's worktree and leave canvas) and nil
  /// for a plain toggle-off (the parent decides where to land based on scope).
  var onExitToTab: (Worktree.ID?) -> Void = { _ in }
  var onFocusedWorktreeChanged: (Worktree.ID?) -> Void = { _ in }
  var onFocusRequestConsumed: (Int) -> Void = { _ in }
  var onCommandConsumed: (Int) -> Void = { _ in }
  /// Reports whether a card is currently expanded in place, so the parent can
  /// give the window toolbar a matching scrim (it can't be covered from here).
  var onExpandedChange: (Bool) -> Void = { _ in }
  @State var layoutStore = CanvasLayoutStore()
  @Shared(.repositoryAppearances) var repositoryAppearances
  @Shared(.settingsFile) var settingsFile

  @State var canvasOffset: CGSize = .zero
  @State var lastCanvasOffset: CGSize = .zero
  @State var canvasScale: CGFloat = 1.0
  @State var lastCanvasScale: CGFloat = 1.0
  @State var selectionState = CanvasSelectionState()
  @State var lastTitleBarTapDate: Date = .distantPast
  @State var activeResize: [TerminalTabID: ActiveResize] = [:]
  @State var hasPerformedInitialFit = false
  @State var hasSeenCanvasCards = false
  @State var viewportSize: CGSize = .zero
  @State private var resizeRelayoutTask: Task<Void, Never>?
  @State var configReloadCounter = 0
  @State var focusViewportAnimationID = 0
  /// The tab currently expanded in place (near-fullscreen overlay) on canvas,
  /// or nil when no card is expanded.
  @State var expandedTabID: TerminalTabID?
  @State var viewportAnimator = CanvasViewportAnimator()

  let minCardWidth: CGFloat = 300
  let minCardHeight: CGFloat = 200
  let maxCardWidth: CGFloat = 2400
  let maxCardHeight: CGFloat = 1600
  let titleBarHeight: CGFloat = 28
  let cardSpacing: CGFloat = 20
  /// Tighter gap for the Tile layout. It lives in the scaled-up tile frame, so
  /// the on-screen gap shrinks further as more cards are tiled (gap × scale).
  let tileCardSpacing: CGFloat = 12
  /// Outer margin kept when fitting the whole canvas into the visible viewport.
  let viewportFitPadding: CGFloat = 12
  /// Reserved height at the bottom of the viewport for the help button and
  /// layout toolbar so cards don't sit underneath them after auto-fit.
  /// Cards end up shifted upward by half of this amount.
  let bottomToolbarReserve: CGFloat = 40
  /// Margin kept on every side of a card temporarily expanded to near-fullscreen.
  let expandPadding: CGFloat = 40
  /// Shared animation for expand / restore / relayout. Matches the easeInOut
  /// 0.2s that `CanvasCardView` uses to animate `cardSize`, so the canvas
  /// scale/offset stays in lock-step with the card's terminal size refit.
  let expandAnimation: Animation = .easeInOut(duration: 0.2)

  /// Width of the screen hosting the canvas window, used to scale the default
  /// card size. Falls back to the large-screen reference when unknown.
  var hostScreenWidth: CGFloat {
    (NSApp.keyWindow?.screen ?? NSScreen.main)?.frame.width
      ?? CanvasCardLayout.maxDefaultScreenWidth
  }

  /// Default size for newly created and uniformly arranged cards, scaled to the
  /// host screen so small screens (14") don't zoom out into tiny text while
  /// large screens still get the roomier card.
  var adaptiveDefaultCardSize: CGSize {
    CanvasCardLayout.adaptiveDefaultSize(forScreenWidth: hostScreenWidth)
  }

  /// True for any scoped canvas (per-worktree, per-repository, or active-agents).
  /// Scoped canvases tile the viewport with `focusAwareCardLayout` and reset
  /// their layout on scope/viewport changes; the overall canvas keeps user
  /// card positions and sizes.
  var isScopedMode: Bool {
    scopedWorktreeID != nil || scopedWorktreeIDs != nil || scopedTabIDs != nil
  }

  /// The tab whose card should be grown to 50% of its row width. Non-nil only
  /// when exactly one card is selected (matches "selected only one card" from
  /// the user spec); during multi-card broadcast and zero-selection the value
  /// is nil and rows fall back to uniform widths. Drives `focusAwareCardLayout`
  /// and the `.onChange` re-layout trigger; recomputed from `selectionState`
  /// every body evaluation so SwiftUI's `.onChange(of:)` sees value changes.
  private var focusGrowTabID: TerminalTabID? {
    selectionState.selectedTabIDs.count == 1 ? selectionState.primaryTabID : nil
  }

  /// Worktree that owns the current primary card. Used by the external-focus
  /// `.onChange(of: terminalManager.canvasFocusedWorktreeID)` handler to skip
  /// when the requested focus already matches the current primary — that's
  /// the self-trigger guard against `syncPrimaryFocus`'s own writes.
  private var primaryCardOwnerWorktreeID: Worktree.ID? {
    guard let primaryTabID = selectionState.primaryTabID else { return nil }
    return terminalManager.activeWorktreeStates
      .first(where: { $0.surfaceView(for: primaryTabID) != nil })?
      .worktreeID
  }

  /// Filters `terminalManager.activeWorktreeStates` by the active scope filter:
  /// `scopedWorktreeID` (per-worktree) or `scopedWorktreeIDs` (per-repo). With
  /// no filter set, returns all active states (overall canvas). Sorted by
  /// `sortKey` when provided.
  var scopedActiveStates: [WorktreeTerminalState] {
    let all = terminalManager.activeWorktreeStates
    var filtered: [WorktreeTerminalState]
    if let scopedWorktreeID {
      filtered = all.filter { $0.worktreeID == scopedWorktreeID }
    } else if let scopedWorktreeIDs {
      filtered = all.filter { scopedWorktreeIDs.contains($0.worktreeID) }
    } else {
      filtered = all
    }
    guard let sortKey else { return filtered }
    return filtered.sorted { lhs, rhs in
      let l = sortKey(lhs)
      let r = sortKey(rhs)
      let primary = l.0.localizedCaseInsensitiveCompare(r.0)
      if primary != .orderedSame { return primary == .orderedAscending }
      return l.1.localizedCaseInsensitiveCompare(r.1) == .orderedAscending
    }
  }

  /// Tab visibility gate. `scopedTabIDs == nil` (the worktree/repo/overall
  /// canvases) shows every tab; the active-agents canvas passes the set of
  /// agent tab IDs so only those render.
  func includesTab(_ tabID: TerminalTabID) -> Bool {
    scopedTabIDs?.contains(tabID) ?? true
  }

  var body: some View {
    let selectAllCanvasShortcut = AppShortcuts.resolvedShortcut(
      for: AppShortcuts.CommandID.selectAllCanvasCards,
      in: resolvedKeybindings
    )
    let arrangeCanvasShortcut = AppShortcuts.resolvedShortcut(
      for: AppShortcuts.CommandID.arrangeCanvasCards,
      in: resolvedKeybindings
    )
    let organizeCanvasShortcut = AppShortcuts.resolvedShortcut(
      for: AppShortcuts.CommandID.organizeCanvasCards,
      in: resolvedKeybindings
    )
    let tileCanvasShortcut = AppShortcuts.resolvedShortcut(
      for: AppShortcuts.CommandID.tileCanvasCards,
      in: resolvedKeybindings
    )
    let expandCanvasShortcut = AppShortcuts.resolvedShortcut(
      for: AppShortcuts.CommandID.expandCanvasCard,
      in: resolvedKeybindings
    )
    let _ = configReloadCounter
    CanvasScrollContainer(
      offset: $canvasOffset,
      lastOffset: $lastCanvasOffset,
      scale: $canvasScale,
      lastScale: $lastCanvasScale,
      isInteractionEnabled: expandedTabID == nil
    ) {
      canvasScrollContent
    }
    .overlay(alignment: .bottomTrailing) {
      canvasToolbar
    }
    .overlay(alignment: .bottomLeading) {
      CanvasHelpButton()
    }
    .onKeyPress(.escape) {
      guard selectionState.isBroadcasting else { return .ignored }
      clearSelection(states: scopedActiveStates)
      return .handled
    }
    .onKeyPress(
      selectAllCanvasShortcut?.keyEquivalent ?? AppShortcuts.selectAllCanvasCards.keyEquivalent,
      phases: .down
    ) { keyPress in
      // Bail when the binding is disabled in Settings (resolved shortcut is nil);
      // otherwise the app-default key would still fire despite being unbound.
      guard let shortcut = selectAllCanvasShortcut else { return .ignored }
      guard keyPress.modifiers == shortcut.modifiers else { return .ignored }
      selectAllCards()
      return .handled
    }
    .onKeyPress(
      arrangeCanvasShortcut?.keyEquivalent ?? AppShortcuts.arrangeCanvasCards.keyEquivalent,
      phases: .down
    ) { keyPress in
      guard let shortcut = arrangeCanvasShortcut else { return .ignored }
      guard keyPress.modifiers == shortcut.modifiers else { return .ignored }
      arrangeCardsWithFit()
      return .handled
    }
    .onKeyPress(
      organizeCanvasShortcut?.keyEquivalent ?? AppShortcuts.organizeCanvasCards.keyEquivalent,
      phases: .down
    ) { keyPress in
      guard let shortcut = organizeCanvasShortcut else { return .ignored }
      guard keyPress.modifiers == shortcut.modifiers else { return .ignored }
      organizeCardsWithFit()
      return .handled
    }
    .onKeyPress(
      tileCanvasShortcut?.keyEquivalent ?? AppShortcuts.tileCanvasCards.keyEquivalent,
      phases: .down
    ) { keyPress in
      guard let shortcut = tileCanvasShortcut else { return .ignored }
      guard keyPress.modifiers == shortcut.modifiers else { return .ignored }
      tileCardsWithFit()
      return .handled
    }
    .onKeyPress(
      expandCanvasShortcut?.keyEquivalent ?? AppShortcuts.expandCanvasCard.keyEquivalent,
      phases: .down
    ) { keyPress in
      guard let shortcut = expandCanvasShortcut else { return .ignored }
      guard keyPress.modifiers == shortcut.modifiers else { return .ignored }
      toggleExpandFocusedCard()
      return .handled
    }
    .onChange(of: expandedTabID) { _, newValue in
      onExpandedChange(newValue != nil)
    }
    .onChange(of: commandRequest) { _, newRequest in
      fulfillCommandRequest(newRequest)
    }
    .task { activateCanvas() }
    .onReceive(NotificationCenter.default.publisher(for: .ghosttyRuntimeConfigDidChange)) { _ in
      configReloadCounter &+= 1
    }
    .onDisappear {
      resizeRelayoutTask?.cancel()
      resizeRelayoutTask = nil
      deactivateCanvas()
    }
  }

  func showsSelectionShield(for tabID: TerminalTabID) -> Bool {
    if commandKeyObserver.isPressed { return true }
    if selectionState.isSelecting { return true }
    if selectionState.isBroadcasting, selectionState.primaryTabID != tabID { return true }
    return false
  }

  /// The scrollable canvas surface (background + cards). Extracted from `body`
  /// so the `CanvasScrollContainer` / `GeometryReader` / `.onGeometryChange`
  /// chain stays small enough for the Swift type checker.
  @ViewBuilder
  private var canvasScrollContent: some View {
    GeometryReader { _ in
      let activeStates = scopedActiveStates
      let allCardKeys = collectCardKeys(from: activeStates)
      let allTabIDs = collectVisibleTabIDs(from: activeStates)

      canvasBackgroundLayer(
        activeStates: activeStates,
        allCardKeys: allCardKeys,
        allTabIDs: allTabIDs
      )

      cardsLayer(activeStates: activeStates)
    }
    .contentShape(.rect)
    .simultaneousGesture(canvasZoomGesture, isEnabled: expandedTabID == nil)
    .animation(.easeInOut(duration: 0.22), value: focusViewportAnimationID)
    .onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { newSize in
      let previousSize = viewportSize
      viewportSize = newSize
      let currentCardKeys = collectCardKeys(from: scopedActiveStates)
      if !hasPerformedInitialFit, !currentCardKeys.isEmpty {
        performInitialFit(for: currentCardKeys, canvasSize: newSize)
      } else if previousSize != newSize, isScopedMode {
        // Scoped canvases re-tile to the new viewport on window resize so the
        // grid keeps filling the visible space; debounced to avoid thrash
        // during a live drag. The overall canvas keeps user card positions.
        scheduleResizeRelayout(for: newSize)
      }
    }
  }

  // MARK: - Cards Layer

  /// Background layer: handles canvas pan, tap-to-clear, and the lifecycle /
  /// scope `.onChange` handlers. Extracted from `body` so the type checker
  /// doesn't choke on the combined modifier chain.
  @ViewBuilder
  private func canvasBackgroundLayer(
    activeStates: [WorktreeTerminalState],
    allCardKeys: [String],
    allTabIDs: [TerminalTabID]
  ) -> some View {
    Color.clear
      .modifier(
        CanvasLifecycleHandlers(
          allCardKeys: allCardKeys,
          allTabIDs: allTabIDs,
          focusRequest: focusRequest,
          onAppear: {
            if !allCardKeys.isEmpty {
              hasSeenCanvasCards = true
            }
            ensureLayouts(for: allCardKeys)
            if !allCardKeys.isEmpty {
              layoutStore.ensureZOrder(for: allCardKeys)
            }
            pruneSelection(previousOrder: [], currentOrder: allTabIDs, states: activeStates)
            syncBroadcastCallbacks(states: activeStates)
            fulfillPendingFocusRequest(focusRequest, states: activeStates)
          },
          onCardKeysChanged: { newKeys in
            if newKeys.isEmpty {
              if hasSeenCanvasCards {
                layoutStore.prune(to: [])
              }
            } else {
              hasSeenCanvasCards = true
            }
            ensureLayouts(for: newKeys)
            if !newKeys.isEmpty {
              layoutStore.ensureZOrder(for: newKeys)
              performColdEntryFitIfNeeded()
            }
            syncBroadcastCallbacks(states: activeStates)
            fulfillPendingFocusRequest(focusRequest, states: activeStates)
          },
          onTabIDsChanged: { oldTabIDs, newTabIDs in
            pruneSelection(previousOrder: oldTabIDs, currentOrder: newTabIDs, states: activeStates)
            if let expandedTabID, !newTabIDs.contains(expandedTabID) {
              cancelExpandForRelayout()
            }
            fulfillPendingFocusRequest(focusRequest, states: activeStates)
          },
          onFocusRequestChanged: { newRequest in
            fulfillPendingFocusRequest(newRequest, states: activeStates)
          }
        )
      )
      .modifier(canvasScopeChangeHandlers)
      .contentShape(.rect)
      .accessibilityAddTraits(.isButton)
      .onTapGesture { clearSelection(states: activeStates) }
      .gesture(canvasPanGesture, isEnabled: expandedTabID == nil)
  }

  /// Scope-driven relayout handlers, factored into a `ViewModifier` so the
  /// background layer's modifier chain stays short enough for the type checker.
  private var canvasScopeChangeHandlers: some ViewModifier {
    CanvasScopeChangeHandlers(
      scopedWorktreeID: scopedWorktreeID,
      scopedWorktreeIDs: scopedWorktreeIDs,
      scopedTabIDs: scopedTabIDs,
      focusGrowTabID: focusGrowTabID,
      canvasFocusedWorktreeID: terminalManager.canvasFocusedWorktreeID,
      isScopedMode: isScopedMode,
      onScopeRelayout: {
        applyLayoutForCurrentMode()
        fitToView(canvasSize: viewportSize)
      },
      onFocusGrowChanged: {
        guard isScopedMode else { return }
        withAnimation(.smooth(duration: 0.15)) {
          organizeCards()
        }
      },
      onExternalFocus: { newValue in
        // External focus request (e.g. repo-canvas sidebar tap on a different
        // worktree): switch the primary card to that worktree's first tab.
        // `syncPrimaryFocus` writes this same field on every primary change,
        // so the divergence guard below prevents a self-trigger loop —
        // syncPrimaryFocus's writes always equal the current primary's owner.
        guard let newValue,
          isScopedMode,
          primaryCardOwnerWorktreeID != newValue,
          let owner = scopedActiveStates.first(where: { $0.worktreeID == newValue }),
          let firstTab = owner.tabManager.tabs.first
        else { return }
        focusSingleCard(firstTab.id, states: scopedActiveStates)
        // External navigation (sidebar / notification / command-palette) into a
        // scoped canvas: zoom-fit + center the target, matching the active-agents
        // popover behavior so navigating always brings the card fully into view.
        focusViewport(on: firstTab.id)
      }
    )
  }

  /// Uses .offset() (not .position()) to avoid parent size proposals
  /// reaching the NSView, keeping terminal grid stable during zoom.
  @ViewBuilder
  func cardsLayer(activeStates: [WorktreeTerminalState]) -> some View {
    // Pin to .topLeading and fill the viewport so each card's `.offset()` keeps
    // the same (0,0) origin it had under GeometryReader — otherwise the scrim's
    // full-size frame would resize the stack and shift the cards' base position.
    ZStack(alignment: .topLeading) {
      ForEach(activeStates, id: \.worktreeID) { state in
        ForEach(state.tabManager.tabs) { tab in
          if state.surfaceView(for: tab.id) != nil, includesTab(tab.id) {
            cardView(for: tab, in: state, activeStates: activeStates)
          }
        }
      }

      // Dimming scrim behind the expanded card (above all other cards). Tapping
      // it — i.e. anywhere outside the expanded card, including the padding —
      // restores the layout.
      if expandedTabID != nil {
        // Material gives a GPU-efficient backdrop blur; a small black overlay
        // adds the dim. The whole scrim is kept partly transparent so the
        // background cards stay clearly visible (still running) behind it.
        Rectangle()
          .fill(.ultraThinMaterial)
          .overlay(Color.black.opacity(0.1))
          .opacity(0.7)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(.rect)
          .accessibilityAddTraits(.isButton)
          .accessibilityLabel("Restore expanded card")
          .onTapGesture { collapseExpand() }
          .zIndex(5_000)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  func cardView(
    for tab: TerminalTabItem,
    in state: WorktreeTerminalState,
    activeStates: [WorktreeTerminalState]
  ) -> some View {
    let tree = state.splitTree(for: tab.id)
    let cardKey = tab.id.rawValue.uuidString
    let baseLayout = layoutStore.cardLayouts[cardKey] ?? CanvasCardLayout(position: .zero)
    let isCardExpanded = expandedTabID == tab.id
    // The title-bar button exits to this card's pane when not expanded, and
    // restores the card while expanded in place (⌘-expand shortcut). The help
    // text tracks the action; only the restore case carries the shortcut hint
    // since the shortcut drives in-place expand/restore, not the exit.
    let expandHelp =
      isCardExpanded
      ? AppShortcuts.helpText(
        title: "Restore card size",
        commandID: AppShortcuts.CommandID.expandCanvasCard,
        in: resolvedKeybindings
      )
      : "Expand to tab view"
    // The expanded card magic-moves between its in-canvas frame and the full
    // viewport. AnimatedExpandableCard drives every sub-value (size, center,
    // scale) from one animatable progress, so they advance frame by frame in
    // lock-step. The canvas transform is never touched → background frozen.
    let fromGeometry = nonExpandedGeometry(for: tab.id, baseLayout: baseLayout)
    let toGeometry = expandedGeometry()
    let unfocusedSplitOverlay = terminalManager.unfocusedSplitOverlay()
    let splitDivider = terminalManager.splitDividerAppearance()
    let repositoryAppearance = appearance(for: state.repositoryRootURL)
    let resolvedRepositoryName = repositoryDisplayName(for: state.repositoryRootURL)

    AnimatedExpandableCard(
      progress: isCardExpanded ? 1 : 0,
      collapsed: fromGeometry,
      expanded: toGeometry,
      titleBarHeight: titleBarHeight
    ) { renderSize in
      CanvasCardView(
        repositoryName: resolvedRepositoryName,
        worktreeName: tab.displayTitle,
        repositoryIcon: repositoryAppearance.icon,
        repositoryColor: repositoryAppearance.color?.color,
        repositoryRootURL: state.repositoryRootURL,
        tree: tree,
        activeSurfaceID: state.activeSurfaceID(for: tab.id),
        unfocusedSplitOverlay: unfocusedSplitOverlay,
        splitDivider: splitDivider,
        isFocused: selectionState.primaryTabID == tab.id,
        isSelected: selectionState.selectedTabIDs.contains(tab.id),
        hasUnseenNotification: state.hasUnseenNotification(for: tab.id),
        tabIcon: tab.iconLock != .auto ? tab.icon : nil,
        tabId: tab.id,
        tabs: state.tabManager.tabs,
        tabContextMenuActions: tabContextMenuActions(for: state),
        cardSize: renderSize,
        isExpanded: isCardExpanded,
        expandHelp: expandHelp,
        canvasScale: isCardExpanded ? 1 : canvasScale,
        showsSelectionShield: showsSelectionShield(for: tab.id),
        onTap: {
          let cmdHeld = NSEvent.modifierFlags.contains(.command)
          if cmdHeld {
            handleSelectionShieldTap(tab.id, surfaceState: state, states: activeStates)
          } else {
            focusSingleCard(tab.id, states: activeStates)
            // Body tap only — center an off-screen card when zoomed. The
            // title-bar tap deliberately does NOT do this (it owns the
            // double-tap-to-exit, which needs the card to stay put).
            recenterFocusedCardIfOffscreen(tab.id)
          }
        },
        onSelectionTap: {
          handleSelectionShieldTap(tab.id, surfaceState: state, states: activeStates)
        },
        onDragCommit: { translation in commitDrag(for: cardKey, translation: translation) },
        onResize: { edge, translation in
          activeResize[tab.id] = ActiveResize(
            edge: edge,
            translation: CGSize(
              width: translation.width / canvasScale,
              height: translation.height / canvasScale
            )
          )
        },
        onResizeEnd: { commitResize(for: tab.id, cardKey: cardKey, surfaces: tree.leaves()) },
        onSplitOperation: { operation in
          state.performSplitOperation(operation, in: tab.id)
          if selectionState.isBroadcasting {
            syncBroadcastCallbacks(states: activeStates)
          }
        },
        onTitleBarTap: {
          let wasAlreadyFocused =
            selectionState.primaryTabID == tab.id
            && selectionState.selectedTabIDs.count <= 1
          focusSingleCard(tab.id, states: activeStates)
          let now = Date()
          if wasAlreadyFocused,
            now.timeIntervalSince(lastTitleBarTapDate) <= NSEvent.doubleClickInterval
          {
            // Double-tap the title bar exits canvas straight to this card's pane
            // rather than expanding the card in place. While the card is expanded
            // in place (⌘-expand shortcut), double-tap restores it instead.
            if expandedTabID == tab.id {
              collapseExpand()
            } else {
              onExitToTab(state.worktreeID)
            }
          }
          lastTitleBarTapDate = now
        },
        onExpand: {
          // The title-bar button exits canvas to this card's pane (the feature's
          // UX). When the card is currently expanded in place (only reachable via
          // the ⌘-expand keyboard shortcut), it instead restores the card so that
          // state stays recoverable from the button.
          if expandedTabID == tab.id {
            collapseExpand()
          } else {
            focusSingleCard(tab.id, states: activeStates)
            onExitToTab(state.worktreeID)
          }
        },
        onClose: {
          state.closeTab(tab.id)
        }
      )
      .sheet(item: iconPickerBinding(for: tab.id, in: state)) { tabId in
        iconPickerSheet(state: state, tabId: tabId)
      }
    }
    // Animatable progress is interpolated by binding the animation to this
    // card's expanded state. A plain withAnimation around expandedTabID doesn't
    // reach here (the GeometryReader's value-scoped .animation swallows the
    // implicit transaction), so drive it explicitly. Only the toggled card's
    // value changes, so the rest stay put.
    .animation(expandAnimation, value: isCardExpanded)
    .zIndex(zIndex(for: tab.id, cardKey: cardKey))
  }

  func tabContextMenuActions(for state: WorktreeTerminalState) -> TerminalTabContextMenuActions {
    TerminalTabContextMenuActions(
      renameTab: { state.promptChangeTabTitle($0) },
      changeIcon: { state.presentIconPicker(for: $0) },
      closeTab: { state.closeTab($0) },
      closeOthers: { state.closeOtherTabs(keeping: $0) },
      closeToRight: { state.closeTabsToRight(of: $0) },
      closeAll: { state.closeAllTabs() }
    )
  }

  func iconPickerBinding(for tabId: TerminalTabID, in state: WorktreeTerminalState) -> Binding<TerminalTabID?> {
    Binding(
      get: { state.iconPickerTabId == tabId ? tabId : nil },
      set: { state.iconPickerTabId = $0 }
    )
  }

  func iconPickerSheet(state: WorktreeTerminalState, tabId: TerminalTabID) -> some View {
    let currentIcon = state.tabManager.tabs.first(where: { $0.id == tabId })?.icon
    return TabIconPickerView(
      initialIcon: currentIcon,
      defaultIcon: state.defaultIcon(for: tabId),
      onApply: { newIcon in
        state.applyIconChange(tabId, icon: newIcon)
        state.dismissIconPicker()
      },
      onCancel: {
        state.dismissIconPicker()
      }
    )
  }

  // MARK: - Canvas Gestures

  var canvasPanGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        canvasOffset = CGSize(
          width: lastCanvasOffset.width + value.translation.width,
          height: lastCanvasOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        lastCanvasOffset = canvasOffset
      }
  }

  var canvasZoomGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let newScale = max(0.25, min(2.0, lastCanvasScale * value.magnification))
        let anchor = value.startLocation

        // Keep the canvas point under the pinch center fixed:
        // screenPos = canvasPoint * scale + offset
        // → canvasPoint = (anchor - lastOffset) / lastScale
        // → newOffset  = anchor - canvasPoint * newScale
        let canvasX = (anchor.x - lastCanvasOffset.width) / lastCanvasScale
        let canvasY = (anchor.y - lastCanvasOffset.height) / lastCanvasScale

        canvasOffset = CGSize(
          width: anchor.x - canvasX * newScale,
          height: anchor.y - canvasY * newScale
        )
        canvasScale = newScale
      }
      .onEnded { _ in
        lastCanvasScale = canvasScale
        lastCanvasOffset = canvasOffset
      }
  }

  // MARK: - Layout

  /// Batch-position all cards that don't have stored layouts yet.
  /// Uses a single, consistent column count to avoid overlap between
  /// cards positioned in different passes.
  func ensureLayouts(for cardKeys: [String]) {
    let unpositioned = cardKeys.filter { layoutStore.cardLayouts[$0] == nil }
    let isScoped = isScopedMode
    guard !unpositioned.isEmpty || isScoped else { return }

    if isScoped {
      // Re-tile the whole scoped grid so every card matches the new fitted
      // size — keeps the "all equal" invariant as panes come and go, and lets
      // focus-grow apply when exactly one card is selected. The no-`zOrder:`
      // overload preserves the existing stacking order and only appends new
      // keys (alphabetically) — important so a `moveToFront` from a recent
      // tap isn't undone when a sibling card opens. Merge (don't replace) so a
      // scoped relayout never wipes the off-scope overall-canvas positions.
      let focusedKey = focusGrowTabID?.rawValue.uuidString
      let focusedIndex = focusedKey.flatMap { cardKeys.firstIndex(of: $0) }
      let layouts = focusAwareCardLayout(
        keys: cardKeys,
        focusedIndex: focusedIndex,
        viewportSize: viewportSize
      )
      layoutStore.mergeCardLayouts(layouts)
      return
    }

    // Count only VISIBLE cards that already have layouts (ignores stale entries).
    let positionedCount = cardKeys.count - unpositioned.count
    // For incremental adds, preserve the existing grid shape.
    // For initial layout, use total count for a balanced grid.
    let columns =
      positionedCount > 0
      ? gridColumns(for: positionedCount)
      : gridColumns(for: cardKeys.count)

    // Build locally, assign once to trigger a single save.
    let cardSize = adaptiveDefaultCardSize
    var layouts = layoutStore.cardLayouts
    for (offset, key) in unpositioned.enumerated() {
      layouts[key] = CanvasCardLayout(
        position: gridPosition(index: positionedCount + offset, columns: columns, cardSize: cardSize),
        size: cardSize
      )
    }
    layoutStore.setCardLayouts(layouts)
  }

  /// Balanced grid: columns ≈ sqrt(N). No viewport constraint — the canvas
  /// is infinite and fitToView handles zoom.
  func gridColumns(for count: Int) -> Int {
    max(1, Int(ceil(sqrt(Double(count)))))
  }

  func gridPosition(index: Int, columns: Int, cardSize: CGSize) -> CGPoint {
    let cardW = cardSize.width
    let cardH = cardSize.height + titleBarHeight
    let row = index / columns
    let col = index % columns
    return CGPoint(
      x: cardSpacing + (cardW + cardSpacing) * CGFloat(col) + cardW / 2,
      y: cardSpacing + (cardH + cardSpacing) * CGFloat(row) + cardH / 2
    )
  }

  /// Compute effective center and size accounting for resize only (not drag).
  /// Drag is applied separately via `.offset()` to avoid layout passes.
  func resizedFrame(
    for tabID: TerminalTabID,
    baseLayout: CanvasCardLayout
  ) -> (center: CGPoint, size: CGSize) {
    var centerX = baseLayout.position.x
    var centerY = baseLayout.position.y
    var width = baseLayout.size.width
    var height = baseLayout.size.height

    if let resize = activeResize[tabID] {
      let (wSign, hSign) = resize.edge.resizeSigns
      if wSign != 0 {
        let newW = clampWidth(width + CGFloat(wSign) * resize.translation.width)
        centerX += CGFloat(wSign) * (newW - width) / 2
        width = newW
      }
      if hSign != 0 {
        let newH = clampHeight(height + CGFloat(hSign) * resize.translation.height)
        centerY += CGFloat(hSign) * (newH - height) / 2
        height = newH
      }
    }

    return (CGPoint(x: centerX, y: centerY), CGSize(width: width, height: height))
  }

  func screenPosition(for canvasCenter: CGPoint) -> CGPoint {
    CGPoint(
      x: canvasCenter.x * canvasScale + canvasOffset.width,
      y: canvasCenter.y * canvasScale + canvasOffset.height
    )
  }

  func clampWidth(_ width: CGFloat) -> CGFloat {
    max(minCardWidth, min(maxCardWidth, width))
  }

  func clampHeight(_ height: CGFloat) -> CGFloat {
    max(minCardHeight, min(maxCardHeight, height))
  }

  // MARK: - Organize & Fit

  func collectCardKeys(from states: [WorktreeTerminalState]) -> [String] {
    states.flatMap { state in
      state.tabManager.tabs.compactMap { tab in
        state.surfaceView(for: tab.id) != nil && includesTab(tab.id)
          ? tab.id.rawValue.uuidString : nil
      }
    }
  }

  /// Card keys for every tab that currently has a surface, across all active
  /// worktrees — independent of the canvas scope. Unlike `collectCardKeys`, this
  /// does not apply the `includesTab` gate, so out-of-scope-but-live cards are
  /// still reported. Used by `cleanStaleLayouts` to prune only genuinely dead
  /// tabs without deleting off-scope card positions.
  func collectAllLiveCardKeys() -> [String] {
    terminalManager.activeWorktreeStates.flatMap { state in
      state.tabManager.tabs.compactMap { tab in
        state.surfaceView(for: tab.id) != nil ? tab.id.rawValue.uuidString : nil
      }
    }
  }

  func collectVisibleTabIDs(from states: [WorktreeTerminalState]) -> [TerminalTabID] {
    states.flatMap { state in
      state.tabManager.tabs.compactMap { tab in
        state.surfaceView(for: tab.id) != nil && includesTab(tab.id) ? tab.id : nil
      }
    }
  }

  func collectFocusCandidates(from states: [WorktreeTerminalState]) -> [CanvasFocusCandidate] {
    states.flatMap { state in
      state.tabManager.tabs.compactMap { tab in
        state.surfaceView(for: tab.id) != nil
          ? CanvasFocusCandidate(worktreeID: state.worktreeID, tabID: tab.id)
          : nil
      }
    }
  }

  /// Second first-fit latch for cold entry from the command palette: cards can
  /// materialize AFTER the geometry pass (the overlay tears down in the same
  /// transaction that opens the canvas), so the `.onGeometryChange` latch may
  /// have run before any card keys existed. Re-fit once when the viewport is
  /// already measured, gated by the same `hasPerformedInitialFit` flag.
  func performColdEntryFitIfNeeded() {
    let keys = collectCardKeys(from: scopedActiveStates)
    performInitialFit(for: keys, canvasSize: viewportSize)
  }

  /// First-fit on entry from outside canvas mode. Scoped canvases intentionally
  /// re-tile to the viewport; the overall canvas only fills missing card
  /// layouts so persisted user positions, sizes, and stacking are restored.
  func performInitialFit(for cardKeys: [String], canvasSize: CGSize) {
    guard !hasPerformedInitialFit, !cardKeys.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else {
      return
    }
    hasPerformedInitialFit = true
    if isScopedMode {
      arrangeCards()
    } else {
      ensureLayouts(for: cardKeys)
      layoutStore.ensureZOrder(for: cardKeys)
    }
    fitToView(canvasSize: canvasSize)
  }

  /// Runs the auto-layout for the current canvas mode. Scoped canvases tile the
  /// viewport with `focusAwareCardLayout`; the overall canvas uses the adaptive
  /// default card size. Both reset on every canvas open / scope change / resize.
  func applyLayoutForCurrentMode() {
    organizeCards()
  }

  /// Debounce viewport-change relayouts so a live window drag doesn't thrash
  /// the grid on every delta. Cancels any pending relayout and re-fires after
  /// the user stops resizing.
  func scheduleResizeRelayout(for newSize: CGSize) {
    resizeRelayoutTask?.cancel()
    resizeRelayoutTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      applyLayoutForCurrentMode()
      fitToView(canvasSize: newSize)
    }
  }

  /// Reset all card positions to a clean grid layout. For the overall canvas
  /// this keeps the adaptive default size so user dashboards stay predictable;
  /// for a scoped canvas it tiles the viewport so a handful of panes fill the
  /// visible space (with focus-grow when exactly one card is selected).
  func organizeCards() {
    let keys = collectCardKeys(from: scopedActiveStates)
    guard !keys.isEmpty else { return }
    if isScopedMode {
      let focusedKey = focusGrowTabID?.rawValue.uuidString
      let focusedIndex = focusedKey.flatMap { keys.firstIndex(of: $0) }
      let layouts = focusAwareCardLayout(
        keys: keys,
        focusedIndex: focusedIndex,
        viewportSize: viewportSize
      )
      // Merge so re-tiling the scoped grid keeps the off-scope overall-canvas
      // card positions instead of replacing the whole store with scoped keys.
      layoutStore.mergeCardLayouts(layouts, zOrder: keys)
      return
    }
    // Overall (non-scoped) canvas keeps the adaptive default size so new cards
    // line up with user-placed ones; no focus-grow behavior here.
    let columns = gridColumns(for: keys.count)
    let cardSize = adaptiveDefaultCardSize
    var layouts = layoutStore.cardLayouts
    for (index, key) in keys.enumerated() {
      layouts[key] = CanvasCardLayout(
        position: gridPosition(index: index, columns: columns, cardSize: cardSize),
        size: cardSize
      )
    }
    layoutStore.setCardLayouts(layouts, zOrder: keys)
  }

  /// Selection-aware tiling for scoped canvases.
  ///
  /// With `focusedIndex == nil`, OR the focused card's row holds only one
  /// card, every card uses the grid-wide uniform width `availableW / columns`
  /// so partial last rows stay at the same width as full rows.
  ///
  /// With a focused card in a multi-card row, that row's focused card takes
  /// 50% of `availableW` and the peers split the other 50% equally. Other
  /// rows still use the grid-wide uniform width. Heights stay uniform across
  /// rows.
  ///
  /// Peer widths clamp to `minCardWidth`; the row may exceed the viewport
  /// width as a result — pan/zoom absorbs the overflow.
  ///
  /// If `viewportSize` is zero (viewport not measured yet), falls back to the
  /// adaptive default size uniform tiling. Critical: never return an empty
  /// dict for non-empty `keys`, because callers pass the result straight to
  /// `setCardLayouts(...)` which would wipe persisted layouts.
  func focusAwareCardLayout(
    keys: [String],
    focusedIndex: Int?,
    viewportSize: CGSize
  ) -> [String: CanvasCardLayout] {
    guard !keys.isEmpty else { return [:] }
    let columns = gridColumns(for: keys.count)

    if viewportSize.width <= 0 || viewportSize.height <= 0 {
      let defaultSize = adaptiveDefaultCardSize
      var fallback: [String: CanvasCardLayout] = [:]
      for (index, key) in keys.enumerated() {
        fallback[key] = CanvasCardLayout(
          position: gridPosition(index: index, columns: columns, cardSize: defaultSize),
          size: defaultSize
        )
      }
      return fallback
    }

    let rows = Int(ceil(Double(keys.count) / Double(columns)))
    let availableW = viewportSize.width - cardSpacing * CGFloat(columns + 1)
    let availableH =
      viewportSize.height - cardSpacing * CGFloat(rows + 1) - titleBarHeight * CGFloat(rows)
    let cardHeight = clampHeight(availableH / CGFloat(rows))
    let uniformWidth = clampWidth(availableW / CGFloat(columns))

    var layouts: [String: CanvasCardLayout] = [:]
    for rowIdx in 0..<rows {
      let firstColOfRow = rowIdx * columns
      let lastColOfRow = min(firstColOfRow + columns - 1, keys.count - 1)
      let rowCardCount = lastColOfRow - firstColOfRow + 1

      // Focused card is grown only when it sits in this row AND the row has
      // at least one peer to share the other half with. Single-card rows
      // fall through to uniform (which gives the lone card full row width).
      let localFocusedIndex: Int? = {
        guard let focusedIndex,
          focusedIndex >= firstColOfRow,
          focusedIndex <= lastColOfRow,
          rowCardCount > 1
        else { return nil }
        return focusedIndex - firstColOfRow
      }()

      let widths: [CGFloat] = {
        if let localFocusedIndex {
          let focusedW = clampWidth(0.5 * availableW)
          let peerW = clampWidth(0.5 * availableW / CGFloat(rowCardCount - 1))
          return (0..<rowCardCount).map { $0 == localFocusedIndex ? focusedW : peerW }
        }
        return Array(repeating: uniformWidth, count: rowCardCount)
      }()

      // Y is uniform per row; X walks a cursor across the row so non-uniform
      // widths place neighbors correctly without overlap.
      let centerY =
        cardSpacing
        + (cardHeight + titleBarHeight + cardSpacing) * CGFloat(rowIdx)
        + (cardHeight + titleBarHeight) / 2
      var cursorX = cardSpacing
      for localCol in 0..<rowCardCount {
        let width = widths[localCol]
        let key = keys[firstColOfRow + localCol]
        layouts[key] = CanvasCardLayout(
          position: CGPoint(x: cursorX + width / 2, y: centerY),
          size: CGSize(width: width, height: cardHeight)
        )
        cursorX += width + cardSpacing
      }
    }
    return layouts
  }

  /// Arrange cards using MaxRects-BSSF bin packing. Preserves each card's
  /// current size and finds a compact layout whose aspect ratio matches
  /// the viewport.
  func arrangeCards() {
    let keys = collectCardKeys(from: scopedActiveStates)
    guard !keys.isEmpty, viewportSize.width > 0, viewportSize.height > 0 else { return }

    let cards: [CanvasCardPacker.CardInfo] = keys.map { key in
      let size = layoutStore.cardLayouts[key]?.size ?? adaptiveDefaultCardSize
      return CanvasCardPacker.CardInfo(key: key, size: size)
    }

    let packer = CanvasCardPacker(spacing: cardSpacing, titleBarHeight: titleBarHeight)
    let targetRatio = viewportSize.width / viewportSize.height
    let result = packer.pack(cards: cards, targetRatio: targetRatio)

    guard !result.layouts.isEmpty else { return }
    // Merge so packing the scoped cards preserves off-scope card positions.
    layoutStore.mergeCardLayouts(result.layouts, zOrder: keys)
  }

  /// Tile cards to fill the viewport: resize every card into a balanced grid
  /// whose orientation follows the viewport (rows when wide, columns when tall).
  func tileCards() {
    let keys = collectCardKeys(from: terminalManager.activeWorktreeStates)
    guard !keys.isEmpty, viewportSize.width > 0, viewportSize.height > 0 else { return }

    // Below this card surface, scale the layout up (and the viewport back down)
    // so cards keep enough rows/columns to read at a glance. 0.6 keeps a handful
    // of cards at native scale before the gentle zoom-out begins.
    let comfortableSize = CGSize(
      width: adaptiveDefaultCardSize.width * 0.6,
      height: adaptiveDefaultCardSize.height * 0.6
    )
    let tiler = CanvasTileLayout(spacing: tileCardSpacing, titleBarHeight: titleBarHeight)
    let layouts = tiler.layout(keys: keys, viewport: viewportSize, comfortableSize: comfortableSize)
    guard !layouts.isEmpty else { return }
    layoutStore.setCardLayouts(layouts, zOrder: keys)
  }

  /// Arrange cards (preserving sizes) and refit the viewport, animated.
  /// Shared by the toolbar button and the keyboard shortcut.
  func arrangeCardsWithFit() {
    withAnimation(.easeInOut(duration: 0.2)) {
      cancelExpandForRelayout()
      arrangeCards()
      fitToView(canvasSize: viewportSize)
    }
  }

  /// Organize cards into a uniform grid and refit the viewport, animated.
  /// Shared by the toolbar button and the keyboard shortcut.
  func organizeCardsWithFit() {
    withAnimation(.easeInOut(duration: 0.2)) {
      cancelExpandForRelayout()
      organizeCards()
      fitToView(canvasSize: viewportSize)
    }
  }

  /// Tile cards to fill the viewport and refit, animated. Shared by the toolbar
  /// button and the keyboard shortcut.
  func tileCardsWithFit() {
    withAnimation(.easeInOut(duration: 0.2)) {
      cancelExpandForRelayout()
      tileCards()
      fitToView(canvasSize: viewportSize)
    }
  }

  /// Adjust scale and offset so all cards fit within the viewport.
  func fitToView(canvasSize: CGSize) {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return }

    // Fit only the cards visible in the current scope. The store now retains
    // off-scope cards (merge, not replace), so an unscoped key set would skew
    // the bounding box toward worktrees that aren't on screen.
    let keys = collectCardKeys(from: scopedActiveStates)
    guard !keys.isEmpty else { return }

    var bounds = CGRect.null

    for key in keys {
      guard let layout = layoutStore.cardLayouts[key] else { continue }
      bounds = bounds.union(cardRect(for: layout))
    }

    guard
      let fit = CanvasViewportMath.fit(
        bounds: bounds,
        viewport: canvasSize,
        bottomReserve: bottomToolbarReserve,
        padding: viewportFitPadding
      )
    else {
      return
    }

    canvasOffset = fit.offset
    canvasScale = fit.scale
    lastCanvasScale = fit.scale
    lastCanvasOffset = canvasOffset
  }

  /// Remove stored layouts for tabs that no longer exist. Staleness is a global
  /// property: a card that's merely out of the current scope (e.g. a non-agent
  /// card while the active-agents canvas is open) is not stale, so this prunes
  /// against every live card — never the scope-filtered set, which would re-wipe
  /// the off-scope positions the merge relayout just preserved.
  func cleanStaleLayouts() {
    let visibleKeys = Set(collectAllLiveCardKeys())
    guard !visibleKeys.isEmpty || hasSeenCanvasCards else { return }
    layoutStore.prune(to: visibleKeys)
  }

  var canvasToolbar: some View {
    // Two visual groups: selection (broadcast / select-all) and the three layout
    // actions. A wider gap separates the groups; the layout trio is tucked tight.
    HStack(spacing: 14) {
      HStack(spacing: 8) {
        if selectionState.isBroadcasting {
          Label(
            "Broadcasting to \(selectionState.selectedTabIDs.count) cards",
            systemImage: "dot.radiowaves.left.and.right"
          )
          .font(.callout)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(.bar, in: Capsule())
        }

        Button {
          selectAllCards()
        } label: {
          Image(systemName: "checkmark.rectangle.stack")
            .font(.body)
            .accessibilityLabel("Select All")
        }
        .buttonStyle(.bordered)
        .help(
          AppShortcuts.helpText(
            title: "Select all cards for broadcast",
            commandID: AppShortcuts.CommandID.selectAllCanvasCards,
            in: resolvedKeybindings
          ))
      }

      HStack(spacing: 4) {
        Button {
          arrangeCardsWithFit()
        } label: {
          Image(systemName: "rectangle.3.group")
            .font(.body)
            .accessibilityLabel("Arrange")
        }
        .buttonStyle(.bordered)
        .help(
          AppShortcuts.helpText(
            title: "Arrange cards preserving sizes",
            commandID: AppShortcuts.CommandID.arrangeCanvasCards,
            in: resolvedKeybindings
          ))

        Button {
          organizeCardsWithFit()
        } label: {
          Image(systemName: "square.grid.2x2")
            .font(.body)
            .accessibilityLabel("Organize")
        }
        .buttonStyle(.bordered)
        .help(
          AppShortcuts.helpText(
            title: "Organize cards in a uniform grid",
            commandID: AppShortcuts.CommandID.organizeCanvasCards,
            in: resolvedKeybindings
          ))

        Button {
          tileCardsWithFit()
        } label: {
          Image(systemName: "rectangle.split.2x1")
            .font(.body)
            .accessibilityLabel("Tile")
        }
        .buttonStyle(.bordered)
        .help(
          AppShortcuts.helpText(
            title: "Tile cards to fill the canvas",
            commandID: AppShortcuts.CommandID.tileCanvasCards,
            in: resolvedKeybindings
          ))
      }
    }
    .padding()
  }

  func zIndex(for tabID: TerminalTabID, cardKey: String) -> Double {
    let base = layoutStore.zIndex(for: cardKey)
    if selectionState.primaryTabID == tabID {
      return 10_000 + base
    }
    if selectionState.selectedTabIDs.contains(tabID) {
      return 9_000 + base
    }
    return base
  }

  // MARK: - Drag

  func commitDrag(for cardKey: String, translation: CGSize) {
    if var layout = layoutStore.cardLayouts[cardKey] {
      layout.position.x += translation.width
      layout.position.y += translation.height
      layoutStore.cardLayouts[cardKey] = layout
    }
  }

  // MARK: - Resize

  func commitResize(for tabID: TerminalTabID, cardKey: String, surfaces: [GhosttySurfaceView]) {
    guard activeResize[tabID] != nil else { return }
    if var layout = layoutStore.cardLayouts[cardKey] {
      let resized = resizedFrame(for: tabID, baseLayout: layout)
      // Settle the card into its committed size with a short animation (cards
      // no longer animate size on their own; the canvas drives it explicitly).
      withAnimation(.easeInOut(duration: 0.2)) {
        layout.position = resized.center
        layout.size = resized.size
        layoutStore.cardLayouts[cardKey] = layout
      }
    }
    activeResize[tabID] = nil
    for surface in surfaces {
      surface.needsLayout = true
      surface.needsDisplay = true
    }
  }

  func selectAllCards() {
    // Scope to the active canvas so "Select All Cards" can't reach worktrees the
    // user isn't viewing — an unscoped selection fans broadcast commands out to
    // off-canvas worktrees (matches the scoped Escape/clear path).
    let activeStates = scopedActiveStates
    let allTabIDs = collectVisibleTabIDs(from: activeStates)
    guard allTabIDs.count > 1 else { return }
    mutateSelection(states: activeStates) { state in
      state.selectAll(allTabIDs)
    }
  }

  // MARK: - Selection and Focus

  func focusSingleCard(
    _ tabID: TerminalTabID,
    states: [WorktreeTerminalState]
  ) {
    layoutStore.moveToFront(tabID.rawValue.uuidString)
    mutateSelection(states: states) { state in
      state.focusSingle(tabID)
    }
  }

  // MARK: - Spatial Navigation

  @discardableResult
  func navigateCard(_ direction: CanvasNavigationDirection) -> Bool {
    guard expandedTabID == nil else { return false }
    let activeStates = terminalManager.activeWorktreeStates
    guard let currentTabID = selectionState.primaryTabID else {
      let allTabIDs = collectVisibleTabIDs(from: activeStates)
      if let first = allTabIDs.first {
        focusSingleCard(first, states: activeStates)
        scrollToRevealCard(first)
      }
      return !allTabIDs.isEmpty
    }

    let entries = cardEntries(from: activeStates)
    let currentKey = currentTabID.rawValue.uuidString
    guard
      let targetKey = CanvasSpatialNavigation.nearest(
        from: currentKey,
        direction: direction,
        cards: entries
      )
    else {
      return true
    }

    let allTabIDs = collectVisibleTabIDs(from: activeStates)
    guard let targetTabID = allTabIDs.first(where: { $0.rawValue.uuidString == targetKey }) else {
      return true
    }

    focusSingleCard(targetTabID, states: activeStates)
    scrollToRevealCard(targetTabID)
    return true
  }

  private func scrollToRevealCard(_ tabID: TerminalTabID) {
    guard viewportSize.width > 0, viewportSize.height > 0 else { return }
    let cardKey = tabID.rawValue.uuidString
    guard let layout = layoutStore.cardLayouts[cardKey] else { return }

    let cardRect = screenRect(for: layout)
    let delta = CanvasViewportMath.revealDelta(
      for: cardRect,
      viewport: viewportSize,
      bottomReserve: bottomToolbarReserve,
      margin: 20
    )

    guard delta != .zero else { return }

    let target = CGSize(
      width: canvasOffset.width + delta.width,
      height: canvasOffset.height + delta.height
    )
    let start = CanvasViewportAnimator.Snapshot(offset: canvasOffset, scale: canvasScale)
    let end = CanvasViewportAnimator.Snapshot(offset: target, scale: canvasScale)
    viewportAnimator.animate(from: start, to: end) { [self] snapshot in
      canvasOffset = snapshot.offset
      lastCanvasOffset = snapshot.offset
    }
  }

  private func cardRect(for layout: CanvasCardLayout) -> CGRect {
    let width = layout.size.width
    let height = layout.size.height + titleBarHeight
    return CGRect(
      x: layout.position.x - width / 2,
      y: layout.position.y - height / 2,
      width: width,
      height: height
    )
  }

  private func screenRect(for layout: CanvasCardLayout) -> CGRect {
    let rect = cardRect(for: layout)
    return CGRect(
      x: rect.minX * canvasScale + canvasOffset.width,
      y: rect.minY * canvasScale + canvasOffset.height,
      width: rect.width * canvasScale,
      height: rect.height * canvasScale
    )
  }

  private func cardEntries(
    from states: [WorktreeTerminalState]
  ) -> [CanvasSpatialNavigation.CardEntry] {
    states.flatMap { state in
      state.tabManager.tabs.compactMap { tab -> CanvasSpatialNavigation.CardEntry? in
        guard state.surfaceView(for: tab.id) != nil else { return nil }
        let key = tab.id.rawValue.uuidString
        guard let layout = layoutStore.cardLayouts[key] else { return nil }
        return CanvasSpatialNavigation.CardEntry(id: key, center: layout.position)
      }
    }
  }

  // MARK: - Expand In Place

  var expandMetrics: CanvasExpandGeometry.Metrics {
    CanvasExpandGeometry.Metrics(
      padding: expandPadding,
      bottomReserve: bottomToolbarReserve,
      titleBarHeight: titleBarHeight,
      minSize: CGSize(width: minCardWidth, height: minCardHeight)
    )
  }

  /// Screen-space center for a fully expanded card: horizontally centered and
  /// within the toolbar-adjusted viewport. Independent of canvas pan/zoom.
  var expandedScreenCenter: CGPoint {
    CGPoint(x: viewportSize.width / 2, y: (viewportSize.height - bottomToolbarReserve) / 2)
  }

  /// A card's normal (non-expanded) on-screen frame, following the canvas
  /// pan/zoom and any in-progress resize. This is the `progress = 0` endpoint of
  /// the expand magic-move.
  func nonExpandedGeometry(
    for tabID: TerminalTabID,
    baseLayout: CanvasCardLayout
  ) -> CardScreenGeometry {
    let resized = resizedFrame(for: tabID, baseLayout: baseLayout)
    return CardScreenGeometry(
      size: resized.size,
      center: screenPosition(for: resized.center),
      scale: canvasScale
    )
  }

  /// The full-viewport expanded frame at scale 1 — the `progress = 1` endpoint.
  /// Independent of the canvas transform, so it covers the viewport regardless
  /// of the (frozen) background.
  func expandedGeometry() -> CardScreenGeometry {
    CardScreenGeometry(
      size: CanvasExpandGeometry.expandedSize(viewport: viewportSize, metrics: expandMetrics),
      center: expandedScreenCenter,
      scale: 1
    )
  }

  /// Toggle expand/restore for a card — used by the title-bar button and the
  /// title-bar double-click.
  func toggleExpand(_ tabID: TerminalTabID, states: [WorktreeTerminalState]) {
    if expandedTabID == tabID {
      collapseExpand()
    } else {
      expandCard(tabID, states: states)
    }
  }

  /// Toggle expand/restore for the focused (primary) card. Used by the keyboard
  /// shortcut and the command palette, which target whichever card is focused.
  func toggleExpandFocusedCard() {
    if expandedTabID != nil {
      collapseExpand()
    } else if let tabID = selectionState.primaryTabID {
      expandCard(tabID, states: terminalManager.activeWorktreeStates)
    }
  }
}

/// Applies the canvas background layer's lifecycle `.onAppear` / `.onChange`
/// handlers. Factored into a `ViewModifier` so the chain stays short enough for
/// the Swift type checker.
private struct CanvasLifecycleHandlers: ViewModifier {
  let allCardKeys: [String]
  let allTabIDs: [TerminalTabID]
  let focusRequest: CanvasFocusRequest?
  let onAppear: () -> Void
  let onCardKeysChanged: ([String]) -> Void
  let onTabIDsChanged: ([TerminalTabID], [TerminalTabID]) -> Void
  let onFocusRequestChanged: (CanvasFocusRequest?) -> Void

  func body(content: Content) -> some View {
    content
      .onAppear { onAppear() }
      .onChange(of: allCardKeys) { _, newKeys in onCardKeysChanged(newKeys) }
      .onChange(of: allTabIDs) { oldTabIDs, newTabIDs in onTabIDsChanged(oldTabIDs, newTabIDs) }
      .onChange(of: focusRequest) { _, newRequest in onFocusRequestChanged(newRequest) }
  }
}

/// Applies the canvas's scope-change relayout `.onChange` handlers. Lives in a
/// dedicated `ViewModifier` so `CanvasView.canvasBackgroundLayer`'s modifier
/// chain stays short enough for the Swift type checker.
private struct CanvasScopeChangeHandlers: ViewModifier {
  let scopedWorktreeID: Worktree.ID?
  let scopedWorktreeIDs: Set<Worktree.ID>?
  let scopedTabIDs: Set<TerminalTabID>?
  let focusGrowTabID: TerminalTabID?
  let canvasFocusedWorktreeID: Worktree.ID?
  let isScopedMode: Bool
  let onScopeRelayout: () -> Void
  let onFocusGrowChanged: () -> Void
  let onExternalFocus: (Worktree.ID?) -> Void

  func body(content: Content) -> some View {
    content
      .onChange(of: scopedWorktreeID) { _, _ in onScopeRelayout() }
      .onChange(of: scopedWorktreeIDs) { _, _ in onScopeRelayout() }
      .onChange(of: scopedTabIDs) { _, _ in onScopeRelayout() }
      .onChange(of: focusGrowTabID) { _, _ in onFocusGrowChanged() }
      .onChange(of: canvasFocusedWorktreeID) { _, newValue in onExternalFocus(newValue) }
  }
}
