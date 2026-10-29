extends Node

## The death flow at several window sizes: the HUD as in play, the death moment alone (solo), the run card alone, and both at once (online: the moment plays while the card opens).
##   godot --path . res://tools/look/death_capture.tscn -- OUT_DIR [tag]
func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	var tag := args[1] if args.size() > 1 else "now"
	DirAccess.make_dir_recursive_absolute(out)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "DEATH-LOOK"
	Settings.short_death_scenes = false
	Settings.reduced_motion = true
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	add_child(route)
	for i in 20:
		await get_tree().process_frame
	var picked: Dictionary = {"text": "You ran so far down, and I was always one door behind you. Stay a while; the lights are kinder here.", "source": "hunter", "style": ""}
	var report := {"online": false, "host": true, "respawn": true, "title": "YOU DIED", "kicker": "RUNNER SIGNAL // LOST", "reason": "CAUGHT BY KATHY",
		"depth": 3, "score": 420, "relays": 1, "relay_target": 3, "coins": 12, "difficulty": "STANDARD", "seed": "DEATH-LOOK"}
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(480, 270), Vector2i(390, 844)]:
		get_window().size = size
		var key := "%dx%d" % [size.x, size.y]
		for i in 6:
			await get_tree().process_frame
		route.hud.show_message("YOU DIED // SPECTATOR MODE")
		await _shot("%s/%s_%s_0hud.png" % [out, tag, key])
		route._play_death_moment("KATHY", picked, "kathy")   # online it is not awaited: the card is asked to open while the line is up
		await _shot("%s/%s_%s_1moment.png" % [out, tag, key], 10)
		_open_card_when_ready(route, report)
		await _shot("%s/%s_%s_2both.png" % [out, tag, key], 10)
		route._death_moment.dismiss()
		await _shot("%s/%s_%s_3card.png" % [out, tag, key], 8)
		route.run_report.close()
		route.hud.call("set_death_flow", false) if route.hud.has_method("set_death_flow") else null
	get_tree().quit()


func _open_card_when_ready(route: Node, report: Dictionary) -> void:
	if route.has_method("_finish_death_moment"):
		await route._finish_death_moment()
		route.hud.set_death_flow(true)
	route.run_report.open(report)
