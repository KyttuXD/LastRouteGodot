class_name RunProfile
extends RefCounted

## `--profile=NAME` (after `--`) gives one launched instance its own user:// files, so several instances on one machine
## (tools/build/run_multi.sh) keep separate logins and settings: `user://settings.cfg` -> `user://settings_NAME.cfg`.

static func name() -> String:
	for argument in OS.get_cmdline_user_args():
		if String(argument).begins_with("--profile="):
			var clean := ""
			for character in String(argument).trim_prefix("--profile="):
				if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_":
					clean += character
			return clean
	return ""


static func path(base: String) -> String:
	var profile := name()
	return base if profile.is_empty() else base.trim_suffix(".cfg") + "_" + profile + ".cfg"
