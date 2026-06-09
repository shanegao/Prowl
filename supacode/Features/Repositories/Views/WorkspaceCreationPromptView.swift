import AppKit
import ComposableArchitecture
import SwiftUI

struct WorkspaceCreationPromptView: View {
  @Bindable var store: StoreOf<WorkspaceCreationPromptFeature>
  @FocusState private var isTitleFieldFocused: Bool
  private let sourceKinds: [ProjectWorkspaceRepositorySourceKind] = [
    .existingPath,
    .localRepository,
    .remote,
    .bareRepository,
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("New Workspace")
          .font(.title3)
        Text("\(store.selectedRepositoryCount) of \(store.repositories.count) repositories selected")
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
        HStack(spacing: 8) {
          Button {
            store.send(.addBlankRepository(.remote))
          } label: {
            Label("Add Remote", systemImage: "network")
          }
          .help("Add Remote Repository")
          .disabled(store.isCreating)

          Button {
            chooseRepositorySource(kind: .localRepository)
          } label: {
            Label("Add Local", systemImage: "folder")
          }
          .help("Add Local Repository")
          .disabled(store.isCreating)

          Button {
            chooseRepositorySource(kind: .bareRepository)
          } label: {
            Label("Add Bare", systemImage: "externaldrive")
          }
          .help("Add Bare Repository")
          .disabled(store.isCreating)
        }
        ScrollView {
          VStack(spacing: 0) {
            ForEach(store.repositories) { repository in
              repositoryEditor(repository)
              if repository.id != store.repositories.last?.id {
                Divider()
              }
            }
          }
        }
        .frame(maxHeight: 340)
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
    .frame(minWidth: 680)
    .task {
      isTitleFieldFocused = true
    }
  }

  private func repositoryEditor(_ repository: ProjectWorkspaceCreationRepository) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      repositoryHeader(repository)
      repositoryNameAndPathFields(repository)
      repositorySourceField(repository)
      repositoryBranchFields(repository)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
  }

  private func repositoryHeader(_ repository: ProjectWorkspaceCreationRepository) -> some View {
    HStack(spacing: 10) {
      Toggle(
        isOn: Binding(
          get: { store.selectedRepositoryIDs.contains(repository.id) },
          set: { store.send(.repositorySelectionChanged(repository.id, $0)) }
        )
      ) {
        Text(repository.name.isEmpty ? "Repository" : repository.name)
          .fontWeight(.medium)
      }
      .toggleStyle(.checkbox)

      Picker(
        "Source",
        selection: Binding(
          get: { repository.sourceKind },
          set: { store.send(.repositorySourceKindChanged(repository.id, $0)) }
        )
      ) {
        ForEach(sourceKinds, id: \.self) { kind in
          Text(sourceKindTitle(kind)).tag(kind)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .frame(width: 150)
      .disabled(store.isCreating)

      Spacer()

      Button {
        store.send(.removeRepository(repository.id))
      } label: {
        Image(systemName: "trash")
          .accessibilityLabel("Remove Repository")
      }
      .buttonStyle(.borderless)
      .help("Remove Repository")
      .disabled(store.isCreating)
    }
  }

  private func repositoryNameAndPathFields(_ repository: ProjectWorkspaceCreationRepository) -> some View {
    HStack(spacing: 8) {
      TextField(
        "Name",
        text: Binding(
          get: { repository.name },
          set: { store.send(.repositoryNameChanged(repository.id, $0)) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .disabled(store.isCreating)

      TextField(
        "Workspace path",
        text: Binding(
          get: { repository.path ?? "" },
          set: { store.send(.repositoryPathChanged(repository.id, $0)) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .disabled(store.isCreating)
    }
  }

  private func repositorySourceField(_ repository: ProjectWorkspaceCreationRepository) -> some View {
    HStack(spacing: 8) {
      TextField(
        sourceLocationPlaceholder(repository.sourceKind),
        text: Binding(
          get: { repository.sourceLocation },
          set: { store.send(.repositorySourceLocationChanged(repository.id, $0)) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .font(.body.monospaced())
      .disabled(store.isCreating)

      if repository.sourceKind != .remote {
        Button {
          chooseSource(for: repository)
        } label: {
          Image(systemName: "folder")
            .accessibilityLabel("Choose Repository Source")
        }
        .help("Choose Repository Source")
        .disabled(store.isCreating)
      }
    }
  }

  private func repositoryBranchFields(_ repository: ProjectWorkspaceCreationRepository) -> some View {
    HStack(spacing: 8) {
      TextField(
        "Branch",
        text: Binding(
          get: { repository.branchName ?? "" },
          set: { store.send(.repositoryBranchNameChanged(repository.id, $0)) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .disabled(store.isCreating)

      TextField(
        "Base ref",
        text: Binding(
          get: { repository.baseRef ?? "" },
          set: { store.send(.repositoryBaseRefChanged(repository.id, $0)) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .disabled(store.isCreating)
    }
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

  private func chooseRepositorySource(kind: ProjectWorkspaceRepositorySourceKind) {
    let panel = repositorySourcePanel(kind: kind, currentPath: nil)
    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        return
      }
      store.send(.addRepositoryFromURL(kind, url.path(percentEncoded: false)))
    }
  }

  private func chooseSource(for repository: ProjectWorkspaceCreationRepository) {
    let panel = repositorySourcePanel(kind: repository.sourceKind, currentPath: repository.sourceLocation)
    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        return
      }
      store.send(.repositorySourceLocationChanged(repository.id, url.path(percentEncoded: false)))
    }
  }

  private func repositorySourcePanel(
    kind: ProjectWorkspaceRepositorySourceKind,
    currentPath: String?
  ) -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    if let currentPath, !currentPath.isEmpty {
      panel.directoryURL = URL(filePath: currentPath).deletingLastPathComponent()
    }
    panel.message = kind == .bareRepository ? "Choose a bare repository folder" : "Choose a repository folder"
    return panel
  }

  private func sourceKindTitle(_ kind: ProjectWorkspaceRepositorySourceKind) -> String {
    switch kind {
    case .existingPath:
      return "Opened Path"
    case .localRepository:
      return "Local Repo"
    case .remote:
      return "Remote Clone"
    case .bareRepository:
      return "Bare Worktree"
    }
  }

  private func sourceLocationPlaceholder(_ kind: ProjectWorkspaceRepositorySourceKind) -> String {
    switch kind {
    case .existingPath, .localRepository:
      return "Repository folder"
    case .remote:
      return "Remote URL"
    case .bareRepository:
      return "Bare repository folder"
    }
  }
}
