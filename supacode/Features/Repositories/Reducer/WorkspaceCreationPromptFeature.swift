import ComposableArchitecture
import Foundation
import IdentifiedCollections

@Reducer
struct WorkspaceCreationPromptFeature {
  @ObservableState
  struct State: Equatable {
    var repositories: IdentifiedArrayOf<ProjectWorkspaceCreationRepository>
    var title: String
    var rootPath: String
    var selectedRepositoryIDs: Set<Repository.ID>
    var validationMessage: String?
    var isCreating = false

    var selectedRepositoryCount: Int {
      repositories.count { selectedRepositoryIDs.contains($0.id) }
    }

    var selectedRepositories: [ProjectWorkspaceCreationRepository] {
      repositories.filter { selectedRepositoryIDs.contains($0.id) }
    }

    var rootPathPreview: String {
      PathPolicy.normalizePath(rootPath, resolvingSymlinks: false) ?? rootPath
    }

    init(
      repositories: [ProjectWorkspaceCreationRepository],
      title: String,
      rootPath: String,
      selectedRepositoryIDs: Set<Repository.ID>
    ) {
      self.repositories = IdentifiedArray(repositories, uniquingIDsWith: { current, _ in current })
      self.title = title
      self.rootPath = rootPath
      self.selectedRepositoryIDs = selectedRepositoryIDs
    }
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case addBlankRepository(ProjectWorkspaceRepositorySourceKind)
    case addRepositoryFromURL(ProjectWorkspaceRepositorySourceKind, String)
    case removeRepository(Repository.ID)
    case repositorySelectionChanged(Repository.ID, Bool)
    case repositorySourceKindChanged(Repository.ID, ProjectWorkspaceRepositorySourceKind)
    case repositoryNameChanged(Repository.ID, String)
    case repositoryPathChanged(Repository.ID, String)
    case repositorySourceChosen(Repository.ID, String)
    case repositorySourceLocationChanged(Repository.ID, String)
    case repositoryBranchNameChanged(Repository.ID, String)
    case repositoryBaseRefChanged(Repository.ID, String)
    case rootPathChosen(String)
    case cancelButtonTapped
    case createButtonTapped
    case setCreating(Bool)
    case setValidationMessage(String?)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case baseRefSourceChanged(Repository.ID)
    case cancel
    case submit(ProjectWorkspaceCreationDraft)
  }

  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.validationMessage = nil
        return .none

      case .addBlankRepository(let sourceKind):
        let id = uuid().uuidString
        state.repositories.append(
          ProjectWorkspaceCreationRepository(
            id: id,
            name: "",
            sourceKind: sourceKind,
            sourceLocation: ""
          )
        )
        state.selectedRepositoryIDs.insert(id)
        state.validationMessage = nil
        return .none

      case .addRepositoryFromURL(let sourceKind, let path):
        guard let rootPath = PathPolicy.normalizePath(path) else {
          state.validationMessage =
            ProjectWorkspaceCreationError.missingRepositorySource("repository").localizedDescription
          return .none
        }
        let url = URL(fileURLWithPath: rootPath).standardizedFileURL
        let id = uuid().uuidString
        state.repositories.append(
          ProjectWorkspaceCreationRepository(
            id: id,
            name: Repository.name(for: url),
            sourceKind: sourceKind,
            sourceLocation: rootPath
          )
        )
        state.selectedRepositoryIDs.insert(id)
        state.validationMessage = nil
        return .send(.delegate(.baseRefSourceChanged(id)))

      case .removeRepository(let repositoryID):
        state.repositories.remove(id: repositoryID)
        state.selectedRepositoryIDs.remove(repositoryID)
        state.validationMessage = nil
        return .none

      case .repositorySelectionChanged(let repositoryID, let isSelected):
        if isSelected {
          state.selectedRepositoryIDs.insert(repositoryID)
        } else {
          state.selectedRepositoryIDs.remove(repositoryID)
        }
        state.validationMessage = nil
        return .none

      case .repositorySourceKindChanged(let repositoryID, let sourceKind):
        guard var repository = state.repositories[id: repositoryID] else {
          return .none
        }
        repository.sourceKind = sourceKind
        repository.baseRef = nil
        if sourceKind == .remote {
          repository.sourceLocation = ""
        } else {
          repository.baseRefOptions = []
        }
        state.repositories[id: repositoryID] = repository
        state.validationMessage = nil
        guard sourceKind != .remote, repository.localSourceURL != nil else {
          return .none
        }
        return .send(.delegate(.baseRefSourceChanged(repositoryID)))

      case .repositoryNameChanged(let repositoryID, let name):
        state.repositories[id: repositoryID]?.name = name
        state.validationMessage = nil
        return .none

      case .repositoryPathChanged(let repositoryID, let path):
        state.repositories[id: repositoryID]?.path = path
        state.validationMessage = nil
        return .none

      case .repositorySourceChosen(let repositoryID, let sourceLocation):
        guard let rootPath = PathPolicy.normalizePath(sourceLocation) else {
          state.validationMessage =
            ProjectWorkspaceCreationError.missingRepositorySource("repository").localizedDescription
          return .none
        }
        guard var repository = state.repositories[id: repositoryID] else {
          return .none
        }
        repository.sourceLocation = rootPath
        if repository.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          repository.name = Repository.name(for: URL(fileURLWithPath: rootPath))
        }
        repository.baseRef = nil
        repository.baseRefOptions = []
        state.repositories[id: repositoryID] = repository
        state.validationMessage = nil
        return .send(.delegate(.baseRefSourceChanged(repositoryID)))

      case .repositorySourceLocationChanged(let repositoryID, let sourceLocation):
        state.repositories[id: repositoryID]?.sourceLocation = sourceLocation
        state.validationMessage = nil
        return .none

      case .repositoryBranchNameChanged(let repositoryID, let branchName):
        state.repositories[id: repositoryID]?.branchName = branchName
        state.validationMessage = nil
        return .none

      case .repositoryBaseRefChanged(let repositoryID, let baseRef):
        guard var repository = state.repositories[id: repositoryID] else {
          return .none
        }
        let trimmed = baseRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || repository.baseRefOptions.contains(trimmed) else {
          return .none
        }
        repository.baseRef = trimmed.isEmpty ? nil : trimmed
        state.repositories[id: repositoryID] = repository
        state.validationMessage = nil
        return .none

      case .rootPathChosen(let path):
        state.rootPath = path
        state.validationMessage = nil
        return .none

      case .cancelButtonTapped:
        return .send(.delegate(.cancel))

      case .createButtonTapped:
        let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
          state.validationMessage = ProjectWorkspaceCreationError.missingTitle.localizedDescription
          return .none
        }
        guard let rootPath = PathPolicy.normalizePath(state.rootPath, resolvingSymlinks: false) else {
          state.validationMessage = ProjectWorkspaceCreationError.missingPath.localizedDescription
          return .none
        }
        let repositories = state.selectedRepositories
        guard repositories.count >= 2 else {
          state.validationMessage = ProjectWorkspaceCreationError.notEnoughRepositories.localizedDescription
          return .none
        }
        for repository in repositories {
          let name = repository.name.trimmingCharacters(in: .whitespacesAndNewlines)
          let sourceLocation = repository.sourceLocation.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !sourceLocation.isEmpty else {
            let displayName = name.isEmpty ? "repository" : name
            state.validationMessage =
              ProjectWorkspaceCreationError.missingRepositorySource(displayName).localizedDescription
            return .none
          }
        }
        state.validationMessage = nil
        return .send(
          .delegate(
            .submit(
              ProjectWorkspaceCreationDraft(
                title: title,
                rootURL: URL(filePath: rootPath, directoryHint: .isDirectory),
                repositories: repositories
              )
            )
          )
        )

      case .setCreating(let isCreating):
        state.isCreating = isCreating
        return .none

      case .setValidationMessage(let message):
        state.validationMessage = message
        return .none

      case .delegate:
        return .none
      }
    }
  }
}
