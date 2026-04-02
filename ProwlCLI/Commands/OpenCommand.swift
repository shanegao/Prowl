// ProwlCLI/Commands/OpenCommand.swift

import ArgumentParser
import Foundation

struct OpenCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "open",
    abstract: "Open a path in Prowl, or bring the app to front."
  )

  @OptionGroup var options: GlobalOptions

  @Argument(help: "Path to open. Omit to bring Prowl to front.")
  var path: String?

  mutating func run() throws {
    let resolvedPath: String? = try path.map { try normalizePath($0) }
    let envelope = CommandEnvelope(
      output: options.outputMode,
      command: .open(OpenInput(path: resolvedPath))
    )
    try CLIRunner.execute(envelope)
  }

  private func normalizePath(_ raw: String) throws -> String {
    let expanded = NSString(string: raw).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded).standardized
    let abs = url.path
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: abs, isDirectory: &isDir) else {
      throw ExitError(
        code: CLIErrorCode.pathNotFound,
        message: "Path not found: \(raw)"
      )
    }
    guard isDir.boolValue else {
      throw ExitError(
        code: CLIErrorCode.pathNotDirectory,
        message: "Not a directory: \(raw)"
      )
    }
    return abs
  }
}
