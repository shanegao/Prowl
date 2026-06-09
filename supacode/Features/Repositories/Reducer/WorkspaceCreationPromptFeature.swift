import ComposableArchitecture
import Foundation

@Reducer
struct WorkspaceCreationPromptFeature {
  @ObservableState
  struct State: Equatable {
    let candidates: [ProjectWorkspaceCreationRepository]
    var title: String
    var rootPath: String
    var selectedRepositoryIDs: Set<Repository.ID>
    var validationMessage: String?
    var isCreating = false

    var selectedRepositoryCount: Int {
      candidates.count { selectedRepositoryIDs.contains($0.id) }
    }

    var selectedRepositories: [ProjectWorkspaceCreationRepository] {
      candidates.filter { selectedRepositoryIDs.contains($0.id) }
    }

    var rootPathPreview: String {
      PathPolicy.normalizePath(rootPath, resolvingSymlinks: false) ?? rootPath
    }
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case repositorySelectionChanged(Repository.ID, Bool)
    case rootPathChosen(String)
    case cancelButtonTapped
    case createButtonTapped
    case setCreating(Bool)
    case setValidationMessage(String?)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case cancel
    case submit(ProjectWorkspaceCreationDraft)
  }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
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
