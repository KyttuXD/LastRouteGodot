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
	if OS.get_environment("CAP_FPS") != "":
		Settings.fps_limit = 0
		Settings.vsync_enabled = false
		Settings._apply_display_performance()
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
			for stair_value in data.get("stairs", []):
				var stair: Dictionary = stair_value
				if String(stair.get("direction", "")) != "up" or seen.has("stairs_" + String(data.get("region", ""))):
					continue
				var path := StreamedRouteGenerator.stair_path_cells(stair.get("cell", Vector2i.ZERO))
				if path.size() < 2:
					continue
				var dir := path[1] - path[0]
				seen["stairs_" + String(data.get("region", ""))] = true
				picks.append({"name": "stairs_" + String(data.get("region", "")),
					"pos": Vector3(cx * cs + path[0].x + .5 - dir.x * 4.0,
						level * StreamedFacilityView3D.LEVEL_HEIGHT + 0.05,
						cz * cs + path[0].y + .5 - dir.y * 4.0),
					"yaw": rad_to_deg(atan2(-dir.x, -dir.y))})
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


## CAP_HUNTERS="a,b,c": place sprite hunters 3.5, 6 and 9 m ahead of the runner.
func _place_hunters(origin: Vector3, yaw_deg: float) -> Array:
	var placed := []
	var ids := OS.get_environment("CAP_HUNTERS")
	if ids == "":
		return placed
	var forward := Vector3(-sin(deg_to_rad(yaw_deg)), 0, -cos(deg_to_rad(yaw_deg)))
	var side := Vector3(forward.z, 0, -forward.x)
	var distance := 3.5
	var lateral := -.8
	for id in ids.split(","):
		var identity: Dictionary = HunterRoster.get_identity(id)
		if identity.is_empty():
			continue
		var node: Node3D = ModelSlot.instantiate_hunter(identity)
		if node == null:
			continue
		_scene.add_child(node)
		node.global_position = origin + forward * distance + side * lateral
		node.rotation.y = deg_to_rad(yaw_deg)
		placed.append(node)
		distance += 2.5
		lateral = -lateral
	return placed


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
		if only != "":
			var wanted := false
			for part in only.split(","):
				if String(p["name"]).contains(part):
					wanted = true
			if not wanted:
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
			player._pitch = deg_to_rad(float(OS.get_environment("CAP_PITCH")) if OS.get_environment("CAP_PITCH") != "" else -2.0)
			player._apply_look_rotation()
			facility.refresh_at_tracked_player()
			var hunter_nodes := _place_hunters(p["pos"], float(yaw_text))
			await _wait(14)
			if OS.get_environment("CAP_FPS") != "":
				var t0 := Time.get_ticks_usec()
				await _wait(60)
				print("%s yaw %s: %.1f fps, %d draw calls, %d objects" % [p["name"], yaw_text,
					60.0 / ((Time.get_ticks_usec() - t0) / 1e6),
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
				continue
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%s_%s.png" % [_out_dir, _tag, p["name"], yaw_text])
			for node in hunter_nodes:
				node.queue_free()
	get_tree().quit()
