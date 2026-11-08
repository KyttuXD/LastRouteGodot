#!/usr/bin/env bash
# Publishes one commit's builds to the single GitHub prerelease tagged `staging` (CI: the staging-release job of
# .github/workflows/build.yml, on every push to main). It never makes a second release or tag:
#   - the first run creates the `staging` release and its tag;
#   - every run moves that same tag to this commit, overwrites the files it is given (same names, --clobber), and
#     rewrites the release title and notes.
# A platform whose build failed is not in the file list: its previous file stays, and the notes say which files are
# from this commit and which are older.
# Usage: tools/build/staging_release.sh <file>...   (needs gh, GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA)
set -euo pipefail

TAG="${STAGING_TAG:-staging}"
REPO="${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY (owner/name)}"
SHA="${GITHUB_SHA:?set GITHUB_SHA}"
SHORT="${SHA::7}"
# every file a full build produces; anything else on the release is removed
EXPECTED=(
	KyttusLab-Linux-Debug.x86_64
	KyttusLab-Windows-Debug.exe
	KyttusLab-macOS-Intel-Debug.zip
	KyttusLab-macOS-AppleSilicon-Debug.zip
	KyttusLab-Web-Debug.zip
)

files=()
for f in "$@"; do [ -f "$f" ] && files+=("$f"); done
if [ "${#files[@]}" -eq 0 ]; then
	echo "::warning::no builds to publish; the staging release is left as it is"
	exit 0
fi

if ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
	echo "creating the $TAG release (first run only)"
	gh release create "$TAG" -R "$REPO" --prerelease --target "$SHA" --title "Staging" --notes "Latest builds from main."
fi

# the tag is the release's; move it here instead of making a new one
if gh api "repos/$REPO/git/ref/tags/$TAG" >/dev/null 2>&1; then
	gh api -X PATCH "repos/$REPO/git/refs/tags/$TAG" -f sha="$SHA" -F force=true >/dev/null
else
	gh api -X POST "repos/$REPO/git/refs" -f ref="refs/tags/$TAG" -f sha="$SHA" >/dev/null
fi

gh release upload "$TAG" -R "$REPO" --clobber "${files[@]}"

uploaded=()
for f in "${files[@]}"; do uploaded+=("$(basename "$f")"); done
is_in() { local needle="$1"; shift; local x; for x in "$@"; do [ "$x" = "$needle" ] && return 0; done; return 1; }

# files from older layouts (names no build makes any more) are removed
while IFS= read -r asset; do
	[ -n "$asset" ] || continue
	if ! is_in "$asset" "${EXPECTED[@]}"; then
		gh release delete-asset "$TAG" "$asset" -R "$REPO" --yes
	fi
done < <(gh release view "$TAG" -R "$REPO" --json assets -q '.assets[].name')

subject="$(git log -1 --format=%s "$SHA" 2>/dev/null || true)"
{
	echo "Debug builds of \`main\` at [\`$SHORT\`](https://github.com/$REPO/commit/$SHA)${subject:+: $subject}."
	echo "Updated $(date -u '+%Y-%m-%d %H:%M UTC'). This release is replaced by every push to main; it is not a versioned release."
	echo
	echo "| File | Build |"
	echo "| --- | --- |"
	for name in "${EXPECTED[@]}"; do
		if is_in "$name" "${uploaded[@]}"; then echo "| \`$name\` | this commit |"
		else echo "| \`$name\` | older build (this commit's build failed) |"; fi
	done
	echo
	echo "- **Linux:** \`chmod +x\` the file after downloading."
	echo "- **macOS:** unzip, then right-click the app and choose Open the first time (ad-hoc signed, not notarized)."
	echo "  Intel Macs use the Intel build, M-series Macs the Apple Silicon build."
	echo "- **Web:** unzip and serve the folder over HTTP(S); the \`.gz\` files are pre-compressed copies."
} > staging-notes.md

gh release edit "$TAG" -R "$REPO" --prerelease --title "Staging ($SHORT)" --notes-file staging-notes.md
echo "staging release now at $SHORT with: ${uploaded[*]}"
