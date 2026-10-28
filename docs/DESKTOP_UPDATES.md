# Desktop self-update (macOS and Windows)

Same identity and rule as phones and the Quest (see [XR_ANDROID.md](XR_ANDROID.md), "Self-update"): the git commit is the build,
`build_revision.json` carries the commit and its build number (`git rev-list --count`). `version/name` stays `0.0.1.0`.

## Client (`UpdateManager`)

- macOS asks `/api/updates/<channel>/macos`, Windows `/windows` (`windows_legacy`, `steamvr` for those exports; `platform_key_for`).
- An update is offered when the published commit differs **and** its `build` is higher (`mobile_update_needed`, now used on every
  native platform). An entry without a build number is never offered.
- Download: staged to `user://updates`, sha256 checked against the manifest (HTTPS or the backend's own `/api/updates/files/`
  route only; plain localhost only in debug builds), then unpacked to a staging folder.
- Never silent: the update screen shows **INSTALL & RESTART** (and CONTINUE OFFLINE); nothing is replaced until it is pressed.
  The main menu shows "UPDATE READY // INSTALL & RESTART" outside the gate.
- Swap: a helper (shell on macOS, PowerShell on Windows) waits for the game to exit, copies the staged build beside the
  installed one, moves the old files (the whole `.app` on macOS; the exe/pck on Windows) into `.lastroute-backup-previous`
  next to the game, moves the new ones in, and relaunches. On any failure it restores the previous files.
- Rollback: the previous build stays in `.lastroute-backup-previous` until the next update replaces it. To roll back by hand,
  quit the game and move the files from that folder back over the current ones.
- Every exported build shows `VERSION 0.0.1.0 // BUILD <commit>` on the title screen.
- Debug-only end-to-end switch: `-- --update-smoke` checks at once (also headless), installs without the button and prints
  `UPDATE_SMOKE` lines. Release exports ignore it.

## Server (`backend/server.mjs`)

- `/api/updates/<channel>/<platform>` serves `version`, `revision`, `build`, `file` or `url`, `sha256`, `bytes`, `notes`,
  `required`. Every native platform's entry now needs a `revision` and a positive `build` or it is withheld (404); the web
  build still refreshes by revision only.
- Files come from `LASTROUTE_UPDATE_DIR` through `/api/updates/files/<name>` (or an absolute HTTPS `url`, e.g. a GitHub release
  asset). The manifest file is `LASTROUTE_UPDATE_MANIFEST` (`updates.debug.json`); the GitHub release sync fills both.

## Publishing a desktop update (exact steps)

On the Mac mini, from a clean checkout of the commit being published (`<checkout>`):

1. `cd <checkout> && node scripts/generate_build_revision.mjs` — stamps `build_revision.json` with the commit and build
   number (fails on a dirty tree).
2. Export: `godot --headless --path . --export-debug "macOS Debug Tools" builds/KyttusLab-macOS-Debug.zip` and
   `godot --headless --path . --export-debug "Windows Debug Tools" builds/win/KyttusLab.exe`, then
   `(cd builds/win && zip -qr ../KyttusLab-Windows-Debug.zip .)` (and `Windows Legacy Debug` -> `KyttusLab-Windows-Legacy-Debug.zip`
   if published).
3. `node scripts/generate_update_manifest.mjs` — writes `builds/updates.debug.json` with `revision`, `build`, `sha256`, `bytes`
   for every artifact present (phone/Quest APKs from the same commit go in the same folder; one release = one commit).
4. Upload the zips (and APKs) plus `updates.debug.json` to the GitHub `debug` release as today; the backend's release sync
   fetches them into `LASTROUTE_UPDATE_DIR` / `LASTROUTE_UPDATE_MANIFEST`.
5. Check: `curl https://<backend>/api/updates/debug/macos` and `/windows` return the entry with the new `build`.

Deploying the server change (build numbers required for desktop entries) is the coordinator's manual VPS 3 deploy: on the VPS
`deploy/deploy.sh` (dry run), then `deploy/deploy.sh --apply`; `--rollback --apply` returns to the previous release. Publish a
desktop build **with** a build number before or together with that deploy, or desktop clients see no update until one exists.

## Tests

- `self_update` suite: channel per platform, the newer-commit-and-build rule, manifest trust, sha256, and the real helper's swap
  on this OS (shell on macOS/Linux, PowerShell on Windows: new files in, previous kept, new build launched).
- `backend/server.test.mjs`: build carried for desktop, desktop entries without a build withheld.
- End to end: `tools/update_e2e/run_mac.sh` on the Mac mini (exports A and B, local backend, A updates itself to B and
  relaunches); `tools/update_e2e/export_windows.sh` on the mini then `tools/update_e2e/run_windows.ps1` on a Windows PC with the
  exported `win/` folder copied to `e2e\win`.
