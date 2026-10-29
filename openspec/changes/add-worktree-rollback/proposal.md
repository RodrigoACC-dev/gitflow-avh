## Why

Worktree mode is one-way today: `git flow init --noworktree` flips the setting off but leaves `.bare` and the sibling worktrees on disk, telling the user that collapsing them "is a manual step". Anyone who tries worktree mode and wants to return to Git Flow's default single-working-tree flow is left with an unusable mixed state (a bare hub that no longer behaves like a checkout). This change adds the missing rollback: disabling worktree mode converts the repository back into a classic checkout automatically.

## What Changes

- `git flow init -f --noworktree` on a repository in worktree layout SHALL collapse it: remove the linked worktrees, move `.bare` back to `.git` with `core.bare=false`, restore the checkout of `develop` at the repository root, and clear `gitflow.worktree`.
- Only clean worktrees may be discarded: `master` and any feature/bugfix/hotfix/release/support worktrees must have no staged, unstaged, or untracked changes, otherwise the rollback aborts before touching anything and lists the offending paths. Their branches are kept.
- The `develop` worktree is the one that survives: its content (including unstaged and untracked files) is preserved as the new root checkout; staged changes become unstaged after the index resync, losing nothing.
- Ignored files inside discarded worktrees are deleted with a notice in the final summary.
- `gitflow.path.hooks` pointing into `.bare/hooks` is repointed to `.git/hooks`, and container directories left empty (`feature/`, `bugfix/`, …) are removed.
- To make the round trip lossless, the forward migration additionally records the pre-existing `remote.origin.fetch` value, and the rollback restores it when present.
- A repository without `.bare` is unaffected: `--noworktree` keeps its current meaning (disable the setting only).

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `gitflow-worktree-init`: adds the reverse migration (collapse back to a single working tree), changes the behavior of disabling worktree mode from "leave the layout as-is" to "convert the repository", and records the original remote fetch refspec during the forward migration.

## Impact

- `git-flow-init`: new `gitflow_init_collapse_worktrees()` (or equivalent) invoked from the existing `--noworktree` branch of `cmd_default`; the forward migration stores `gitflow.worktree.savedfetch`.
- `gitflow-common`: reuses the existing `gitflow_worktree_hub_dir`, `gitflow_worktree_enabled` and the staging-restore helper introduced for the forward migration.
- `tests/smoke-worktree.sh`: new rollback scenarios (clean collapse, dirty-worktree abort, develop dirt preserved, ignored-file notice, no-op without `.bare`, round trip re-enable).
- `README.md`: documents the rollback and the new meaning of `--noworktree`.
- No change for repositories that never enabled worktree mode.
