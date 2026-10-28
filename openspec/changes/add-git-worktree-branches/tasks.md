## 1. Shared foundation (`gitflow-common`)

- [x] 1.1 Add a `gitflow_worktree_enabled()` helper reading `git config --bool gitflow.worktree`, and verify it returns false on a repo that never ran init with worktree mode.
- [x] 1.2 Add `gitflow_worktree_hub_dir()` (derives `<hub>` as the parent of `git rev-parse --path-format=absolute --git-common-dir`) and `gitflow_worktree_path_for_branch()` (returns `<hub>/<branch>`), and verify both resolve correctly from the hub root and from inside a linked worktree.
- [x] 1.3 Add `gitflow_worktree_add()`, wrapping `git worktree add <path> [-b <branch>] <start-point>`, used in place of `git_do checkout -b`; verify it creates the expected directory and checks out the branch nowhere else.
- [x] 1.4 Add `gitflow_worktree_remove()`, wrapping `git worktree remove --force <path>` with explicit failure handling (die with a retry-guidance message, without touching the branch ref, if removal fails); verify both the success path and a simulated removal failure (e.g. a file held open) abort before any `git branch -d/-D` call.
- [x] 1.5 Add `gitflow_worktree_move()`, wrapping `git worktree move <old-path> <new-path>`, for use by rename; verify `git worktree list` reflects the new path afterward.
- [x] 1.6 Change `gitflow_load_settings` to derive `DOT_GIT_DIR` (or a new `COMMON_GIT_DIR`) from `git rev-parse --git-common-dir` instead of `--git-dir`, and verify `HOOKS_DIR` and the `.gitflow/MERGE_BASE`/`SQUASH_MSG` paths resolve identically whether invoked from the hub root or from a linked worktree.
- [x] 1.7 Update `gitflow_rename_branch` to call `gitflow_worktree_move()` (when worktree mode is enabled) alongside the existing `git branch -m`, and verify a rename updates both the branch ref and the worktree location together.
- [x] 1.8 Extend `run_pre_hook`/`run_post_hook` to accept and append a worktree-path argument, defaulting to an empty string, and verify a hook script receives it as its last argument without affecting existing arguments.

## 2. `git-flow-init`: opt-in activation and layout migration

- [x] 2.1 Add a `worktree` boolean flag/prompt to `git flow init`, stored as `gitflow.worktree`, defaulting to false; verify a plain `git flow init` leaves it unset.
- [x] 2.2 Gate changing `gitflow.worktree` on an already-initialized repo behind the existing `-f`/force flag, reusing the `gitflow_is_initialized` guard; verify a second `init` without `-f` leaves the setting untouched and warns, and `init -f` allows changing it.
- [x] 2.3 Implement the `.bare` migration: move `.git` to `.bare`, relocate the repository root's currently checked-out content into a worktree directory named after whichever branch was checked out there, and fix up `remote.origin.fetch` so remote-tracking refs populate correctly; verify with a fetch/pull from origin after migration.
- [x] 2.4 Create (or attach) the `master` worktree if it does not already have one, and the `develop` worktree from the relocated content (or fresh, if develop wasn't already checked out); verify `git worktree list` shows exactly these two permanent worktrees after init.
- [x] 2.5 Create empty, persistent container directories for each configured prefix (`feature/`, `bugfix/`, `hotfix/`, `release/`, `support/`); verify they exist and remain empty immediately after init.
- [x] 2.6 Update the hooks-path default suggestion in `git-flow-init` to use `--git-common-dir` instead of `--git-dir`, matching the `gitflow-common` fix; verify the suggested default hooks path is the same regardless of which worktree `init -f` is run from.
- [x] 2.7 Verify end-to-end: running `init` with worktree mode off on a fresh repo produces byte-for-byte the same layout as today (no `.bare`, no prefix directories).

## 3. `git-flow-feature` lifecycle

- [x] 3.1 `cmd_start`/`cmd_track`: replace `checkout -b` with `gitflow_worktree_add()` when worktree mode is enabled; verify `git flow feature start`/`track` create `<hub>/feature/<name>` and leave other worktrees untouched.
- [x] 3.2 `cmd_finish`: route the merge (and squash-commit, when used) through the base branch's worktree (`git -C <hub>/<base>`), then call `gitflow_worktree_remove()` before `git branch -d/-D`, removing the existing "checkout base to evacuate" block; verify a clean finish, a conflicting finish (conflict appears in the base worktree, feature worktree untouched, resumable finish), and a squash finish.
- [x] 3.3 `cmd_delete`: remove the pre-delete checkout-to-base step; call `gitflow_worktree_remove()` before `git branch -d/-D`; verify deleting both a merged and an unmerged (`-f`) feature branch.
- [x] 3.4 `cmd_rebase`/`cmd_pull` (existing branch path): replace the leading checkout with operating via `git -C <hub>/<branch>`; verify rebase/pull succeed when invoked from a different worktree than the target branch's.
- [x] 3.5 `cmd_pull` (new branch path): replace `branch --no-track` + `checkout` with `gitflow_worktree_add()`; verify a first-time pull creates the expected worktree.
- [x] 3.6 `cmd_publish`: drop the trailing checkout when worktree mode is enabled; verify publish no longer changes any worktree's checked-out branch.
- [x] 3.7 `cmd_checkout`/`cmd_co`: when worktree mode is enabled, resolve and print the branch's worktree path instead of checking it out; verify output and that no worktree's checkout changes.
- [x] 3.8 `cmd_rename`: verify (via the shared `gitflow_rename_branch` change in 1.7) that renaming a feature branch moves its worktree.
- [x] 3.9 Verify every command above still behaves exactly as today when `gitflow.worktree` is disabled (regression pass against the classic flow).

## 4. `git-flow-bugfix` lifecycle

- [x] 4.1 Apply the same changes as Section 3 (start, finish, delete, rebase, pull, publish, checkout/co, rename) to `git-flow-bugfix`, verifying each with the same scenarios.

## 5. `git-flow-hotfix` lifecycle

- [x] 5.1 `cmd_start`: replace `checkout -b` with `gitflow_worktree_add()`; verify.
- [x] 5.2 `cmd_finish`: route the master merge+tag and the develop merge through `git -C <hub>/master` then `git -C <hub>/develop`, then `gitflow_worktree_remove()` before branch deletion; verify a clean finish and a finish with conflicts at each merge stage.
- [x] 5.3 `cmd_delete`: apply the worktree-first deletion order; verify.
- [x] 5.4 `cmd_track`/`cmd_publish`/`cmd_rebase`: apply the same worktree-add / drop-trailing-checkout / operate-via-`-C` changes as feature; verify.
- [x] 5.5 `cmd_rename`: verify worktree relocation via the shared helper.
- [x] 5.6 Verify classic-mode (worktree disabled) behavior is unchanged.

## 6. `git-flow-release` lifecycle

- [x] 6.1 `cmd_start`: replace `checkout -b` with `gitflow_worktree_add()`; verify.
- [x] 6.2 `cmd_finish`: route the master merge+tag then develop merge through `git -C <hub>/master` / `git -C <hub>/develop`, then `gitflow_worktree_remove()` before branch deletion; verify clean and conflicting finishes.
- [x] 6.3 `cmd_branch` (direct-to-master shortcut): route its merge+tag through `git -C <hub>/master`, creating no new worktree; verify it still works when invoked with `develop` or an arbitrary branch as the source.
- [x] 6.4 `cmd_delete`: apply the worktree-first deletion order; verify.
- [x] 6.5 `cmd_track`/`cmd_publish`/`cmd_rebase`: apply the same changes as feature/hotfix; verify.
- [x] 6.6 Verify classic-mode behavior is unchanged.

## 7. `git-flow-support` lifecycle

- [x] 7.1 `cmd_start`: replace `checkout -b` with `gitflow_worktree_add()`, creating `<hub>/support/<version>`; verify.
- [x] 7.2 `cmd_rebase`: operate via `git -C <hub>/support/<version>` instead of checkout; verify.
- [x] 7.3 Confirm (by inspection and a manual test) that no automatic worktree removal exists for support, matching today's lack of `finish`/`delete`.
- [x] 7.4 Verify classic-mode behavior is unchanged.

## 8. Hooks

- [x] 8.1 Update `pre-flow-*-start`, `post-flow-*-start`, `pre-flow-*-track`, `post-flow-*-track`, `pre-flow-*-finish`, `post-flow-*-finish`, `pre-flow-*-delete`, `post-flow-*-delete` templates in `hooks/` to document the new trailing worktree-path argument in their header comments, without changing their executable logic.
- [x] 8.2 Write or extend a sample hook that reads the new trailing argument, and verify it receives the correct worktree path when worktree mode is enabled and an empty string when it is disabled.
- [x] 8.3 Verify `filter-flow-*` hooks are untouched and still receive their existing arguments unchanged.

## 9. Cross-cutting verification

- [x] 9.1 End-to-end manual run: initialize a fresh repo with worktree mode enabled, run `feature`, `bugfix`, `hotfix`, `release`, and `support` through their full lifecycles (start → work → finish/delete where applicable), confirming the `.bare` + sibling-worktree layout stays consistent throughout and prefix container directories survive branch removal.
- [x] 9.2 End-to-end manual run: repeat the same lifecycles with worktree mode left disabled on a fresh repo, confirming behavior is identical to the pre-change scripts.
- [x] 9.3 Verify `git flow init -f` can toggle `gitflow.worktree` after the repo already has history, and that a plain `init` (no `-f`) cannot.
- [x] 9.4 Verify a merge conflict during `finish` (feature and release/hotfix) surfaces in the base branch's worktree, leaves the source worktree/branch intact, and resumes correctly on a second `finish` invocation run from a different worktree than the first attempt.

## 10. Documentation

- [x] 10.1 Update `README.md` with a section describing worktree mode, how to enable it, and the resulting directory layout.
- [x] 10.2 Add a `CHANGELOG.md` entry describing the new opt-in worktree mode and the new trailing hook argument.

## 11. Follow-up: guard `finish` against a base branch without a worktree

- [x] 11.1 Add a shared `gitflow_worktree_require_base()` (or equivalent) helper in `gitflow-common` that dies with an actionable message when the base branch's worktree directory does not exist, suggesting `git worktree add`; verify it exits non-zero and prints the message for a base with no worktree, and is a no-op for an existing one.
- [x] 11.2 Call the guard in `git-flow-feature` `cmd_finish` immediately after `BASE_WORKTREE` is resolved and before any merge; verify a feature based on a custom branch without a worktree aborts with the explicit error, writes no `MERGE_BASE` marker, and leaves the feature worktree/branch intact.
- [x] 11.3 Apply the same guard to `git-flow-bugfix` `cmd_finish`; verify with the same scenario.
- [x] 11.4 Apply the same guard to `git-flow-hotfix` `cmd_finish` (covering both the base merge and the develop back-merge paths); verify the error replaces the misleading "There were merge conflicts." message.
- [x] 11.5 Re-run the standard-scenario regression (feature/bugfix/hotfix finish against `develop`/`master`) to confirm the guard changes nothing when the base worktree exists.
