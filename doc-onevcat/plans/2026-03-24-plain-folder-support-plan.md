# Plain Folder Support Implementation Plan

## Goal

Allow users to add any folder to the sidebar.

Git repositories must keep their current behavior.
Plain folders must become first-class selectable items with a usable detail view, reusable non-git settings, and capability-gated actions.

## Scope

In scope:

- add plain folders from the existing Add Repository flow
- persist and restore mixed `git` and `plain` entries
- show plain folders in the sidebar
- allow selecting a plain folder as a real target
- support repository-level detail for plain folders
- reuse non-git repository settings for plain folders
- gate git-only behavior through shared capabilities
- keep mixed states working: git repos, plain folders, failed git loads

Out of scope:

- pull request support for plain folders
- branch operations for plain folders
- diff / line change tracking for plain folders
- worktree creation / archive / delete for plain folders
- GitHub integration for plain folders

## Principles

- Model `plain` folders in the domain layer, not only in UI row models.
- Avoid fake worktrees for non-git folders.
- Treat repository selection and worktree selection as different concepts.
- Use capabilities to gate behavior instead of scattering `kind == .git` checks.
- Migrate persistence explicitly instead of inferring long-term meaning from paths alone.
- Reuse existing settings UI where the semantics still make sense.

## Key Decisions

### 1. Repository Modeling

Extend `Repository` with explicit identity beyond `rootURL` and `worktrees`.

Recommended shape:

- `Repository.Kind`
  - `.git`
  - `.plain`
- `RepositoryCapabilities`
  - `supportsWorktrees`
  - `supportsBranchOperations`
  - `supportsPullRequests`
  - `supportsDiff`
  - `supportsGitStatus`
  - `supportsRunnableFolderActions`
  - `supportsRepositoryGitSettings`

Notes:

- `kind` expresses what the repository is.
- `capabilities` expresses what the UI and reducers may do with it.
- Views should prefer capabilities over direct kind checks.

### 2. Selection Model

Current behavior is effectively worktree-centric.
That is not sufficient once a repository may have zero worktrees.

The selected target needs to become explicit:

- repository selection remains valid for all repositories
- worktree selection remains valid for git repositories
- plain folders rely on repository selection, not synthetic worktree selection

The sidebar repository row must stop being only an expand/collapse control.
It must become a real selectable item for plain folders, and likely for git repositories as well to keep the model coherent.

### 3. Persistence Model

Replace path-only persistence with an explicit entry model.

Recommended persisted entry:

```swift
struct PersistedRepositoryEntry: Codable, Equatable, Sendable {
  var path: String
  var kind: Repository.Kind
}
```

Migration strategy:

- continue decoding legacy `repositoryRoots: [String]`
- transform legacy roots into persisted entries during load
- write back only the new structure after the first successful save

This same explicit kind must also be reflected in the repository snapshot payload.

### 4. Settings Reuse

Keep `RepositorySettingsFeature` as the shared entry point.

Behavior:

- plain folders reuse non-git settings
- git/worktree-only sections are hidden by capability
- git-only async loading is skipped when unsupported

Expected reusable areas:

- open action
- run script
- custom commands
- onevcat-specific settings that do not require git metadata

Expected hidden areas:

- base ref options
- branch-derived defaults
- worktree creation options that only make sense for git
- bare repository handling

## Data Flow Changes

### Add Repository Flow

Current flow:

1. file importer returns folder URLs
2. reducer resolves each URL through `gitClient.repoRoot`
3. failures are rejected as invalid roots

Target flow:

1. file importer returns folder URLs
2. reducer tries to resolve each URL as a git repository
3. if resolution succeeds, store a `.git` entry for the resolved root
4. if resolution fails, store a `.plain` entry for the original folder
5. merged persisted entries are saved
6. live loading builds repositories from those entries

This makes "not a git repository" a supported path instead of an error.

### Reload Flow

Current reload assumes all stored roots are git repositories.

Target reload must:

- load persisted repository entries
- for `.git`, fetch worktrees and build a git repository
- for `.plain`, build a plain repository with zero worktrees
- only record load failures for entries that were expected to be git but cannot currently load

### Snapshot Flow

Snapshot caching must persist enough information to restore both kinds.

Required additions:

- repository kind
- zero-worktree repositories must be valid snapshot content

Invalidation rules remain disposable and conservative.

## UI Plan

### Sidebar

Sidebar needs to support three distinct row concepts:

- repository row
- worktree row
- special rows such as archived worktrees / canvas

Repository row behavior:

- selectable
- expandable where relevant
- capability-driven actions

Plain folder sidebar behavior:

- selecting the repository row selects the folder
- expand/collapse may be disabled or become a no-op if there are no children
- git-only affordances are hidden

Git repository sidebar behavior:

- existing child worktree presentation remains
- repository row still supports selection, not only expansion
- worktree rows remain individually selectable

### Detail View

Plain folders need a repository-level detail branch.

V1 repository detail for plain folders should support:

- name and path presentation
- open action
- run script action
- custom commands
- empty-state style explanation for unavailable git features

Git repositories keep the current worktree-based terminal detail flow.

### Toolbar and Menus

Toolbar and context menus must be driven by the selected target's capabilities.

Hide for plain folders:

- rename branch
- pull request actions
- diff actions backed by git line changes
- worktree archive / delete actions
- new worktree

Keep for plain folders where meaningful:

- open in configured destination
- copy path
- run script
- custom commands
- repository settings
- remove repository

## Reducer and Client Work

### RepositoriesFeature

Primary changes:

- introduce repository entry loading instead of raw root loading
- update open / reload / restore flows
- make repository selection a first-class reducer concept
- make worktree creation resolution ignore repositories without `supportsWorktrees`
- skip git-only effects for repositories lacking required capabilities

Specific hotspots:

- `openRepositories`
- `loadPersistedRepositories`
- `reloadRepositories`
- `loadRepositoriesData`
- `repositoryForWorktreeCreation`
- `canCreateWorktree`
- repository row selection behavior
- alert text and empty-state copy

### AppFeature

Primary changes:

- stop assuming all useful selection state comes from `selectedWorktree`
- support repository-level selection for plain folders
- keep worktree-driven terminal setup only for git worktrees
- drive settings and open actions from the selected target

Likely additions:

- repository-level settings loading path
- repository-level open/run/custom-command behavior

### WorktreeInfoWatcher

Only git worktrees should be sent into watcher infrastructure.

This means:

- plain repositories contribute nothing to watcher state
- PR refresh scheduling ignores plain repositories
- line change scheduling ignores plain repositories

### Command Palette

Command palette must filter items by capability.

Keep for plain folders:

- open repository
- open settings
- refresh
- repository selection
- run/custom command actions if targetable

Hide for plain folders:

- new worktree
- PR actions
- archive/delete worktree actions

## Settings Plan

### RepositorySettingsFeature

Keep the feature, but make it repository-aware instead of implicitly git-aware.

Changes:

- accept repository kind and capabilities in state
- skip git requests when git capabilities are absent
- hide unsupported settings sections in the view layer
- preserve existing behavior for git repositories

Risk:

- current settings loading is frequently driven from selected worktree root URL
- plain folders may require a repository-level settings load path to avoid worktree-only assumptions

### Repository Settings Storage

Existing per-root settings storage can remain keyed by root path.

That is still valid for plain folders as long as:

- the root path is stable
- unsupported fields are ignored or hidden
- old git-specific values do not break plain folder UI

## Migration Plan

### Persisted Settings

Add new persisted repository-entry storage while continuing to read the old `repositoryRoots` field.

Migration steps:

1. decode new entries if present
2. otherwise decode legacy roots
3. map legacy roots to default entries
4. save back in the new format on the next write

Default entry mapping for legacy roots:

- attempt git discovery during load
- persist the detected kind after the first successful save

### Snapshot Cache

Bump snapshot schema version.

Rules:

- old snapshot versions are discarded
- new snapshot supports both `.git` and `.plain`
- zero-worktree repositories are valid snapshot content

## Testing Strategy

### Reducer Tests

Add reducer coverage for:

- adding a plain folder
- adding mixed plain and git folders
- reloading mixed persisted entries
- selecting a plain repository
- preventing worktree creation on plain folders
- gating git-only actions on plain folders

### Persistence Tests

Add persistence coverage for:

- legacy path-only data migration
- new repository entry encode/decode
- snapshot restore for plain repositories
- snapshot invalidation on schema mismatch

### Command Palette Tests

Add coverage for:

- plain folder selection entries remain visible
- git-only command palette items disappear for plain folders
- mixed repository sets still prune recency correctly

### Settings Tests

Add coverage for:

- plain folders skip git metadata loading
- reusable settings persist for plain folders
- unsupported git sections remain hidden or inactive

### Integration Validation

Manual validation checklist:

1. Add a non-git folder.
2. Restart the app and confirm it restores.
3. Select the folder and confirm detail view is usable.
4. Open the folder via the configured open action.
5. Confirm run script and custom commands remain available.
6. Confirm git-only actions are absent.
7. Add a git repository and confirm current worktree flow still works.
8. Confirm mixed sidebar ordering and selection remain stable.

## Milestones

### Milestone 1: Domain and Persistence

- add `Repository.Kind`
- add repository capabilities
- add persisted repository entry model
- migrate settings storage
- migrate snapshot payload

Tasks:

1. Add `Repository.Kind` and `RepositoryCapabilities` to the domain model.
2. Add repository-entry persistence models and legacy decode compatibility.
3. Update repository snapshot payload to persist `kind`.
4. Add persistence tests for legacy migration and mixed restore.

### Milestone 2: Discovery and Loading

- update Add Repository flow
- update reload flow
- build plain repositories during live load
- keep failure handling only for real git load failures

Tasks:

1. Introduce repository-entry loading in `RepositoryPersistenceClient`.
2. Update `openRepositories` to classify `.git` vs `.plain`.
3. Update live reload paths to load mixed entries.
4. Add reducer tests for add/reload of mixed git/plain repositories.

### Milestone 3: Selection and Detail

- make repository selection first-class
- add plain folder detail
- update sidebar repository row behavior

Tasks:

1. Promote repository selection to a real reducer/view state transition.
2. Update sidebar repository rows to support selection without breaking expand/collapse.
3. Add repository-level detail view for plain folders.
4. Add reducer and detail-view tests for plain folder selection.

### Milestone 4: Capability Gating

- gate reducer actions
- gate watcher feeds
- gate toolbar, menus, command palette

Tasks:

1. Gate worktree creation and other reducer entry points by capability.
2. Exclude plain repositories from watcher and PR refresh feeds.
3. Hide unsupported toolbar, row, and command palette actions.
4. Add tests for capability-driven command palette and reducer behavior.

### Milestone 5: Settings Reuse

- reuse repository settings for plain folders
- hide git-only sections
- add repository-level settings path where needed

Tasks:

1. Make `RepositorySettingsFeature` accept repository capabilities.
2. Skip git metadata loading when unsupported.
3. Hide git-only settings sections while preserving reusable fields.
4. Add tests covering plain-folder settings loading and persistence.

### Milestone 6: Validation and Cleanup

- migration tests
- mixed-state regression tests
- copy cleanup
- final build verification

Tasks:

1. Update empty-state and alert copy to mention folders, not only git repositories.
2. Add mixed-state regression coverage across repositories, snapshots, and settings.
3. Run targeted test suites for each milestone.
4. Run final app build verification.

## Execution Order

Recommended implementation order:

1. finish domain and persistence first
2. wire repository discovery and reload
3. make selection and detail coherent
4. gate git-only actions by capability
5. adapt settings reuse
6. run regression and build verification

This order keeps the model stable before touching broad UI surfaces.

## Change Plan

Use one `jj` change per milestone-sized task group:

1. `plan: detail plain-folder support tasks`
2. `model: add repository kind and persisted entries`
3. `load: support plain folders in repository discovery`
4. `ui: support repository selection and plain folder detail`
5. `capability: gate git-only actions for plain folders`
6. `settings: reuse repository settings for plain folders`
7. `verify: add regression coverage and final copy cleanup`

Execution workflow:

- describe each change up front
- `jj edit` into the target change before implementation
- follow TDD for logic-layer work inside each change
- keep tests green before moving to the next change

## Risks

- The largest risk is hidden dependence on `selectedWorktree` across reducers and views.
- The second largest risk is repository settings still being loaded indirectly from worktree state.
- A fake-worktree shortcut would appear faster but would increase long-term complexity and should be avoided.
- Mixed persisted state must stay deterministic to avoid sidebar flicker or accidental load failures after migration.

## Rollout Notes

- This work is large enough to land in multiple focused commits or PR-sized slices.
- Domain and persistence should land before broad UI refactors.
- Each milestone should keep the app compiling even if the full feature is not yet user-complete.
