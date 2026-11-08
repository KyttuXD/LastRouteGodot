extends Node

## Command line for the mod starter kit (ModKit). Use tools/modpack/modpack.sh, or directly:
##   godot --headless --path <game> res://tools/modpack/modpack.tscn -- init <pack_id> [parent dir]
##   godot --headless --path <game> res://tools/modpack/modpack.tscn -- validate <pack dir>
##   godot --headless --path <game> res://tools/modpack/modpack.tscn -- validate-examples <examples/mods dir>
##   godot --headless --path <game> res://tools/modpack/modpack.tscn -- pack <pack dir>
## Paths are absolute (the wrapper resolves relative ones). init defaults to user://mods, where the game finds packs.
## Exit code 0 = OK, 1 = the pack has errors, 2 = usage.
## `validate-examples` is what `tools/build/pack_smoke.sh examples` runs in CI: every immediate child with a pack.json,
## except folders whose names start with "_" (those fixtures are supposed to be refused).


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var command := args[0] if not args.is_empty() else ""
	match command:
		"init":
			if args.size() < 2:
				_quit(2, "usage: init <pack_id> [parent dir]")
				return
			var parent := args[2] if args.size() > 2 else ContentPacks.ROOT
			var made := ModKit.init_pack(args[1], parent)
			if not made["errors"].is_empty():
				_quit(1, "init failed: " + "; ".join(made["errors"]))
				return
			print("created %s" % ProjectSettings.globalize_path(made["dir"]))
			print("next: replace assets/water_cooler.glb, edit props/office.json and hunters/variant.json, then run")
			print("      validate %s" % ProjectSettings.globalize_path(made["dir"]))
			_quit(0)
		"validate":
			if args.size() < 2:
				_quit(2, "usage: validate <pack dir>")
				return
			var result := ModKit.validate(args[1])
			for message in result["warnings"]:
				print("WARNING %s" % message)
			for message in result["errors"]:
				print("ERROR   %s" % message)
			if result["errors"].is_empty():
				var summary: Dictionary = result["summary"]
				print("OK %s %s: %d files, %d bytes, %s, sha256 %s" % [summary["id"], summary["version"], summary["files"],
					summary["bytes"], summary["defs"], summary["sha256"]])
			_quit(0 if result["errors"].is_empty() else 1)
		"validate-examples":
			if args.size() < 2:
				_quit(2, "usage: validate-examples <examples/mods dir>")
				return
			var root := String(args[1]).trim_suffix("/")
			if not DirAccess.dir_exists_absolute(root):
				_quit(1, "cannot open %s" % root)
				return
			var names := DirAccess.get_directories_at(root)
			names.sort()
			var pack_count := 0
			var fail_count := 0
			for name in names:
				if String(name).begins_with("_") or String(name).begins_with("."):
					continue
				var dir := root.path_join(name)
				if not FileAccess.file_exists(dir.path_join("pack.json")):
					continue
				pack_count += 1
				var pack_result := ModKit.validate(dir)
				for message in pack_result["warnings"]:
					print("WARNING %s: %s" % [name, message])
				if not pack_result["errors"].is_empty():
					fail_count += 1
					for message in pack_result["errors"]:
						print("ERROR   %s: %s" % [name, message])
					continue
				var pack_summary: Dictionary = pack_result["summary"]
				print("OK %s %s: %d files, %d bytes, %s, sha256 %s" % [pack_summary["id"], pack_summary["version"],
					pack_summary["files"], pack_summary["bytes"], pack_summary["defs"], pack_summary["sha256"]])
			if pack_count == 0:
				_quit(1, "no example packs under %s" % root)
				return
			if fail_count > 0:
				_quit(1, "EXAMPLE PACKS FAIL // %d of %d" % [fail_count, pack_count])
				return
			_quit(0, "EXAMPLE PACKS OK // %d" % pack_count)
		"pack":
			if args.size() < 2:
				_quit(2, "usage: pack <pack dir>")
				return
			var checked := ModKit.validate(args[1])
			if not checked["errors"].is_empty():
				_quit(1, "not packed, run validate first:\n" + "\n".join(checked["errors"]))
				return
			var manifest := ModKit.manifest(args[1])
			print(JSON.stringify({"id": manifest["id"], "version": manifest["version"], "sha256": manifest["sha256"],
				"files": manifest["files"]}, "\t"))
			_quit(0)
		_:
			_quit(2, "usage: init <pack_id> [parent dir] | validate <pack dir> | validate-examples <examples/mods dir> | pack <pack dir>")


func _quit(code: int, message: String = "") -> void:
	if not message.is_empty():
		print(message)
	get_tree().quit(code)
