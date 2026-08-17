#!/usr/bin/env bash
set -eu

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

mkdir -p "${build_dir}/LastRoute-Web-Debug"
# Desktop presets embed their PCK in the executable. Remove artifacts from
# older split-PCK exports so local builds and updater archives cannot
# accidentally keep shipping a stale companion file.
rm -f -- \
	"${build_dir}/LastRoute-Linux-Debug.pck" \
	"${build_dir}/LastRoute-Windows-Debug.pck" \
	"${build_dir}/LastRoute-Windows-SteamVR-Debug.pck"
node "${project_dir}/scripts/generate_build_revision.mjs"

"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Linux Debug Tools"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Windows Debug Tools"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "macOS Debug Tools"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Web Debug Tools"
"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Windows SteamVR Debug"

(
	cd "${build_dir}"
	zip -FS LastRoute-Linux-Debug.zip LastRoute-Linux-Debug.x86_64
	zip -FS LastRoute-Windows-Debug.zip LastRoute-Windows-Debug.exe
	zip -FS LastRoute-Windows-SteamVR-Debug.zip LastRoute-Windows-SteamVR-Debug.exe
	zip -FS -r LastRoute-Web-Debug.zip LastRoute-Web-Debug -x '*.import'
	unzip -o LastRoute-macOS-Debug.zip -d .
)

if [[ "${1:-}" == "--quest" ]]; then
	"${godot_command[@]}" --headless --path "${project_dir}" --export-debug "Meta Quest OpenXR Debug"
fi

node "${project_dir}/scripts/generate_update_manifest.mjs"

printf 'Test builds are ready in %s\n' "${build_dir}"
