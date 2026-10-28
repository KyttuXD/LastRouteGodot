extends Node

## Screenshot rig for the reference-look pass. Loads the infinite route, teleports
## the runner to one room of each type and saves viewport PNGs.
##
##   godot --path . res://tools/look/capture.tscn -- OUTDIR TAG [SEED]
## Add CAP_FULLBRIGHT=1 (or FULLBRIGHT=1) as an extra argument for the flat fullbright look (DebugView).
##
## Environment: CAP_ONLY=<substring of "region_roomtype">, CAP_MAX=<n rooms>,
## CAP_YAWS="0,90" (degrees), CAP_FPS=1 to print the frame time instead of
## shooting, CAP_LIST=1 to list the picks.

var _out_dir := ""
var _tag := "x"


func _ready() -> void:
	LampField.optimise = OS.get_environment("CAP_LEGACY_LIGHTS") == ""
	var args := OS.get_cmdline_user_args()
	# extra "KEY=VALUE" arguments become environment variables (mini-run.sh cannot prefix env vars)
	for extra in args.slice(3):
		var pair := String(extra).split("=", false, 1)
		if pair.size() == 2:
			OS.set_environment(pair[0], pair[1])
	_out_dir = args[0] if args.size() > 0 else "/tmp"
	_tag = args[1] if args.size() > 1 else "x"
	DirAccess.make_dir_recursive_absolute(_out_dir)
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
			# an archway seen from the hall, looking into the room
			if not seen.has("arch_" + String(data.get("region", ""))):
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					if bool(prop.get("arch", false)):
						var cell: Vector2i = prop["cell"]
						var out: Vector2i = prop["outward"]
						seen["arch_" + String(data.get("region", ""))] = true
						picks.append({"name": "arch_" + String(data.get("region", "")),
							"pos": Vector3(cx * cs + cell.x + .5 + out.x * 5.0, 0.05, cz * cs + cell.y + .5 + out.y * 5.0),
							"yaw": rad_to_deg(atan2(float(out.x), float(out.y)))})
						break
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
		# CAP_SCALE=1.5: draw them at the in-game hunter scale (HunterRoster.MODEL_SCALE)
		if OS.get_environment("CAP_SCALE") != "":
			node.scale = Vector3.ONE * float(OS.get_environment("CAP_SCALE"))
		node.global_position = origin + forward * distance + side * lateral
		node.rotation.y = deg_to_rad(yaw_deg)
		placed.append(node)
		distance += 2.5
		lateral = -lateral
	if OS.get_environment("CAP_MANNEQUIN") != "":
		# CAP_MANNEQUIN=1: the player model 1.5 m to the right of the nearest hunter, for scale
		var mannequin: Node3D = (load(PlayerModels.BLOCKY) as PackedScene).instantiate()
		_scene.add_child(mannequin)
		mannequin.global_position = origin + forward * 3.5 + side * 1.2
		mannequin.rotation.y = deg_to_rad(yaw_deg)
		placed.append(mannequin)
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
	if OS.get_environment("CAP_COLLISION") != "":
		# CAP_COLLISION=1: the admin SHOW COLLISION overlay (colliders red, door keep-clear zones green)
		scene.call("_set_show_collision", true)
	var gen := facility.generator
	var cs := StreamedRouteGenerator.CHUNK_SIZE
	var picks := []
	var seen := {}
	var level_env := OS.get_environment("CAP_LEVELS")
	var reach := 3 if level_env != "" else 2
	if OS.get_environment("CAP_REACH") != "":
		reach = int(OS.get_environment("CAP_REACH"))
	for level_text in (level_env if level_env != "" else "0").split(","):
		_scan_level(gen, int(level_text), reach, cs, picks, seen)
	if OS.get_environment("CAP_SUITE") != "":
		# CAP_SUITE=apartment|office: the rooms of the nearest generated suite of that kind
		picks = []
		var found := false
		for cz in range(-12, 13):
			if found:
				break
			for cx in range(-12, 13):
				var data: Dictionary = gen.chunk(Vector3i(cx, 0, cz))
				for suite in data.get("suites", []):
					if String(suite["kind"]) != OS.get_environment("CAP_SUITE") or found:
						continue
					found = true
					for room in data.get("rooms", []):
						if String(room.get("suite_id", "")) == String(suite["id"]) and not bool(room.get("suite_parent", false)):
							var rect: Rect2i = room["rect"]
							picks.append({"name": "suite_%s" % room["room_type"], "pos": Vector3(
								cx * cs + rect.position.x + rect.size.x * .5, .05,
								cz * cs + rect.position.y + rect.size.y * .5)})
	if OS.get_environment("CAP_GREAT") != "":
		# CAP_GREAT=1: the first great hall (21x21 gathering room) of each district, seen from its door
		picks = []
		var seen_biomes := {}
		for gr in range(0, 12):
			for gz in range(-gr, gr + 1):
				for gx in range(-gr, gr + 1):
					var gc := Vector3i(gx, 0, gz)
					if maxi(absi(gx), absi(gz)) != gr or not gen.is_chunk_allowed(gc):
						continue
					var gb := gen.biome_for(gc)
					if seen_biomes.has(gb):
						continue
					var plan := gen.large_plan(gc)
					for side in ["W", "E"]:
						if String(plan[side]).is_empty() or seen_biomes.has(gb):
							continue
						seen_biomes[gb] = true
						var west: bool = side == "W"
						picks.append({"name": "great_%s_%s" % [gb, plan[side]], "yaw": 90.0 if west else -90.0,
							"pos": Vector3(gx * cs + (17.5 if west else 27.5), 0.05, gz * cs + 22.5)})
	if OS.get_environment("CAP_AT") not in ["", "start"]:
		# CAP_AT="x,z;x,z": world metres, one pick per pair
		picks = []
		for pair in OS.get_environment("CAP_AT").split(";"):
			var xz := pair.split(",")
			var pick := {"name": "at_%s_%s" % [xz[0], xz[1]], "pos": Vector3(float(xz[0]), .05, float(xz[1]))}
			if xz.size() > 2:
				pick["yaw"] = float(xz[2])   # optional third value: the heading in degrees
			if xz.size() > 3:
				pick["pos"].y = float(xz[3])   # optional fourth value: the standing height (a lower level's floor)
			picks.append(pick)
	if OS.get_environment("CAP_JUNCTION") != "":
		# CAP_JUNCTION=gothic: one T and one cross junction of that biome in THIS run's generator, 5 m down an arm
		picks = []
		for entry in GeometryAudit.junction_spots(facility.generator, OS.get_environment("CAP_JUNCTION")):
			var xz := String(entry).split(",")
			picks.append({"name": "junction_%s_%s" % [xz[0], xz[1]], "pos": Vector3(float(xz[0]), .05, float(xz[1])), "yaw": float(xz[2])})
	if OS.get_environment("CAP_CRAWL") != "":
		# CAP_CRAWL=1: the first crawl-under pipe of the sewer layer, 4 m down its branch looking at it (CAP_LEVELS is ignored)
		picks = []
		var sewers := SewerRouteGenerator.new(facility.generator)
		for cz in range(-4, 5):
			for cx in range(-4, 5):
				if picks.size() >= 2:
					continue
				for prop in sewers.chunk(Vector3i(cx, SewerRouteGenerator.LEVEL, cz))["region_props"]:
					if prop.get("crawl_under", false) and picks.size() < 2:
						var step: Vector2i = prop["crawl_step"]
						var at := Vector2(cx * 45 + (prop["cell"] as Vector2i).x + .5, cz * 45 + (prop["cell"] as Vector2i).y + .5) + Vector2(step) * 4.0
						picks.append({"name": "crawl_%d_%d" % [cx, cz], "pos": Vector3(at.x, SewerRouteGenerator.LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT + .05, at.y),
							"yaw": rad_to_deg(atan2(float(step.x), float(step.y)))})
						break
	if OS.get_environment("CAP_FALLS") != "":
		# CAP_FALLS=1: the first waterfall of this run's generator: the top (level -1, on the spur looking at the lip) and the
		# bottom (level -2, across the cistern looking at the landing); CAP_FALLS=pit: the first cage pit on level -3
		picks = []
		var fsize := StreamedRouteGenerator.CHUNK_SIZE
		for cz in range(-4, 5):
			for cx in range(-4, 5):
				if not picks.is_empty():
					continue
				if OS.get_environment("CAP_FALLS") == "ramp":
					var ramp: Dictionary = facility.generator.sewer().ramp_between(cx, cz, SewerRouteGenerator.LOWER_LEVEL)
					if ramp.is_empty():
						continue
					var rz := cz * fsize + float(ramp["row"]) + .5
					var top_rect: Rect2i = ramp["top"]
					var bottom_rect: Rect2i = ramp["bottom"]
					var slope_rect: Rect2i = ramp["ramp"]
					var top_cx := cx * fsize + top_rect.position.x + 1.5
					var bot_cx := cx * fsize + bottom_rect.position.x + 1.5
					var slope_mid := cx * fsize + slope_rect.position.x + slope_rect.size.x * .5
					var low2 := SewerRouteGenerator.LOWER_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT
					var low3 := StreamedRouteGenerator.INFERNO_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT
					var away := -1.0 if top_cx > slope_mid else 1.0       # from the landing toward the slope
					picks.append({"name": "ramp_top", "pos": Vector3(top_cx - away * 1.5, low2 + .05, rz), "yaw": 0.0,
						"look": Vector3(slope_mid, low3 + 1.2, rz)})
					picks.append({"name": "ramp_bottom", "pos": Vector3(bot_cx + away * 1.0, low3 + .05, rz), "yaw": 0.0,
						"look": Vector3(slope_mid, low2 + .6, rz)})
					picks.append({"name": "ramp_bottom_side", "pos": Vector3(bot_cx, low3 + .05, rz), "yaw": 0.0,
						"look": Vector3(bot_cx, low3 + 1.4, cz * fsize + float((ramp["connector"] as Rect2i).position.y) + (ramp["connector"] as Rect2i).size.y * .5)})
					continue
				if OS.get_environment("CAP_FALLS") == "seal":
					var seal_y := StreamedRouteGenerator.INFERNO_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT
					for spec in facility.generator.chunk(Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz)).get("breakables", []):
						var seal_centre: Vector2 = spec["extras"]["centre"]
						var seal_dir: Vector2 = spec["extras"]["dir"]
						var from_cell: Vector2 = seal_centre - seal_dir * 5.0
						picks.append({"name": "seal_%s" % String(spec["variant"]), "yaw": 0.0,
							"pos": Vector3(cx * fsize + from_cell.x, seal_y + .05, cz * fsize + from_cell.y),
							"look": Vector3(cx * fsize + seal_centre.x, seal_y + 1.4, cz * fsize + seal_centre.y)})
						break
					continue
				if OS.get_environment("CAP_FALLS") == "cave":
					var cave_data: Dictionary = facility.generator.chunk(Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz))
					var cave_chambers: Array = cave_data.get("inferno_caverns", [])
					if cave_chambers.is_empty() or cx != 1 or cz != 1:
						continue
					var cave_y := StreamedRouteGenerator.INFERNO_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT
					var mid := Vector2i(StreamedRouteGenerator.CHUNK_SIZE / 2, StreamedRouteGenerator.CHUNK_SIZE / 2)
					# from the middle chamber looking along a tunnel toward the seam, and across the chamber
					var home: Vector2i = InfernoCaverns.landing(cave_data)
					for heading in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
						picks.append({"name": "cave_%d_%d" % [heading.x, heading.y], "yaw": 0.0,
							"pos": Vector3(cx * fsize + home.x + .5, cave_y + .05, cz * fsize + home.y + .5),
							"look": Vector3(cx * fsize + home.x + .5 + heading.x * 12, cave_y + 1.2, cz * fsize + home.y + .5 + heading.y * 12)})
					continue
				if OS.get_environment("CAP_FALLS") == "pit":
					for pit in InfernoCaverns.pits_in(facility.generator.chunk(Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz))):
						var span: Rect2i = pit["bridge"]
						var pit_north: bool = pit["north"]
						var pit_y := StreamedRouteGenerator.INFERNO_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT
						var pit_z := float(span.end.y) + 5.0 if pit_north else float(span.position.y) - 5.0
						picks.append({"name": "pit_stand", "pos": Vector3(cx * fsize + span.position.x + 1.5, pit_y + .05, cz * fsize + pit_z + (3.0 if pit_north else -3.0)),
							"yaw": 0.0, "look": Vector3(cx * fsize + span.position.x + 1.5, pit_y - .7, cz * fsize + float(span.position.y) + 1.5)})
						break
					continue
				var falls: Dictionary = facility.generator.sewer().falls_between(cx, cz)
				if falls.is_empty():
					continue
				var qc: Vector2i = falls["center"]
				var falls_north: bool = falls["north"]
				var lip_z := cz * fsize + float(falls["edge_z"])
				var fx := cx * fsize + qc.x + .5
				var top_y := SewerRouteGenerator.LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT
				var low_y := SewerRouteGenerator.LOWER_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT
				var back := 6.0 if falls_north else -6.0
				picks.append({"name": "falls_top", "pos": Vector3(fx, top_y + .05, lip_z + back),
					"yaw": 0.0, "look": Vector3(fx, top_y - 1.0, lip_z)})
				picks.append({"name": "falls_bottom", "pos": Vector3(fx, low_y + .05, lip_z - back * 1.1),
					"yaw": 0.0, "look": Vector3(fx, low_y + 1.2, lip_z)})
	if OS.get_environment("CAP_AT") == "start":
		# CAP_AT=start: only the spawn (the starting safe room), 4 m back from its centre
		picks = [{"name": "start", "pos": player.global_position + Vector3(0, 0, 4)}]
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
			if p.has("look") or OS.get_environment("CAP_LOOK") != "":
				# CAP_LOOK="x,y,z": aim every CAP_AT pick at that world point (eye height 1.6 m)
				var d := Vector3.ZERO
				if p.has("look"):
					d = (p["look"] as Vector3) - (p["pos"] as Vector3 + Vector3(0, 1.6, 0))
				else:
					var target := PackedStringArray(OS.get_environment("CAP_LOOK").split(","))
					d = Vector3(float(target[0]), float(target[1]), float(target[2])) - (p["pos"] as Vector3 + Vector3(0, 1.6, 0))
				player._yaw = atan2(-d.x, -d.z)
				player._pitch = atan2(d.y, Vector2(d.x, d.z).length())
			player._apply_look_rotation()
			facility.refresh_at_tracked_player()
			# CAP_FULLBRIGHT=1 (or FULLBRIGHT=1): DebugView's flat, shadowless look, so dark levels can be judged; the shot name
			# gets a _fb suffix. Capture tools only: DebugView stays admin-gated in the game.
			if OS.get_environment("CAP_FULLBRIGHT") != "" or OS.get_environment("FULLBRIGHT") != "":
				DebugView.tool_override = true
				DebugView.set_mode(DebugView.Mode.FULLBRIGHT, get_viewport())
			var hunter_nodes := _place_hunters(p["pos"], float(yaw_text))
			await _wait(int(OS.get_environment("CAP_WAIT")) if OS.get_environment("CAP_WAIT") != "" else 14)
			if OS.get_environment("CAP_FPS") != "":
				var t0 := Time.get_ticks_usec()
				await _wait(60)
				print("%s yaw %s: %.1f fps, %d draw calls, %d objects" % [p["name"], yaw_text,
					60.0 / ((Time.get_ticks_usec() - t0) / 1e6),
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
				continue
			if OS.get_environment("CAP_LIGHTS") != "":
				var omni := 0
				var omni_visible := 0
				var spot_shadow := 0
				var omni_shadow := 0
				for light in get_tree().root.find_children("*", "Light3D", true, false):
					if light is OmniLight3D:
						omni += 1
						if (light as Light3D).is_visible_in_tree():
							omni_visible += 1
					if (light as Light3D).shadow_enabled and (light as Light3D).is_visible_in_tree():
						if light is SpotLight3D:
							spot_shadow += 1
						else:
							omni_shadow += 1
				if OS.get_environment("CAP_LIGHTS") == "2":
					var by_owner := {}
					for light in get_tree().root.find_children("*", "OmniLight3D", true, false):
						if (light as Light3D).is_visible_in_tree() and not (light as Node).is_in_group("budget_light") \
								and not (light.get_parent() is LampField):
							var gp := light.get_parent().get_parent()
							var key := "%s|%s|r=%.1f e=%.2f" % [light.name, (gp.name if gp != null else "-"), (light as OmniLight3D).omni_range, (light as Light3D).light_energy]
							by_owner[key] = int(by_owner.get(key, 0)) + 1
					print("UNBUDGETED ", by_owner)
				print("LIGHTS %s yaw %s: omni=%d visible=%d shadowed(omni=%d spot=%d)" % [p["name"], yaw_text, omni, omni_visible, omni_shadow, spot_shadow])
			var map_layer: CanvasLayer = null
			if OS.get_environment("CAP_MAP") != "":
				map_layer = await _show_map(scene, player)
			var img := get_viewport().get_texture().get_image()
			if map_layer != null:
				map_layer.queue_free()
				img = img.get_region(Rect2i(0, 0, mini(img.get_width(), img.get_height()), mini(img.get_width(), img.get_height())))
				img.resize(480, 480, Image.INTERPOLATE_BILINEAR)
			img.save_png("%s/%s_%s_%s.png" % [_out_dir, _tag, p["name"], yaw_text])
			for node in hunter_nodes:
				node.queue_free()
	get_tree().quit()


## CAP_MAP=1: the HUD map widget (FacilityMap, revealed, CAP_MAP_RADIUS cells around the runner, default 9) drawn over the
## frame, with the prop collision shapes that really exist in the 3D scene outlined in red on top: on an accurate map the
## grey boxes fill the red outlines exactly.
func _show_map(scene: Node, player: PlayerController3D) -> CanvasLayer:
	scene.set("_admin_reveal_map", true)
	scene.call("_discover_loaded_chunks")
	var layer := CanvasLayer.new()
	layer.layer = 100
	var side := float(mini(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y))
	var map := FacilityMap.new()
	map.size = Vector2(side, side)
	layer.add_child(map)
	var truth := _ShapeOutlines.new()
	truth.map = map
	truth.size = map.size
	layer.add_child(truth)
	get_tree().root.add_child(layer)
	var radius := int(OS.get_environment("CAP_MAP_RADIUS")) if OS.get_environment("CAP_MAP_RADIUS") != "" else 9
	var facility: StreamedFacilityView3D = scene.get_node("%StreamedFacility")
	map.show_streamed_state(scene.call("_local_map_chunks"), facility.current_chunk_coord().y, StreamedRouteGenerator.CHUNK_SIZE,
		Vector2(player.global_position.x, player.global_position.z), Vector2(0, 1), [], false, radius)
	for shape_node in facility.find_children("*", "CollisionShape3D", true, false):
		var shape := (shape_node as CollisionShape3D).shape
		if shape is BoxShape3D and StreamedFacilityView3D._box_shapes.values().has(shape):
			truth.boxes.append([(shape_node as CollisionShape3D).global_transform, (shape as BoxShape3D).size])
	await _wait(4)
	return layer


class _ShapeOutlines extends Control:
	var map: FacilityMap
	var boxes: Array = []

	func _draw() -> void:
		var cell: float = map._last_cell_scale
		for entry in boxes:
			var xf: Transform3D = entry[0]
			var size: Vector3 = entry[1]
			var points := PackedVector2Array()
			for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
				var w: Vector3 = xf * ((corner as Vector3) * size * .5)
				points.append(map._last_screen_origin + (Vector2(w.x, w.z) - map._last_world_origin) * cell)
			draw_polyline(points, Color(1, .2, .2), 1.5)

	func _process(_delta: float) -> void:
		queue_redraw()
