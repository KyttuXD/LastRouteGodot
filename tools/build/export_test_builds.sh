#!/usr/bin/env bash
set -eu

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="${project_dir}/builds"
revision_file="${project_dir}/build_revision.json"

cleanup_revision() {
	rm -f -- "${revision_file}"
}
trap cleanup_revision EXIT

if command -v godot4 >/dev/null 2>&1; then
	godot_command=(godot4)
elif command -v godot >/dev/null 2>&1; then
	godot_command=(godot)
elif command -v flatpak >/dev/null 2>&1; then
	godot_command=(flatpak run org.godotengine.Godot)
else
	printf 'Godot 4 was not found.\n' >&2
	exit 1
fi
# Templates only ship universal binaries; ship Apple Silicon only unless MAC_UNIVERSAL=1.
if [[ "${MAC_UNIVERSAL:-0}" != 1 ]]; then
	"${project_dir}/tools/macos/thin_app.sh" "${build_dir}/KyttusLab-macOS-Debug.zip" arm64
fi

mkdir -p "${build_dir}/KyttusLab-Web-Debug"
# Desktop presets embed their PCK in the executable. Remove artifacts from
# older split-PCK exports so local builds and updater archives cannot
# accidentally keep shipping a stale companion file.
rm -f -- \
	"${build_dir}/KyttusLab-Linux-Debug.pck" \
	"${build_dir}/KyttusLab-Windows-Debug.pck" \
	"${build_dir}/KyttusLab-Windows-Legacy-Debug.pck" \
	"${build_dir}/KyttusLab-Windows-SteamVR-Debug.pck" \
	"${build_dir}/KyttusLab-iOS-Debug.pck" \
	"${build_dir}/Kyttu's Lab.command"
node "${project_dir}/tools/build/generate_build_revision.mjs"

"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Linux Debug Tools"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Windows Debug Tools"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Windows Legacy Debug"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "macOS Debug Tools"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Web Debug Tools"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Windows SteamVR Debug"

if unzip -Z1 "${build_dir}/KyttusLab-macOS-Debug.zip" | grep -qE '\.command$'; then
	printf 'The macOS export unexpectedly contains a .command launcher.\n' >&2
	exit 1
fi

(
	cd "${build_dir}"
	zip -FS KyttusLab-Linux-Debug.zip KyttusLab-Linux-Debug.x86_64
	zip -FS KyttusLab-Windows-Debug.zip KyttusLab-Windows-Debug.exe
	zip -FS KyttusLab-Windows-Legacy-Debug.zip KyttusLab-Windows-Legacy-Debug.exe
	zip -FS KyttusLab-Windows-SteamVR-Debug.zip KyttusLab-Windows-SteamVR-Debug.exe
	zip -FS -r KyttusLab-Web-Debug.zip KyttusLab-Web-Debug -x '*.import'
	unzip -o KyttusLab-macOS-Debug.zip -d .
)

if [[ "${1:-}" == "--quest" ]]; then
	"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Meta Quest OpenXR Debug"
fi

node "${project_dir}/tools/build/generate_update_manifest.mjs"

printf 'Test builds are ready in %s\n' "${build_dir}"
