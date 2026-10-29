## Context

See `proposal.md` - Why. The forward migration (`gitflow_init_setup_worktrees` in `git-flow-init`) turns `.git` into `.bare`, registers `master`/`develop` worktrees, creates one container directory per branch-type prefix, rewrites `remote.origin.fetch` to `+refs/heads/*:refs/remotes/origin/*`, and repoints `gitflow.path.hooks` from `<hub>/.git/hooks` to `<hub>/.bare/hooks`. It also preserves top-level ignored directories and nested Git repositories in the hub root.

The observed layout after a migration (verified on a real repository):

```
hub/
├── .git            → pointer file "gitdir: ./.bare"
├── .bare/          → core.bare=true; HEAD: refs/heads/develop; index; hooks/; worktrees/{develop,master}
├── develop/        → checked-out worktree (has its own .git file)
├── master/         → checked-out worktree
├── feature/ bugfix/ hotfix/ release/ support/
└── (ignored/nested dirs left intact by the forward migration)
```

Disabling today only writes `gitflow.worktree=false` and warns that collapsing is manual.

## Goals / Non-Goals

**Goals:**
- Make `git flow init -f --noworktree` a complete, safe inverse of the forward migration.
- Never destroy uncommitted work: abort before mutating when anything other than `develop` is dirty or locked.
- Preserve the `develop` working tree exactly (tracked modifications and untracked files).
- Keep the change within `git-flow-init` plus the shared helpers already in `gitflow-common`.

**Non-Goals:**
- Collapsing from a dirty *extra* worktree by stashing/merging it automatically.
- Restoring submodule gitdir layouts (same out-of-scope caveat as the forward migration).
- Recreating the original single-tree repository when `.bare` is absent.
- Choosing a branch other than `develop` for the final checkout (explicit product decision).

## Decisions

### 1. Trigger: explicit `--noworktree` only
`git flow init -f --noworktree` performs the collapse; `init -f` without mentioning the flag keeps the sticky behavior already implemented. Making a plain reinit collapse the layout would be destructive by accident, and the short flag `-w` toggles defaults in shFlags, so the explicit long form is the unambiguous one.

### 2. Preflight before any mutation
Sequence, all read-only:
1. `.bare` exists? If not, only clear the setting (today's behavior).
2. The `develop` worktree is registered and present at `<hub>/develop`; otherwise abort.
3. No `.gitflow-migrate-tmp` staging directory is left over.
4. Every other linked worktree (`master`, and any feature/bugfix/hotfix/release/support worktree) has an empty `git status --porcelain` and is not locked. On failure, abort listing the blocking paths.

This is what keeps the destructive window small: everything that can fail cheaply is checked first.

### 3. `develop` is the surviving checkout
`.bare/HEAD` normally already points at `develop` (the branch active when the forward migration ran). The collapse still forces `HEAD` to `refs/heads/develop` before the index resync, so the outcome does not depend on historical state. Content preservation works like the forward migration in reverse: move `develop/`'s entries (except its `.git` file) into `.gitflow-migrate-tmp`, later move them back to the hub root, and finish with `git reset -q` so the index matches `HEAD` while the working files stay untouched. Staged changes in `develop` become unstaged; no content is lost.

### 4. Deletion order
1. Stage `develop/`'s content.
2. `git --git-dir=.bare worktree remove --force` for every linked worktree (including the now-empty `develop`). `--force` is safe here precisely because the preflight established cleanliness and we moved the surviving content ourselves; without it, git would refuse the emptied `develop` worktree as "dirty".
3. Remove the hub's `.git` pointer file, `mv .bare .git`, set `core.bare false`.
4. Repoint `gitflow.path.hooks` when it equals `<hub>/.bare/hooks`.
5. `git symbolic-ref HEAD refs/heads/develop`.
6. Move the staged entries to the hub root.
7. `git reset -q`, then `rmdir` empty prefix containers, then unset `gitflow.worktree`.

From step 3 on, the repository is already a functioning classic checkout, so a failure in steps 6-7 degrades to "files are in the staging directory" rather than an unusable repository.

Alternative considered: register the surviving worktree with `git worktree move` into the hub root. Rejected: the hub root is not a worktree, and moving a worktree onto a directory that must become the main working tree leaves `.git` as a file rather than a directory.

### 5. "Clean" excludes ignored files on purpose
`git status --porcelain` does not report ignored files, so ignored content inside discarded worktrees is deleted. Requiring ignored files to be absent as well would block routine rollbacks (`node_modules`, build output), so the design accepts the loss and states it in the summary. This matches the user decision.

### 6. Save the original fetch refspec on the forward migration
The forward migration rewrites `remote.origin.fetch` and cannot recover the previous value later. Store it once, before rewriting, as `gitflow.worktree.savedfetch` (only when `remote.origin.url` exists). The collapse restores it and unsets the key. Repositories that migrated before this change have no saved value; they keep the permissive rewrite, which is a superset of normal fetch behavior.

### 7. Reuse the forward migration's staging helpers
`gitflow_init_restore_staging` already restores a partially populated staging directory; the collapse reuses the same pattern and error messaging for its staging phase so both directions behave identically on failure.

## Risks / Trade-offs

- **[Risk] A crash between removing the worktrees and renaming `.bare` leaves the repository without usable checkouts.** → Mitigation: preflight makes this window depend only on filesystem operations that rarely fail; the message tells the user the branches are intact and how to re-add the worktrees (`git --git-dir=.bare worktree add <path> <branch>`).
- **[Risk] Ignored files in discarded worktrees are lost.** → Mitigation: explicitly reported in the summary; documented in README.
- **[Risk] A dirty `develop` with staged deletions could surprise the user after `git reset`.** → Mitigation: content is never touched; only the index is re-synced, and the summary reports the resulting status.
- **[Risk] Repositories migrated before this change cannot recover their original fetch refspec.** → Mitigation: documented; the rewritten value is functionally a superset.
- **[Risk] Locked worktrees make removal fail after preflight (race).** → Mitigation: preflight detects locks; removal failure aborts with the same actionable message and leaves `.bare` in place.

## Migration Plan

- No action for classic repositories or for repos that keep worktree mode enabled.
- Rollback is invoked explicitly (`git flow init -f --noworktree`) and is itself the migration; there is no background/automatic path.
- Suggested user flow after rollback: `git checkout <branch>` for any previously worktree-backed branch, then continue with the classic Git Flow commands.
