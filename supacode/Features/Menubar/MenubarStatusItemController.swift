import AppKit
import ComposableArchitecture

/// AppKit-native menubar status item for Prowl.
///
/// Replaces a SwiftUI `MenuBarExtra` scene because that scene interferes with
/// the lifecycle of sibling `Window(_:id:)` scenes — even with the docs-
/// recommended `isInserted:` overload and explicit `defaultLaunchBehavior
/// (.presented)`, having `MenuBarExtra` declared in `App.body` causes the
/// app's main window to never auto-present on launch. The status item alone
/// satisfies AppKit's "this app has a UI surface" heuristic and SwiftUI
/// declines to instantiate the Window scene's content view. CodexBar (Peter
/// Steinberger's macOS menubar app) uses the same pattern: skip `MenuBarExtra`
/// entirely, build the menubar with `NSStatusItem` + `NSMenu` in AppKit-land,
/// and let SwiftUI scenes work normally.
///
/// Owned by `SupacodeAppDelegate`; created when `appStore` is assigned. The
/// menu is rebuilt on every open (via `NSMenuDelegate.menuNeedsUpdate(_:)`)
/// from current store state — cheap, and avoids reactive plumbing for an
/// element a user interacts with seconds apart at most.
@MainActor
final class MenubarStatusItemController: NSObject, NSMenuDelegate {
  /// Cap on inline rows in the Active Agents section before the rest fold
  /// into a "More" submenu. Matches the cap from the prior SwiftUI impl.
  private static let activeAgentsInlineLimit = 5

  private let store: StoreOf<AppFeature>
  private let statusItem: NSStatusItem
  private let menu: NSMenu

  init(store: StoreOf<AppFeature>) {
    self.store = store
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.menu = NSMenu()
    super.init()

    if let button = statusItem.button {
      // Same SF Symbol the old `MenuBarExtra("Prowl", systemImage: ...)` used,
      // sized to 15 pt to match Prowl's intended menubar weight (the
      // unconfigured default renders smaller than the surrounding system
      // status items at our default text-size). `withSymbolConfiguration`
      // returns nil if the configuration can't be applied; falling back
      // to the unconfigured image keeps the icon present in that case.
      let baseImage = NSImage(
        systemSymbolName: "square.split.bottomrightquarter",
        accessibilityDescription: "Prowl"
      )
      let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
      button.image = baseImage?.withSymbolConfiguration(configuration) ?? baseImage
    }
    menu.delegate = self
    menu.autoenablesItems = false
    statusItem.menu = menu
  }

  // MARK: NSMenuDelegate

  /// AppKit calls this just before showing the menu — rebuild from current
  /// store state every time. The menu is opened by a deliberate user click,
  /// so per-open rebuild cost is irrelevant compared to keeping items in
  /// sync with state changes that happened while the menu was closed.
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    appendReposSection(into: menu)
    appendActiveAgentsSection(into: menu, displays: resolveActiveAgentDisplays())
    appendFooter(into: menu)
  }

  /// Resolves per-entry repo/branch labels using the same SSOT the sidebar
  /// and the toolbar popover use (`SidebarListView.activeAgentRowDisplays`)
  /// — the resolver applies workingDirectory-aware repo lookup so the
  /// displayed names track live branch renames. Two worktrees with the same
  /// branch name end up with the same `branchName` but distinct
  /// `repositoryName`, which we render as the row's subtitle so the user
  /// can tell them apart.
  private func resolveActiveAgentDisplays() -> [ActiveAgentEntry.ID: ActiveAgentRowDisplay] {
    let metadata = SidebarListView.activeAgentWorktreeMetadata(
      repositories: store.repositories.repositories,
      customTitles: store.repositories.repositoryCustomTitles
    )
    return SidebarListView.activeAgentRowDisplays(
      entries: store.repositories.activeAgents.entries,
      repositories: store.repositories.repositories,
      metadata: metadata
    )
  }

  // MARK: Repos section

  private func appendReposSection(into menu: NSMenu) {
    menu.addItem(.sectionHeader(title: "Repos"))

    let orderedRepos = store.repositories.orderedRepositoryIDs()
      .compactMap { store.repositories.repositories[id: $0] }

    guard !orderedRepos.isEmpty else {
      let item = NSMenuItem(title: "No repositories", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
      return
    }

    for repo in orderedRepos {
      menu.addItem(makeRepoItem(repo))
    }
  }

  private func makeRepoItem(_ repo: Repository) -> NSMenuItem {
    let title = store.repositories.repositoryName(for: repo.id) ?? repo.name

    if repo.kind == .plain {
      let item = NSMenuItem(title: title, action: #selector(handleSelectRepo(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = repo.id
      return item
    }

    // Git repo: parent item with a submenu of worktrees. Tapping the parent
    // selects the first worktree (matching the prior `Menu(_:primaryAction:)`
    // affordance from the SwiftUI impl).
    let rows = store.repositories.worktreeRows(in: repo)
    let parent = NSMenuItem(
      title: title,
      action: #selector(handleSelectFirstWorktree(_:)),
      keyEquivalent: ""
    )
    parent.target = self
    parent.representedObject = rows.first?.id

    let submenu = NSMenu(title: title)
    submenu.autoenablesItems = false
    for row in rows {
      let item = NSMenuItem(
        title: row.name,
        action: #selector(handleSelectWorktree(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = row.id
      submenu.addItem(item)
    }
    parent.submenu = submenu

    return parent
  }

  // MARK: Active Agents section

  private func appendActiveAgentsSection(
    into menu: NSMenu,
    displays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay]
  ) {
    let sorted = sortedActiveAgentEntries()
    guard !sorted.isEmpty else { return }

    menu.addItem(.sectionHeader(title: "Active Agents"))

    let inline = sorted.prefix(Self.activeAgentsInlineLimit)
    let overflow = Array(sorted.dropFirst(Self.activeAgentsInlineLimit))

    for entry in inline {
      menu.addItem(makeAgentItem(entry, display: displays[entry.id]))
    }

    if !overflow.isEmpty {
      let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
      let submenu = NSMenu(title: "More")
      submenu.autoenablesItems = false
      for entry in overflow {
        submenu.addItem(makeAgentItem(entry, display: displays[entry.id]))
      }
      moreItem.submenu = submenu
      menu.addItem(moreItem)
    }
  }

  private func sortedActiveAgentEntries() -> [ActiveAgentEntry] {
    store.repositories.activeAgents.entries.sorted { lhs, rhs in
      let lhsBlocked = lhs.displayState == .blocked
      let rhsBlocked = rhs.displayState == .blocked
      if lhsBlocked != rhsBlocked { return lhsBlocked }
      return lhs.lastChangedAt > rhs.lastChangedAt
    }
  }

  private func makeAgentItem(
    _ entry: ActiveAgentEntry,
    display: ActiveAgentRowDisplay?
  ) -> NSMenuItem {
    // Title shows branch (from workingDirectory-aware resolver) so rebases
    // / live branch renames are reflected; falls back to the surface's
    // owning worktree name if the resolver can't place the directory.
    let branchName = display?.branchName ?? entry.worktreeName
    // Mirrors the repo rows above: the parent carries a Focus action AND a
    // submenu, so tapping the row focuses the agent while {Focus, Send text…}
    // stays available via the disclosure (AppKit fires the parent's action on a
    // direct click, the same affordance as `Menu(_:primaryAction:)`).
    let item = NSMenuItem(
      title: "[\(entry.displayState.label)] \(branchName)",
      action: #selector(handleAgentTapped(_:)),
      keyEquivalent: ""
    )
    // Subtitle (macOS 14+) shows the repository name, so two worktrees
    // that share a branch name (e.g. `master` in two repos) become
    // distinguishable at a glance.
    if let repositoryName = display?.repositoryName {
      item.subtitle = repositoryName
    }
    item.target = self
    item.image = agentMenuIcon(for: entry)
    item.representedObject = entry.id
    item.submenu = makeAgentSubmenu(entry)
    return item
  }

  private func makeAgentSubmenu(_ entry: ActiveAgentEntry) -> NSMenu {
    let submenu = NSMenu(title: "")
    submenu.autoenablesItems = false

    let focusItem = NSMenuItem(title: "Focus", action: #selector(handleAgentTapped(_:)), keyEquivalent: "")
    focusItem.target = self
    focusItem.representedObject = entry.id
    submenu.addItem(focusItem)

    let sendItem = NSMenuItem(title: "Send text…", action: #selector(handleAgentSendText(_:)), keyEquivalent: "")
    sendItem.target = self
    sendItem.representedObject = entry.id
    submenu.addItem(sendItem)

    return submenu
  }

  /// Resolves the agent's branded icon to an `NSImage` for the menu row — via the
  /// same `entry.iconSource` SSOT the in-app `AgentIconImage` uses (so aliases like
  /// `omp`/`pi` resolve to the right logo), but rendered as `NSImage` because this
  /// is a native `NSMenu`. Prefers the asset logo, falls back to the SF Symbol,
  /// then `sparkle`.
  private func agentMenuIcon(for entry: ActiveAgentEntry) -> NSImage? {
    let image: NSImage?
    if let icon = entry.iconSource {
      if let assetName = icon.assetName {
        image = NSImage(named: assetName)
      } else {
        image = NSImage(systemSymbolName: icon.systemSymbol, accessibilityDescription: nil)
      }
    } else {
      image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
    }
    image?.size = NSSize(width: 16, height: 16)
    return image
  }

  // MARK: Footer

  private func appendFooter(into menu: NSMenu) {
    menu.addItem(NSMenuItem.separator())

    let openItem = NSMenuItem(
      title: "Open Prowl Window",
      action: #selector(handleOpenWindow(_:)),
      keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)

    let quitItem = NSMenuItem(
      title: "Quit Prowl",
      action: #selector(handleQuit(_:)),
      keyEquivalent: ""
    )
    quitItem.target = self
    menu.addItem(quitItem)
  }

  // MARK: Actions

  /// `focusTerminal: true` (vs the sidebar-button default of `false`) matches
  /// the prior SwiftUI menubar's behavior: the user invoked the action from
  /// outside Prowl, so keyboard focus should land in the terminal directly.
  /// `surfaceMainWindow()` is needed because TCA state changes alone don't
  /// surface the window from a background app.
  @objc private func handleSelectWorktree(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? Worktree.ID else { return }
    store.send(.repositories(.selectWorktree(id, focusTerminal: true, recordHistory: true)))
    NSApplication.shared.surfaceMainWindow()
  }

  @objc private func handleSelectFirstWorktree(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? Worktree.ID else { return }
    store.send(.repositories(.selectWorktree(id, focusTerminal: true, recordHistory: true)))
    NSApplication.shared.surfaceMainWindow()
  }

  @objc private func handleSelectRepo(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? Repository.ID else { return }
    store.send(.repositories(.selectRepository(id)))
    NSApplication.shared.surfaceMainWindow()
  }

  @objc private func handleAgentTapped(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? ActiveAgentEntry.ID else { return }
    store.send(.repositories(.activeAgents(.entryTapped(id))))
    NSApplication.shared.surfaceMainWindow()
  }

  /// Opens the quick-send composer for this agent. Deliberately does NOT call
  /// `surfaceMainWindow()` — the non-activating panel is the whole point, so the
  /// main app stays in the background.
  @objc private func handleAgentSendText(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? ActiveAgentEntry.ID else { return }
    store.send(.presentQuickSend(defaultAgentID: id))
  }

  @objc private func handleOpenWindow(_ sender: NSMenuItem) {
    NSApplication.shared.surfaceMainWindow()
  }

  @objc private func handleQuit(_ sender: NSMenuItem) {
    store.send(.requestQuit)
  }
}
