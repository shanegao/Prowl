import Foundation

nonisolated enum ProjectWorkspaceRepositorySourceKind: String, Codable, Equatable, Hashable, Sendable {
  case remote
  case localRepository = "local_repository"
  case bareRepository = "bare_repository"
  case existingPath = "existing_path"
}

nonisolated struct ProjectWorkspaceCreationRepository: Equatable, Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var path: String?
  var sourceKind: ProjectWorkspaceRepositorySourceKind
  var sourceLocation: String
  var branchName: String?
  var baseRef: String?

  init(
    id: String,
    name: String,
    rootURL: URL,
    branchName: String? = nil,
    path: String? = nil
  ) {
    let normalizedURL = rootURL.standardizedFileURL
    self.id = id
    self.name = name
    self.path = path
    sourceKind = .existingPath
    sourceLocation = normalizedURL.path(percentEncoded: false)
    self.branchName = branchName
    baseRef = nil
  }

  init(
    id: String,
    name: String,
    sourceKind: ProjectWorkspaceRepositorySourceKind,
    sourceLocation: String,
    branchName: String? = nil,
    baseRef: String? = nil,
    path: String? = nil
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.sourceKind = sourceKind
    self.sourceLocation = sourceLocation
    self.branchName = branchName
    self.baseRef = baseRef
  }

  var localSourceURL: URL? {
    switch sourceKind {
    case .existingPath, .localRepository, .bareRepository:
      let trimmed = sourceLocation.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return nil
      }
      return URL(fileURLWithPath: trimmed).standardizedFileURL
    case .remote:
      return nil
    }
  }
}

nonisolated struct ProjectWorkspaceCreationDraft: Equatable, Sendable {
  var title: String
  var rootURL: URL
  var repositories: [ProjectWorkspaceCreationRepository]

  init(
    title: String,
    rootURL: URL,
    repositories: [ProjectWorkspaceCreationRepository]
  ) {
    self.title = title
    self.rootURL = rootURL.standardizedFileURL
    self.repositories = repositories
  }
}

nonisolated struct ProjectWorkspaceCreationRequest: Equatable, Sendable {
  var draft: ProjectWorkspaceCreationDraft
  var createdAt: Date
}

nonisolated struct ProjectWorkspaceGitCommand: Equatable, Sendable {
  var arguments: [String]
  var currentDirectoryURL: URL?

  var displayCommand: String {
    (["git"] + arguments).joined(separator: " ")
  }
}

nonisolated struct ProjectWorkspaceGitRunner: Sendable {
  var run: @Sendable (ProjectWorkspaceGitCommand) async throws -> Void
}

nonisolated enum ProjectWorkspaceCreationError: LocalizedError, Equatable, Sendable {
  case missingTitle
  case missingPath
  case notEnoughRepositories
  case missingRepositoryName
  case missingRepositorySource(String)
  case destinationIsFile(String)
  case workspaceAlreadyExists(String)
  case repositoryDoesNotExist(String)
  case linkAlreadyExists(String)
  case gitCommandFailed(command: String, message: String)

  var errorDescription: String? {
    switch self {
    case .missingTitle:
      return "Workspace title required."
    case .missingPath:
      return "Workspace folder required."
    case .notEnoughRepositories:
      return "Select at least two repositories."
    case .missingRepositoryName:
      return "Repository name required."
    case .missingRepositorySource(let name):
      return "Source required for \(name)."
    case .destinationIsFile(let path):
      return "\(path) is a file. Choose a folder path instead."
    case .workspaceAlreadyExists(let path):
      return "\(path) already contains a Prowl workspace."
    case .repositoryDoesNotExist(let path):
      return "\(path) does not exist."
    case .linkAlreadyExists(let path):
      return "\(path) already exists."
    case .gitCommandFailed(let command, let message):
      if message.isEmpty {
        return "Git command failed: \(command)"
      }
      return "Git command failed: \(command)\n\(message)"
    }
  }
}

nonisolated struct ProjectWorkspaceRepositoryEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var role: String?
  var path: String
  var sourceKind: ProjectWorkspaceRepositorySourceKind
  var sourceLocation: String?
  var branchName: String?
  var baseRef: String?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case role
    case path
    case sourceKind = "source_kind"
    case sourceLocation = "source_location"
    case branchName = "branch_name"
    case baseRef = "base_ref"
  }

  init(
    id: String = "",
    name: String = "",
    role: String? = nil,
    path: String = "",
    sourceKind: ProjectWorkspaceRepositorySourceKind = .existingPath,
    sourceLocation: String? = nil,
    branchName: String? = nil,
    baseRef: String? = nil
  ) {
    self.id = id
    self.name = name
    self.role = role
    self.path = path
    self.sourceKind = sourceKind
    self.sourceLocation = sourceLocation
    self.branchName = branchName
    self.baseRef = baseRef
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    role = try container.decodeIfPresent(String.self, forKey: .role)
    path =
      try container.decodeIfPresent(String.self, forKey: .path)
      ?? name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? id.trimmingCharacters(in: .whitespacesAndNewlines)
    sourceKind =
      try container.decodeIfPresent(ProjectWorkspaceRepositorySourceKind.self, forKey: .sourceKind)
      ?? .existingPath
    sourceLocation = try container.decodeIfPresent(String.self, forKey: .sourceLocation)
    branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
    baseRef = try container.decodeIfPresent(String.self, forKey: .baseRef)
  }

  func resolvedURL(relativeTo workspaceRootURL: URL) -> URL {
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedPath.hasPrefix("/") {
      return URL(fileURLWithPath: trimmedPath).standardizedFileURL
    }
    return workspaceRootURL.appending(path: trimmedPath).standardizedFileURL
  }
}

nonisolated struct ProjectWorkspace: Codable, Equatable, Hashable, Sendable {
  typealias RepositorySourceKind = ProjectWorkspaceRepositorySourceKind
  typealias RepositoryEntry = ProjectWorkspaceRepositoryEntry

  nonisolated static let metadataDirectoryName = ".prowl"
  nonisolated static let metadataFileName = "workspace.json"

  var id: String
  var title: String
  var description: String
  var taskLinks: [String]
  var repositories: [RepositoryEntry]
  var createdAt: Date?
  var updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case description
    case taskLinks = "task_links"
    case repositories
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  init(
    id: String = "",
    title: String = "",
    description: String = "",
    taskLinks: [String] = [],
    repositories: [RepositoryEntry] = [],
    createdAt: Date? = nil,
    updatedAt: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.taskLinks = taskLinks
    self.repositories = repositories
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    taskLinks = try container.decodeIfPresent([String].self, forKey: .taskLinks) ?? []
    repositories = try container.decodeIfPresent([RepositoryEntry].self, forKey: .repositories) ?? []
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
  }

  static func metadataURL(for rootURL: URL) -> URL {
    rootURL
      .appending(path: metadataDirectoryName)
      .appending(path: metadataFileName)
  }

  static func load(from rootURL: URL) -> ProjectWorkspace? {
    let metadataURL = metadataURL(for: rootURL)
    guard let data = try? Data(contentsOf: metadataURL) else {
      return nil
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard var workspace = try? decoder.decode(ProjectWorkspace.self, from: data) else {
      return nil
    }
    let normalizedRoot = rootURL.standardizedFileURL.path(percentEncoded: false)
    if workspace.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      workspace.id = normalizedRoot
    }
    if workspace.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      workspace.title = rootURL.lastPathComponent.isEmpty ? normalizedRoot : rootURL.lastPathComponent
    }
    return workspace.normalized(relativeTo: rootURL)
  }

  func normalized(relativeTo rootURL: URL) -> ProjectWorkspace {
    var copy = self
    let normalizedRoot = rootURL.standardizedFileURL.path(percentEncoded: false)
    if copy.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      copy.id = normalizedRoot
    }
    copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if copy.title.isEmpty {
      copy.title = rootURL.lastPathComponent.isEmpty ? normalizedRoot : rootURL.lastPathComponent
    }
    copy.description = copy.description.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.taskLinks = copy.taskLinks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    copy.repositories = copy.repositories.map { entry in
      var entry = entry
      entry.id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
      entry.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
      entry.path = entry.path.trimmingCharacters(in: .whitespacesAndNewlines)
      if entry.id.isEmpty {
        entry.id = entry.path.isEmpty ? entry.name : entry.path
      }
      if entry.name.isEmpty {
        let resolvedURL = entry.resolvedURL(relativeTo: rootURL)
        entry.name = resolvedURL.lastPathComponent.isEmpty ? entry.id : resolvedURL.lastPathComponent
      }
      entry.role = entry.role?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      entry.sourceLocation = entry.sourceLocation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      entry.branchName = entry.branchName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      entry.baseRef = entry.baseRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      return entry
    }
    return copy
  }

  static func create(
    _ request: ProjectWorkspaceCreationRequest,
    fileManager: FileManager = .default,
    gitRunner: ProjectWorkspaceGitRunner
  ) async throws -> ProjectWorkspace {
    let title = request.draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw ProjectWorkspaceCreationError.missingTitle
    }
    guard request.draft.repositories.count >= 2 else {
      throw ProjectWorkspaceCreationError.notEnoughRepositories
    }
    let rootPath = normalizedPath(request.draft.rootURL, resolvingSymlinks: false)
    guard !rootPath.isEmpty else {
      throw ProjectWorkspaceCreationError.missingPath
    }
    let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL

    var createdRoot = false
    var createdMetadataDirectory = false
    var createdURLs: [URL] = []
    var cleanupCommands: [ProjectWorkspaceGitCommand] = []
    do {
      var isDirectory = ObjCBool(false)
      if fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory) {
        guard isDirectory.boolValue else {
          throw ProjectWorkspaceCreationError.destinationIsFile(rootPath)
        }
      } else {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        createdRoot = true
      }

      let metadataDirectoryURL = rootURL.appending(path: metadataDirectoryName, directoryHint: .isDirectory)
      let metadataPath = metadataDirectoryURL.path(percentEncoded: false)
      let metadataURL = metadataURL(for: rootURL)
      if fileManager.fileExists(atPath: metadataURL.path(percentEncoded: false)) {
        throw ProjectWorkspaceCreationError.workspaceAlreadyExists(rootPath)
      }
      if !fileManager.fileExists(atPath: metadataPath) {
        try fileManager.createDirectory(at: metadataDirectoryURL, withIntermediateDirectories: true)
        createdMetadataDirectory = true
      }

      var occupiedNames: Set<String> = []
      var entries: [RepositoryEntry] = []
      for repository in request.draft.repositories {
        let prepared = try await materialize(
          repository,
          workspaceRootURL: rootURL,
          occupiedNames: &occupiedNames,
          fileManager: fileManager,
          gitRunner: gitRunner
        )
        createdURLs.append(prepared.createdURL)
        if let cleanupCommand = prepared.cleanupCommand {
          cleanupCommands.append(cleanupCommand)
        }
        entries.append(prepared.entry)
      }

      let workspace = ProjectWorkspace(
        id: rootPath,
        title: title,
        repositories: entries,
        createdAt: request.createdAt,
        updatedAt: request.createdAt
      )
      .normalized(relativeTo: rootURL)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(workspace).write(to: metadataURL, options: .atomic)
      createdURLs.append(metadataURL)
      return workspace
    } catch {
      for command in cleanupCommands.reversed() {
        try? await gitRunner.run(command)
      }
      for url in createdURLs.reversed() {
        try? fileManager.removeItem(at: url)
      }
      if createdRoot {
        try? fileManager.removeItem(at: rootURL)
      } else if createdMetadataDirectory {
        try? fileManager.removeItem(at: rootURL.appending(path: metadataDirectoryName, directoryHint: .isDirectory))
      }
      throw error
    }
  }

  static func defaultWorkspaceFolderName(for title: String) -> String {
    let sanitized = sanitizedWorkspaceComponent(title)
    return sanitized.isEmpty ? "workspace" : sanitized
  }

  private struct PreparedRepository {
    var entry: RepositoryEntry
    var createdURL: URL
    var cleanupCommand: ProjectWorkspaceGitCommand?
  }

  private static func materialize(
    _ repository: ProjectWorkspaceCreationRepository,
    workspaceRootURL: URL,
    occupiedNames: inout Set<String>,
    fileManager: FileManager,
    gitRunner: ProjectWorkspaceGitRunner
  ) async throws -> PreparedRepository {
    let name = repositoryDisplayName(repository)
    guard !name.isEmpty else {
      throw ProjectWorkspaceCreationError.missingRepositoryName
    }
    let sourceLocation = repository.sourceLocation.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sourceLocation.isEmpty else {
      throw ProjectWorkspaceCreationError.missingRepositorySource(name)
    }
    let workspacePath = uniqueRepositoryPath(for: repository, displayName: name, occupiedNames: &occupiedNames)
    let destinationURL = workspaceRootURL.appending(path: workspacePath, directoryHint: .isDirectory)
    let destinationPath = normalizedPath(destinationURL, resolvingSymlinks: false)
    guard !fileManager.fileExists(atPath: destinationPath) else {
      throw ProjectWorkspaceCreationError.linkAlreadyExists(destinationPath)
    }

    let sourceKind = repository.sourceKind
    let normalizedSourceLocation: String?
    let cleanupCommand: ProjectWorkspaceGitCommand?
    switch sourceKind {
    case .existingPath, .localRepository:
      let sourcePath = try localRepositoryPath(repository, sourceLocation: sourceLocation, fileManager: fileManager)
      let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: true).standardizedFileURL
      try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
      normalizedSourceLocation = sourcePath
      cleanupCommand = nil

    case .remote:
      try await gitRunner.run(
        ProjectWorkspaceGitCommand(
          arguments: ["clone", sourceLocation, destinationPath],
          currentDirectoryURL: workspaceRootURL
        )
      )
      try await checkoutIfNeeded(
        repository,
        destinationURL: destinationURL,
        gitRunner: gitRunner
      )
      normalizedSourceLocation = sourceLocation
      cleanupCommand = nil

    case .bareRepository:
      let sourcePath = try localRepositoryPath(repository, sourceLocation: sourceLocation, fileManager: fileManager)
      let command = bareWorktreeCommand(
        repository,
        sourcePath: sourcePath,
        destinationPath: destinationPath
      )
      try await gitRunner.run(command)
      normalizedSourceLocation = sourcePath
      cleanupCommand = ProjectWorkspaceGitCommand(
        arguments: ["-C", sourcePath, "worktree", "remove", "--force", destinationPath],
        currentDirectoryURL: nil
      )
    }

    return PreparedRepository(
      entry: RepositoryEntry(
        id: repository.id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? workspacePath,
        name: name,
        path: workspacePath,
        sourceKind: sourceKind,
        sourceLocation: normalizedSourceLocation,
        branchName: repository.branchName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        baseRef: repository.baseRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ),
      createdURL: destinationURL,
      cleanupCommand: cleanupCommand
    )
  }

  private static func checkoutIfNeeded(
    _ repository: ProjectWorkspaceCreationRepository,
    destinationURL: URL,
    gitRunner: ProjectWorkspaceGitRunner
  ) async throws {
    let destinationPath = normalizedPath(destinationURL, resolvingSymlinks: false)
    let branchName = repository.branchName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    let baseRef = repository.baseRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    switch (branchName, baseRef) {
    case (.some(let branchName), .some(let baseRef)):
      try await gitRunner.run(
        ProjectWorkspaceGitCommand(
          arguments: ["-C", destinationPath, "checkout", "-B", branchName, baseRef],
          currentDirectoryURL: nil
        )
      )
    case (.some(let branchName), .none):
      try await gitRunner.run(
        ProjectWorkspaceGitCommand(
          arguments: ["-C", destinationPath, "checkout", "-B", branchName],
          currentDirectoryURL: nil
        )
      )
    case (.none, .some(let baseRef)):
      try await gitRunner.run(
        ProjectWorkspaceGitCommand(
          arguments: ["-C", destinationPath, "checkout", baseRef],
          currentDirectoryURL: nil
        )
      )
    case (.none, .none):
      break
    }
  }

  private static func bareWorktreeCommand(
    _ repository: ProjectWorkspaceCreationRepository,
    sourcePath: String,
    destinationPath: String
  ) -> ProjectWorkspaceGitCommand {
    let branchName = repository.branchName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    let baseRef = repository.baseRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    var arguments = ["-C", sourcePath, "worktree", "add"]
    if let branchName, let baseRef {
      arguments += ["-b", branchName, destinationPath, baseRef]
    } else if let branchName {
      arguments += [destinationPath, branchName]
    } else if let baseRef {
      arguments += [destinationPath, baseRef]
    } else {
      arguments += [destinationPath]
    }
    return ProjectWorkspaceGitCommand(arguments: arguments, currentDirectoryURL: nil)
  }

  private static func localRepositoryPath(
    _ repository: ProjectWorkspaceCreationRepository,
    sourceLocation: String,
    fileManager: FileManager
  ) throws -> String {
    let repositoryPath = normalizedPath(URL(fileURLWithPath: sourceLocation), resolvingSymlinks: true)
    var repositoryIsDirectory = ObjCBool(false)
    guard fileManager.fileExists(atPath: repositoryPath, isDirectory: &repositoryIsDirectory),
      repositoryIsDirectory.boolValue
    else {
      throw ProjectWorkspaceCreationError.repositoryDoesNotExist(repositoryPath)
    }
    return repositoryPath
  }

  private static func uniqueRepositoryPath(
    for repository: ProjectWorkspaceCreationRepository,
    displayName: String,
    occupiedNames: inout Set<String>
  ) -> String {
    var baseName = sanitizedWorkspaceComponent(repository.path ?? "")
    if baseName.isEmpty {
      baseName = sanitizedWorkspaceComponent(displayName)
    }
    if baseName.isEmpty {
      baseName = "repository"
    }

    var candidate = baseName
    var suffix = 2
    while occupiedNames.contains(candidate.lowercased()) {
      candidate = "\(baseName)-\(suffix)"
      suffix += 1
    }
    occupiedNames.insert(candidate.lowercased())
    return candidate
  }

  private static func repositoryDisplayName(_ repository: ProjectWorkspaceCreationRepository) -> String {
    let trimmedName = repository.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedName.isEmpty {
      return trimmedName
    }
    switch repository.sourceKind {
    case .existingPath, .localRepository, .bareRepository:
      if let localSourceURL = repository.localSourceURL {
        return Repository.name(for: localSourceURL)
      }
    case .remote:
      let source = repository.sourceLocation.trimmingCharacters(in: .whitespacesAndNewlines)
      let lastPathComponent =
        source
        .split(separator: "/")
        .last
        .map(String.init)?
        .replacing(".git", with: "")
      if let lastPathComponent, !lastPathComponent.isEmpty {
        return lastPathComponent
      }
    }
    return ""
  }

  private static func sanitizedWorkspaceComponent(_ value: String) -> String {
    var result = ""
    for scalar in value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
      if CharacterSet.whitespacesAndNewlines.contains(scalar)
        || CharacterSet(charactersIn: "/:").contains(scalar)
      {
        result.append("-")
      } else {
        result.unicodeScalars.append(scalar)
      }
    }
    while result.contains("--") {
      result = result.replacing("--", with: "-")
    }
    result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    if result == "." || result == ".." {
      return ""
    }
    return result
  }

  private static func normalizedPath(_ url: URL, resolvingSymlinks: Bool) -> String {
    var path = PathPolicy.normalizeURL(url, resolvingSymlinks: resolvingSymlinks).path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return path
  }
}

extension String {
  nonisolated fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
