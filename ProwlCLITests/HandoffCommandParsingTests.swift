import ProwlCLIShared
import XCTest

@testable import prowl

final class HandoffCommandParsingTests: XCTestCase {
  func testSaveAcceptsPositionalTarget() throws {
    let command = try HandoffSaveCommand.parse(["App"])

    XCTAssertEqual(
      try command.selector.resolve(positionalTarget: command.target),
      .auto("App")
    )
  }

  func testToAcceptsPositionalTargetAfterAgent() throws {
    let command = try HandoffToCommand.parse(["claude", "App"])

    XCTAssertEqual(command.agent, "claude")
    XCTAssertEqual(
      try command.selector.resolve(positionalTarget: command.target),
      .auto("App")
    )
  }

  func testStatusAcceptsPositionalTarget() throws {
    let command = try HandoffStatusCommand.parse(["App"])

    XCTAssertEqual(
      try command.selector.resolve(positionalTarget: command.target),
      .auto("App")
    )
  }
}
