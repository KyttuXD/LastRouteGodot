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
	var open := _open_mask(grid)
	var total_open := 0
	for value in open:
		total_open += int(value)
	# each candidate on its own first: the entrances must still meet and it must shut a worthwhile wing in (the gates of
	# different tunnels do not touch each other's wings, so one flood each is enough); then a few at a time
	var usable: Array = []
	for gate in candidates:
		var blocked := _block_mask([gate])
		var reach := _reach_mask(open, entries, blocked)
		if not _all_reached(reach, entries):
			continue
		var shut := total_open - _count(blocked, open) - _count(reach, open)
		if shut >= MIN_WING:
			(gate as Dictionary)["shut"] = shut
			usable.append(gate)
	if usable.is_empty():
		return result
	# shuffle (deterministic) and take as many as the ring asks for
	for i in range(usable.size() - 1, 0, -1):
		var j := rng.next_index(i + 1)
		var swap = usable[i]
		usable[i] = usable[j]
		usable[j] = swap
	var chosen: Array = usable.slice(0, mini(maxi(1, want), usable.size()))
	var reach_all := PackedByteArray()
	var blocked_all := PackedByteArray()
	while true:
		blocked_all = _block_mask(chosen)
		reach_all = _reach_mask(open, entries, blocked_all)
		if _all_reached(reach_all, entries) or chosen.size() <= 1:
			break
		chosen.pop_back()
	var sealed: Array[Vector2i] = []
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var at := z * CHUNK_SIZE + x
			if open[at] == 1 and reach_all[at] == 0 and blocked_all[at] == 0:
				sealed.append(Vector2i(x, z))
	if sealed.is_empty():
		return result
	result["gates"] = chosen
	result["sealed"] = sealed
	result["open_share"] = float(_count(reach_all, open)) / maxf(1.0, float(total_open - _count(blocked_all, open)))
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


static func _open_mask(grid: Array) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(CHUNK_SIZE * CHUNK_SIZE)
	for z in CHUNK_SIZE:
		var row: Array = grid[z]
		for x in CHUNK_SIZE:
			if int(row[x]) == 0:
				mask[z * CHUNK_SIZE + x] = 1
	return mask


static func _block_mask(gates: Array) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(CHUNK_SIZE * CHUNK_SIZE)
	for gate in gates:
		for cell in (gate as Dictionary)["cells"]:
			mask[(cell as Vector2i).y * CHUNK_SIZE + (cell as Vector2i).x] = 1
	return mask


## Cells where both masks are set.
static func _count(mask: PackedByteArray, within: PackedByteArray) -> int:
	var n := 0
	for i in mask.size():
		n += mask[i] & within[i]
	return n


## Flood from the entries over open cells that are not blocked; 1 marks reached.
static func _reach_mask(open: PackedByteArray, entries: Array, blocked: PackedByteArray) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(CHUNK_SIZE * CHUNK_SIZE)
	var stack := PackedInt32Array()
	for entry in entries:
		var e: Vector2i = entry
		var at := e.y * CHUNK_SIZE + e.x
		if open[at] == 1 and blocked[at] == 0 and seen[at] == 0:
			stack.append(at)
			seen[at] = 1
	while not stack.is_empty():
		var at := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x := at % CHUNK_SIZE
		if x > 0 and open[at - 1] == 1 and seen[at - 1] == 0 and blocked[at - 1] == 0:
			seen[at - 1] = 1
			stack.append(at - 1)
		if x < CHUNK_SIZE - 1 and open[at + 1] == 1 and seen[at + 1] == 0 and blocked[at + 1] == 0:
			seen[at + 1] = 1
			stack.append(at + 1)
		if at >= CHUNK_SIZE and open[at - CHUNK_SIZE] == 1 and seen[at - CHUNK_SIZE] == 0 and blocked[at - CHUNK_SIZE] == 0:
			seen[at - CHUNK_SIZE] = 1
			stack.append(at - CHUNK_SIZE)
		if at < CHUNK_SIZE * (CHUNK_SIZE - 1) and open[at + CHUNK_SIZE] == 1 and seen[at + CHUNK_SIZE] == 0 and blocked[at + CHUNK_SIZE] == 0:
			seen[at + CHUNK_SIZE] = 1
			stack.append(at + CHUNK_SIZE)
	return seen


static func _all_reached(seen: PackedByteArray, entries: Array) -> bool:
	for entry in entries:
		var e: Vector2i = entry
		if seen[e.y * CHUNK_SIZE + e.x] == 0:
			return false
	return true
