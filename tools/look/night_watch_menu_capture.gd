extends Node

## Night Watch menu screenshots, one set per window size (1280x720 and 1920x1080):
##   godot --path . res://tools/look/night_watch_menu_capture.tscn -- OUT_DIR
## writes <size>_title.png, _board.png, _board_dead_air.png, _settings.png, _account.png, _credits.png, _custom.png and _pause.png.

func _shot(path: String, frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	NightWatchSave.path = "user://night_watch_capture.cfg"
	NightWatchSave.reset()
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_window().size = size
		await get_tree().process_frame
		var tag := "%dx%d" % [size.x, size.y]
		var menu := (load("res://scenes/night_watch_menu.tscn") as PackedScene).instantiate() as NightWatchMenu
		add_child(menu)
		await _shot("%s/%s_title.png" % [out, tag])
		menu.show_screen("board")
		await _shot("%s/%s_board.png" % [out, tag])
		menu.select_mode(2)
		await _shot("%s/%s_board_dead_air.png" % [out, tag])
		menu.show_screen("settings")
		await _shot("%s/%s_settings.png" % [out, tag])
		menu.show_screen("account")
		await _shot("%s/%s_account.png" % [out, tag])
		menu.show_screen("credits")
		await _shot("%s/%s_credits.png" % [out, tag])
		for m in ["classic"]:
			for n in range(1, 6):
				NightWatchSave.record_level_clear(m, n)
		menu.show_screen("custom")
		await _shot("%s/%s_custom.png" % [out, tag])
		menu.queue_free()
		await get_tree().process_frame
		var hud := NightWatchHud.new()
		add_child(hud)
		await get_tree().process_frame
		hud.show_pause(true)
		await _shot("%s/%s_pause.png" % [out, tag])
		hud.queue_free()
		NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
