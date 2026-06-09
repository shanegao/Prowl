import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct ProjectWorkspaceTests {
  @Test func loadsWorkspaceMetadataWithDefaultsAndSnakeCaseSources() throws {
    let rootURL = try makeTemporaryWorkspaceRoot()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    try writeWorkspaceJSON(
      """
      {
        "title": "Multi Repo Task",
        "repositories": [
          {
            "role": "backend",
            "path": "api",
            "source_kind": "bare_repository",
            "source_location": "/Users/mikoto/Repos/api.git",
            "branch_name": "feature/workspace"
          },
          {
            "id": "web",
            "name": "Web",
            "path": "/tmp/web",
            "source_kind": "remote",
            "source_location": "git@github.com:onevcat/web.git"
          },
          {
            "name": "Shared",
            "path": "shared"
          }
        ]
      }
      """,
      to: rootURL
    )

    let workspace = try #require(ProjectWorkspace.load(from: rootURL))
    let rootPath = rootURL.standardizedFileURL.path(percentEncoded: false)

    #expect(workspace.id == rootPath)
    #expect(workspace.title == "Multi Repo Task")
    #expect(workspace.description == "")
    #expect(workspace.taskLinks == [])
    try #require(workspace.repositories.count == 3)

    let api = workspace.repositories[0]
    #expect(api.id == "api")
    #expect(api.name == "api")
    #expect(api.role == "backend")
    #expect(api.sourceKind == .bareRepository)
    #expect(api.sourceLocation == "/Users/mikoto/Repos/api.git")
    #expect(api.branchName == "feature/workspace")
    #expect(
      api.resolvedURL(relativeTo: rootURL).path(percentEncoded: false)
        == rootURL.appending(path: "api").standardizedFileURL.path(percentEncoded: false)
    )

    let web = workspace.repositories[1]
    #expect(web.id == "web")
    #expect(web.name == "Web")
    #expect(web.sourceKind == .remote)
    #expect(
      web.resolvedURL(relativeTo: rootURL).path(percentEncoded: false)
        == URL(fileURLWithPath: "/tmp/web").standardizedFileURL.path(percentEncoded: false)
    )

    let shared = workspace.repositories[2]
    #expect(shared.id == "shared")
    #expect(shared.name == "Shared")
    #expect(shared.sourceKind == .existingPath)
  }

  @Test func normalizesEmptyWorkspaceAndRepositoryFields() throws {
    let rootURL = URL(fileURLWithPath: "/tmp/prowl-workspace")

    let workspace = ProjectWorkspace(
      id: " ",
      title: " ",
      description: "  Touch app and API together  ",
      taskLinks: [" https://github.com/onevcat/Prowl/issues/1 ", " "],
      repositories: [
        ProjectWorkspace.RepositoryEntry(
          id: " ",
          name: " ",
          role: " ",
          path: " app ",
          sourceKind: .localRepository,
          sourceLocation: " ",
          branchName: " feature/workspace ",
          baseRef: " "
        )
      ]
    )
    .normalized(relativeTo: rootURL)

    #expect(workspace.id == "/tmp/prowl-workspace")
    #expect(workspace.title == "prowl-workspace")
    #expect(workspace.description == "Touch app and API together")
    #expect(workspace.taskLinks == ["https://github.com/onevcat/Prowl/issues/1"])

    let entry = try #require(workspace.repositories.first)
    #expect(entry.id == "app")
    #expect(entry.name == "app")
    #expect(entry.role == nil)
    #expect(entry.sourceKind == .localRepository)
    #expect(entry.sourceLocation == nil)
    #expect(entry.branchName == "feature/workspace")
    #expect(entry.baseRef == nil)
  }

  @Test func repositoryEntryNormalizerKeepsWorkspacePathPlain() throws {
    let rootURL = try makeTemporaryWorkspaceRoot()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    try writeWorkspaceJSON("{}", to: rootURL)

    let rootPath = rootURL.standardizedFileURL.path(percentEncoded: false)
    let normalized = RepositoryEntryNormalizer.normalize([
      PersistedRepositoryEntry(path: rootPath, kind: .git)
    ])

    #expect(normalized == [PersistedRepositoryEntry(path: rootPath, kind: .plain)])
  }

  @Test func createWorkspaceWritesMetadataAndRepositoryLinks() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appending(path: "prowl-created-workspace-\(UUID().uuidString)")
      .standardizedFileURL
    let appURL = try makeTemporaryWorkspaceRoot()
    let apiURL = try makeTemporaryWorkspaceRoot()
    defer {
      try? FileManager.default.removeItem(at: rootURL)
      try? FileManager.default.removeItem(at: appURL)
      try? FileManager.default.removeItem(at: apiURL)
    }
    let createdAt = Date(timeIntervalSince1970: 1_234_567)
    let workspace = try await ProjectWorkspace.create(
      ProjectWorkspaceCreationRequest(
        draft: ProjectWorkspaceCreationDraft(
          title: "Checkout Flow",
          rootURL: rootURL,
          repositories: [
            ProjectWorkspaceCreationRepository(
              id: "app",
              name: "App Repo",
              rootURL: appURL,
              branchName: "main"
            ),
            ProjectWorkspaceCreationRepository(
              id: "api",
              name: "App Repo",
              rootURL: apiURL,
              branchName: "feature/api"
            ),
          ]
        ),
        createdAt: createdAt
      ),
      gitRunner: ProjectWorkspaceGitRunner { command in
        throw ProjectWorkspaceCreationError.gitCommandFailed(command: command.displayCommand, message: "unexpected")
      }
    )

    #expect(workspace.title == "Checkout Flow")
    #expect(workspace.createdAt == createdAt)
    let loaded = try #require(ProjectWorkspace.load(from: rootURL))
    #expect(loaded.repositories.map(\.path) == ["App-Repo", "App-Repo-2"])
    #expect(loaded.repositories.map(\.sourceKind) == [.existingPath, .existingPath])
    let appPath = normalizedTestPath(appURL)
    let apiPath = normalizedTestPath(apiURL)
    #expect(
      loaded.repositories.map(\.sourceLocation) == [
        appPath,
        apiPath,
      ])
    #expect(loaded.repositories.map(\.branchName) == ["main", "feature/api"])

    let appLinkPath = rootURL.appending(path: "App-Repo").path(percentEncoded: false)
    let apiLinkPath = rootURL.appending(path: "App-Repo-2").path(percentEncoded: false)
    #expect(URL(fileURLWithPath: appLinkPath).resolvingSymlinksInPath().path(percentEncoded: false) == appPath)
    #expect(URL(fileURLWithPath: apiLinkPath).resolvingSymlinksInPath().path(percentEncoded: false) == apiPath)
  }

  @Test func createWorkspaceMaterializesRemoteCloneAndBareWorktree() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appending(path: "prowl-materialized-workspace-\(UUID().uuidString)")
      .standardizedFileURL
    let bareURL = try makeTemporaryWorkspaceRoot()
    defer {
      try? FileManager.default.removeItem(at: rootURL)
      try? FileManager.default.removeItem(at: bareURL)
    }
    let commands = LockIsolated<[ProjectWorkspaceGitCommand]>([])
    let workspace = try await ProjectWorkspace.create(
      ProjectWorkspaceCreationRequest(
        draft: ProjectWorkspaceCreationDraft(
          title: "Materialized",
          rootURL: rootURL,
          repositories: [
            ProjectWorkspaceCreationRepository(
              id: "app",
              name: "App",
              sourceKind: .remote,
              sourceLocation: "git@github.com:onevcat/app.git",
              branchName: "codex/app",
              baseRef: "origin/main",
              path: "app"
            ),
            ProjectWorkspaceCreationRepository(
              id: "api",
              name: "API",
              sourceKind: .bareRepository,
              sourceLocation: bareURL.path(percentEncoded: false),
              branchName: "codex/api",
              baseRef: "main",
              path: "api"
            ),
          ]
        ),
        createdAt: Date(timeIntervalSince1970: 2_345_678)
      ),
      gitRunner: ProjectWorkspaceGitRunner { command in
        commands.withValue { $0.append(command) }
      }
    )

    #expect(workspace.repositories.map(\.path) == ["app", "api"])
    #expect(workspace.repositories.map(\.sourceKind) == [.remote, .bareRepository])
    let rootPath = rootURL.path(percentEncoded: false)
    let barePath = normalizedTestPath(bareURL)
    #expect(
      commands.value.map(\.arguments) == [
        ["clone", "git@github.com:onevcat/app.git", "\(rootPath)/app"],
        ["-C", "\(rootPath)/app", "checkout", "-B", "codex/app", "origin/main"],
        ["-C", barePath, "worktree", "add", "-b", "codex/api", "\(rootPath)/api", "main"],
      ])

    let loaded = try #require(ProjectWorkspace.load(from: rootURL))
    #expect(loaded.repositories.map(\.sourceLocation) == ["git@github.com:onevcat/app.git", barePath])
    #expect(loaded.repositories.map(\.branchName) == ["codex/app", "codex/api"])
    #expect(loaded.repositories.map(\.baseRef) == ["origin/main", "main"])
  }

  @Test func listRuntimeContextsReportWorkspaceKind() {
    let rootURL = URL(fileURLWithPath: "/tmp/workspace")
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "Workspace",
      kind: .plain,
      worktrees: [],
      workspace: ProjectWorkspace(title: "Workspace")
    )
    var state = RepositoriesFeature.State()
    state.repositories = [repository]
    state.repositoryRoots = [rootURL]

    let contexts = ListRuntimeSnapshotBuilder.orderedWorktreeContexts(from: state)

    #expect(contexts.map(\.kind) == [.workspace])
    #expect(contexts.first?.id == repository.id)
  }

  private func makeTemporaryWorkspaceRoot() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
      .appending(path: "prowl-workspace-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
  }

  private func writeWorkspaceJSON(_ json: String, to rootURL: URL) throws {
    let metadataDirectoryURL = rootURL.appending(path: ProjectWorkspace.metadataDirectoryName)
    try FileManager.default.createDirectory(at: metadataDirectoryURL, withIntermediateDirectories: true)
    try Data(json.utf8).write(to: ProjectWorkspace.metadataURL(for: rootURL))
  }

  private func normalizedTestPath(_ url: URL) -> String {
    var path = PathPolicy.normalizeURL(url).path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return path
  }
}
