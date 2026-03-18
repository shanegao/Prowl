Sync upstream changes into the fork's main branch.

Follow the workflow documented in `doc-onevcat/fork-sync-and-release.md`:

1. Run `./doc-onevcat/scripts/sync-upstream-main.sh`
2. If there are merge conflicts, resolve them by preserving our fork customizations (see `doc-onevcat/change-list.md` for reference)
3. After resolving conflicts, stage the resolved files, then complete the merge commit with `git commit --no-edit`
4. Verify the build with `make build-app` (clear SPM cache at `/tmp/supacode-spm-cache/SourcePackages` if dependency resolution fails)
5. Push to origin: `git push origin main`
6. Report what was synced (upstream commit range) when done
