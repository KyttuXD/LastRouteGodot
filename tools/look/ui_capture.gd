extends Node

## Screenshot rig for menus: loads each scene in UI_SCENES (comma list of res://
## paths) at the project's 480x270 design size, waits, saves PNGs.
##
##   UI_SCENES=res://scenes/main_menu.tscn godot --path . res://tools/look/ui_capture.tscn -- OUTDIR TAG

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "/tmp"
	var tag := args[1] if args.size() > 1 else "ui"
	var scenes := OS.get_environment("UI_SCENES").split(",", false)
	var wait_frames := int(OS.get_environment("UI_WAIT")) if OS.get_environment("UI_WAIT") != "" else 40
	for path in scenes:
		var scene: Node = load(path).instantiate()
		add_child(scene)
		# overlays that need data or a call to appear: UI_OPEN=report|settings|pause
		match OS.get_environment("UI_OPEN"):
			"report":
				scene.open({"online": false, "depth": 7, "score": 1840, "relays": 2, "relay_target": 3,
					"coins": 12, "difficulty": "STANDARD", "seed": "ROOM-QTE9F-86B8"})
			"settings":
				scene.get_node("%SettingsOverlay").open()
			"pause":
				var pause := PauseMenu.new()
				scene.add_child(pause)
				pause.open()
		for i in wait_frames:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out_dir, tag, path.get_file().get_basename()])
		scene.queue_free()
		await get_tree().process_frame
	get_tree().quit()
