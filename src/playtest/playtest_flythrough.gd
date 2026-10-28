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
		var rows: Array = _grids[key]
		var lz := z - cz * size
		var lx := x - cx * size
		if lz < 0 or lz >= rows.size() or lx < 0 or lx >= (rows[lz] as Array).size():
			return false
		var code := int(rows[lz][lx])
		if level == StreamedRouteGenerator.SEWER_LEVEL:
			return code == 0 or code == 3
		return code == 0

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
	## Frame indexes where the picture cuts to a new shot: angles are not smoothed across them.
	var cuts: Array[int] = []

	func add(p: Vector3, y: float, pt: float) -> void:
		pos.append(p)
		yaw.append(y)
		pitch.append(pt)

	func hold(count: int) -> void:
		if pos.is_empty():
			return
		for _i in count:
			add(pos[pos.size() - 1], yaw[yaw.size() - 1], pitch[pitch.size() - 1])

	func size() -> int:
		return pos.size()


static func bake_walk(track: Track, points: Array[Vector2], floor_y: float, fps: int) -> void:
	var dense := resample(chaikin(points, 3), WALK_SPEED / float(fps))
	var look_ahead := int(3.0 * float(fps) / WALK_SPEED)
	for i in dense.size():
		var ahead := dense[mini(i + look_ahead, dense.size() - 1)]
		var here := dense[i]
		var yaw_value := track.yaw[track.yaw.size() - 1] if ahead.distance_to(here) < .05 and track.size() > 0 else yaw_for(ahead.x - here.x, ahead.y - here.y)
		var t := float(i) / float(fps)
		var bob := sin(t * 2.0 * PI * WALK_SPEED * .5) * .025
		track.add(Vector3(here.x, floor_y + 1.6 + bob, here.y), yaw_value, sin(t * 1.3) * .02)


## Orbit `center` starting from the camera's current spot, rising/zooming to `to_height`/`to_radius`; always looking at the centre at `look_y`.
static func bake_orbit(track: Track, center: Vector3, degrees: float, seconds: float, to_height: float, to_radius: float, look_y: float, fps: int) -> void:
	var from := track.pos[track.pos.size() - 1]
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
			track.add(p, yaw_for(d.x, d.z), pitch_for(d))


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
		track.add(p, yaw_for(d.x, d.z), pitch_for(d))


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
		track.add(at, yaw0 + deg_to_rad(degrees) * e, lerpf(track.pitch[track.pitch.size() - 1], pitch, .08))


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
static func find_biome_chunk(gen: StreamedRouteGenerator, biome: String, level: int) -> Dictionary:
	var best := {}
	var best_score := 1e9
	for cz in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for cx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			var coord := Vector3i(cx, level, cz)
			if not gen.is_chunk_allowed(coord) or gen.biome_for(coord) != biome or gen.is_safe_room(coord):
				continue
			var rx := posmod(cx, StreamedRouteGenerator.BIOME_REGION_SIZE)
			var rz := posmod(cz, StreamedRouteGenerator.BIOME_REGION_SIZE)
			var interior := (rx == 1 or rx == 2) and (rz == 1 or rz == 2)
			var score := float(absi(cx) + absi(cz)) + (0.0 if interior else 30.0)
			if score < best_score:
				best_score = score
				best = {"coord": coord}
	return best


## Build the camera track of an area. Returns {"ok", "track", "info"}; "info" says where it went (chunk, level, biome, start, goal).
static func plan(gen: StreamedRouteGenerator, area: String, fps: int, seconds_override: float) -> Dictionary:
	if not AREAS.has(area):
		return {"ok": false, "error": "unknown area '%s' (have: %s)" % [area, ", ".join(area_names())]}
	var preset: Dictionary = AREAS[area]
	var kind := String(preset["kind"])
	var track := Track.new()
	var info := {"area": area, "kind": kind}
	var walk_seconds := WALK_SECONDS if seconds_override <= 0.0 else maxf(seconds_override - ORBIT_SECONDS - HOLD_SECONDS, 6.0)
	match kind:
		"district":
			var level := int(preset["level"])
			var found := find_biome_chunk(gen, String(preset["biome"]), level)
			if found.is_empty():
				return {"ok": false, "error": "this build has no '%s' district on level %d within %d chunks of the spawn" % [preset["biome"], level, SEARCH_RADIUS], "unavailable": true}
			var coord: Vector3i = found["coord"]
			var s := Sampler.new(gen, level)
			var base := _chunk_start(Vector2i(coord.x, coord.z))
			var start := _nearest_open(s, base + Vector2i(CHUNK / 2, CHUNK / 2))
			var field := path_field(s, start, 70)
			var wanted := int(walk_seconds * WALK_SPEED)
			var goal := far_goal(field, start, int(wanted * .7), wanted)
			if goal == start:
				goal = far_goal(field, start, 8, wanted)
			var floor_y := float(level) * LEVEL_HEIGHT
			track.hold(0)
			var points := path_to(field, goal)
			bake_walk(track, points, floor_y, fps)
			if track.size() < 10:
				return {"ok": false, "error": "no walkable route from the middle of chunk %s" % coord}
			var centre := Vector3(base.x + CHUNK * .5, floor_y, base.y + CHUNK * .5)
			bake_overview(track, centre, points[points.size() - 1], 80.0, ORBIT_SECONDS, floor_y + 8.0, 13.0, fps)
			info.merge({"level": level, "chunk": [coord.x, coord.z], "biome": gen.biome_for(coord), "start": [start.x, start.y], "goal": [goal.x, goal.y], "path_cells": points.size()})
		"sewer_tunnels":
			var base := Vector2i.ZERO
			var s := Sampler.new(gen, -1)
			var start := Vector2i(base.x + 19, base.y + 2)
			var goal := Vector2i(base.x + 19, base.y + 2 + int(walk_seconds * WALK_SPEED))
			var field := path_field(s, start, 90)
			if not field["cost"].has(goal):
				return {"ok": false, "error": "sewer tunnel lane is not walkable end to end"}
			var floor_y := -LEVEL_HEIGHT
			bake_walk(track, path_to(field, goal), floor_y, fps)
			bake_turn(track, 180.0, ORBIT_SECONDS * .8, -.05, fps)
			info.merge({"level": -1, "chunk": [0, 0], "start": [start.x, start.y], "goal": [goal.x, goal.y]})
		"sewer_junction":
			var s := Sampler.new(gen, -1)
			var start := Vector2i(19, 6)
			var centre_cell := Vector2i(CHUNK / 2, CHUNK / 2)
			var field := path_field(s, start, 40)
			var floor_y := -LEVEL_HEIGHT
			bake_walk(track, path_to(field, Vector2i(19, 18)), floor_y, fps)
			bake_orbit(track, Vector3(centre_cell.x + .5, floor_y, centre_cell.y + .5), 330.0, maxf(walk_seconds, 14.0) - 4.0 + ORBIT_SECONDS * .5, floor_y + 3.0, 4.2, floor_y + 1.0, fps)
			info.merge({"level": -1, "chunk": [0, 0], "start": [start.x, start.y]})
		"sewer_room":
			var data: Dictionary = gen.sewer().chunk(Vector3i(0, -1, 0))
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
			var centre: Vector2i = base + (room["centre"] as Vector2i)
			var walk_to := _nearest_open(s, centre, false)
			var field := path_field(s, junction, 60)
			var floor_y := -LEVEL_HEIGHT
			if not field["cost"].has(walk_to):
				return {"ok": false, "error": "room centre %s not reachable from the junction" % centre}
			bake_walk(track, path_to(field, walk_to), floor_y, fps)
			bake_orbit(track, Vector3(centre.x + .5, floor_y, centre.y + .5), 300.0, ORBIT_SECONDS + 4.0, floor_y + 2.4, 3.6, floor_y + 1.0, fps)
			info.merge({"level": -1, "chunk": [room["chunk"].x, room["chunk"].y], "room": wanted, "start": [junction.x, junction.y], "goal": [centre.x, centre.y]})
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
			var field := path_field(s, base + Vector2i(CHUNK / 2, CHUNK / 2), 60)
			if not field["cost"].has(chamber):
				return {"ok": false, "error": "ladder chamber %s not reachable from the junction" % chamber}
			var floor_y := -LEVEL_HEIGHT
			bake_walk(track, path_to(field, chamber), floor_y, fps)
			track.hold(fps)
			var ladder_xz := Vector2(up.x + .5, up.y + .5) - Vector2(wall) * .45
			bake_rise(track, Vector2(chamber.x + .5, chamber.y + .5), Vector2(chamber.x + .5, chamber.y + .5).lerp(ladder_xz, .6), floor_y + 1.6, 1.6, 6.0, Vector2(wall), .55, fps)
			track.hold(fps)
			bake_turn(track, 300.0, ORBIT_SECONDS * .8, 0.0, fps)
			info.merge({"level": -1, "chunk": [chunk_of.x, chunk_of.y], "ladder_cell": [up.x, up.y], "wall": [wall.x, wall.y]})
	smooth_angles(track, fps, .45)
	# a short still at the start (fade-in) and at the end (fade-out)
	var first_pos := track.pos[0]
	var first_yaw := track.yaw[0]
	var first_pitch := track.pitch[0]
	var padded := Track.new()
	for _i in int(HOLD_SECONDS * fps):
		padded.add(first_pos, first_yaw, first_pitch)
	for cut in track.cuts:
		padded.cuts.append(cut + int(HOLD_SECONDS * fps))
	for i in track.size():
		padded.add(track.pos[i], track.yaw[i], track.pitch[i])
	padded.hold(int(HOLD_SECONDS * fps))
	info["frames"] = padded.size()
	info["seconds"] = snappedf(float(padded.size()) / float(fps), .1)
	return {"ok": true, "track": padded, "info": info}


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
	var planned := plan(generator, area, fps, float(opts.get("seconds", 0.0)))
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
	var eye_offset := camera.global_position.y - player.global_position.y
	var lamp: OmniLight3D = null
	if bool(opts.get("lamp", true)):
		# the maze is dark on purpose: a soft lamp riding on the camera lets a viewer read the architecture (rooms, props, colours)
		lamp = OmniLight3D.new()
		lamp.shadow_enabled = false
		lamp.light_energy = 1.1
		lamp.omni_range = 11.0
		lamp.light_color = Color(1.0, .95, .85)
		camera.add_child(lamp)
	var clip_start_frame := Engine.get_frames_drawn()
	for i in track.size():
		bridge.status = "flythrough %s: frame %d / %d" % [area, i, track.size()]
		var p := track.pos[i]
		player.global_position = Vector3(p.x, p.y - eye_offset, p.z)
		player.velocity = Vector3.ZERO
		player._yaw = track.yaw[i]
		player._pitch = track.pitch[i]
		player._apply_look_rotation()
		if lamp != null:
			var above := maxf(p.y - (floor_y_of(info)) - 2.0, 0.0)
			lamp.omni_range = 11.0 + above * 2.2
			lamp.light_energy = 1.1 + above * .12
		if i % 45 == 0:
			_clear_hunters(scene, show_hunters)
		# a camera that does not move "for real" counts as idle: keep the anti-idle clocks (they send hunters) at zero
		scene.set("_relay_inactivity_seconds", 0.0)
		scene.set("_party_afk_seconds", 0.0)
		await tree.process_frame
		frames += 1
	info["fps"] = fps
	info["clip_start_frame"] = clip_start_frame
	info["clip_frames"] = track.size()
	info["eye_offset"] = snappedf(eye_offset, .01)
	info["current_biome"] = String((facility.call("current_chunk_data") as Dictionary).get("biome", "?"))
	info["available"] = true
	report["flythrough"] = info
	return {"outcome": "recorded", "game_seconds": snappedf(float(frames) / float(fps), .1), "frames": frames, "scenario_failure": ""}


static func floor_y_of(info: Dictionary) -> float:
	return float(int(info.get("level", 0))) * LEVEL_HEIGHT


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
