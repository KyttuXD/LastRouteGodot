extends Node

## The admin menu of Dead Air, Bedtime and The Facility, one capture per section tab at 1280x720:
##   godot --path . res://dev/look/night_watch_admin_a_capture.tscn -- OUT_DIR

const MODES := {
	"lure": "res://game/night_watch/lure/night_watch_lure.tscn",
	"bedroom": "res://game/night_watch/bedroom/night_watch_bedroom.tscn",
	"story": "res://game/night_watch/story/night_watch_story.tscn",
}


func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	Build.capture_rig = true
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	for mode in MODES:
		NightWatchSession.start_mode(mode, 4, {}, 77)
		var game := (load(String(MODES[mode])) as PackedScene).instantiate()
		game.set("manual_clock", true)
		add_child(game)
		await get_tree().process_frame
		await get_tree().process_frame
		if game.get("admin_menu") == null:
			print("no admin menu for %s" % mode)
			continue
		game.admin_menu.call("_set_open", true)
		var tabs := game.admin_menu.get("_tabs") as TabBar
		for i in tabs.tab_count:
			tabs.current_tab = i
			game.admin_menu.call("_show_page", i)
			await _shot("%s/admin_%s_1280x720_%d_%s.png" % [out, mode, i, tabs.get_tab_title(i).replace(" ", "_")], 4)
		game.queue_free()
		await get_tree().process_frame
	get_tree().quit()
