# 010 — Plain Folder Support: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-24 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #48, #80, #553 |
| **Sources** | `doc-onevcat/plans/2026-03-24-plain-folder-support-plan.md` (absorbed here; original removed in the docs-ai migration), PR #48/#80/#548/#553 descriptions, change-list 2026-04-20 review batch |
| **Related** | [034-worktree-watcher-correctness](../034-worktree-watcher-correctness/000-plan.md), [042-project-workspaces](../042-project-workspaces/000-plan.md), `docs/concepts.md`, `docs/components/repositories-and-worktrees.md` |

## Background

Prowl's sidebar was git-only: the Add Repository flow resolved every picked folder
through `gitClient.repoRoot` and rejected failures as invalid roots. There was no way to
open an arbitrary folder (a scratch directory, a non-git project) in Prowl's terminal
tabs. The selection model was also worktree-centric — nothing could be "selected" unless
it was a git worktree — which made non-git folders impossible to represent without hacks.

## Goals

- Add plain (non-git) folders through the existing Add Repository flow.
- Persist and restore mixed `.git` and `.plain` entries (including the snapshot cache).
- Make a plain folder a first-class selectable sidebar item with a usable terminal
  detail view.
- Reuse non-git repository settings (open action, run script, custom commands) for
  plain folders.
- Gate git-only behavior through shared capabilities instead of scattered
  `kind == .git` checks.
- Keep mixed states coherent: git repos, plain folders, failed git loads.

### Non-goals

- Pull request support, branch operations, diff/line-change tracking, worktree
  creation/archive/delete, and GitHub integration for plain folders.

## Design / Approach

Condensed from the original plan document.

**Domain modeling.** Extend `Repository` with an explicit `Kind` (`.git` / `.plain`) and
a capabilities value (`supportsWorktrees`, `supportsBranchOperations`,
`supportsPullRequests`, `supportsDiff`, `supportsGitStatus`,
`supportsRunnableFolderActions`, `supportsRepositoryGitSettings`). `kind` expresses what
the repository *is*; capabilities express what UI and reducers *may do* with it. Views
prefer capabilities over direct kind checks. Explicit principle: no fake worktrees for
non-git folders.

**Selection model.** Repository selection becomes a first-class concept distinct from
worktree selection. Plain folders are selected at the repository level; git repositories
keep worktree-level selection, and their sidebar header row remains an expand/collapse
control.

**Persistence.** Replace path-only persistence (`repositoryRoots: [String]`) with an
explicit `PersistedRepositoryEntry { path, kind }`. Legacy roots keep decoding and are
migrated to entries on the first save. The startup snapshot cache
(006-startup-performance) gets a schema bump so it can carry `kind` and treat
zero-worktree repositories as valid content.

**Add/reload flow.** The file importer's URLs are first tried as git repositories; on
success a `.git` entry is stored for the resolved root, on failure a `.plain` entry is
stored for the original folder — "not a git repository" becomes a supported path instead
of an error. Reload additionally auto-upgrades a `.plain` entry to `.git` when the path
has become its own repository root (e.g. after `git init`), and conservatively
downgrades `.git` to `.plain` only when the path definitively stopped being a repository
root (transient probe failures must not downgrade).

**Capability gating.** Toolbar, context menus, command palette, and
`RepositorySettingsFeature` sections are driven by the selected target's capabilities:
plain folders keep Open / Run Script / Custom Commands / Copy Path / repository settings
/ Remove; branch rename, PR actions, diff actions, and worktree actions are hidden.
Settings skip git metadata loading when git capabilities are absent. Plain repositories
contribute nothing to `WorktreeInfoWatcher` feeds (PR refresh, line-change scheduling).

**Milestones** (executed in order): 1. domain + persistence, 2. discovery/loading,
3. selection + detail view, 4. capability gating, 5. settings reuse,
6. validation/cleanup. Model work lands before broad UI refactors so the app keeps
compiling per milestone.

## Alternatives & decisions

- **No fake worktrees.** A synthetic-worktree shortcut would have shipped faster but was
  explicitly rejected in the plan as long-term complexity; selection and detail were
  reworked instead.
- **Capabilities over kind checks.** Chosen so later features (e.g. workspaces, which
  reuse `.plain`) gate behavior uniformly instead of re-deriving what "plain" means.
- **Explicit persistence migration** instead of inferring entry kind from paths at every
  load; the detected kind is persisted after the first successful save.
- **Kept over upstream's version.** Upstream shipped its own non-git folder support about
  a month later (upstream #257, `68e44966`, reviewed in the 2026-04-20 change-list
  batch); the fork's implementation predates it and was kept — that batch recorded no
  action for it.

## Amendments

- Updated 2026-07-11: plain→git upgrade watchers (react to `git init` immediately) and
  their hardening — see [002-plain-upgrade-watchers.md](002-plain-upgrade-watchers.md)
