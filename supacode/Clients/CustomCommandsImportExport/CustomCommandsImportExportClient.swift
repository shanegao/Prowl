import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

/// Imports/exports the user's global custom commands as JSON via macOS
/// `NSOpenPanel` / `NSSavePanel`. Wraps the modal-panel + codec work
/// behind a `DependencyKey` surface so reducers stay free of AppKit
/// modal coupling (matches `AppLifecycleClient` style).
///
/// Error feedback is surfaced to the user directly via `NSAlert` from
/// the live implementation — the reducer treats "user cancelled" and
/// "decode failed" identically (both yield `nil` from `runImport`),
/// keeping the reducer's surface narrow.
struct CustomCommandsImportExportClient: Sendable {
  /// Show a save panel and write the commands as JSON. No-ops if the
  /// user cancels. Failures surface via `NSAlert`.
  var runExport: @MainActor @Sendable ([UserCustomCommand]) async -> Void

  /// Show an open panel, read + decode the chosen JSON file, return the
  /// imported commands. Returns `nil` when the user cancels OR an error
  /// occurs — in the error case the user has already been shown an
  /// `NSAlert` describing the problem.
  var runImport: @MainActor @Sendable () async -> [UserCustomCommand]?

  /// JSON envelope written by `runExport` and parsed by `runImport`. The
  /// `version` field exists so future schema migrations can change the
  /// shape of `commands` without breaking older exports — bump
  /// `currentExportVersion` and add a migrator branch in the decoder.
  struct ExportPayload: Codable {
    let version: Int
    let commands: [UserCustomCommand]
  }

  /// On-disk schema version. Older exports remain readable as long as
  /// the `commands` array shape stays backward-compatible at the
  /// `UserCustomCommand` codec level. Bump when the envelope itself
  /// gains structure.
  static let currentExportVersion = 1
}

extension CustomCommandsImportExportClient: DependencyKey {
  static let liveValue = CustomCommandsImportExportClient(
    runExport: { commands in
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.json]
      panel.canCreateDirectories = true
      panel.nameFieldStringValue = defaultExportFilename()
      panel.title = "Export Global Commands"
      guard panel.runModal() == .OK, let url = panel.url else { return }

      let payload = ExportPayload(
        version: currentExportVersion,
        commands: commands
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      do {
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
      } catch {
        showAlert(
          title: "Export failed",
          message: error.localizedDescription
        )
      }
    },
    runImport: {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.json]
      panel.allowsMultipleSelection = false
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.title = "Import Global Commands"
      guard panel.runModal() == .OK, let url = panel.url else { return nil }

      do {
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(ExportPayload.self, from: data)
        return payload.commands
      } catch {
        showAlert(
          title: "Import failed",
          message:
            "The file isn't a valid Prowl commands export.\n\(error.localizedDescription)"
        )
        return nil
      }
    }
  )

  static let testValue = CustomCommandsImportExportClient(
    runExport: { _ in },
    runImport: { nil }
  )
}

extension DependencyValues {
  var customCommandsImportExportClient: CustomCommandsImportExportClient {
    get { self[CustomCommandsImportExportClient.self] }
    set { self[CustomCommandsImportExportClient.self] = newValue }
  }
}

/// Default filename suggested by the save panel. Uses an ISO-style date
/// stamp so multiple exports sort chronologically in Finder without
/// colliding on the same name within one day.
@MainActor
private func defaultExportFilename() -> String {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  let date = formatter.string(from: Date())
  return "prowl-global-commands-\(date).json"
}

@MainActor
private func showAlert(title: String, message: String) {
  let alert = NSAlert()
  alert.messageText = title
  alert.informativeText = message
  alert.alertStyle = .warning
  alert.addButton(withTitle: "OK")
  alert.runModal()
}
