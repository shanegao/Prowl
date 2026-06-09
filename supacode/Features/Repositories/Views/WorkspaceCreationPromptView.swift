import AppKit
import ComposableArchitecture
import SwiftUI

struct WorkspaceCreationPromptView: View {
  @Bindable var store: StoreOf<WorkspaceCreationPromptFeature>
  @FocusState private var isTitleFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("New Workspace")
          .font(.title3)
        Text("\(store.selectedRepositoryCount) of \(store.candidates.count) repositories selected")
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Title")
          .foregroundStyle(.secondary)
        TextField("Workspace title", text: $store.title)
          .textFieldStyle(.roundedBorder)
          .focused($isTitleFieldFocused)
          .disabled(store.isCreating)
          .onSubmit {
            store.send(.createButtonTapped)
          }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Folder")
          .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          TextField("Workspace folder", text: $store.rootPath)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .disabled(store.isCreating)
          Button {
            chooseFolder()
          } label: {
            Label("Choose Folder", systemImage: "folder")
          }
          .help("Choose Workspace Folder")
          .disabled(store.isCreating)
        }
        Text(store.rootPathPreview)
          .font(.footnote.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Repositories")
          .foregroundStyle(.secondary)
        ScrollView {
          VStack(spacing: 0) {
            ForEach(store.candidates) { repository in
              repositoryToggle(repository)
              if repository.id != store.candidates.last?.id {
                Divider()
              }
            }
          }
        }
        .frame(maxHeight: 220)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
      }

      if let message = store.validationMessage, !message.isEmpty {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      HStack {
        if store.isCreating {
          ProgressView()
            .controlSize(.small)
        }
        Spacer()
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .keyboardShortcut(.cancelAction)
        .help("Cancel (Esc)")
        .disabled(store.isCreating)
        Button("Create") {
          store.send(.createButtonTapped)
        }
        .keyboardShortcut(.defaultAction)
        .help("Create Workspace (↩)")
        .disabled(store.isCreating)
      }
    }
    .padding(20)
    .frame(minWidth: 520)
    .task {
      isTitleFieldFocused = true
    }
  }

  private func repositoryToggle(_ repository: ProjectWorkspaceCreationRepository) -> some View {
    Toggle(
      isOn: Binding(
        get: { store.selectedRepositoryIDs.contains(repository.id) },
        set: { store.send(.repositorySelectionChanged(repository.id, $0)) }
      )
    ) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(repository.name)
            .fontWeight(.medium)
          if let branchName = repository.branchName {
            Text(branchName)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
          }
        }
        Text(repository.rootURL.path(percentEncoded: false))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .toggleStyle(.checkbox)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.directoryURL = URL(filePath: store.rootPath).deletingLastPathComponent()
    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        return
      }
      store.send(.rootPathChosen(url.path(percentEncoded: false)))
    }
  }
}
