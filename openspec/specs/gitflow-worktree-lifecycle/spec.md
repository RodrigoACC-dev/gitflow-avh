# gitflow-worktree-lifecycle Specification

## Purpose

Defines how feature, bugfix, hotfix, release, and support branches are created, used, and torn down through per-branch Git worktrees once worktree mode is active, while preserving Git Flow's existing merge, tagging, conflict-handling, and hook semantics.

## Requirements

### Requirement: Branch creation uses a dedicated worktree
When worktree mode is enabled, `start` and `track` SHALL create a new worktree for the branch instead of checking it out in a shared working tree. The worktree's path SHALL mirror the branch's full name (prefix and name) as nested directories under the repository's worktree root.

#### Scenario: Starting a feature
- **WHEN** a user runs `git flow feature start login`
- **THEN** a new worktree is created at `<hub>/feature/login`, the `feature/login` branch is checked out only there, and no other worktree's checkout changes

#### Scenario: Tracking a remote branch
- **WHEN** a user runs `git flow feature track login` for a branch that exists on the remote but not locally
- **THEN** a new worktree is created at `<hub>/feature/login` tracking `$ORIGIN/feature/login`

### Requirement: Finish merges against the base branch's own worktree
`finish` on feature, bugfix, hotfix, and release branches SHALL perform its merge(s) directly against the base branch's existing worktree, without checking out the branch being finished.

#### Scenario: Finishing a feature
- **WHEN** a user runs `git flow feature finish login` and the feature's base is `develop`
- **THEN** the merge is executed against the `develop` worktree, and the `feature/login` worktree is not checked out or altered by the merge step itself

#### Scenario: Finishing a release or hotfix
- **WHEN** a user runs `git flow release finish` or `git flow hotfix finish`
- **THEN** the merge and tag operations execute against the `master` worktree, followed by the merge into the `develop` worktree, in the same sequence and with the same outcome as today's single-tree finish

### Requirement: A branch's worktree is removed before its ref is deleted
On a successful finish or an explicit delete, Git Flow SHALL remove the branch's worktree before deleting the branch reference, and SHALL NOT attempt to delete a branch reference that is still attached to an existing worktree.

#### Scenario: Finish completes with no conflicts
- **WHEN** `finish` merges cleanly
- **THEN** the finished branch's worktree is removed first, and only then is the branch reference deleted

#### Scenario: Explicit delete of a merged branch
- **WHEN** a user runs `git flow feature delete login` on a branch already merged into its base
- **THEN** the branch's worktree is removed before the branch reference is deleted, with no prior checkout of the base branch

### Requirement: Worktree removal is forced and fails safely
Worktree removal during finish or delete SHALL use a forced mode that succeeds even when the worktree contains modified, untracked, or otherwise in-use files. If forced removal still fails (for example due to an operating-system-level file lock), Git Flow SHALL abort before deleting the branch reference and SHALL report the failure so the user can retry after releasing the lock.

#### Scenario: Worktree has uncommitted or untracked files
- **WHEN** a feature's worktree contains uncommitted changes or untracked files at finish time
- **THEN** the worktree is still removed and the branch reference is still deleted

#### Scenario: Worktree removal fails due to a locked file
- **WHEN** the operating system prevents removing the worktree directory (e.g., an open file handle)
- **THEN** `finish`/`delete` aborts with an explicit error, the branch reference is not deleted, and the worktree directory is left in place for retry

### Requirement: Merge conflicts preserve the source branch's worktree
If a `finish` merge produces conflicts, Git Flow SHALL leave the conflict for manual resolution in the base branch's worktree and SHALL NOT remove, alter, or detach the source branch's worktree until `finish` subsequently completes successfully.

#### Scenario: Conflicting feature merge
- **WHEN** merging `feature/login` into `develop` produces conflicts
- **THEN** conflict markers appear in the `develop` worktree, the `feature/login` worktree and branch remain intact and untouched, and re-running `finish` (from any worktree) resumes and completes the operation once conflicts are resolved

### Requirement: Rebase and pull operate on the branch's own worktree without checkout
`rebase`, and `pull` against an already-existing local branch, SHALL operate directly on that branch's own worktree rather than checking the branch out in the invoking working tree first.

#### Scenario: Rebasing a feature from another worktree
- **WHEN** a user runs `git flow feature rebase login` while their shell is inside a different worktree (e.g. `develop`)
- **THEN** the rebase is applied to the `feature/login` worktree directly, and the invoking worktree's own checkout is unaffected

### Requirement: Pull creates a worktree for a new local branch
When `pull` creates a local branch that does not yet exist, it SHALL do so by creating a new worktree for that branch rather than creating a plain branch and checking it out in the invoking working tree.

#### Scenario: Pulling a branch for the first time
- **WHEN** a user runs `git flow feature pull origin login` and no local `feature/login` branch exists yet
- **THEN** a new worktree for `feature/login` is created from the fetched remote branch

### Requirement: Publish does not relocate the branch
`publish` SHALL NOT perform a final checkout of the published branch, since the branch already resides in its own worktree once worktree mode is enabled.

#### Scenario: Publishing a feature
- **WHEN** a user runs `git flow feature publish login`
- **THEN** the branch is pushed and configured to track the remote, and no checkout of `feature/login` occurs as part of the command

### Requirement: Rename relocates the branch's worktree
`rename` (feature, bugfix, hotfix) SHALL relocate the branch's worktree directory to match the renamed branch, in addition to renaming the branch reference, keeping the worktree's registered location consistent.

#### Scenario: Renaming a feature branch
- **WHEN** a user runs `git flow feature rename new-name` for `feature/old-name`
- **THEN** the branch reference is renamed to `feature/new-name` and its worktree moves from `<hub>/feature/old-name` to `<hub>/feature/new-name` with no loss of worktree metadata

### Requirement: Checkout surfaces the worktree path instead of switching branches
Because a Git Flow command cannot change the working directory of the shell that invoked it, `checkout`/`co` SHALL NOT attempt to switch any working tree's checked-out branch. Instead, it SHALL resolve the target branch's worktree and present its path to the user.

#### Scenario: Checking out an existing feature branch
- **WHEN** a user runs `git flow feature checkout login`
- **THEN** the command reports the worktree path for `feature/login` and does not change the checked-out branch of any existing worktree

### Requirement: Support branches use worktrees without automatic teardown
`support` `start`, `track`, and `rebase` SHALL apply the same worktree-creation and worktree-targeted-operation behavior as feature/bugfix/hotfix. Because Git Flow provides no `finish` or `delete` for support branches, their worktrees SHALL remain in place indefinitely once created, in the same way as `master` and `develop`.

#### Scenario: Starting a support branch
- **WHEN** a user runs `git flow support start 1.x master`
- **THEN** a new worktree is created at `<hub>/support/1.x`, and Git Flow provides no command that automatically removes it

### Requirement: Finish fails clearly when the base branch has no worktree
`finish` accepts branches whose base is not necessarily `master` or `develop`, but only those two branches are guaranteed a worktree by initialization. Before attempting any merge, `finish` on feature, bugfix, hotfix, and release branches SHALL verify that the base branch has an existing worktree and SHALL abort with an explicit, actionable error message when it does not, rather than attempting the merge and misreporting the failure as a merge conflict.

#### Scenario: Feature based on a branch without a worktree
- **WHEN** a user runs `git flow feature finish <name>` for a feature based on a local branch other than `master`/`develop` that has no worktree of its own
- **THEN** the command aborts before merging, explains that no worktree exists for that base branch, and leaves the feature's branch and worktree intact with no merge-conflict marker written

#### Scenario: Bugfix or hotfix based on a branch without a worktree
- **WHEN** a user runs `git flow bugfix finish` or `git flow hotfix finish` for a branch whose base has no worktree
- **THEN** the command aborts with the same explicit base-worktree error instead of reporting a merge conflict

#### Scenario: Base branch with a worktree still finishes normally
- **WHEN** the base branch has its own worktree (including a non-`master`/`develop` base for which the user created one manually)
- **THEN** `finish` merges into that worktree exactly as before, with no behavior change

### Requirement: The release-to-master shortcut uses master's existing worktree
The `release branch` command, which merges an arbitrary branch directly into `master` without creating a release branch, SHALL perform its merge and tag operations against the existing `master` worktree and SHALL NOT create any new worktree.

#### Scenario: Releasing develop directly to master
- **WHEN** a user runs `git flow release branch 1.2.0`
- **THEN** the merge and tag are applied to the `master` worktree, and no new worktree is created or removed

### Requirement: Branch-type container directories outlive their branches
Removing a branch's worktree (via `finish` or `delete`) SHALL NOT remove the persistent container directory for its branch-type prefix (`feature/`, `bugfix/`, `hotfix/`, `release/`, `support/`).

#### Scenario: Finishing the last feature in a container
- **WHEN** the only remaining `feature/*` worktree is finished and removed
- **THEN** the `feature/` container directory still exists, ready for future feature branches

### Requirement: No behavior change when worktree mode is disabled
Every requirement in this capability SHALL apply only when `gitflow.worktree` is enabled. When it is disabled, all affected commands SHALL behave exactly as they do today, using in-place checkouts in a single working tree.

#### Scenario: Running commands with worktree mode off
- **WHEN** `gitflow.worktree` is unset or false
- **THEN** `start`, `finish`, `delete`, `track`, `rebase`, `pull`, `publish`, `checkout`, and `rename` behave identically to the current single-working-tree implementation
