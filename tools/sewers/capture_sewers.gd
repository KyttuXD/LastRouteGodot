extends Node3D

## Windowed review captures of the sewer (docs/SEWERS.md): a tunnel, the
## junction chamber, a utility room, a hunter mid-climb in a ladder shaft and
## the open manhole seen from the maze. Run on a test machine:
##
##   Claude-Setup/mini-run.sh . <lane> --scene "res://tools/sewers/capture_sewers.tscn -- OUTDIR"

const SEED := "SEWER-CAPTURE"
const CLIMBER := "umbriel"

var _view: StreamedFacilityView3D
var _player: PlayerController3D
var _camera: Camera3D
var _out := "user://sewer_captures"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	add_child(env)
	RefLook.install(self, env)
	_view = StreamedFacilityView3D.new()
	add_child(_view)
	_player = (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	add_child(_player)
	_player.visible = false
	_player.flashlight_enabled = false
	_camera = Camera3D.new()
	_camera.fov = 72.0
	add_child(_camera)
	_camera.current = true
	# the runner's flashlight, so the dark sewer reads the way a player sees it
	var torch := SpotLight3D.new()
	torch.spot_range = 16.0
	torch.spot_angle = 30.0
	torch.light_energy = 2.2
	torch.light_color = Color("fff1d6")
	_camera.add_child(torch)
	_run.call_deferred()


func _run() -> void:
	var level_y := float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	var c := SewerRouteGenerator.CENTER
	var half := SewerRouteGenerator.TUNNEL_HALF
	_player.global_position = Vector3(c - half + .5, level_y + .04, c + .5)
	_view.begin(SEED, _player)
	await _settle()
	# 1: down the east-west tunnel from the north walkway
	await _shot("sewer_tunnel", Vector3(c + 12.5, level_y + 1.6, c - half + 1.2), Vector3(c - 6.0, level_y + .4, c + .5))
	# 1b: looking up at the vault over the tunnel (what decorates the ceiling)
	await _shot("sewer_ceiling", Vector3(c + 8.5, level_y + 1.6, c - half + 1.5), Vector3(c - 2.0, level_y + 3.1, c + .5))
	# 2: across the junction chamber
	await _shot("sewer_junction", Vector3(c - 5.5, level_y + 2.2, c - 5.5), Vector3(c + 3.0, level_y, c + 3.0))
	# 3: a utility room nearby
	var room := _find_room(["pump_room", "valve_room", "overflow_chamber"])
	if not room.is_empty():
		var rect: Rect2i = room["rect"]
		var chunk: Vector3i = room["coord"]
		var origin := Vector3(chunk.x * StreamedRouteGenerator.CHUNK_SIZE, level_y, chunk.z * StreamedRouteGenerator.CHUNK_SIZE)
		_player.global_position = origin + Vector3(rect.get_center().x, .04, rect.get_center().y)
		_view.refresh_at_tracked_player()
		await _settle()
		await _shot("sewer_%s" % room["room_type"], origin + Vector3(rect.end.x - .6, 2.4, rect.end.y - .6),
			origin + Vector3(rect.position.x + 1.0, .3, rect.position.y + 1.0))
	# 4 + 5: the origin chunk's ladder: a hunter mid-climb from the shaft chamber, then the manhole from the maze
	# a ladder away from the origin chunk (its spawn marker would crowd the shot)
	var link := {}
	for coord in [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 1)]:
		var links: Array = _view.generator.sewer().links_for(coord)
		if not links.is_empty():
			link = links[0]
			break
	var foot := LadderTraffic.ladder_point(link, SewerRouteGenerator.LEVEL)
	var wall: Vector2i = link.get("wall", Vector2i(0, -1))
	var away := Vector3(-wall.x, 0, -wall.y)
	_player.global_position = Vector3(foot.x, level_y + .04, foot.y)
	_view.refresh_at_tracked_player()
	await _settle()
	# up the ladder shaft from its foot: the lining runs from the vault to the open lid with no gap at either end
	await _shot("ladder_looking_up", Vector3(foot.x, level_y + 1.4, foot.y) + away * .7, Vector3(foot.x, level_y + 6.0, foot.y) - away * .1)
	var climber := _climbing_hunter(Vector3(foot.x, level_y + 1.4, foot.y) - away * .32, wall)
	await _shot("sewer_hunter_climbing", Vector3(foot.x, level_y + 1.1, foot.y) + away * 2.3 + Vector3(.6, 0, .6),
		Vector3(foot.x, level_y + 2.3, foot.y))
	climber.global_position.y = -3.1   # climbing up the shaft, her head just under the open lid
	_player.global_position = Vector3(foot.x, .04, foot.y)
	_view.refresh_at_tracked_player()
	await _settle()
	await _shot("maze_manhole", Vector3(foot.x, 1.9, foot.y) + away * 1.6, Vector3(foot.x, -1.2, foot.y))
	# 6: down a ramp tunnel from the first sewer to the collector, from its top landing
	for upper in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
		var ramp := {}
		var column := Vector2i.ZERO
		for cz in range(-2, 3):
			for cx in range(-2, 3):
				if ramp.is_empty():
					ramp = _view.generator.sewer().ramp_between(cx, cz, upper)
					column = Vector2i(cx, cz)
		if ramp.is_empty():
			continue
		var size := StreamedRouteGenerator.CHUNK_SIZE
		var base := Vector2(column * size)
		var top := base + Vector2(ramp["link"]["from_cell"]) + Vector2(.5, .5)
		var bottom := base + Vector2(ramp["link"]["to_cell"]) + Vector2(.5, .5)
		var upper_y := float(upper) * StreamedFacilityView3D.LEVEL_HEIGHT
		_player.global_position = Vector3(top.x, upper_y + .04, top.y)
		_view.refresh_at_tracked_player()
		await _settle()
		var back := (top - bottom).normalized()
		await _shot("ramp_from_%d" % upper, Vector3(top.x + back.x * 1.2, upper_y + 1.7, top.y + back.y * 1.2),
			Vector3(bottom.x, upper_y - 3.2, bottom.y))
	# 6b: the falls from the first sewer into the collector: from the overlook, and from the cistern below
	var site := {}
	var site_column := Vector2i.ZERO
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			if site.is_empty():
				site = _view.generator.sewer().falls_between(cx, cz)
				site_column = Vector2i(cx, cz)
	if not site.is_empty():
		var size := StreamedRouteGenerator.CHUNK_SIZE
		var base := Vector3(site_column.x * size, 0.0, site_column.y * size)
		var lip := base + Vector3(float(site["edge_x0"]) + 1.5, 0.0, float(site["edge_z"]))
		var toward := 1.0 if bool(site["north"]) else -1.0     # from the lip back along the spur
		var overlook: Rect2i = site["overlook"]
		_player.global_position = base + Vector3(overlook.position.x + 1.5, level_y + .04, overlook.get_center().y)
		_view.refresh_at_tracked_player()
		await _settle()
		await _shot("falls_overlook", lip + Vector3(3.2, level_y + 1.7, toward * 3.0), lip + Vector3(0, level_y - 2.5, -toward * 1.5))
		var low_y := float(SewerRouteGenerator.LOWER_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
		var chamber: Rect2i = site["chamber"]
		_player.global_position = base + Vector3(chamber.position.x + 1.5, low_y + .04, chamber.get_center().y)
		_view.refresh_at_tracked_player()
		await _settle()
		await _shot("falls_cistern", base + Vector3(chamber.position.x + 1.5, low_y + 1.6, chamber.get_center().y - toward * 3.5),
			lip + Vector3(0, low_y + 1.8, 0))
		# up the drop at the lip a storey overhead
		await _shot("falls_looking_up", base + Vector3(chamber.position.x + 1.5, low_y + 1.2, chamber.get_center().y - toward * 3.5),
			lip + Vector3(0, level_y + .8, 0))
	# 6c: a maze <-> sewer stairwell, looking up it from the foot and down it from the head, with the runner on the
	# stairs half way (where its level flips): the other storey around the doorway must be built, not blank
	var well := {}
	var well_column := Vector2i.ZERO
	for cz in range(-4, 5):
		for cx in range(-4, 5):
			if well.is_empty():
				well = _view.generator.stairwell_between(cx, cz, 0)
				well_column = Vector2i(cx, cz)
	if not well.is_empty():
		var size := StreamedRouteGenerator.CHUNK_SIZE
		var base := Vector3(well_column.x * size, level_y, well_column.y * size)
		var path: Array = well["link"]["path"]
		var well_foot: Vector3 = base + (path[0] as Vector3)
		var well_head: Vector3 = base + (path[path.size() - 1] as Vector3)
		var out_dir := Vector3(0, 0, float(int(well["outward"])))
		_player.global_position = well_foot + Vector3(0, .04, 0)
		_view.refresh_at_tracked_player()
		await _settle()
		for _frame in 600:      # both storeys of the window streamed in (the shots are about what is built)
			if _view._pending_loads.is_empty() and _view._active_build.is_empty():
				break
			await get_tree().process_frame
		var lower_data: Dictionary = _view._chunk_data.get(Vector3i(well_column.x, SewerRouteGenerator.LEVEL, well_column.y), {})
		var upper_data: Dictionary = _view._chunk_data.get(Vector3i(well_column.x, 0, well_column.y), {})
		var landing: Vector2i = well["landing"]
		print("stairwell %s kind %s box %s: level %d, lower shaft %d/%d, upper shaft %d/%d, landing open %s/%s" % [
			well["link"]["id"], well["kind"], well["box"], _view.current_level(),
			(well["shaft"] as Dictionary).keys().filter(func(c): return (lower_data.get("shaft_cells", {}) as Dictionary).has(c)).size(),
			(well["shaft"] as Dictionary).size(),
			(well["shaft"] as Dictionary).keys().filter(func(c): return (upper_data.get("shaft_cells", {}) as Dictionary).has(c)).size(),
			(well["shaft"] as Dictionary).size(),
			int((lower_data.get("grid", []) as Array)[landing.y][landing.x]) if lower_data.has("grid") else -9,
			int((upper_data.get("grid", []) as Array)[landing.y][landing.x]) if upper_data.has("grid") else -9])
		await _shaft_shots("stairwell", well, base)
		# walk the flight at a runner's pace (the bug is in streaming while walking, not in a settled window): start at
		# the foot, climb to the head, shoot out of the top doorway at once; then walk back down and shoot out of the foot
		for leg in ["up", "down"]:
			var points: Array = path.duplicate()
			if leg == "down":
				points.reverse()
			for k in range(1, points.size()):
				var a: Vector3 = base + (points[k - 1] as Vector3)
				var b: Vector3 = base + (points[k] as Vector3)
				var steps := maxi(1, int(a.distance_to(b) / (3.5 / 60.0)))
				for t in steps:
					_player.global_position = a.lerp(b, float(t + 1) / float(steps)) + Vector3(0, .04, 0)
					await get_tree().process_frame
			if leg == "up":
				await _shot("stairwell_top_after_climb", well_head + Vector3(0, 1.6, 0) - out_dir * .5,
					well_head + Vector3(0, 1.2, 0) + out_dir * 10.0)
			else:
				await _shot("stairwell_foot_after_descent", well_foot + Vector3(0, 1.6, 0) - out_dir * .5,
					well_foot + Vector3(0, 1.2, 0) + out_dir * 10.0)
	# 6d: the sewer -> collector and collector -> Inferno ramps (KT's report on LEVEL -2: a slab across the way down),
	# from each foot up the slope, from each head down it, and from a few steps down at the tunnel mouth
	for ramp_upper in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
		var tag := "collector_ramp" if ramp_upper == SewerRouteGenerator.LEVEL else "inferno_ramp"
		var deep_ramp := {}
		var ramp_column := Vector2i.ZERO
		for cz in range(-4, 5):
			for cx in range(-4, 5):
				if deep_ramp.is_empty():
					deep_ramp = _view.generator.sewer().ramp_between(cx, cz, ramp_upper)
					ramp_column = Vector2i(cx, cz)
		if not deep_ramp.is_empty():
			var size := StreamedRouteGenerator.CHUNK_SIZE
			var height := StreamedFacilityView3D.LEVEL_HEIGHT
			var corner := Vector3(ramp_column.x * size, 0, ramp_column.y * size)
			var row := float(int(deep_ramp["row"])) + .5
			var top_x := float(deep_ramp["top_x"])
			var bottom_x := float(deep_ramp["bottom_x"])
			var down := signf(bottom_x - top_x)
			var ramp_foot := corner + Vector3(bottom_x + down * 1.5, (ramp_upper - 1) * height, row)
			var ramp_head := corner + Vector3(top_x - down * 1.5, ramp_upper * height, row)
			print("ramp %s at column %s: foot %s head %s" % [deep_ramp["link"]["id"], ramp_column, ramp_foot, ramp_head])
			_player.global_position = ramp_foot + Vector3(0, .04, 0)
			_view.refresh_at_tracked_player()
			await _settle()
			for _frame in 600:
				if _view._pending_loads.is_empty() and _view._active_build.is_empty():
					break
				await get_tree().process_frame
			if OS.get_environment("RAMP_DUMP") != "":
				_dump_ramp(deep_ramp, ramp_column)
			await _shot(tag + "_looking_up", ramp_foot + Vector3(0, 1.6, 0), ramp_head + Vector3(0, 2.4, 0))
			await _shot(tag + "_looking_down", ramp_head + Vector3(0, 1.6, 0), ramp_foot + Vector3(0, .6, 0))
			# KT's viewpoint: a few steps down the slope, looking down at the tunnel mouth
			var part_way := ramp_head.lerp(ramp_foot, .35)
			await _shot(tag + "_mouth", part_way + Vector3(0, 1.6, 0), ramp_foot + Vector3(0, 1.2, 0))
	# 6e: the collector's vault along its north-south channel steps down under the first sewer's trench overhead
	var low_level_y := float(SewerRouteGenerator.LOWER_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	_player.global_position = Vector3(c - half + .5, low_level_y + .04, c + 14.5)
	_view.refresh_at_tracked_player()
	await _settle()
	await _shot("collector_channel_vault", Vector3(c - half + 1.2, low_level_y + 1.6, c + 14.5),
		Vector3(c + 1.0, low_level_y + 3.0, c + 6.0))
	# 6f: an outflow main across a walkway (KT: crawl under it or go round): from down the walkway, and crouched under it
	var main := {}
	var main_coord := Vector3i.ZERO
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			if main.is_empty():
				for prop in _view.generator.chunk(Vector3i(cx, SewerRouteGenerator.LEVEL, cz))["region_props"]:
					if bool((prop as Dictionary).get("outflow", false)):
						main = prop
						main_coord = Vector3i(cx, SewerRouteGenerator.LEVEL, cz)
	if not main.is_empty():
		var size := StreamedRouteGenerator.CHUNK_SIZE
		var corner := Vector3(main_coord.x * size, level_y, main_coord.z * size)
		var middle: Vector2i = main["cell"]
		var along: Vector2i = main["crawl_step"]
		var at := corner + Vector3(middle.x + .5, 0, middle.y + .5)
		var back := Vector3(along.x, 0, along.y)
		_player.global_position = at + back * 6.0 + Vector3(0, .04, 0)
		_view.refresh_at_tracked_player()
		await _settle()
		await _shot("outflow_main", at + back * 6.0 + Vector3(0, 1.6, 0), at + Vector3(0, 1.4, 0))
		await _shot("outflow_crawl", at + back * 1.4 + Vector3(0, .8, 0), at - back * 3.0 + Vector3(0, .6, 0))
	# 7: the Inferno, the deepest level, along its central hall
	var inferno_y := float(StreamedRouteGenerator.INFERNO_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	_player.global_position = Vector3(c + 4.5, inferno_y + .04, c + .5)
	_view.refresh_at_tracked_player()
	await _settle()
	await _shot("inferno_hall", Vector3(c + 9.5, inferno_y + 1.7, c + .5), Vector3(c - 6.0, inferno_y + 1.0, c + .5))
	print("SEWER CAPTURES -> %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()


## Looking up a stairwell's shaft from its lower landing and down it from the upper one. `base` is the world
## position of the well's lower storey's chunk origin; the path's y runs 0 (lower) .. RISE (upper) above it.
func _shaft_shots(name: String, well: Dictionary, base: Vector3) -> void:
	var path: Array = well["link"]["path"]
	var lower := base
	var foot: Vector3 = lower + (path[0] as Vector3)
	var middle := Vector3.ZERO
	for cell_value in well["shaft"]:
		var cell: Vector2i = cell_value
		middle += Vector3(cell.x + .5, 0, cell.y + .5)
	middle /= float((well["shaft"] as Dictionary).size())
	_player.global_position = foot + Vector3(0, .04, 0)
	_view.refresh_at_tracked_player()
	await _settle()
	for _frame in 600:
		if _view._pending_loads.is_empty() and _view._active_build.is_empty():
			break
		await get_tree().process_frame
	await _shot(name + "_looking_up", foot + Vector3(0, 1.5, 0), lower + middle + Vector3(0, 5.5, 0))
	var head: Vector3 = base + (path[path.size() - 1] as Vector3)
	await _shot(name + "_looking_down", head + Vector3(0, 1.6, 0), lower + middle + Vector3(0, .3, 0))


## Debug (RAMP_DUMP=1): every quad and mesh of both chunks near a ramp, chunk-local.
func _dump_ramp(ramp: Dictionary, column: Vector2i) -> void:
	var rect: Rect2i = ramp["ramp"]
	print("RAMPDUMP rect %s top %s bottom %s top_x %s bottom_x %s" % [rect, ramp["top"], ramp["bottom"], ramp["top_x"], ramp["bottom_x"]])
	for level in [int(ramp["upper"]), int(ramp["upper"]) - 1]:
		var node := _view.get_node_or_null("Chunk_%d_%d_%d" % [column.x, level, column.y]) as Node3D
		if node == null:
			print("RAMPDUMP level %d missing" % level)
			continue
		var inv := node.global_transform.affine_inverse()
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf: Transform3D = inv * mi.global_transform
			if mi.name != "Surface":
				var at: Vector3 = xf.origin
				if at.x > rect.position.x - 2 and at.x < rect.end.x + 2 and at.z > rect.position.y - 2 and at.z < rect.end.y + 2:
					print("RAMPDUMP L%d mesh %s at %s" % [level, node.get_path_to(mi), at.snapped(Vector3.ONE * .01)])
				continue
			for si in mi.mesh.get_surface_count():
				var v: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
				for q in range(0, v.size(), 4):
					var a: Vector3 = xf * v[q]
					var b: Vector3 = xf * v[q + 2]
					var c := (a + b) * .5
					if c.x > rect.position.x - 1.5 and c.x < rect.end.x + 1.5 and c.z > rect.position.y - 1.5 and c.z < rect.end.y + 1.5:
						print("RAMPDUMP L%d s%d %s -> %s" % [level, si, a.snapped(Vector3.ONE * .01), b.snapped(Vector3.ONE * .01)])


func _settle() -> void:
	for _frame in 40:
		await get_tree().process_frame


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	_camera.global_position = eye
	_camera.look_at(look, Vector3.UP)
	for _frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("captured ", name)


func _find_room(kinds: Array) -> Dictionary:
	for radius in 3:
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var coord := Vector3i(x, SewerRouteGenerator.LEVEL, z)
				for room in _view.generator.chunk(coord).get("rooms", []):
					if kinds.has(String(room["room_type"])):
						var found: Dictionary = room.duplicate()
						found["coord"] = coord
						return found
	return {}


## The hunter's own rig on the rungs, facing the wall, frozen partway through her climb clip.
func _climbing_hunter(at: Vector3, wall: Vector2i) -> Node3D:
	var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(CLIMBER))
	add_child(model)
	model.global_position = at
	model.rotation.y = atan2(-float(wall.x), -float(wall.y))
	model.scale = Vector3.ONE * HunterRoster.scale_for(CLIMBER)
	var animation := ModelSlot.find_animation_player(model)
	if animation != null and animation.has_animation("climb"):
		animation.play("climb")
		animation.seek(.3, true)
		animation.pause()
	return model
