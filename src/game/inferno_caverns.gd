class_name InfernoCaverns
extends RefCounted

## Level -3 is a cave network, not a maze (KT: "a different style of layout instead of copying the maze above it").
## Per chunk, deterministic from the world seed and the chunk coordinate: a middle chamber and one or two more
## (rough blobs 10-22 cells across, some with natural pillars, a rim of one-cell dead-end crevices, high ceilings),
## joined to each other, to every seam opening and to the ramp landings by winding tunnels 3-5 cells wide whose width
## wanders. The cage-pit district (lava channel, chain bridge, hanging cages) is one chamber type.
## Everything runs on the walk grid only; the view reads the chamber data.

const CHUNK_SIZE := 45
const MARGIN := 6                    # keeps a chamber off the seam openings
const MIN_SPAN := 14
const MAX_SPAN := 22
const CHAMBERS_EXTRA := Vector2i(1, 2)
const TUNNEL_RADIUS := Vector2(2.0, 2.9)   # a cell centre within this of the path is open: 3 to 5 wide
const WIGGLE := 6.0
const CREVICES := 3
const CREVICE_DEPTH := 4
const PILLARS := Vector2i(3, 6)
const PIT_CHANCE := 0.6
const PIT_MIN_SPAN := 16
const PIT_BAND := 3                  # width of the lava channel
const PIT_BRIDGE := 3                # width of the span across it
const CAGE_CAP := 3.9                # the storey cap the caverns rise to (LEVEL_HEIGHT - SLAB)
const CAGE_HEIGHT := 1.0
const CAGE_HIGH := 2.5               # bottom heights above the floor: high, low enough to walk under, and in the way
const CAGE_UNDER := 2.1
const CAGE_LOW := 0.75
const OPEN_CLEARANCE := 3            # a 7x7 fully open block is clearance 3
const HALL_WIDTH := 3                # the narrowest a tunnel runs (kept for the checks)


## Carves the cave network into `grid` (all rock on entry) and returns the chambers as
## {"rect", "cells", "halls", "crevices", "pillars", "tunnel_cells", "pit"?} dictionaries. `edges` are the seam openings
## (offsets along each side), `ramps` the ramp landings that must be reachable, `safe` a safe-room chunk (its middle
## stays one open chamber). `circulation` receives every open cell.
static func carve(world_seed: String, coord: Vector3i, grid: Array, edges: Dictionary, ramps: Array, safe: bool,
		circulation: Dictionary, tunnels: Array = []) -> Array:
	var rng := SeededRandom.new("%s:INFERNO-CAVE:%d:%d:%d" % [world_seed, coord.x, coord.y, coord.z])
	var middle := Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
	var keep_out: Array[Rect2i] = []
	var anchors: Array[Vector2i] = []
	for ramp in ramps:
		for part in ["ramp", "bottom", "connector"]:
			keep_out.append((ramp[part] as Rect2i).grow(3))
		var bottom: Rect2i = ramp["bottom"]
		anchors.append(Vector2i(bottom.position.x + bottom.size.x / 2, bottom.position.y + bottom.size.y / 2))
	# chambers: the middle one first, then up to two more that keep their distance
	var chambers: Array = []
	var first_rect := Rect2i(0, 0, MIN_SPAN + 2 + rng.next_index(MAX_SPAN - MIN_SPAN - 1), MIN_SPAN + 2 + rng.next_index(MAX_SPAN - MIN_SPAN - 1))
	if safe:
		first_rect.size = Vector2i(MIN_SPAN, MIN_SPAN)
	# the middle chamber keeps off the ramp landings: try nearby spots, then a smaller chamber
	var settled := false
	for attempt in 30:
		var jitter := Vector2i(rng.next_index(17) - 8, rng.next_index(17) - 8) if attempt > 0 else Vector2i.ZERO
		first_rect.position = middle - first_rect.size / 2 + jitter
		var clash := first_rect.position.x < MARGIN or first_rect.position.y < MARGIN or first_rect.end.x > CHUNK_SIZE - MARGIN or first_rect.end.y > CHUNK_SIZE - MARGIN
		for blocked in keep_out:
			if first_rect.grow(1).intersects(blocked):
				clash = true
		if not clash:
			settled = true
			break
		if attempt == 20:
			first_rect.size = Vector2i(MIN_SPAN, MIN_SPAN)
	if not settled:
		first_rect.position = middle - first_rect.size / 2
	chambers.append(_chamber(rng, first_rect))
	var links := {}
	# every seam opening and ramp landing runs to the nearest chamber
	var portals: Array[Vector2i] = []
	var stubs: Array[Rect2i] = []
	for side in ["west", "east", "north", "south"]:
		for offset_value in edges.get(side, []):
			var offset := int(offset_value)
			var edge := Vector2i(0, offset)
			var inner := Vector2i(3, offset)
			match side:
				"east":
					edge = Vector2i(CHUNK_SIZE - 1, offset)
					inner = Vector2i(CHUNK_SIZE - 4, offset)
				"north":
					edge = Vector2i(offset, 0)
					inner = Vector2i(offset, 3)
				"south":
					edge = Vector2i(offset, CHUNK_SIZE - 1)
					inner = Vector2i(offset, CHUNK_SIZE - 4)
			stubs.append(_carve_stub(grid, edge, inner, side))
			portals.append(inner)
	for portal in portals:
		_link(rng, grid, tunnels, links, portal, chambers, 0, "portal", -1)
	for anchor in anchors:
		_link(rng, grid, tunnels, links, anchor, chambers, 0, "anchor", -1)
	# Side chambers go into rock the seam and ramp tunnels leave alone, and hang off the middle one by a single tunnel: so
	# each is a real wing a gate on that tunnel can shut (SealPlanner).
	var extra := CHAMBERS_EXTRA.x + rng.next_index(CHAMBERS_EXTRA.y - CHAMBERS_EXTRA.x + 1)
	for _i in extra:
		var placed := _place(rng, grid, chambers, keep_out)
		if not placed.is_empty():
			chambers.append(placed)
			_link(rng, grid, tunnels, links, _centre(placed), chambers, 0, "hang", chambers.size() - 1)
	for chamber in chambers:
		for cell in chamber["cells"]:
			grid[cell.y][cell.x] = 0
	_close_slivers(grid, ramps, stubs)
	for chamber in chambers:
		chamber["tunnel_cells"] = links
		chamber["pillars"] = _pillars(rng, grid, chamber, links)
	_close_slivers(grid, ramps, stubs)
	for chamber in chambers:
		chamber["crevices"] = _crevices(rng, grid, chamber)
		if rng.next_float() < PIT_CHANCE and not safe:
			chamber["pit"] = _pit(rng, grid, chamber, keep_out)
	# a last pass over everything the pits and crevices left behind, sparing what they placed
	var spared := {}
	for chamber in chambers:
		for slit in chamber["crevices"]:
			spared[slit["mouth"]] = true
			for at in slit["cells"]:
				spared[at] = true
		var pit: Dictionary = chamber.get("pit", {})
		if not pit.is_empty():
			for z in range((pit["bridge"] as Rect2i).position.y - 1, (pit["bridge"] as Rect2i).end.y + 1):
				for x in range((pit["bridge"] as Rect2i).position.x - 1, (pit["bridge"] as Rect2i).end.x + 1):
					spared[Vector2i(x, z)] = true
			for cage in pit["cages"]:
				spared[cage["cell"]] = true
			for entry in pit["row"]:
				spared[entry["cell"]] = true
	_close_slivers(grid, ramps, stubs, spared)
	_drop_islands(grid, _centre(chambers[0]))
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if grid[z][x] == 0:
				circulation[Vector2i(x, z)] = true
	return chambers


## Rock fills any open cell that is not in a fully open 3x3 block (ragged rims, notches between a tunnel and a chamber),
## until none is left; the seam mouths and the ramp landings are kept as carved.
static func _close_slivers(grid: Array, ramps: Array, stubs: Array[Rect2i], protect: Dictionary = {}) -> void:
	protect = protect.duplicate()
	for rect in stubs:
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				protect[Vector2i(x, z)] = true
	for ramp in ramps:
		for part in ["bottom", "connector"]:
			var rect: Rect2i = ramp[part]
			for z in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					protect[Vector2i(x, z)] = true
	for _round in 12:
		var covered := {}
		for z in range(1, CHUNK_SIZE - 1):
			for x in range(1, CHUNK_SIZE - 1):
				if clearance(grid, Vector2i(x, z), 1) >= 1:
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							covered[Vector2i(x + dx, z + dz)] = true
		var closed := 0
		for z in range(1, CHUNK_SIZE - 1):
			for x in range(1, CHUNK_SIZE - 1):
				var at := Vector2i(x, z)
				if grid[z][x] == 0 and not covered.has(at) and not protect.has(at):
					grid[z][x] = 1
					closed += 1
		if closed == 0:
			return


## Open ground the middle chamber cannot reach (a pocket the sliver pass or a pillar cut off) goes back to rock.
static func _drop_islands(grid: Array, from: Vector2i) -> void:
	var seen := PackedByteArray()
	seen.resize(CHUNK_SIZE * CHUNK_SIZE)
	var start := from
	if grid[start.y][start.x] != 0:
		return
	var stack := PackedInt32Array([start.y * CHUNK_SIZE + start.x])
	seen[start.y * CHUNK_SIZE + start.x] = 1
	while not stack.is_empty():
		var at := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x := at % CHUNK_SIZE
		var z := at / CHUNK_SIZE
		for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = x + step[0]
			var nz: int = z + step[1]
			if nx < 0 or nz < 0 or nx >= CHUNK_SIZE or nz >= CHUNK_SIZE or seen[nz * CHUNK_SIZE + nx] == 1 or grid[nz][nx] != 0:
				continue
			seen[nz * CHUNK_SIZE + nx] = 1
			stack.append(nz * CHUNK_SIZE + nx)
	for z in range(1, CHUNK_SIZE - 1):
		for x in range(1, CHUNK_SIZE - 1):
			if grid[z][x] == 0 and seen[z * CHUNK_SIZE + x] == 0:
				grid[z][x] = 1


static func _chamber(rng: SeededRandom, rect: Rect2i) -> Dictionary:
	return {"rect": rect, "cells": _blob(rng, rect), "halls": [], "crevices": [], "pillars": [], "tunnel_cells": {}}


static func _centre(chamber: Dictionary) -> Vector2i:
	var rect: Rect2i = chamber["rect"]
	return Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)


static func _nearest(chambers: Array, from: Vector2i) -> int:
	var best := 0
	var best_d := 1.0e9
	for index in chambers.size():
		var d := float(from.distance_to(_centre(chambers[index])))
		if d < best_d:
			best_d = d
			best = index
	return best


## A chamber 14-18 cells across somewhere clear of the others, the border margin and the ramp landings.
static func _place(rng: SeededRandom, grid: Array, chambers: Array, keep_out: Array[Rect2i]) -> Dictionary:
	# side chambers are smaller (9-14 across) and, when the chunk is crowded, smaller still (7-9)
	for attempt in 2:
		var low := 9 if attempt == 0 else 7
		var width := low + rng.next_index(6 if attempt == 0 else 3)
		var depth := low + rng.next_index(6 if attempt == 0 else 3)
		var found := _place_sized(rng, grid, chambers, keep_out, width, depth)
		if not found.is_empty():
			return found
	return {}


static func _place_sized(rng: SeededRandom, grid: Array, chambers: Array, keep_out: Array[Rect2i], width: int, depth: int) -> Dictionary:
	var spots: Array[Vector2i] = []
	for z in range(4, CHUNK_SIZE - 4 - depth + 1, 1):
		for x in range(4, CHUNK_SIZE - 4 - width + 1, 1):
			spots.append(Vector2i(x, z))
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.next_index(i + 1)
		var swap := spots[i]
		spots[i] = spots[j]
		spots[j] = swap
	for spot in spots:
		var rect := Rect2i(spot.x, spot.y, width, depth)
		var clash := false
		for other in chambers:
			if rect.grow(2).intersects((other as Dictionary)["rect"]):
				clash = true
				break
		for blocked in keep_out:
			if rect.grow(1).intersects(blocked):
				clash = true
				break
		# rock all round: no open cell within two of the chamber
		if not clash:
			for z in range(maxi(0, rect.position.y - 2), mini(CHUNK_SIZE, rect.end.y + 2)):
				for x in range(maxi(0, rect.position.x - 2), mini(CHUNK_SIZE, rect.end.x + 2)):
					if grid[z][x] == 0:
						clash = true
						break
				if clash:
					break
		if not clash:
			return _chamber(rng, rect)
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
			if x < 1 or z < 1 or x > CHUNK_SIZE - 2 or z > CHUNK_SIZE - 2:
				continue
			var dx := (x + .5 - cx) / rx
			var dz := (z + .5 - cz) / rz
			var angle := atan2(dz, dx)
			var edge := 0.94 + .06 * sin(angle * 3.0 + phase_a) - .04 * sin(angle * 5.0 + phase_b)
			if sqrt(dx * dx + dz * dz) <= edge:
				cells.append(Vector2i(x, z))
	return cells


## The three-wide mouth on the seam and the stub in to where the tunnel proper starts.
static func _carve_stub(grid: Array, edge: Vector2i, inner: Vector2i, side: String) -> Rect2i:
	var horizontal := side == "west" or side == "east"
	var lo := Vector2i(mini(edge.x, inner.x), mini(edge.y, inner.y))
	var hi := Vector2i(maxi(edge.x, inner.x), maxi(edge.y, inner.y))
	var rect := Rect2i(lo.x - (0 if horizontal else 1), lo.y - (1 if horizontal else 0), hi.x - lo.x + (1 if horizontal else 3),
		hi.y - lo.y + (3 if horizontal else 1))
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			grid[z][x] = 0
	return rect


## A winding tunnel from `from` to the chamber's middle: the path bends through a couple of offset points and its radius
## wanders between TUNNEL_RADIUS.x and .y, so it is never narrower than three cells.
static func _link(rng: SeededRandom, grid: Array, tunnels: Array, links: Dictionary, from: Vector2i, chambers: Array,
		to_index: int, kind: String, from_index: int) -> void:
	var to := _centre(chambers[to_index])
	var a := Vector2(from) + Vector2(.5, .5)
	var b := Vector2(to) + Vector2(.5, .5)
	var along := (b - a)
	var length := along.length()
	if length < 2.0:
		return
	var side := Vector2(-along.y, along.x).normalized()
	var points: Array[Vector2] = [a]
	var bends := 1 + int(length / 18.0)
	for k in range(1, bends + 1):
		var t := float(k) / (bends + 1)
		points.append(a + along * t + side * (rng.next_float() * 2.0 - 1.0) * minf(WIGGLE, length * .3))
	points.append(b)
	var phase := rng.next_float() * TAU
	var walked := 0.0
	var samples: Array[Vector2] = []
	for i in range(points.size() - 1):
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		var segment := p1.distance_to(p2)
		var steps := maxi(2, int(segment / .5))
		for k in steps:
			var t := float(k) / steps
			samples.append(_spline(p0, p1, p2, p3, t))
	samples.append(b)
	for sample in samples:
		var radius := TUNNEL_RADIUS.x + (TUNNEL_RADIUS.y - TUNNEL_RADIUS.x) * (.5 + .5 * sin(walked * .35 + phase))
		walked += .5
		var reach := int(ceil(radius))
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var cell := Vector2i(int(floor(sample.x)) + dx, int(floor(sample.y)) + dz)
				if cell.x < 1 or cell.y < 1 or cell.x > CHUNK_SIZE - 2 or cell.y > CHUNK_SIZE - 2:
					continue
				if Vector2(cell.x + .5, cell.y + .5).distance_to(sample) <= radius:
					grid[cell.y][cell.x] = 0
					links[cell] = true
	# the tunnel's path, for the seal planner: kind "portal"/"anchor" run from a seam or ramp landing (from_chamber -1) to a
	# chamber, "hang" from an extra chamber to the middle one, "loop" between two extras
	var radii := PackedFloat32Array()
	var walk := 0.0
	for k in samples.size():
		radii.append(TUNNEL_RADIUS.x + (TUNNEL_RADIUS.y - TUNNEL_RADIUS.x) * (.5 + .5 * sin(float(k) * .5 * .35 + phase)))
	tunnels.append({"kind": kind, "from": from, "to": to, "from_chamber": from_index, "to_chamber": to_index,
		"samples": samples, "radii": radii})


static func _spline(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return .5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Natural pillars: single rock cells standing in a chamber's open ground, off the tunnels' mouths and apart.
static func _pillars(rng: SeededRandom, grid: Array, chamber: Dictionary, links: Dictionary) -> Array:
	var want := PILLARS.x + rng.next_index(PILLARS.y - PILLARS.x + 1)
	var centre := _centre(chamber)
	var pillars: Array = []
	var cells: Array = chamber["cells"]
	var tries := 0
	while pillars.size() < want and tries < 80:
		tries += 1
		var cell: Vector2i = cells[rng.next_index(cells.size())]
		if cell.distance_to(centre) < 3.5 or links.has(cell) or clearance(grid, cell, 3) < 2:
			continue
		var apart := true
		for other in pillars:
			if (other as Vector2i).distance_to(cell) < 4.0:
				apart = false
		if apart:
			pillars.append(cell)
	for cell in pillars:
		grid[cell.y][cell.x] = 1
	return pillars


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
			# everything around the slit must be rock (bar its own path and mouth), or it is a corridor or touches
			# another slit, not a crevice
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var near := at + Vector2i(dx, dz)
					if near == cell + dir * (step - 1) or near == at:
						continue
					if slit.has(near) or (step == 1 and near.distance_to(cell) <= 1.5):
						continue
					if grid[near.y][near.x] != 1:
						ok = false
			if not ok:
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


## The cage-pit district: a lava channel across the cavern (never walkable: its cells are rock to the walk grid) with a
## chain bridge over it, iron cages hanging from the ceiling at three heights, a row of cages standing against a wall
## and cracks glowing in the floor. Returns {} when the cavern is too small or the channel would cut it in two.
## "lava" cells are rock in `grid`; the generator also lists them as floor/structural voids, and the view draws them.
static func _pit(rng: SeededRandom, grid: Array, cavern: Dictionary, keep_out: Array[Rect2i]) -> Dictionary:
	var rect: Rect2i = cavern["rect"]
	if rect.size.x < PIT_MIN_SPAN or rect.size.y < PIT_MIN_SPAN:
		return {}
	var open := {}
	for cell in cavern["cells"]:
		open[cell] = true
	var keep := {}             # tunnel mouths, pillars, crevices and the ramp landings stay clear of lava
	for cell_value in cavern["tunnel_cells"]:
		var cell: Vector2i = cell_value
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				keep[cell + Vector2i(dx, dz)] = true
	for blocked in keep_out:
		for z in range(blocked.position.y, blocked.end.y):
			for x in range(blocked.position.x, blocked.end.x):
				keep[Vector2i(x, z)] = true
	for pillar in cavern["pillars"]:
		keep[pillar] = true
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
	for z in range(span.position.y, span.end.y):
		for x in range(span.position.x, span.end.x):
			grid[z][x] = 0                      # a pillar in the way of the span comes out
	cavern["pillars"] = (cavern["pillars"] as Array).filter(func(p): return not span.has_point(p))
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
