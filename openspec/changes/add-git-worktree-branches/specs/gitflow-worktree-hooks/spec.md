## Purpose

Ensures Git Flow's pre/post hook mechanism and its merge-resume state resolve correctly when a repository has multiple worktrees sharing one Git database, and exposes the relevant worktree path to hook scripts that need it.

## ADDED Requirements

### Requirement: Hook loading and the merge-resume marker resolve from the shared common directory
Git Flow SHALL resolve the hooks directory and git-flow's own `.gitflow/MERGE_BASE` merge-resume marker from the repository's shared common Git directory, not from the private Git directory of whichever worktree invoked the command. Git's own `SQUASH_MSG` file SHALL remain resolved from the private Git directory of the worktree that performs the squash merge, matching where git itself reads and writes it.

#### Scenario: Squash merge in a base branch's worktree
- **WHEN** a squash merge is performed in a base branch's worktree, with a customized squash message requested
- **THEN** `SQUASH_MSG` is written to and read from that worktree's own private Git directory, and the customized message is used for the commit

#### Scenario: Resuming a finish from a different worktree
- **WHEN** `finish` writes a merge-conflict marker while invoked from a branch's own worktree, and the user later resolves the conflict and reruns `finish` from a different worktree of the same repository (e.g. the base branch's worktree)
- **THEN** the rerun finds the same marker and resumes correctly

#### Scenario: Custom hooks path configured
- **WHEN** `gitflow.path.hooks` is explicitly configured
- **THEN** hooks are found at that configured path regardless of which worktree invoked the command

#### Scenario: Default hooks path with no explicit configuration
- **WHEN** no `gitflow.path.hooks` is configured
- **THEN** the hooks directory resolves to the same location (relative to the shared common directory) regardless of which worktree invoked the command

### Requirement: Worktree-creating and worktree-removing hooks receive the worktree path
The pre/post hooks for `start`, `track`, `finish`, and `delete` SHALL receive the resolved worktree path as an additional trailing positional argument, after all arguments they already receive today.

#### Scenario: Worktree mode enabled
- **WHEN** worktree mode is enabled and a lifecycle hook for `start`, `track`, `finish`, or `delete` fires
- **THEN** the hook receives the created or removed worktree's path as its last argument

#### Scenario: Worktree mode disabled
- **WHEN** worktree mode is disabled and the same hooks fire
- **THEN** the hook receives an empty string as its last argument

### Requirement: Existing hook arguments and scripts remain backward compatible
This change SHALL NOT change the meaning, order, or content of any positional argument that hooks already receive today.

#### Scenario: Existing hook script unaware of the new argument
- **WHEN** an existing hook script only reads its first four positional arguments
- **THEN** it continues to behave identically after this change, regardless of worktree mode

### Requirement: Filter hooks are unaffected
`filter-flow-*` hooks SHALL continue to receive exactly the same arguments as before this change, with no worktree-related additions.

#### Scenario: Tag message filter hook
- **WHEN** a `filter-flow-*-tag-message` hook runs during a release or hotfix operation
- **THEN** its arguments are unchanged by worktree mode
