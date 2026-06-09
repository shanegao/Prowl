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
  var rootURL: URL
  var branchName: String?

  init(
    id: String,
    name: String,
    rootURL: URL,
    branchName: String? = nil
  ) {
    self.id = id
    self.name = name
    self.rootURL = rootURL.standardizedFileURL
    self.branchName = branchName
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

nonisolated enum ProjectWorkspaceCreationError: LocalizedError, Equatable, Sendable {
  case missingTitle
  case missingPath
  case notEnoughRepositories
  case destinationIsFile(String)
  case workspaceAlreadyExists(String)
  case repositoryDoesNotExist(String)
  case linkAlreadyExists(String)

  var errorDescription: String? {
    switch self {
    case .missingTitle:
      return "Workspace title required."
    case .missingPath:
      return "Workspace folder required."
    case .notEnoughRepositories:
      return "Select at least two repositories."
    case .destinationIsFile(let path):
      return "\(path) is a file. Choose a folder path instead."
    case .workspaceAlreadyExists(let path):
      return "\(path) already contains a Prowl workspace."
    case .repositoryDoesNotExist(let path):
      return "\(path) does not exist."
    case .linkAlreadyExists(let path):
      return "\(path) already exists."
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
    fileManager: FileManager = .default
  ) throws -> ProjectWorkspace {
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
      let entries = try request.draft.repositories.map { repository in
        let repositoryPath = normalizedPath(repository.rootURL, resolvingSymlinks: true)
        let repositoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true).standardizedFileURL
        var repositoryIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: repositoryPath, isDirectory: &repositoryIsDirectory),
          repositoryIsDirectory.boolValue
        else {
          throw ProjectWorkspaceCreationError.repositoryDoesNotExist(repositoryPath)
        }

        let linkName = uniqueRepositoryLinkName(for: repository, occupiedNames: &occupiedNames)
        let linkURL = rootURL.appending(path: linkName, directoryHint: .isDirectory)
        let linkPath = linkURL.path(percentEncoded: false)
        guard !fileManager.fileExists(atPath: linkPath) else {
          throw ProjectWorkspaceCreationError.linkAlreadyExists(linkPath)
        }
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: repositoryURL)
        createdURLs.append(linkURL)
        return RepositoryEntry(
          id: repository.id,
          name: repository.name,
          path: linkName,
          sourceKind: .existingPath,
          sourceLocation: repositoryPath,
          branchName: repository.branchName
        )
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

  private static func uniqueRepositoryLinkName(
    for repository: ProjectWorkspaceCreationRepository,
    occupiedNames: inout Set<String>
  ) -> String {
    var baseName = sanitizedWorkspaceComponent(repository.name)
    if baseName.isEmpty {
      baseName = sanitizedWorkspaceComponent(repository.rootURL.lastPathComponent)
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
