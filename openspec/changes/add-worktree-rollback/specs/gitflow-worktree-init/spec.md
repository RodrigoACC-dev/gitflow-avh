## MODIFIED Requirements

### Requirement: Changing worktree mode requires forced reinitialization
Once a repository has been initialized, Git Flow SHALL NOT change the `gitflow.worktree` setting on a subsequent `git flow init` unless the existing force flag (`-f`) is supplied, reusing the same guard that already protects reinitialization of branch names and prefixes.

#### Scenario: Re-running init without force
- **WHEN** `git flow init` is run again on an already-initialized repository without `-f`
- **THEN** the existing `gitflow.worktree` value is left unchanged and the user is warned that `-f` is required to change it

#### Scenario: Re-running init with force
- **WHEN** `git flow init -f` is run on an already-initialized repository
- **THEN** `gitflow.worktree` may be changed, triggering the corresponding layout migration or rollback

#### Scenario: Explicitly enabling an already-enabled repository
- **WHEN** `git flow init -f -w` (or `--worktree`) is run on a repository where worktree mode is already enabled
- **THEN** the mode stays enabled (it is never flipped off by the flag), and a pending migration is completed if the layout was not in place yet

#### Scenario: Reinit that does not mention worktree mode
- **WHEN** `git flow init -f` is run without `-w`, `--worktree` or `--noworktree`
- **THEN** the configured `gitflow.worktree` value is preserved, and the layout is completed if the mode is enabled but the migration had not finished

#### Scenario: Disabling an enabled repository
- **WHEN** `git flow init -f --noworktree` is run on a repository where worktree mode is enabled and the worktree layout is present
- **THEN** the repository is collapsed back into a single working tree as described by the rollback requirements, and `gitflow.worktree` is cleared

## ADDED Requirements

### Requirement: Disabling worktree mode collapses the repository back to a single working tree
When worktree mode is disabled on a repository that has the worktree layout (`.bare` present), Git Flow SHALL convert the repository back to Git Flow's default single-working-tree layout instead of leaving it in a mixed state. The conversion SHALL move the Git database back from `.bare` to a regular `.git` directory with `core.bare` disabled, remove the linked worktrees, and restore a checkout of the `develop` branch at the repository root with its working content preserved. Branch references SHALL remain intact. Directory settings that were rewritten by the forward migration SHALL be restored, and container directories left empty SHALL be removed. The `gitflow.worktree` setting SHALL be cleared only after the conversion succeeds.

#### Scenario: Collapsing a clean worktree repository
- **WHEN** `git flow init -f --noworktree` is run on a clean worktree-layout repository
- **THEN** `.bare` no longer exists, `.git` is a regular directory with `core.bare` disabled, the repository root holds a clean checkout of `develop`, the former `master/` and `develop/` directories no longer exist locally, and `gitflow.worktree` is unset

#### Scenario: Branches survive the collapse
- **WHEN** the repository is collapsed
- **THEN** every local branch that existed before the rollback still exists, including those whose worktrees were removed

#### Scenario: Hooks path is restored
- **WHEN** `gitflow.path.hooks` pointed at the `.bare/hooks` directory produced by the forward migration
- **THEN** after the collapse it points at `.git/hooks`

#### Scenario: Original remote fetch refspec restored
- **WHEN** the forward migration recorded the repository's pre-existing `remote.origin.fetch` value
- **THEN** the collapse restores that value, and clears the saved record

#### Scenario: Empty container directories are removed
- **WHEN** the collapse leaves a branch-type container directory (`feature/`, `bugfix/`, `hotfix/`, `release/`, `support/`) empty
- **THEN** that directory is removed

#### Scenario: Disabling without a worktree layout
- **WHEN** `git flow init -f --noworktree` is run on a repository whose `gitflow.worktree` setting is enabled but which has no `.bare` directory
- **THEN** only the setting is cleared and no layout change is attempted

### Requirement: Rollback never discards work in progress
Before changing anything, the collapse SHALL verify that every worktree other than the `develop` worktree is clean (no staged, unstaged, or untracked changes) and unlocked. If any of them is not, or if the `develop` worktree is missing, the collapse SHALL abort without modifying the repository and SHALL report which paths block the rollback.

The `develop` worktree is the one whose content survives: its unstaged and untracked files SHALL be preserved as the checkout at the repository root. Files excluded by `.gitignore` inside discarded worktrees SHALL be deleted, and the final summary SHALL state that they were discarded.

#### Scenario: Dirty extra worktree aborts the rollback
- **WHEN** a feature, bugfix, hotfix, release, support, or `master` worktree has staged, unstaged, or untracked changes
- **THEN** the rollback aborts, no worktree is removed and `.bare` is not renamed, and the blocking paths are reported

#### Scenario: Clean extra worktree is discarded but its branch kept
- **WHEN** a feature worktree is clean
- **THEN** the rollback removes that worktree, keeps the feature branch, and continues

#### Scenario: Locked worktree aborts the rollback
- **WHEN** any worktree is locked
- **THEN** the rollback aborts before modifying anything and reports the locked worktree

#### Scenario: Uncommitted develop changes survive
- **WHEN** the `develop` worktree has unstaged modifications and untracked files
- **THEN** after the collapse those files are present at the repository root and reported as modifications/untracked, with no content lost

#### Scenario: Ignored files in discarded worktrees are reported
- **WHEN** a discarded worktree contained files excluded by `.gitignore`
- **THEN** those files are deleted with the worktree and the summary states that ignored files were discarded

#### Scenario: Missing develop worktree aborts
- **WHEN** the repository has no `develop` worktree to preserve
- **THEN** the rollback aborts with an explanatory message instead of guessing a branch
