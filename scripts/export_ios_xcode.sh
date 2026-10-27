#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${project_dir}/builds"
revision_file="${project_dir}/build_revision.json"

if [[ "$(uname -s)" != "Darwin" ]]; then
	printf 'iOS export requires macOS with Xcode installed.\n' >&2
	exit 1
fi

if command -v godot4 >/dev/null 2>&1; then
	godot_command=(godot4)
elif command -v godot >/dev/null 2>&1; then
	godot_command=(godot)
else
	printf 'Godot 4 was not found. Install Godot and its iOS export templates.\n' >&2
	exit 1
fi

team_id="$(awk '
	/name="iOS Debug Xcode"/ { preset = 1 }
	preset && /application\/app_store_team_id=/ {
		value = $0
		sub(/^[^=]*="/, "", value)
		sub(/"$/, "", value)
		print value
		exit
	}
' "${project_dir}/export_presets.cfg")"
if [[ ! "${team_id}" =~ ^[A-Za-z0-9]{10}$ ]]; then
	printf '%s\n' \
		'Set Application > App Store Team ID in the iOS Debug Xcode export preset first.' >&2
	exit 1
fi

cleanup_revision() {
	rm -f -- "${revision_file}"
}
trap cleanup_revision EXIT

mkdir -p "${build_dir}"
rm -f -- "${build_dir}/KyttusLab-iOS-Debug.zip" \
	"${build_dir}/KyttusLab-iOS-Debug.pck"
node "${project_dir}/scripts/generate_build_revision.mjs"
"${godot_command[@]}" --headless --path "${project_dir}" \
	--export-debug "iOS Debug Xcode" "${build_dir}/KyttusLab-iOS-Debug.zip"

unzip -tq "${build_dir}/KyttusLab-iOS-Debug.zip"
printf 'iOS Xcode project is ready at %s\n' \
	"${build_dir}/KyttusLab-iOS-Debug.zip"
