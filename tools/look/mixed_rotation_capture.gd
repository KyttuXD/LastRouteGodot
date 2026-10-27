extends Node

## Mixed Shift's rotation, three nights: the office, then the camera feed of the central room with a hunter in it, for three of the nine maps.
##   godot --path . res://tools/look/mixed_rotation_capture.tscn -- OUT_DIR
## writes night1_<skin>_office.png and night1_<skin>_feed.png (and the same for nights 2 and 3) into OUT_DIR.

func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	MixedSkin.reset()
	for night in 3:
		NightWatchSession.start_mode("mixed", 2, {}, 500 + night)
		var game := (load(NightWatchModeRegistry.scene_for("mixed")) as PackedScene).instantiate() as MixedGame
		game.manual_clock = true
		add_child(game)
		await get_tree().process_frame
		game.advance_ms(2000.0)
		var id := String(MixedSkin.skin(game.world.dress_set)["id"])
		var tag := "%s/night%d_%s" % [out, night + 1, id]
		await _shot(tag + "_office.png")
		game.admin_set_hour(2)
		game.sim.admin_add_threat("dovelle")
		game.admin_place_hunter("dovelle", "dining")
		game.open_monitor("dining")
		game.advance_ms(300.0)
		await _shot(tag + "_feed.png", 10)
		game.queue_free()
		await get_tree().process_frame
	get_tree().quit()
