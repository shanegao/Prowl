import ComposableArchitecture
import Foundation
import GhosttyKit
import Testing

@testable import supacode

@MainActor
struct SupacodeAppCLITests {
  @Test func shellQuoteEscapesWhitespaceAndSingleQuotes() {
    #expect(SupacodeApp.shellQuote("/tmp/plain") == "/tmp/plain")
    #expect(SupacodeApp.shellQuote("/tmp/with space") == "'/tmp/with space'")
    #expect(SupacodeApp.shellQuote("/tmp/it'works") == "'/tmp/it'\"'\"'works'")
  }

  @Test func cliRouterWiresKeyAndReadHandlersInsteadOfStubHandlers() async {
    let store = Store(initialState: AppFeature.State()) {
      AppFeature()
    }
    let terminalManager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    let router = SupacodeApp.makeCLICommandRouter(appStore: store, terminalManager: terminalManager)

    let keyResponse = await router.route(
      CommandEnvelope(output: .json, command: .key(KeyInput(rawToken: "enter", token: "enter")))
    )
    let readResponse = await router.route(
      CommandEnvelope(output: .json, command: .read(ReadInput()))
    )

    #expect(keyResponse.command == "key")
    #expect(readResponse.command == "read")
    #expect(keyResponse.error?.code != "NOT_IMPLEMENTED")
    #expect(readResponse.error?.code != "NOT_IMPLEMENTED")
  }
}
