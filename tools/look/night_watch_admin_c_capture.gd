extends Node

## The admin menu of The Descent and Open Air, one capture per section tab at 1280x720 (docs/night_watch_admin/):
##   godot --path . res://tools/look/night_watch_admin_c_capture.tscn -- OUT_DIR
## writes admin_descent_<tab>.png and admin_openair_<rooftop|busstop|campfire>_<tab>.png.

func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _tabs(game: Node, prefix: String, out: String) -> void:
	game.admin_menu.call("_set_open", true)
	var tabs := game.admin_menu.get("_tabs") as TabBar
	for i in tabs.tab_count:
		tabs.current_tab = i
		game.admin_menu.call("_show_page", i)
		await _shot("%s/%s_%d_%s.png" % [out, prefix, i, tabs.get_tab_title(i).replace(" ", "_").replace("/", "")], 4)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	Build.capture_rig = true
	NightWatchSave.path = "user://night_watch_admin_c_capture.cfg"
	NightWatchSave.reset()
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	NightWatchSession.start_mode("descent", 4, {}, 77)
	var lift := (load("res://scenes/night_watch_descent.tscn") as PackedScene).instantiate() as NightWatchDescentGame
	lift.manual_clock = true
	add_child(lift)
	await get_tree().process_frame
	await get_tree().process_frame
	lift.advance_ms(NightWatchDescentLogic.RIDE_MS + 10.0)
	lift.admin_set_closeness(55.0)
	if lift.admin_menu == null:
		print("no admin menu")
	else:
		await _tabs(lift, "admin_descent", out)
	lift.queue_free()
	await get_tree().process_frame
	for row in [[1, "rooftop"], [2, "busstop"], [3, "campfire"]]:
		NightWatchSession.start_mode("extra", int(row[0]), {}, 77)
		var shift := (load("res://scenes/night_watch_extra.tscn") as PackedScene).instantiate() as NightWatchOpenAirGame
		shift.manual_clock = true
		add_child(shift)
		await get_tree().process_frame
		await get_tree().process_frame
		shift.advance_ms(2000.0)
		if shift.admin_menu == null:
			print("no admin menu")
		else:
			await _tabs(shift, "admin_openair_%s" % row[1], out)
		shift.queue_free()
		await get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
