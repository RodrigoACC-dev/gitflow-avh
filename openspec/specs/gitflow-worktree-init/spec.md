# gitflow-worktree-init Specification

## Purpose

Defines how a Git Flow repository opts into worktree-based branch management during `git flow init`, and the on-disk repository layout that results once it is enabled.

## Requirements

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

#### Scenario: Explicitly enabling an already-enabled repository
- **WHEN** `git flow init -f -w` (or `--worktree`) is run on a repository where worktree mode is already enabled
- **THEN** the mode stays enabled (it is never flipped off by the flag), and a pending migration is completed if the layout was not in place yet

#### Scenario: Reinit that does not mention worktree mode
- **WHEN** `git flow init -f` is run without `-w`, `--worktree` or `--noworktree`
- **THEN** the configured `gitflow.worktree` value is preserved, and the layout is completed if the mode is enabled but the migration had not finished

#### Scenario: Disabling an enabled repository
- **WHEN** `git flow init -f --noworktree` is run on a repository where worktree mode is enabled
- **THEN** `gitflow.worktree` is set to false, the user is warned, and any existing `.bare` directory and worktrees are left on disk

### Requirement: Enabling worktree mode restructures the repository into a shared bare directory with sibling worktrees
When worktree mode is enabled for the first time, Git Flow SHALL convert the repository so that its Git database lives in a shared common directory (`.bare`), with `master` and `develop` each checked out in their own permanent, sibling worktree directories. Any content already checked out at the repository root SHALL be preserved by moving it into the worktree directory for the branch that was checked out there, except for top-level directories that are excluded by `.gitignore` and top-level directories that are themselves Git repositories, which SHALL be left untouched in the hub root. Those preserved paths SHALL be reported to the user at the end of the migration. The remote fetch configuration SHALL be adjusted so that remote-tracking refs populate correctly for all worktrees.

#### Scenario: Enabling worktree mode on a repository with develop checked out at the root
- **WHEN** worktree mode is enabled on a repository whose root directory currently holds the checked-out `develop` branch
- **THEN** the repository's Git database is moved into `.bare`, the previously checked-out files are relocated into a `develop/` worktree directory, and `master` is created as its own worktree directory

#### Scenario: Master has no prior working copy
- **WHEN** worktree mode is enabled and `master` was only a local branch reference with no prior checkout
- **THEN** a new worktree directory for `master` is created from that branch

#### Scenario: Ignored directories and nested repositories stay at the hub
- **WHEN** worktree mode is enabled on a repository whose root contains a top-level directory excluded by `.gitignore` and a top-level directory holding its own Git repository
- **THEN** neither directory is moved into a worktree, both remain in the hub root untouched, and the migration completes and reports them to the user

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
