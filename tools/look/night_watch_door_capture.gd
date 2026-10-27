extends Node

## Door and hazard-stripe captures: both doors closed / half / open from the office, and from the corridor at 1.5 m and 4 m.
##   godot --path . res://tools/look/night_watch_door_capture.tscn -- OUT_DIR PREFIX
## writes PREFIX_<door>_<state>_office.png, PREFIX_<door>_closed_hall15.png, _hall4.png and PREFIX_desk.png (frame, desk edge, panel from inside).

func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	var prefix := args[1] if args.size() > 1 else "after"
	DirAccess.make_dir_recursive_absolute(out)
	NightWatchSession.start(1, 7)
	var game := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.advance_ms(500.0)
	game.hud.visible = false if "visible" in game.hud else true
	var office := game.office
	for door in ["doorL", "doorR"]:
		var side := -1.0 if door == "doorL" else 1.0
		var yaw := PI * 0.5 * (1.0 if door == "doorL" else -1.0)   # looking toward the door from the office
		for state in ["closed", "half", "open"]:
			var slab := office.slabs[door] as Node3D
			var y := NightWatchOffice.SLAB_CLOSED_Y if state == "closed" else (NightWatchOffice.SLAB_OPEN_Y if state == "open" else (NightWatchOffice.SLAB_CLOSED_Y + NightWatchOffice.SLAB_OPEN_Y) * 0.5)
			slab.position.y = y
			game.player.global_position = Vector3(side * 1.1, 0.0, 0.5)
			game.face_player(yaw, -0.05)
			await _shot("%s/%s_%s_%s_office.png" % [out, prefix, door, state])
			if state == "closed":
				game.player.global_position = Vector3(side * 2.2, 0.0, 0.3)
				game.face_player(yaw, 0.0)
				await _shot("%s/%s_%s_closed_close.png" % [out, prefix, door])
		game.set_light(door, true)
		game.advance_ms(20.0)
		(office.slabs[door] as Node3D).position.y = NightWatchOffice.SLAB_CLOSED_Y
		for dist in [1.5, 4.0]:
			game.player.global_position = Vector3(side * (NightWatchOffice.HALF_W + dist), 0.0, 0.0)
			game.face_player(-yaw, -0.03)
			await _shot("%s/%s_%s_closed_hall%s.png" % [out, prefix, door, str(dist).replace(".", "")])
		game.set_light(door, false)
	game.player.global_position = Vector3(0.0, 0.0, -0.2)
	game.face_player(PI * 0.5, -0.12)
	await _shot("%s/%s_desk.png" % [out, prefix])
	game.face_player(-PI * 0.5, -0.12)
	await _shot("%s/%s_deskR.png" % [out, prefix])
	get_tree().quit()
