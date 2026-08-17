# GitHub commit and push helper

`push_to_github.sh` is the project-owned path for reviewing, validating,
committing, and pushing work. It is intentionally interactive so that a person
or coding agent cannot silently publish a dirty shared worktree.

## Standard use

From anywhere inside the repository, run:

```sh
./scripts/push_to_github.sh "Describe the completed change"
```

If no commit message is supplied, the script asks for one. It discovers the
repository root automatically and publishes the currently checked-out branch
to the branch with the same name on `origin`. A non-`main` branch requires an
extra confirmation.

The normal sequence is:

1. Display every tracked and untracked working-tree change.
2. Reject whitespace errors with `git diff --check`.
3. Run all Node backend tests with `npm test`.
4. Run the complete Godot validation scene. The helper supports `godot4`,
   `godot`, or the `org.godotengine.Godot` Flatpak.
5. Ask before staging anything.
6. Display the complete staged name/status list and diff statistics.
7. Reject staged files at or above 50 MiB, well before GitHub's 100 MiB limit,
   and direct genuinely large retained assets to Git LFS.
8. Ask before creating the commit.
9. Fetch the destination branch and refuse to push over remote-only commits.
10. Ask separately before pushing.

It never changes the game version, creates a tag, creates a GitHub release, or
force-pushes.

## Options

```sh
./scripts/push_to_github.sh --tracked-only "Commit message"
./scripts/push_to_github.sh --skip-tests "Commit message"
./scripts/push_to_github.sh --help
```

- `--tracked-only` stages modifications and deletions to already tracked files
  but leaves all new files untracked. Use it carefully: newly added scenes,
  scripts, textures, and `.uid` files may be required by the change.
- `--skip-tests` bypasses both test suites. Use it only when the exact current
  revision has already passed them or the user explicitly accepts an untested
  commit.

Without `--tracked-only`, the script runs `git add -A`. Always read both status
lists before answering yes. Generated Meshy tasks, prop preview renders and
Blender `.blend1` backups are ignored; retained `.blend` sources, GLBs, atlases
and Godot imports remain visible for review. Persistent/private paths such as
`.data/`, `.env`, `builds/`, and `.godot/` are also excluded by `.gitignore`.

## Guidance for coding agents

Running the helper is a write/publish operation. Only do so after the user has
explicitly requested a commit and push. Do not interpret a request to edit,
test, review, or prepare files as permission to publish them.

Before approving the staging prompt:

- inspect `git status --short` for unrelated user changes;
- confirm that required untracked files are intentional;
- preserve the user's chosen version unless they separately requested a bump;
- use a commit message that describes the actual staged scope.

Do not pipe automatic `yes` responses into the helper. Each prompt is a final
scope boundary and should be evaluated independently.

## Cancellation and recovery

- Cancelling before staging leaves the index and working tree unchanged.
- Cancelling before the commit may leave the reviewed files staged, but does
  not modify their contents.
- Cancelling before the push leaves a normal local commit. Running the helper
  again with a clean working tree detects and offers to push that commit.
- If the remote contains commits absent locally, the helper aborts instead of
  force-pushing. Inspect the histories and integrate them safely before retrying.
- A failed push also leaves the local commit intact.

## GitHub authentication

The repository currently uses an HTTPS `origin`. `git push` therefore uses the
machine's configured Git credential helper. If GitHub authentication is not
available, either configure the GitHub CLI for Git:

```sh
gh auth login
gh auth setup-git
```

or enter a GitHub personal access token as the HTTPS password when Git prompts.
Never place a token in the script, repository, commit message, or remote URL.
