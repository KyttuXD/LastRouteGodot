#!/usr/bin/env bash
# Builds the headless game a region agent runs (docs/SERVER_HOSTING.md): the existing "Linux Debug Tools" export
# (same version, same build revision as the player builds -- no new preset), placed with a manifest in
# builds/dedicated/. Copying it to a VPS is the deploy step, done by the coordinator.
set -eu
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${project_dir}/builds/dedicated"
revision_file="${project_dir}/build_revision.json"
trap 'rm -f -- "${revision_file}"' EXIT

godot="${GODOT_BIN:-$(command -v godot4 || command -v godot || true)}"
[ -n "${godot}" ] || { echo "Godot 4 was not found (set GODOT_BIN)" >&2; exit 1; }

node "${project_dir}/scripts/generate_build_revision.mjs"
mkdir -p "${out}"
"${godot}" --headless --path "${project_dir}" --export-debug "Linux Debug Tools"
cp "${project_dir}/builds/KyttusLab-Linux-Debug.x86_64" "${out}/LastRoute-Dedicated.x86_64"
chmod 0755 "${out}/LastRoute-Dedicated.x86_64"
revision="$(git -C "${project_dir}" rev-parse --short HEAD)"
sha="$(shasum -a 256 "${out}/LastRoute-Dedicated.x86_64" | cut -d' ' -f1)"
printf '{"revision":"%s","sha256":"%s","built":"%s"}\n' "${revision}" "${sha}" "$(date -u +%FT%TZ)" > "${out}/manifest.json"
echo "built ${out}/LastRoute-Dedicated.x86_64 (revision ${revision})"
echo "smoke test on the VPS: LastRoute-Dedicated.x86_64 --headless -- --dedicated-host AB2CD --idle-minutes 1"
