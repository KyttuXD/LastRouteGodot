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
