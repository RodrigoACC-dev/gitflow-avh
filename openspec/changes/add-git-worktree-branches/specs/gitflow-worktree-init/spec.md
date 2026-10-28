## Purpose

Defines how a Git Flow repository opts into worktree-based branch management during `git flow init`, and the on-disk repository layout that results once it is enabled.

## ADDED Requirements

### Requirement: Worktree mode is an opt-in setting
Git Flow SHALL support a boolean setting (`gitflow.worktree`) that controls whether branch lifecycle commands use per-branch worktrees. The setting SHALL be configurable only through `git flow init`, SHALL default to disabled, and SHALL leave all Git Flow commands behaving exactly as they do today when disabled.

#### Scenario: Init without requesting worktree mode
- **WHEN** a user runs `git flow init` without enabling worktree mode
- **THEN** `gitflow.worktree` remains unset/false and every Git Flow command continues to operate on a single working tree as before

#### Scenario: Init with worktree mode requested
- **WHEN** a user runs `git flow init` and enables worktree mode
- **THEN** `gitflow.worktree` is set to true in the repository's local config

### Requirement: Changing worktree mode requires forced reinitialization
Once a repository has been initialized, Git Flow SHALL NOT change the `gitflow.worktree` setting on a subsequent `git flow init` unless the existing force flag (`-f`) is supplied, reusing the same guard that already protects reinitialization of branch names and prefixes.

#### Scenario: Re-running init without force
- **WHEN** `git flow init` is run again on an already-initialized repository without `-f`
- **THEN** the existing `gitflow.worktree` value is left unchanged and the user is warned that `-f` is required to change it

#### Scenario: Re-running init with force
- **WHEN** `git flow init -f` is run on an already-initialized repository
- **THEN** `gitflow.worktree` may be changed, triggering the corresponding layout migration or rollback

### Requirement: Enabling worktree mode restructures the repository into a shared bare directory with sibling worktrees
When worktree mode is enabled for the first time, Git Flow SHALL convert the repository so that its Git database lives in a shared common directory (`.bare`), with `master` and `develop` each checked out in their own permanent, sibling worktree directories. Any content already checked out at the repository root SHALL be preserved by moving it into the worktree directory for the branch that was checked out there. The remote fetch configuration SHALL be adjusted so that remote-tracking refs populate correctly for all worktrees.

#### Scenario: Enabling worktree mode on a repository with develop checked out at the root
- **WHEN** worktree mode is enabled on a repository whose root directory currently holds the checked-out `develop` branch
- **THEN** the repository's Git database is moved into `.bare`, the previously checked-out files are relocated into a `develop/` worktree directory, and `master` is created as its own worktree directory

#### Scenario: Master has no prior working copy
- **WHEN** worktree mode is enabled and `master` was only a local branch reference with no prior checkout
- **THEN** a new worktree directory for `master` is created from that branch

### Requirement: Branch-type prefixes get persistent container directories
When worktree mode is enabled, Git Flow SHALL create one top-level directory per configured branch-type prefix (feature, bugfix, hotfix, release, support). These directories SHALL persist independently of any individual branch's lifecycle and SHALL NOT be removed when the last branch worktree inside them is removed.

#### Scenario: Container directories created at init
- **WHEN** worktree mode is enabled
- **THEN** `feature/`, `bugfix/`, `hotfix/`, `release/`, and `support/` directories exist as empty containers alongside `master/` and `develop/`

### Requirement: Classic mode is unaffected
When worktree mode is not enabled, `git flow init` SHALL NOT create a `.bare` directory, SHALL NOT create any branch-prefix container directories, and SHALL NOT alter the existing single-working-tree repository layout.

#### Scenario: Classic init
- **WHEN** a repository is initialized or reinitialized without worktree mode
- **THEN** no `.bare` directory or prefix container directories are created, and the repository layout matches today's behavior
