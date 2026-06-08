import ComposableArchitecture
import SwiftUI

struct GlobalCommandsSettingsView: View {
  @Bindable var store: StoreOf<GlobalCommandsFeature>
  let keybindingUserOverrides: KeybindingUserOverrideStore

  var body: some View {
    Form {
      Section {
        CustomCommandsEditorView(
          commands: $store.commands,
          keybindingUserOverrides: keybindingUserOverrides
        )
      } header: {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Global Commands")
            Text(
              "Available in every worktree. Repository-local custom commands take precedence on shortcut conflicts."
            )
            .foregroundStyle(.secondary)
          }
          Spacer()
          // Import always available — even with zero commands the user
          // may want to seed from a file. Export disabled when there's
          // nothing to write so the save panel can't produce an empty
          // export file accidentally.
          Button("Import…") {
            store.send(.importButtonTapped)
          }
          .help("Merge commands from a Prowl JSON export. Existing IDs are kept.")
          Button("Export…") {
            store.send(.exportButtonTapped)
          }
          .disabled(store.commands.isEmpty)
          .help("Save the current commands as a JSON file.")
        }
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
