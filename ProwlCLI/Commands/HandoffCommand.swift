// ProwlCLI/Commands/HandoffCommand.swift

import ArgumentParser
import Foundation
import ProwlCLIShared

struct HandoffCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "handoff",
    abstract: "Refresh, archive, and hand off the cross-agent task artifact in a runnable target.",
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

  @Argument(help: "Target pane/tab UUID or worktree id/name/path (auto-resolved).")
  var target: String?

  @Option(name: .long, help: "Optional note appended to the handoff log.")
  var note: String?

  @Flag(
    name: .customLong("no-prepare"),
    help: "Skip asking the detected source agent to refresh current.md before saving."
  )
  var noPrepare = false

  mutating func run() throws {
    try CLIExecution.run(command: "handoff", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .handoff(
          HandoffInput(
            action: .save,
            selector: try selector.resolve(positionalTarget: target),
            note: note,
            prepare: !noPrepare
          )
        )
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

  @Argument(
    help:
      "The agent to hand off to. Launch supported: \(HandoffAgentSupport.launchableAgentsDescription); use --no-launch for other detected agents."
  )
  var agent: String

  @Argument(help: "Target pane/tab UUID or worktree id/name/path (auto-resolved).")
  var target: String?

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  @Option(name: .long, help: "Optional note appended to the handoff log.")
  var note: String?

  @Flag(name: .customLong("no-launch"), help: "Archive + save only; do not launch the receiving agent.")
  var noLaunch = false

  @Flag(
    name: .customLong("no-prepare"),
    help: "Skip asking the detected source agent to refresh current.md before saving."
  )
  var noPrepare = false

  mutating func run() throws {
    try CLIExecution.run(command: "handoff", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let rawAgent = agent.lowercased()
      guard let normalizedAgent = HandoffAgentSupport.normalize(rawAgent) else {
        throw ExitError(
          code: CLIErrorCode.invalidArgument,
          message: "handoff to requires an agent of: \(HandoffAgentSupport.supportedAgentsDescription)."
        )
      }
      if !noLaunch, !HandoffAgentSupport.canLaunch(normalizedAgent) {
        throw ExitError(
          code: CLIErrorCode.invalidArgument,
          message:
            "handoff can only launch: \(HandoffAgentSupport.launchableAgentsDescription). Use --no-launch for other agents."
        )
      }
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .handoff(
          HandoffInput(
            action: .toAgent,
            selector: try selector.resolve(positionalTarget: target),
            toAgent: normalizedAgent,
            note: note,
            launch: !noLaunch,
            prepare: !noPrepare
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

  @Argument(help: "Target pane/tab UUID or worktree id/name/path (auto-resolved).")
  var target: String?

  mutating func run() throws {
    try CLIExecution.run(command: "handoff", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .handoff(
          HandoffInput(action: .status, selector: try selector.resolve(positionalTarget: target))
        )
      )
      try CLIRunner.execute(envelope)
    }
  }
}
