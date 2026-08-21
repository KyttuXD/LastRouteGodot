extends Node

## Mandatory debug updates are downloaded from the trusted primary backend,
## checked against the published SHA-256, and unpacked under user://. Native
## desktop builds keep this process on an in-progress screen until that staged
## tree is ready, then a small helper replaces the install after exit. A
## running Windows executable cannot replace itself, and treating every
## desktop the same keeps the update hand-off predictable. Web refreshes its
## hosted build; Android/Quest opens the verified APK in the system installer
## because Android requires the player to approve package replacement.

const UPDATE_PROGRESS_SCENE := "res://scenes/update_progress.tscn"

signal update_available(update: Dictionary)
signal status_changed(message: String)
signal check_finished(success: bool, update_needed: bool)
signal download_progress(received_bytes: int, total_bytes: int)
signal update_ready(path: String)

const UPDATE_ROOT := "user://updates"
const DOWNLOAD_PART := "pending-update.part"
const DEBUG_RECHECK_SECONDS := 10.0
const RELEASE_RECHECK_SECONDS := 60.0
const MANIFEST_TIMEOUT_SECONDS := 8.0
const UNIX_HELPER := """#!/bin/sh
set -u
stage=$1
install=$2
launch=$3
game_pid=$4
revision=$5
mode=$6
log=$(dirname "$stage")/apply-update.log
while kill -0 "$game_pid" 2>/dev/null; do sleep 1; done
incoming="$install/.lastroute-incoming-$revision"
backup="$install/.lastroute-backup-previous"
rm -rf -- "$incoming" "$backup"
if ! mkdir -p -- "$incoming" "$backup"; then
  printf '%s\n' "Could not create update folders in $install" > "$log"
  exit 1
fi
if ! cp -R -- "$stage"/. "$incoming"/; then
  printf '%s\n' "Could not stage the update in $install" > "$log"
  rm -rf -- "$incoming"
  exit 1
fi
failed=0
for item in "$incoming"/*; do
  [ -e "$item" ] || continue
  name=${item##*/}
  if [ -e "$install/$name" ] && ! mv -- "$install/$name" "$backup/$name"; then
    failed=1
    break
  fi
  if ! mv -- "$item" "$install/$name"; then
    failed=1
    break
  fi
done
if [ "$failed" -ne 0 ]; then
  cp -R -- "$backup"/. "$install"/ 2>/dev/null || true
  printf '%s\n' "Update installation failed; the previous build was restored." > "$log"
  rm -rf -- "$incoming"
  exit 1
fi
rm -rf -- "$incoming"
if [ "$mode" = "macos" ]; then
  chmod +x "$install/$launch/Contents/MacOS/"* 2>/dev/null || true
  open "$install/$launch"
else
  chmod +x "$install/$launch"
  "$install/$launch" --updated-from "$revision" >/dev/null 2>&1 &
fi
"""
const WINDOWS_HELPER := """param(
  [Parameter(Mandatory=$true)][string]$Stage,
  [Parameter(Mandatory=$true)][string]$Install,
  [Parameter(Mandatory=$true)][string]$Launch,
  [Parameter(Mandatory=$true)][int]$GamePid,
  [Parameter(Mandatory=$true)][string]$Revision
)
$ErrorActionPreference = 'Stop'
$Log = Join-Path (Split-Path $Stage -Parent) 'apply-update.log'
$Incoming = Join-Path $Install ".lastroute-incoming-$Revision"
$Backup = Join-Path $Install '.lastroute-backup-previous'
try {
  Wait-Process -Id $GamePid -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Incoming -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Backup -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $Incoming, $Backup -Force | Out-Null
  Get-ChildItem -LiteralPath $Stage -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Incoming -Recurse -Force
  }
  Get-ChildItem -LiteralPath $Incoming -Force | ForEach-Object {
    $Destination = Join-Path $Install $_.Name
    if (Test-Path -LiteralPath $Destination) {
      Move-Item -LiteralPath $Destination -Destination (Join-Path $Backup $_.Name) -Force
    }
    Move-Item -LiteralPath $_.FullName -Destination $Destination -Force
  }
  Remove-Item -LiteralPath $Incoming -Recurse -Force -ErrorAction SilentlyContinue
  Start-Process -FilePath (Join-Path $Install $Launch) -ArgumentList '--updated-from', $Revision
} catch {
  Get-ChildItem -LiteralPath $Backup -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Install -Recurse -Force
  }
  $_ | Out-String | Set-Content -LiteralPath $Log
  exit 1
}
"""

var available := {}
var check_complete := false
var check_succeeded := false
var update_required := false
var checking := false
var downloading := false
var ready_to_install := false
var installing := false
var downloaded_path := ""
var staged_path := ""
var status_message := ""
var offline_mode := false

var _manifest_request: HTTPRequest
var _download_request: HTTPRequest
var _recheck_timer: Timer
var _last_progress_percent := -1


func _ready() -> void:
	offline_mode = "--offline" in OS.get_cmdline_user_args()
	# A completed update leaves no useful player data behind in this directory.
	# Clear archives, extracted staging trees, partial downloads and installer
	# helpers from older revisions before beginning another check. Route saves,
	# settings and account credentials live outside UPDATE_ROOT and are never
	# considered by this cleanup.
	_cleanup_update_cache()
	_cleanup_previous_install_backup()
	_manifest_request = HTTPRequest.new()
	_manifest_request.name = "UpdateManifestRequest"
	_manifest_request.timeout = MANIFEST_TIMEOUT_SECONDS
	add_child(_manifest_request)
	_manifest_request.request_completed.connect(_on_manifest_response)
	_download_request = HTTPRequest.new()
	_download_request.name = "UpdatePackageRequest"
	_download_request.use_threads = true
	add_child(_download_request)
	_download_request.request_completed.connect(_on_download_response)
	set_process(false)
	# Apple requires executable updates to be delivered through TestFlight or
	# the App Store. Treat that channel as healthy instead of trapping an iOS
	# build behind the native self-updater's startup gate.
	if OS.has_feature("ios"):
		_finish_check(true, false, "APP STORE UPDATES")
		return
	if DisplayServer.get_name() != "headless" and not offline_mode:
		_recheck_timer = Timer.new()
		_recheck_timer.name = "UpdateRecheckTimer"
		_recheck_timer.wait_time = DEBUG_RECHECK_SECONDS \
				if Build.update_channel() == "debug" else RELEASE_RECHECK_SECONDS
		_recheck_timer.timeout.connect(_on_recheck_timeout)
		add_child(_recheck_timer)
		_recheck_timer.start()
		check.call_deferred()


func _on_recheck_timeout() -> void:
	# Preserve a discovered or staged package. The timer exists to refresh an
	# UP TO DATE result (and recover transient check failures), not reset an
	# update that is already downloading or waiting to install.
	if ready_to_install and _should_install_automatically():
		# Quest still opens its system installer from the background timer.
		# Desktop required/debug updates wait for the in-progress screen.
		install_update()
		return
	if checking or downloading or installing or not available.is_empty():
		return
	check()


func _process(_delta: float) -> void:
	if not downloading:
		set_process(false)
		return
	var received := _download_request.get_downloaded_bytes()
	var total := _download_request.get_body_size()
	download_progress.emit(received, total)
	if total <= 0:
		return
	var percent := clampi(int(float(received) / float(total) * 100.0), 0, 100)
	if percent != _last_progress_percent:
		_last_progress_percent = percent
		_set_status("DOWNLOADING UPDATE // %d%%" % percent)


func check() -> void:
	if OS.has_feature("ios"):
		_finish_check(true, false, "APP STORE UPDATES")
		return
	if offline_mode:
		_finish_check(false, false, "OFFLINE MODE")
		return
	if checking or downloading \
			or _manifest_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	check_complete = false
	check_succeeded = false
	update_required = false
	available = {}
	ready_to_install = false
	downloaded_path = ""
	staged_path = ""
	if not Backend.configured():
		_finish_check(false, false, "UPDATE CHECK UNAVAILABLE")
		return
	checking = true
	_set_status("CHECKING FOR UPDATES")
	var error := _manifest_request.request("%s/api/updates/%s/%s" % [
		Backend.base_url, Build.update_channel(), platform_key()],
		PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if error != OK:
		_finish_check(false, false, "UPDATE CHECK UNAVAILABLE")


func enable_offline_mode() -> void:
	offline_mode = true
	if _recheck_timer != null:
		_recheck_timer.stop()
	if _manifest_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_manifest_request.cancel_request()
	if _download_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_download_request.cancel_request()
	checking = false
	downloading = false
	installing = false
	available = {}
	ready_to_install = false
	check_complete = true
	check_succeeded = false
	_set_status("OFFLINE MODE")


func platform_key() -> String:
	if OS.has_feature("web"):
		return "web"
	if OS.has_feature("ios"):
		return "ios"
	if OS.has_feature("quest"):
		return "quest"
	if OS.has_feature("windows") and OS.has_feature("xr"):
		return "steamvr"
	if OS.has_feature("windows") and OS.has_feature("legacy"):
		return "windows_legacy"
	if OS.has_feature("macos"):
		return "macos"
	if OS.has_feature("windows"):
		return "windows"
	return "linux"


func _on_manifest_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_check(false, false, "UPDATE CHECK UNAVAILABLE")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("update") is Dictionary:
		_finish_check(false, false, "INVALID UPDATE RESPONSE")
		return
	var candidate: Dictionary = parsed["update"]
	var version := String(candidate.get("version", ""))
	var revision := String(candidate.get("revision", "")).strip_edges().to_lower()
	var url := String(candidate.get("url", ""))
	var sha256 := String(candidate.get("sha256", "")).strip_edges().to_lower()
	if url.begins_with("/api/"):
		url = "%s%s" % [Backend.base_url, url]
		candidate["url"] = url
	var trusted_transport := url.begins_with("https://") \
		or url.begins_with("%s/api/updates/files/" % Backend.base_url) \
		or (OS.is_debug_build() and (url.begins_with("http://127.0.0.1") \
			or url.begins_with("http://localhost")))
	if not trusted_transport or not _valid_sha256(sha256):
		_finish_check(false, false, "UNTRUSTED UPDATE RESPONSE")
		return
	# Source/editor sessions are never an installation target. Without this
	# guard a future version bump could try to replace the Godot editor itself.
	if Build.revision() == Build.SOURCE_REVISION:
		_finish_check(true, false, "SOURCE BUILD // UPDATE SKIPPED")
		return
	if not _update_needed(version, Build.VERSION, revision, Build.revision()):
		_finish_check(true, false, "UP TO DATE")
		return
	available = candidate.duplicate(true)
	update_required = bool(candidate.get("required", false))
	update_available.emit(available)
	var identity := revision.left(8) if not revision.is_empty() else version
	_finish_check(true, true, "UPDATE %s FOUND" % identity)
	download_update.call_deferred()


## Downloads immediately after discovery. Calling this again is also the
## retry path used by the menu after a network, checksum, or permission error.
func download_update(force_web_refresh := false) -> void:
	if available.is_empty() or downloading or installing:
		return
	if OS.has_feature("web"):
		_refresh_web_build(force_web_refresh)
		return
	var url := String(available.get("url", ""))
	if url.is_empty():
		_set_status("UPDATE DOWNLOAD UNAVAILABLE")
		return
	var revision := String(available.get("revision", "")).to_lower()
	var identity := revision if _valid_revision(revision) else String(available.get("version", ""))
	var extension := "apk" if platform_key() == "quest" else "zip"
	var safe_identity := identity.replace(".", "-")
	if safe_identity.is_empty():
		safe_identity = "latest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATE_ROOT))
	downloaded_path = "%s/%s-%s.%s" % [UPDATE_ROOT, platform_key(), safe_identity, extension]
	# Preserve an already verified package for this exact revision, but evict
	# every older platform/revision archive and abandoned staging directory.
	_cleanup_update_cache([downloaded_path])
	var expected_sha := String(available.get("sha256", "")).to_lower()
	if FileAccess.file_exists(downloaded_path) \
			and FileAccess.get_sha256(downloaded_path).to_lower() == expected_sha:
		_prepare_verified_download()
		return
	_remove_file(downloaded_path)
	var partial_path := "%s/%s" % [UPDATE_ROOT, DOWNLOAD_PART]
	_remove_file(partial_path)
	_download_request.download_file = partial_path
	downloading = true
	ready_to_install = false
	_last_progress_percent = -1
	set_process(true)
	_set_status("DOWNLOADING UPDATE // 0%")
	var error := _download_request.request(url,
		PackedStringArray(["Accept: application/octet-stream"]), HTTPClient.METHOD_GET)
	if error != OK:
		_download_failed("UPDATE DOWNLOAD FAILED")


func _on_download_response(result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	downloading = false
	set_process(false)
	_download_request.download_file = ""
	var partial_path := "%s/%s" % [UPDATE_ROOT, DOWNLOAD_PART]
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 \
			or not FileAccess.file_exists(partial_path):
		_remove_file(partial_path)
		_set_status("UPDATE DOWNLOAD FAILED // RETRY")
		return
	var expected_sha := String(available.get("sha256", "")).to_lower()
	_set_status("VERIFYING UPDATE")
	await get_tree().process_frame
	if FileAccess.get_sha256(partial_path).to_lower() != expected_sha:
		_remove_file(partial_path)
		_set_status("UPDATE VERIFICATION FAILED // RETRY")
		return
	_remove_file(downloaded_path)
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(partial_path),
		ProjectSettings.globalize_path(downloaded_path))
	if rename_error != OK:
		_remove_file(partial_path)
		_set_status("COULD NOT STORE UPDATE // RETRY")
		return
	_prepare_verified_download()


func _prepare_verified_download() -> void:
	if platform_key() == "quest":
		ready_to_install = true
		update_ready.emit(downloaded_path)
		if _should_install_automatically():
			_set_status("UPDATE READY // OPENING QUEST INSTALLER")
			install_update.call_deferred()
		else:
			_set_status("UPDATE READY // INSTALL ON QUEST")
		return
	_set_status("UNPACKING UPDATE")
	await get_tree().process_frame
	var revision := String(available.get("revision", "")).to_lower()
	var identity := revision.left(12) if _valid_revision(revision) else "latest"
	staged_path = "%s/staged-%s-%s" % [UPDATE_ROOT, platform_key(), identity]
	_remove_tree(staged_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staged_path))
	var extract_error := _extract_archive(downloaded_path, staged_path)
	if not extract_error.is_empty():
		_remove_tree(staged_path)
		_set_status(extract_error)
		return
	# Desktop installation reads exclusively from the extracted staging tree.
	# Keeping the source ZIP as well only doubles the disk usage.
	_remove_file(downloaded_path)
	downloaded_path = ""
	var layout := _installation_layout(platform_key(), OS.get_executable_path(), staged_path)
	if layout.is_empty():
		_remove_tree(staged_path)
		_set_status("UPDATE PACKAGE DOES NOT MATCH THIS PLATFORM")
		return
	ready_to_install = true
	update_ready.emit(staged_path)
	if _should_install_automatically():
		_set_status("UPDATE READY // RESTARTING")
		install_update.call_deferred()
	elif _gameplay_active():
		_set_status("UPDATE READY // APPLIES AFTER RUN")
	elif uses_in_progress_screen() and _required_or_debug_update():
		_set_status("UPDATE STAGED // OPENING UPDATE SCREEN")
	else:
		_set_status("UPDATE READY // INSTALL & RESTART")


## Starts an independent helper, then exits. Desktop required/debug updates
## only call this after the in-progress screen has staged the new build. The
## helper waits for this exact process ID before touching the current
## executable/PCK or macOS app bundle.
func install_update() -> void:
	if installing or not ready_to_install:
		return
	if platform_key() == "quest":
		var apk := ProjectSettings.globalize_path(downloaded_path)
		var open_error := OS.shell_open(apk)
		if open_error == OK:
			_set_status("APPROVE UPDATE IN THE QUEST INSTALLER")
		else:
			_set_status("COULD NOT OPEN QUEST INSTALLER // RETRY")
		return
	var layout := _installation_layout(platform_key(), OS.get_executable_path(), staged_path)
	if layout.is_empty():
		_set_status("UPDATE PACKAGE DOES NOT MATCH THIS PLATFORM")
		return
	var install_dir := String(layout["install_dir"])
	if not _directory_writable(install_dir):
		_set_status("UPDATE DOWNLOADED // GAME FOLDER IS READ-ONLY")
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(downloaded_path))
		return
	installing = true
	ready_to_install = false
	_set_status("INSTALLING UPDATE // RESTARTING")
	var helper_pid := -1
	var revision := String(available.get("revision", "")).to_lower()
	if platform_key() in ["windows", "windows_legacy", "steamvr"]:
		var helper := "%s/apply-update.ps1" % UPDATE_ROOT
		if not _write_text(helper, WINDOWS_HELPER):
			_install_launch_failed()
			return
		var powershell := OS.get_environment("SystemRoot").path_join(
			"System32/WindowsPowerShell/v1.0/powershell.exe")
		if not FileAccess.file_exists(powershell):
			powershell = "powershell.exe"
		helper_pid = OS.create_process(powershell, PackedStringArray([
			"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
			"-File", ProjectSettings.globalize_path(helper),
			"-Stage", ProjectSettings.globalize_path(staged_path),
			"-Install", install_dir,
			"-Launch", String(layout["launch"]),
			"-GamePid", str(OS.get_process_id()),
			"-Revision", revision]))
	else:
		var helper := "%s/apply-update.sh" % UPDATE_ROOT
		if not _write_text(helper, UNIX_HELPER):
			_install_launch_failed()
			return
		helper_pid = OS.create_process("/bin/sh", PackedStringArray([
			ProjectSettings.globalize_path(helper),
			ProjectSettings.globalize_path(staged_path),
			install_dir,
			String(layout["launch"]),
			str(OS.get_process_id()), revision,
			"macos" if platform_key() == "macos" else "linux"]))
	if helper_pid < 0:
		_install_launch_failed()
		return
	_quit_for_update.call_deferred()


func _quit_for_update() -> void:
	await get_tree().create_timer(0.35).timeout
	get_tree().quit()


func _install_launch_failed() -> void:
	installing = false
	ready_to_install = true
	_set_status("COULD NOT START UPDATE INSTALLER // RETRY")


func _download_failed(message: String) -> void:
	downloading = false
	set_process(false)
	_download_request.download_file = ""
	_remove_file("%s/%s" % [UPDATE_ROOT, DOWNLOAD_PART])
	_set_status(message)


func uses_in_progress_screen() -> bool:
	# Native desktop is the path whose helper must stop this process. Web and
	# Quest already stay inside an in-app installer or refresh.
	return platform_key() in ["linux", "windows", "windows_legacy", "steamvr",
		"macos"]


func _required_or_debug_update() -> bool:
	return update_required or Build.requires_update_gate()


func should_open_progress_screen() -> bool:
	if offline_mode or not uses_in_progress_screen() or not _required_or_debug_update():
		return false
	if _gameplay_active():
		return false
	return downloading or installing or ready_to_install \
		or not available.is_empty()


func _should_install_automatically() -> bool:
	# Downloading and unpacking are safe in the background; replacing the live
	# executable/PCK is not. Desktop required/debug updates stay on the
	# in-progress screen until that screen hands off. Quest still opens its
	# system installer once the player leaves a run.
	if uses_in_progress_screen():
		return false
	return _required_or_debug_update() and not _gameplay_active()


func _gameplay_active() -> bool:
	return get_tree() != null \
		and not get_tree().get_nodes_in_group("gameplay_session").is_empty()


func _refresh_web_build(force: bool) -> void:
	var revision := String(available.get("revision", "")).to_lower()
	if not _valid_revision(revision):
		revision = String(available.get("version", "")).replace("\"", "")
	var script := """
const revision = '%s';
const key = 'last-route-update-' + revision;
const force = %s;
if (!force && sessionStorage.getItem(key)) {
  false;
} else {
  sessionStorage.setItem(key, '1');
  const url = new URL(window.location.href);
  url.searchParams.set('lr_update', revision);
  window.location.replace(url.toString());
  true;
}
""" % [revision, "true" if force else "false"]
	var refreshing = JavaScriptBridge.eval(script, true)
	if refreshing:
		_set_status("REFRESHING WEB BUILD")
	else:
		_set_status("WEB UPDATE PENDING ON HOST // RETRY")


func _extract_archive(archive_path: String, destination: String) -> String:
	var reader := ZIPReader.new()
	var open_error := reader.open(archive_path)
	if open_error != OK:
		return "COULD NOT OPEN UPDATE PACKAGE"
	for entry in reader.get_files():
		if not _safe_archive_entry(entry):
			reader.close()
			return "UNSAFE UPDATE PACKAGE REJECTED"
		var output := destination.path_join(entry)
		if entry.ends_with("/"):
			if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
				reader.close()
				return "COULD NOT UNPACK UPDATE"
			continue
		if DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(output.get_base_dir())) != OK:
			reader.close()
			return "COULD NOT UNPACK UPDATE"
		var output_file := FileAccess.open(output, FileAccess.WRITE)
		if output_file == null:
			reader.close()
			return "COULD NOT UNPACK UPDATE"
		output_file.store_buffer(reader.read_file(entry))
		output_file.close()
	reader.close()
	return ""


static func _installation_layout(platform: String, executable_path: String,
		staging: String) -> Dictionary:
	var directory := DirAccess.open(staging)
	if directory == null:
		return {}
	var launch := ""
	if platform in ["windows", "windows_legacy", "steamvr"]:
		for file in directory.get_files():
			if file.get_extension().to_lower() == "exe":
				launch = file
				break
	elif platform == "linux":
		for file in directory.get_files():
			if file.get_extension().to_lower() in ["x86_64", "arm64"]:
				launch = file
				break
	elif platform == "macos":
		for folder in directory.get_directories():
			if folder.to_lower().ends_with(".app"):
				launch = folder
				break
		var current_app := _mac_bundle_path(executable_path)
		if launch.is_empty() or current_app.is_empty():
			return {}
		return {"install_dir": current_app.get_base_dir(), "launch": launch}
	if launch.is_empty():
		return {}
	return {"install_dir": executable_path.get_base_dir(), "launch": launch}


static func _mac_bundle_path(executable_path: String) -> String:
	var marker := ".app/Contents/MacOS/"
	var at := executable_path.find(marker)
	if at < 0:
		return ""
	return executable_path.left(at + 4)


static func _safe_archive_entry(entry: String) -> bool:
	if entry.is_empty() or entry.begins_with("/") or entry.begins_with("\\") \
			or entry.contains("\\"):
		return false
	var pieces := entry.split("/", false)
	if pieces.is_empty():
		return false
	for piece in pieces:
		if piece == "." or piece == ".." or piece.contains(":"):
			return false
	return true


static func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _newer(candidate: String, current: String) -> bool:
	var a := candidate.trim_prefix("v").split(".")
	var b := current.trim_prefix("v").split(".")
	for index in maxi(a.size(), b.size()):
		var av := int(a[index]) if index < a.size() else 0
		var bv := int(b[index]) if index < b.size() else 0
		if av != bv:
			return av > bv
	return false


static func _update_needed(candidate_version: String, current_version: String,
		candidate_revision: String, current_revision: String) -> bool:
	if _newer(candidate_version, current_version):
		return true
	if _newer(current_version, candidate_version):
		return false
	var candidate := candidate_revision.strip_edges().to_lower()
	var current := current_revision.strip_edges().to_lower()
	return _valid_revision(candidate) and _valid_revision(current) and candidate != current


static func _valid_revision(value: String) -> bool:
	if value.length() < 7 or value.length() > 40:
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _directory_writable(path: String) -> bool:
	var probe := path.path_join(".lastroute-update-write-test-%d" % Time.get_ticks_msec())
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("update")
	file.close()
	_remove_file(probe)
	return true


func _write_text(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.close()
	return true


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_tree(path: String) -> void:
	var global_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(global_path):
		return
	var directory := DirAccess.open(global_path)
	if directory == null:
		return
	directory.include_hidden = true
	for file in directory.get_files():
		DirAccess.remove_absolute(global_path.path_join(file))
	for folder in directory.get_directories():
		_remove_tree(global_path.path_join(folder))
	DirAccess.remove_absolute(global_path)


func _cleanup_update_cache(keep_paths: Array = []) -> void:
	var global_root := ProjectSettings.globalize_path(UPDATE_ROOT).simplify_path()
	if not DirAccess.dir_exists_absolute(global_root):
		return
	var keep := {}
	for path in keep_paths:
		var global_keep := ProjectSettings.globalize_path(String(path)).simplify_path()
		if global_keep.get_base_dir() == global_root:
			keep[global_keep] = true
	var directory := DirAccess.open(global_root)
	if directory == null:
		return
	directory.include_hidden = true
	for file in directory.get_files():
		var file_path := global_root.path_join(file).simplify_path()
		if not keep.has(file_path):
			DirAccess.remove_absolute(file_path)
	for folder in directory.get_directories():
		var folder_path := global_root.path_join(folder).simplify_path()
		if not keep.has(folder_path):
			_remove_tree(folder_path)


func _cleanup_previous_install_backup() -> void:
	if Build.revision() == Build.SOURCE_REVISION:
		return
	var backup := _previous_install_backup_path(platform_key(), OS.get_executable_path())
	if not backup.is_empty():
		_remove_tree(backup)


static func _previous_install_backup_path(platform: String, executable_path: String) -> String:
	if platform == "macos":
		var app := _mac_bundle_path(executable_path)
		return app.get_base_dir().path_join(".lastroute-backup-previous") \
			if not app.is_empty() else ""
	if platform in ["linux", "windows", "windows_legacy", "steamvr"]:
		return executable_path.get_base_dir().path_join(".lastroute-backup-previous")
	return ""


func _set_status(message: String) -> void:
	status_message = message
	status_changed.emit(message)


func _finish_check(success: bool, needs_update: bool, message: String) -> void:
	checking = false
	check_complete = true
	check_succeeded = success
	_set_status(message)
	check_finished.emit(success, needs_update)
