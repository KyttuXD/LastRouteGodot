# Last Route agent notes

## Publishing to GitHub

- Never stage, commit, push, tag, or create a release unless the user has
  explicitly authorized that action in the current conversation.
- When a commit and push are authorized, use `scripts/push_to_github.sh` from
  the repository instead of assembling an ad-hoc Git command sequence.
- Read `scripts/PUSHING.md` before using the helper. In particular, its default
  staging mode includes every tracked and untracked path shown by
  `git status`; this repository may contain unrelated user work.
- Keep the full test run enabled unless the same working-tree revision was
  already validated and the user accepts `--skip-tests`.
- Do not force-push. If the helper reports that the remote branch diverged,
  stop and resolve it without discarding either the local or remote history.
- The helper only commits and pushes. Version bumps, tags, GitHub releases,
  and release artifacts are separate operations requiring separate user
  authorization.
