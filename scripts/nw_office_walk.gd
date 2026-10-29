class_name NwOfficeWalk
extends RefCounted

## The OFFICE CONTRACT's walkability check (scripts/validate_night_watch_offices.gd's capsule flood fill) as a helper, so a mode's own suite can run it on
## every variant of its office (Open Air's office is built three ways). Returns the problems found (empty when the office is walkable): the spawn blocked, the
## room split (under 90% of the free cells reachable), a station with no reachable floor within 3 m, an entrance with none within 2.5 m.

const CELL := 0.25
const CAPSULE_R := 0.3
const CAPSULE_H := 1.7


static func problems(office: NightWatchOfficeBase) -> Array:
	var out := []
	var spec := office.spec
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
	if not bool(free.get(start, false)):
		out.append("the spawn is blocked" + _blockers(office, space_state, capsule, spec.spawn))
		return out
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
	if float(seen.size()) < 0.9 * float(free_count):
		out.append("only %d of %d free cells are reachable from the spawn" % [seen.size(), free_count])
	var near := func(target_local: Vector3, radius: float) -> bool:
		for cell in seen:
			var p := Vector3(fp.position.x + (cell.x + 0.5) * CELL, 0.0, fp.position.y + (cell.y + 0.5) * CELL)
			if Vector2(p.x - target_local.x, p.z - target_local.z).length() <= radius:
				return true
		return false
	for sid in office.stations:
		if not near.call(office.to_local((office.stations[sid] as Node3D).global_position), 3.0):
			out.append("station '%s' cannot be reached" % sid)
	for e in spec.entrances:
		if not near.call(e["position"], 2.5):
			out.append("entrance '%s' cannot be reached" % e["id"])
	return out


## Who is standing on the spawn: the colliders a capsule there hits (a body left in the shared physics world by an earlier suite shows up here by path).
static func _blockers(office: Node3D, space_state: PhysicsDirectSpaceState3D, capsule: CapsuleShape3D, spawn: Vector3) -> String:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, office.global_transform * Vector3(spawn.x, CAPSULE_H * 0.5 + 0.05, spawn.z))
	q.collision_mask = 1
	var names := []
	for hit in space_state.intersect_shape(q, 4):
		var body := hit["collider"] as Node
		names.append(str(body.get_path()) if body != null and body.is_inside_tree() else str(body))
	return " (%s)" % ", ".join(names)
