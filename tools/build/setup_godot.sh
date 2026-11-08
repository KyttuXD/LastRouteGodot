#!/usr/bin/env bash
# Installs the pinned headless-capable Godot editor (idempotent) so the validation suite can run locally and in cloud sessions.
#   tools/build/setup_godot.sh          install Godot and link it as ~/.local/bin/godot4
#   tools/build/setup_godot.sh --hook   also install a git pre-push hook that runs tools/build/check.sh
#   tools/build/setup_godot.sh --templates   also install the matching export templates (1.3 GB; needed to export builds)
#   Flags combine. GODOT_VERSION is the single pin used by local setup and by .github/workflows/build.yml.
# tools/build/push_to_github.sh and tools/build/check.sh both find `godot4` on PATH.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2-stable}"
INSTALL_DIR="${GODOT_INSTALL_DIR:-$HOME/.local/share/godot/$GODOT_VERSION}"
BIN_DIR="${GODOT_BIN_DIR:-$HOME/.local/bin}"
REPOSITORY_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

case "$(uname -s)-$(uname -m)" in
	Linux-x86_64) ASSET="Godot_v${GODOT_VERSION}_linux.x86_64" ;;
	Linux-aarch64) ASSET="Godot_v${GODOT_VERSION}_linux.arm64" ;;
	*) echo "Unsupported platform $(uname -sm); install Godot ${GODOT_VERSION} manually and put it on PATH as godot4." >&2; exit 1 ;;
esac

BINARY="$INSTALL_DIR/$ASSET"
if [[ ! -x "$BINARY" ]]; then
	mkdir -p "$INSTALL_DIR" "$BIN_DIR"
	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT
	URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${ASSET}.zip"
	echo "Downloading $URL"
	curl -fsSL -o "$TMP/godot.zip" "$URL"
	unzip -q -o "$TMP/godot.zip" -d "$INSTALL_DIR"
	chmod +x "$BINARY"
fi
mkdir -p "$BIN_DIR"
ln -sf "$BINARY" "$BIN_DIR/godot4"
echo "Godot ready: $("$BIN_DIR/godot4" --version) -> $BIN_DIR/godot4"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "Add $BIN_DIR to PATH to use godot4 directly." ;; esac

if [[ " $* " == *" --templates "* ]]; then
	# the exporter looks in <data dir>/export_templates/<version with - as .>/ (4.7.2-stable -> 4.7.2.stable)
	TEMPLATES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION/-/.}"
	if [[ ! -f "$TEMPLATES_DIR/version.txt" ]]; then
		TMP_T="$(mktemp -d)"
		echo "Downloading export templates for $GODOT_VERSION"
		curl -fsSL -o "$TMP_T/templates.tpz" \
			"https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
		mkdir -p "$TMP_T/x" "$TEMPLATES_DIR"
		unzip -q -o "$TMP_T/templates.tpz" -d "$TMP_T/x"
		cp -a "$TMP_T/x/templates/." "$TEMPLATES_DIR/"
		rm -rf "$TMP_T"
	fi
	echo "Export templates ready: $TEMPLATES_DIR"
fi

if [[ " $* " == *" --hook "* ]]; then
	HOOK="$REPOSITORY_ROOT/.git/hooks/pre-push"
	printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/tools/build/check.sh"\n' > "$HOOK"
	chmod +x "$HOOK"
	echo "Installed pre-push hook: $HOOK (bypass once with git push --no-verify)"
fi
