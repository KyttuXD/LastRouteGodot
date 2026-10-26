extends Node

## Screenshot rig for the reference-look pass. Loads the infinite route, teleports
## the runner to one room of each type and saves viewport PNGs.
##
##   godot --path . res://tools/look/capture.tscn -- OUTDIR TAG [SEED]
##
## Environment: CAP_ONLY=<substring of "region_roomtype">, CAP_MAX=<n rooms>,
## CAP_YAWS="0,90" (degrees), CAP_FPS=1 to print the frame time instead of
## shooting, CAP_LIST=1 to list the picks.

var _out_dir := ""
var _tag := "x"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else "/tmp"
	_tag = args[1] if args.size() > 1 else "x"
	RoomState.seed_text = args[2] if args.size() > 2 else "REFLOOK"
	var scene: Node = load("res://scenes/infinite_route_test.tscn").instantiate()
	add_child(scene)
	_scene = scene
	_run(scene)


var _scene: Node


## The window is not focused during a scripted run, which opens the pause menu
## and its scrim over every shot; close it again each frame.
func _corridor_spot(data: Dictionary) -> Dictionary:
	var grid: Array = data["grid"]
	var size := grid.size()
	var in_room := {}
	for room in data.get("rooms", []):
		var rect: Rect2i = room["rect"]
		for z in range(rect.position.y - 1, rect.end.y + 1):
			for x in range(rect.position.x - 1, rect.end.x + 1):
				in_room[Vector2i(x, z)] = true
	for swap in [false, true]:
		for z in range(3, size - 3):
			for x in range(3, size - 12):
				var ok := true
				for dx in 10:
					var cx := x + dx
					var cells := [Vector2i(cx, z), Vector2i(cx, z - 1), Vector2i(cx, z + 1),
						Vector2i(cx, z - 2), Vector2i(cx, z + 2)]
					var open := []
					for c in cells:
						var gx: int = c.y if swap else c.x
						var gz: int = c.x if swap else c.y
						open.append(int(grid[gz][gx]) == 0 and not in_room.has(Vector2i(gx, gz)))
					if not (open[0] and open[1] and open[2]) or open[3] or open[4]:
						ok = false
						break
				if ok:
					return {"x": z if swap else x, "z": x if swap else z, "swap": swap}
	return {}


func _scan_level(gen: StreamedRouteGenerator, level: int, reach: int, cs: int,
		picks: Array, seen: Dictionary) -> void:
	for cz in range(-reach, reach + 1):
		for cx in range(-reach, reach + 1):
			var data: Dictionary = gen.chunk(Vector3i(cx, level, cz))
			for room in data.get("rooms", []):
				var key := "%s_%s" % [data.get("region", ""), room.get("room_type", "")]
				if seen.has(key):
					continue
				seen[key] = true
				var rect: Rect2i = room["rect"]
				picks.append({"name": key, "pos": Vector3(
					cx * cs + rect.position.x + rect.size.x * .5,
					level * StreamedFacilityView3D.LEVEL_HEIGHT + 0.05,
					cz * cs + rect.position.y + rect.size.y * .5)})
			# one long corridor stretch per region, looking down its axis
			var region := String(data.get("region", ""))
			if not seen.has("corridor_" + region):
				var spot := _corridor_spot(data)
				if not spot.is_empty():
					seen["corridor_" + region] = true
					picks.append({"name": "corridor_" + region, "pos": Vector3(
						cx * cs + spot["x"] + .5,
						level * StreamedFacilityView3D.LEVEL_HEIGHT + 0.05,
						cz * cs + spot["z"] + .5),
						"yaw": 180.0 if spot["swap"] else -90.0})


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		var pause = _scene.get("pause_menu")
		if pause != null and pause.has_method("close") and pause.is_open():
			pause.close()
		get_tree().paused = false


func _run(scene: Node) -> void:
	await _wait(30)
	var facility: StreamedFacilityView3D = scene.get_node("%StreamedFacility")
	var player: PlayerController3D = scene.get_node("%Player")
	if OS.get_environment("CAP_HUD") == "":
		scene.get_node("%HUD").visible = false
	var gen := facility.generator
	var cs := StreamedRouteGenerator.CHUNK_SIZE
	var picks := []
	var seen := {}
	var level_env := OS.get_environment("CAP_LEVELS")
	var reach := 3 if level_env != "" else 2
	for level_text in (level_env if level_env != "" else "0").split(","):
		_scan_level(gen, int(level_text), reach, cs, picks, seen)
	if OS.get_environment("CAP_LIST") != "":
		for p in picks:
			print(p["name"], " ", p["pos"])
	var only := OS.get_environment("CAP_ONLY")
	var max_n := int(OS.get_environment("CAP_MAX")) if OS.get_environment("CAP_MAX") != "" else 9999
	var yaws := PackedStringArray((OS.get_environment("CAP_YAWS") if OS.get_environment("CAP_YAWS") != "" else "0,90").split(","))
	var n := 0
	for p in picks:
		if only != "" and not String(p["name"]).contains(only):
			continue
		if n >= max_n:
			break
		n += 1
		var these_yaws := yaws
		if p.has("yaw"):
			these_yaws = PackedStringArray([str(p["yaw"])])
		for yaw_text in these_yaws:
			player.global_position = p["pos"]
			player._yaw = deg_to_rad(float(yaw_text))
			player._pitch = -0.04
			player._apply_look_rotation()
			facility.refresh_at_tracked_player()
			await _wait(14)
			if OS.get_environment("CAP_FPS") != "":
				var t0 := Time.get_ticks_usec()
				await _wait(60)
				print("%s yaw %s: %.1f fps" % [p["name"], yaw_text, 60.0 / ((Time.get_ticks_usec() - t0) / 1e6)])
				continue
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%s_%s.png" % [_out_dir, _tag, p["name"], yaw_text])
	get_tree().quit()
