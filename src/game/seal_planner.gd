class_name SealPlanner
extends RefCounted

## Sealed wings (SealRules, KT "more sealed"): parts of a chunk that stay shut until somebody breaks a seal across the way
## in. On level -3 a seal is a gate across a cave tunnel that runs to a chamber the entrances do not reach any other way.
## The planner is deterministic per seed and chunk, sits on the walk grid only, and guarantees what the rules ask:
##   - every seam opening and ramp landing stays connected with every seal closed (seals never cut a level link or a seam);
##   - every gate really shuts something in (taking it away opens more ground);
##   - the number of seals follows SealRules.seals_per_chunk for the chunk's ring (as far as the chunk's tunnels allow).
## Wings are returned as `sealed` cells; relays and tools are placed against them by the generator (_pickups).

const CHUNK_SIZE := 45
const SLAB_HALF := .8
const FRACTION_LOW := .3
const FRACTION_HIGH := .7
const MIN_WING := 24              # fewest cells a wing must hold to be worth a seal


## {"gates": [{cells, centre, dir, radius, tunnel}], "sealed": Array[Vector2i], "open_share": float, "entries": Array}
static func plan_cave(world_seed: String, coord: Vector3i, grid: Array, chambers: Array, tunnels: Array) -> Dictionary:
	var result := {"gates": [], "sealed": [], "open_share": 1.0, "entries": []}
	var entries: Array[Vector2i] = []
	for tunnel in tunnels:
		var from: Vector2i = tunnel["from"]
		# a seam stub a ramp's slope has since walled over is a dead end, not an entrance; the side lanes of a seam
		# (rows 10 and 34 of an east-west seam) are not entrances either: a gate may shut them
		if String(tunnel["kind"]) in ["portal", "anchor"] and int(grid[from.y][from.x]) == 0 and not _side_lane(tunnel):
			entries.append(from)
	result["entries"] = entries
	if entries.is_empty():
		return result
	var candidates: Array = []
	for index in tunnels.size():
		var tunnel: Dictionary = tunnels[index]
		if String(tunnel["kind"]) == "hang" or _side_lane(tunnel):
			var gate := _gate(grid, chambers, tunnel, index)
			if not gate.is_empty():
				candidates.append(gate)
	if candidates.is_empty():
		return result
	var rng := SeededRandom.new("%s:SEALS:%d:%d:%d" % [world_seed, coord.x, coord.y, coord.z])
	var base := SealRules.seals_per_chunk(coord)
	var want := floori(base) + (1 if rng.next_float() < base - floor(base) else 0)
	var total_open := _open_count(grid)
	var best := {}
	var best_score := 1.0e9
	var target_open := SealRules.open_share(coord)
	for mask in range(1, 1 << candidates.size()):
		var chosen: Array = []
		for bit in candidates.size():
			if mask & (1 << bit) != 0:
				chosen.append(candidates[bit])
		var blocked := _blocked(chosen)
		var reach := _reach(grid, entries, blocked)
		if not _all_reached(reach, entries):
			continue
		# every gate must shut ground in: without it, fewer cells stay cut off (the gate's own cells do not count)
		var shut := total_open - blocked.size() - _reach_count(reach)
		if shut < MIN_WING:
			continue
		var effective := true
		for gate in chosen:
			var without := _blocked(chosen.filter(func(g): return g != gate))
			if total_open - without.size() - _reach_count(_reach(grid, entries, without)) >= shut:
				effective = false
				break
		if not effective:
			continue
		var open_share := float(_reach_count(reach)) / maxf(1.0, float(total_open - blocked.size()))
		var score := absf(float(chosen.size() - want)) * 2.0 + absf(open_share - target_open)
		if score < best_score:
			best_score = score
			best = {"chosen": chosen, "reach": reach, "open_share": open_share}
	if best.is_empty():
		return result
	var sealed: Array[Vector2i] = []
	var reached: PackedByteArray = best["reach"]
	var blocked_cells := _blocked(best["chosen"])
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if int(grid[z][x]) == 0 and reached[z * CHUNK_SIZE + x] == 0 and not blocked_cells.has(Vector2i(x, z)):
				sealed.append(Vector2i(x, z))
	result["gates"] = best["chosen"]
	result["sealed"] = sealed
	result["open_share"] = best["open_share"]
	return result


## The Breach specs of a plan's gates: each draws a seal kind from the level's mix.
static func specs(world_seed: String, coord: Vector3i, plan: Dictionary, level: int, first_index: int = 0) -> Array:
	var rng := SeededRandom.new("%s:SEAL-KINDS:%d:%d:%d" % [world_seed, coord.x, coord.y, coord.z])
	var mix := SealRules.seal_mix(level)
	var kinds: Array = mix.keys()
	var result: Array = []
	for gate_value in plan["gates"]:
		var gate: Dictionary = gate_value
		var roll := rng.next_float()
		var seal_kind := String(kinds[0]) if not kinds.is_empty() else "barricade"
		var acc := 0.0
		for kind in kinds:
			acc += float(mix[kind])
			if roll <= acc:
				seal_kind = String(kind)
				break
		var variant := SealRules.seal_prop(level, seal_kind)
		var hp := int(SealRules.SEAL_HP.get(seal_kind, 3))
		result.append(Breach.make_spec(Breach.make_id(coord, first_index + result.size()), Breach.KIND_SEAL, variant, coord,
			Vector2i(int(gate["centre"].x), int(gate["centre"].y)), hp, _tools(level, seal_kind),
			{"seal": seal_kind, "cells": gate["cells"], "centre": gate["centre"], "dir": gate["dir"],
				"radius": gate["radius"], "tunnel": gate["tunnel"]}, seal_kind == "locked_door"))
	return result


## SealRules names the axe "axe"; the player's item is the rescue axe.
static func _tools(level: int, seal_kind: String) -> Array:
	var out: Array = []
	for tool in SealRules.seal_tools(level, seal_kind):
		out.append("rescue_axe" if String(tool) == "axe" else String(tool))
	return out


## A seam tunnel that is not the central lane (the middle of its side): the maze's dense seams carry two more.
static func _side_lane(tunnel: Dictionary) -> bool:
	if String(tunnel["kind"]) != "portal":
		return false
	var from: Vector2i = tunnel["from"]
	var middle := CHUNK_SIZE / 2
	return (from.x <= 3 or from.x >= CHUNK_SIZE - 4) and from.y != middle


static func _gate(grid: Array, chambers: Array, tunnel: Dictionary, index: int) -> Dictionary:
	var samples: Array = tunnel["samples"]
	var radii: PackedFloat32Array = tunnel["radii"]
	if samples.size() < 8:
		return {}
	var inside := {}
	if int(tunnel["from_chamber"]) >= 0:
		for cell in (chambers[int(tunnel["from_chamber"])] as Dictionary)["cells"]:
			inside[cell] = true
	# A side chamber's gate sits just outside it (the tunnel starts at its middle), so nothing else can join in between; a
	# side lane's gate sits a third of the way in from its seam.
	var pick := -1
	if String(tunnel["kind"]) == "hang":
		for k in range(samples.size() - 1):
			var cell := Vector2i(int(floor((samples[k] as Vector2).x)), int(floor((samples[k] as Vector2).y)))
			if not inside.has(cell):
				pick = mini(k + 3, samples.size() - 2)
				break
	else:
		pick = clampi(int(samples.size() * .35), 6, samples.size() - 2)
	if pick < 1 or pick >= samples.size() - 1:
		return {}
	var centre: Vector2 = samples[pick]
	var dir := ((samples[pick + 1] as Vector2) - (samples[pick - 1] as Vector2)).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var radius := radii[pick]
	var cells: Array[Vector2i] = []
	var reach := int(ceil(radius + 2.0))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := Vector2i(int(floor(centre.x)) + dx, int(floor(centre.y)) + dz)
			if cell.x < 1 or cell.y < 1 or cell.x > CHUNK_SIZE - 2 or cell.y > CHUNK_SIZE - 2 or int(grid[cell.y][cell.x]) != 0:
				continue
			var v := Vector2(cell.x + .5, cell.y + .5) - centre
			if absf(v.dot(dir)) <= SLAB_HALF and absf(v.dot(perp)) <= radius + 1.1:
				cells.append(cell)
	if cells.size() < 3:
		return {}
	return {"cells": cells, "centre": centre, "dir": dir, "radius": radius, "tunnel": index}


static func _blocked(gates: Array) -> Dictionary:
	var blocked := {}
	for gate in gates:
		for cell in (gate as Dictionary)["cells"]:
			blocked[cell] = true
	return blocked


static func _open_count(grid: Array) -> int:
	var n := 0
	for z in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			if int(grid[z][x]) == 0:
				n += 1
	return n


## Flood from the entries over open cells that are not blocked; 1 marks reached.
static func _reach(grid: Array, entries: Array, blocked: Dictionary) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(CHUNK_SIZE * CHUNK_SIZE)
	var stack := PackedInt32Array()
	for entry in entries:
		var e: Vector2i = entry
		if int(grid[e.y][e.x]) == 0 and not blocked.has(e):
			stack.append(e.y * CHUNK_SIZE + e.x)
			seen[e.y * CHUNK_SIZE + e.x] = 1
	while not stack.is_empty():
		var at := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x := at % CHUNK_SIZE
		var z := at / CHUNK_SIZE
		for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = x + step[0]
			var nz: int = z + step[1]
			if nx < 0 or nz < 0 or nx >= CHUNK_SIZE or nz >= CHUNK_SIZE:
				continue
			var n := nz * CHUNK_SIZE + nx
			if seen[n] == 1 or int(grid[nz][nx]) != 0 or (not blocked.is_empty() and blocked.has(Vector2i(nx, nz))):
				continue
			seen[n] = 1
			stack.append(n)
	return seen


static func _reach_count(seen: PackedByteArray) -> int:
	var n := 0
	for value in seen:
		n += int(value)
	return n


static func _all_reached(seen: PackedByteArray, entries: Array) -> bool:
	for entry in entries:
		var e: Vector2i = entry
		if seen[e.y * CHUNK_SIZE + e.x] == 0:
			return false
	return true
