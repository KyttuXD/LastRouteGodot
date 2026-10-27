class_name PlacementClearance
extends RefCounted

## Deterministic walkway clean-up run on every generated chunk after its props are placed (host and guests compute the
## same chunk, so they get the same result; nothing here is random).
##
##  1. Door keep-clear zones: no solid prop may reach into the 1.5 m either side of a room door, across its width.
##  2. Walk-through: from each door, a capsule with a margin (CollisionWorld.MARGIN_RADIUS) must reach the room's floor;
##     a prop that blocks the door or splits off a pocket of 1 m2 or more is removed, most separating prop first.
##
## Props are removed, not moved: a missing sideboard is better than a room nobody can enter. The removal count is kept
## small by placement rules upstream; docs/COLLISION.md has the numbers.

const POCKET_AREA_LIMIT := 1.0
const MAX_REMOVALS_PER_DOOR := 8
const SAMPLE := 0.5


static func clear(grid: Array, rooms: Array, region_props: Array) -> Array:
	var props := region_props
	# 1. keep-clear zones
	var world := _world(grid, props)
	var doomed := {}
	for violation in world.zone_violations():
		doomed[String(violation["id"])] = true
	if not doomed.is_empty():
		props = _without(props, doomed)
		world = _world(grid, props)
	# 2. walk-through, door by door
	var room_by_id := {}
	for room in rooms:
		room_by_id[String(room.get("id", ""))] = room
	for door in world.doors:
		var room: Dictionary = room_by_id.get(String(door.get("room_id", "")), {})
		if room.is_empty():
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		if not _has_props_in(world, rect):
			continue
		for _round in MAX_REMOVALS_PER_DOOR:
			var culprit := _blocking_prop(world, door, rect)
			if culprit.is_empty():
				break
			doomed = {culprit: true}
			props = _without(props, doomed)
			world = _world(grid, props)
	return _drop_orphans(props) if props.size() != region_props.size() else props


## A monitor or lamp whose desk/table was removed would float: drop surface props that lost every parent.
static func _drop_orphans(props: Array) -> Array:
	var kept := []
	for prop in props:
		var prop_type := String(prop.get("type", ""))
		if RoomCatalog.is_surface_prop(prop_type) and float(prop.get("mount_y", 0.0)) > 0.0:
			var seated := false
			for other in props:
				if RoomCatalog.surface_parent_covers(other, prop):
					seated = true
					break
			if not seated:
				continue
		kept.append(prop)
	return kept


static func _world(grid: Array, props: Array) -> CollisionWorld:
	var world := CollisionWorld.from_chunk({"grid": grid, "region_props": props})
	world.step = CollisionWorld.COARSE_STEP
	return world


static func _without(props: Array, doomed: Dictionary) -> Array:
	var kept := []
	for prop in props:
		if not doomed.has(String(prop.get("id", ""))):
			kept.append(prop)
	return kept


static func _has_props_in(world: CollisionWorld, rect: Rect2i) -> bool:
	var area := Rect2(rect).grow(1.0)
	for prop in world.rects:
		if area.has_point(prop["center"]):
			return true
	return false


## Raster walk-through for one door: points every STEP metres, a point is free when a capsule of `radius` fits there.
## Walls and props are stamped onto the raster expanded by the radius (square corners: slightly stricter than the exact
## test the validator uses, never looser), then one flood from the hall side of the door.
class Raster:
	var origin := Vector2.ZERO
	var width := 0
	var height := 0
	var blocked := PackedByteArray()
	var step := 0.5

	func _init(area: Rect2, raster_step: float) -> void:
		origin = area.position
		step = raster_step
		width = int(ceil(area.size.x / step)) + 1
		height = int(ceil(area.size.y / step)) + 1
		blocked.resize(width * height)

	func stamp(rect_min: Vector2, rect_max: Vector2) -> void:
		var x0 := maxi(0, int(floor((rect_min.x - origin.x) / step)) + 1)
		var x1 := mini(width - 1, int(ceil((rect_max.x - origin.x) / step)) - 1)
		var y0 := maxi(0, int(floor((rect_min.y - origin.y) / step)) + 1)
		var y1 := mini(height - 1, int(ceil((rect_max.y - origin.y) / step)) - 1)
		for y in range(y0, y1 + 1):
			var row := y * width
			for x in range(x0, x1 + 1):
				blocked[row + x] = 1

	func key_of(p: Vector2) -> int:
		var x := clampi(roundi((p.x - origin.x) / step), 0, width - 1)
		var y := clampi(roundi((p.y - origin.y) / step), 0, height - 1)
		return y * width + x

	func point_of(key: int) -> Vector2:
		return origin + Vector2(float(key % width), float(key / width)) * step


static func _build_raster(world: CollisionWorld, area: Rect2, radius: float) -> Raster:
	var raster := Raster.new(area, world.step)
	var x0 := int(floor(area.position.x))
	var y0 := int(floor(area.position.y))
	var x1 := int(ceil(area.end.x))
	var y1 := int(ceil(area.end.y))
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			if not world.is_open_cell(Vector2i(cx, cy)):
				raster.stamp(Vector2(cx - radius, cy - radius), Vector2(cx + 1 + radius, cy + 1 + radius))
	for prop in world.local_rects:
		var half: Vector2 = prop["half"]
		var centre: Vector2 = prop["center"]
		var yaw := float(prop["yaw"])
		var quarter := absf(sin(yaw * 2.0)) < 0.02
		if quarter:
			if absf(sin(yaw)) > 0.7:
				half = Vector2(half.y, half.x)
		else:
			var reach := half.length()
			half = Vector2(reach, reach)   # a tilted box: its bounding square (rare, only 45 degree pieces)
		raster.stamp(centre - half - Vector2(radius, radius), centre + half + Vector2(radius, radius))
	return raster


## The id of the prop to drop so this door's room becomes walkable, or "" when it already is.
static func _visit(raster: Raster, reached: PackedByteArray, frontier: PackedInt32Array, key: int) -> void:
	if raster.blocked[key] == 0 and reached[key] == 0:
		reached[key] = 1
		frontier.append(key)


static func _free_near(raster: Raster, key: int) -> int:
	if raster.blocked[key] == 0:
		return key
	for d in [1, -1, raster.width, -raster.width, raster.width + 1, raster.width - 1, -raster.width + 1, -raster.width - 1]:
		var k: int = key + d
		if k >= 0 and k < raster.width * raster.height and raster.blocked[k] == 0:
			return k
	return -1


static func _near_reached(raster: Raster, reached: PackedByteArray, key: int) -> bool:
	for d in [0, 1, -1, raster.width, -raster.width, raster.width + 1, raster.width - 1, -raster.width + 1, -raster.width - 1]:
		var k: int = key + d
		if k >= 0 and k < raster.width * raster.height and reached[k] != 0:
			return true
	return false


static func _blocking_prop(world: CollisionWorld, door: Dictionary, rect: Rect2i) -> String:
	var radius := CollisionWorld.MARGIN_RADIUS
	var cell: Vector2i = door.get("cell", Vector2i.ZERO)
	var inward: Vector2i = door.get("inward", Vector2i(0, -1))
	var outward: Vector2i = door.get("outward", Vector2i(0, 1))
	var area := Rect2(Vector2(rect.position) - Vector2(1.5, 1.5), Vector2(rect.size) + Vector2(3, 3))
	world.focus(area)
	var outside := Vector2(cell) + Vector2(.5, .5) + Vector2(outward)
	var inside := Vector2(cell) + Vector2(.5, .5) + Vector2(inward)
	var raster := _build_raster(world, area, radius)
	var reached := PackedByteArray()
	reached.resize(raster.width * raster.height)
	var seed_key := _free_near(raster, raster.key_of(outside))
	if seed_key >= 0:
		var frontier := PackedInt32Array([seed_key])
		reached[seed_key] = 1
		while not frontier.is_empty():
			var current: int = frontier[frontier.size() - 1]
			frontier.resize(frontier.size() - 1)
			var cx := current % raster.width
			var cy := current / raster.width
			if cx > 0:
				_visit(raster, reached, frontier, current - 1)
			if cx < raster.width - 1:
				_visit(raster, reached, frontier, current + 1)
			if cy > 0:
				_visit(raster, reached, frontier, current - raster.width)
			if cy < raster.height - 1:
				_visit(raster, reached, frontier, current + raster.width)
	var unreached := []
	var reached_samples := []
	var room_rect := Rect2(rect)
	for key in raster.width * raster.height:
		if raster.blocked[key] != 0:
			continue
		var p := raster.point_of(key)
		if not room_rect.has_point(p):
			continue
		if reached[key] != 0:
			reached_samples.append(p)
		else:
			unreached.append(p)
	var inside_key := raster.key_of(inside)
	var door_blocked := reached[inside_key] == 0 and not _near_reached(raster, reached, inside_key)
	if not door_blocked and float(unreached.size()) * world.step * world.step < POCKET_AREA_LIMIT:
		return ""
	var probe := unreached
	if door_blocked or probe.is_empty():
		probe = [inside]
	var best := ""
	var best_score := -1
	var reach := radius + 0.55
	for prop in world.rects:
		var near_blocked := 0
		for p in probe:
			if CollisionWorld.rect_distance(p, prop) <= reach:
				near_blocked += 1
		if near_blocked == 0:
			continue
		var near_open := 0
		for p in reached_samples:
			if CollisionWorld.rect_distance(p, prop) <= reach:
				near_open += 1
		var score := mini(near_blocked, maxi(near_open, 1)) * 1000 + near_blocked
		if door_blocked:
			score += 100000 if CollisionWorld.rect_distance(inside, prop) <= reach else 0
		if score > best_score:
			best_score = score
			best = String(prop["id"])
	return best
