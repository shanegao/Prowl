import CoreServices
import Darwin
import Dispatch
import Foundation

@MainActor
protocol WorktreeFileEventMonitoring: AnyObject {
  func cancel()
}

@MainActor
protocol WorktreeRegistryMonitoring: AnyObject {
  func cancel()
}

final class FSEventsWorktreeFileEventMonitor: WorktreeFileEventMonitoring {
  private let onEvent: @MainActor @Sendable () -> Void
  private var stream: FSEventStreamRef?

  init?(
    rootURL: URL,
    onEvent: @escaping @MainActor @Sendable () -> Void
  ) {
    self.onEvent = onEvent
    let path = rootURL.path(percentEncoded: false)
    var context = FSEventStreamContext(
      version: 0,
      info: nil,
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    context.info = Unmanaged.passUnretained(self).toOpaque()
    let callback: FSEventStreamCallback = { _, callbackInfo, _, _, _, _ in
      guard let callbackInfo else { return }
      let monitor = Unmanaged<FSEventsWorktreeFileEventMonitor>
        .fromOpaque(callbackInfo)
        .takeUnretainedValue()
      Task { @MainActor in
        monitor.onEvent()
      }
    }
    stream = FSEventStreamCreate(
      nil,
      callback,
      &context,
      [path] as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      1.0,
      FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents
          | kFSEventStreamCreateFlagNoDefer
          | kFSEventStreamCreateFlagWatchRoot
      )
    )
    guard let stream else {
      return nil
    }
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
      return nil
    }
  }

  func cancel() {
    guard let stream else {
      return
    }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    self.stream = nil
  }
}

@MainActor
final class GitWorktreeRegistryMonitor: WorktreeRegistryMonitoring {
  private let commonGitDirectoryURL: URL
  private let worktreesDirectoryURL: URL
  private let onEvent: @MainActor @Sendable () -> Void
  private var commonDirectorySource: DispatchSourceFileSystemObject?
  private var worktreesDirectorySource: DispatchSourceFileSystemObject?
  private var isWorktreesDirectoryPresent: Bool

  init?(
    repositoryRootURL: URL,
    onEvent: @escaping @MainActor @Sendable () -> Void,
    fileManager: FileManager = .default
  ) {
    guard
      let commonGitDirectoryURL = Self.commonGitDirectoryURL(
        for: repositoryRootURL,
        fileManager: fileManager
      )
    else {
      return nil
    }
    self.commonGitDirectoryURL = commonGitDirectoryURL
    worktreesDirectoryURL = commonGitDirectoryURL.appending(path: "worktrees")
    self.onEvent = onEvent
    isWorktreesDirectoryPresent = Self.isDirectory(worktreesDirectoryURL, fileManager: fileManager)
    commonDirectorySource = Self.makeDirectorySource(url: commonGitDirectoryURL) { [weak self] in
      self?.handleCommonDirectoryEvent()
    }
    if isWorktreesDirectoryPresent {
      startWorktreesDirectorySourceIfNeeded()
    }
    guard commonDirectorySource != nil || worktreesDirectorySource != nil else {
      return nil
    }
  }

  func cancel() {
    commonDirectorySource?.cancel()
    worktreesDirectorySource?.cancel()
    commonDirectorySource = nil
    worktreesDirectorySource = nil
  }

  private func handleCommonDirectoryEvent() {
    let isPresent = Self.isDirectory(worktreesDirectoryURL, fileManager: .default)
    guard isPresent != isWorktreesDirectoryPresent else {
      return
    }
    isWorktreesDirectoryPresent = isPresent
    if isPresent {
      startWorktreesDirectorySourceIfNeeded()
    } else {
      worktreesDirectorySource?.cancel()
      worktreesDirectorySource = nil
    }
    onEvent()
  }

  private func handleWorktreesDirectoryEvent() {
    guard Self.isDirectory(worktreesDirectoryURL, fileManager: .default) else {
      if isWorktreesDirectoryPresent {
        isWorktreesDirectoryPresent = false
        worktreesDirectorySource?.cancel()
        worktreesDirectorySource = nil
        onEvent()
      }
      return
    }
    onEvent()
  }

  private func startWorktreesDirectorySourceIfNeeded() {
    guard worktreesDirectorySource == nil else {
      return
    }
    worktreesDirectorySource = Self.makeDirectorySource(url: worktreesDirectoryURL) { [weak self] in
      self?.handleWorktreesDirectoryEvent()
    }
  }

  private static func makeDirectorySource(
    url: URL,
    onEvent: @escaping @MainActor @Sendable () -> Void
  ) -> DispatchSourceFileSystemObject? {
    let fileDescriptor = open(url.path(percentEncoded: false), O_EVTONLY)
    guard fileDescriptor >= 0 else {
      return nil
    }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .rename, .delete, .attrib],
      queue: .main
    )
    source.setEventHandler {
      onEvent()
    }
    source.setCancelHandler {
      close(fileDescriptor)
    }
    source.resume()
    return source
  }

  private static func commonGitDirectoryURL(
    for repositoryRootURL: URL,
    fileManager: FileManager
  ) -> URL? {
    let repositoryRootURL = repositoryRootURL.standardizedFileURL
    let dotGitURL = repositoryRootURL.appending(path: ".git")
    var isDirectory = ObjCBool(false)
    if fileManager.fileExists(atPath: dotGitURL.path(percentEncoded: false), isDirectory: &isDirectory) {
      if isDirectory.boolValue {
        return dotGitURL.standardizedFileURL
      }
      guard let gitdirURL = gitdirURL(from: dotGitURL, relativeTo: repositoryRootURL) else {
        return nil
      }
      return commonDirectoryURL(from: gitdirURL, fileManager: fileManager)
    }
    if fileManager.fileExists(atPath: repositoryRootURL.appending(path: "HEAD").path(percentEncoded: false)),
      fileManager.fileExists(atPath: repositoryRootURL.appending(path: "config").path(percentEncoded: false))
    {
      return repositoryRootURL
    }
    return nil
  }

  private static func gitdirURL(from dotGitURL: URL, relativeTo repositoryRootURL: URL) -> URL? {
    guard let contents = try? String(contentsOf: dotGitURL, encoding: .utf8),
      let line = contents.split(whereSeparator: \.isNewline).first
    else {
      return nil
    }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "gitdir:"
    guard trimmed.hasPrefix(prefix) else {
      return nil
    }
    let pathPart = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pathPart.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: String(pathPart), relativeTo: repositoryRootURL)
      .standardizedFileURL
  }

  private static func commonDirectoryURL(from gitdirURL: URL, fileManager: FileManager) -> URL {
    let commondirURL = gitdirURL.appending(path: "commondir")
    guard let contents = try? String(contentsOf: commondirURL, encoding: .utf8),
      let line = contents.split(whereSeparator: \.isNewline).first
    else {
      return gitdirURL.standardizedFileURL
    }
    let pathPart = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pathPart.isEmpty else {
      return gitdirURL.standardizedFileURL
    }
    return URL(fileURLWithPath: pathPart, relativeTo: gitdirURL)
      .standardizedFileURL
  }

  private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}
