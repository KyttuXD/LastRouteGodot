class_name PlaytestFlythrough
extends RefCounted

## Scripted camera flythroughs for Last Route (the `flythrough` playtest scenario): teleports a noclip, input-frozen player to a named area and
## glides its first-person camera along a smoothed walkable path, then cranes up and orbits for an overview. Meant to be run with Godot's Movie
## Maker (`--write-movie x.avi --fixed-fps 30`) by tools/playtest/flythrough.py; the frame range of the clip is written to the report so the
## encoder can cut away the menu and loading frames in front of it. A DEBUG run: nothing is saved.

const CHUNK := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL_HEIGHT := 4.0
const WALK_SPEED := 2.4
const WALK_SECONDS := 22.0
const ORBIT_SECONDS := 12.0
const HOLD_SECONDS := 1.0
const SEARCH_RADIUS := 40

## name -> preset. kind "district": walk a hall of the nearest chunk of that biome. "sewer_*": hand-picked sewer layouts of chunk (0,-1,0).
const AREAS := {
	"hospital": {"kind": "district", "biome": "hospital", "level": 0},
	"lab": {"kind": "district", "biome": "lab", "level": 0},
	"greenhouse": {"kind": "district", "biome": "greenhouse", "level": 0},
	"mall": {"kind": "district", "biome": "mall", "level": 0},
	"prison": {"kind": "district", "biome": "prison", "level": 0},
	"mansion": {"kind": "district", "biome": "mansion", "level": 0},
	"hotel": {"kind": "district", "biome": "hotel", "level": 0},
	"maze": {"kind": "district", "biome": "maze", "level": 0},
	"apartment": {"kind": "district", "biome": "apartment", "level": 0},
	"beach": {"kind": "district", "biome": "beach", "level": 0},
	"gothic": {"kind": "district", "biome": "gothic", "level": 0},
	"carnival": {"kind": "district", "biome": "carnival", "level": 0},
	"inferno": {"kind": "district", "biome": "inferno", "level": -3},
	"sewer_tunnels": {"kind": "sewer_tunnels"},
	"sewer_junction": {"kind": "sewer_junction"},
	"sewer_valve_room": {"kind": "sewer_room", "room": "valve_room"},
	"sewer_pump_room": {"kind": "sewer_room", "room": "pump_room"},
	"sewer_overflow": {"kind": "sewer_room", "room": "overflow_chamber"},
	"sewer_ladder": {"kind": "sewer_ladder"},
	"descent_ladder": {"kind": "maze_ladder_down"},
}

## What `flythrough.py` renders by default (the coordinator's list). The collector (-2) has no preset until it exists on main.
const DEFAULT_SET := ["hospital", "lab", "greenhouse", "mall", "prison", "mansion", "hotel", "sewer_tunnels", "sewer_junction",
	"sewer_valve_room", "sewer_ladder", "inferno"]


static func area_names() -> Array:
	return AREAS.keys()


## Walkable cells of one level read straight from the generator (surface: grid 0; sewer: dry floor or bridge deck).
class Sampler:
	var gen: StreamedRouteGenerator
	var level: int
	var _grids := {}
	## World cells covered by a solid prop collider (tables, beds, counters...): blocked like walls so tours walk AROUND them (doors are not props).
	var _props := {}

	func _init(p_gen: StreamedRouteGenerator, p_level: int) -> void:
		gen = p_gen
		level = p_level

	func open(x: int, z: int) -> bool:
		var size := StreamedRouteGenerator.CHUNK_SIZE
		var cx := floori(float(x) / size)
		var cz := floori(float(z) / size)
		var key := Vector2i(cx, cz)
		if not _grids.has(key):
			var coord := Vector3i(cx, level, cz)
			var data: Dictionary = gen.sewer().chunk(coord) if level == StreamedRouteGenerator.SEWER_LEVEL else gen.chunk(coord)
			_grids[key] = data.get("sewer_grid", data.get("grid", [])) if level == StreamedRouteGenerator.SEWER_LEVEL else data.get("grid", [])
			for prop_value in data.get("region_props", []):
				var prop: Dictionary = prop_value
				if not bool(prop.get("solid", true)) or bool(prop.get("room_door", false)):
					continue
				var occupied: Array = prop.get("occupied_cells", [])
				if occupied.is_empty():
					occupied = [prop.get("cell", Vector2i.ZERO)]
				for local_value in occupied:
					_props[Vector2i(cx * size, cz * size) + (local_value as Vector2i)] = true
		var rows: Array = _grids[key]
		if _props.has(Vector2i(x, z)):
			return false
		var lz := z - cz * size
		var lx := x - cx * size
		if lz < 0 or lz >= rows.size() or lx < 0 or lx >= (rows[lz] as Array).size():
			return false
		var code := int(rows[lz][lx])
		if level == StreamedRouteGenerator.SEWER_LEVEL:
			return code == 0 or code == 3
		return code == 0

	## Distance along `dir` (unit) from `p` to the first closed cell, capped at `max_d` (grid ray march: walls only, props are not in the grid).
	func depth(p: Vector2, dir: Vector2, max_d: float) -> float:
		var d := 0.0
		while d < max_d:
			var q := p + dir * d
			if not open(floori(q.x), floori(q.y)):
				return d
			d += .25
		return max_d

	func circle_clear(p: Vector2, r: float) -> bool:
		if not open(floori(p.x), floori(p.y)):
			return false
		for k in 8:
			var a := TAU * float(k) / 8.0
			var q := p + Vector2(cos(a), sin(a)) * r
			if not open(floori(q.x), floori(q.y)):
				return false
		return true

	## Distance to the nearest closed cell box within two cells of `p`, and the unit vector pointing away from it.
	func nearest_wall(p: Vector2) -> Array:
		var best := 99.0
		var away := Vector2.ZERO
		for cz in range(floori(p.y) - 2, floori(p.y) + 3):
			for cx in range(floori(p.x) - 2, floori(p.x) + 3):
				if open(cx, cz):
					continue
				var q := Vector2(clampf(p.x, cx, cx + 1.0), clampf(p.y, cz, cz + 1.0))
				var d := p.distance_to(q)
				if d < best:
					best = d
					away = (p - q).normalized() if d > .001 else Vector2.ZERO
		return [best, away]

	func roomy(x: int, z: int) -> int:
		var blocked := 0
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if not open(x + dx, z + dz):
					blocked += 1
		return blocked


## Cheapest-path field from `start` over open cells, cells beside walls cost more so paths run down the middle of halls.
static func path_field(s: Sampler, start: Vector2i, radius: int) -> Dictionary:
	var cost := {start: 0}
	var steps := {start: 0}
	var prev := {}
	var heap: Array = [[0, start]]
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var here: Vector2i = top[1]
		if int(top[0]) > int(cost[here]):
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = here + d
			if absi(next.x - start.x) > radius or absi(next.y - start.y) > radius or not s.open(next.x, next.y):
				continue
			var step_cost := 1 + (5 if s.roomy(next.x, next.y) > 0 else 0)
			var total := int(cost[here]) + step_cost
			if not cost.has(next) or total < int(cost[next]):
				cost[next] = total
				steps[next] = int(steps[here]) + 1
				prev[next] = here
				_heap_push(heap, [total, next])
	return {"cost": cost, "steps": steps, "prev": prev}


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if int((heap[parent] as Array)[0]) <= int((heap[i] as Array)[0]):
			break
		var swap: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < heap.size() and int((heap[l] as Array)[0]) < int((heap[m] as Array)[0]):
				m = l
			if r < heap.size() and int((heap[r] as Array)[0]) < int((heap[m] as Array)[0]):
				m = r
			if m == i:
				break
			var swap: Array = heap[m]
			heap[m] = heap[i]
			heap[i] = swap
			i = m
	return top


static func path_to(field: Dictionary, goal: Vector2i) -> Array[Vector2]:
	var cells: Array[Vector2i] = [goal]
	var prev: Dictionary = field["prev"]
	var at := goal
	while prev.has(at):
		at = prev[at]
		cells.push_front(at)
	var points: Array[Vector2] = []
	for cell in cells:
		points.append(Vector2(cell.x + .5, cell.y + .5))
	return points


## The reachable cell between min and max path steps that lies farthest (straight line) from the start: a walk that goes somewhere instead of doubling back.
static func far_goal(field: Dictionary, start: Vector2i, min_steps: int, max_steps: int) -> Vector2i:
	var best := start
	var best_distance := -1.0
	var steps: Dictionary = field["steps"]
	for cell_value in steps:
		var cell: Vector2i = cell_value
		var n := int(steps[cell])
		if n < min_steps or n > max_steps:
			continue
		var d := Vector2(cell).distance_to(Vector2(start))
		if d > best_distance:
			best_distance = d
			best = cell
	return best


static func chaikin(points: Array[Vector2], rounds: int) -> Array[Vector2]:
	var current: Array[Vector2] = points
	for _r in rounds:
		if current.size() < 3:
			break
		var next: Array[Vector2] = [current[0]]
		for i in current.size() - 1:
			next.append(current[i].lerp(current[i + 1], .25))
			next.append(current[i].lerp(current[i + 1], .75))
		next.append(current[current.size() - 1])
		current = next
	return current


static func resample(points: Array[Vector2], step: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if points.is_empty():
		return out
	out.append(points[0])
	var carried := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var at := step - carried
		while at <= length:
			out.append(a.lerp(b, at / length))
			at += step
		carried = length - (at - step)
	return out


static func yaw_for(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)


static func pitch_for(direction: Vector3) -> float:
	return asin(clampf(direction.normalized().y, -1.0, 1.0))


## One baked camera track: positions are CAMERA (eye) positions.
class Track:
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var pitch := PackedFloat32Array()
	## 1 = a walking frame: pos.y is the eye height ABOVE the physics floor (the scenario ray-casts the real collision floor, so ramps, bridges and
	## stairs are followed); 0 = a flying frame: pos.y is an absolute world y.
	var ground := PackedByteArray()
	## Spring-arm pivot of a flying frame (the point the camera orbits / looks from): the camera is pulled in toward it when geometry is in the way. INF = none.
	var pivot := PackedVector3Array()
	## frame -> event dictionary (a real ladder climb the scenario plays through the game's own ladder).
	var events := {}
	## Frame indexes where the picture cuts to a new shot: angles are not smoothed across them.
	var cuts: Array[int] = []

	func add(p: Vector3, y: float, pt: float, on_ground: int = 0, pv: Vector3 = Vector3.INF) -> void:
		pivot.append(pv)
		pos.append(p)
		yaw.append(y)
		pitch.append(pt)
		ground.append(on_ground)

	func hold(count: int) -> void:
		if pos.is_empty():
			return
		for _i in count:
			add(pos[pos.size() - 1], yaw[yaw.size() - 1], pitch[pitch.size() - 1], ground[ground.size() - 1])

	func size() -> int:
		return pos.size()

	## The last camera position with y as an absolute world y (a walking frame stores the height above the floor).
	func last_absolute(floor_y: float) -> Vector3:
		var p := pos[pos.size() - 1]
		return Vector3(p.x, p.y + (floor_y if ground[ground.size() - 1] == 1 else 0.0), p.z)


## A point of interest the camera likes to look at: world xz, look height above the floor, weight.
static func poi(x: float, z: float, height: float, weight: float, kind: String) -> Dictionary:
	return {"p": Vector2(x, z), "h": height, "w": weight, "kind": kind}


## Line-of-sight pruning: drop every waypoint the straight segment can skip while a body of radius `margin` stays clear of the walls.
static func string_pull(points: Array[Vector2], s: Sampler, margin: float) -> Array[Vector2]:
	if points.size() < 3:
		return points
	var out: Array[Vector2] = [points[0]]
	var i := 0
	while i < points.size() - 1:
		var far := i + 1
		for j in range(points.size() - 1, i, -1):
			if _segment_clear(points[i], points[j], s, margin):
				far = j
				break
		out.append(points[far])
		i = far
	return out


static func _segment_clear(a: Vector2, b: Vector2, s: Sampler, margin: float) -> bool:
	var length := a.distance_to(b)
	var steps := maxi(int(length / .2), 1)
	for k in steps + 1:
		if not s.circle_clear(a.lerp(b, float(k) / float(steps)), margin):
			return false
	return true


## Catmull-Rom through the pruned points, sampled about every 5 cm: straight runs stay straight, corners take a rounded turn.
static func catmull(points: Array[Vector2], spacing: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in points.size() - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		var n := maxi(int(p1.distance_to(p2) / spacing), 2)
		for k in n:
			var t := float(k) / float(n)
			var t2 := t * t
			var t3 := t2 * t
			out.append(.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[points.size() - 1])
	return out


## Keep the path `want` metres off the walls where the hall is wide enough (a one-cell doorway keeps its centre line).
static func push_clear(path: Array[Vector2], s: Sampler, want: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for point in path:
		var p := point
		for _k in 3:
			var wall := s.nearest_wall(p)
			var d: float = wall[0]
			if d >= want or (wall[1] as Vector2) == Vector2.ZERO:
				break
			var moved := p + (wall[1] as Vector2) * (want - d)
			if (s.nearest_wall(moved)[0] as float) > d:
				p = moved
			else:
				break
		out.append(p)
	return out


static func moving_average(path: Array[Vector2], window: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in path.size():
		var sum := Vector2.ZERO
		var n := 0
		for k in range(maxi(i - window, 0), mini(i + window, path.size() - 1) + 1):
			sum += path[k]
			n += 1
		out.append(sum / float(n))
	return out


## Cell-centre route -> a smooth, clear, rounded path (about 5 cm spacing).
static func smooth_route(cells: Array[Vector2], s: Sampler) -> Array[Vector2]:
	var pruned := string_pull(cells, s, .42)
	var dense := catmull(pruned, .05)
	dense = push_clear(dense, s, .6)
	return moving_average(moving_average(dense, 12), 12)


## Walking speed along the path: slower in tight turns, gentle acceleration from rest and deceleration to rest.
static func speed_profile(path: Array[Vector2], spacing: float, vmax: float, accel: float) -> PackedFloat32Array:
	var n := path.size()
	var v := PackedFloat32Array()
	v.resize(n)
	var span := maxi(int(1.4 / spacing), 1)
	for i in n:
		var a := path[maxi(i - span, 0)]
		var b := path[i]
		var c := path[mini(i + span, n - 1)]
		var angle := absf(wrapf((c - b).angle() - (b - a).angle(), -PI, PI))
		var curvature := angle / (2.0 * span * spacing)
		v[i] = clampf(vmax / (1.0 + 3.0 * curvature), .9, vmax)
	v[0] = .35
	v[n - 1] = .0
	for i in range(1, n):
		v[i] = minf(v[i], sqrt(v[i - 1] * v[i - 1] + 2.0 * accel * spacing))
	for i in range(n - 2, -1, -1):
		v[i] = minf(v[i], sqrt(v[i + 1] * v[i + 1] + 2.0 * accel * spacing))
	return v


## Walk the route like a player would: player walking speed with gentle acceleration, yaw following the direction of travel with a slight lead and
## damping, eased glances at points of interest (never into a wall closer than 3 m), optional head bob. Frames are appended to `track`.
static func bake_walk(track: Track, route: Array[Vector2], s: Sampler, pois: Array, fps: int, bob: bool = true, start_yaw: float = NAN) -> void:
	if route.size() < 2:
		return
	var spacing := .05
	var path := smooth_route(route, s)
	var speed := speed_profile(path, spacing, WALK_SPEED, 1.1)
	var dt := 1.0 / float(fps)
	var look_ahead := int(3.0 / spacing)
	var index := 0.0
	var travelled := 0.0
	var yaw_now := start_yaw if not is_nan(start_yaw) else yaw_for((path[mini(look_ahead, path.size() - 1)] - path[0]).x, (path[mini(look_ahead, path.size() - 1)] - path[0]).y)
	var pitch_now := 0.0
	var aim_w := 0.0
	var current: Dictionary = {}
	var lost := 0.0
	while int(index) < path.size() - 1:
		var i := int(index)
		var here := path[i]
		var ahead := path[mini(i + look_ahead, path.size() - 1)]
		# a wall straight ahead of the current view (a corner coming up): look at the exit of the turn instead, 4.5 m down the path
		var view_dir := Vector2(-sin(yaw_now), -cos(yaw_now))
		if s.depth(here, view_dir, 3.0) < 2.5:
			ahead = path[mini(i + int(4.5 / spacing), path.size() - 1)]
		var heading := (ahead - here)
		if heading.length() < .05:
			heading = (path[path.size() - 1] - here)
		var travel_yaw := yaw_for(heading.x, heading.y) if heading.length() > .001 else yaw_now
		var heading_unit := heading.normalized() if heading.length() > .001 else Vector2(-sin(yaw_now), -cos(yaw_now))
		# choose / keep a point of interest: close, inside the view cone, with a clear line of sight
		var valid := false
		if not current.is_empty():
			valid = _poi_visible(current, here, heading_unit, s, 11.0)
		if not valid:
			var best := {}
			var best_score := -1.0
			for candidate in pois:
				if _poi_visible(candidate, here, heading_unit, s, 9.0):
					var score := float(candidate["w"]) / maxf((candidate["p"] as Vector2).distance_to(here), 1.0)
					if score > best_score:
						best_score = score
						best = candidate
			if best.is_empty():
				lost += dt
				if lost > .6:
					current = {}
			else:
				current = best
				lost = 0.0
		else:
			lost = 0.0
		var wants_poi := not current.is_empty() and lost <= .6
		aim_w = clampf(aim_w + (dt / .9 if wants_poi else -dt / .9), 0.0, 1.0)
		var aim_yaw := travel_yaw
		var aim_pitch := 0.0
		if not current.is_empty():
			var to_poi := (current["p"] as Vector2) - here
			var poi_yaw := yaw_for(to_poi.x, to_poi.y)
			var weight := aim_w * .85
			# never point the camera into a wall closer than 3 m: no glance if the glance direction is walled off
			var glance_dir := Vector2(-sin(lerp_angle(travel_yaw, poi_yaw, weight)), -cos(lerp_angle(travel_yaw, poi_yaw, weight)))
			if s.depth(here, glance_dir, 3.0) < 3.0 and to_poi.length() > 3.0:
				weight = 0.0
			aim_yaw = lerp_angle(travel_yaw, poi_yaw, weight)
			aim_pitch = clampf(atan2(float(current["h"]) - 1.6, maxf(to_poi.length(), 1.0)), -.5, .5) * weight
		# damped, rate-limited follow (no snapping): about 1.1 rad/s at most
		var yaw_diff := wrapf(aim_yaw - yaw_now, -PI, PI)
		var yaw_rate := 1.3 if open_view_ok(s, here, yaw_now) else 2.0
		yaw_now += clampf(yaw_diff * 3.5 * dt, -yaw_rate * dt, yaw_rate * dt)
		pitch_now += clampf((aim_pitch - pitch_now) * 3.0 * dt, -.6 * dt, .6 * dt)
		var bob_y := sin(travelled * TAU / .95) * .022 if bob else 0.0
		track.add(Vector3(here.x, 1.6 + bob_y, here.y), yaw_now, pitch_now, 1)
		# a wall in the view ahead (the corner is coming and the turn is not done): wait for the turn, then go on
		var open_ahead := s.depth(here, Vector2(-sin(yaw_now), -cos(yaw_now)), 3.0)
		var v := speed[i] * clampf((open_ahead - 1.1) / 1.6, .2, 1.0)
		travelled += v * dt
		index += maxf(v, .05) * dt / spacing
	# arrive: ease to a stop, still looking where the glance was
	for _k in int(.5 * float(fps)):
		track.add(Vector3(path[path.size() - 1].x, 1.6, path[path.size() - 1].y), yaw_now, pitch_now, 1)


static func open_view_ok(s: Sampler, here: Vector2, yaw_value: float) -> bool:
	return s.depth(here, Vector2(-sin(yaw_value), -cos(yaw_value)), 3.0) >= 2.2


static func _poi_visible(candidate: Dictionary, here: Vector2, heading: Vector2, s: Sampler, max_d: float) -> bool:
	var to_poi: Vector2 = (candidate["p"] as Vector2) - here
	var d := to_poi.length()
	if d < 1.5 or d > max_d:
		return false
	if absf(heading.angle_to(to_poi)) > deg_to_rad(75.0):
		return false
	return s.depth(here, to_poi / d, d) >= d - .35


## Orbit `center` starting from the camera's current spot, rising/zooming to `to_height`/`to_radius`; always looking at the centre at `look_y`.
static func bake_orbit(track: Track, center: Vector3, degrees: float, seconds: float, to_height: float, to_radius: float, look_y: float, fps: int) -> void:
	var from := track.last_absolute(center.y)
	var rel := Vector2(from.x - center.x, from.z - center.z)
	var r0 := rel.length()
	var a0 := atan2(rel.y, rel.x) if r0 > .001 else 0.0
	var frames := int(seconds * fps)
	for i in frames:
		var t := float(i + 1) / float(frames)
		var e := t * t * (3.0 - 2.0 * t)
		var a := a0 + deg_to_rad(degrees) * e
		var r := lerpf(r0, to_radius, e)
		var h := lerpf(from.y, to_height, e)
		var p := Vector3(center.x + cos(a) * r, h, center.z + sin(a) * r)
		var d := Vector3(center.x, look_y, center.z) - p
		if Vector2(d.x, d.z).length() < .8:
			# on top of the centre there is no direction to look in: keep the last view until the orbit opens out
			track.add(p, track.yaw[track.yaw.size() - 1], track.pitch[track.pitch.size() - 1])
		else:
			track.add(p, yaw_for(d.x, d.z), pitch_for(d), 0, Vector3(center.x, center.y + 1.2, center.z))


## A hard cut to an overview: starts high and wide on the side of `center` the walk ended on, then orbits slowly and drifts a little higher.
static func bake_overview(track: Track, center: Vector3, from_xz: Vector2, degrees: float, seconds: float, height: float, radius: float, fps: int) -> void:
	track.cuts.append(track.size())
	var a0 := atan2(from_xz.y - center.z, from_xz.x - center.x)
	var frames := int(seconds * fps)
	for i in frames:
		var t := float(i + 1) / float(frames)
		var e := t * t * (3.0 - 2.0 * t)
		var a := a0 + deg_to_rad(degrees) * e
		var r := radius * (1.0 + .12 * e)
		var h := height * (1.0 + .25 * e)
		var p := Vector3(center.x + cos(a) * r, h, center.z + sin(a) * r)
		var d := Vector3(center.x, center.y + 1.0, center.z) - p
		track.add(p, yaw_for(d.x, d.z), pitch_for(d), 0, Vector3(center.x, center.y + 1.2, center.z))


static func bake_rise(track: Track, xz_from: Vector2, xz_to: Vector2, from_y: float, to_y: float, seconds: float, face: Vector2, up_pitch: float, fps: int) -> void:
	var frames := int(seconds * fps)
	var yaw_value := yaw_for(face.x, face.y)
	var pitch_from := track.pitch[track.pitch.size() - 1]
	for i in frames:
		var t := float(i + 1) / float(frames)
		var e := t * t * (3.0 - 2.0 * t)
		var xz := xz_from.lerp(xz_to, minf(e * 2.0, 1.0))
		track.add(Vector3(xz.x, lerpf(from_y, to_y, e), xz.y), yaw_value, lerpf(pitch_from, up_pitch, minf(t * 4.0, 1.0)))


## Stand still and turn on the spot (look back down a tunnel, look round at the top of a ladder).
static func bake_turn(track: Track, degrees: float, seconds: float, pitch: float, fps: int) -> void:
	var at := track.pos[track.pos.size() - 1]
	var yaw0 := track.yaw[track.yaw.size() - 1]
	var frames := int(seconds * fps)
	for i in frames:
		var t := float(i + 1) / float(frames)
		var e := t * t * (3.0 - 2.0 * t)
		track.add(at, yaw0 + deg_to_rad(degrees) * e, lerpf(track.pitch[track.pitch.size() - 1], pitch, .08), track.ground[track.ground.size() - 1])


## Low-pass the view angles (unwrapped) so joins between segments turn smoothly instead of snapping.
static func smooth_angles(track: Track, fps: int, seconds: float) -> void:
	var bounds: Array[int] = [0]
	bounds.append_array(track.cuts)
	bounds.append(track.size())
	for b in bounds.size() - 1:
		_smooth_range(track, bounds[b], bounds[b + 1], fps, seconds)


static func _smooth_range(track: Track, from_i: int, to_i: int, fps: int, seconds: float) -> void:
	if to_i - from_i < 2:
		return
	var k := 1.0 - exp(-1.0 / (float(fps) * seconds))
	var yaw_now := track.yaw[from_i]
	var pitch_now := track.pitch[from_i]
	for i in range(from_i, to_i):
		var target_yaw := track.yaw[i]
		while target_yaw - yaw_now > PI:
			target_yaw -= TAU
		while target_yaw - yaw_now < -PI:
			target_yaw += TAU
		yaw_now += (target_yaw - yaw_now) * k
		pitch_now += (track.pitch[i] - pitch_now) * k
		track.yaw[i] = yaw_now
		track.pitch[i] = pitch_now


# ----------------------------------------------------------------------------------------------------------------------------------
# area resolution

static func _chunk_start(coord: Vector2i) -> Vector2i:
	return Vector2i(coord.x * CHUNK, coord.y * CHUNK)


## Find the chunk of `biome` on `level` nearest the spawn, preferring region interiors; returns {} when the build has none within the search radius.
static func find_biome_chunk(gen: StreamedRouteGenerator, biome: String, level: int, variant: int = 0) -> Dictionary:
	var best := {}
	var best_score := 1e9
	var candidates: Array = []
	for cz in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for cx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			var coord := Vector3i(cx, level, cz)
			if not gen.is_chunk_allowed(coord) or gen.biome_for(coord) != biome or gen.is_safe_room(coord):
				continue
			var rx := posmod(cx, StreamedRouteGenerator.BIOME_REGION_SIZE)
			var rz := posmod(cz, StreamedRouteGenerator.BIOME_REGION_SIZE)
			var interior := (rx == 1 or rx == 2) and (rz == 1 or rz == 2)
			var score := float(absi(cx) + absi(cz)) + (0.0 if interior else 30.0)
			candidates.append([score, coord])
	candidates.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	if candidates.is_empty():
		return {}
	# a retry (variant) takes the next-nearest region interior instead of the same chunk
	return {"coord": (candidates[mini(variant * 3, candidates.size() - 1)] as Array)[1]}


## Tour waypoints through the layout: the hall start, then (doorway, centre) of a few rooms, ending where the walk has covered about `budget` metres.
static func _tour_cells(s: Sampler, data: Dictionary, base: Vector2i, start: Vector2i, budget: float, variant: int) -> Dictionary:
	var rooms: Array = []
	for room in data.get("rooms", []):
		rooms.append(room)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	# nearest first for variant 0, shuffled for the retries
	rooms.sort_custom(func(a, b): return (base + (a["center"] as Vector2i)).distance_to(start) < (base + (b["center"] as Vector2i)).distance_to(start))
	if variant > 0:
		for i in range(rooms.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap = rooms[i]
			rooms[i] = rooms[j]
			rooms[j] = swap
	var legs: Array[Vector2] = []
	var at := start
	var total := 0.0
	var visited: Array = []
	for room in rooms:
		if total >= budget or visited.size() >= 6:
			break
		var centre: Vector2i = _nearest_open(s, base + (room["center"] as Vector2i), false)
		var door: Vector2i = _nearest_open(s, base + (room["doorway"] as Vector2i), false) if room.has("doorway") else centre
		var field := path_field(s, at, 80)
		var field_ok: bool = field["cost"].has(door) and field["cost"].has(centre)
		if not field_ok:
			continue
		var leg := path_to(field, door)
		var field2 := path_field(s, door, 40)
		if not field2["cost"].has(centre):
			continue
		leg.append_array(path_to(field2, centre))
		if total > 0.0 and leg.size() + total > budget * 1.5:
			continue
		legs.append_array(leg)
		total += leg.size()
		at = centre
		visited.append(String(room.get("room_type", "room")))
	if total < budget and not legs.is_empty():
		# still short: finish with a walk down the halls from the last room to the farthest reachable spot
		var tail_field := path_field(s, at, 70)
		var tail_goal := far_goal(tail_field, at, mini(int((budget - total) * .6), 40), int(budget - total) + 40)
		if tail_goal == at:
			tail_goal = far_goal(tail_field, at, 6, 120)
		if tail_goal != at:
			legs.append_array(path_to(tail_field, tail_goal))
			visited.append("hall")
	return {"cells": legs, "rooms": visited, "length": total}


## Points of interest of a district chunk: room centres, relays, the district's signature props.
static func _chunk_pois(data: Dictionary, base: Vector2i) -> Array:
	var out: Array = []
	for room in data.get("rooms", []):
		var c: Vector2i = base + (room["center"] as Vector2i)
		out.append(poi(c.x + .5, c.y + .5, 1.2, 1.0, "room:%s" % room.get("room_type", "")))
	for pick in data.get("pickups", []):
		if String(pick.get("kind", "")) == "relay":
			var c: Vector2i = base + (pick["cell"] as Vector2i)
			out.append(poi(c.x + .5, c.y + .5, .9, 1.3, "relay"))
	var boring := ["ceilingLight", "rug", "lampPost", "wallLight"]
	var seen := {}
	for prop in data.get("region_props", []):
		var type := String(prop.get("type", ""))
		if boring.has(type) or int(seen.get(type, 0)) >= 3:
			continue
		seen[type] = int(seen.get(type, 0)) + 1
		var c: Vector2i = base + (prop["cell"] as Vector2i)
		out.append(poi(c.x + .5, c.y + .5, 1.0, .8, "prop:%s" % type))
	return out


## Build the camera track of an area. Returns {"ok", "track", "info"}; "info" says where it went (chunk, level, biome, rooms toured, planned tight spots).
## `variant` picks a different tour (the renderer retries a boring clip with the next variant).
static func plan(gen: StreamedRouteGenerator, area: String, fps: int, seconds_override: float, variant: int = 0, bob: bool = true) -> Dictionary:
	if not AREAS.has(area):
		return {"ok": false, "error": "unknown area '%s' (have: %s)" % [area, ", ".join(area_names())]}
	var preset: Dictionary = AREAS[area]
	var kind := String(preset["kind"])
	var track := Track.new()
	var info := {"area": area, "kind": kind, "variant": variant}
	var walk_seconds := WALK_SECONDS if seconds_override <= 0.0 else maxf(seconds_override - ORBIT_SECONDS - HOLD_SECONDS, 6.0)
	var sampler: Sampler = null
	match kind:
		"district":
			var level := int(preset["level"])
			var found := find_biome_chunk(gen, String(preset["biome"]), level, variant)
			if found.is_empty():
				return {"ok": false, "error": "this build has no '%s' district on level %d within %d chunks of the spawn" % [preset["biome"], level, SEARCH_RADIUS], "unavailable": true}
			var coord: Vector3i = found["coord"]
			var s := Sampler.new(gen, level)
			sampler = s
			var data: Dictionary = gen.chunk(coord)
			var base := _chunk_start(Vector2i(coord.x, coord.z))
			var start := _nearest_open(s, base + Vector2i(CHUNK / 2, CHUNK / 2))
			var floor_y := float(level) * LEVEL_HEIGHT
			var centre := Vector3(base.x + CHUNK * .5, floor_y, base.y + CHUNK * .5)
			# 1. establishing shot: a slow high orbit over the whole district chunk
			bake_overview(track, centre, Vector2(start) + Vector2(.5, .5), 60.0, 6.0, floor_y + 8.0, 13.0, fps)
			# 2. the tour: down the halls, through doorways, into rooms, looking at what is in them
			var tour := _tour_cells(s, data, base, start, walk_seconds * 2.8, variant)
			var cells: Array[Vector2] = []
			for c in (tour["cells"] as Array[Vector2]):
				cells.append(c)
			if cells.size() < 8:
				# a chunk with no usable rooms: a long hall walk instead
				var field := path_field(s, start, 70)
				var goal := far_goal(field, start, 30, int(walk_seconds * 2.0))
				cells = path_to(field, goal)
			track.cuts.append(track.size())
			bake_walk(track, cells, s, _chunk_pois(data, base), fps, bob)
			if track.size() < 40:
				return {"ok": false, "error": "no walkable route from the middle of chunk %s" % coord}
			info.merge({"level": level, "chunk": [coord.x, coord.z], "biome": gen.biome_for(coord), "start": [start.x, start.y], "rooms": tour["rooms"], "path_cells": cells.size()})
		"sewer_tunnels":
			var s := Sampler.new(gen, -1)
			sampler = s
			var start := Vector2i(19, 2)
			var goal := Vector2i(19, 2 + int(walk_seconds * 2.0))
			var field := path_field(s, start, 90)
			if not field["cost"].has(goal):
				return {"ok": false, "error": "sewer tunnel lane is not walkable end to end"}
			var pois := _sewer_pois(gen, [Vector2i(0, 0), Vector2i(0, 1)])
			bake_walk(track, path_to(field, goal), s, pois, fps, bob)
			bake_turn(track, 180.0, ORBIT_SECONDS * .7, -.05, fps)
			info.merge({"level": -1, "chunk": [0, 0], "start": [start.x, start.y], "goal": [goal.x, goal.y]})
		"sewer_junction":
			var s := Sampler.new(gen, -1)
			sampler = s
			var start := Vector2i(19, 4)
			var field := path_field(s, start, 40)
			var floor_y := -LEVEL_HEIGHT
			bake_walk(track, path_to(field, Vector2i(19, 19)), s, _sewer_pois(gen, [Vector2i(0, 0)]), fps, bob)
			bake_orbit(track, Vector3(CHUNK / 2 + .5, floor_y, CHUNK / 2 + .5), 330.0, maxf(walk_seconds, 14.0) - 2.0, floor_y + 3.0, 4.2, floor_y + 1.0, fps)
			info.merge({"level": -1, "chunk": [0, 0], "start": [start.x, start.y]})
		"sewer_room":
			var wanted := String(preset["room"])
			var room := {}
			for cz in range(-4, 5):
				for cx in range(-4, 5):
					if not room.is_empty():
						break
					var chunk_data: Dictionary = gen.sewer().chunk(Vector3i(cx, -1, cz))
					for entry in chunk_data.get("rooms", []):
						if String(entry["room_type"]) == wanted:
							room = {"chunk": Vector2i(cx, cz), "centre": entry["center"], "rect": entry["rect"]}
							break
			if room.is_empty():
				return {"ok": false, "error": "no '%s' within four chunks of the origin on this seed" % wanted, "unavailable": true}
			var base := _chunk_start(room["chunk"])
			var junction := base + Vector2i(19, 19)
			var s := Sampler.new(gen, -1)
			sampler = s
			var centre: Vector2i = base + (room["centre"] as Vector2i)
			var walk_to := _nearest_open(s, centre, false)
			var field := path_field(s, junction, 60)
			var floor_y := -LEVEL_HEIGHT
			if not field["cost"].has(walk_to):
				return {"ok": false, "error": "room centre %s not reachable from the junction" % centre}
			bake_walk(track, path_to(field, walk_to), s, _sewer_pois(gen, [room["chunk"]]), fps, bob)
			bake_orbit(track, Vector3(centre.x + .5, floor_y, centre.y + .5), 300.0, ORBIT_SECONDS + 4.0, floor_y + 2.4, 3.6, floor_y + 1.0, fps)
			info.merge({"level": -1, "chunk": [room["chunk"].x, room["chunk"].y], "room": wanted, "start": [junction.x, junction.y], "goal": [centre.x, centre.y]})
		"maze_ladder_down":
			var link := {}
			var chunk_of := Vector2i.ZERO
			for cz in range(-4, 5):
				for cx in range(-4, 5):
					if not link.is_empty():
						break
					var links: Array = gen.sewer().chunk(Vector3i(cx, -1, cz)).get("links", [])
					if not links.is_empty():
						link = links[0]
						chunk_of = Vector2i(cx, cz)
			if link.is_empty():
				return {"ok": false, "error": "no sewer ladder within four chunks of the origin", "unavailable": true}
			var base := _chunk_start(chunk_of)
			var manhole: Vector2i = base + (link["from_cell"] as Vector2i)
			var s := Sampler.new(gen, 0)
			sampler = s
			var start := _nearest_open(s, base + Vector2i(CHUNK / 2, CHUNK / 2))
			var field := path_field(s, start, 70)
			var goal := _nearest_open(s, manhole, false)
			if not field["cost"].has(goal):
				return {"ok": false, "error": "manhole %s not reachable from the middle of its chunk" % manhole}
			var pois: Array = _chunk_pois(gen.chunk(Vector3i(chunk_of.x, 0, chunk_of.y)), base)
			pois.append(poi(manhole.x + .5, manhole.y + .5, 0.0, 2.0, "manhole"))
			bake_walk(track, path_to(field, goal), s, pois, fps, bob)
			track.hold(fps)
			track.events[track.size()] = {"ladder": true, "at": Vector2(manhole.x + .5, manhole.y + .5), "level": 0, "down": true}
			track.add(track.pos[track.size() - 1], track.yaw[track.yaw.size() - 1], 0.0, 2)
			bake_turn(track, 120.0, ORBIT_SECONDS * .5, 0.0, fps)
			info.merge({"level": 0, "chunk": [chunk_of.x, chunk_of.y], "manhole": [manhole.x, manhole.y]})
		"sewer_ladder":
			var link := {}
			var chunk_of := Vector2i.ZERO
			for cz in range(-4, 5):
				for cx in range(-4, 5):
					if not link.is_empty():
						break
					var links: Array = gen.sewer().chunk(Vector3i(cx, -1, cz)).get("links", [])
					if not links.is_empty():
						link = links[0]
						chunk_of = Vector2i(cx, cz)
			if link.is_empty():
				return {"ok": false, "error": "no sewer ladder within four chunks of the origin", "unavailable": true}
			var base := _chunk_start(chunk_of)
			var up: Vector2i = base + (link["to_cell"] as Vector2i)
			var wall: Vector2i = link.get("wall", Vector2i(0, -1))
			var chamber := up - wall
			var s := Sampler.new(gen, -1)
			sampler = s
			var field := path_field(s, base + Vector2i(CHUNK / 2, CHUNK / 2), 60)
			if not field["cost"].has(chamber):
				return {"ok": false, "error": "ladder chamber %s not reachable from the junction" % chamber}
			var floor_y := -LEVEL_HEIGHT
			var pois := _sewer_pois(gen, [chunk_of])
			pois.append(poi(up.x + .5, up.y + .5, 2.2, 1.6, "ladder"))
			bake_walk(track, path_to(field, chamber), s, pois, fps, bob)
			track.hold(fps)
			# the climb itself is the game's: the scenario stands the player on the ladder, holds up, and the real controller mounts, climbs and dismounts
			track.events[track.size()] = {"ladder": true, "at": Vector2(up.x + .5, up.y + .5), "level": -1, "down": false}
			track.add(track.pos[track.size() - 1], track.yaw[track.yaw.size() - 1], 0.0, 2)
			bake_turn(track, 300.0, ORBIT_SECONDS * .8, 0.0, fps)
			info.merge({"level": -1, "chunk": [chunk_of.x, chunk_of.y], "ladder_cell": [up.x, up.y], "wall": [wall.x, wall.y]})
	smooth_angles(track, fps, .45)
	var first_pos := track.pos[0]
	var first_yaw := track.yaw[0]
	var first_pitch := track.pitch[0]
	var first_ground := track.ground[0]
	var padded := Track.new()
	for _i in int(HOLD_SECONDS * fps):
		padded.add(first_pos, first_yaw, first_pitch, first_ground)
	for cut in track.cuts:
		padded.cuts.append(cut + int(HOLD_SECONDS * fps))
	for i in track.size():
		padded.add(track.pos[i], track.yaw[i], track.pitch[i], track.ground[i], track.pivot[i])
	padded.hold(int(HOLD_SECONDS * fps))
	info["frames"] = padded.size()
	info["seconds"] = snappedf(float(padded.size()) / float(fps), .1)
	info["motion"] = motion_stats(padded, fps)
	if sampler != null:
		info["planned_tight_s"] = tight_seconds(padded, sampler, fps)
	return {"ok": true, "track": padded, "info": info}


static func _sewer_pois(gen: StreamedRouteGenerator, chunks: Array) -> Array:
	var out: Array = []
	for chunk_coord in chunks:
		var base := _chunk_start(chunk_coord)
		for feature in gen.sewer().chunk(Vector3i(chunk_coord.x, -1, chunk_coord.y)).get("features", []):
			var type := String(feature.get("type", ""))
			var weights := {"sewerValveWheel": [1.3, 1.5], "sewerLadder": [1.4, 2.0], "sewerBridge": [1.0, 1.0], "sewerPipeRun": [.7, 2.2], "sewerLamp": [.9, 2.4]}
			if not weights.has(type) or not feature.has("cell"):
				continue
			var cell: Vector2i = base + (feature["cell"] as Vector2i)
			out.append(poi(cell.x + .5, cell.y + .5, float((weights[type] as Array)[1]), float((weights[type] as Array)[0]), type))
	return out


## Per-clip motion numbers the validator checks: the biggest per-frame heading change of the WALKING frames (not across cuts) and a zig-zag measure
## (turning done minus net turning over 2 s windows, in radians: a straight corridor walk scores about 0, a back-and-forth wobble scores high).
static func motion_stats(track: Track, fps: int) -> Dictionary:
	var biggest := 0.0
	var wobble := 0.0
	var window := fps * 2
	var headings: Array[float] = []
	for i in range(1, track.size()):
		if track.cuts.has(i) or track.ground[i] != 1 or track.ground[i - 1] != 1:
			headings.append(NAN)
			continue
		var step := Vector2(track.pos[i].x - track.pos[i - 1].x, track.pos[i].z - track.pos[i - 1].z)
		headings.append(step.angle() if step.length() > .004 else NAN)
		biggest = maxf(biggest, absf(wrapf(track.yaw[i] - track.yaw[i - 1], -PI, PI)))
	for i in range(0, headings.size() - window, fps):
		var total := 0.0
		var net := 0.0
		var prev := NAN
		var first := NAN
		var valid := true
		for k in range(i, i + window):
			var h := headings[k]
			if is_nan(h):
				continue
			if is_nan(first):
				first = h
			if not is_nan(prev):
				total += absf(wrapf(h - prev, -PI, PI))
				net += wrapf(h - prev, -PI, PI)
			prev = h
		if valid and not is_nan(first):
			wobble = maxf(wobble, total - absf(net))
	return {"max_yaw_step": snappedf(biggest, .001), "max_wobble": snappedf(wobble, .01)}


## Seconds of walking frames whose view direction faces a wall closer than 2 m (grid ray march): the planner-side half of the "staring at walls" check.
static func tight_seconds(track: Track, s: Sampler, fps: int) -> float:
	var frames := 0
	for i in track.size():
		if track.ground[i] != 1:
			continue
		var dir := Vector2(-sin(track.yaw[i]), -cos(track.yaw[i]))
		var moving := i > 0 and Vector2(track.pos[i].x - track.pos[i - 1].x, track.pos[i].z - track.pos[i - 1].z).length() > .004
		if moving and s.depth(Vector2(track.pos[i].x, track.pos[i].z), dir, 1.5) < 1.5:
			frames += 1
	return snappedf(float(frames) / float(fps), .1)


static func _nearest_open(s: Sampler, cell: Vector2i, strict: bool = true) -> Vector2i:
	for radius in range(0, 24):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var c := cell + Vector2i(dx, dz)
				if s.open(c.x, c.y) and (not strict or s.roomy(c.x, c.y) == 0):
					return c
	return cell


# ----------------------------------------------------------------------------------------------------------------------------------
# the scenario

static func run(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var fps := maxi(int(opts.get("fps", 30)), 10)
	var area := String(opts.get("area", ""))
	bridge.status = "flythrough %s: starting the run" % area
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"], "bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	bridge.admin("god", {"on": true})
	bridge.admin("no_target", {"on": true})
	var scene := tree.current_scene
	var facility: Object = scene.get("facility")
	var generator := facility.get("generator") as StreamedRouteGenerator
	var player := scene.get("player") as PlayerController3D
	if generator == null or player == null:
		return {"scenario_failure": "no generator or player in the route scene", "outcome": "error", "game_seconds": 0.0, "frames": 0}
	var planned := plan(generator, area, fps, float(opts.get("seconds", 0.0)), int(opts.get("variant", 0)), bool(opts.get("bob", true)))
	if not bool(planned.get("ok", false)):
		report["flythrough"] = {"area": area, "available": false, "reason": planned.get("error", "?")}
		return {"scenario_failure": "" if bool(planned.get("unavailable", false)) else String(planned.get("error", "plan failed")), "outcome": "unavailable" if bool(planned.get("unavailable", false)) else "error",
			"game_seconds": 0.0, "frames": 0}
	var track: Track = planned["track"]
	var info: Dictionary = planned["info"]
	# a clean frame: no HUD, no viewmodel; the camera is the player's own, moved by this script
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	if player.first_person_items != null:
		player.first_person_items.visible = false
	player.input_frozen = true
	player.look_frozen = true
	player.set_admin_noclip(true)
	var first := track.pos[0]
	bridge.admin("teleport", {"x": first.x, "y": first.y - 1.6, "z": first.z})
	var show_hunters := String(opts.get("hunters", "")) == "show"
	var frames := 0
	# let the first chunks stream in and the arrival settle before the clip starts
	for _i in 120:
		await tree.process_frame
		frames += 1
		if frames % 20 == 0:
			_clear_hunters(scene, show_hunters)
		scene.set("_relay_inactivity_seconds", 0.0)
		scene.set("_party_afk_seconds", 0.0)
	player.global_position = Vector3(first.x, first.y - 1.6, first.z)
	player._yaw = track.yaw[0]
	player._pitch = track.pitch[0]
	player._apply_look_rotation()
	await tree.process_frame
	var camera := player.active_camera()
	camera.near = .1
	var eye_offset := camera.global_position.y - player.global_position.y
	var lamp: OmniLight3D = null
	# the sewers are much darker than the maze: a stronger capture fill light there
	var lamp_base := 2.4 if String(info.get("kind", "")).begins_with("sewer") or String(info.get("kind", "")) == "maze_ladder_down" else 1.1
	if bool(opts.get("lamp", true)):
		# the maze is dark on purpose: a soft lamp riding on the camera lets a viewer read the architecture (rooms, props, colours)
		lamp = OmniLight3D.new()
		lamp.shadow_enabled = false
		lamp.light_energy = lamp_base
		lamp.omni_range = 11.0
		lamp.light_color = Color(1.0, .95, .85)
		camera.add_child(lamp)
	var clean := bool(opts.get("clean", false))
	var keep := String(opts.get("keep", "")).split(",", false)
	var space := player.get_world_3d().direct_space_state
	var floor_base := float(int(info.get("level", 0))) * LEVEL_HEIGHT
	var ground_y := floor_base + .05
	var last_hit_y := NAN
	var depth_by_second := {}
	var tight_run := 0
	var worst_tight_run := 0
	var view2_frames := 0
	var overlap_frames := 0
	var worst_floor_jump := 0.0
	var hold_yaw_offset := NAN
	var opened_doors := {}
	var doors_opened := 0
	var door_clip_frames := 0
	var blocked_frames := 0
	var inside_frames := 0
	var camera_probe := SphereShape3D.new()
	camera_probe.radius = .2
	var arm_shape := SphereShape3D.new()
	arm_shape.radius = .35
	var footprint := CapsuleShape3D.new()
	footprint.radius = .2
	footprint.height = 1.2
	var clip_start_frame := Engine.get_frames_drawn()
	var played := 0
	for i in track.size():
		bridge.status = "flythrough %s: frame %d / %d" % [area, i, track.size()]
		if track.events.has(i) and bool((track.events[i] as Dictionary).get("ladder", false)):
			played += await _play_ladder(bridge, scene, player, generator, track.events[i] as Dictionary, fps)
			# the real climb ended wherever the game put the player: the next frames only turn the view on the spot
			hold_yaw_offset = NAN
		var p := track.pos[i]
		var eye_y := p.y
		var mode := int(track.ground[i])
		if mode == 1 and bool(opts.get("doors", true)) and i % 3 == 0:
			var door := _closed_door_ahead(scene, player.active_camera(), opened_doors)
			if door != null:
				opened_doors[door.get_instance_id()] = true
				played += await _door_beat(tree, player, door, track.yaw[i], track.pitch[i])
				doors_opened += 1
		if mode == 2:
			if is_nan(hold_yaw_offset):
				hold_yaw_offset = player._yaw - track.yaw[i]
			player._yaw = track.yaw[i] + hold_yaw_offset
			player._pitch = track.pitch[i]
			player._apply_look_rotation()
		elif mode == 1:
			# WALKING: the camera is the real player body (collision capsule, gravity, the real floor: ramps, bridges, stairs). It is moved by
			# move_and_collide and slides along walls, jambs and props, so it physically cannot enter geometry.
			if player.admin_noclip:
				player.set_admin_noclip(false)
				player.global_position = Vector3(p.x, ground_y + .08, p.z)
				for _settle in 12:
					await tree.process_frame
					frames += 1
			var feet := player.global_position
			var motion := Vector3(p.x - feet.x, 0.0, p.z - feet.z)
			if motion.length() > .3:
				motion = motion.normalized() * .3
			var hit := player.move_and_collide(motion)
			if hit != null:
				var rest := hit.get_remainder().slide(hit.get_normal())
				rest.y = 0.0
				player.move_and_collide(rest)
				blocked_frames += 1
			var floor_now := player.global_position.y
			if not is_nan(last_hit_y):
				worst_floor_jump = maxf(worst_floor_jump, absf(floor_now - last_hit_y))
			last_hit_y = floor_now
			ground_y = floor_now
			player.first_person_pivot.position.y = 1.6 + (p.y - 1.6)
			player.velocity = Vector3.ZERO
			player._yaw = track.yaw[i]
			player._pitch = track.pitch[i]
			player._apply_look_rotation()
		else:
			# FLYING (establishing orbit, overview): a spring arm. A sphere is cast from the pivot to the wanted camera spot and the camera is pulled in on a hit.
			if not player.admin_noclip:
				player.set_admin_noclip(true)
			var want := Vector3(p.x, p.y, p.z)
			var pv := track.pivot[i]
			if pv.is_finite():
				var arm := PhysicsShapeQueryParameters3D.new()
				arm.shape = arm_shape
				arm.transform = Transform3D(Basis.IDENTITY, pv)
				arm.motion = want - pv
				arm.exclude = [player.get_rid()]
				var fractions := space.cast_motion(arm)
				if fractions.size() >= 2:
					want = pv + (want - pv) * (clampf(float(fractions[0]), 0.0, 1.0) * .97)
			player.first_person_pivot.position.y = 1.6
			player.global_position = Vector3(want.x, want.y - 1.6, want.z)
			player.velocity = Vector3.ZERO
			player._yaw = track.yaw[i]
			player._pitch = track.pitch[i]
			player._apply_look_rotation()
		if lamp != null:
			var above := maxf(player.active_camera().global_position.y - floor_base - 2.0, 0.0)
			lamp.omni_range = 11.0 + above * 2.2
			lamp.light_energy = lamp_base + above * .12
		if i % 45 == 0:
			_clear_hunters(scene, show_hunters)
		if clean and i % 30 == 0:
			_clean_scene(scene, keep)
		# what the camera really sees: depth of the view straight ahead through the REAL collision (walls, props, doors)
		var forward := -camera.global_basis.z
		var look := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + forward * 12.0)
		look.exclude = [player.get_rid()]
		var seen := space.intersect_ray(look)
		var depth := 12.0 if seen.is_empty() else camera.global_position.distance_to(seen["position"] as Vector3)
		var second := (i + played) / fps
		depth_by_second[second] = minf(float(depth_by_second.get(second, 99.0)), depth)
		var moving := i > 0 and Vector2(track.pos[i].x - track.pos[i - 1].x, track.pos[i].z - track.pos[i - 1].z).length() > .004
		if mode == 1 and moving and depth < 1.5:
			tight_run += 1
			worst_tight_run = maxi(worst_tight_run, tight_run)
		else:
			tight_run = 0
		if mode == 1 and depth < 2.0:
			view2_frames += 1
		# is the CAMERA inside geometry? (a sphere at the camera itself, every frame of every shot except the game's own ladder camera)
		if mode != 2:
			var overlap := PhysicsShapeQueryParameters3D.new()
			overlap.shape = camera_probe
			overlap.transform = Transform3D(Basis.IDENTITY, camera.global_position)
			overlap.exclude = [player.get_rid()]
			var inside_door := false
			var inside_other := false
			for inside in space.intersect_shape(overlap, 6):
				var body := inside["collider"] as Node
				var owner_item := body.get_parent() as RouteInteractable3D if body != null else null
				if owner_item != null and owner_item.kind == RouteInteractable3D.Kind.ROOM_DOOR:
					inside_door = true
				else:
					inside_other = true
			if inside_door:
				door_clip_frames += 1
			if inside_other:
				overlap_frames += 1
			if inside_door or inside_other:
				inside_frames += 1
		# a camera that does not move "for real" counts as idle: keep the anti-idle clocks (they send hunters) at zero
		scene.set("_relay_inactivity_seconds", 0.0)
		scene.set("_party_afk_seconds", 0.0)
		await tree.process_frame
		frames += 1
	var depth_list: Array = []
	for second in range(0, int(depth_by_second.size())):
		depth_list.append(snappedf(float(depth_by_second.get(second, 0.0)), .1))
	info["depth_per_second"] = depth_list
	info["worst_tight_run_s"] = snappedf(float(worst_tight_run) / float(fps), .2)
	info["view_under_2m_s"] = snappedf(float(view2_frames) / float(fps), .1)
	info["prop_overlap_s"] = snappedf(float(overlap_frames) / float(fps), .2)
	info["max_floor_step_m"] = snappedf(worst_floor_jump, .01)
	info["ladder_frames"] = played
	info["inside_geometry_s"] = snappedf(float(inside_frames) / float(fps), .2)
	info["blocked_s"] = snappedf(float(blocked_frames) / float(fps), .2)
	info["doors_opened"] = doors_opened
	info["door_clip_s"] = snappedf(float(door_clip_frames) / float(fps), .2)
	info["clip_frames_actual"] = Engine.get_frames_drawn() - clip_start_frame
	info["fps"] = fps
	info["clip_start_frame"] = clip_start_frame
	info["clip_frames"] = int(info.get("clip_frames_actual", track.size()))
	info["seconds"] = snappedf(float(info["clip_frames"]) / float(fps), .1)
	info["eye_offset"] = snappedf(eye_offset, .01)
	info["current_biome"] = String((facility.call("current_chunk_data") as Dictionary).get("biome", "?"))
	info["available"] = true
	report["flythrough"] = info
	return {"outcome": "recorded", "game_seconds": snappedf(float(frames) / float(fps), .1), "frames": frames, "scenario_failure": ""}


static func floor_y_of(info: Dictionary) -> float:
	return float(int(info.get("level", 0))) * LEVEL_HEIGHT


## A closed, unbroken room door 1.6-3.0 m ahead of the camera (inside a 55 degree cone) that has not been opened by this clip yet.
static func _closed_door_ahead(scene: Node, camera: Camera3D, done: Dictionary) -> RouteInteractable3D:
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for node in scene.get_tree().get_nodes_in_group("room_door"):
		var door := node as RouteInteractable3D
		if door == null or not is_instance_valid(door) or door.kind != RouteInteractable3D.Kind.ROOM_DOOR:
			continue
		if door.room_door_open or door.room_door_broken or done.has(door.get_instance_id()):
			continue
		var to_door := door.interaction_focus() - camera.global_position
		if absf(to_door.y) > 1.6:
			continue
		to_door.y = 0.0
		var d := to_door.length()
		if d < 1.6 or d > 3.0:
			continue
		if forward.angle_to(to_door / d) < deg_to_rad(55.0):
			return door
	return null


## The camera stops, turns to the door and opens it through the game's own door interaction (activate(): the hinged leaf swings, Sound.door plays).
## Returns the frames used.
static func _door_beat(tree: SceneTree, player: PlayerController3D, door: RouteInteractable3D, resume_yaw: float, resume_pitch: float) -> int:
	var count := 0
	var to_door := door.interaction_focus() - player.global_position
	var aim_yaw := yaw_for(to_door.x, to_door.z)
	var start_yaw := player._yaw
	for k in 24:
		var e := float(k + 1) / 24.0
		e = e * e * (3.0 - 2.0 * e)
		player._yaw = lerp_angle(start_yaw, aim_yaw, e)
		player._pitch = lerpf(player._pitch, 0.0, .1)
		player._apply_look_rotation()
		await tree.process_frame
		count += 1
	door.activate(player)
	for _k in 40:
		await tree.process_frame
		count += 1
	var from_yaw := player._yaw
	for k in 14:
		var e := float(k + 1) / 14.0
		player._yaw = lerp_angle(from_yaw, resume_yaw, e)
		player._pitch = lerpf(player._pitch, resume_pitch, e)
		player._apply_look_rotation()
		await tree.process_frame
		count += 1
	return count


## Play a REAL ladder climb: the player becomes a normal, collidable runner again, stands on the ladder cell and holds up (or down); the game's own
## controller mounts, climbs and dismounts, so the view is centred on the rungs facing the wall. Returns the number of frames it took.
static func _play_ladder(bridge: PlaytestBridge, scene: Node, player: PlayerController3D, generator: StreamedRouteGenerator, event: Dictionary, fps: int) -> int:
	var tree := bridge.get_tree()
	var level := int(event["level"])
	var at: Vector2 = event["at"]
	var link := LadderTraffic.nearest_ladder(generator, level, at)
	if link.is_empty():
		return 0
	var point := LadderTraffic.ladder_point(link, level)
	var floor_y := float(level) * LEVEL_HEIGHT + (.04 if level != 0 else .04)
	var count := 0
	player.set_admin_noclip(false)
	player.input_frozen = false
	player.look_frozen = false
	player.first_person_items.visible = false if player.first_person_items != null else false
	scene.call("_admin_teleport_to", Vector3(point.x, floor_y, point.y))
	var action := "move_down" if bool(event.get("down", false)) else "move_up"
	# wait for the game to start the climb (standing on the ladder cell does it), then hold the direction until it has dismounted
	for _k in 90:
		await tree.process_frame
		count += 1
		if player.is_climbing():
			break
	if player.is_climbing():
		Input.action_press(action, 1.0)
		var guard := 0
		while player.is_climbing() and guard < fps * 40:
			bridge.status = "flythrough ladder: climbing (%s)" % action
			await tree.process_frame
			count += 1
			guard += 1
		Input.action_release(action)
		for _k in fps / 2:
			await tree.process_frame
			count += 1
	player.input_frozen = true
	player.look_frozen = true
	player.set_admin_noclip(true)
	if player.first_person_items != null:
		player.first_person_items.visible = false
	return count


## Capture-only clean scene: hide pickups, tools and the waypoint trail by VISIBILITY only (the world state is untouched). `keep` is a whitelist of
## kind names (relay, battery, coin, tool_pickup, music_box) a shot wants to keep visible.
static func _clean_scene(scene: Node, keep: PackedStringArray) -> void:
	var hide_kinds := {"relay": RouteInteractable3D.Kind.RELAY, "battery": RouteInteractable3D.Kind.BATTERY, "coin": RouteInteractable3D.Kind.COIN,
		"tool_pickup": RouteInteractable3D.Kind.TOOL_PICKUP, "music_box": RouteInteractable3D.Kind.MUSIC_BOX}
	for node in scene.get_tree().get_nodes_in_group("interactable"):
		var item := node as RouteInteractable3D
		if item == null or not is_instance_valid(item):
			continue
		for name in hide_kinds:
			if int(hide_kinds[name]) == int(item.kind) and not keep.has(name):
				item.visible = false
	var trail: Variant = scene.get("_waypoint_trail")
	if trail is Node3D:
		(trail as Node3D).visible = false


static func _clear_hunters(scene: Node, keep: bool) -> void:
	if keep:
		return
	var world_state: Object = scene.get("world_state")
	if world_state == null:
		return
	var ids := {}
	for entity_id in (world_state.get("hunters") as Dictionary):
		ids[String(((world_state.get("hunters") as Dictionary)[entity_id] as Dictionary).get("hunter_id", ""))] = true
	for hunter_id in ids:
		if not String(hunter_id).is_empty() and scene.has_method("_admin_remove_hunter"):
			scene.call("_admin_remove_hunter", hunter_id)
