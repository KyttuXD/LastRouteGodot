extends Node

## The Night Watch admin menu, one capture per section tab, for Classic (and Night 7) at 1280x720 and 1920x1080:
##   godot --path . res://dev/look/night_watch_admin_capture.tscn -- OUT_DIR

func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	Build.capture_rig = true
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_window().size = size
		await get_tree().process_frame
		for level in [3, 7]:
			NightWatchSession.start_mode("classic", level, {}, 77)
			var game := (load("res://game/night_watch/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
			game.manual_clock = true
			add_child(game)
			await get_tree().process_frame
			await get_tree().process_frame
			if game.admin_menu == null:
				print("no admin menu")
				continue
			game.admin_menu.call("_set_open", true)
			var tabs := game.admin_menu.get("_tabs") as TabBar
			for i in tabs.tab_count:
				tabs.current_tab = i
				game.admin_menu.call("_show_page", i)
				await _shot("%s/admin_classic_n%d_%dx%d_%d_%s.png" % [out, level, size.x, size.y, i, tabs.get_tab_title(i).replace(" ", "_")], 4)
			game.queue_free()
			await get_tree().process_frame
	get_tree().quit()
