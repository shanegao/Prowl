import ComposableArchitecture
import SwiftUI

struct ActiveAgentsPanel: View {
  @Bindable var store: StoreOf<ActiveAgentsFeature>
  /// Per-entry repository/branch labels resolved from each agent's working directory by the parent
  /// (see `SidebarListView.activeAgentRowDisplays`); keeps this view presentational.
  let rowDisplays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay]
  let selectedSurfaceID: UUID?
  /// Merged "⌥⌃↑↓" hint shown while Cmd is held; `nil` hides it (bindings customized
  /// or Cmd not held). Resolved by the parent so the panel stays presentational.
  let navigationShortcutHint: String?
  let showTabTitles: Bool
  let onEntrySelected: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Active Agents")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if let navigationShortcutHint, !store.entries.isEmpty {
          ShortcutHintView(text: navigationShortcutHint, color: .secondary)
            .transition(.opacity)
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 4)
      .animation(.easeInOut(duration: 0.15), value: navigationShortcutHint)

      if store.entries.isEmpty {
        Text("No active agents")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 40)
          .padding(.vertical, 32)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groupedEntries, id: \.repoName) { group in
              VStack(alignment: .leading, spacing: 0) {
                Divider()
                Text(group.repoName)
                  .font(.subheadline)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                ForEach(group.entries) { entry in
                  Button {
                    store.send(.entryTapped(entry.id))
                    onEntrySelected()
                  } label: {
                    ActiveAgentRow(
                      entry: entry,
                      repositoryName: repositoryName(for: entry),
                      subtitle: subtitle(for: entry),
                      repositoryColor: repositoryColor(for: entry),
                      isDimmed: isDimmed(entry)
                    )
                  }
                  .buttonStyle(.plain)
                  .help(helpText(for: entry))
                }
              }
            }
          }
        }
        .scrollIndicators(.never)
        .frame(minWidth: 320, maxWidth: 520, maxHeight: 440)
      }
    }
  }

  /// Entries grouped by repository, preserving first-seen-of-repo order. Same
  /// pattern as `ToolbarNotificationsPopoverView` — keeps the visual layout
  /// stable as agents come and go during a working session.
  private var groupedEntries: [(repoName: String, entries: [ActiveAgentEntry])] {
    var order: [String] = []
    var seen = Set<String>()
    var byRepo: [String: [ActiveAgentEntry]] = [:]
    for entry in store.entries {
      let name = repositoryName(for: entry)
      if !seen.contains(name) {
        order.append(name)
        seen.insert(name)
      }
      byRepo[name, default: []].append(entry)
    }
    return order.map { (repoName: $0, entries: byRepo[$0] ?? []) }
  }

  private func repositoryName(for entry: ActiveAgentEntry) -> String {
    rowDisplays[entry.id]?.repositoryName ?? entry.worktreeName
  }

  private func branchName(for entry: ActiveAgentEntry) -> String {
    rowDisplays[entry.id]?.branchName ?? entry.worktreeName
  }

  private func subtitle(for entry: ActiveAgentEntry) -> String {
    Self.subtitle(
      for: entry,
      branchName: branchName(for: entry),
      showTabTitles: showTabTitles
    )
  }

  private func repositoryColor(for entry: ActiveAgentEntry) -> RepositoryColorChoice? {
    rowDisplays[entry.id]?.color
  }

  private func isDimmed(_ entry: ActiveAgentEntry) -> Bool {
    // Highlight the selected worktree's active surface. `entryTapped` now focuses
    // the target surface before selecting its worktree, so `selectedSurfaceID` is
    // already correct by the time the selection lands — no cross-worktree flash and
    // no dependence on the reducer's focus anchor, which can go stale when the
    // per-worktree `focusChanged` dedup suppresses an event.
    if let selectedSurfaceID {
      return entry.surfaceID != selectedSurfaceID
    }
    return false
  }

  private func helpText(for entry: ActiveAgentEntry) -> String {
    Self.helpText(
      for: entry,
      branchName: branchName(for: entry),
      showTabTitles: showTabTitles
    )
  }

  static func subtitle(
    for entry: ActiveAgentEntry,
    branchName: String,
    showTabTitles: Bool
  ) -> String {
    showTabTitles ? tabTitle(for: entry) : branchName
  }

  static func helpText(
    for entry: ActiveAgentEntry,
    branchName: String,
    showTabTitles: Bool
  ) -> String {
    showTabTitles ? branchName : tabTitle(for: entry)
  }

  static func tabTitle(for entry: ActiveAgentEntry) -> String {
    let trimmed = entry.tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled tab" : trimmed
  }
}
