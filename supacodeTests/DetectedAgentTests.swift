import Testing

@testable import supacode

struct DetectedAgentTests {
  @Test func displayNamesUseCommandStyleTokens() {
    for agent in DetectedAgent.allCases {
      #expect(agent.displayName == agent.rawValue)
    }
  }
}
