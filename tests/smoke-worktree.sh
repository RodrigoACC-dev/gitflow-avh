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
test_classic_mode_unchanged

printf '\n%d checks, %d failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
