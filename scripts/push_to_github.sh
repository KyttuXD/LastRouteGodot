#!/usr/bin/env bash
set -euo pipefail

REMOTE="origin"
SKIP_TESTS=false
TRACKED_ONLY=false
COMMIT_PARTS=()


usage() {
	cat <<'EOF'
Usage: ./scripts/push_to_github.sh [options] [commit message]

Safely review, test, commit, and push the current branch to GitHub.

Options:
  --skip-tests     Skip the Godot and Node test suites.
  --tracked-only   Stage modifications/deletions to tracked files only.
  -h, --help       Show this help.

Examples:
  ./scripts/push_to_github.sh "Finish co-op playability pass"
  ./scripts/push_to_github.sh --tracked-only "Update gameplay code"

Every staging, commit, and push step still requires confirmation. The script
never creates a release, tag, or version bump.

Full documentation: scripts/PUSHING.md
EOF
}


confirm() {
	local answer
	read -r -p "$1 [y/N] " answer
	[[ "$answer" =~ ^[Yy]$ ]]
}


die() {
	printf 'ERROR: %s\n' "$1" >&2
	exit 1
}


while (($#)); do
	case "$1" in
		--skip-tests)
			SKIP_TESTS=true
			;;
		--tracked-only)
			TRACKED_ONLY=true
			;;
		-h|--help)
			usage
			exit 0
			;;
		--)
			shift
			COMMIT_PARTS+=("$@")
			break
			;;
		-*)
			die "unknown option: $1"
			;;
		*)
			COMMIT_PARTS+=("$1")
			;;
	esac
	shift
done

command -v git >/dev/null 2>&1 || die "git is not installed"

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(git -C "$SCRIPT_DIRECTORY" rev-parse --show-toplevel 2>/dev/null)" \
	|| die "this script is not inside a Git repository"
cd "$REPOSITORY_ROOT"

BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || die "detached HEAD; switch to a branch before publishing"
git remote get-url "$REMOTE" >/dev/null 2>&1 \
	|| die "Git remote '$REMOTE' is not configured"

printf 'Repository: %s\n' "$REPOSITORY_ROOT"
printf 'Destination: %s/%s\n\n' "$REMOTE" "$BRANCH"

if [[ "$BRANCH" != "main" ]]; then
	confirm "Current branch is '$BRANCH', not 'main'. Continue on this branch?" \
		|| exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
	printf 'Working-tree changes:\n'
	git status --short
	printf '\n'
	git diff --check

	if [[ "$SKIP_TESTS" == false ]]; then
		printf 'Running Node backend tests...\n'
		command -v npm >/dev/null 2>&1 \
			|| die "npm is unavailable; install Node.js or rerun with --skip-tests"
		npm test

		printf '\nRunning complete Godot validation suite...\n'
		if command -v godot4 >/dev/null 2>&1; then
			godot4 --headless --path "$REPOSITORY_ROOT" res://scenes/validate.tscn
		elif command -v godot >/dev/null 2>&1; then
			godot --headless --path "$REPOSITORY_ROOT" res://scenes/validate.tscn
		elif command -v flatpak >/dev/null 2>&1 \
				&& flatpak info org.godotengine.Godot >/dev/null 2>&1; then
			flatpak run org.godotengine.Godot --headless --path "$REPOSITORY_ROOT" \
				res://scenes/validate.tscn
		else
			die "Godot 4 is unavailable; install it or rerun with --skip-tests"
		fi
	else
		printf 'WARNING: tests were skipped by request.\n'
	fi

	printf '\nChanges ready to stage:\n'
	git status --short
	printf '\n'
	if [[ "$TRACKED_ONLY" == true ]]; then
		confirm "Stage every tracked modification/deletion shown above?" || exit 0
		git add -u
	else
		confirm "Stage ALL changes shown above, including untracked files?" || exit 0
		git add -A
	fi

	if git diff --cached --quiet; then
		printf 'Nothing was staged; there is no commit to create.\n'
		exit 0
	fi

	git diff --cached --check
	printf '\nStaged commit summary:\n'
	git diff --cached --stat
	printf '\nStaged paths:\n'
	git diff --cached --name-status

	large_file_found=false
	while IFS= read -r -d '' path; do
		[[ -f "$path" ]] || continue
		size="$(stat -c '%s' -- "$path")"
		if ((size >= 50 * 1024 * 1024)); then
			printf "Large binary needs Git LFS review before GitHub: %s (%d bytes)\n" \
				"$path" "$size" >&2
			large_file_found=true
		fi
	done < <(git diff --cached --name-only --diff-filter=ACMR -z)
	[[ "$large_file_found" == false ]] \
		|| die "remove the large staged file or configure Git LFS in development and deployment before committing"

	COMMIT_MESSAGE="${COMMIT_PARTS[*]:-}"
	if [[ -z "$COMMIT_MESSAGE" ]]; then
		printf '\n'
		read -r -p "Commit message: " COMMIT_MESSAGE
	fi
	[[ -n "${COMMIT_MESSAGE//[[:space:]]/}" ]] || die "commit message cannot be empty"

	git config user.name >/dev/null 2>&1 \
		|| die "Git user.name is unset; configure it before committing"
	git config user.email >/dev/null 2>&1 \
		|| die "Git user.email is unset; configure it before committing"

	printf '\nCommit message: %s\n' "$COMMIT_MESSAGE"
	confirm "Create this commit?" || exit 0
	git commit -m "$COMMIT_MESSAGE"
else
	printf 'Working tree is clean; checking for an existing unpushed commit.\n'
fi

printf '\nRefreshing %s/%s before push...\n' "$REMOTE" "$BRANCH"
REMOTE_BRANCH_EXISTS=false
if git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
	REMOTE_BRANCH_EXISTS=true
	git fetch --quiet "$REMOTE" "$BRANCH"
	REMOTE_REF="refs/remotes/${REMOTE}/${BRANCH}"
	if ! git merge-base --is-ancestor "$REMOTE_REF" HEAD; then
		die "$REMOTE/$BRANCH contains commits not in the local branch; pull/rebase and retest before pushing"
	fi
	AHEAD="$(git rev-list --count "${REMOTE_REF}..HEAD")"
	if [[ "$AHEAD" == "0" ]]; then
		printf '%s/%s is already up to date.\n' "$REMOTE" "$BRANCH"
		exit 0
	fi
	printf '%s commit(s) are ready to push.\n' "$AHEAD"
else
	ls_remote_status=$?
	[[ "$ls_remote_status" == "2" ]] \
		|| die "could not contact $REMOTE; check the network and GitHub credentials"
	printf 'Remote branch %s/%s does not exist yet.\n' "$REMOTE" "$BRANCH"
fi

confirm "Push HEAD to $REMOTE/$BRANCH?" || {
	printf 'Push cancelled. The local commit remains ready.\n'
	exit 0
}

if [[ "$REMOTE_BRANCH_EXISTS" == true ]]; then
	git push "$REMOTE" "HEAD:$BRANCH"
else
	git push --set-upstream "$REMOTE" "HEAD:$BRANCH"
fi

printf '\nPublished successfully to %s/%s.\n' "$REMOTE" "$BRANCH"
