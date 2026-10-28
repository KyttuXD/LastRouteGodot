extends RefCounted

## The OFFICE CONTRACT (docs/NIGHT_WATCH_OFFICES.md): every mode has its own office id (all nine different), every BUILT office loads as a NightWatchOfficeBase,
## its spec is complete, its required stations exist, it stays within the light budget, its prop groups are textured, and it is WALKABLE: a capsule flood fill from the
## spawn reaches every station (within use range) and every entrance, so nothing is walled off and nothing needs a jump or a fall. A mode whose office is not built yet
## is listed (it uses the Classic room meanwhile); once every mode has one, set REQUIRE_ALL_BUILT.

const REQUIRE_ALL_BUILT := true
const CELL := 0.25
const CAPSULE_R := 0.3
const CAPSULE_H := 1.7

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var ids := {}
	var built := []
	var planned := []
	for mode_id in NightWatchModesData.MODES.map(func(m): return String(m["id"])):
		var entry: Dictionary = NightWatchOfficeRegistry.OFFICES.get(mode_id, {})
		_expect(not entry.is_empty(), "mode %s has no office entry" % mode_id)
		if entry.is_empty():
			continue
		var oid := String(entry["id"])
		_expect(not oid.is_empty() and not ids.has(oid), "mode %s: office id '%s' is empty or already used by %s" % [mode_id, oid, str(ids.get(oid, ""))])
		ids[oid] = mode_id
		if NightWatchOfficeRegistry.built(mode_id):
			built.append(mode_id)
		else:
			planned.append(mode_id)
	if REQUIRE_ALL_BUILT:
		_expect(planned.is_empty(), "offices not built yet: %s" % str(planned))
	_expect(built.has("classic"), "the Classic office is not registered as built")
	for mode_id in built:
		await _check_office(host, mode_id)
	if _failures == 0:
		print("  night_watch_offices  %d of 9 offices built and walkable (%s); planned: %s" % [built.size(), ", ".join(PackedStringArray(built)), ", ".join(PackedStringArray(planned))])
	return _failures


func _check_office(host: Node, mode_id: String) -> void:
	var office := NightWatchOfficeRegistry.make(mode_id)
	_expect(office != null, "%s: the office script does not make a NightWatchOfficeBase" % mode_id)
	if office == null:
		return
	host.add_child(office)
	await host.get_tree().process_frame
	await host.get_tree().physics_frame
	var spec := office.spec
	for p in spec.problems():
		_expect(false, "%s: %s" % [mode_id, p])
	_expect(spec.id == NightWatchOfficeRegistry.office_id(mode_id), "%s: the spec id '%s' differs from the registry's '%s'" % [mode_id, spec.id, NightWatchOfficeRegistry.office_id(mode_id)])
	_expect(spec.mode_ids.has(mode_id) or spec.rotation.size() > 0, "%s: the spec does not name its mode" % mode_id)
	for sid in spec.required_stations:
		_expect(office.stations.has(sid), "%s: required station '%s' is missing" % [mode_id, sid])
	_expect(office.light_count() <= NightWatchOfficeSpec.MAX_REAL_LIGHTS, "%s: %d real lights on, the budget is %d" % [mode_id, office.light_count(), NightWatchOfficeSpec.MAX_REAL_LIGHTS])
	for prop_name in office.props:
		var st := NightWatchArt.prop_stats(office.props[prop_name])
		_expect(int(st["untextured"]) == 0, "%s: prop %s has untextured cubes" % [mode_id, prop_name])
	# the signature decor (bands, posters, dashes, bars, grilles) hangs on the walls: none of it stands in the walk area (the footprint, floor to head height)
	var sig := office.get_node_or_null("Signature")
	if sig != null:
		var walk := AABB(Vector3(spec.footprint.position.x, 0.05, spec.footprint.position.y), Vector3(spec.footprint.size.x, 1.75, spec.footprint.size.y))
		for node in sig.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var box: AABB = office.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			_expect(not box.intersects(walk), "%s: signature piece %s stands in the walk area (%s)" % [mode_id, mi.name, str(box)])
	# walkability: a capsule flood fill from the spawn over the footprint
	var space := (host.get_viewport().world_3d if host.get_viewport() != null else null)
	var space_state: PhysicsDirectSpaceState3D = office.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_R
	capsule.height = CAPSULE_H
	var fp := spec.footprint
	var cols := int(ceil(fp.size.x / CELL))
	var rows := int(ceil(fp.size.y / CELL))
	var free := {}
	for ix in cols:
		for iz in rows:
			var local := Vector3(fp.position.x + (ix + 0.5) * CELL, CAPSULE_H * 0.5 + 0.05, fp.position.y + (iz + 0.5) * CELL)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = capsule
			q.transform = Transform3D(Basis.IDENTITY, office.global_transform * local)
			q.collision_mask = 1
			free[Vector2i(ix, iz)] = space_state.intersect_shape(q, 1).is_empty()
	var start := Vector2i(int((spec.spawn.x - fp.position.x) / CELL), int((spec.spawn.z - fp.position.y) / CELL))
	_expect(bool(free.get(start, false)), "%s: the spawn is blocked" % mode_id)
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if free.get(n, false) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	var free_count := 0
	for k in free:
		if free[k]:
			free_count += 1
	_expect(float(seen.size()) >= 0.9 * float(free_count), "%s: only %d of %d free cells are reachable from the spawn (the room is split)" % [mode_id, seen.size(), free_count])
	var cell_pos := func(cell: Vector2i) -> Vector3:
		return Vector3(fp.position.x + (cell.x + 0.5) * CELL, 0.0, fp.position.y + (cell.y + 0.5) * CELL)
	var near := func(target_local: Vector3, radius: float) -> bool:
		for cell in seen:
			var p: Vector3 = cell_pos.call(cell)
			if Vector2(p.x - target_local.x, p.z - target_local.z).length() <= radius:
				return true
		return false
	for sid in office.stations:
		var st_local: Vector3 = office.to_local((office.stations[sid] as Node3D).global_position)
		_expect(near.call(st_local, 3.0), "%s: station '%s' cannot be reached (no reachable floor within 3 m)" % [mode_id, sid])
	for e in spec.entrances:
		_expect(near.call(e["position"], 2.5), "%s: entrance '%s' cannot be reached from the spawn" % [mode_id, e["id"]])
	office.queue_free()
	await host.get_tree().process_frame
