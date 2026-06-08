import AppKit
import ComposableArchitecture
import Sharing
import SwiftUI

struct WorktreeDetailView: View {
  private struct ToolbarStateInput {
    let repositories: RepositoriesFeature.State
    let selectedWorktree: Worktree?
    let notificationGroups: [ToolbarNotificationRepositoryGroup]
    let unseenNotificationWorktreeCount: Int
    let openActionSelection: OpenWorktreeAction
    let openActionIsAutomatic: Bool
    let showExtras: Bool
    let runScriptEnabled: Bool
    let runScriptIsRunning: Bool
    let customCommands: [UserCustomCommand]
    let isUpdateAvailable: Bool
    let isUpdateReadyToInstall: Bool
    let availableUpdateVersion: String?
    let showRunButtonInToolbar: Bool
    let showDefaultEditorInToolbar: Bool
  }

  private struct CanvasToolbarState {
    let statusToast: RepositoriesFeature.StatusToast?
    let pullRequest: GithubPullRequest?
    let codeHost: CodeHost
    /// Code-host status fields for `actionTargetWorktree`, mirroring the worktree
    /// toolbar's `ToolbarStatusView` inputs so canvas mode shows the same no-PR
    /// badge (diff size, ahead/behind, push state). `supportsCodeHost` gates the
    /// badge; the metrics are nil/empty when no worktree is the action target.
    let supportsCodeHost: Bool
    let branchName: String
    let repositoryName: String
    let addedLines: Int?
    let removedLines: Int?
    let aheadCount: Int?
    let behindCount: Int?
    let isPushed: Bool?
    let notificationGroups: [ToolbarNotificationRepositoryGroup]
    let unseenNotificationWorktreeCount: Int
    let runScriptEnabled: Bool
    let runScriptIsRunning: Bool
    let customCommands: [UserCustomCommand]
    let isUpdateAvailable: Bool
    let isUpdateReadyToInstall: Bool
    let availableUpdateVersion: String?
    let showRunButtonInToolbar: Bool
  }

  /// Resolved targets + visibility gates for the worktree- and repository-canvas
  /// toolbar buttons. Both gates use a `> 1` threshold (single source of truth
  /// here so call sites can't drift):
  /// - `paneCount` counts panes in the target worktree; the `> 1` gate hides the
  ///   worktree-canvas button when canvas would render the same single pane.
  /// - `activeWorktreeCount` counts worktrees in the target repo with at least
  ///   one open pane; the `> 1` gate hides the repo-canvas button when it would
  ///   render the same single tab the worktree-canvas button does.
  private struct CanvasButtonState {
    let worktreeTarget: WorktreeTarget?
    let repositoryTarget: RepositoryTarget?

    /// `id`: the worktree the buttons will target. `paneCount`: total panes in
    /// that worktree — drives the worktree-canvas visibility gate (`> 1`).
    struct WorktreeTarget: Equatable {
      let id: Worktree.ID
      let paneCount: Int
    }

    /// `id`: the repository the repo-canvas button will target.
    /// `activeWorktreeCount`: worktrees with ≥1 open pane — drives the
    /// repo-canvas visibility gate (`> 1`).
    struct RepositoryTarget: Equatable {
      let id: Repository.ID
      let activeWorktreeCount: Int
    }

    /// True when the worktree-canvas button should be visible. Single source of
    /// truth for the `> 1` threshold so call sites can't drift.
    var showsWorktreeCanvasButton: Bool { (worktreeTarget?.paneCount ?? 0) > 1 }

    /// True when the repository-canvas button should be visible. Single source
    /// of truth for the `> 1` threshold.
    var showsRepositoryCanvasButton: Bool { (repositoryTarget?.activeWorktreeCount ?? 0) > 1 }
  }

  @Bindable var store: StoreOf<AppFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  /// Drive the chrome (nav + toolbar) tint for Normal and Canvas modes.
  @Shared(.repositoryAppearances) private var repositoryAppearances
  @Shared(.settingsFile) private var settingsFile
  /// True while a Canvas card is expanded in place, so the otherwise-transparent
  /// Canvas toolbar gets a matching material scrim instead of showing through.
  @State private var isCanvasCardExpanded = false

  var body: some View {
    detailBody(state: store.state)
  }

  private func detailBody(state: AppFeature.State) -> some View {
    let repositories = state.repositories
    let selectedRow = repositories.selectedRow(for: repositories.selectedWorktreeID)
    let selectedWorktree = repositories.worktree(for: repositories.selectedWorktreeID)
    let selectedTerminalWorktree = repositories.selectedTerminalWorktree
    let canvasFocusedTerminalWorktree = canvasFocusedTerminalWorktree(repositories: repositories)
    let actionTargetWorktree = selectedTerminalWorktree ?? canvasFocusedTerminalWorktree
    let selectedWorktreeSummaries = selectedWorktreeSummaries(from: repositories)
    let showsMultiSelectionSummary = shouldShowMultiSelectionSummary(
      repositories: repositories,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    )
    let loadingInfo = loadingInfo(
      for: selectedRow,
      selectedWorktreeID: repositories.selectedWorktreeID,
      repositories: repositories
    )
    let hasActiveTerminalTarget =
      actionTargetWorktree != nil
      && loadingInfo == nil
      && !showsMultiSelectionSummary
    let runScriptEnabled = hasActiveTerminalTarget
    let runScriptIsRunning = actionTargetWorktree.flatMap { state.runScriptStatusByWorktreeID[$0.id] } == true
    let customCommands = state.selectedCustomCommands
    let notificationGroups = repositories.toolbarNotificationGroups(
      terminalManager: terminalManager,
      customTitles: repositories.repositoryCustomTitles
    )
    let unseenNotificationWorktreeCount = notificationGroups.reduce(0) { count, repository in
      count + repository.unseenWorktreeCount
    }
    let content = detailContent(
      repositories: repositories,
      loadingInfo: loadingInfo,
      selectedWorktree: selectedWorktree,
      selectedTerminalWorktree: selectedTerminalWorktree,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    )
    .navigationTitle(detailNavigationTitle(repositories: repositories))
    .toolbar(removing: repositories.isShowingCanvas ? nil : .title)
    .toolbar {
      if repositories.isShowingCanvas {
        canvasToolbar(
          focusedWorktree: canvasFocusedTerminalWorktree,
          state: state,
          repositories: repositories,
          actionTargetWorktree: actionTargetWorktree,
          notificationGroups: notificationGroups,
          unseenNotificationWorktreeCount: unseenNotificationWorktreeCount,
          runScriptEnabled: runScriptEnabled,
          runScriptIsRunning: runScriptIsRunning,
          customCommands: customCommands
        )
      } else if hasActiveTerminalTarget,
        let toolbarState = toolbarState(
          input: ToolbarStateInput(
            repositories: repositories,
            selectedWorktree: selectedWorktree,
            notificationGroups: notificationGroups,
            unseenNotificationWorktreeCount: unseenNotificationWorktreeCount,
            openActionSelection: state.openActionSelection,
            openActionIsAutomatic: state.openActionIsAutomatic,
            showExtras: commandKeyObserver.isPressed,
            runScriptEnabled: runScriptEnabled,
            runScriptIsRunning: runScriptIsRunning,
            customCommands: customCommands,
            isUpdateAvailable: state.updates.isUpdateAvailable,
            isUpdateReadyToInstall: state.updates.isUpdateReadyToInstall,
            availableUpdateVersion: state.updates.availableVersion,
            showRunButtonInToolbar: settingsFile.global.showRunButtonInToolbar,
            showDefaultEditorInToolbar: settingsFile.global.showDefaultEditorInToolbar
          )
        )
      {
        worktreeToolbarContent(
          toolbarState: toolbarState,
          repositories: repositories,
          selectedWorktree: selectedWorktree,
          actionTargetWorktree: actionTargetWorktree,
          notificationGroups: notificationGroups
        )
      }
    }
    .windowToolbarChromeBackground(
      toolbarChromeFill(repositories: repositories),
      forceMaterialScrim: repositories.isShowingCanvas && isCanvasCardExpanded
    )
    let actions = makeFocusedActions(
      repositories: repositories,
      hasActiveWorktree: hasActiveTerminalTarget && !isCanvasBroadcasting(),
      runScriptEnabled: runScriptEnabled,
      runScriptIsRunning: runScriptIsRunning
    )
    let actionToken = WorktreeActionContext(
      selectedWorktreeID: selectedTerminalWorktree?.id,
      isShowingCanvas: repositories.isShowingCanvas,
      canvasFocusedWorktreeID: repositories.isShowingCanvas ? terminalManager.canvasFocusedWorktreeID : nil
    )
    return applyFocusedActions(content: content, actions: actions, token: actionToken)
  }

  @ToolbarContentBuilder
  private func worktreeToolbarContent(
    toolbarState: WorktreeToolbarState,
    repositories: RepositoriesFeature.State,
    selectedWorktree: Worktree?,
    actionTargetWorktree: Worktree?,
    notificationGroups: [ToolbarNotificationRepositoryGroup]
  ) -> some ToolbarContent {
    canvasButtonGroup(
      repositories: repositories,
      actionTargetWorktree: actionTargetWorktree
    )
    popoverButtonsGroup()
    WorktreeToolbarContent(
      toolbarState: toolbarState,
      onRenameBranch: { newBranch in
        guard let selectedWorktree else { return }
        store.send(.repositories(.requestRenameBranch(selectedWorktree.id, newBranch)))
      },
      externalRenamePrompt: repositories.pendingRenameBranchRequest
        .flatMap { request in
          request.worktreeID == selectedWorktree?.id ? request : nil
        },
      onConsumeExternalRenamePrompt: { requestID in
        store.send(.repositories(.consumePendingRenameBranchRequest(requestID)))
      },
      onOpenWorktree: { action in
        store.send(.openWorktree(action))
      },
      onOpenActionSelectionChanged: { action in
        store.send(.openActionSelectionChanged(action))
      },
      onResetOpenActionToAutomatic: {
        store.send(.openActionResetToAutomatic)
      },
      onCopyPath: {
        guard let actionTargetWorktree else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(actionTargetWorktree.workingDirectory.path, forType: .string)
      },
      onSelectNotification: selectToolbarNotification,
      onDismissAllNotifications: { dismissAllToolbarNotifications(in: notificationGroups) },
      onRunScript: { store.send(.runScript) },
      onStopRunScript: { store.send(.stopRunScript) },
      onRunCustomCommand: { index in
        store.send(.runCustomCommand(index))
      },
      onActivateUpdateButton: { store.send(.updates(.activateUpdateButton)) },
      onCodeHostAction: { action in
        guard let selectedWorktree else { return }
        store.send(.repositories(.githubIntegration(.pullRequestAction(selectedWorktree.id, action))))
      },
      onShowDiff: {
        guard let selectedWorktree else { return }
        store.send(.repositories(.delegate(.showDiff(selectedWorktree.id))))
      }
    )
  }

  /// The worktree / repository / overall / active-agents canvas toggle buttons,
  /// grouped in one trailing `ToolbarItemGroup`. Each button has its own visibility gate so
  /// the group is emitted only when at least one button is shown. Toggle targets
  /// are resolved at PRESS time from `store.state` (not toolbar-render time): the
  /// `.keyboardShortcut` on each button routes through this closure even after
  /// the sidebar selection has changed, so capturing a render-time ID would open
  /// canvas for a stale worktree.
  @ToolbarContentBuilder
  private func canvasButtonGroup(
    repositories: RepositoriesFeature.State,
    actionTargetWorktree: Worktree?
  ) -> some ToolbarContent {
    let canvasButton = canvasButtonState(
      repositories: repositories,
      selectedTerminalWorktree: actionTargetWorktree
    )
    let showsActiveAgentsCanvasButton =
      !repositories.activeAgents.entries.isEmpty || repositories.isShowingActiveAgentsCanvas
    // Overall canvas: available whenever there's at least one worktree to render
    // (the same gate `toggleCanvas` uses to enter) or while it's already showing
    // so the toggle can exit. Replaces the former sidebar "Canvas" segment.
    let showsOverallCanvasButton =
      !repositories.orderedWorktreeRows().isEmpty || repositories.isShowingGlobalCanvas
    if canvasButton.showsWorktreeCanvasButton
      || canvasButton.showsRepositoryCanvasButton
      || showsOverallCanvasButton
      || showsActiveAgentsCanvasButton
    {
      ToolbarItemGroup(placement: .primaryAction) {
        if canvasButton.showsWorktreeCanvasButton {
          WorktreeCanvasToolbarButton(
            isActive: repositories.isShowingCanvas
              && repositories.scopedCanvasWorktreeID == canvasButton.worktreeTarget?.id,
            onToggle: {
              guard let id = canvasButtonTargetWorktreeID() else { return }
              store.send(.repositories(.toggleWorktreeCanvas(id)))
            }
          )
        }
        if canvasButton.showsRepositoryCanvasButton {
          RepositoryCanvasToolbarButton(
            isActive: repositories.isShowingCanvas
              && repositories.scopedCanvasRepositoryID == canvasButton.repositoryTarget?.id,
            onToggle: {
              guard let worktreeID = canvasButtonTargetWorktreeID(),
                let repoID = store.state.repositories.repositoryID(containing: worktreeID)
              else { return }
              store.send(.repositories(.toggleRepositoryCanvas(repoID)))
            }
          )
        }
        if showsOverallCanvasButton {
          OverallCanvasToolbarButton(
            isActive: repositories.isShowingGlobalCanvas,
            onToggle: { store.send(.repositories(.toggleCanvas)) }
          )
        }
        if showsActiveAgentsCanvasButton {
          ActiveAgentsCanvasToolbarButton(
            isActive: repositories.isShowingActiveAgentsCanvas,
            onToggle: { store.send(.repositories(.toggleActiveAgentsCanvas)) }
          )
        }
      }
    }
  }

  /// Worktree the canvas toggle buttons act on: the focused card first (the
  /// active-agents canvas has no sidebar selection), else the sidebar selection.
  /// Press-time resolution (reads `store.state`), matching the buttons' contract.
  private func canvasButtonTargetWorktreeID() -> Worktree.ID? {
    terminalManager.canvasFocusedWorktreeID ?? store.state.repositories.selectedTerminalWorktree?.id
  }

  /// Resolves the worktree / repository targets and their pane counts that drive
  /// the canvas button visibility gates and active-state checks. Mirrors the
  /// canvas-seed resolution: in a scoped repo canvas the target worktree comes
  /// from the focused card or the pre-canvas selection; in the active-agents
  /// canvas it follows the focused card; otherwise it's the selected terminal
  /// worktree.
  private func canvasButtonState(
    repositories: RepositoriesFeature.State,
    selectedTerminalWorktree: Worktree?
  ) -> CanvasButtonState {
    let worktreeID: Worktree.ID? = {
      if let scopedRepoID = repositories.scopedCanvasRepositoryID {
        let scopedWorktreeIDs: Set<Worktree.ID> =
          repositories.repositories[id: scopedRepoID]
          .map { Set($0.worktrees.map(\.id)) } ?? []
        return [
          terminalManager.canvasFocusedWorktreeID,
          repositories.preCanvasTerminalTargetID,
          repositories.preCanvasWorktreeID,
        ]
        .compactMap { $0 }
        .first(where: scopedWorktreeIDs.contains)
          ?? repositories.repositories[id: scopedRepoID]?.worktrees.first?.id
      }
      if repositories.isShowingActiveAgentsCanvas {
        return terminalManager.canvasFocusedWorktreeID
      }
      return selectedTerminalWorktree?.id
    }()
    let worktreeTarget: CanvasButtonState.WorktreeTarget? = worktreeID.map { id in
      let paneCount =
        terminalManager.activeWorktreeStates
        .first(where: { $0.worktreeID == id })?
        .totalPaneCount ?? 0
      return CanvasButtonState.WorktreeTarget(id: id, paneCount: paneCount)
    }
    let repositoryID =
      repositories.scopedCanvasRepositoryID
      ?? worktreeID.flatMap(repositories.repositoryID(containing:))
    let repositoryTarget: CanvasButtonState.RepositoryTarget? = repositoryID.flatMap {
      repoID -> CanvasButtonState.RepositoryTarget? in
      guard let worktreeIDs = repositories.repositories[id: repoID]?.worktrees.map(\.id)
      else { return nil }
      let worktreeIDSet = Set(worktreeIDs)
      let activeCount = terminalManager.activeWorktreeStates
        .filter { worktreeIDSet.contains($0.worktreeID) && $0.totalPaneCount > 0 }
        .count
      return CanvasButtonState.RepositoryTarget(id: repoID, activeWorktreeCount: activeCount)
    }
    return CanvasButtonState(worktreeTarget: worktreeTarget, repositoryTarget: repositoryTarget)
  }

  /// The PR matched to a worktree's branch, or nil when the worktree's PR head
  /// ref doesn't match its branch. Ported from main so the canvas toolbar's status
  /// view can show the same PR the worktree toolbar does.
  private func matchedPullRequest(
    for worktree: Worktree?,
    repositories: RepositoriesFeature.State
  ) -> GithubPullRequest? {
    guard let worktree,
      let pullRequest = repositories.worktreeInfo(for: worktree.id)?.pullRequest
    else {
      return nil
    }
    guard pullRequest.headRefName == nil || pullRequest.headRefName == worktree.name else {
      return nil
    }
    return pullRequest
  }

  @ToolbarContentBuilder
  private func canvasToolbarContent(
    state: CanvasToolbarState,
    repositories: RepositoriesFeature.State,
    actionTargetWorktree: Worktree?
  ) -> some ToolbarContent {
    // Full status view (toast + PR + code-host badge) in the canvas toolbar's
    // center, matching the worktree toolbar so canvas mode shows the same status —
    // including app toasts like quick-send's "Message sent". The code-host
    // actions target `actionTargetWorktree`; they no-op when there's no target
    // (which is also when `supportsCodeHost` is false, so the button is hidden).
    ToolbarItem(placement: .principal) {
      ToolbarStatusView(
        toast: state.statusToast,
        pullRequest: state.pullRequest,
        codeHost: state.codeHost,
        supportsCodeHost: state.supportsCodeHost,
        branchName: state.branchName,
        repositoryName: state.repositoryName,
        addedLines: state.addedLines,
        removedLines: state.removedLines,
        aheadCount: state.aheadCount,
        behindCount: state.behindCount,
        isPushed: state.isPushed,
        onCodeHostAction: { action in
          guard let id = actionTargetWorktree?.id else { return }
          store.send(.repositories(.githubIntegration(.pullRequestAction(id, action))))
        },
        onShowDiff: {
          guard let id = actionTargetWorktree?.id else { return }
          store.send(.repositories(.delegate(.showDiff(id))))
        }
      )
      .padding(.horizontal)
    }
    // Keep the canvas toggles available while already in canvas so the user can
    // switch between scopes (worktree ↔ repo ↔ active-agents) or exit back to a
    // tab without leaving the board first.
    canvasButtonGroup(
      repositories: repositories,
      actionTargetWorktree: actionTargetWorktree
    )
    popoverButtonsGroup()
    let broadcastTargets = canvasSelectedWorktreeIDs()
    let isBroadcasting = broadcastTargets.count > 1
    ToolbarItemGroup(placement: .primaryAction) {
      ToolbarNotificationsPopoverButton(
        groups: state.notificationGroups,
        unseenWorktreeCount: state.unseenNotificationWorktreeCount,
        onSelectNotification: selectToolbarNotification,
        onDismissAll: { dismissAllToolbarNotifications(in: state.notificationGroups) }
      )
      if state.isUpdateAvailable {
        ToolbarUpdateButton(
          availableVersion: state.availableUpdateVersion,
          isReadyToInstall: state.isUpdateReadyToInstall
        ) {
          store.send(.updates(.activateUpdateButton))
        }
      }
    }

    let showRunButton =
      state.showRunButtonInToolbar
      && (state.runScriptIsRunning || state.runScriptEnabled)
    let inlineCommands = Array(state.customCommands.enumerated().prefix(3))
    let overflowCommands = Array(state.customCommands.enumerated().dropFirst(3))
    // A fixed separator splits the Run + Custom Command cluster from the
    // notification group, mirroring the Normal toolbar.
    //
    // INTENTIONAL DIVERGENCE FROM THE NORMAL TOOLBAR: the whole cluster is a
    // single `ToolbarItem` (an HStack) here, whereas `commandToolbarItems`
    // (Normal mode) lays the buttons out as separate items / a
    // `ToolbarItemGroup`. The reason is how each mode updates NSToolbar (which
    // SwiftUI's `.toolbar` bridges to):
    //   - Normal: switching worktree swaps the whole detail view, so NSToolbar
    //     is rebuilt wholesale — no per-item diff, no animation.
    //   - Canvas: `CanvasView` stays mounted across card switches; only the
    //     toolbar items change. With a multi-item structure NSToolbar performs
    //     an incremental insert/remove with its own animation (which SwiftUI
    //     transactions can't suppress), briefly overflowing the toolbar — the
    //     visible "jump" when switching between cards with different command
    //     counts.
    // Collapsing the cluster into one item keeps NSToolbar's item set stable,
    // so a command-count change is just an internal HStack relayout. Do NOT
    // "unify" this back into a `ToolbarItemGroup` to match Normal — that
    // reintroduces the jump.
    if !isBroadcasting && (showRunButton || !state.customCommands.isEmpty) {
      ToolbarSpacer(.fixed)
      ToolbarItem(placement: .primaryAction) {
        // `spacing: 0` keeps the cluster as tight as the Normal toolbar's
        // ToolbarItemGroup (whose buttons sit nearly flush on macOS 26); the
        // buttons' own internal padding provides the visible gap.
        HStack(spacing: 0) {
          if showRunButton {
            RunScriptToolbarButton(
              isRunning: state.runScriptIsRunning,
              isEnabled: state.runScriptEnabled,
              runHelpText: AppShortcuts.helpText(
                title: "Run Script",
                commandID: AppShortcuts.CommandID.runScript,
                in: store.resolvedKeybindings
              ),
              stopHelpText: AppShortcuts.helpText(
                title: "Stop Script",
                commandID: AppShortcuts.CommandID.stopScript,
                in: store.resolvedKeybindings
              ),
              runShortcut: store.resolvedKeybindings.display(for: AppShortcuts.CommandID.runScript),
              stopShortcut: store.resolvedKeybindings.display(for: AppShortcuts.CommandID.stopScript),
              runAction: { store.send(.runScript) },
              stopAction: { store.send(.stopRunScript) }
            )
          }
          ForEach(inlineCommands, id: \.element.id) { index, command in
            UserCustomCommandToolbarButton(
              title: command.resolvedTitle,
              systemImage: command.resolvedSystemImage,
              shortcut: store.resolvedKeybindings.display(
                for: LegacyCustomCommandShortcutMigration.customCommandBindingID(for: command.id)
              ),
              isEnabled: command.hasRunnableCommand,
              action: {
                store.send(.runCustomCommand(index))
              }
            )
          }
          if !overflowCommands.isEmpty {
            CustomCommandOverflowButton(
              entries: overflowCommands.map {
                (index: $0.offset, command: $0.element)
              },
              shortcutDisplay: { command in
                store.resolvedKeybindings.display(
                  for: LegacyCustomCommandShortcutMigration.customCommandBindingID(for: command.id)
                )
              },
              onRunCustomCommand: { index in
                store.send(.runCustomCommand(index))
              }
            )
          }
        }
      }
    }
    if isBroadcasting {
      broadcastCommandsToolbar(
        globalCommands: settingsFile.global.customCommands,
        targets: broadcastTargets
      )
    }
  }

  /// Routes the canvas toolbar: a single focused worktree (not broadcasting) gets
  /// its full per-card toolbar; otherwise the slim / broadcast command cluster.
  @ToolbarContentBuilder
  private func canvasToolbar(
    focusedWorktree: Worktree?,
    state: AppFeature.State,
    repositories: RepositoriesFeature.State,
    actionTargetWorktree: Worktree?,
    notificationGroups: [ToolbarNotificationRepositoryGroup],
    unseenNotificationWorktreeCount: Int,
    runScriptEnabled: Bool,
    runScriptIsRunning: Bool,
    customCommands: [UserCustomCommand]
  ) -> some ToolbarContent {
    if !isCanvasBroadcasting(), let focusedWorktree {
      focusedCardCanvasToolbar(
        focusedWorktree: focusedWorktree,
        state: state,
        repositories: repositories,
        actionTargetWorktree: actionTargetWorktree,
        notificationGroups: notificationGroups,
        unseenNotificationWorktreeCount: unseenNotificationWorktreeCount
      )
    } else {
      // Resolve the action-target worktree's code-host status fields, mirroring
      // `toolbarState(input:)` so canvas mode's status view matches the worktree
      // toolbar (nil/empty when no worktree is the action target).
      let codeHostRepository = actionTargetWorktree.flatMap { worktree in
        repositories.repositoryID(containing: worktree.id)
          .flatMap { repositories.repositories[id: $0] }
      }
      let branchInfo = actionTargetWorktree.flatMap { repositories.worktreeInfo(for: $0.id) }
      canvasToolbarContent(
        state: CanvasToolbarState(
          statusToast: repositories.statusToast,
          pullRequest: matchedPullRequest(for: actionTargetWorktree, repositories: repositories),
          codeHost: repositories.codeHost(forWorktreeID: actionTargetWorktree?.id),
          supportsCodeHost: codeHostRepository?.capabilities.supportsCodeHost ?? false,
          branchName: actionTargetWorktree?.name ?? "",
          repositoryName: codeHostRepository?.name ?? "",
          addedLines: branchInfo?.addedLines,
          removedLines: branchInfo?.removedLines,
          aheadCount: branchInfo?.aheadBehind?.ahead,
          behindCount: branchInfo?.aheadBehind?.behind,
          isPushed: branchInfo?.isPushed,
          notificationGroups: notificationGroups,
          unseenNotificationWorktreeCount: unseenNotificationWorktreeCount,
          runScriptEnabled: runScriptEnabled,
          runScriptIsRunning: runScriptIsRunning,
          customCommands: customCommands,
          isUpdateAvailable: state.updates.isUpdateAvailable,
          isUpdateReadyToInstall: state.updates.isUpdateReadyToInstall,
          availableUpdateVersion: state.updates.availableVersion,
          showRunButtonInToolbar: settingsFile.global.showRunButtonInToolbar
        ),
        repositories: repositories,
        actionTargetWorktree: actionTargetWorktree
      )
    }
  }

  /// Full per-card toolbar shown when a SINGLE card is focused in a repository or
  /// active-agents canvas (not broadcasting). Renders `WorktreeToolbarContent`
  /// synthesized from the focused card — its own repo's effective commands,
  /// Open-In/editor-picker, branch rename, PR/code-host — routed through the
  /// explicit-target action variants so it acts on the focused card, not the
  /// (absent) sidebar selection. Mirrors `worktreeToolbarContent`'s structure
  /// (canvas buttons + popovers + `WorktreeToolbarContent`).
  @ToolbarContentBuilder
  private func focusedCardCanvasToolbar(
    focusedWorktree: Worktree,
    state: AppFeature.State,
    repositories: RepositoriesFeature.State,
    actionTargetWorktree: Worktree?,
    notificationGroups: [ToolbarNotificationRepositoryGroup],
    unseenNotificationWorktreeCount: Int
  ) -> some ToolbarContent {
    canvasButtonGroup(repositories: repositories, actionTargetWorktree: actionTargetWorktree)
    popoverButtonsGroup()
    let rootURL = focusedWorktree.repositoryRootURL
    @Shared(.repositorySettings(rootURL)) var focusedRepoSettings
    @Shared(.userRepositorySettings(rootURL)) var focusedUserSettings
    let focusedCommands = EffectiveCommandsResolver.resolve(
      globalCommands: state.settings.globalCommands.commands,
      perRepoCommands: focusedUserSettings.customCommands
    )
    let focusedOpenAction = OpenWorktreeAction.fromSettingsID(
      focusedRepoSettings.openActionID,
      defaultEditorID: state.settings.defaultEditorID
    )
    if let synthState = toolbarState(
      input: ToolbarStateInput(
        repositories: repositories,
        selectedWorktree: focusedWorktree,
        notificationGroups: notificationGroups,
        unseenNotificationWorktreeCount: unseenNotificationWorktreeCount,
        openActionSelection: focusedOpenAction,
        openActionIsAutomatic: focusedRepoSettings.openActionID == OpenWorktreeAction.automaticSettingsID,
        showExtras: commandKeyObserver.isPressed,
        runScriptEnabled: true,
        runScriptIsRunning: state.runScriptStatusByWorktreeID[focusedWorktree.id] == true,
        customCommands: focusedCommands,
        isUpdateAvailable: state.updates.isUpdateAvailable,
        isUpdateReadyToInstall: state.updates.isUpdateReadyToInstall,
        availableUpdateVersion: state.updates.availableVersion,
        showRunButtonInToolbar: settingsFile.global.showRunButtonInToolbar,
        showDefaultEditorInToolbar: settingsFile.global.showDefaultEditorInToolbar
      )
    ) {
      WorktreeToolbarContent(
        toolbarState: synthState,
        onRenameBranch: { newBranch in
          store.send(.repositories(.requestRenameBranch(focusedWorktree.id, newBranch)))
        },
        externalRenamePrompt: repositories.pendingRenameBranchRequest.flatMap {
          $0.worktreeID == focusedWorktree.id ? $0 : nil
        },
        onConsumeExternalRenamePrompt: { requestID in
          store.send(.repositories(.consumePendingRenameBranchRequest(requestID)))
        },
        onOpenWorktree: { action in
          store.send(.openWorktreeForWorktree(action, focusedWorktree.id))
        },
        onOpenActionSelectionChanged: { action in
          store.send(.openActionSelectionChangedForWorktree(action, focusedWorktree.id))
        },
        onResetOpenActionToAutomatic: {
          store.send(.openActionResetToAutomaticForWorktree(focusedWorktree.id))
        },
        onCopyPath: {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(focusedWorktree.workingDirectory.path, forType: .string)
        },
        onSelectNotification: selectToolbarNotification,
        onDismissAllNotifications: { dismissAllToolbarNotifications(in: notificationGroups) },
        onRunScript: { store.send(.runScript) },
        onStopRunScript: { store.send(.stopRunScript) },
        onRunCustomCommand: { index in
          guard focusedCommands.indices.contains(index) else { return }
          store.send(.runCustomCommandOnWorktrees(focusedCommands[index], [focusedWorktree.id]))
        },
        onActivateUpdateButton: { store.send(.updates(.activateUpdateButton)) },
        onCodeHostAction: { action in
          store.send(.repositories(.githubIntegration(.pullRequestAction(focusedWorktree.id, action))))
        },
        onShowDiff: {
          store.send(.repositories(.delegate(.showDiff(focusedWorktree.id))))
        }
      )
    }
  }

  private func toolbarState(input: ToolbarStateInput) -> WorktreeToolbarState? {
    guard
      let title = DetailToolbarTitle.forSelection(
        worktree: input.selectedWorktree,
        repository: input.repositories.selectedRepository
      )
    else {
      return nil
    }
    let pullRequest = input.selectedWorktree.flatMap { input.repositories.worktreeInfo(for: $0.id)?.pullRequest }
    let matchesBranch =
      if let selectedWorktree = input.selectedWorktree, let pullRequest {
        pullRequest.headRefName == nil || pullRequest.headRefName == selectedWorktree.name
      } else {
        false
      }
    let codeHostRepository = input.selectedWorktree.flatMap { worktree in
      input.repositories.repositoryID(containing: worktree.id)
        .flatMap { input.repositories.repositories[id: $0] }
    }
    let worktreeBranchInfo = input.selectedWorktree.flatMap { input.repositories.worktreeInfo(for: $0.id) }
    return WorktreeToolbarState(
      title: title,
      statusToast: input.repositories.statusToast,
      pullRequest: matchesBranch ? pullRequest : nil,
      codeHost: input.repositories.codeHost(forWorktreeID: input.selectedWorktree?.id),
      supportsCodeHost: codeHostRepository?.capabilities.supportsCodeHost ?? false,
      branchName: input.selectedWorktree?.name ?? "",
      repositoryName: codeHostRepository?.name ?? "",
      addedLines: worktreeBranchInfo?.addedLines,
      removedLines: worktreeBranchInfo?.removedLines,
      aheadCount: worktreeBranchInfo?.aheadBehind?.ahead,
      behindCount: worktreeBranchInfo?.aheadBehind?.behind,
      isPushed: worktreeBranchInfo?.isPushed,
      notificationGroups: input.notificationGroups,
      unseenNotificationWorktreeCount: input.unseenNotificationWorktreeCount,
      openActionSelection: input.openActionSelection,
      openActionIsAutomatic: input.openActionIsAutomatic,
      showExtras: input.showExtras,
      runScriptEnabled: input.runScriptEnabled,
      runScriptIsRunning: input.runScriptIsRunning,
      customCommands: input.customCommands,
      isUpdateAvailable: input.isUpdateAvailable,
      isUpdateReadyToInstall: input.isUpdateReadyToInstall,
      availableUpdateVersion: input.availableUpdateVersion,
      showRunButtonInToolbar: input.showRunButtonInToolbar,
      showDefaultEditorInToolbar: input.showDefaultEditorInToolbar
    )
  }

  private func selectedWorktreeSummaries(
    from repositories: RepositoriesFeature.State
  ) -> [MultiSelectedWorktreeSummary] {
    repositories.sidebarSelectedWorktreeIDs
      .compactMap { worktreeID in
        repositories.selectedRow(for: worktreeID).map {
          MultiSelectedWorktreeSummary(
            id: $0.id,
            name: $0.name,
            repositoryName: repositories.repositoryName(for: $0.repositoryID)
          )
        }
      }
      .sorted { lhs, rhs in
        let lhsRepository = lhs.repositoryName ?? ""
        let rhsRepository = rhs.repositoryName ?? ""
        if lhsRepository == rhsRepository {
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhsRepository.localizedCaseInsensitiveCompare(rhsRepository) == .orderedAscending
      }
  }

  private func shouldShowMultiSelectionSummary(
    repositories: RepositoriesFeature.State,
    selectedWorktreeSummaries: [MultiSelectedWorktreeSummary]
  ) -> Bool {
    !repositories.isShowingArchivedWorktrees
      && !repositories.isShowingCanvas
      && selectedWorktreeSummaries.count > 1
  }

  private func canvasFocusedTerminalWorktree(repositories: RepositoriesFeature.State) -> Worktree? {
    guard repositories.isShowingCanvas,
      let worktreeID = terminalManager.canvasFocusedWorktreeID
    else {
      return nil
    }
    if let worktree = repositories.worktree(for: worktreeID) {
      return worktree
    }
    guard let repository = repositories.repositories[id: worktreeID],
      repository.capabilities.supportsRunnableFolderActions,
      !repository.capabilities.supportsWorktrees
    else {
      return nil
    }
    return Worktree(
      id: repository.id,
      name: repository.name,
      detail: repository.rootURL.path(percentEncoded: false),
      workingDirectory: repository.rootURL,
      repositoryRootURL: repository.rootURL
    )
  }

  @ViewBuilder
  private func detailContent(
    repositories: RepositoriesFeature.State,
    loadingInfo: WorktreeLoadingInfo?,
    selectedWorktree: Worktree?,
    selectedTerminalWorktree: Worktree?,
    selectedWorktreeSummaries: [MultiSelectedWorktreeSummary]
  ) -> some View {
    if repositories.isShowingCanvas {
      let scopedWorktreeID = repositories.scopedCanvasWorktreeID
      let scopedRepositoryID = repositories.scopedCanvasRepositoryID
      let scopedRepoWorktreeIDs: Set<Worktree.ID>? = scopedRepositoryID.flatMap { repoID in
        repositories.repositories[id: repoID].map { Set($0.worktrees.map(\.id)) }
      }
      // Active-agents canvas: restrict to the tabs that currently have a live
      // agent (derived from the deduped agent-entry list). nil for every other
      // canvas scope, leaving CanvasView's tab filter inert.
      let scopedTabIDs: Set<TerminalTabID>? =
        repositories.isShowingActiveAgentsCanvas
        ? Set(repositories.activeAgents.entries.map(\.tabID))
        : nil
      CanvasView(
        terminalManager: terminalManager,
        scopedWorktreeID: scopedWorktreeID,
        scopedWorktreeIDs: scopedRepoWorktreeIDs,
        scopedTabIDs: scopedTabIDs,
        sortKey: { state in
          let repoID = repositories.repositoryID(containing: state.worktreeID)
          let repoName = repoID.flatMap { repositories.repositoryName(for: $0) } ?? ""
          return (repoName, state.worktreeName)
        },
        repositoryCustomTitles: repositories.repositoryCustomTitles,
        focusRequest: repositories.pendingCanvasFocusRequest,
        commandRequest: repositories.pendingCanvasCommandRequest,
        onExitToTab: { explicitWorktreeID in
          if let explicitWorktreeID {
            // Expand-to-pane: jump to the card's worktree, exit canvas.
            store.send(.repositories(.exitCanvasToWorktree(explicitWorktreeID)))
          } else if let scopedWorktreeID {
            store.send(.repositories(.toggleWorktreeCanvas(scopedWorktreeID)))
          } else if let scopedRepositoryID {
            store.send(.repositories(.toggleRepositoryCanvas(scopedRepositoryID)))
          } else if repositories.isShowingActiveAgentsCanvas {
            store.send(.repositories(.toggleActiveAgentsCanvas))
          } else {
            store.send(.repositories(.toggleCanvas))
          }
        },
        onFocusedWorktreeChanged: { worktreeID in
          store.send(.canvasFocusedWorktreeChanged(worktreeID))
        },
        onFocusRequestConsumed: { requestID in
          store.send(.repositories(.consumeCanvasFocusRequest(requestID)))
        },
        onCommandConsumed: { requestID in
          store.send(.repositories(.consumeCanvasCommandRequest(requestID)))
        },
        onExpandedChange: { expanded in
          isCanvasCardExpanded = expanded
        }
      )
      // Canvas tints the nav (leading) only; the toolbar is left untinted so
      // floating cards don't read against a colored band. The card title
      // bars still carry their own per-repo color.
      .windowChromeTint(chromeFill(repositories: repositories, context: .canvas), edges: [.leading])
    } else if repositories.isShowingShelf {
      // Shelf manages its own chrome bands (and its always-repo-colored
      // spine) inside `ShelfView`, so no tint modifier is applied here.
      ShelfView(
        store: store.scope(state: \.repositories, action: \.repositories),
        terminalManager: terminalManager,
        createTab: { store.send(.newTerminal) }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      // Normal view mode (terminal, archived list, multi-selection, loading,
      // repository detail, empty): tint the toolbar (top) and nav (leading)
      // chrome, and pass the same fill into the terminal tab bar so its
      // background reads as part of the same tinted chrome.
      let normalFill = chromeFill(repositories: repositories, context: .normal)
      normalModeContent(
        repositories: repositories,
        loadingInfo: loadingInfo,
        selectedTerminalWorktree: selectedTerminalWorktree,
        selectedWorktreeSummaries: selectedWorktreeSummaries,
        barTint: normalFill
      )
      .windowChromeTint(normalFill, edges: [.top, .leading])
    }
  }

  @ViewBuilder
  private func normalModeContent(
    repositories: RepositoriesFeature.State,
    loadingInfo: WorktreeLoadingInfo?,
    selectedTerminalWorktree: Worktree?,
    selectedWorktreeSummaries: [MultiSelectedWorktreeSummary],
    barTint: WindowChromeTint.Fill?
  ) -> some View {
    if repositories.isShowingArchivedWorktrees {
      ArchivedWorktreesDetailView(
        store: store.scope(state: \.repositories, action: \.repositories)
      )
    } else if shouldShowMultiSelectionSummary(
      repositories: repositories,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    ) {
      MultiSelectedWorktreesDetailView(rows: selectedWorktreeSummaries)
    } else if let loadingInfo {
      WorktreeLoadingView(info: loadingInfo)
    } else if let selectedTerminalWorktree {
      let shouldRunSetupScript = repositories.pendingSetupScriptWorktreeIDs.contains(selectedTerminalWorktree.id)
      let shouldFocusTerminal = repositories.shouldFocusTerminal(for: selectedTerminalWorktree.id)
      WorktreeTerminalTabsView(
        worktree: selectedTerminalWorktree,
        manager: terminalManager,
        shouldRunSetupScript: shouldRunSetupScript,
        forceAutoFocus: shouldFocusTerminal,
        createTab: { store.send(.newTerminal) },
        barTint: barTint
      )
      .id(selectedTerminalWorktree.id)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        if shouldFocusTerminal {
          store.send(.repositories(.worktreeCreation(.consumeTerminalFocus(selectedTerminalWorktree.id))))
        }
      }
    } else if let selectedRepository = repositories.selectedRepository {
      RepositoryDetailView(
        repository: selectedRepository,
        customTitle: repositories.repositoryCustomTitles[selectedRepository.id]
      )
    } else {
      EmptyStateView(store: store.scope(state: \.repositories, action: \.repositories))
    }
  }

  /// The chrome region a tint is being resolved for.
  private enum ChromeContext {
    case normal
    case canvas
  }

  /// Resolves the chrome band fill for the current view mode, honoring the
  /// user's window tint setting. In `.repositoryColor` mode the band tracks
  /// the active repository — the selected worktree's repo in Normal, the
  /// focused card's repo in Canvas — falling back to a neutral surface when
  /// none is colored.
  private func chromeFill(
    repositories: RepositoriesFeature.State,
    context: ChromeContext
  ) -> WindowChromeTint.Fill? {
    let repositoryID: Repository.ID? =
      switch context {
      case .normal:
        repositories.repositoryID(for: repositories.selectedWorktreeID) ?? repositories.selectedRepositoryID
      case .canvas:
        repositories.repositoryID(for: terminalManager.canvasFocusedWorktreeID)
      }
    let repositoryColor = repositoryID.flatMap { repositoryAppearances[$0]?.color }
    return WindowChromeTint.fill(
      mode: settingsFile.global.windowTintMode,
      customColor: settingsFile.global.windowTintCustomColor.color,
      repositoryColor: repositoryColor
    )
  }

  /// Resolves the real window toolbar background. Unlike the content tint
  /// bands, this applies to the AppKit/SwiftUI toolbar surface itself, which
  /// remains visible when macOS changes the zoomed/fullscreen window layout.
  private func toolbarChromeFill(repositories: RepositoriesFeature.State) -> WindowChromeTint.Fill? {
    guard !repositories.isShowingCanvas else { return nil }
    return chromeFill(repositories: repositories, context: .normal)
  }

  private func applyFocusedActions<Content: View>(
    content: Content,
    actions: FocusedActions,
    token: WorktreeActionContext
  ) -> some View {
    content
      .focusedSceneValue(\.openSelectedWorktreeAction, actions.openSelectedWorktree.asFocusedAction(token: token))
      .focusedSceneValue(\.newTerminalAction, actions.newTerminal.asFocusedAction(token: token))
      .focusedSceneValue(\.closeTabAction, actions.closeTab.asFocusedAction(token: token))
      .focusedSceneValue(\.closeSurfaceAction, actions.closeSurface.asFocusedAction(token: token))
      .focusedSceneValue(\.resetFontSizeAction, actions.resetFontSize.asFocusedAction(token: token))
      .focusedSceneValue(\.increaseFontSizeAction, actions.increaseFontSize.asFocusedAction(token: token))
      .focusedSceneValue(\.decreaseFontSizeAction, actions.decreaseFontSize.asFocusedAction(token: token))
      .focusedSceneValue(\.startSearchAction, actions.startSearch.asFocusedAction(token: token))
      .focusedSceneValue(\.searchSelectionAction, actions.searchSelection.asFocusedAction(token: token))
      .focusedSceneValue(\.navigateSearchNextAction, actions.navigateSearchNext.asFocusedAction(token: token))
      .focusedSceneValue(
        \.navigateSearchPreviousAction, actions.navigateSearchPrevious.asFocusedAction(token: token)
      )
      .focusedSceneValue(\.endSearchAction, actions.endSearch.asFocusedAction(token: token))
      .focusedSceneValue(
        \.selectPreviousTerminalTabAction, actions.selectPreviousTerminalTab.asFocusedAction(token: token)
      )
      .focusedSceneValue(\.selectNextTerminalTabAction, actions.selectNextTerminalTab.asFocusedAction(token: token))
      .focusedSceneValue(
        \.selectPreviousTerminalPaneAction, actions.selectPreviousTerminalPane.asFocusedAction(token: token)
      )
      .focusedSceneValue(
        \.selectNextTerminalPaneAction, actions.selectNextTerminalPane.asFocusedAction(token: token)
      )
      .focusedSceneValue(\.selectTerminalPaneAboveAction, actions.selectTerminalPaneAbove.asFocusedAction(token: token))
      .focusedSceneValue(\.selectTerminalPaneBelowAction, actions.selectTerminalPaneBelow.asFocusedAction(token: token))
      .focusedSceneValue(\.selectTerminalPaneLeftAction, actions.selectTerminalPaneLeft.asFocusedAction(token: token))
      .focusedSceneValue(\.selectTerminalPaneRightAction, actions.selectTerminalPaneRight.asFocusedAction(token: token))
      .focusedSceneValue(\.runScriptAction, actions.runScript.asFocusedAction(token: token))
      .focusedSceneValue(\.stopRunScriptAction, actions.stopRunScript.asFocusedAction(token: token))
  }

  private func makeFocusedActions(
    repositories: RepositoriesFeature.State,
    hasActiveWorktree: Bool,
    runScriptEnabled: Bool,
    runScriptIsRunning: Bool
  ) -> FocusedActions {
    func action(_ appAction: AppFeature.Action) -> (() -> Void)? {
      hasActiveWorktree ? { store.send(appAction) } : nil
    }

    func canvasAction(_ perform: @escaping (WorktreeTerminalState) -> Bool) -> (() -> Void)? {
      guard repositories.isShowingCanvas else { return nil }
      return {
        guard let worktreeID = terminalManager.canvasFocusedWorktreeID,
          let state = terminalManager.stateIfExists(for: worktreeID)
        else {
          return
        }
        _ = perform(state)
      }
    }

    func fontSizeAction(_ bindingAction: String) -> (() -> Void)? {
      if repositories.isShowingCanvas {
        return {
          guard let worktreeID = terminalManager.canvasFocusedWorktreeID,
            let state = terminalManager.stateIfExists(for: worktreeID)
          else { return }
          _ = state.performBindingActionOnFocusedSurface(bindingAction)
          terminalManager.syncPreferredFontSize(from: worktreeID)
        }
      }
      guard hasActiveWorktree, let selectedWorktree = repositories.selectedTerminalWorktree else { return nil }
      return {
        guard let state = terminalManager.stateIfExists(for: selectedWorktree.id) else { return }
        _ = state.performBindingActionOnFocusedSurface(bindingAction)
        terminalManager.syncPreferredFontSize(from: selectedWorktree.id)
      }
    }

    func terminalBindingAction(_ bindingAction: String) -> (() -> Void)? {
      if let action = canvasAction({ $0.performBindingActionOnFocusedSurface(bindingAction) }) {
        return action
      }
      guard hasActiveWorktree, let selectedWorktree = repositories.selectedTerminalWorktree else { return nil }
      return {
        guard let state = terminalManager.stateIfExists(for: selectedWorktree.id) else { return }
        _ = state.performBindingActionOnFocusedSurface(bindingAction)
      }
    }

    func closeTabAction() -> (() -> Void)? {
      if repositories.isShowingCanvas {
        guard let worktreeID = terminalManager.canvasFocusedWorktreeID,
          let state = terminalManager.stateIfExists(for: worktreeID),
          state.canCloseFocusedTab
        else {
          return nil
        }
        return { _ = state.closeFocusedTab() }
      }
      guard hasActiveWorktree, let selectedWorktree = repositories.selectedTerminalWorktree,
        terminalManager.stateIfExists(for: selectedWorktree.id)?.canCloseFocusedTab == true
      else {
        return nil
      }
      return { store.send(.closeTab) }
    }

    func closeSurfaceAction() -> (() -> Void)? {
      if repositories.isShowingCanvas {
        guard let worktreeID = terminalManager.canvasFocusedWorktreeID,
          let state = terminalManager.stateIfExists(for: worktreeID),
          state.canCloseFocusedSurface
        else {
          return nil
        }
        return { _ = state.closeFocusedSurface() }
      }
      guard hasActiveWorktree, let selectedWorktree = repositories.selectedTerminalWorktree,
        terminalManager.stateIfExists(for: selectedWorktree.id)?.canCloseFocusedSurface == true
      else {
        return nil
      }
      return { store.send(.closeSurface) }
    }

    return FocusedActions(
      openSelectedWorktree: action(.openSelectedWorktree),
      newTerminal: action(.newTerminal),
      closeTab: closeTabAction(),
      closeSurface: closeSurfaceAction(),
      resetFontSize: fontSizeAction("reset_font_size"),
      increaseFontSize: fontSizeAction("increase_font_size:1"),
      decreaseFontSize: fontSizeAction("decrease_font_size:1"),
      startSearch: action(.startSearch),
      searchSelection: action(.searchSelection),
      navigateSearchNext: action(.navigateSearchNext),
      navigateSearchPrevious: action(.navigateSearchPrevious),
      endSearch: action(.endSearch),
      selectPreviousTerminalTab: terminalBindingAction("previous_tab"),
      selectNextTerminalTab: terminalBindingAction("next_tab"),
      selectPreviousTerminalPane: terminalBindingAction("goto_split:previous"),
      selectNextTerminalPane: terminalBindingAction("goto_split:next"),
      selectTerminalPaneAbove: terminalBindingAction("goto_split:up"),
      selectTerminalPaneBelow: terminalBindingAction("goto_split:down"),
      selectTerminalPaneLeft: terminalBindingAction("goto_split:left"),
      selectTerminalPaneRight: terminalBindingAction("goto_split:right"),
      runScript: (runScriptEnabled && !isCanvasBroadcasting()) ? { store.send(.runScript) } : nil,
      stopRunScript: runScriptIsRunning ? { store.send(.stopRunScript) } : nil
    )
  }

  private func selectToolbarNotification(
    _ worktreeID: Worktree.ID,
    _ notification: WorktreeTerminalNotification
  ) {
    store.send(.repositories(.selectWorktree(worktreeID)))
    if let terminalState = terminalManager.stateIfExists(for: worktreeID) {
      _ = terminalState.focusSurface(id: notification.surfaceId)
    }
  }

  private func dismissAllToolbarNotifications(in groups: [ToolbarNotificationRepositoryGroup]) {
    for repositoryGroup in groups {
      for worktreeGroup in repositoryGroup.worktrees {
        terminalManager.stateIfExists(for: worktreeGroup.id)?.dismissAllNotifications()
      }
    }
  }

  /// Hashable identity of the inputs the focused actions capture, used as the
  /// `FocusedAction` token. The detail body re-runs on every OSC-9 progress
  /// tick during agent activity; without a stable token each run would look
  /// like a focused-value change and rebuild the menu bar. Including the
  /// selected / canvas-focused worktree here keeps the published actions stable
  /// while the same worktree is focused, yet still republishes when the target
  /// worktree changes (so a menu item never fires against a stale worktree).
  private struct WorktreeActionContext: Hashable {
    let selectedWorktreeID: Worktree.ID?
    let isShowingCanvas: Bool
    let canvasFocusedWorktreeID: Worktree.ID?
  }

  private struct FocusedActions {
    let openSelectedWorktree: (() -> Void)?
    let newTerminal: (() -> Void)?
    let closeTab: (() -> Void)?
    let closeSurface: (() -> Void)?
    let resetFontSize: (() -> Void)?
    let increaseFontSize: (() -> Void)?
    let decreaseFontSize: (() -> Void)?
    let startSearch: (() -> Void)?
    let searchSelection: (() -> Void)?
    let navigateSearchNext: (() -> Void)?
    let navigateSearchPrevious: (() -> Void)?
    let endSearch: (() -> Void)?
    let selectPreviousTerminalTab: (() -> Void)?
    let selectNextTerminalTab: (() -> Void)?
    let selectPreviousTerminalPane: (() -> Void)?
    let selectNextTerminalPane: (() -> Void)?
    let selectTerminalPaneAbove: (() -> Void)?
    let selectTerminalPaneBelow: (() -> Void)?
    let selectTerminalPaneLeft: (() -> Void)?
    let selectTerminalPaneRight: (() -> Void)?
    let runScript: (() -> Void)?
    let stopRunScript: (() -> Void)?
  }

  struct WorktreeToolbarState {
    let title: DetailToolbarTitle
    let statusToast: RepositoriesFeature.StatusToast?
    let pullRequest: GithubPullRequest?
    let codeHost: CodeHost
    let supportsCodeHost: Bool
    let branchName: String
    let repositoryName: String
    let addedLines: Int?
    let removedLines: Int?
    let aheadCount: Int?
    let behindCount: Int?
    let isPushed: Bool?
    let notificationGroups: [ToolbarNotificationRepositoryGroup]
    let unseenNotificationWorktreeCount: Int
    let openActionSelection: OpenWorktreeAction
    let openActionIsAutomatic: Bool
    let showExtras: Bool
    let runScriptEnabled: Bool
    let runScriptIsRunning: Bool
    let customCommands: [UserCustomCommand]
    let isUpdateAvailable: Bool
    let isUpdateReadyToInstall: Bool
    let availableUpdateVersion: String?
    let showRunButtonInToolbar: Bool
    let showDefaultEditorInToolbar: Bool
  }

  struct WorktreeToolbarContent: ToolbarContent {
    let toolbarState: WorktreeToolbarState
    let onRenameBranch: (String) -> Void
    let externalRenamePrompt: PendingRenameBranchRequest?
    let onConsumeExternalRenamePrompt: (Int) -> Void
    let onOpenWorktree: (OpenWorktreeAction) -> Void
    let onOpenActionSelectionChanged: (OpenWorktreeAction) -> Void
    let onResetOpenActionToAutomatic: () -> Void
    let onCopyPath: () -> Void
    let onSelectNotification: (Worktree.ID, WorktreeTerminalNotification) -> Void
    let onDismissAllNotifications: () -> Void
    let onRunScript: () -> Void
    let onStopRunScript: () -> Void
    let onRunCustomCommand: (Int) -> Void
    let onActivateUpdateButton: () -> Void
    let onCodeHostAction: (RepositoriesFeature.PullRequestAction) -> Void
    /// Opens the diff view for the focused worktree — the toolbar `+/-` badge taps
    /// to this, mirroring the sidebar's change badge.
    let onShowDiff: () -> Void
    @Environment(\.resolvedKeybindings) private var resolvedKeybindings

    var body: some ToolbarContent {
      ToolbarItem(placement: .navigation) {
        WorktreeDetailTitleView(
          title: toolbarState.title,
          onSubmit: toolbarState.title.supportsRename ? onRenameBranch : nil,
          externalRenamePrompt: externalRenamePrompt,
          onConsumeExternalRenamePrompt: onConsumeExternalRenamePrompt
        )
      }

      ToolbarItem(placement: .principal) {
        ToolbarStatusView(
          toast: toolbarState.statusToast,
          pullRequest: toolbarState.pullRequest,
          codeHost: toolbarState.codeHost,
          supportsCodeHost: toolbarState.supportsCodeHost,
          branchName: toolbarState.branchName,
          repositoryName: toolbarState.repositoryName,
          addedLines: toolbarState.addedLines,
          removedLines: toolbarState.removedLines,
          aheadCount: toolbarState.aheadCount,
          behindCount: toolbarState.behindCount,
          isPushed: toolbarState.isPushed,
          onCodeHostAction: onCodeHostAction,
          onShowDiff: onShowDiff
        )
        .padding(.horizontal)
      }

      ToolbarItemGroup {
        ToolbarNotificationsPopoverButton(
          groups: toolbarState.notificationGroups,
          unseenWorktreeCount: toolbarState.unseenNotificationWorktreeCount,
          onSelectNotification: onSelectNotification,
          onDismissAll: onDismissAllNotifications
        )
        if toolbarState.isUpdateAvailable {
          ToolbarUpdateButton(
            availableVersion: toolbarState.availableUpdateVersion,
            isReadyToInstall: toolbarState.isUpdateReadyToInstall,
            onActivate: onActivateUpdateButton
          )
        }
      }

      if toolbarState.showDefaultEditorInToolbar {
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
          openMenu(
            openActionSelection: toolbarState.openActionSelection,
            openActionIsAutomatic: toolbarState.openActionIsAutomatic,
            showExtras: toolbarState.showExtras
          )
        }
      }
      commandToolbarItems

    }

    @ViewBuilder
    private func openMenu(
      openActionSelection: OpenWorktreeAction,
      openActionIsAutomatic: Bool,
      showExtras: Bool
    ) -> some View {
      let availableActions = OpenWorktreeAction.availableCases
      let resolvedOpenActionSelection = OpenWorktreeAction.availableSelection(openActionSelection)
      Button {
        onOpenWorktree(resolvedOpenActionSelection)
      } label: {
        OpenWorktreeActionMenuLabelView(
          action: resolvedOpenActionSelection,
          shortcutHint: showExtras ? shortcutDisplay(for: AppShortcuts.CommandID.openWorktree) : nil
        )
      }
      .help(openActionHelpText(for: resolvedOpenActionSelection, isDefault: true))

      Menu {
        Button {
          onResetOpenActionToAutomatic()
        } label: {
          if openActionIsAutomatic {
            Label("Automatic", systemImage: "checkmark")
          } else {
            Text("Automatic")
          }
        }
        .buttonStyle(.plain)
        .help("Pick the app automatically based on the project type")
        Divider()
        ForEach(availableActions) { action in
          let isDefault = action == resolvedOpenActionSelection
          Button {
            onOpenActionSelectionChanged(action)
            onOpenWorktree(action)
          } label: {
            OpenWorktreeActionMenuLabelView(action: action, shortcutHint: nil)
          }
          .buttonStyle(.plain)
          .help(openActionHelpText(for: action, isDefault: isDefault))
        }
        Divider()
        Button("Copy Path") {
          onCopyPath()
        }
        .help("Copy path")
      } label: {
        Image(systemName: "chevron.down")
          .font(.caption2)
          .accessibilityLabel("Open in menu")
      }
      .imageScale(.small)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Open in...")

    }

    private func openActionHelpText(for action: OpenWorktreeAction, isDefault: Bool) -> String {
      guard isDefault else { return action.title }
      return AppShortcuts.helpText(
        title: action.title,
        commandID: AppShortcuts.CommandID.openWorktree,
        in: resolvedKeybindings
      )
    }

    @ToolbarContentBuilder
    private var commandToolbarItems: some ToolbarContent {
      let showRunButton =
        toolbarState.showRunButtonInToolbar
        && (toolbarState.runScriptIsRunning || toolbarState.runScriptEnabled)
      let entries = customCommandEntries
      let inlineEntries = Array(entries.prefix(3))
      let overflowEntries = Array(entries.dropFirst(3))

      // One fixed separator in front of the whole Run + Custom Command cluster
      // keeps it distinct from the Open Editor / notification groups no matter
      // which items are hidden. Run and the custom commands share one group (no
      // spacer between them), matching the grouping before the toolbar toggles.
      if showRunButton || !inlineEntries.isEmpty || !overflowEntries.isEmpty {
        ToolbarSpacer(.fixed)
      }

      if showRunButton {
        ToolbarItem {
          RunScriptToolbarButton(
            isRunning: toolbarState.runScriptIsRunning,
            isEnabled: toolbarState.runScriptEnabled,
            runHelpText: AppShortcuts.helpText(
              title: "Run Script",
              commandID: AppShortcuts.CommandID.runScript,
              in: resolvedKeybindings
            ),
            stopHelpText: AppShortcuts.helpText(
              title: "Stop Script",
              commandID: AppShortcuts.CommandID.stopScript,
              in: resolvedKeybindings
            ),
            runShortcut: shortcutDisplay(for: AppShortcuts.CommandID.runScript),
            stopShortcut: shortcutDisplay(for: AppShortcuts.CommandID.stopScript),
            runAction: onRunScript,
            stopAction: onStopRunScript
          )
        }
      }

      if !inlineEntries.isEmpty {
        ToolbarItemGroup {
          ForEach(inlineEntries, id: \.command.id) { entry in
            customCommandButton(entry.command, index: entry.index)
          }
        }
      }

      if !overflowEntries.isEmpty {
        ToolbarItem {
          CustomCommandOverflowButton(
            entries: overflowEntries,
            shortcutDisplay: customCommandShortcutDisplay(for:),
            onRunCustomCommand: onRunCustomCommand
          )
        }
      }
    }

    private var customCommandEntries: [(index: Int, command: UserCustomCommand)] {
      Array(toolbarState.customCommands.enumerated()).map { (index: $0.offset, command: $0.element) }
    }

    private func customCommandButton(_ command: UserCustomCommand, index: Int) -> some View {
      UserCustomCommandToolbarButton(
        title: command.resolvedTitle,
        systemImage: command.resolvedSystemImage,
        shortcut: customCommandShortcutDisplay(for: command),
        isEnabled: command.hasRunnableCommand,
        action: {
          onRunCustomCommand(index)
        }
      )
    }

    private func customCommandShortcutDisplay(for command: UserCustomCommand) -> String? {
      shortcutDisplay(for: LegacyCustomCommandShortcutMigration.customCommandBindingID(for: command.id))
    }

    private func shortcutDisplay(for commandID: String) -> String? {
      AppShortcuts.display(for: commandID, in: resolvedKeybindings)
    }
  }

  private func loadingInfo(
    for selectedRow: WorktreeRowModel?,
    selectedWorktreeID: Worktree.ID?,
    repositories: RepositoriesFeature.State
  ) -> WorktreeLoadingInfo? {
    guard let selectedRow else { return nil }
    let repositoryName = repositories.repositoryName(for: selectedRow.repositoryID)
    let isFolder = repositories.repositories[id: selectedRow.repositoryID]?.kind == .plain
    if selectedRow.isDeleting {
      return WorktreeLoadingInfo(
        name: selectedRow.name,
        repositoryName: repositoryName,
        state: .removing,
        isFolder: isFolder,
        statusTitle: nil,
        statusDetail: nil,
        statusCommand: nil,
        statusLines: []
      )
    }
    if selectedRow.isArchiving {
      let progress = repositories.archiveScriptProgress(for: selectedWorktreeID)
      return WorktreeLoadingInfo(
        name: selectedRow.name,
        repositoryName: repositoryName,
        state: .archiving,
        statusTitle: progress?.titleText ?? selectedRow.name,
        statusDetail: progress?.detailText ?? selectedRow.detail,
        statusCommand: progress?.commandText,
        statusLines: progress?.outputLines ?? []
      )
    }
    if selectedRow.isPending {
      let pending = repositories.pendingWorktree(for: selectedWorktreeID)
      let progress = pending?.progress
      let displayName = progress?.worktreeName ?? selectedRow.name
      return WorktreeLoadingInfo(
        name: displayName,
        repositoryName: repositoryName,
        state: .creating,
        statusTitle: progress?.titleText ?? selectedRow.name,
        statusDetail: progress?.detailText ?? selectedRow.detail,
        statusCommand: progress?.commandText,
        statusLines: progress?.liveOutputLines ?? []
      )
    }
    return nil
  }
}
