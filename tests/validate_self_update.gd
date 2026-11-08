extends RefCounted

## Desktop (and mobile) self-update: the channel each platform asks for, the update rule (different commit AND higher build
## number), the manifest trust rules, the sha256 check, and the staged swap done by the real helper script (on macOS/Linux
## the shell helper, on Windows the PowerShell helper): new files in, previous build kept in .lastroute-backup-previous, the
## new launch target started.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- self_update

var _failures := 0
const A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _features(names: Array) -> Callable:
	return func(name: String) -> bool: return names.has(name)


func _check_channel() -> void:
	_expect(UpdateManager.platform_key_for(_features(["macos"])) == "macos", "macOS asks for the wrong platform")
	_expect(UpdateManager.platform_key_for(_features(["windows"])) == "windows", "Windows asks for the wrong platform")
	_expect(UpdateManager.platform_key_for(_features(["windows", "legacy"])) == "windows_legacy", "legacy Windows")
	_expect(UpdateManager.platform_key_for(_features(["android", "quest"])) == "quest", "Quest")
	_expect(UpdateManager.platform_key_for(_features(["android"])) == "phone", "phone")
	_expect(UpdateManager.update_manifest_url().contains("/api/updates/%s/" % Build.update_channel()), "manifest URL misses the channel")


func _check_compare() -> void:
	_expect(UpdateManager.mobile_update_needed(B, A, 12, 11), "a newer commit with a higher build was not offered")
	_expect(not UpdateManager.mobile_update_needed(B, A, 11, 11), "an equal build number was offered")
	_expect(not UpdateManager.mobile_update_needed(B, A, 10, 11), "an older build was offered")
	_expect(not UpdateManager.mobile_update_needed(A, A, 99, 11), "the same commit was offered")
	_expect(not UpdateManager.mobile_update_needed("nothex!", A, 99, 11), "an invalid revision was offered")


func _check_manifest() -> void:
	var sha := "e".repeat(64)
	var ok := UpdateManager.parse_manifest(JSON.stringify({"update": {"version": "0.0.1.0", "revision": B.to_upper(), "build": 12,
		"url": "/api/updates/files/x.zip", "sha256": sha.to_upper()}}), "https://lr.example", false)
	_expect(not ok.has("error") and ok["url"] == "https://lr.example/api/updates/files/x.zip" and ok["revision"] == B
		and ok["sha256"] == sha and int(ok["build"]) == 12, "a good manifest was not accepted as expected: %s" % ok)
	var plain := UpdateManager.parse_manifest(JSON.stringify({"update": {"url": "http://evil.example/x.zip", "sha256": sha}}), "https://lr.example", false)
	_expect(plain.has("error"), "a plain-http download from another host was trusted")
	var bad_sha := UpdateManager.parse_manifest(JSON.stringify({"update": {"url": "https://x/x.zip", "sha256": "1234"}}), "https://lr.example", false)
	_expect(bad_sha.has("error"), "a manifest without a valid sha256 was trusted")


func _check_checksum() -> void:
	var path := "user://self_update_check.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("abc")
	file.close()
	_expect(FileAccess.get_sha256(path) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
		"sha256 of 'abc' is wrong: the download check cannot be trusted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_layout() -> void:
	_expect(UpdateManager._mac_bundle_path("/Apps/Kyttus Lab.app/Contents/MacOS/Kyttus Lab") == "/Apps/Kyttus Lab.app", "mac bundle path")
	_expect(UpdateManager._previous_install_backup_path("macos", "/Apps/K.app/Contents/MacOS/K") == "/Apps/.lastroute-backup-previous", "mac backup path")
	_expect(UpdateManager._previous_install_backup_path("windows", "C:/Games/K/K.exe") == "C:/Games/K/.lastroute-backup-previous", "windows backup path")
	_expect(UpdateManager._safe_archive_entry("Kyttus Lab.app/Contents/Info.plist") and not UpdateManager._safe_archive_entry("../evil")
		and not UpdateManager._safe_archive_entry("/abs"), "archive entry safety")


## The real helper on this OS: stage -> install, previous build kept, new launch target started.
func _check_swap() -> void:
	var root := OS.get_user_data_dir().path_join("self_update_swap")
	_wipe(root)
	var stage := root.path_join("stage")
	var install := root.path_join("install")
	DirAccess.make_dir_recursive_absolute(stage)
	DirAccess.make_dir_recursive_absolute(install)
	var windows := OS.has_feature("windows")
	var launch := "Game.cmd" if windows else "game.sh"
	var marker := root.path_join("launched.txt")
	_write(install.path_join("data.pck"), "old")
	_write(install.path_join(launch), "old launcher")
	_write(stage.path_join("data.pck"), "new")
	if windows:
		_write(stage.path_join(launch), "@echo started %%1 %%2> \"%s\"\r\n" % marker.replace("/", "\\"))
	else:
		_write(stage.path_join(launch), "#!/bin/sh\necho \"started $1 $2\" > \"%s\"\n" % marker)
	var output := []
	var code := 0
	if windows:
		var helper := root.path_join("apply-update.ps1")
		_write(helper, UpdateManager.WINDOWS_HELPER)
		code = OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper,
			"-Stage", stage, "-Install", install, "-Launch", launch, "-GamePid", "999999", "-Revision", B], output, true)
	else:
		var helper := root.path_join("apply-update.sh")
		_write(helper, UpdateManager.UNIX_HELPER)
		code = OS.execute("/bin/sh", [helper, stage, install, launch, "999999", B, "linux"], output, true)
	for _i in 50:
		if FileAccess.file_exists(marker):
			break
		OS.delay_msec(100)
	_expect(code == 0, "the update helper failed (%d): %s" % [code, output])
	_expect(_read(install.path_join("data.pck")) == "new", "the new build was not swapped in")
	_expect(_read(install.path_join(".lastroute-backup-previous/data.pck")) == "old", "the previous build was not kept for rollback")
	_expect(FileAccess.file_exists(marker) and (_read(marker).contains("updated-from") or _read(marker).contains(B)),
		"the new build was not relaunched (marker: '%s')" % _read(marker))
	# apply on quit: the same swap without a relaunch
	_write(stage.path_join("data.pck"), "newer")
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(marker)
	if windows:
		var helper2 := root.path_join("apply-update.ps1")
		OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper2,
			"-Stage", stage, "-Install", install, "-Launch", launch, "-GamePid", "999999", "-Revision", B, "-Relaunch", "0"], output, true)
	else:
		OS.execute("/bin/sh", [root.path_join("apply-update.sh"), stage, install, launch, "999999", B, "linux", "0"], output, true)
	OS.delay_msec(800)
	_expect(_read(install.path_join("data.pck")) == "newer", "the quit-time swap did not install the update")
	_expect(not FileAccess.file_exists(marker), "the quit-time swap relaunched the game")
	_wipe(root)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	if OS.has_feature("windows"):
		OS.execute("cmd.exe", ["/c", "rmdir", "/s", "/q", path.replace("/", "\\")])
	else:
		OS.execute("/bin/rm", ["-rf", path])


func run(_host: Node) -> int:
	_check_channel()
	_check_compare()
	_check_manifest()
	_check_checksum()
	_check_layout()
	_check_swap()
	if _failures == 0:
		print("  update    channel per platform, newer-commit-and-build rule, manifest trust, sha256, staged swap with rollback copy and relaunch (%s)" % OS.get_name())
	return _failures
