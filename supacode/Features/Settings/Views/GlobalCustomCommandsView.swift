import ComposableArchitecture
import SwiftUI

struct GlobalCustomCommandsView: View {
  @Bindable var store: StoreOf<GlobalCustomCommandsFeature>

  var body: some View {
    Form {
      Section {
        Text("Global commands are available in every repository. A local command with the same title takes precedence.")
          .foregroundStyle(.secondary)
      }

      Section {
        if store.settings.customCommands.isEmpty {
          ContentUnavailableView("No Global Commands", systemImage: "globe")
            .frame(maxWidth: .infinity)
        } else {
          ForEach($store.settings.customCommands) { $command in
            GlobalCustomCommandRow(command: $command)
          }
          .onDelete { store.send(.removeCommands($0)) }
        }
        Button("Add Command", systemImage: "plus") {
          store.send(.addCommand)
        }
        .help("Add global custom command")
      } header: {
        Text("Commands")
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task { store.send(.task) }
  }
}

private struct GlobalCustomCommandRow: View {
  @Binding var command: UserCustomCommand

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Title", text: $command.title)
        TextField("Symbol", text: $command.systemImage)
          .frame(width: 160)
      }
      TextField("Command", text: $command.command, axis: .vertical)
        .lineLimit(2...5)
        .font(.body.monospaced())
      Picker("Run", selection: $command.execution) {
        ForEach(UserCustomCommandExecution.allCases) { execution in
          Text(execution.title).tag(execution)
        }
      }
      if command.execution == .split {
        Picker("Split", selection: $command.splitDirection) {
          ForEach(UserCustomSplitDirection.allCases) { direction in
            Text(direction.title).tag(direction)
          }
        }
      }
      if command.execution.supportsCloseOnSuccess {
        Toggle("Close terminal after success", isOn: $command.closeOnSuccess)
      }
      HStack {
        TextField("Shortcut key", text: shortcutKey)
          .frame(width: 120)
        Toggle("⌘", isOn: shortcutModifier(\.command))
        Toggle("⇧", isOn: shortcutModifier(\.shift))
        Toggle("⌥", isOn: shortcutModifier(\.option))
        Toggle("⌃", isOn: shortcutModifier(\.control))
      }
      .font(.caption)
    }
    .padding(.vertical, 4)
  }

  private var shortcutKey: Binding<String> {
    Binding(
      get: { command.shortcut?.key ?? "" },
      set: { key in
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          command.shortcut = nil
          return
        }
        command.shortcut = UserCustomShortcut(
          key: key,
          modifiers: command.shortcut?.modifiers ?? .init()
        )
      }
    )
  }

  private func shortcutModifier(
    _ keyPath: WritableKeyPath<UserCustomShortcutModifiers, Bool>
  ) -> Binding<Bool> {
    Binding(
      get: { command.shortcut?.modifiers[keyPath: keyPath] ?? (keyPath == \.command) },
      set: { value in
        var modifiers = command.shortcut?.modifiers ?? .init()
        modifiers[keyPath: keyPath] = value
        command.shortcut = UserCustomShortcut(key: command.shortcut?.key ?? "", modifiers: modifiers)
      }
    )
  }
}
