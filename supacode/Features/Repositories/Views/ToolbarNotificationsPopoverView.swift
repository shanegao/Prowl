import SwiftUI

struct ToolbarNotificationsPopoverView: View {
  let groups: [ToolbarNotificationRepositoryGroup]
  let onSelectNotification: (Worktree.ID, WorktreeTerminalNotification) -> Void
  let onDismissAll: () -> Void

  /// Non-destructive filter that hides already-read notifications from the
  /// list. Replaces the prior "Clean Read" destructive action — toggle on
  /// to focus, toggle off to see history. Persisted across popover opens
  /// (defaults to `true`) so the last choice sticks.
  @AppStorage("focusUnreadNotifications") private var focusUnread = true

  /// Measured natural height of the popover content. Drives an explicit height
  /// (capped, then scrolls) so the popover resizes to fit when toggling the
  /// Unread filter changes how many rows are shown — a plain `maxHeight` lets
  /// the greedy `ScrollView` hold one size regardless of content.
  @State private var contentHeight: CGFloat = 0

  var body: some View {
    let notificationCount = groups.reduce(0) { count, repository in
      count + repository.notificationCount
    }
    let notificationLabel = notificationCount == 1 ? "notification" : "notifications"
    let visibleGroups = focusUnread ? filterToUnread(groups) : groups

    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Notifications")
              .font(.headline)
            Text("\(notificationCount) \(notificationLabel)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Toggle("Unread", isOn: $focusUnread)
            .toggleStyle(.button)
            .help("Hide notifications you've already read. Toggle off to show all.")
          Button("Dismiss All") {
            onDismissAll()
          }
          .disabled(notificationCount == 0)
          .help("Dismiss all notifications")
        }

        ForEach(visibleGroups) { repository in
          VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(repository.name)
              .font(.subheadline)
            ForEach(repository.worktrees) { worktree in
              VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                  Text(worktree.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  if worktree.hasUnseenNotifications {
                    Circle()
                      .fill(.orange)
                      .frame(width: 6, height: 6)
                      .accessibilityHidden(true)
                  }
                }
                ForEach(worktree.notifications) { notification in
                  Button {
                    onSelectNotification(worktree.id, notification)
                  } label: {
                    HStack(alignment: .top, spacing: 8) {
                      Image(systemName: "bell")
                        .foregroundStyle(notification.isRead ? Color.secondary : Color.orange)
                        .accessibilityHidden(true)
                      Text(notification.content)
                        .font(.caption)
                        .foregroundStyle(notification.isRead ? Color.secondary : Color.primary)
                        .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .buttonStyle(.plain)
                  .help(
                    notification.content.isEmpty
                      ? "Select worktree and focus terminal"
                      : notification.content
                  )
                }
              }
            }
          }
        }
      }
      .padding()
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { newHeight in
        contentHeight = newHeight
      }
    }
    .frame(minWidth: 320, maxWidth: 520)
    .frame(height: min(contentHeight, 440))
  }

  /// Drops read notifications row-by-row, then drops any worktree whose
  /// notifications are entirely read, then any repository with no remaining
  /// worktrees — so the list collapses naturally when the focus filter
  /// removes everything in a section, instead of leaving empty headers.
  private func filterToUnread(
    _ groups: [ToolbarNotificationRepositoryGroup]
  ) -> [ToolbarNotificationRepositoryGroup] {
    groups.compactMap { repository in
      let worktrees = repository.worktrees.compactMap { worktree -> ToolbarNotificationWorktreeGroup? in
        let unread = worktree.notifications.filter { !$0.isRead }
        guard !unread.isEmpty else { return nil }
        return ToolbarNotificationWorktreeGroup(
          id: worktree.id,
          name: worktree.name,
          notifications: unread,
          hasUnseenNotifications: worktree.hasUnseenNotifications
        )
      }
      guard !worktrees.isEmpty else { return nil }
      return ToolbarNotificationRepositoryGroup(
        id: repository.id,
        name: repository.name,
        worktrees: worktrees
      )
    }
  }
}
