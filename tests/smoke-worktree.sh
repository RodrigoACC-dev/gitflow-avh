#!/bin/sh
#
# Smoke tests for git-flow's opt-in worktree mode (--worktree) and the
# classic single-tree flow.
#
# Usage:
#   sh tests/smoke-worktree.sh
#   KEEP=1 sh tests/smoke-worktree.sh   # keep the temporary repositories
#
# Exits non-zero if any check fails.
#
set -u

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gitflow-smoke.XXXXXX") || exit 1
BIN_DIR="$TMP_ROOT/bin"

export GIT_AUTHOR_NAME=smoke
export GIT_AUTHOR_EMAIL=smoke@example.invalid
export GIT_COMMITTER_NAME=smoke
export GIT_COMMITTER_EMAIL=smoke@example.invalid
export GIT_EDITOR=true

checks=0
failures=0

ok()  { checks=$((checks + 1)); }
bad() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL: %s\n' "$*" >&2; }

assert_dir_exists()   { [ -d "$1" ] && ok || bad "$2 (missing directory: $1)"; }
assert_dir_absent()   { [ ! -d "$1" ] && ok || bad "$2 (unexpected directory: $1)"; }
assert_file_exists()  { [ -f "$1" ] && ok || bad "$2 (missing file: $1)"; }
assert_file_absent()  { [ ! -f "$1" ] && ok || bad "$2 (unexpected file: $1)"; }
assert_branch_exists()  { git -C "$1" show-ref --verify --quiet "refs/heads/$2" && ok || bad "$3 (missing branch: $2)"; }
assert_branch_absent()  { git -C "$1" show-ref --verify --quiet "refs/heads/$2" && bad "$3 (branch still exists: $2)" || ok; }
assert_contains()       { case "$1" in *"$2"*) ok ;; *) bad "$3 (output does not contain: $2)" ;; esac; }
assert_not_contains()   { case "$1" in *"$2"*) bad "$3 (output contains: $2)" ;; *) ok ;; esac; }

cleanup() {
	if [ "${KEEP:-0}" = "1" ]; then
		printf 'Temporary repositories kept in %s\n' "$TMP_ROOT"
	else
		rm -rf "$TMP_ROOT"
	fi
}
trap cleanup EXIT

# Stage LF copies of the scripts: a checkout with CRLF line endings would
# otherwise make them unrunnable on POSIX shells.
mkdir -p "$BIN_DIR"
for f in git-flow git-flow-init git-flow-feature git-flow-bugfix git-flow-hotfix \
	git-flow-release git-flow-support gitflow-common gitflow-shFlags; do
	tr -d '\r' < "$REPO_DIR/$f" > "$BIN_DIR/$f" || exit 1
done
chmod +x "$BIN_DIR"/git-flow*
FLOW="$BIN_DIR/git-flow"

# new_repo <dir>: create a repository with master and develop, print its path.
new_repo() {
	_dir=$1
	mkdir -p "$_dir"
	(
		cd "$_dir" || exit 1
		git init -q -b master .
		printf 'base\n' > README.md
		git add README.md
		git commit -q -m base
		git branch develop
	)
	printf '%s\n' "$_dir"
}

test_init_layout() {
	printf 'init: worktree layout\n'
	dir=$(new_repo "$TMP_ROOT/init-layout")
	(cd "$dir" && "$FLOW" init -d --worktree >/dev/null 2>&1)
	assert_dir_exists "$dir/.bare" "init creates .bare"
	assert_dir_exists "$dir/master" "init creates master worktree"
	assert_dir_exists "$dir/develop" "init creates develop worktree"
	for prefix in feature bugfix hotfix release support; do
		assert_dir_exists "$dir/$prefix" "init creates $prefix/ container"
	done
	assert_dir_absent "$dir/.gitflow-migrate-tmp" "init leaves no staging directory"
}

test_feature_lifecycle() {
	printf 'lifecycle: feature start/finish from inside its worktree\n'
	dir=$(new_repo "$TMP_ROOT/feature-lifecycle")
	(cd "$dir" && "$FLOW" init -d --worktree >/dev/null 2>&1)
	(cd "$dir/develop" && "$FLOW" feature start login >/dev/null 2>&1)
	assert_dir_exists "$dir/feature/login" "feature start creates the worktree"
	(
		cd "$dir/feature/login" || exit 1
		printf 'code\n' > login.txt
		git add login.txt
		git commit -q -m "add login"
	)
	(cd "$dir/feature/login" && "$FLOW" feature finish login >/dev/null 2>&1)
	assert_dir_absent "$dir/feature/login" "feature finish removes the worktree"
	assert_dir_exists "$dir/feature" "feature finish keeps the feature/ container"
	assert_branch_absent "$dir" feature/login "feature finish deletes the branch"
	assert_file_exists "$dir/develop/login.txt" "feature finish merges into develop"
}

test_conflict_and_resume() {
	printf 'lifecycle: merge conflict surfaced in base worktree and resumed from another one\n'
	dir=$(new_repo "$TMP_ROOT/conflict-resume")
	(cd "$dir" && "$FLOW" init -d --worktree >/dev/null 2>&1)
	(cd "$dir/develop" && "$FLOW" feature start x >/dev/null 2>&1)
	(
		cd "$dir/feature/x" || exit 1
		printf 'feature-change\n' > shared.txt
		git add shared.txt
		git commit -q -m "feature changes shared.txt"
	)
	(
		cd "$dir/develop" || exit 1
		printf 'develop-change\n' > shared.txt
		git add shared.txt
		git commit -q -m "develop changes shared.txt"
	)
	out=$(cd "$dir/feature/x" && "$FLOW" feature finish x 2>&1)
	assert_contains "$out" "There were merge conflicts" "conflicting finish reports the conflict"
	assert_file_exists "$dir/.bare/.gitflow/MERGE_BASE" "conflicting finish records MERGE_BASE"
	assert_dir_exists "$dir/feature/x" "conflicting finish leaves the feature worktree intact"
	assert_branch_exists "$dir" feature/x "conflicting finish leaves the feature branch intact"
	(
		cd "$dir/develop" || exit 1
		printf 'develop-change\nfeature-change\n' > shared.txt
		git add shared.txt
		git commit -q -m "resolve conflict"
	)
	out=$(cd "$dir/develop" && "$FLOW" feature finish x 2>&1)
	assert_dir_absent "$dir/feature/x" "resumed finish (from develop) removes the worktree"
	assert_branch_absent "$dir" feature/x "resumed finish deletes the branch"
	assert_file_absent "$dir/.bare/.gitflow/MERGE_BASE" "resumed finish clears MERGE_BASE"
}

test_finish_requires_base_worktree() {
	printf 'lifecycle: finish aborts clearly when the base branch has no worktree\n'
	dir=$(new_repo "$TMP_ROOT/guard-base")
	(cd "$dir" && "$FLOW" init -d --worktree >/dev/null 2>&1)
	git -C "$dir" branch custom-base master
	(cd "$dir/develop" && "$FLOW" feature start g custom-base >/dev/null 2>&1)
	(
		cd "$dir/feature/g" || exit 1
		printf 'work\n' > work.txt
		git add work.txt
		git commit -q -m work
	)
	out=$(cd "$dir/feature/g" && "$FLOW" feature finish g 2>&1)
	assert_contains "$out" "No worktree found for base branch" "finish reports the missing base worktree"
	assert_file_absent "$dir/.bare/.gitflow/MERGE_BASE" "no MERGE_BASE marker is written"
	assert_dir_exists "$dir/feature/g" "feature worktree stays intact"
	assert_branch_exists "$dir" feature/g "feature branch stays intact"
	(
		cd "$dir/develop" || exit 1
		git worktree add "$dir/custom-base" custom-base >/dev/null 2>&1
	)
	(cd "$dir/feature/g" && "$FLOW" feature finish g >/dev/null 2>&1)
	assert_dir_absent "$dir/feature/g" "finish succeeds once the base has a worktree"
	assert_file_exists "$dir/custom-base/work.txt" "merge reached the base worktree"
}

test_forced_removal_failure() {
	printf 'lifecycle: a failed forced removal keeps the branch\n'
	dir=$(new_repo "$TMP_ROOT/locked")
	(cd "$dir" && "$FLOW" init -d --worktree >/dev/null 2>&1)
	(cd "$dir/develop" && "$FLOW" feature start locked >/dev/null 2>&1)
	(
		cd "$dir/feature/locked" || exit 1
		printf 'x\n' > x.txt
		git add x.txt
		git commit -q -m x
	)
	(cd "$dir" && git worktree lock feature/locked --reason "smoke test" >/dev/null 2>&1)
	out=$(cd "$dir/feature/locked" && "$FLOW" feature finish locked 2>&1)
	assert_contains "$out" "Could not remove the worktree" "finish reports the removal failure"
	assert_branch_exists "$dir" feature/locked "branch is not deleted when removal fails"
	(cd "$dir" && git worktree unlock feature/locked >/dev/null 2>&1)
}

test_squash_message_in_base_worktree() {
	printf 'lifecycle: squash message resolves in the base worktree\n'
	dir=$(new_repo "$TMP_ROOT/squash")
	(cd "$dir" && "$FLOW" init -d --worktree >/dev/null 2>&1)
	(cd "$dir/develop" && "$FLOW" feature start sq >/dev/null 2>&1)
	(
		cd "$dir/feature/sq" || exit 1
		printf 'a\n' > a.txt
		git add a.txt
		git commit -q -m "sq add a"
	)
	(cd "$dir/feature/sq" && "$FLOW" feature finish --squash --squash-info sq >/dev/null 2>&1)
	msg=$(git -C "$dir/develop" log -1 --format=%B)
	assert_contains "$msg" "Squashed commit of the following" "custom squash message is used"
	assert_contains "$msg" "Merged feature branch 'feature/sq'" "squash message names the branch"
	assert_file_absent "$dir/.bare/SQUASH_MSG" "SQUASH_MSG is not written to the common dir"
	assert_file_exists "$dir/develop/a.txt" "squash merge lands in develop"
}

assert_status() {
	_actual=$(git -C "$1" status --porcelain)
	[ "$_actual" = "$2" ] && ok || bad "$3 (got: $_actual)"
}

test_preserved_top_level_dirs() {
	printf 'init: ignored dirs and nested repos stay at the hub\n'
	dir=$(new_repo "$TMP_ROOT/preserved")
	printf 'scratch\n' > "$dir/notes.txt"                 # legitimately untracked
	(
		cd "$dir" || exit 1
		printf 'build/\n' > .gitignore
		git add .gitignore
		git commit -q -m "ignore build"
	)
	mkdir -p "$dir/build"
	printf 'artifact\n' > "$dir/build/out.bin"
	mkdir -p "$dir/nested repo"
	(
		cd "$dir/nested repo" || exit 1
		git init -q -b main .
		printf 'nested\n' > nested.txt
		git add nested.txt
		git commit -q -m nested
		git worktree add -q "$dir/nested-wt" -b wt   # .git as a file
	) || exit 1
	out=$(cd "$dir" && "$FLOW" init -d --worktree 2>&1)
	assert_dir_exists "$dir/.bare" "migration completes with preserved dirs"
	assert_dir_absent "$dir/.gitflow-migrate-tmp" "no staging directory remains"
	assert_file_exists "$dir/build/out.bin" "ignored dir stays at the hub"
	assert_dir_exists "$dir/nested repo" "nested repo stays at the hub"
	assert_dir_exists "$dir/nested-wt" "nested worktree (.git file) stays at the hub"
	assert_dir_absent "$dir/master/build" "ignored dir is not moved into the worktree"
	assert_dir_absent "$dir/master/nested repo" "nested repo is not moved into the worktree"
	assert_file_exists "$dir/master/notes.txt" "legit untracked file migrates"
	assert_status "$dir/master" "?? notes.txt" "master worktree clean except the migrated untracked file"
	assert_status "$dir/develop" "" "develop worktree is clean"
	assert_contains "$out" "build (ignored)" "init reports the ignored dir left at the hub"
	assert_contains "$out" "nested repo (nested Git repository)" "init reports the nested repo left at the hub"
	(
		cd "$dir/nested repo" || exit 1
		printf 'more\n' > more.txt
		git add more.txt
		git commit -q -m more
	) || exit 1
	[ "$(git -C "$dir/nested repo" log -1 --format=%s)" = more ] && ok || bad "nested repo still works after migration"
	assert_status "$dir/nested-wt" "" "nested worktree still works after migration"
}

test_worktree_flag_is_sticky() {
	printf 'init: -w enables, --noworktree disables, plain reinit preserves\n'
	dir=$(new_repo "$TMP_ROOT/sticky-flag")
	(cd "$dir" && "$FLOW" init -d >/dev/null 2>&1)
	# State left by a migration that failed after the setting was written.
	git -C "$dir" config --bool gitflow.worktree true

	out=$(cd "$dir" && "$FLOW" init -f -d -w 2>&1)
	assert_dir_exists "$dir/.bare" "-w completes a pending migration"
	assert_not_contains "$out" "being disabled" "-w does not disable an already-enabled repo"
	[ "$(git -C "$dir" config --bool gitflow.worktree)" = true ] && ok || bad "-w leaves the setting enabled"

	out=$(cd "$dir" && "$FLOW" init -f -d 2>&1)
	assert_not_contains "$out" "being disabled" "plain reinit keeps the mode"
	[ "$(git -C "$dir" config --bool gitflow.worktree)" = true ] && ok || bad "plain reinit leaves the setting enabled"
	assert_dir_exists "$dir/.bare" "plain reinit leaves the layout alone"

	out=$(cd "$dir" && "$FLOW" init -f -d --noworktree 2>&1)
	assert_contains "$out" "Worktree mode is disabled" "--noworktree disables the mode"
	[ -z "$(git -C "$dir" config --bool gitflow.worktree 2>/dev/null)" ] && ok || bad "--noworktree clears the setting"
	assert_dir_absent "$dir/.bare" "--noworktree collapses the layout"

	out=$(cd "$dir" && "$FLOW" init -f -d -w 2>&1)
	[ "$(git -C "$dir" config --bool gitflow.worktree)" = true ] && ok || bad "-w re-enables the mode"
	assert_dir_exists "$dir/.bare" "-w migrates the collapsed repository again"
}

test_worktree_rollback() {
	printf 'rollback: --noworktree collapses back to a single working tree\n'
	dir=$(new_repo "$TMP_ROOT/rollback")
	git -C "$dir" config remote.origin.url "https://example.invalid/repo.git"
	git -C "$dir" config remote.origin.fetch "+refs/heads/develop:refs/remotes/origin/develop"
	(
		cd "$dir" || exit 1
		printf '*.log\n' > .gitignore
		git add .gitignore
		git commit -q -m "ignore logs"
	)
	(cd "$dir" && "$FLOW" init -d -w >/dev/null 2>&1)
	# A clean feature worktree is discarded; its branch must survive.
	(cd "$dir/develop" && "$FLOW" feature start feat >/dev/null 2>&1)
	# Ignored content inside a discarded worktree.
	printf 'noise\n' > "$dir/master/build.log"
	# Uncommitted work in develop must survive the collapse.
	printf 'changed\n' > "$dir/develop/README.md"
	printf 'scratch\n' > "$dir/develop/notes.txt"

	out=$(cd "$dir" && "$FLOW" init -f -d --noworktree 2>&1)
	assert_dir_absent "$dir/.bare" ".bare is gone after the collapse"
	[ -d "$dir/.git" ] && ok || bad ".git is a directory again"
	assert_dir_absent "$dir/develop" "develop worktree directory was removed"
	assert_dir_absent "$dir/master" "master worktree directory was removed"
	assert_dir_absent "$dir/feature" "empty feature container was removed"
	[ "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" = develop ] && ok || bad "develop is checked out at the root"
	assert_file_exists "$dir/notes.txt" "untracked develop file survives"
	[ "$(cat "$dir/README.md")" = changed ] && ok || bad "modified develop file survives"
	assert_branch_exists "$dir" master "master branch survives"
	assert_branch_exists "$dir" feature/feat "clean feature branch survives"
	assert_contains "$out" "Removed worktrees" "summary lists removed worktrees"
	assert_contains "$out" "Ignored files were discarded" "summary reports discarded ignored files"
	[ -z "$(git -C "$dir" config --bool gitflow.worktree 2>/dev/null)" ] && ok || bad "worktree setting is cleared"
	[ "$(git -C "$dir" config --get gitflow.path.hooks)" = "$dir/.git/hooks" ] && ok || bad "hooks path points at .git/hooks"
	[ "$(git -C "$dir" config --get remote.origin.fetch)" = "+refs/heads/develop:refs/remotes/origin/develop" ] && ok || bad "original fetch refspec restored"
	[ -z "$(git -C "$dir" config --get gitflow.worktree.savedfetch 2>/dev/null)" ] && ok || bad "saved fetch refspec cleared"

	# init requires a clean working tree, and the collapse preserved the
	# dirty develop state on purpose; commit it before re-enabling.
	(
		cd "$dir" || exit 1
		git add -A
		git commit -q -m "keep preserved work"
	)
	out=$(cd "$dir" && "$FLOW" init -f -d -w 2>&1)
	assert_dir_exists "$dir/.bare" "round trip: -w migrates again"
	[ "$(git -C "$dir" config --bool gitflow.worktree)" = true ] && ok || bad "round trip: setting enabled again"
}

test_worktree_rollback_safeguards() {
	printf 'rollback: refuses to discard work in progress\n'
	dir=$(new_repo "$TMP_ROOT/rollback-guard")
	(cd "$dir" && "$FLOW" init -d -w >/dev/null 2>&1)
	printf 'dirty\n' > "$dir/master/dirty.txt"
	out=$(cd "$dir" && "$FLOW" init -f -d --noworktree 2>&1)
	assert_contains "$out" "Cannot collapse" "dirty master aborts the rollback"
	assert_dir_exists "$dir/.bare" "aborted rollback leaves .bare in place"
	assert_dir_exists "$dir/master" "aborted rollback leaves worktrees in place"
	assert_file_exists "$dir/master/dirty.txt" "aborted rollback leaves the dirty file in place"
	[ "$(git -C "$dir" config --bool gitflow.worktree)" = true ] && ok || bad "aborted rollback keeps the setting"

	rm -f "$dir/master/dirty.txt"
	git -C "$dir" worktree lock master --reason "smoke test" >/dev/null 2>&1
	out=$(cd "$dir" && "$FLOW" init -f -d --noworktree 2>&1)
	assert_contains "$out" "is locked" "locked worktree aborts the rollback"
	assert_dir_exists "$dir/.bare" "locked abort leaves .bare in place"
	git -C "$dir" worktree unlock master >/dev/null 2>&1

	dir2=$(new_repo "$TMP_ROOT/rollback-classic")
	(cd "$dir2" && "$FLOW" init -d >/dev/null 2>&1)
	(cd "$dir2" && "$FLOW" init -f -d --noworktree >/dev/null 2>&1)
	[ "$(git -C "$dir2" config --bool gitflow.worktree)" = false ] && ok || bad "classic repo: only the setting is cleared"
	assert_dir_absent "$dir2/.bare" "classic repo: no layout change"
}

test_classic_mode_unchanged() {
	printf 'classic: single-tree flow is unaffected\n'
	dir=$(new_repo "$TMP_ROOT/classic")
	(cd "$dir" && "$FLOW" init -d >/dev/null 2>&1)
	assert_dir_absent "$dir/.bare" "classic init creates no .bare"
	assert_dir_absent "$dir/feature" "classic init creates no prefix container"
	(cd "$dir" && "$FLOW" feature start classic >/dev/null 2>&1)
	branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
	[ "$branch" = "feature/classic" ] && ok || bad "classic start checks out the branch in place (got: $branch)"
	(
		cd "$dir" || exit 1
		printf 'c\n' > classic.txt
		git add classic.txt
		git commit -q -m classic
	)
	(cd "$dir" && "$FLOW" feature finish classic >/dev/null 2>&1)
	assert_branch_absent "$dir" feature/classic "classic finish deletes the branch"
	assert_file_exists "$dir/classic.txt" "classic finish merges into develop"
	[ "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" = "develop" ] && ok || bad "classic finish returns to develop"
}

test_init_layout
test_feature_lifecycle
test_conflict_and_resume
test_finish_requires_base_worktree
test_forced_removal_failure
test_squash_message_in_base_worktree
test_preserved_top_level_dirs
test_worktree_flag_is_sticky
test_worktree_rollback
test_worktree_rollback_safeguards
test_classic_mode_unchanged

printf '\n%d checks, %d failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
