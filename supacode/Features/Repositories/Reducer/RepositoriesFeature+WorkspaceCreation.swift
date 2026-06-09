import ComposableArchitecture
import Foundation

extension RepositoriesFeature.State {
  var canCreateWorkspace: Bool {
    true
  }

  var workspaceCreationCandidates: [ProjectWorkspaceCreationRepository] {
    repositories.compactMap { repository in
      guard !repository.isWorkspace, !removingRepositoryIDs.contains(repository.id) else {
        return nil
      }
      let name = repositoryCustomTitles[repository.id] ?? repository.name
      return ProjectWorkspaceCreationRepository(
        id: repository.id,
        name: name,
        rootURL: repository.rootURL,
        branchName: repository.worktrees.first(where: \.isMain)?.name
      )
    }
  }
}

extension RepositoriesFeature {
  func reduceWorkspaceCreation(
    state: inout State,
    action: WorkspaceCreationAction
  ) -> Effect<Action> {
    switch action {
    case .promptRequested:
      let candidates = state.workspaceCreationCandidates
      let title = workspaceCreationDefaultTitle(candidates: candidates)
      state.workspaceCreationPrompt = WorkspaceCreationPromptFeature.State(
        repositories: candidates,
        title: title,
        rootPath: defaultWorkspaceRootURL(title: title).path(percentEncoded: false),
        selectedRepositoryIDs: Set(candidates.map(\.id))
      )
      return .none

    case .promptCanceled, .promptDismissed:
      state.workspaceCreationPrompt = nil
      return .cancel(id: CancelID.workspaceCreation)

    case .createWorkspace(let draft):
      state.workspaceCreationPrompt?.isCreating = true
      state.workspaceCreationPrompt?.validationMessage = nil
      let request = ProjectWorkspaceCreationRequest(draft: draft, createdAt: now)
      let shellClient = shellClient
      let gitRunner = ProjectWorkspaceGitRunner { command in
        do {
          _ = try await shellClient.run(
            URL(fileURLWithPath: "/usr/bin/env"),
            ["git"] + command.arguments,
            command.currentDirectoryURL
          )
        } catch let error as ShellClientError {
          throw ProjectWorkspaceCreationError.gitCommandFailed(
            command: command.displayCommand,
            message: error.stderr.isEmpty ? error.stdout : error.stderr
          )
        } catch {
          throw error
        }
      }
      return .run { send in
        do {
          _ = try await ProjectWorkspace.create(request, gitRunner: gitRunner)
          await send(.workspaceCreation(.workspaceCreated(request.draft.rootURL)))
        } catch {
          await send(.workspaceCreation(.workspaceCreationFailed(error.localizedDescription)))
        }
      }
      .cancellable(id: CancelID.workspaceCreation, cancelInFlight: true)

    case .workspaceCreated(let rootURL):
      analyticsClient.capture("workspace_created", [String: Any]?.none)
      state.workspaceCreationPrompt = nil
      return .merge(
        .send(.showToast(.success("Workspace created"))),
        .send(.repositoryManagement(.openRepositories([rootURL])))
      )

    case .workspaceCreationFailed(let message):
      if state.workspaceCreationPrompt != nil {
        state.workspaceCreationPrompt?.isCreating = false
        state.workspaceCreationPrompt?.validationMessage = message
      } else {
        state.alert = messageAlert(title: "Unable to create workspace", message: message)
      }
      return .none
    }
  }

  var workspaceCreationReducer: some ReducerOf<Self> {
    Reduce { state, action in
      guard case .workspaceCreation(let action) = action else {
        return .none
      }
      return reduceWorkspaceCreation(state: &state, action: action)
    }
  }

  private func workspaceCreationDefaultTitle(candidates: [ProjectWorkspaceCreationRepository]) -> String {
    let names = candidates.map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if names.isEmpty {
      return "Workspace"
    }
    if names.count <= 3 {
      return names.joined(separator: " + ")
    }
    guard let first = names.first else {
      return "Workspace"
    }
    return "\(first) + \(names.count - 1) repos"
  }

  private func defaultWorkspaceRootURL(title: String) -> URL {
    let folderName = ProjectWorkspace.defaultWorkspaceFolderName(for: title)
    let baseURL = SupacodePaths.workspacesDirectory
    var candidateURL = baseURL.appending(path: folderName, directoryHint: .isDirectory)
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidateURL.path(percentEncoded: false)) {
      candidateURL = baseURL.appending(path: "\(folderName)-\(suffix)", directoryHint: .isDirectory)
      suffix += 1
    }
    return candidateURL.standardizedFileURL
  }
}
