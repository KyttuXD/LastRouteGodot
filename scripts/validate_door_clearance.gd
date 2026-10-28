extends RefCounted

## Door clearance (docs/DOORWAY_CLEARANCE.md): walks every normal (1.5x humanoid) hunter through every door type at walk
## and at run, with the real clips, the real raised frames and the DoorwayPose overlay, and checks each mesh part of her
## against the opening measured from the frame's own vertices: 10 cm or more over her head (or the duck is on and she
## still clears), side room at the posts and through the wall, and never into the open door leaf.
##
##   godot --headless --path . res://scenes/validate.tscn -- door_clearance

const WALL_DEPTH := 1.0
const DUCK_ON := .05
const MIN_DUCKED := .02
const MIN_SIDE := .005
## Hair, ears, horns, tails, wings may brush a frame by this much (the body parts may not touch it at all); every brush is
## listed in the summary so it stays visible.
const ACCESSORY_BRUSH := .10
## Parts wider than a 1 m door however she turns (floating glyphs). They still pass through the frame side; listed every
## run, never failed, until the models change or the doors widen (docs/DOORWAY_CLEARANCE.md).
const WIDER_THAN_A_DOOR := {"nyxie": ["R-Glyph"], "solyth": ["R-Glyph"]}
const SPEEDS := {"walk": 1.7, "sprint": 4.8}
const DT := 1.0 / 60.0

var _failures := 0
var _brushes := {}
var _wide := {}


func _brush(id: String, part: String, door: String) -> void:
	(_brushes.get_or_add("%s %s" % [id, part], {}) as Dictionary)[door] = true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var doors := _doors(host)
	_check_frames(doors)
	_check_registry(host)
	_check_headers(doors)
	var hunters: Array = HunterRoster.A_Z_IDS
	var ducks := 0
	var turns := 0
	var tightest := INF
	var narrowest := INF
	for id in hunters:
		if HunterRoster.scale_for(id) != HunterRoster.MODEL_SCALE:
			continue
		var result := _walk_hunter(host, id, doors)
		ducks += int(result["ducks"])
		turns += int(result["turns"])
		tightest = minf(tightest, float(result["headroom"]))
		narrowest = minf(narrowest, float(result["side"]))
	for door in doors:
		(door["node"] as Node).free()
	for key in _wide:
		print("    wider than a door (known, through the frame side): %s at %s" % [key, ", ".join((_wide[key] as Dictionary).keys())])
	for key in WIDER_THAN_A_DOOR:
		for part in WIDER_THAN_A_DOOR[key]:
			_expect(not DoorwayPose.BONES.has(part), "%s: a body part (%s) cannot be excused as wider than a door" % [key, part])
	for key in _brushes:
		print("    brush (accessory within %.0f cm of a frame): %s at %s" % [ACCESSORY_BRUSH * 100.0, key, ", ".join((_brushes[key] as Dictionary).keys())])
	if _failures == 0:
		print("  door_clearance  %d hunters x %d door types at walk and run: no body part through a frame or leaf; %d passes ducked, %d turned; body headroom >= %.2f m, side room >= %.2f m, %d accessory brushes, %d known-wide parts" \
			% [hunters.size(), doors.size(), ducks, turns, tightest, narrowest, _brushes.size(), _wide.size()])
	return _failures


## Every door type as the game builds it: {name, node, width (clear), height (clear), leaves (Array[AABB])}.
func _doors(host: Node) -> Array:
	var out := []
	for type in PropModelCatalog.ROOM_DOOR_TYPES:
		var door := RouteInteractable3D.new()
		var span := 2 if String(type).contains("Double") else 1
		door.configure_room_door("check:%s" % type, PropModelCatalog.model_path(type, "check"), true, false, Callable(), span)
		host.add_child(door)
		var frame := DoorwayFrames.opening(door, ["DoorFrame"])
		var leaves: Array[AABB] = []
		for mesh in door.find_children("*Leaf*", "MeshInstance3D", true, false):
			leaves.append(_in_space(door, mesh as MeshInstance3D))
		out.append({"name": type, "node": door, "width": frame.x, "height": frame.y, "leaves": leaves})
	var boarded := RouteInteractable3D.new()
	boarded.kind = RouteInteractable3D.Kind.BOARDED_PATH
	host.add_child(boarded)
	for mesh in boarded.find_children("Board_*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).visible = false   # cleared: the frame alone
	var opening := DoorwayFrames.opening(boarded, ["DoorFrame", "DoorHeader"])
	out.append({"name": "boarded_door", "node": boarded, "width": opening.x, "height": opening.y, "leaves": []})
	# the prison cell doorway: a wall gap between two gate runs, jambs either side, no lintel
	var prison := Node3D.new()
	host.add_child(prison)
	out.append({"name": "prison_doorway", "node": prison, "width": 1.0, "height": DoorwayFrames.NO_HEADER, "leaves": []})
	return out


func _space(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var walk := node
	while walk != null and walk != root:
		xf = walk.transform * xf
		walk = walk.get_parent_node_3d()
	return xf


func _in_space(root: Node3D, mesh: MeshInstance3D) -> AABB:
	return _space(root, mesh) * mesh.get_aabb()


func _check_frames(doors: Array) -> void:
	for door in doors:
		var name := String(door["name"])
		var node: Node3D = door["node"]
		if name == "prison_doorway":
			continue
		_expect(float(door["height"]) >= 2.4, "%s opens only %.2f m high after the raise" % [name, float(door["height"])])
		_expect(float(door["width"]) >= .8 and float(door["width"]) < 3.0 and float(door["height"]) < 5.0,
			"%s measured %.2f x %.2f m (frame vertex scan found no posts/header in %s)" % [name, float(door["width"]),
			float(door["height"]), node.find_children("*", "MeshInstance3D", true, false).map(func(m): return m.name)])
		var visual_top := 0.0
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			visual_top = maxf(visual_top, _in_space(node, mesh as MeshInstance3D).end.y)
		_expect(visual_top <= DoorwayFrames.FRAME_TOP_CAP + .01, "%s frame reaches %.2f m, over the %.2f m cap (lowest room ceiling)" \
			% [name, visual_top, DoorwayFrames.FRAME_TOP_CAP])
		print("    %s  opening %.2f x %.2f m, frame top %.2f m" % [name, float(door["width"]), float(door["height"]), visual_top])


## No see-through gap over a door (KT): in generated chunks on several floors and in every biome they reach, each room
## door cell gets a header whose faces stop a ray through the opening above the frame on both sides, up to each side's
## ceiling, and a soffit that stops a ray straight up; every raised frame reaches the soffit.
func _check_headers(doors: Array) -> void:
	for door in doors:
		if String(door["name"]).ends_with("RoomDoor"):
			var top := 0.0
			for mesh in (door["node"] as Node3D).find_children("*", "MeshInstance3D", true, false):
				top = maxf(top, _in_space(door["node"], mesh as MeshInstance3D).end.y)
			_expect(top >= DoorwayFrames.HEADER_Y, "%s frame top %.2f m stops under the header soffit (%.2f m): a gap" \
				% [door["name"], top, DoorwayFrames.HEADER_Y])
	var checked := 0
	var tallest := 0.0
	for seed_text in ["DOOR-HEAD-A", "DOOR-HEAD-B", "DOOR-HEAD-C"]:
		var generator := StreamedRouteGenerator.new(seed_text)
		for level in [0, 1, 2]:
			for cz in range(-2, 3):
				for cx in range(-2, 3):
					var coord := Vector3i(cx, level, cz)
					var data := generator.chunk(coord)
					var region := String(data.get("region", "maze"))
					var heights := RefLook.chunk_heights(data)
					var headers := StreamedFacilityView3D.door_headers(data.get("region_props", []), heights,
						RefLook.corridor_height(region, coord))
					for cell_value in headers:
						var cell: Vector2i = cell_value
						var header: Dictionary = headers[cell]
						checked += 1
						tallest = maxf(tallest, maxf(float(header["front_h"]), float(header["back_h"])))
						_check_header_rays(cell, header, "%s %s %s" % [seed_text, coord, cell])
	_expect(checked >= 20, "only %d door cells found to check headers on" % checked)
	print("    headers: %d door cells, ceilings up to %.1f m, no ray through the opening above a frame" % [checked, tallest])


func _check_header_rays(cell: Vector2i, header: Dictionary, where: String) -> void:
	var surface := RefSurfaceMesh.new()
	StreamedFacilityView3D.add_door_header(surface, cell, header, [0.0, Color.WHITE], [0.0, Color.WHITE])
	var faces := surface.build(null, null).get_faces()
	var centre := Vector3(cell.x + .5, 0.0, cell.y + .5)
	var across: Vector2i = header["normal"]
	for side in [across, -across]:
		var top := float(header["front_h"] if side == across else header["back_h"])
		var out := Vector3(side.x, 0, side.y)
		for y in [DoorwayFrames.HEADER_Y + .05, (DoorwayFrames.HEADER_Y + top) * .5, top - .05]:
			if y >= top:
				continue
			for slide in [-.4, 0.0, .4]:
				var along: Vector3 = Vector3(-out.z, 0, out.x) * float(slide)
				_expect(_hits(faces, centre + along + out * 1.2 + Vector3.UP * y, -out),
					"gap over the door at %s: a ray at %.2f m from the %s side passes (ceiling %.2f m)" % [where, y, side, top])
	_expect(_hits(faces, centre + Vector3.UP * 2.0, Vector3.UP), "no soffit over the door frame at %s" % where)


func _hits(faces: PackedVector3Array, from: Vector3, direction: Vector3) -> bool:
	for index in range(0, faces.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(from, direction, faces[index], faces[index + 1], faces[index + 2])
		if hit != null and from.distance_to(hit) < 1.3:
			return true
	return false


func _check_registry(host: Node) -> void:
	var before := DoorwayFrames.count()
	var marker := Node3D.new()
	marker.position = Vector3(40.5, 0, 40.5)
	DoorwayFrames.register(marker, 1.0, 2.8, .25)
	_expect(DoorwayFrames.count() == before, "a frame registered before it was in the tree")
	host.add_child(marker)
	_expect(DoorwayFrames.count() == before + 1, "a frame did not register when it entered the tree")
	var hit := DoorwayFrames.nearest(Vector3(40.5, 0, 41.3))
	_expect(not hit.is_empty() and is_equal_approx(float(hit["along"]), .8), "nearest() missed a frame 0.8 m away: %s" % hit)
	_expect(DoorwayFrames.nearest(Vector3(40.5, 0, 44.5)).is_empty(), "a frame 4 m away still counted")
	_expect(DoorwayFrames.nearest(Vector3(40.5, 4.0, 41.0)).is_empty(), "a frame on another floor counted")
	marker.free()
	_expect(DoorwayFrames.count() == before, "a freed frame stayed registered")


func _walk_hunter(host: Node, id: String, doors: Array) -> Dictionary:
	var walker := Node3D.new()
	host.add_child(walker)
	var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(id))
	model.scale = Vector3.ONE * HunterRoster.scale_for(id)
	walker.add_child(model)
	var player := ModelSlot.find_animation_player(model)
	var pose := DoorwayPose.new()
	pose.bind(model)
	_expect(pose.bound(), "%s: doorway pose did not bind to the rig" % id)
	var stats := {"ducks": 0, "turns": 0, "headroom": INF, "side": INF}
	for door in doors:
		var frame := {"width": door["width"], "height": door["height"], "depth": .25}
		for clip in SPEEDS:
			var clip_name := String(clip) if player != null and player.has_animation(clip) else "walk"
			if player != null and player.has_animation(clip_name):
				player.play(clip_name)
			# bound once at rest (as the game does on spawn); each pass starts out of the pose
			pose.turn = 0.0
			pose.duck = 0.0
			var worst := _pass(model, player, pose, frame, float(SPEEDS[clip]), door, id, String(clip))
			stats["headroom"] = minf(float(stats["headroom"]), worst["headroom"])
			stats["side"] = minf(float(stats["side"]), worst["side"])
			stats["ducks"] += int(worst["ducked"])
			stats["turns"] += int(worst["turned"])
	walker.free()
	return stats


## One pass from 2.6 m before the wall to 2.6 m past it; returns the worst headroom and whether she ducked / turned.
func _pass(model: Node3D, player: AnimationPlayer, pose: DoorwayPose, frame: Dictionary, speed: float,
		door: Dictionary, id: String, clip: String) -> Dictionary:
	var name := String(door["name"])
	var half := float(door["width"]) * .5
	var height := float(door["height"])
	var worst := {"headroom": INF, "side": INF, "ducked": false, "turned": false}
	var reported := false
	var along := 2.6
	var seconds := 0.0
	var walker := model.get_parent_node_3d()
	while along > -2.6:
		pose.restore()
		if player != null and player.current_animation != "":
			player.seek(fmod(seconds, maxf(player.current_animation_length, .01)), true)
		pose.update(DT, frame, along)
		var ducked := pose.duck > DUCK_ON
		worst["ducked"] = worst["ducked"] or ducked
		worst["turned"] = worst["turned"] or pose.turn > .5
		var space := Transform3D(Basis.IDENTITY, Vector3(0, 0, along))
		var names := []
		var boxes := DoorwayPose.mesh_boxes(model, space, names)
		for index in boxes.size():
			var box: AABB = boxes[index]
			var core := DoorwayPose.BONES.has(String(names[index]))
			var slack := 0.0 if core else ACCESSORY_BRUSH
			var problem := ""
			# side room through the whole wall gap
			if box.position.z < WALL_DEPTH * .5 and box.end.z > -WALL_DEPTH * .5:
				var side_room := minf(box.position.x + half, half - box.end.x)
				if core:
					worst["side"] = minf(worst["side"], side_room)
				if side_room < MIN_SIDE - slack:
					problem = "side through the %s (x %.2f..%.2f, opening +-%.2f)" % [name, box.position.x, box.end.x, half]
				elif side_room < MIN_SIDE:
					_brush(id, String(names[index]), name)
			# headroom under the header
			if box.position.z < .2 and box.end.z > -.2:
				var room := height - box.end.y
				var needed := MIN_DUCKED if ducked else DoorwayFrames.HEADROOM
				if core:
					worst["headroom"] = minf(worst["headroom"], room)
				if room < needed - slack:
					problem = "head %.2f m under the %s header (%s)" % [room, name, "ducked %.2f" % pose.duck if ducked else "not ducking"]
				elif room < needed:
					_brush(id, String(names[index]), name)
			for leaf in door["leaves"]:
				if (leaf as AABB).grow(-.005 - slack).intersects(box):
					problem = "through the open %s leaf" % name
				elif (leaf as AABB).grow(-.005).intersects(box):
					_brush(id, String(names[index]), name + " leaf")
			if not problem.is_empty() and (WIDER_THAN_A_DOOR.get(id, []) as Array).has(String(names[index])):
				(_wide.get_or_add("%s %s" % [id, names[index]], {}) as Dictionary)[name] = true
				problem = ""
			if not problem.is_empty() and not reported:
				_expect(false, "%s %s at %.2f m: %s %s (turn %.2f duck %.2f)" % [id, clip, along, names[index], problem, pose.turn, pose.duck])
				reported = true
		along -= speed * DT
		seconds += DT
	pose.restore()
	return worst
