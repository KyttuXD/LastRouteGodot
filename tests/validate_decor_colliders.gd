extends RefCounted

## Decor colliders ("wall arches need collisions"): the hall pilasters and the four door-arch columns of every archway are
## solid (RefDecor.collider_boxes -> one StaticBody3D "DecorColliders" per chunk), and nothing else of the arch trim is.
## Builds real streamed chunks (maze, mansion, hotel, gothic, mall, sewer ... several seeds, levels 0 / -1 / -2) and checks:
##   - every drawn arch / pilaster box that stands below the standing player's head has a collider within 1 cm (and every
##     collider has a drawn box), while the header, corner steps, keystones, voussoirs and sewer haunch ribs hang above it;
##   - each door3 arch has its four columns; a second build from the same seed gives identical collider lists;
##   - the body sits on the wall blocks' layer / mask, holds one box shape per collider, is bounded per chunk, and is
##     freed with the chunk;
##   - with the real physics world: a standing, crouching and hunter-sized capsule still walk through every arch doorway
##     and along every hall between two facing pilasters (clear width >= 1.4 m), while a capsule on a pilaster hits it.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- decor_colliders

const SEEDS := ["DCOL-A", "DCOL-B", "DCOL-C"]
const LEVELS := [0, -1, -2]
const PER_REGION := 1
const ARCH_REGIONS := ["mansion", "gothic", "hotel", "maze"]
const ARCH_CHUNKS_PER_REGION := 2
## Boxes per chunk: the densest measured chunk has about 65 pilasters + 24 arch columns.
const MAX_BOXES := 100
const TOL := .011
const STAND_H := PlayerController3D.STANDING_COLLISION_HEIGHT
const CROUCH_H := PlayerController3D.CROUCH_COLLISION_HEIGHT
const HUNTER_H := HunterView3D.HUNTER_BODY_HEIGHT
const MIN_AISLE := 1.4

var _failures := 0
var _chunks := 0
var _pilasters := 0
var _columns := 0
var _arches := 0
var _regions := {}
var _max_boxes := 0
var _box_total := 0
var _min_gap := INF
var _pairs := 0
var _doors_walked := 0
var _tail_ms_max := 0.0
var _body_ms_max := 0.0
var _body_ms_sum := 0.0
var _attach_ms_max := 0.0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		if _failures < 30:
			print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var bodies_before := host.get_tree().get_nodes_in_group("decor_colliders").size()
	for seed_text in SEEDS:
		var view := StreamedFacilityView3D.new()
		host.add_child(view)
		view.generator = StreamedRouteGenerator.new(seed_text)
		view.world_state = StreamedWorldState.new()
		for coord_value in _pick_chunks(view.generator):
			await _audit_chunk(host, view, coord_value, seed_text)
		view.queue_free()
		await host.get_tree().process_frame
	await host.get_tree().process_frame
	_expect(host.get_tree().get_nodes_in_group("decor_colliders").size() == bodies_before,
		"decor collider bodies outlived their chunks (%d before, %d after)" % [bodies_before,
		host.get_tree().get_nodes_in_group("decor_colliders").size()])
	_expect(_chunks >= 15, "only %d chunks audited" % _chunks)
	_expect(_pilasters >= 200, "only %d pilaster colliders found" % _pilasters)
	_expect(_arches >= 4, "only %d door3 arches audited" % _arches)
	_expect(_columns == _arches * 4, "%d arch columns for %d arches (want 4 each)" % [_columns, _arches])
	_expect(_pairs >= 50, "only %d facing pilaster pairs walked" % _pairs)
	_expect(_min_gap >= MIN_AISLE, "narrowest hall between pilasters is %.2f m (< %.1f m aisle)" % [_min_gap, MIN_AISLE])
	_expect(_doors_walked >= 4, "only %d archways walked" % _doors_walked)
	print("  decor_colliders  %d chunks %s; %d pilasters, %d arch columns on %d arches; boxes/chunk avg %.1f max %d"
		% [_chunks, str(_regions.keys()), _pilasters, _columns, _arches, float(_box_total) / maxf(1.0, _chunks), _max_boxes])
	print("  decor_colliders  narrowest hall between pilasters %.2f m over %d pairs, %d archways walked; last-slice ms max %.2f; body build ms avg %.3f max %.3f, attach ms max %.3f: %d failures"
		% [_min_gap, _pairs, _doors_walked, _tail_ms_max, _body_ms_sum / maxf(1.0, _chunks), _body_ms_max, _attach_ms_max, _failures])
	return _failures


func _pick_chunks(generator: StreamedRouteGenerator) -> Array:
	var out := []
	var taken := {}
	var arch_taken := {}
	for level in LEVELS:
		for r in range(0, 14):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var coord := Vector3i(dx, level, dz)
					if not generator.is_chunk_allowed(coord):
						continue
					var region := generator.region_for(coord)
					var key := "%d %s" % [level, region]
					var has_arch := false
					if level == 0 and ARCH_REGIONS.has(region) and int(arch_taken.get(region, 0)) < ARCH_CHUNKS_PER_REGION:
						has_arch = _has_arch(generator.chunk(coord))
					if int(taken.get(key, 0)) < PER_REGION or has_arch:
						taken[key] = int(taken.get(key, 0)) + 1
						if has_arch:
							arch_taken[region] = int(arch_taken.get(region, 0)) + 1
						out.append(coord)
	return out


static func _has_arch(data: Dictionary) -> bool:
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if bool(prop.get("arch", false)) and (prop.get("doorway_cells", []) as Array).size() == 3:
			return true
	return false


func _audit_chunk(host: Node, view: StreamedFacilityView3D, coord: Vector3i, seed_text: String) -> void:
	var where := "%s %s" % [seed_text, coord]
	var build := view._create_chunk_build(coord)

	while not view._advance_chunk_build(build, true):
		pass
	var root := build["root"] as Node3D
	var decor := build["decor"] as RefDecor
	var data: Dictionary = build["data"]
	var region := String(data.get("region", "maze"))
	_regions["%d %s" % [coord.y, region]] = true
	_chunks += 1
	if decor == null or root == null:
		_expect(data.has("mezzanine_grid"), "%s: no decor built" % where)
		if root != null:
			root.queue_free()
		return
	var boxes: Array = decor.collider_boxes
	_max_boxes = maxi(_max_boxes, boxes.size())
	_box_total += boxes.size()
	_expect(boxes.size() <= MAX_BOXES, "%s: %d collider boxes in one chunk (bound %d)" % [where, boxes.size(), MAX_BOXES])
	# --- the body: layer / mask like the wall blocks, one box shape per collider, a child of the chunk root
	var body := root.get_node_or_null("DecorColliders") as StaticBody3D
	var structure := root.get_node("Structure") as GridMap
	_expect((body != null) == (not boxes.is_empty()), "%s: body %s for %d boxes" % [where, body, boxes.size()])
	if body != null:
		_expect(body.collision_layer == structure.collision_layer and body.collision_mask == structure.collision_mask,
			"%s: decor body layer/mask %d/%d differ from the walls' %d/%d" % [where, body.collision_layer, body.collision_mask, structure.collision_layer, structure.collision_mask])
		_expect(body.get_child_count() == boxes.size(), "%s: %d shapes for %d boxes" % [where, body.get_child_count(), boxes.size()])
		for i in mini(body.get_child_count(), boxes.size()):
			var shape_node := body.get_child(i) as CollisionShape3D
			var box: Dictionary = boxes[i]
			var shape := shape_node.shape as BoxShape3D
			if shape == null or not (shape_node.position - (box["transform"] as Transform3D).origin).is_zero_approx() \
					or _vmax((shape.size - (box["size"] as Vector3)).abs()) > .006:
				_expect(false, "%s: shape %d does not match its box" % [where, i])
				break
	# --- visible trim vs colliders (both directions)
	_check_cover(decor, boxes, where)
	var pilasters := 0
	var columns := 0
	for box_value in boxes:
		match String((box_value as Dictionary)["kind"]):
			"pilaster":
				pilasters += 1
			"arch_column":
				columns += 1
	var doors := 0
	for entry_value in decor.arch_log:
		if String((entry_value as Dictionary)["kind"]) == "door3":
			doors += 1
	_expect(columns == doors * 4, "%s: %d arch columns for %d door3 arches" % [where, columns, doors])
	_pilasters += pilasters
	_columns += columns
	_arches += doors
	# --- determinism: a second decor from the same seed's data builds the identical list; time the body and the last slice
	var scratch := Node3D.new()
	var again := RefDecor.new(scratch, StreamedRouteGenerator.new(seed_text).chunk(coord), build["room_map"], build["heights"], build["corridor_h"])
	var slice_ms := 0.0
	while true:
		var t0 := Time.get_ticks_usec()
		var finished := again.step()
		slice_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		if finished:
			break
	_tail_ms_max = maxf(_tail_ms_max, slice_ms)
	_expect(again.collider_boxes == boxes, "%s: a second build from the same seed gives a different collider list" % where)
	var scratch_body := scratch.get_node_or_null("DecorColliders") as StaticBody3D
	if scratch_body != null:
		scratch.remove_child(scratch_body)
		scratch_body.free()
		var t1 := Time.get_ticks_usec()
		again._flush_colliders()
		var built_ms := float(Time.get_ticks_usec() - t1) / 1000.0
		_body_ms_max = maxf(_body_ms_max, built_ms)
		_body_ms_sum += built_ms
		var t2 := Time.get_ticks_usec()
		host.add_child(scratch)
		_attach_ms_max = maxf(_attach_ms_max, float(Time.get_ticks_usec() - t2) / 1000.0)
	scratch.free()
	# --- the real physics world
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	_check_physics(root, decor, data, where)
	root.queue_free()
	await host.get_tree().process_frame


## Every drawn arch / pilaster box with its underside below the standing head has a collider; every collider has a drawn box.
func _check_cover(decor: RefDecor, boxes: Array, where: String) -> void:
	var visuals: Array = []    # [centre, size] of every axis-aligned wall-theme box
	var uncovered := 0
	var hanging_low := 0
	for key in decor._transforms:
		if not (String(key).begins_with("arch_wall:") or String(key).begins_with("arch_trim:")):
			continue
		for t_value in decor._transforms[key]:
			var t: Transform3D = t_value
			var half := (t.basis.x.abs() + t.basis.y.abs() + t.basis.z.abs()) * .5
			var bottom := t.origin.y - half.y
			var aligned := true
			for column in [t.basis.x, t.basis.y, t.basis.z]:
				var a: Vector3 = (column as Vector3).abs()
				if a.x + a.y + a.z - maxf(a.x, maxf(a.y, a.z)) > 1e-3:
					aligned = false
			if aligned:
				visuals.append([t.origin, half * 2.0])
			if bottom >= STAND_H + .05 or half.y * 2.0 < .2:
				continue    # above every head, or a 12 cm cap
			if not aligned:
				hanging_low += 1
				continue
			if not _has_box(boxes, t.origin, half * 2.0):
				uncovered += 1
	_expect(uncovered == 0, "%s: %d drawn arch/pilaster boxes below head height have no collider" % [where, uncovered])
	_expect(hanging_low == 0, "%s: %d rotated arch pieces hang below head height (%.2f m) with no collider" % [where, hanging_low, STAND_H])
	var phantom := 0
	for box_value in boxes:
		var box: Dictionary = box_value
		var found := false
		for visual_value in visuals:
			var visual: Array = visual_value
			if _same_box((box["transform"] as Transform3D).origin, box["size"], visual[0], visual[1]):
				found = true
				break
		if not found:
			phantom += 1
	_expect(phantom == 0, "%s: %d colliders without a drawn box" % [where, phantom])


func _has_box(boxes: Array, centre: Vector3, size: Vector3) -> bool:
	for box_value in boxes:
		var box: Dictionary = box_value
		if _same_box((box["transform"] as Transform3D).origin, box["size"], centre, size):
			return true
	return false


static func _same_box(c1: Vector3, s1: Vector3, c2: Vector3, s2: Vector3) -> bool:
	return _vmax((c1 - c2).abs()) <= TOL and _vmax((s1 - s2).abs()) <= TOL


static func _vmax(v: Vector3) -> float:
	return maxf(v.x, maxf(v.y, v.z))


# -- physics ---------------------------------------------------------------------------------------------------------

func _capsule(radius: float, height: float) -> CapsuleShape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	return capsule


## Wall / decor-body hits of `shape` standing with its feet `lift` above `floor_at` (a world point on the chunk's floor).
func _solid_hits(space: PhysicsDirectSpaceState3D, shape: CapsuleShape3D, floor_at: Vector3) -> int:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, floor_at + Vector3(0, .12 + shape.height * .5, 0))
	var count := 0
	for hit in space.intersect_shape(query, 8):
		var collider: Object = hit["collider"]
		if collider is GridMap or (collider is Node and (collider as Node).name == "DecorColliders"):
			count += 1
	return count


func _check_physics(root: Node3D, decor: RefDecor, data: Dictionary, where: String) -> void:
	var space := root.get_world_3d().direct_space_state
	var origin := root.global_position
	var shapes := [
		["stand", _capsule(GameConfig.PLAYER_RADIUS, STAND_H)],
		["crouch", _capsule(GameConfig.PLAYER_RADIUS, CROUCH_H)],
		["hunter", _capsule(HunterView3D.HUNTER_BODY_RADIUS, HUNTER_H)]]
	# archways: walk each capsule through the opening, centred and hugging either shoulder, and out to both faces
	for entry_value in decor.arch_log:
		var entry: Dictionary = entry_value
		if String(entry["kind"]) != "door3":
			continue
		var centre: Vector3 = entry["centre"]
		var out3 := ((entry["faces"][0] as Vector3) - centre) * 2.0
		var across := out3.cross(Vector3.UP).normalized()
		_doors_walked += 1
		for shape_pair in shapes:
			var radius := (shape_pair[1] as CapsuleShape3D).radius
			for lane in [-1.0, 0.0, 1.0]:
				var offset: float = lane * (1.5 - radius - .06)
				for step in range(-6, 7):
					var at := origin + centre + out3 * (float(step) * .25) + across * offset
					var hits := _solid_hits(space, shape_pair[1], at)
					if hits > 0:
						_expect(false, "%s: %s capsule blocked in the archway at %s (lane %.2f, step %d)" % [where, shape_pair[0], centre, offset, step])
						break
	# control: a capsule on a pilaster / arch column hits the decor body
	for box_value in decor.collider_boxes:
		var box: Dictionary = box_value
		var at := origin + (box["transform"] as Transform3D).origin
		var probe := _capsule(.1, 1.0)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = probe
		query.collision_mask = 1
		query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, origin.y + 1.2, at.z))
		var on_body := false
		for hit in space.intersect_shape(query, 8):
			if (hit["collider"] as Node).name == "DecorColliders":
				on_body = true
		_expect(on_body, "%s: a probe inside the %s box at %s hits nothing" % [where, box["kind"], at])
	# halls: between two facing pilasters every capsule fits and walks the hall's length past the station
	var grid: Array = data["grid"]
	for a_value in decor.collider_boxes:
		var a: Dictionary = a_value
		if String(a["kind"]) != "pilaster":
			continue
		var a_centre: Vector3 = (a["transform"] as Transform3D).origin
		var a_size: Vector3 = a["size"]
		var depth_x := a_size.x < a_size.z    # the .32 m side is x: the wall faces along x
		var n_candidates: Array = [Vector3(1, 0, 0), Vector3(-1, 0, 0)] if depth_x else [Vector3(0, 0, 1), Vector3(0, 0, -1)]
		for n_value in n_candidates:
			var n: Vector3 = n_value
			var partner := _facing_partner(decor.collider_boxes, a_centre, n, depth_x)
			if partner.is_empty() or not _open_between(grid, a_centre, partner["pos"], n):
				continue
			# the pilaster faces `partner`: the open hall is the gap between the two inner faces
			var gap: float = (partner["pos"] as Vector3 - a_centre).dot(n) - PILASTER_DEPTH_FULL
			var mid: Vector3 = a_centre + n * (gap * .5 + PILASTER_DEPTH_FULL * .5)
			# each pair once, and only halls narrow enough that the strip beside the station is open floor (a wide space can hold
			# walls of its own mid-way; the line check above covers the pilaster line only)
			if n.dot(Vector3(1, 1, 1)) < 0.0 or gap > 4.0:
				continue    # each pair once
			_pairs += 1
			_min_gap = minf(_min_gap, gap)
			_expect(gap >= MIN_AISLE, "%s: hall %.2f m between pilasters at %s (< %.1f m)" % [where, gap, a_centre, MIN_AISLE])
			var along := Vector3(0, 0, 1) if depth_x else Vector3(1, 0, 0)
			for shape_pair in shapes:
				for step in range(-3, 4):
					var at := origin + Vector3(mid.x, 0, mid.z) + along * (float(step) * .5)
					if _solid_hits(space, shape_pair[1], at) > 0:
						_expect(false, "%s: %s capsule blocked in the hall between pilasters at %s (step %d)" % [where, shape_pair[0], a_centre, step])
						break
			break


const PILASTER_DEPTH_FULL := RefDecor.PILASTER_DEPTH


## The nearest pilaster box straight along `n` from `from` on the same line whose depth axis matches (facing back).
func _facing_partner(boxes: Array, from: Vector3, n: Vector3, depth_x: bool) -> Dictionary:
	var best := {}
	var best_d := 13.0
	for b_value in boxes:
		var b: Dictionary = b_value
		if String(b["kind"]) != "pilaster":
			continue
		var b_size: Vector3 = b["size"]
		if (b_size.x < b_size.z) != depth_x:
			continue
		var pos: Vector3 = (b["transform"] as Transform3D).origin
		var d := (pos - from).dot(n)
		var lateral := (pos - from - n * d)
		lateral.y = 0.0
		if d > 1.0 and d < best_d and lateral.length() < .02:
			best_d = d
			best = {"pos": pos}
	return best


## Every grid cell on the straight line between two pilaster centres is open floor.
func _open_between(grid: Array, from: Vector3, to: Vector3, n: Vector3) -> bool:
	var length := (to - from).dot(n)
	var d := PILASTER_DEPTH_FULL
	while d < length - PILASTER_DEPTH_FULL:
		var p := from + n * d
		var x := floori(p.x)
		var z := floori(p.z)
		if z < 0 or x < 0 or z >= grid.size() or x >= (grid[z] as Array).size() or int(grid[z][x]) != 0:
			return false
		d += .4
	return true
