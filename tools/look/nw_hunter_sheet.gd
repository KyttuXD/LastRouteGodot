extends Node

## Night Watch hunters in view, per mode: every hunter sent to its door (and the first camera room), seen from the spawn looking at each door and, in the monitor, a camera that shows one.
##   godot --path . res://tools/look/nw_hunter_sheet.tscn -- OUT_DIR [tag] [mode,mode]
func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	var tag := args[1] if args.size() > 1 else "now"
	var only := args[2].split(",") if args.size() > 2 else PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(960, 540)
	for mode_id in ["classic", "mask", "lure", "bedroom", "story", "dayshift", "mixed", "descent", "extra"]:
		if not only.is_empty() and not only.has(String(mode_id)):
			continue
		NightWatchSession.start_mode(String(mode_id), 2, {}, 5)
		var game := (load(NightWatchModeRegistry.scene_for(String(mode_id))) as PackedScene).instantiate()
		game.set("manual_clock", true)
		add_child(game)
		if game.has_method("start_shift"):
			game.call("start_shift", [])
		for i in 10:
			await get_tree().process_frame
		if game.has_method("advance_ms"):
			game.call("advance_ms", 300.0)
		if game.has_method("admin_all_to_doors"):
			game.call("admin_all_to_doors")
		elif game.has_method("admin_hunter_ids") and game.has_method("admin_place_hunter") and game.has_method("admin_places"):
			var places: Array = game.call("admin_places")
			var n := 0
			for id in game.call("admin_hunter_ids"):
				game.call("admin_place_hunter", String(id), String(places[(n % places.size()) if places.size() > 4 or n > 0 else places.size() - 1]))
				n += 1
		for i in 8:
			await get_tree().process_frame
		var n_shot := 0
		for yaw in [0.0, PI * 0.5, -PI * 0.5, PI]:
			if game.has_method("face_player"):
				game.call("face_player", yaw, -0.05)
			await _shot("%s/%s_%s_%d.png" % [out, mode_id, tag, n_shot], 4)
			n_shot += 1
		game.queue_free()
		await get_tree().process_frame
	get_tree().quit()
