extends Node

## Command line for the mod starter kit (ModKit). Use tools/modpack/modpack.sh, or directly:
##   godot --headless --path <game> res://tools/modpack/modpack.tscn -- init <pack_id> [parent dir]
##   godot --headless --path <game> res://tools/modpack/modpack.tscn -- validate <pack dir>
##   godot --headless --path <game> res://tools/modpack/modpack.tscn -- pack <pack dir>
## Paths are absolute (the wrapper resolves relative ones). init defaults to user://mods, where the game finds packs.
## Exit code 0 = OK, 1 = the pack has errors, 2 = usage.


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
			_quit(2, "usage: init <pack_id> [parent dir] | validate <pack dir> | pack <pack dir>")


func _quit(code: int, message: String = "") -> void:
	if not message.is_empty():
		print(message)
	get_tree().quit(code)
