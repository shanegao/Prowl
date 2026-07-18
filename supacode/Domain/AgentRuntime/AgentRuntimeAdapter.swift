import Foundation

nonisolated protocol AgentRuntimeAdapter: Sendable {
  var agent: DetectedAgent { get }

  func observe(arguments: [String]) -> AgentLaunchObservation
  func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation
  func makeResumeInvocation(_ request: AgentResumeRequest) throws -> AgentInvocation
}

nonisolated enum AgentExecutionMode: String, Codable, Equatable, Sendable {
  case standard
  case unrestricted
}

nonisolated struct AgentLaunchConfiguration: Codable, Equatable, Sendable {
  var model: String?
  var executionMode: AgentExecutionMode

  init(model: String? = nil, executionMode: AgentExecutionMode = .standard) {
    self.model = model
    self.executionMode = executionMode
  }
}

/// Options observed from a live agent process. Nil denotes an unknown effective setting,
/// never an inferred safe default from the absence of an argv flag.
nonisolated struct AgentLaunchObservation: Equatable, Sendable {
  let model: String?
  let executionMode: AgentExecutionMode?

  init(model: String? = nil, executionMode: AgentExecutionMode? = nil) {
    self.model = model
    self.executionMode = executionMode
  }
}

nonisolated struct AgentStartRequest: Equatable, Sendable {
  let agent: DetectedAgent
  let prompt: String
  let configuration: AgentLaunchConfiguration

  init(agent: DetectedAgent, prompt: String, configuration: AgentLaunchConfiguration = .init()) {
    self.agent = agent
    self.prompt = prompt
    self.configuration = configuration
  }
}

nonisolated struct AgentResumeRequest: Equatable, Sendable {
  let agent: DetectedAgent
  let session: AgentSession
  let prompt: String
  let configuration: AgentLaunchConfiguration

  init(
    agent: DetectedAgent,
    session: AgentSession,
    prompt: String,
    configuration: AgentLaunchConfiguration = .init()
  ) {
    self.agent = agent
    self.session = session
    self.prompt = prompt
    self.configuration = configuration
  }
}

nonisolated struct AgentInvocation: Equatable, Sendable {
  let executable: String
  let arguments: [String]

  init(executable: String, arguments: [String]) {
    self.executable = executable
    self.arguments = arguments
  }

  /// One reviewed POSIX-shell rendering path for a command injected into a terminal surface.
  var terminalInput: String {
    ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
  }

  private static func shellQuote(_ argument: String) -> String {
    "'" + argument.replacing("'", with: "'\"'\"'") + "'"
  }
}

nonisolated enum AgentRuntimeError: Error, Equatable, Sendable {
  case unsupportedAgent(DetectedAgent)
  case unsafeSessionConfidence(AgentSession.Confidence)
}

nonisolated enum AgentRuntimeAdapterRegistry {
  static func adapter(for agent: DetectedAgent) -> (any AgentRuntimeAdapter)? {
    switch agent {
    case .claude: ClaudeCodeRuntimeAdapter()
    case .codex: CodexRuntimeAdapter()
    default: nil
    }
  }

  static func canStart(_ agent: DetectedAgent) -> Bool {
    adapter(for: agent) != nil
  }

  static func canResume(_ agent: DetectedAgent) -> Bool {
    adapter(for: agent) != nil
  }

  static func observe(agent: DetectedAgent, arguments: [String]) -> AgentLaunchObservation {
    adapter(for: agent)?.observe(arguments: arguments) ?? .init()
  }

  static func inheritedConfiguration(
    from sourceAgent: DetectedAgent,
    observation: AgentLaunchObservation?,
    to destinationAgent: DetectedAgent
  ) -> AgentLaunchConfiguration {
    AgentLaunchConfiguration(
      model: sourceAgent == destinationAgent ? observation?.model : nil,
      executionMode: observation?.executionMode ?? .standard
    )
  }

  static func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation {
    guard let adapter = adapter(for: request.agent) else {
      throw AgentRuntimeError.unsupportedAgent(request.agent)
    }
    return try adapter.makeStartInvocation(request)
  }

  static func makeResumeInvocation(_ request: AgentResumeRequest) throws -> AgentInvocation {
    guard request.session.confidence == .exact || request.session.confidence == .high else {
      throw AgentRuntimeError.unsafeSessionConfidence(request.session.confidence)
    }
    guard let adapter = adapter(for: request.agent) else {
      throw AgentRuntimeError.unsupportedAgent(request.agent)
    }
    return try adapter.makeResumeInvocation(request)
  }
}

nonisolated private struct CodexRuntimeAdapter: AgentRuntimeAdapter {
  let agent: DetectedAgent = .codex

  func observe(arguments: [String]) -> AgentLaunchObservation {
    AgentLaunchObservation(
      model: arguments.optionValue(long: "--model", short: "-m"),
      executionMode: arguments.contains("--dangerously-bypass-approvals-and-sandbox") ? .unrestricted : nil
    )
  }

  func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation {
    AgentInvocation(executable: "codex", arguments: options(for: request.configuration) + [request.prompt])
  }

  func makeResumeInvocation(_ request: AgentResumeRequest) throws -> AgentInvocation {
    AgentInvocation(
      executable: "codex",
      arguments: ["exec", "resume"] + options(for: request.configuration) + [request.session.id, request.prompt]
    )
  }

  private func options(for configuration: AgentLaunchConfiguration) -> [String] {
    var options: [String] = []
    if let model = configuration.model {
      options += ["--model", model]
    }
    if configuration.executionMode == .unrestricted {
      options.append("--dangerously-bypass-approvals-and-sandbox")
    }
    return options
  }
}

nonisolated private struct ClaudeCodeRuntimeAdapter: AgentRuntimeAdapter {
  let agent: DetectedAgent = .claude

  func observe(arguments: [String]) -> AgentLaunchObservation {
    let explicitlyBypassesPermissions =
      arguments.contains("--dangerously-skip-permissions")
      || arguments.optionValue(long: "--permission-mode") == "bypassPermissions"
    return AgentLaunchObservation(
      model: arguments.optionValue(long: "--model", short: "-m"),
      executionMode: explicitlyBypassesPermissions ? .unrestricted : nil
    )
  }

  func makeStartInvocation(_ request: AgentStartRequest) throws -> AgentInvocation {
    AgentInvocation(executable: "claude", arguments: options(for: request.configuration) + [request.prompt])
  }

  func makeResumeInvocation(_ request: AgentResumeRequest) throws -> AgentInvocation {
    AgentInvocation(
      executable: "claude",
      arguments: ["-p", "--resume", request.session.id] + options(for: request.configuration) + [request.prompt]
    )
  }

  private func options(for configuration: AgentLaunchConfiguration) -> [String] {
    var options: [String] = []
    if let model = configuration.model {
      options += ["--model", model]
    }
    if configuration.executionMode == .unrestricted {
      options.append("--dangerously-skip-permissions")
    }
    return options
  }
}

nonisolated extension [String] {
  fileprivate func optionValue(long: String, short: String? = nil) -> String? {
    for (index, argument) in enumerated() {
      if argument == long || short == argument {
        let next = self.index(after: index)
        guard next < endIndex else { return nil }
        return self[next]
      }
      if argument.hasPrefix(long + "=") {
        return String(argument.dropFirst(long.count + 1))
      }
    }
    return nil
  }
}
