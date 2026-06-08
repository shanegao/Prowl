import ComposableArchitecture
import Foundation

@Reducer
struct GlobalCommandsFeature {
  @ObservableState
  struct State: Equatable {
    var commands: [UserCustomCommand]

    init(commands: [UserCustomCommand] = []) {
      self.commands = UserRepositorySettings.normalizedCommands(commands)
    }
  }

  enum Action: BindableAction {
    case delegate(Delegate)
    case binding(BindingAction<State>)
    case exportButtonTapped
    case importButtonTapped
    /// Effect output: commands successfully decoded from a chosen import
    /// file. Reducer merges them into `state.commands` here. Failure and
    /// cancellation never produce this action — the import client
    /// surfaces errors via `NSAlert` and returns nil.
    case importCompleted([UserCustomCommand])
  }

  @CasePathable
  enum Delegate: Equatable {
    case commandsChanged([UserCustomCommand])
  }

  @Dependency(CustomCommandsImportExportClient.self) var importExport

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding(\.commands):
        // Scope to `commands` so future bindable properties don't silently
        // emit `commandsChanged` and re-trigger persistence.
        //
        // Do NOT re-normalize on every binding mutation. Normalizing produces
        // new UserCustomCommand struct identities for every keystroke, which
        // invalidates the SwiftUI TextField <-> AppKit cursor bridge and snaps
        // the cursor to the end. Normalization happens at decode time
        // (UserRepositorySettings.init) and at shortcut commit, which is
        // sufficient — title/command/systemImage edits don't need it.
        return .send(.delegate(.commandsChanged(state.commands)))

      case .binding, .delegate:
        return .none

      case .exportButtonTapped:
        let commands = state.commands
        return .run { _ in
          await importExport.runExport(commands)
        }

      case .importButtonTapped:
        return .run { send in
          guard let imported = await importExport.runImport() else { return }
          await send(.importCompleted(imported))
        }

      case .importCompleted(let imported):
        state.commands = Self.mergeByID(existing: state.commands, imported: imported)
        return .send(.delegate(.commandsChanged(state.commands)))
      }
    }
  }

  /// Append commands whose IDs aren't already present, dropping any
  /// incoming shortcut that collides with an existing one (keep the
  /// command, lose the key). Matches the chosen import UX: non-
  /// destructive, safe to re-import the same file repeatedly. ID
  /// uniqueness is the existence check rather than title because the
  /// title is editable and a user may have intentionally renamed a
  /// command between machines while keeping the same `id`.
  static func mergeByID(
    existing: [UserCustomCommand],
    imported: [UserCustomCommand]
  ) -> [UserCustomCommand] {
    let existingIDs = Set(existing.map(\.id))
    let existingShortcuts: [UserCustomShortcut] = existing.compactMap(\.shortcut)
    var result = existing
    for command in imported where !existingIDs.contains(command.id) {
      var sanitized = command
      if let shortcut = command.shortcut, existingShortcuts.contains(shortcut) {
        sanitized.shortcut = nil
      }
      result.append(sanitized)
    }
    return result
  }
}
