## 1. Forward migration: remember the original fetch refspec

- [x] 1.1 In `gitflow_init_setup_worktrees`, before rewriting `remote.origin.fetch`, store the current value as `gitflow.worktree.savedfetch` (only when `remote.origin.url` is configured and the value is not already saved); verify a migrated repository with an origin shows the saved key, and one without an origin shows none.
- [x] 1.2 Verify a second `init -f -w` does not overwrite an already saved refspec.

## 2. Rollback helpers in `git-flow-init`

- [x] 2.1 Add a rollback preflight helper that reports (non-zero + message) when: `.bare` is absent, the `develop` worktree is missing, `.gitflow-migrate-tmp` exists, or any non-`develop` worktree is dirty/unlocked; verify each condition aborts with its own message and that the repository is unchanged.
- [x] 2.2 Add a helper that stages the `develop` worktree's entries (skipping its `.git` file) into `.gitflow-migrate-tmp` and restores them on failure; verify a forced failure leaves `develop/` intact.
- [x] 2.3 Add the collapse helper: remove all linked worktrees with `worktree remove --force`, delete the hub `.git` pointer, `mv .bare .git`, set `core.bare false`, repoint `gitflow.path.hooks` from `.bare/hooks` to `.git/hooks`, force `HEAD` to `refs/heads/develop`, move the staged entries to the hub root, run `git reset -q`, `rmdir` empty prefix containers, restore `gitflow.worktree.savedfetch` if present (and unset it), and finally unset `gitflow.worktree`; verify with the end-to-end scenario below.
- [x] 2.4 Make the helper print a summary that lists: the branch checked out, the worktrees removed, the branches kept, and an explicit note when ignored files were discarded with the removed worktrees (`git status --porcelain --ignored=matching` on each discarded worktree before removal).

## 3. Wire the rollback into `git flow init`

- [x] 3.1 In `cmd_default`, the `--noworktree` branch SHALL call the collapse helper when `.bare` exists, and only clear the setting otherwise; verify both paths.
- [x] 3.2 Verify `git flow init -f -w` after a rollback migrates the repository again (round trip), and that `init -f` without a flag keeps the current mode.

## 4. Tests in `tests/smoke-worktree.sh`

- [x] 4.1 Happy path: worktree repo (master+develop, clean) → `init -f --noworktree` → `.bare` gone, `.git` is a directory, develop checked out and clean, `master/`/`develop/` gone, prefix containers gone, `gitflow.worktree` unset, all branches still present.
- [x] 4.2 Dirty `develop`: unstaged modification + untracked file survive the collapse and appear as such in `git status`.
- [x] 4.3 Dirty extra worktree (e.g. `master` or a clean-then-modified feature): rollback aborts, no worktree removed, `.bare` still present, message names the path.
- [x] 4.4 Clean feature worktree: rollback removes it, keeps `feature/<name>` as a local branch.
- [x] 4.5 Ignored files inside a discarded worktree are deleted and the summary mentions it.
- [x] 4.6 `--noworktree` on a classic repository only clears the setting.
- [x] 4.7 Hooks path is repointed to `.git/hooks` and the saved fetch refspec is restored.
- [x] 4.8 Register the new tests in the suite's invocation list and run `sh tests/smoke-worktree.sh` with all checks green.

## 5. Documentation

- [x] 5.1 Update the README's Worktree mode section: `--noworktree` now converts the repository back, what happens to extra worktrees and ignored files, and the recommended follow-up (`git checkout <branch>`).
- [x] 5.2 Update `CHANGELOG.md` with the rollback entry.
