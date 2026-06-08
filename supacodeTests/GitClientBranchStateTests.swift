import Foundation
import Testing

@testable import supacode

struct GitClientAheadBehindTests {
  /// Stubs the three git calls `aheadBehind` makes in order: `symbolic-ref` (base
  /// resolution) → `rev-parse --verify` (the refExists check) → `rev-list
  /// --left-right --count`. Outputs are pre-trimmed, matching the real
  /// `ShellClient`, which normalizes/trims stdout before `runGit` reads it.
  private func makeClient(revListOutput: String) -> GitClient {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("symbolic-ref") {
          return ShellOutput(stdout: "refs/remotes/origin/main", stderr: "", exitCode: 0)
        }
        if arguments.contains("rev-parse") {
          return ShellOutput(stdout: "0123456789abcdef", stderr: "", exitCode: 0)
        }
        if arguments.contains("rev-list") {
          return ShellOutput(stdout: revListOutput, stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    return GitClient(shell: shell)
  }

  @Test func aheadBehindMapsLeftRightCountAsBehindThenAhead() async {
    // `git rev-list --left-right --count base...HEAD` prints "<behind>\t<ahead>",
    // so the columns must map to behind=counts[0], ahead=counts[1]. This pins that
    // ordering — a swap would silently flip the toolbar's ↑/↓ counts.
    let client = makeClient(revListOutput: "1\t3")
    let result = await client.aheadBehind(
      for: URL(fileURLWithPath: "/tmp/repo/feature"),
      repositoryRoot: URL(fileURLWithPath: "/tmp/repo")
    )
    #expect(result?.ahead == 3)
    #expect(result?.behind == 1)
  }

  @Test func aheadBehindReturnsNilWhenCountsUnparseable() async {
    let client = makeClient(revListOutput: "garbage-output")
    let result = await client.aheadBehind(
      for: URL(fileURLWithPath: "/tmp/repo/feature"),
      repositoryRoot: URL(fileURLWithPath: "/tmp/repo")
    )
    #expect(result == nil)
  }

  @Test func aheadBehindReturnsNilWhenNoBaseResolves() async {
    // Every git call fails (as the real shell does — by throwing), so neither
    // origin/HEAD nor the origin/main fallback resolves a base: aheadBehind
    // returns nil and rev-list must never run.
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("rev-list") {
          Issue.record("rev-list should not run when no base resolves")
        }
        throw ShellClientError(command: "git", stdout: "", stderr: "fatal: not a ref", exitCode: 1)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)
    let result = await client.aheadBehind(
      for: URL(fileURLWithPath: "/tmp/repo/feature"),
      repositoryRoot: URL(fileURLWithPath: "/tmp/repo")
    )
    #expect(result == nil)
  }
}

struct GitClientRemoteBranchExistsTests {
  /// Stubs `for-each-ref`. A non-zero `exitCode` throws `ShellClientError` to match
  /// the real `ShellClient`, which throws (rather than returning) on git failure.
  private func makeClient(output: String, exitCode: Int32) -> GitClient {
    let shell = ShellClient(
      run: { _, _, _ in
        if exitCode != 0 {
          throw ShellClientError(command: "git", stdout: output, stderr: "", exitCode: exitCode)
        }
        return ShellOutput(stdout: output, stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    return GitClient(shell: shell)
  }

  @Test func returnsTrueWhenExactRefPresent() async {
    let client = makeClient(output: "refs/remotes/origin/feature", exitCode: 0)
    let result = await client.remoteBranchExists(
      for: URL(fileURLWithPath: "/tmp/repo"), branch: "feature")
    #expect(result == true)
  }

  @Test func returnsFalseWhenAbsent() async {
    // `for-each-ref` exits 0 with empty output when nothing matches.
    let client = makeClient(output: "", exitCode: 0)
    let result = await client.remoteBranchExists(
      for: URL(fileURLWithPath: "/tmp/repo"), branch: "feature")
    #expect(result == false)
  }

  @Test func rejectsNonExactSiblingRef() async {
    // A sibling ref (`feature-2`) must not count as `feature` being present.
    let client = makeClient(output: "refs/remotes/origin/feature-2", exitCode: 0)
    let result = await client.remoteBranchExists(
      for: URL(fileURLWithPath: "/tmp/repo"), branch: "feature")
    #expect(result == false)
  }

  @Test func returnsNilOnGitError() async {
    // A genuine git failure (non-zero exit) is distinct from a confirmed absence,
    // so the result is nil ("unknown"), not false ("not pushed").
    let client = makeClient(output: "", exitCode: 128)
    let result = await client.remoteBranchExists(
      for: URL(fileURLWithPath: "/tmp/repo"), branch: "feature")
    #expect(result == nil)
  }

  @Test func returnsFalseForEmptyBranch() async {
    let client = makeClient(output: "refs/remotes/origin/anything", exitCode: 0)
    let result = await client.remoteBranchExists(
      for: URL(fileURLWithPath: "/tmp/repo"), branch: "")
    #expect(result == false)
  }
}
