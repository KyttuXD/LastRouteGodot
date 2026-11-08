extends RefCounted

## The app is "KYTTU: Last Route Godot Edition" (Night Watch lives in it too). Renaming config/name moves
## Godot's default user data folder, which would orphan accounts, settings, run saves and per-server sessions, so the
## project pins the CURRENT folder name (config/custom_user_dir_name). This keeps both true, and keeps the bundle id.

const DISPLAY_NAME := "KYTTU: Last Route Godot Edition"
const OLD_DATA_FOLDER := "KYTTU- The Last Route"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_expect(String(ProjectSettings.get_setting("application/config/name", "")) == DISPLAY_NAME,
		"application/config/name is not %s" % DISPLAY_NAME)
	_expect(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)),
		"use_custom_user_dir is off: the rename would move the user data folder")
	var custom := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	_expect(custom.ends_with(OLD_DATA_FOLDER), "custom_user_dir_name %s does not end with the old data folder %s" % [custom, OLD_DATA_FOLDER])
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var data_dir := OS.get_user_data_dir()
		_expect(data_dir.get_file() == OLD_DATA_FOLDER, "user data dir is %s, expected a folder named %s" % [data_dir, OLD_DATA_FOLDER])
		_expect(data_dir.to_lower().contains("app_userdata"), "user data dir %s left Godot's app_userdata location" % data_dir)
	# the files the game keeps in user:// resolve and round-trip from there
	var probe := "user://app_name_probe.tmp"
	var file := FileAccess.open(probe, FileAccess.WRITE)
	_expect(file != null, "user:// is not writable")
	if file != null:
		file.store_string("ok")
		file.close()
		_expect(FileAccess.get_file_as_string(probe) == "ok", "user:// round trip failed")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))
	# export presets: display name on every preset, bundle id unchanged, artifact names renamed
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	_expect(presets.contains('application/bundle_identifier="org.kyttuslab.lastroute"'), "the bundle identifier changed")
	_expect(not presets.contains("LastRoute-"), "export presets still write LastRoute-* artifacts")
	_expect(not presets.contains("KYTTU: The Last Route"), "export presets still carry the old display name")
	for script in ["export_beta.sh", "export_test_multiplayer.sh", "export_test_builds.sh"]:
		if not FileAccess.file_exists("res://tools/build/%s" % script):
			continue
		_expect(not FileAccess.get_file_as_string("res://tools/build/%s" % script).contains("LastRoute-"), "%s still names LastRoute-* artifacts" % script)
	if _failures == 0:
		print("  app_name  %s, user data stays in %s, bundle id and artifacts consistent" % [DISPLAY_NAME, OLD_DATA_FOLDER])
	return _failures
