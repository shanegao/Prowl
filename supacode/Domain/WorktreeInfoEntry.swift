import Foundation

/// A worktree branch's commit divergence from its base: `ahead` commits the
/// branch has that the base lacks, `behind` commits the base has that the branch
/// lacks. Modeled as one value (not two independent `Int?`s) so the pair is
/// always present-or-absent together — "ahead known but behind unknown" is
/// unrepresentable. The whole value is `nil` until computed or when no base
/// resolves.
struct AheadBehind: Equatable, Hashable, Sendable {
  let ahead: Int
  let behind: Int
}

struct WorktreeInfoEntry: Equatable, Hashable {
  var addedLines: Int?
  var removedLines: Int?
  var pullRequest: GithubPullRequest?
  /// Commits this worktree's branch is ahead of / behind its base (the repo's
  /// default remote branch, e.g. `origin/main`). `nil` until computed or when no
  /// base resolves. Surfaced in the no-PR toolbar status item.
  var aheadBehind: AheadBehind?
  /// Whether the branch exists on `origin` (pushed). `nil` until computed or when
  /// the check could not be determined (git error); `false` only on a confirmed
  /// absence. Drives the no-PR toolbar "not pushed" indicator.
  var isPushed: Bool?

  var isEmpty: Bool {
    addedLines == nil && removedLines == nil && pullRequest == nil
      && aheadBehind == nil && isPushed == nil
  }
}
