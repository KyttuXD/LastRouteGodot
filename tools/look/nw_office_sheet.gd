extends Node

## Every mode's office as the player first sees it, 960x540, one PNG per mode: the 3D side of the before/after against the 2D offices.
##   godot --path . res://tools/look/nw_office_sheet.tscn -- OUT_DIR [tag]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	var tag := args[1] if args.size() > 1 else "now"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(960, 540)
	NightWatchPalette.enabled = tag != "before"
	NightWatchSignature.enabled = tag != "before"
	var only := args[2].split(",") if args.size() > 2 else PackedStringArray()
	for mode_id in ["classic", "mask", "lure", "bedroom", "story", "descent", "dayshift", "extra", "mixed"]:
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
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, mode_id, tag])
		if game.has_method("face_player"):   # and the way the player came in from: the wall behind the spawn
			game.call("face_player", PI, -0.05)
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s_rear.png" % [out, mode_id, tag])
		game.queue_free()
		await get_tree().process_frame
	get_tree().quit()
