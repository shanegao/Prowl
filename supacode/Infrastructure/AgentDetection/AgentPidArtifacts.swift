import Foundation

/// Copilot CLI writes `~/.copilot/logs/process-<epoch-ms>-<pid>.log` and logs
/// "Registering foreground session: <uuid>" once the interactive session is
/// live, giving an exact pid→session mapping without descriptor inspection.
nonisolated enum CopilotProcessLog {
  static func session(
    logsDirectory: URL,
    sessionStateDirectory: URL,
    pid: pid_t,
    processStartedAt: Date,
    fileManager: FileManager = .default
  ) -> AgentSession? {
    guard let log = latestLog(in: logsDirectory, pid: pid, fileManager: fileManager),
      let modifiedAt = try? log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
      modifiedAt >= processStartedAt.addingTimeInterval(-2),
      let id = lastRegisteredSession(in: log)
    else { return nil }
    let transcript = sessionStateDirectory.appending(path: "\(id)/events.jsonl")
    return AgentSession(
      id: id,
      transcriptPath: fileManager.fileExists(atPath: transcript.path) ? transcript : nil,
      source: .processLog,
      confidence: .exact
    )
  }

  /// Pid reuse across app restarts leaves several `process-*-<pid>.log` files;
  /// the largest epoch prefix is the current process's log.
  private static func latestLog(in directory: URL, pid: pid_t, fileManager: FileManager) -> URL? {
    let suffix = "-\(pid).log"
    let logs = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return
      logs
      .filter { $0.lastPathComponent.hasPrefix("process-") && $0.lastPathComponent.hasSuffix(suffix) }
      .max { $0.lastPathComponent < $1.lastPathComponent }
  }

  private static func lastRegisteredSession(in url: URL, byteLimit: Int = 262_144) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd() else { return nil }
    try? handle.seek(toOffset: size > UInt64(byteLimit) ? size - UInt64(byteLimit) : 0)
    guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
    let pattern = /Registering foreground session: ([0-9a-fA-F-]{36})/
    return text.matches(of: pattern).last.map { String($0.output.1).lowercased() }
  }
}

/// Qwen Code writes `<chats dir>/<session id>.runtime.json` sidecars
/// (`{"pid": ..., "session_id": ...}`) for every live session, intended for
/// external observers.
nonisolated enum QwenRuntimeStatus {
  static func session(
    projectsRoot: URL,
    pid: pid_t,
    fileManager: FileManager = .default
  ) -> AgentSession? {
    let projects = (try? fileManager.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)) ?? []
    for project in projects {
      let chats = project.appending(path: "chats")
      let sidecars = (try? fileManager.contentsOfDirectory(at: chats, includingPropertiesForKeys: nil)) ?? []
      for sidecar in sidecars where sidecar.lastPathComponent.hasSuffix(".runtime.json") {
        guard let data = try? Data(contentsOf: sidecar),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sidecarPID = object["pid"] as? Int, sidecarPID == Int(pid),
          let id = object["session_id"] as? String, !id.isEmpty
        else { continue }
        let transcript = chats.appending(path: "\(id).jsonl")
        return AgentSession(
          id: id,
          transcriptPath: fileManager.fileExists(atPath: transcript.path) ? transcript : nil,
          source: .processLog,
          confidence: .exact
        )
      }
    }
    return nil
  }
}
