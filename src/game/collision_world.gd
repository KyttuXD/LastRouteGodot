class_name CollisionWorld
extends RefCounted

## The walk-through view of a generated chunk, built from the same data the 3D view builds its colliders from
## (grid walls, one box per solid prop at its placement offset and yaw, room doors as openable gaps), so a validator, the
## placement clean-up and the debug overlay all agree with what the player capsule really meets.
## Everything is in chunk-local grid metres (1 cell = 1 m, x right, y = world z).

const PLAYER_RADIUS := 0.2
## Walking lane used by the placement rules: capsule plus a margin, and a comfortable lane to doors and interactables.
const MARGIN_RADIUS := 0.3
const LANE_RADIUS := 0.4
const STEP := 0.25
## The generator clean-up runs on every chunk as it streams in, so it walks a coarser raster and only the props near the room.
const COARSE_STEP := 0.5

var grid: Array = []
var rects: Array = []
## Keep-clear zones: {rect: Rect2, door_id}
var door_zones: Array = []
## Raster step of flood()/reached_near(); validators keep the fine STEP, the generator pass sets COARSE_STEP.
var step := STEP
## When set, can_stand() only tests these boxes (the ones near the room being walked).
var local_rects: Array = []
var use_local := false
var doors: Array = []
var chunk: Dictionary = {}


static func from_chunk(data: Dictionary) -> CollisionWorld:
	var world := CollisionWorld.new()
	world.chunk = data
	world.grid = data.get("grid", [])
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if bool(prop.get("room_door", false)):
			world.doors.append(prop)
			world.door_zones.append({"rect": _door_zone(prop), "door_id": String(prop.get("id", "")), "prop": prop})
			continue
		if not bool(prop.get("solid", true)):
			continue
		var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		var offset: Vector2 = Vector2(prop.get("mount_offset", Vector2.ZERO)) + Vector2(prop.get("placement_offset", Vector2.ZERO))
		world.rects.append({
			"id": String(prop.get("id", "")), "type": String(prop.get("type", "")),
			"center": Vector2(cell) + Vector2(.5, .5) + offset,
			"half": Vector2(size.x, size.z) * .5, "yaw": float(prop.get("yaw", 0.0)), "height": size.y,
		})
	return world


## Width of the door across its wall, 1.5 m deep to each side.
static func _door_zone(door: Dictionary) -> Rect2:
	var cell: Vector2i = door.get("cell", Vector2i.ZERO)
	var inward: Vector2i = door.get("inward", Vector2i(0, -1))
	var span := float(door.get("door_span", 1))
	var across := Vector2(absf(float(inward.y)), absf(float(inward.x)))   # unit vector along the wall
	var along := Vector2(absf(float(inward.x)), absf(float(inward.y)))    # unit vector through the door
	var centre := Vector2(cell) + Vector2(.5, .5)
	var half := across * (span * .5 + .1) + along * 1.5
	return Rect2(centre - half, half * 2.0)


static func rect_distance(point: Vector2, rect: Dictionary) -> float:
	var d: Vector2 = point - Vector2(rect["center"])
	var yaw := float(rect["yaw"])
	var c := cos(yaw)
	var s := sin(yaw)
	var local := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	var half: Vector2 = rect["half"]
	var q := Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.y) - half.y, 0.0))
	return q.length()


func is_open_cell(cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < grid.size() and cell.x >= 0 and cell.x < (grid[cell.y] as Array).size() \
		and int(grid[cell.y][cell.x]) == 0


## True when a capsule of `radius` can stand at `point`: all of its disc over open cells, clear of every prop box.
func can_stand(point: Vector2, radius: float) -> bool:
	for offset in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
		var p: Vector2 = point + offset
		if not is_open_cell(Vector2i(floori(p.x), floori(p.y))):
			return false
	# diagonal corners only matter next to a wall corner: test them when the point is near a cell edge
	var fx := point.x - floorf(point.x)
	var fy := point.y - floorf(point.y)
	if fx < radius or fx > 1.0 - radius or fy < radius or fy > 1.0 - radius:
		for corner in [Vector2(radius, radius), Vector2(-radius, radius), Vector2(radius, -radius), Vector2(-radius, -radius)]:
			var q: Vector2 = point + corner * .7071
			if not is_open_cell(Vector2i(floori(q.x), floori(q.y))):
				return false
	for rect in (local_rects if use_local else rects):
		if rect_distance(point, rect) < radius:
			return false
	return true


## Restrict can_stand() to the boxes within `margin` of `area`; call with an empty area to go back to all boxes.
func focus(area: Rect2, margin: float = 1.5) -> void:
	local_rects = []
	use_local = true
	var grown := area.grow(margin)
	for rect in rects:
		var half: Vector2 = rect["half"]
		var reach := maxf(half.x, half.y) * 1.5
		if grown.grow(reach).has_point(rect["center"]):
			local_rects.append(rect)


## Flood fill over a STEP raster inside `area`, from `start`. Returns the set of reached raster keys (Vector2i).
func flood(start: Vector2, radius: float, area: Rect2) -> Dictionary:
	var origin := area.position
	var reached := {}
	var first := _snap(start, origin)
	if not can_stand(_point(first, origin), radius):
		# a start point a hair inside geometry: look one step around it
		var found := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var k := first + Vector2i(dx, dy)
				if can_stand(_point(k, origin), radius):
					first = k
					found = true
		if not found:
			return reached
	var width := int(ceil(area.size.x / step))
	var height := int(ceil(area.size.y / step))
	var frontier := [first]
	reached[first] = true
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + d
			if next.x < 0 or next.y < 0 or next.x > width or next.y > height or reached.has(next):
				continue
			if can_stand(_point(next, origin), radius):
				reached[next] = true
				frontier.append(next)
	return reached


## Every raster point of `area` where a capsule of `radius` can stand, evaluated once (the flood then only looks points up).
func standable_set(area: Rect2, radius: float) -> Dictionary:
	var out := {}
	var origin := area.position
	var width := int(ceil(area.size.x / step))
	var height := int(ceil(area.size.y / step))
	for ix in range(0, width + 1):
		for iy in range(0, height + 1):
			var k := Vector2i(ix, iy)
			if can_stand(_point(k, origin), radius):
				out[k] = true
	return out


## Flood over a precomputed standable set from the raster point nearest `start` (or a neighbour of it).
func flood_in(set: Dictionary, area: Rect2, start: Vector2) -> Dictionary:
	var reached := {}
	var first := _snap(start, area.position)
	var seed_key := Vector2i(-1, -1)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var k := first + Vector2i(dx, dy)
			if set.has(k):
				seed_key = k
				break
		if seed_key.x >= 0:
			break
	if seed_key.x < 0:
		return reached
	var frontier := [seed_key]
	reached[seed_key] = true
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + d
			if set.has(next) and not reached.has(next):
				reached[next] = true
				frontier.append(next)
	return reached


func point_of(key: Vector2i, area: Rect2) -> Vector2:
	return _point(key, area.position)


func reached_near(reached: Dictionary, area: Rect2, target: Vector2, within: float) -> bool:
	var origin := area.position
	var k := _snap(target, origin)
	var r := int(ceil(within / step))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if reached.has(k + Vector2i(dx, dy)) and _point(k + Vector2i(dx, dy), origin).distance_to(target) <= within:
				return true
	return false


func _snap(p: Vector2, origin: Vector2) -> Vector2i:
	return Vector2i(roundi((p.x - origin.x) / step), roundi((p.y - origin.y) / step))


func _point(k: Vector2i, origin: Vector2) -> Vector2:
	return origin + Vector2(k) * step


## Props whose box reaches into a door's keep-clear zone.
func zone_violations() -> Array:
	var out := []
	for zone in door_zones:
		var rect: Rect2 = zone["rect"]
		for prop in rects:
			if _rect_touches(prop, rect):
				out.append({"door": zone["door_id"], "prop": prop["type"], "id": prop["id"]})
	return out


static func _rect_touches(prop: Dictionary, zone: Rect2) -> bool:
	# sample the box corners and edge midpoints plus the centre: coarse but reliable at prop scale
	var half: Vector2 = prop["half"]
	var centre: Vector2 = prop["center"]
	if not zone.grow(half.length()).has_point(centre):
		return false
	var yaw := float(prop["yaw"])
	var c := cos(yaw)
	var s := sin(yaw)
	for sx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for sy in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var local := Vector2(half.x * sx, half.y * sy)
			var world := centre + Vector2(local.x * c + local.y * s, -local.x * s + local.y * c)
			if zone.has_point(world):
				return true
	return false
