import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

private struct SystemNotificationSend: Equatable {
  let title: String
  let subtitle: String?
  let body: String
  let worktreeID: Worktree.ID?
  let surfaceID: UUID?
}

@MainActor
struct AppFeatureSystemNotificationTests {
  @Test(.dependencies) func firstTimeDeniedTurnsSystemNotificationsBackOffWithAlert() async {
    let storage = SettingsTestStorage()
    let authorizationRequests = LockIsolated(0)
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.systemNotificationClient.authorizationStatus = { .notDetermined }
        $0.systemNotificationClient.requestAuthorization = {
          authorizationRequests.withValue { $0 += 1 }
          return SystemNotificationClient.AuthorizationRequestResult(
            granted: false,
            errorMessage: "Mock request error"
          )
        }
      }
    }
    store.exhaustivity = .off

    await store.send(.settings(.binding(.set(\.systemNotificationsEnabled, true)))) {
      $0.settings.systemNotificationsEnabled = true
    }
    await store.receive(\.systemNotificationsPermissionFailed)
    await store.receive(\.settings.setSystemNotificationsEnabled) {
      $0.settings.systemNotificationsEnabled = false
    }
    let expectedAlert = AlertState<SettingsFeature.Alert> {
      TextState("Prowl cannot send system notifications")
    } actions: {
      ButtonState(action: .openSystemNotificationSettings) {
        TextState("Open System Settings")
      }
      ButtonState(role: .cancel, action: .dismiss) {
        TextState("Cancel")
      }
    } message: {
      TextState("Notification permission is turned off. Open System Settings to allow Prowl to send notifications.")
    }
    await store.receive(\.settings.showNotificationPermissionAlert) {
      $0.settings.alert = expectedAlert
    }

    #expect(authorizationRequests.value == 1)
    #expect(store.state.settings.systemNotificationsEnabled == false)
    #expect(store.state.settings.alert == expectedAlert)
  }

  @Test(.dependencies) func deniedStatusShowsAlertAndOpensSystemSettings() async {
    let storage = SettingsTestStorage()
    let authorizationRequests = LockIsolated(0)
    let openedSettings = LockIsolated(0)
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.systemNotificationClient.authorizationStatus = { .denied }
        $0.systemNotificationClient.requestAuthorization = {
          authorizationRequests.withValue { $0 += 1 }
          return SystemNotificationClient.AuthorizationRequestResult(
            granted: false,
            errorMessage: "Mock request error"
          )
        }
        $0.systemNotificationClient.openSettings = {
          openedSettings.withValue { $0 += 1 }
        }
      }
    }
    store.exhaustivity = .off

    await store.send(.settings(.binding(.set(\.systemNotificationsEnabled, true)))) {
      $0.settings.systemNotificationsEnabled = true
    }
    await store.receive(\.systemNotificationsPermissionFailed)
    await store.receive(\.settings.setSystemNotificationsEnabled) {
      $0.settings.systemNotificationsEnabled = false
    }
    let expectedAlert = AlertState<SettingsFeature.Alert> {
      TextState("Prowl cannot send system notifications")
    } actions: {
      ButtonState(action: .openSystemNotificationSettings) {
        TextState("Open System Settings")
      }
      ButtonState(role: .cancel, action: .dismiss) {
        TextState("Cancel")
      }
    } message: {
      TextState("Notification permission is turned off. Open System Settings to allow Prowl to send notifications.")
    }
    await store.receive(\.settings.showNotificationPermissionAlert) {
      $0.settings.alert = expectedAlert
    }

    #expect(authorizationRequests.value == 0)
    #expect(store.state.settings.systemNotificationsEnabled == false)
    #expect(store.state.settings.alert == expectedAlert)

    await store.send(.settings(.alert(.presented(.openSystemNotificationSettings)))) {
      $0.settings.alert = nil
    }
    await store.finish()
    #expect(openedSettings.value == 1)
  }

  @Test(.dependencies) func notificationReceivedSendsSystemNotificationWhenEnabled() async {
    var globalSettings = GlobalSettings.default
    globalSettings.systemNotificationsEnabled = true
    let surfaceID = UUID()
    let sends = LockIsolated<[SystemNotificationSend]>([])
    let store = TestStore(
      initialState: AppFeature.State(
        settings: SettingsFeature.State(settings: globalSettings)
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.systemNotificationClient.send = { title, subtitle, body, worktreeID, targetSurfaceID, _ in
        sends.withValue {
          $0.append(
            SystemNotificationSend(
              title: title,
              subtitle: subtitle,
              body: body,
              worktreeID: worktreeID,
              surfaceID: targetSurfaceID
            )
          )
        }
      }
    }
    store.exhaustivity = .off

    await store.send(
      .terminalEvent(
        .notificationReceived(
          worktreeID: "/tmp/repo/wt-1",
          surfaceID: surfaceID,
          title: "Done",
          body: "Build succeeded"
        )
      )
    )
    await store.finish()

    #expect(sends.value.count == 1)
    #expect(sends.value.first?.title == "Done")
    #expect(sends.value.first?.body == "Build succeeded")
    #expect(sends.value.first?.worktreeID == "/tmp/repo/wt-1")
    #expect(sends.value.first?.surfaceID == surfaceID)
    // No repository is registered in this state, so there's no source label.
    #expect(sends.value.first?.subtitle == nil)
  }

  @Test(.dependencies) func notificationReceivedSkipsLocalSoundWhenSystemNotificationsEnabled() async {
    var globalSettings = GlobalSettings.default
    globalSettings.systemNotificationsEnabled = true
    globalSettings.notificationSoundEnabled = true
    let plays = LockIsolated(0)
    let store = TestStore(
      initialState: AppFeature.State(
        settings: SettingsFeature.State(settings: globalSettings)
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.notificationSoundClient.play = {
        plays.withValue { $0 += 1 }
      }
    }
    store.exhaustivity = .off

    await store.send(
      .terminalEvent(
        .notificationReceived(
          worktreeID: "/tmp/repo/wt-1",
          surfaceID: UUID(),
          title: "Done",
          body: "Build succeeded"
        )
      )
    )
    await store.finish()

    #expect(plays.value == 0)
  }

  @Test(.dependencies) func notificationReceivedPlaysLocalSoundWhenSystemNotificationsDisabled() async {
    var globalSettings = GlobalSettings.default
    globalSettings.systemNotificationsEnabled = false
    globalSettings.notificationSoundEnabled = true
    let plays = LockIsolated(0)
    let sends = LockIsolated(0)
    let store = TestStore(
      initialState: AppFeature.State(
        settings: SettingsFeature.State(settings: globalSettings)
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.notificationSoundClient.play = {
        plays.withValue { $0 += 1 }
      }
      $0.systemNotificationClient.send = { _, _, _, _, _, _ in
        sends.withValue { $0 += 1 }
      }
    }
    store.exhaustivity = .off

    await store.send(
      .terminalEvent(
        .notificationReceived(
          worktreeID: "/tmp/repo/wt-1",
          surfaceID: UUID(),
          title: "Done",
          body: "Build succeeded"
        )
      )
    )
    await store.finish()

    #expect(plays.value == 1)
    #expect(sends.value == 0)
  }

  @Test(.dependencies) func notificationReplyDeliversTextToOriginatingPane() async {
    let repoRoot = "/tmp/reply-repo"
    let worktree = Worktree(
      id: repoRoot,
      name: "main",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: repoRoot),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
    let repository = Repository(
      id: repoRoot,
      rootURL: URL(fileURLWithPath: repoRoot),
      name: "alpha",
      worktrees: IdentifiedArrayOf(uniqueElements: [worktree])
    )
    var initialState = AppFeature.State()
    initialState.repositories.repositories = [repository]

    let surfaceID = UUID()
    let sends = LockIsolated<[(Worktree.ID, UUID, String, Bool)]>([])
    let markReads = LockIsolated<[(Worktree.ID, UUID)]>([])
    let store = TestStore(initialState: initialState) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendTextToSurface = { worktree, targetSurfaceID, text, trailingEnter in
        sends.withValue { $0.append((worktree.id, targetSurfaceID, text, trailingEnter)) }
        return true
      }
      $0.terminalClient.markNotificationsReadForSurface = { worktreeID, targetSurfaceID in
        markReads.withValue { $0.append((worktreeID, targetSurfaceID)) }
      }
    }
    store.exhaustivity = .off

    await store.send(
      .systemNotificationReplied(worktreeID: repoRoot, surfaceID: surfaceID, text: "ship it")
    )
    await store.finish()

    // Reply is delivered to the originating pane (trailing enter, like quick-send),
    // and no worktree selection/focus action is emitted — it stays in place.
    #expect(sends.value.count == 1)
    #expect(sends.value.first?.0 == repoRoot)
    #expect(sends.value.first?.1 == surfaceID)
    #expect(sends.value.first?.2 == "ship it")
    #expect(sends.value.first?.3 == true)
    // On success the originating pane's notifications are marked read.
    #expect(markReads.value.count == 1)
    #expect(markReads.value.first?.0 == repoRoot)
    #expect(markReads.value.first?.1 == surfaceID)
  }

  @Test(.dependencies) func notificationReplyIgnoresWhitespaceOnlyText() async {
    let sends = LockIsolated(0)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendTextToSurface = { _, _, _, _ in
        sends.withValue { $0 += 1 }
        return true
      }
    }
    store.exhaustivity = .off

    await store.send(
      .systemNotificationReplied(worktreeID: "/tmp/repo", surfaceID: UUID(), text: "   \n  ")
    )
    await store.finish()

    #expect(sends.value == 0)
  }

  @Test(.dependencies) func notificationAnswerSendsKeypressToOriginatingPane() async {
    let repoRoot = "/tmp/answer-repo"
    let worktree = Worktree(
      id: repoRoot,
      name: "main",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: repoRoot),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
    let repository = Repository(
      id: repoRoot,
      rootURL: URL(fileURLWithPath: repoRoot),
      name: "alpha",
      worktrees: IdentifiedArrayOf(uniqueElements: [worktree])
    )
    var initialState = AppFeature.State()
    initialState.repositories.repositories = [repository]

    let surfaceID = UUID()
    let keys = LockIsolated<[(Worktree.ID, UUID, String)]>([])
    let markReads = LockIsolated<[(Worktree.ID, UUID)]>([])
    let store = TestStore(initialState: initialState) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendKeyToken = { worktree, targetSurfaceID, token in
        keys.withValue { $0.append((worktree.id, targetSurfaceID, token)) }
        return true
      }
      $0.terminalClient.markNotificationsReadForSurface = { worktreeID, targetSurfaceID in
        markReads.withValue { $0.append((worktreeID, targetSurfaceID)) }
      }
    }
    store.exhaustivity = .off

    // A quick-answer button delivers the option's digit as a keypress to the pane.
    await store.send(
      .systemNotificationAnswered(worktreeID: repoRoot, surfaceID: surfaceID, key: "1")
    )
    await store.finish()

    #expect(keys.value.count == 1)
    #expect(keys.value.first?.0 == repoRoot)
    #expect(keys.value.first?.1 == surfaceID)
    #expect(keys.value.first?.2 == "1")
    // On success the originating pane's notifications are marked read.
    #expect(markReads.value.count == 1)
    #expect(markReads.value.first?.0 == repoRoot)
    #expect(markReads.value.first?.1 == surfaceID)
  }

  @Test(.dependencies) func notificationReplyWarnsWhenWorktreeMissing() async {
    // The originating worktree vanished between banner and reply: surface a warning
    // toast and never touch the terminal client.
    let sends = LockIsolated(0)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendTextToSurface = { _, _, _, _ in
        sends.withValue { $0 += 1 }
        return true
      }
    }
    store.exhaustivity = .off

    await store.send(
      .systemNotificationReplied(worktreeID: "/tmp/gone", surfaceID: UUID(), text: "ship it")
    )
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .warning("Reply not sent — that agent is no longer available")
    }

    #expect(sends.value == 0)
  }

  @Test(.dependencies) func notificationReplyWarnsWhenPaneClosed() async {
    // The pane closed between banner and reply (client returns false): surface a
    // warning toast and do NOT mark the notifications read.
    let repoRoot = "/tmp/reply-closed-repo"
    let markReads = LockIsolated(0)
    let store = TestStore(initialState: singleWorktreeState(repoRoot: repoRoot)) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendTextToSurface = { _, _, _, _ in false }
      $0.terminalClient.markNotificationsReadForSurface = { _, _ in
        markReads.withValue { $0 += 1 }
      }
    }
    store.exhaustivity = .off

    await store.send(
      .systemNotificationReplied(worktreeID: repoRoot, surfaceID: UUID(), text: "ship it")
    )
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .warning("Reply not sent — the agent pane is no longer open")
    }

    #expect(markReads.value == 0)
  }

  @Test(.dependencies) func notificationAnswerWarnsWhenWorktreeMissing() async {
    // The originating worktree vanished before the answer: surface a warning toast
    // and never send a keypress.
    let keys = LockIsolated(0)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendKeyToken = { _, _, _ in
        keys.withValue { $0 += 1 }
        return true
      }
    }
    store.exhaustivity = .off

    await store.send(
      .systemNotificationAnswered(worktreeID: "/tmp/gone", surfaceID: UUID(), key: "1")
    )
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .warning("Answer not sent — that agent is no longer available")
    }

    #expect(keys.value == 0)
  }

  @Test(.dependencies) func notificationAnswerWarnsWhenPaneClosed() async {
    // The pane closed before the answer (client returns false): surface a warning
    // toast and do NOT mark the notifications read.
    let repoRoot = "/tmp/answer-closed-repo"
    let markReads = LockIsolated(0)
    let store = TestStore(initialState: singleWorktreeState(repoRoot: repoRoot)) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendKeyToken = { _, _, _ in false }
      $0.terminalClient.markNotificationsReadForSurface = { _, _ in
        markReads.withValue { $0 += 1 }
      }
    }
    store.exhaustivity = .off

    await store.send(
      .systemNotificationAnswered(worktreeID: repoRoot, surfaceID: UUID(), key: "1")
    )
    await store.receive(\.repositories.showToast) {
      $0.repositories.statusToast = .warning("Answer not sent — the agent pane is no longer open")
    }

    #expect(markReads.value == 0)
  }

  /// A single-repository app state whose repo is itself a worktree (`repoRoot`),
  /// so `worktree(for: repoRoot)` resolves — used by the pane-closed tests.
  private func singleWorktreeState(repoRoot: String) -> AppFeature.State {
    let worktree = Worktree(
      id: repoRoot,
      name: "main",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: repoRoot),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
    let repository = Repository(
      id: repoRoot,
      rootURL: URL(fileURLWithPath: repoRoot),
      name: "alpha",
      worktrees: IdentifiedArrayOf(uniqueElements: [worktree])
    )
    var state = AppFeature.State()
    state.repositories.repositories = [repository]
    return state
  }
}
