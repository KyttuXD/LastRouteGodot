class_name InfernoCaverns
extends RefCounted

## Level -3 is a maze of narrow halls with a few wide places in it. A cavern is a rough blob 14-22 cells across that
## replaces whatever rooms it overlaps, with a high ceiling (the view lifts its cells to the storey cap) and a rim of
## pillars and one-cell crevices: the open middle is where a chase can run, the crevices are where a runner can hide.
## A hall 5 cells wide ties each cavern to the circulation the maze already has, so nothing is cut off.
##
## Everything here is deterministic from the world seed and the chunk coordinate, and runs on the grid only.

const CHUNK_SIZE := 45
const MARGIN := 5                    # keeps a cavern off the seam openings
const MIN_SPAN := 14
const MAX_SPAN := 22
const HALL_WIDTH := 5
const CAVERN_CHANCE := 1.0
const SECOND_CHANCE := 0.6
const CREVICES := 3
const CREVICE_DEPTH := 4
const KEEP_CLEAR := 2                # cells between a cavern and a ramp or stairwell footprint
const PIT_CHANCE := 0.28
const PIT_MIN_SPAN := 18
const PIT_BAND := 3                  # width of the lava channel
const PIT_BRIDGE := 3                # width of the span across it
const CAGE_CAP := 3.9                # the storey cap the caverns rise to (LEVEL_HEIGHT - SLAB)
const CAGE_HEIGHT := 1.0
const CAGE_HIGH := 2.5               # bottom heights above the floor: high, low enough to walk under, and in the way
const CAGE_UNDER := 2.1
const CAGE_LOW := 0.75
const OPEN_CLEARANCE := 3            # a 7x7 fully open block is clearance 3


## Carves caverns into `grid` and returns them as {"rect", "cells", "halls", "crevices"} dictionaries.
## `blocked` holds footprints the carve must not touch (ramps, stairwells); `circulation` is the set of cells the
## maze guarantees walkable, which each hall reaches for.
static func carve(world_seed: String, coord: Vector3i, grid: Array, layout: Dictionary, circulation: Dictionary,
		blocked: Array[Rect2i]) -> Array:
	var rng := SeededRandom.new("%s:INFERNO-CAVERN:%d:%d:%d" % [world_seed, coord.x, coord.y, coord.z])
	var caverns: Array = []
	var count := 0
	if rng.next_float() < CAVERN_CHANCE:
		count = 1
		if rng.next_float() < SECOND_CHANCE:
			count = 2
	var taken: Array[Rect2i] = blocked.duplicate()
	for _i in count:
		var cavern := _place(rng, taken, caverns.is_empty())
		if cavern.is_empty():
			continue
		_remove_rooms(grid, layout, (cavern["rect"] as Rect2i).grow(1))
		_stamp(grid, cavern)
		cavern["crevices"] = _crevices(rng, grid, cavern)
		cavern["halls"] = _halls(rng, grid, layout, circulation, cavern, blocked)
		if rng.next_float() < PIT_CHANCE:
			cavern["pit"] = _pit(rng, grid, cavern)
		for hall in cavern["halls"]:
			_mark(circulation, hall)
		for cell in cavern["cells"]:
			circulation[cell] = true
		taken.append((cavern["rect"] as Rect2i).grow(2))
		caverns.append(cavern)
	return caverns


static func _place(rng: SeededRandom, taken: Array[Rect2i], first: bool) -> Dictionary:
	# the first is big; a second must squeeze in beside it
	var low := MIN_SPAN + 2 if first else MIN_SPAN
	var high := MAX_SPAN if first else MIN_SPAN + 2
	var width := low + rng.next_index(high - low + 1)
	var depth := low + rng.next_index(high - low + 1)
	var spots: Array[Vector2i] = []
	for z in range(MARGIN, CHUNK_SIZE - MARGIN - depth + 1, 2):
		for x in range(MARGIN, CHUNK_SIZE - MARGIN - width + 1, 2):
			spots.append(Vector2i(x, z))
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.next_index(i + 1)
		var swap := spots[i]
		spots[i] = spots[j]
		spots[j] = swap
	for spot in spots:
		var rect := Rect2i(spot.x, spot.y, width, depth)
		var clash := false
		for other in taken:
			if rect.grow(KEEP_CLEAR).intersects(other):
				clash = true
				break
		if clash:
			continue
		return {"rect": rect, "cells": _blob(rng, rect), "halls": [], "crevices": []}
	return {}


## An ellipse with a wobbling edge. The inner 70% is always open, so the middle holds a clear 7x7 for any span >= 14.
static func _blob(rng: SeededRandom, rect: Rect2i) -> Array[Vector2i]:
	var cx := rect.position.x + rect.size.x * .5
	var cz := rect.position.y + rect.size.y * .5
	var rx := rect.size.x * .5
	var rz := rect.size.y * .5
	var phase_a := rng.next_float() * TAU
	var phase_b := rng.next_float() * TAU
	var cells: Array[Vector2i] = []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var dx := (x + .5 - cx) / rx
			var dz := (z + .5 - cz) / rz
			var angle := atan2(dz, dx)
			var edge := 0.96 + .04 * sin(angle * 3.0 + phase_a) - .03 * sin(angle * 5.0 + phase_b)
			if sqrt(dx * dx + dz * dz) <= edge:
				cells.append(Vector2i(x, z))
	return cells


static func _stamp(grid: Array, cavern: Dictionary) -> void:
	for cell in cavern["cells"]:
		grid[cell.y][cell.x] = 0


## Rooms the cavern would cut into are dropped whole and filled back to rock, as a ramp bottom does.
static func _remove_rooms(grid: Array, layout: Dictionary, area: Rect2i) -> void:
	var kept := []
	for room_value in layout.get("rooms", []):
		var rect: Rect2i = (room_value as Dictionary).get("rect", Rect2i())
		if rect.grow(1).intersects(area):
			for z in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					grid[z][x] = 1
		else:
			kept.append(room_value)
	layout["rooms"] = kept


## One-cell slits cut into the rim, each ending in a dead end: tight places that only a runner fits.
static func _crevices(rng: SeededRandom, grid: Array, cavern: Dictionary) -> Array:
	var rect: Rect2i = cavern["rect"]
	var open := {}
	for cell in cavern["cells"]:
		open[cell] = true
	var found: Array = []
	var tries := 0
	while found.size() < CREVICES and tries < 40:
		tries += 1
		var cell: Vector2i = (cavern["cells"] as Array)[rng.next_index((cavern["cells"] as Array).size())]
		var dir: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.next_index(4)]
		# start on a rim cell whose neighbour in `dir` is rock
		if open.has(cell + dir) or not open.has(cell - dir):
			continue
		var slit: Array[Vector2i] = []
		var ok := true
		for step in range(1, CREVICE_DEPTH + 1):
			var at := cell + dir * step
			if at.x < 2 or at.y < 2 or at.x > CHUNK_SIZE - 3 or at.y > CHUNK_SIZE - 3 or grid[at.y][at.x] != 1:
				ok = false
				break
			# the slit's sides must be rock, or it is a corridor, not a crevice
			var side := Vector2i(dir.y, dir.x)
			if grid[(at + side).y][(at + side).x] != 1 or grid[(at - side).y][(at - side).x] != 1:
				ok = false
				break
			slit.append(at)
		var cap := cell + dir * (CREVICE_DEPTH + 1)
		if not ok or slit.size() < 3 or cap.x < 1 or cap.y < 1 or cap.x > CHUNK_SIZE - 2 or cap.y > CHUNK_SIZE - 2 \
				or grid[cap.y][cap.x] != 1:
			continue
		var near := false
		for other in found:
			if (other as Dictionary)["mouth"].distance_to(cell) < 6.0:
				near = true
		if near:
			continue
		for at in slit:
			grid[at.y][at.x] = 0
		found.append({"mouth": cell, "dir": dir, "cells": slit})
	return found


## A 5-wide hall from the cavern's middle to the nearest circulation cell outside it: along one axis, then the other.
static func _halls(rng: SeededRandom, grid: Array, layout: Dictionary, circulation: Dictionary, cavern: Dictionary,
		blocked: Array[Rect2i]) -> Array:
	var rect: Rect2i = cavern["rect"]
	var centre := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)
	var inside := {}
	for cell in cavern["cells"]:
		inside[cell] = true
	var best := Vector2i(-1, -1)
	var best_d := 1.0e9
	for cell_value in circulation:
		var cell: Vector2i = cell_value
		if inside.has(cell) or cell.x < 1 or cell.y < 1 or cell.x > CHUNK_SIZE - 2 or cell.y > CHUNK_SIZE - 2:
			continue
		var d := float(absi(cell.x - centre.x) + absi(cell.y - centre.y))
		if d < best_d:
			best_d = d
			best = cell
	var halls: Array = []
	if best.x < 0:
		return halls
	var horizontal_first := rng.next_float() < .5
	var half := HALL_WIDTH / 2
	var legs: Array[Rect2i] = []
	if horizontal_first:
		legs.append(_span(Vector2i(centre.x, centre.y), Vector2i(best.x, centre.y), half))
		legs.append(_span(Vector2i(best.x, centre.y), Vector2i(best.x, best.y), half))
	else:
		legs.append(_span(Vector2i(centre.x, centre.y), Vector2i(centre.x, best.y), half))
		legs.append(_span(Vector2i(centre.x, best.y), Vector2i(best.x, best.y), half))
	for leg in legs:
		_remove_rooms(grid, layout, leg.grow(1))
		for z in range(maxi(1, leg.position.y), mini(CHUNK_SIZE - 1, leg.end.y)):
			for x in range(maxi(1, leg.position.x), mini(CHUNK_SIZE - 1, leg.end.x)):
				if not _in_any(blocked, Vector2i(x, z)):
					grid[z][x] = 0
		halls.append(leg)
	return halls


static func _in_any(rects: Array[Rect2i], cell: Vector2i) -> bool:
	for rect in rects:
		if rect.has_point(cell):
			return true
	return false


static func _span(a: Vector2i, b: Vector2i, half: int) -> Rect2i:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(lo.x - half, lo.y - half, hi.x - lo.x + 2 * half + 1, hi.y - lo.y + 2 * half + 1)


static func _mark(circulation: Dictionary, rect: Rect2i) -> void:
	for z in range(maxi(0, rect.position.y), mini(CHUNK_SIZE, rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(CHUNK_SIZE, rect.end.x)):
			circulation[Vector2i(x, z)] = true


## Largest n such that the (2n+1)-square around `cell` is entirely walkable, capped at `limit`.
static func clearance(grid: Array, cell: Vector2i, limit: int = OPEN_CLEARANCE) -> int:
	var n := 0
	while n < limit:
		var next := n + 1
		for dz in range(-next, next + 1):
			for dx in range(-next, next + 1):
				var x := cell.x + dx
				var z := cell.y + dz
				if x < 0 or z < 0 or x >= CHUNK_SIZE or z >= CHUNK_SIZE or int(grid[z][x]) != 0:
					return n
		n = next
	return n


## The cells of every cavern in a built chunk's data, as a set.
static func cells_in(data: Dictionary) -> Dictionary:
	var set := {}
	for cavern in data.get("inferno_caverns", []):
		for cell in (cavern as Dictionary)["cells"]:
			set[cell] = true
	return set


## The cavern (or hall of one) a chunk-local cell stands in: its index in data["inferno_caverns"], or -1.
static func cavern_index_at(data: Dictionary, cell: Vector2i) -> int:
	var caverns: Array = data.get("inferno_caverns", [])
	for index in caverns.size():
		var cavern: Dictionary = caverns[index]
		if (cavern["cells"] as Array).has(cell):
			return index
		for hall in cavern["halls"]:
			if (hall as Rect2i).has_point(cell):
				return index
	return -1


## A chunk-local walkable cell with a clear 3x3, in the main cavern or a 5-wide hall: where a thrown-down item or
## a dump-hole drop lands. Falls back to the clearest cell nearest the middle. (-1, -1) if the chunk has none.
static func landing(data: Dictionary) -> Vector2i:
	var grid: Array = data.get("grid", [])
	if grid.is_empty():
		return Vector2i(-1, -1)
	var caverns: Array = data.get("inferno_caverns", [])
	if not caverns.is_empty():
		var rect: Rect2i = (caverns[0] as Dictionary)["rect"]
		var middle := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)
		if clearance(grid, middle, 1) >= 1:
			return middle
	var best := Vector2i(-1, -1)
	var best_score := -1.0e9
	var centre := Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
	for z in range(1, CHUNK_SIZE - 1):
		for x in range(1, CHUNK_SIZE - 1):
			var cell := Vector2i(x, z)
			if int(grid[z][x]) != 0 or clearance(grid, cell, 3) < 1:
				continue
			var score := float(clearance(grid, cell, 3)) * 10.0 - float(absi(x - centre.x) + absi(z - centre.y)) * .1
			if score > best_score:
				best_score = score
				best = cell
	return best


## The cage-pit district: a lava channel across the cavern (never walkable: its cells are rock to the walk grid) with a
## chain bridge over it, iron cages hanging from the ceiling at three heights, a row of cages standing against a wall
## and cracks glowing in the floor. Returns {} when the cavern is too small or the channel would cut it in two.
## "lava" cells are rock in `grid`; the generator also lists them as floor/structural voids, and the view draws them.
static func _pit(rng: SeededRandom, grid: Array, cavern: Dictionary) -> Dictionary:
	var rect: Rect2i = cavern["rect"]
	if rect.size.x < PIT_MIN_SPAN or rect.size.y < PIT_MIN_SPAN:
		return {}
	var open := {}
	for cell in cavern["cells"]:
		open[cell] = true
	var keep := {}             # halls, their margin and the crevices stay clear of lava
	for hall in cavern["halls"]:
		for z in range((hall as Rect2i).position.y - 2, (hall as Rect2i).end.y + 2):
			for x in range((hall as Rect2i).position.x - 2, (hall as Rect2i).end.x + 2):
				keep[Vector2i(x, z)] = true
	# the maze's own central cross (three wide) is never lava
	var middle := CHUNK_SIZE / 2
	for k in CHUNK_SIZE:
		for off in range(-2, 3):
			keep[Vector2i(k, middle + off)] = true
			keep[Vector2i(middle + off, k)] = true
	for crevice in cavern["crevices"]:
		for at in crevice["cells"]:
			keep[at] = true
		keep[crevice["mouth"]] = true
	var north := rng.next_float() < .5
	var band_z := rect.position.y + 3 if north else rect.end.y - 3 - PIT_BAND
	var bridge_x := rect.position.x + rect.size.x / 2 - PIT_BRIDGE / 2 + rng.next_index(5) - 2
	var lava: Array[Vector2i] = []
	for z in range(band_z, band_z + PIT_BAND):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, z)
			if not open.has(cell) or keep.has(cell) or (x >= bridge_x and x < bridge_x + PIT_BRIDGE):
				continue
			lava.append(cell)
	if lava.size() < 12:
		return {}
	for cell in lava:
		grid[cell.y][cell.x] = 1
	# every remaining cavern cell must still be one walk
	var rest: Array[Vector2i] = []
	for cell in cavern["cells"]:
		if grid[cell.y][cell.x] == 0:
			rest.append(cell)
	if not _connected(grid, rest):
		for cell in lava:
			grid[cell.y][cell.x] = 0
		return {}
	var lava_set := {}
	for cell in lava:
		lava_set[cell] = true
	var span := Rect2i(bridge_x, band_z, PIT_BRIDGE, PIT_BAND)
	# hanging cages: spread out, off the lava and the bridge, in open ground
	var cages: Array = []
	var tries := 0
	var lows := 0
	while cages.size() < 12 and tries < 120:
		tries += 1
		var cell: Vector2i = rest[rng.next_index(rest.size())]
		if clearance(grid, cell, 1) < 1 or span.grow(1).has_point(cell):
			continue
		var apart := true
		for other in cages:
			if (other["cell"] as Vector2i).distance_to(cell) < 3.0:
				apart = false
		if not apart:
			continue
		var roll := rng.next_float()
		var bottom := CAGE_HIGH
		if roll > .75 and lows < 3 and not keep.has(cell):
			bottom = CAGE_LOW
			lows += 1
		elif roll > .4:
			bottom = CAGE_UNDER
		cages.append({"cell": cell, "bottom": bottom, "sway": rng.next_float() < .5, "open": rng.next_float() < .35})
	# a row of cages against a wall: a straight run of rim cells with rock behind them
	var row: Array = []
	for _attempt in 40:
		var start: Vector2i = rest[rng.next_index(rest.size())]
		var run: Array = []
		for k in 5:
			var at := start + Vector2i(k, 0)
			if grid[at.y][at.x] != 0 or keep.has(at) or lava_set.has(at) or grid[at.y - 1][at.x] != 1 or grid[at.y + 1][at.x] != 0:
				break
			run.append(at)
		if run.size() >= 4:
			for at in run:
				row.append({"cell": at, "face": Vector2i(0, -1), "open": rng.next_float() < .3})
			break
	var cracks: Array = []
	for _i in 40:
		if cracks.size() >= 16:
			break
		var near: Vector2i = lava[rng.next_index(lava.size())] + Vector2i(rng.next_index(7) - 3, rng.next_index(7) - 3)
		if grid[near.y][near.x] == 0 and open.has(near) and not span.has_point(near):
			cracks.append({"cell": near, "yaw": rng.next_float() * PI, "length": 1.2 + rng.next_float() * 2.2})
	return {"lava": lava, "bridge": span, "cages": cages, "row": row, "cracks": cracks, "north": north}


static func _connected(grid: Array, cells: Array[Vector2i]) -> bool:
	if cells.is_empty():
		return true
	var set := {}
	for cell in cells:
		set[cell] = true
	var seen := {cells[0]: true}
	var queue: Array[Vector2i] = [cells[0]]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + step
			if set.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == set.size()


## Every pit in a chunk's data (those caverns that have one).
static func pits_in(data: Dictionary) -> Array:
	var pits: Array = []
	for cavern in data.get("inferno_caverns", []):
		if not (cavern as Dictionary).get("pit", {}).is_empty():
			pits.append(cavern["pit"])
	return pits
