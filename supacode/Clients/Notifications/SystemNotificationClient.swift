import AppKit
import ComposableArchitecture
import Foundation
import UserNotifications

private nonisolated let notificationWorktreeIDKey = "prowl.worktreeID"
private nonisolated let notificationSurfaceIDKey = "prowl.surfaceID"
/// Category + action identifiers for the Slack-style inline reply. The category is
/// attached to every targeted notification (one carrying a worktree + surface) so
/// its banner shows a "Reply" text field; the action id tags the resulting response
/// so the delegate can tell a reply apart from a plain banner tap.
private nonisolated let notificationReplyCategoryID = "prowl.reply"
private nonisolated let notificationReplyActionID = "prowl.reply.action"
/// Category for an actionable permission prompt: its option buttons are registered
/// dynamically per-notification (parsed from the pane). Each option action's id is
/// `<answer prefix><key>`, so the delegate recovers the key token to send.
private nonisolated let notificationPermissionCategoryID = "prowl.permission"
private nonisolated let notificationAnswerActionPrefix = "prowl.answer."

/// A quick-answer button for an actionable permission notification: `label` is the
/// button title (the parsed option text) and `key` is the key token Prowl sends to
/// the pane when tapped (e.g. "1").
struct SystemNotificationReplyOption: Equatable, Sendable {
  let label: String
  let key: String
}

@MainActor
private final class ForegroundSystemNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  var onNotificationTap: ((Worktree.ID, UUID) -> Void)?
  var onNotificationReply: ((Worktree.ID, UUID, String) -> Void)?
  var onNotificationAnswer: ((Worktree.ID, UUID, String) -> Void)?

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    await Task.yield()
    return [.badge, .sound, .banner]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    await Task.yield()
    let userInfo = response.notification.request.content.userInfo
    guard let worktreeID = userInfo[notificationWorktreeIDKey] as? String,
      let rawSurfaceID = userInfo[notificationSurfaceIDKey] as? String,
      let surfaceID = UUID(uuidString: rawSurfaceID)
    else {
      return
    }
    // A parsed-option quick-answer button: the key token follows the prefix in the
    // action id; deliver it as a keypress to the originating pane. Otherwise the
    // Slack-style inline reply routes typed text to that pane — both deliver without
    // focusing it. Any other interaction (tapping the banner body) jumps to and
    // focuses the surface as before.
    if response.actionIdentifier.hasPrefix(notificationAnswerActionPrefix) {
      let key = String(response.actionIdentifier.dropFirst(notificationAnswerActionPrefix.count))
      onNotificationAnswer?(worktreeID, surfaceID, key)
    } else if response.actionIdentifier == notificationReplyActionID,
      let textResponse = response as? UNTextInputNotificationResponse
    {
      onNotificationReply?(worktreeID, surfaceID, textResponse.userText)
    } else {
      onNotificationTap?(worktreeID, surfaceID)
    }
  }
}

@MainActor
private let foregroundSystemNotificationDelegate = ForegroundSystemNotificationDelegate()

@MainActor
private func configuredNotificationCenter() -> UNUserNotificationCenter {
  let center = UNUserNotificationCenter.current()
  if center.delegate !== foregroundSystemNotificationDelegate {
    center.delegate = foregroundSystemNotificationDelegate
    // Register the plain reply category once, alongside the delegate. Permission
    // notifications re-register a richer category per-send (see `send`).
    center.setNotificationCategories([makeBaseReplyCategory()])
  }
  return center
}

/// The shared inline "Reply" text-input action (free-form message to the agent),
/// reused by every category.
private func makeReplyAction() -> UNTextInputNotificationAction {
  UNTextInputNotificationAction(
    identifier: notificationReplyActionID,
    title: "Reply",
    options: [],
    textInputButtonTitle: "Send",
    textInputPlaceholder: "Reply to the agent…"
  )
}

/// The plain reply-only category used by every targeted notification that isn't an
/// actionable permission prompt.
private func makeBaseReplyCategory() -> UNNotificationCategory {
  UNNotificationCategory(
    identifier: notificationReplyCategoryID,
    actions: [makeReplyAction()],
    intentIdentifiers: [],
    options: []
  )
}

/// Registers the permission category with one button per parsed option (capped to
/// fit macOS's four-action limit alongside the text reply), each tagged with its key
/// token via the action identifier. `setNotificationCategories` replaces the whole
/// set, so the base reply category is re-registered alongside it.
@MainActor
private func registerPermissionCategory(
  options: [SystemNotificationReplyOption],
  on center: UNUserNotificationCenter
) {
  let optionActions = options.prefix(3).map { option in
    UNNotificationAction(
      identifier: "\(notificationAnswerActionPrefix)\(option.key)",
      title: option.label,
      options: []
    )
  }
  let permissionCategory = UNNotificationCategory(
    identifier: notificationPermissionCategoryID,
    actions: optionActions + [makeReplyAction()],
    intentIdentifiers: [],
    options: []
  )
  center.setNotificationCategories([makeBaseReplyCategory(), permissionCategory])
}

@MainActor
func setSystemNotificationTapHandler(_ handler: @escaping @MainActor (Worktree.ID, UUID) -> Void) {
  _ = configuredNotificationCenter()
  foregroundSystemNotificationDelegate.onNotificationTap = handler
}

@MainActor
func setSystemNotificationReplyHandler(
  _ handler: @escaping @MainActor (Worktree.ID, UUID, String) -> Void
) {
  _ = configuredNotificationCenter()
  foregroundSystemNotificationDelegate.onNotificationReply = handler
}

@MainActor
func setSystemNotificationAnswerHandler(
  _ handler: @escaping @MainActor (Worktree.ID, UUID, String) -> Void
) {
  _ = configuredNotificationCenter()
  foregroundSystemNotificationDelegate.onNotificationAnswer = handler
}

struct SystemNotificationClient {
  struct AuthorizationRequestResult: Equatable {
    let granted: Bool
    let errorMessage: String?
  }

  enum AuthorizationStatus: Equatable {
    case authorized
    case denied
    case notDetermined
  }

  /// Whether macOS will actually render the app's Dock badge. The Dock badge
  /// is gated by the system notification permission plus the per-app "Badge
  /// app icon" switch — it does not depend on Prowl's own banner toggle.
  enum DockBadgeAuthorization: Equatable {
    /// Notifications are allowed and "Badge app icon" is on.
    case available
    /// macOS is not allowing notifications for Prowl (denied or not yet asked).
    case notificationsDenied
    /// Notifications are allowed, but "Badge app icon" is turned off.
    case badgeDisabled
  }

  var authorizationStatus: @MainActor @Sendable () async -> AuthorizationStatus
  var dockBadgeAuthorization: @MainActor @Sendable () async -> DockBadgeAuthorization
  var requestAuthorization: @MainActor @Sendable () async -> AuthorizationRequestResult
  var send:
    @MainActor @Sendable (
      _ title: String, _ subtitle: String?, _ body: String, _ worktreeID: Worktree.ID?, _ surfaceID: UUID?,
      _ options: [SystemNotificationReplyOption]
    ) async -> Void
  var openSettings: @MainActor @Sendable () async -> Void
}

extension SystemNotificationClient: DependencyKey {
  static let liveValue = SystemNotificationClient(
    authorizationStatus: {
      let center = configuredNotificationCenter()
      let settings = await center.notificationSettings()
      switch settings.authorizationStatus {
      case .authorized, .provisional:
        return .authorized
      case .denied:
        return .denied
      case .notDetermined:
        return .notDetermined
      @unknown default:
        return .denied
      }
    },
    dockBadgeAuthorization: {
      let center = configuredNotificationCenter()
      let settings = await center.notificationSettings()
      switch settings.authorizationStatus {
      case .authorized, .provisional:
        return settings.badgeSetting == .enabled ? .available : .badgeDisabled
      default:
        return .notificationsDenied
      }
    },
    requestAuthorization: {
      let center = configuredNotificationCenter()
      do {
        let granted = try await center.requestAuthorization(
          options: [.alert, .badge, .sound]
        )
        return AuthorizationRequestResult(granted: granted, errorMessage: nil)
      } catch {
        return AuthorizationRequestResult(
          granted: false,
          errorMessage: error.localizedDescription
        )
      }
    },
    send: { title, subtitle, body, worktreeID, surfaceID, options in
      let center = configuredNotificationCenter()
      let content = UNMutableNotificationContent()
      content.title = title
      if let subtitle, !subtitle.isEmpty {
        content.subtitle = subtitle
      }
      content.body = body
      content.sound = .default
      if let worktreeID, let surfaceID {
        content.userInfo = [
          notificationWorktreeIDKey: worktreeID,
          notificationSurfaceIDKey: surfaceID.uuidString,
        ]
        if options.isEmpty {
          // Plain reply-only banner.
          content.categoryIdentifier = notificationReplyCategoryID
        } else {
          // Actionable permission prompt: register a button per parsed option, then
          // attach that category so the banner shows quick-answer buttons.
          registerPermissionCategory(options: options, on: center)
          content.categoryIdentifier = notificationPermissionCategoryID
        }
      }
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
      )
      try? await center.add(request)
    },
    openSettings: {
      guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
        return
      }
      _ = NSWorkspace.shared.open(url)
    }
  )

  static let testValue = SystemNotificationClient(
    authorizationStatus: { .notDetermined },
    dockBadgeAuthorization: { .available },
    requestAuthorization: { AuthorizationRequestResult(granted: false, errorMessage: nil) },
    send: { _, _, _, _, _, _ in },
    openSettings: {}
  )
}

extension DependencyValues {
  var systemNotificationClient: SystemNotificationClient {
    get { self[SystemNotificationClient.self] }
    set { self[SystemNotificationClient.self] = newValue }
  }
}
