extends Node

## Captures the active-room player list (pause menu PLAYERS page, as an admin and as a player), the hold-O overlay and the admin pulse on
## the minimap / full map into captures/player_list_*.png.
##   godot --path . res://tools/look/player_list_capture.tscn

func _rows(admin: bool) -> Array:
	var now := Time.get_ticks_usec()
	var roster := [{"id": 1, "name": "KYTTU", "host": true, "you": false}, {"id": 2, "name": "ANA", "host": false, "you": true},
		{"id": 3, "name": "BO", "host": false, "you": false}, {"id": 4, "name": "CY", "host": false, "you": false},
		{"id": 5, "name": "DI", "host": false, "you": false}]
	var states := {1: {"depth": 2, "received_usec": now}, 3: {"depth": 0, "received_usec": now, "game_over": true},
		4: {"depth": 1, "received_usec": now, "spectating": true, "game_over": true}, 5: {"depth": 0, "received_usec": now - 20_000_000}}
	return RoomPlayerList.build(roster, states, {"depth": 0}, {1: 0, 3: 48, 4: 130}, {3: true}, admin, now)


func _shot(name: String) -> void:
	for _i in 8:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	get_tree().root.get_texture().get_image().save_png("res://captures/player_list_%s.png" % name)


func _ready() -> void:
	var root := get_tree().root
	root.size = Vector2i(960, 540)
	var pause := PauseMenu.new()
	pause.players_admin = func() -> bool: return true
	pause.players_source = func() -> Array: return _rows(true)
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	(pause.find_child("PauseTab_players", true, false) as Button).pressed.emit()
	await _shot("pause_admin")
	pause.players_admin = func() -> bool: return false
	pause.players_source = func() -> Array: return _rows(false)
	pause._refresh_players()
	await _shot("pause_player")
	pause.close()
	pause.queue_free()
	var overlay := PlayerListPanel.new()
	overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.offset_top = 30.0
	overlay.custom_minimum_size = Vector2(300, 60)
	add_child(overlay)
	overlay.set_rows(_rows(false))
	await _shot("hold_overlay")
	overlay.queue_free()
	var world := StreamedRouteGenerator.new("PULSE")
	var chunks := {}
	for z in range(-1, 2):
		for x in range(-1, 2):
			chunks[Vector3i(x, 0, z)] = world.chunk(Vector3i(x, 0, z))
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as HUD
	add_child(hud)
	await get_tree().process_frame
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var centre := Vector2(size * .5, size * .5)
	hud.update_streamed_minimap(chunks, 0, size, centre, Vector2.DOWN, [], [])
	hud.update_streamed_map(chunks, 0, size, centre, Vector2.DOWN, [], [])
	var until := Time.get_ticks_msec() + 60000
	var marks := [{"at": centre + Vector2(9, -5), "level": 0, "until_msec": until, "name": "BO"},
		{"at": centre + Vector2(300, 0), "level": 0, "until_msec": until, "name": "CY"}]
	hud.minimap.set_pulses(marks)
	hud.plan.set_pulses(marks)
	hud.set_map_open(true)
	await _shot("pulse_maps")
	get_tree().quit()
