## Why

Git Flow (AVH) manages every branch (feature/bugfix/hotfix/release/support) by repeatedly checking the same single working tree in and out, which forces sequential context switches (e.g. `release finish` hops through master and develop in one working directory) and makes it impossible to have two Git Flow branches open side by side. `git worktree` lets each branch live in its own directory while sharing one `.git` database, removing the need for in-place checkouts and letting master/develop/feature/bugfix/hotfix/release/support branches coexist on disk simultaneously. This change adapts the Git Flow command set to create, use, and tear down branches through worktrees instead of in-place checkouts, while keeping the rest of the Git Flow process (naming, hooks, config, merge semantics, tagging) unchanged.

## What Changes

- Add an opt-in `gitflow.worktree` setting, set during `git flow init` and only re-settable via `git flow init -f`. When disabled, every command behaves exactly as today (no regression for existing users).
- When enabled, `git flow init` restructures the repo into a `.bare` + sibling-worktrees layout: `master/` and `develop/` become permanent worktrees, and `feature/`, `bugfix/`, `hotfix/`, `release/`, `support/` become persistent container directories. **BREAKING** (opt-in only): migrates the physical layout of the repository the first time it runs.
- `start`/`track` on feature/bugfix/hotfix/release/support create a new worktree (`git worktree add`) under `<hub>/<prefix>/<name>` instead of checking out a branch in place.
- `finish` on feature/bugfix/hotfix performs its merge against the base branch's permanent worktree (`git -C <hub>/develop ...`), then removes the finished branch's worktree (`git worktree remove --force`) before deleting the branch ref — the reverse order of today's "checkout away, then delete," which is required because Git refuses to delete a branch still attached to a worktree.
- `finish` on release/hotfix and the `release branch` shortcut apply the same pattern against both `<hub>/master` and `<hub>/develop` in sequence, preserving the existing two-branch merge/tag behavior.
- `delete` drops its "checkout base branch to free up the current branch" step; freeing the branch is now a side effect of removing its worktree first.
- `rebase`/`pull` (existing local branch) operate via `git -C <hub>/<branch>` instead of checking the branch out first. `pull` (new remote branch) and `track` create a worktree instead of a plain branch + checkout.
- `publish` drops its trailing checkout (the branch already lives in its own worktree).
- `rename` (feature/bugfix/hotfix) additionally moves the branch's worktree (`git worktree move`) to match the renamed branch.
- `checkout`/`co` can no longer switch the invoking shell's directory (a child process cannot do that); it instead resolves and prints the branch's worktree path for the user to `cd` into.
- `support` gains the same `start`/`track` worktree treatment; since it has no `finish`/`delete` today, its worktree is permanent like master/develop's.
- Merge conflicts during `finish` surface in the base branch's worktree (e.g. `<hub>/develop`) exactly as they do today in the single working tree; the source branch's worktree stays untouched until `finish` completes.
- Hook loading and git-flow's own merge-resume marker (`.gitflow/MERGE_BASE`) switch from `git rev-parse --git-dir` to `git rev-parse --git-common-dir` so they resolve to the same shared location regardless of which worktree invoked the command (today's `--git-dir` use is a latent bug once multiple worktrees exist). Git's own `SQUASH_MSG` deliberately stays per-worktree, resolved from the git directory of the worktree performing the squash merge, since that is where git itself reads it.
- Hooks that fire around worktree creation/removal (`pre`/`post` for `start`, `track`, `finish`, `delete`) gain one new trailing positional argument carrying the resolved worktree path (empty string when worktree mode is off), without changing the meaning of existing arguments.

## Capabilities

### New Capabilities
- `gitflow-worktree-init`: opt-in activation during `git flow init`, the `.bare` + sibling-worktree repository layout, and the `-f`-gated re-configuration rule.
- `gitflow-worktree-lifecycle`: worktree-based create/use/finish/delete/rename/checkout behavior for feature, bugfix, hotfix, release, and support branches, including merge/conflict handling and the worktree-then-branch deletion order.
- `gitflow-worktree-hooks`: common-dir-based hook and merge-marker path resolution, and the new worktree-path argument passed to lifecycle hooks.

### Modified Capabilities
(none — no pre-existing specs for this project; all behavior above is captured as new capabilities)

## Impact

- Affected scripts: `gitflow-common` (`gitflow_load_settings`, `gitflow_rename_branch`, new worktree helpers), `git-flow-init` (layout migration, new config flag, hooks-path default), `git-flow-feature`, `git-flow-bugfix`, `git-flow-hotfix`, `git-flow-release`, `git-flow-support` (start/finish/delete/track/rebase/pull/publish/checkout/rename/branch commands).
- Affected hook contracts: all `pre-flow-*-start`, `post-flow-*-start`, `pre-flow-*-track`, `post-flow-*-track`, `pre-flow-*-finish`, `post-flow-*-finish`, `pre-flow-*-delete`, `post-flow-*-delete` scripts in `hooks/` gain a new trailing argument; `filter-flow-*` hooks are unaffected.
- No changes to `git-flow-config`, `git-flow-log`, `git-flow-version`, or the `contrib/` installers.
- No change for repositories that do not opt in via `git flow init`.
