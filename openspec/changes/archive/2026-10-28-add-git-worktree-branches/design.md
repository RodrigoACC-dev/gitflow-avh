## Context

See `proposal.md` - Why. Today every Git Flow script (`git-flow-feature`, `git-flow-bugfix`, `git-flow-hotfix`, `git-flow-release`, `git-flow-support`) shares `gitflow-common` and operates on a single working tree: `start`/`track` do `git checkout -b`, `finish`/`delete`/`rebase`/`pull`/`publish`/`checkout` all switch the same tree in and out via `git checkout`, and `release`/`hotfix finish` sequentially checks out `master` then `develop` in that one tree to perform two merges plus a tag. `git-flow-init` creates `develop` as a real checkout at the repo root and `master` as a local-only branch ref (never checked out anywhere) until something needs it.

`gitflow_load_settings` (in `gitflow-common`) derives `DOT_GIT_DIR` from `git rev-parse --git-dir`, which is used both for the hooks directory fallback and for git-flow's own `.gitflow/MERGE_BASE` marker used to resume a `finish` after a conflict. (`SQUASH_MSG` is not part of this: git itself reads and writes it in the private git directory of whichever worktree performs the squash merge, so it must stay per-worktree.)

## Goals / Non-Goals

**Goals:**
- Make every branch-type's full lifecycle (create, use, rebase/pull, finish, delete, rename) work through `git worktree` instead of in-place checkouts, without changing the merge/tag/hook semantics Git Flow already has.
- Keep the change fully opt-in and zero-regression for repositories that don't enable it.
- Keep the worktree layout legible and aligned with Git Flow's own prefix structure (`feature/`, `bugfix/`, etc.), as requested.

**Non-Goals:**
- Making `git flow feature checkout` change the invoking shell's directory — not possible for a child process; see Decisions.
- Automatically tearing down `support` branch worktrees — Git Flow itself has no `finish`/`delete` for support today, and this change does not add one.
- Changing anything about `git-flow-config`, `git-flow-log`, `git-flow-version`, or the `contrib/` installers.
- Supporting `core.worktreeConfig` (per-worktree config) — this design relies on the default behavior where `git config --local` is shared across all worktrees of a repository.

## Decisions

### 1. Repository layout: `.bare` + sibling worktrees, mirroring Git Flow's own prefixes
`master/` and `develop/` become permanent worktrees; `feature/`, `bugfix/`, `hotfix/`, `release/`, `support/` become persistent container directories holding one ephemeral (or, for `support`, permanent) worktree per branch, named after the branch's full name including prefix (e.g. `feature/login` → `<hub>/feature/login`).

Alternatives considered:
- *Flat sibling directories named only by the short branch name* (`../login`) — rejected: collides when two prefixes share a short name (`feature/x` and `hotfix/x`), and doesn't mirror Git Flow's own mental model of prefixes.
- *A single configurable base path with no fixed sub-structure* — rejected: the user explicitly wants the folder structure to mirror Git Flow's prefix configuration itself, not an independent setting.
- *Leaving the repo root as one of the branches' worktrees, with new folders added as its siblings on the filesystem (not nested under it)* — rejected in favor of `.bare`: nesting `master/`, `develop/`, `feature/`, etc. as actual children of the root only works cleanly if the root itself holds no branch checkout of its own (otherwise one branch's worktree directory would contain all the others' as "untracked" content). The `.bare` + sibling-worktrees pattern is the standard, well-understood way to get a hub directory that isn't itself any branch's working copy.

### 2. Worktree removal before branch deletion, with `--force`
Git refuses `git branch -d`/`-D` on a branch still attached to any worktree ("used by worktree at ..."). So the only valid order is: merge → `git worktree remove --force <path>` → `git branch -d/-D`. `--force` is required because the worktree may hold uncommitted/untracked files, and on Windows/MSYS (a declared target of this project) a directory can be harder to remove than on Linux if something still has a handle open in it.

Alternative considered: checking out the base branch in the feature's own worktree before removing it (mirroring the classic single-tree "evacuate, then delete" pattern) — rejected: unnecessary under worktrees (nothing needs evacuating; removing the worktree itself is what frees the branch), and checking out the base branch inside what is about to become a deleted directory adds a step with no benefit.

### 3. Operate on other worktrees via `git -C <path>`, never via checkout
Anywhere the current code does "`checkout` branch X, then run some git command," the worktree-mode equivalent is `git -C <worktree-of-X> <command>` — no checkout involved, because X's worktree already has it checked out, and `checkout` of a branch already checked out elsewhere fails. This single pattern covers: `finish`'s merge(s), `release branch`'s merge+tag, `rebase`, `pull` (existing branch case). It also means these commands no longer require the user to be standing in any particular directory when they invoke them.

Because this pattern requires the target branch to actually have a worktree, and only `master`/`develop` are guaranteed one by `init`, `finish` verifies that the base branch's worktree exists before attempting any merge and aborts with an actionable message when it does not. Without that check, a merge into a missing directory fails at the `cd`, which downstream error handling misreports as a merge conflict — leaving a stuck `MERGE_BASE` marker and no usable path forward.

### 4. `checkout`/`co` prints the worktree path; it does not relocate anything
A script invoked as a child process cannot change its parent shell's working directory. Per explicit product decision, `checkout`/`co` validates the branch/worktree and prints its path so the user can `cd` manually, rather than failing outright or emitting an `eval`-oriented machine format. This keeps the command's output human-first, consistent with the rest of Git Flow's output style, at the cost of not being a drop-in scriptable replacement for the old checkout behavior.

### 5. Hooks and merge-resume state key off `git rev-parse --git-common-dir`, not `--git-dir`
For a linked worktree, `--git-dir` returns that worktree's private administrative directory (e.g. `.bare/worktrees/feature-login`), not the shared `.bare` directory where the real `hooks/` and git-flow's own `.gitflow/MERGE_BASE` marker need to live. Switching `DOT_GIT_DIR` (or introducing a dedicated common-dir variable) to `--git-common-dir` is required for hooks to fire consistently and for a conflicted `finish` to be resumable from a different worktree than the one that started it — both already confirmed necessary by the agreed conflict-handling behavior (conflicts surface in the base branch's worktree, not the source branch's). `SQUASH_MSG` is the exception: git reads it from the private git directory of the worktree that runs `git commit` after a squash merge, so the scripts must compute that path per worktree (`git -C <merge-worktree> rev-parse --git-dir`) rather than file it under the common directory.

### 6. New trailing hook argument for worktree path, not a new hook file
Rather than introducing new hook names for worktree-aware behavior, the existing `pre`/`post` hooks for `start`/`track`/`finish`/`delete` gain one new trailing positional argument (the worktree path, empty string when worktree mode is off). This keeps the hook contract additive and backward compatible — existing hook scripts that only read `$1`-`$4` are unaffected.

### 7. Config-driven opt-in gated by the existing `-f` reinit guard
`gitflow.worktree` is set at `git flow init` time and reuses the existing `gitflow_is_initialized && ! flag force` guard that already protects reinitialization, rather than introducing a separate "reconfigure" flag or command. This matches established Git Flow conventions and the explicit product decision to treat worktree mode as sticky until a forced reinit.

## Risks / Trade-offs

- **[Risk] Migrating an existing, in-use repository into `.bare` + worktrees is a one-time, structurally invasive operation.** → Mitigation: only runs when the user explicitly opts in via `git flow init`, never silently; `-f` is required to change it again later, making the operation deliberate and rare.
- **[Risk] `git worktree remove --force` can still fail on Windows/MSYS if a file is genuinely locked by another process.** → Mitigation: `finish`/`delete` abort before touching the branch ref in that case (see lifecycle spec, "Worktree removal is forced and fails safely"), leaving a retryable, non-corrupted state instead of an orphaned branch or a half-deleted worktree.
- **[Risk] `checkout`/`co` is no longer a true "switch to this branch" command.** → Mitigation: explicit product decision to print the path; documented as a deliberate, known UX change rather than an oversight.
- **[Risk] Custom hook scripts that assumed their CWD would already be inside the newly created branch after `start` will see a different CWD under worktree mode.** → Mitigation: the new trailing worktree-path argument gives hook authors an explicit, reliable way to locate the worktree instead of relying on CWD.
- **[Risk] `remote.origin.fetch` must be correctly rewritten during migration, or remote-tracking branches silently stop updating in the new worktrees.** → Mitigation: covered explicitly as part of the `gitflow-worktree-init` migration requirement; implementation must verify fetch refspec after migration as part of its own validation, not just assume it.

## Migration Plan

- No action required for repositories that never enable `gitflow.worktree` — zero behavior change.
- Enabling worktree mode is a one-time, explicit step performed via `git flow init`; it converts the current repository in place (`.git` → `.bare`, current checkout relocated into its branch's worktree directory, `master`/prefix directories created).
- Rolling back requires `git flow init -f` to disable `gitflow.worktree`; the reverse migration (collapsing worktrees back into a single tree) is implementation work to be detailed in `tasks.md`, not assumed to be automatic from day one.
