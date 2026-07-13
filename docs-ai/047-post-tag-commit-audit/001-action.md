# 047 — Post-Tag Commit Audit: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-13 | Established `v2026.7.10` as the latest reachable release baseline and inventoried the range. | `v2026.7.10..a933ab9d` |
| 2026-07-13 | Reviewed all 33 commits, including merge grouping and all non-merge implementation and test diffs. | PRs #553, #556, #577–#581, #585 |
| 2026-07-13 | Ran focused regressions, the full app test suite, and the Debug app build. | Local verification |

## Outcome & current state (as of 2026-07-13)

- The range contains seven delivered behavior groups: plain repository upgrade watching and
  symlink roots; native agent session identification; documentation migration; update-channel
  and obsolete release-target removal; Active Agents pane titles; reliable worktree deletion;
  and CLI short handles. The remaining commits are merge commits or targeted test stabilization.
- No release-blocking product-code defect was found in the inspected final state. The watcher
  path handles monitor-construction failures, repeated events, and symlinked roots; deletion
  restores a relocated directory after Git cleanup fails; and text-only CLI handles leave the
  v1 JSON payload shape unchanged.
- Two low-severity documentation follow-ups remain: `supacode/CLIService/OpenCommandHandler.swift`
  still names the removed `doc-onevcat/contracts/cli/open.md` path, and the living
  `docs-ai/020-observability/runbook.md` still describes the removed update-channel-based Sentry
  environment selection. The latter now always uses `"production"` in `supacode/App/supacodeApp.swift`.
- The native-session profiles intentionally track third-party CLI layouts directly. Their
  existing unit fixtures cover parser, scan-cap, attribution, stale-pid, and ambiguity rules;
  a future compatibility canary tied to each supported CLI release would reduce upstream-layout
  drift risk but is not a defect in this range.

## Tests and verification

- `git diff --check v2026.7.10..a933ab9d` passed.
- 19 focused Swift Testing cases passed across watcher upgrades, repository root resolution,
  session attribution, pane-title refresh, worktree deletion, handle lifecycle and resolution,
  and text/JSON CLI payload compatibility.
- `make test` passed: 1,798 tests, 0 failures, 0 skipped.
- `make build-app` passed, including `prowl` CLI and Debug app builds.

## Deviations from plan

None known. The audit found documentation drift but did not change product behavior or repair
those separate follow-ups.

## Open questions

- The two documentation follow-ups should be made in a narrow docs-only change; they were left
  separate so this audit remains a review record rather than an opportunistic fix.
