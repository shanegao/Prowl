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

  func testSaveRejectsPositionalTargetAlongsideFlagSelector() throws {
    let command = try HandoffSaveCommand.parse(["App", "--worktree", "Other"])

    XCTAssertThrowsError(try command.selector.resolve(positionalTarget: command.target))
  }

  func testSaveParsesNoPrepareFlag() throws {
    XCTAssertFalse(try HandoffSaveCommand.parse(["App"]).noPrepare)
    XCTAssertTrue(try HandoffSaveCommand.parse(["App", "--no-prepare"]).noPrepare)
  }

  func testToAcceptsPositionalTargetAfterAgent() throws {
    let command = try HandoffToCommand.parse(["claude", "App"])

    XCTAssertEqual(command.agent, "claude")
    XCTAssertEqual(
      try command.selector.resolve(positionalTarget: command.target),
      .auto("App")
    )
  }

  func testToParsesNoPrepareFlag() throws {
    let command = try HandoffToCommand.parse(["claude", "App", "--no-prepare", "--no-launch"])

    XCTAssertTrue(command.noPrepare)
    XCTAssertTrue(command.noLaunch)
  }

  func testStatusAcceptsPositionalTarget() throws {
    let command = try HandoffStatusCommand.parse(["App"])

    XCTAssertEqual(
      try command.selector.resolve(positionalTarget: command.target),
      .auto("App")
    )
  }
}
