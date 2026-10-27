extends Node

## The admin menu of Masked Hours, Salvage Run and Mixed Shift, one capture per section tab at 1280x720 (docs/night_watch_admin/admin_<mode>_<tab>.png).
##   godot --path . res://tools/look/night_watch_admin_modes_capture.tscn -- OUT_DIR

func _shot(path: String, frames := 5) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	Build.capture_rig = true
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	for mode in [["mask", 4, "res://scenes/night_watch_mask.tscn"], ["dayshift", 4, "res://scenes/night_watch_dayshift.tscn"], ["mixed", 5, "res://scenes/night_watch_mixed.tscn"]]:
		NightWatchSession.start_mode(String(mode[0]), int(mode[1]), {}, 77)
		var game := (load(String(mode[2])) as PackedScene).instantiate() as Node
		game.set("manual_clock", true)
		add_child(game)
		await get_tree().process_frame
		await get_tree().process_frame
		if String(mode[0]) == "dayshift":
			game.call("start_shift", [])
			await get_tree().process_frame
		var menu := game.get("admin_menu") as AdminMenu
		if menu == null:
			print("no admin menu for ", mode[0])
			continue
		menu.call("_set_open", true)
		var tabs := menu.get("_tabs") as TabBar
		for i in tabs.tab_count:
			tabs.current_tab = i
			menu.call("_show_page", i)
			await _shot("%s/admin_%s_%d_%s.png" % [out, mode[0], i, tabs.get_tab_title(i).replace(" ", "_")])
		game.queue_free()
		await get_tree().process_frame
	get_tree().quit()
