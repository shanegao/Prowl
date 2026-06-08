import Foundation
import Testing

@testable import supacode

struct CommandPaletteFuzzyScorerTests {
  private func makeScorer(query: String) -> CommandPaletteFuzzyScorer {
    // `bestContiguousMatch` takes its query/target as parameters, so the scorer's own
    // `query`/recency/`now` don't affect it — a fixed date keeps the instance deterministic.
    CommandPaletteFuzzyScorer(query: query, recencyByID: [:], now: Date(timeIntervalSince1970: 0))
  }

  @Test func contiguousMatchReturnsSubstringPositions() {
    let scorer = makeScorer(query: "send")
    let result = scorer.bestContiguousMatch(
      query: Array("send"), queryLower: Array("send"),
      target: Array("QuickSend"), targetLower: Array("quicksend"))
    // "send" occupies offsets 5...8 of "QuickSend".
    #expect(result?.1 == [5, 6, 7, 8])
  }

  @Test func contiguousMatchPrefersEarliestRun() {
    let scorer = makeScorer(query: "ab")
    let result = scorer.bestContiguousMatch(
      query: Array("ab"), queryLower: Array("ab"),
      target: Array("abxab"), targetLower: Array("abxab"))
    // "ab" matches at [0,1] and [3,4]; the start-of-string run wins (strict `>` also
    // keeps the left-most on a tie), so highlights never drift right.
    #expect(result?.1 == [0, 1])
  }

  @Test func contiguousMatchTreatsSlashAndBackslashAsEqual() {
    let scorer = makeScorer(query: "a/b")
    let result = scorer.bestContiguousMatch(
      query: Array("a/b"), queryLower: Array("a/b"),
      target: Array("a\\b"), targetLower: Array("a\\b"))
    // `/` ≈ `\` via considerAsEqual, so the run still matches.
    #expect(result?.1 == [0, 1, 2])
  }

  @Test func contiguousMatchReturnsNilWhenNoRunMatches() {
    let scorer = makeScorer(query: "xyz")
    let result = scorer.bestContiguousMatch(
      query: Array("xyz"), queryLower: Array("xyz"),
      target: Array("abcdef"), targetLower: Array("abcdef"))
    // No contiguous run → caller falls through to the scattered DP scorer.
    #expect(result == nil)
  }

  @Test func contiguousMatchReturnsNilWhenQueryLongerThanTarget() {
    let scorer = makeScorer(query: "abcd")
    let result = scorer.bestContiguousMatch(
      query: Array("abcd"), queryLower: Array("abcd"),
      target: Array("abc"), targetLower: Array("abc"))
    #expect(result == nil)
  }
}
