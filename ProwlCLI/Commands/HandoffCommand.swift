// ProwlCLI/Commands/HandoffCommand.swift

import ArgumentParser
import Foundation
import ProwlCLIShared

struct HandoffCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "handoff",
    abstract: "Refresh, archive, and hand off the cross-agent task artifact in a workspace.",
    subcommands: [
      HandoffSaveCommand.self,
      HandoffToCommand.self,
      HandoffStatusCommand.self,
    ]
  )
}

struct HandoffSaveCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "save",
    abstract: "Refresh the handoff artifact's auto context appendix from live git state."
  )

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  @Option(name: .long, help: "Optional note appended to the handoff log.")
  var note: String?

  mutating func run() throws {
    try CLIExecution.run(command: "handoff", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .handoff(HandoffInput(action: .save, selector: try selector.resolve(), note: note))
      )
      try CLIRunner.execute(envelope)
    }
  }
}

struct HandoffToCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "to",
    abstract: "Save + archive the handoff, then launch the receiving agent in a new tab."
  )

  @Argument(help: "The agent to hand off to. Supported: \(HandoffAgentSupport.supportedAgentsDescription).")
  var agent: String

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  @Option(name: .long, help: "Optional note appended to the handoff log.")
  var note: String?

  @Flag(name: .customLong("no-launch"), help: "Archive + save only; do not launch the receiving agent.")
  var noLaunch = false

  mutating func run() throws {
    try CLIExecution.run(command: "handoff", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let rawAgent = agent.lowercased()
      guard let normalizedAgent = HandoffAgentSupport.normalize(rawAgent) else {
        throw ExitError(
          code: CLIErrorCode.invalidArgument,
          message: "handoff to requires an agent of: \(HandoffAgentSupport.supportedAgentsDescription)."
        )
      }
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .handoff(
          HandoffInput(
            action: .toAgent,
            selector: try selector.resolve(),
            toAgent: normalizedAgent,
            note: note,
            launch: !noLaunch
          )
        )
      )
      try CLIRunner.execute(envelope)
    }
  }
}

struct HandoffStatusCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show the handoff artifact path, existence, and last log line."
  )

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CLIExecution.run(command: "handoff", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .handoff(HandoffInput(action: .status, selector: try selector.resolve()))
      )
      try CLIRunner.execute(envelope)
    }
  }
}
