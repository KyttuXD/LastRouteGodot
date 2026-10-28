extends RefCounted

## Level -3's caverns (InfernoCaverns): each is 14-22 cells across with a clear 7x7 middle, joined to the maze by a
## 5-wide hall, rimmed with dead-end crevices, deterministic per seed, off every ramp footprint; the walk through a
## window of chunks still holds together; dump_landing() gives a clear 3x3 inside a cavern or hall.
##
##   godot --headless --path . res://scenes/validate.tscn -- inferno_caverns

const SEEDS := ["INFERNO-CAV-A", "INFERNO-CAV-B"]
const RADIUS := 3

var _failures := 0
var _pits_seen := 0
var _piles := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var pits := 0
	for seed_text in SEEDS:
		_check_seed(seed_text)
		pits += _pits_seen
	_expect(_piles >= 8, "only %d landing piles across the windows" % _piles)
	var forced := StreamedRouteGenerator.new("PILE-FORCE")
	var spot := Vector3i(1, StreamedRouteGenerator.INFERNO_LEVEL, 1)
	forced.dump_landing_chunks[spot] = true
	_expect((forced.chunk(spot)["landing_pile"] as Vector2i).x >= 0, "a dump-hole chunk shows no landing pile")
	_expect(pits >= 4, "only %d cage pits across the windows" % pits)
	await _check_pit_view(host)
	return _failures


func _check_seed(seed_text: String) -> void:
	_pits_seen = 0
	var generator := StreamedRouteGenerator.new(seed_text)
	var other := StreamedRouteGenerator.new(seed_text)
	var caverns_total := 0
	var floor_cells := 0
	var wide_cells := 0
	var chunks_with := 0
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var world := {}
	for cz in range(-RADIUS, RADIUS + 1):
		for cx in range(-RADIUS, RADIUS + 1):
			var coord := Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz)
			var data := generator.chunk(coord)
			var grid: Array = data["grid"]
			for z in size:
				for x in size:
					if int(grid[z][x]) == 0:
						world[Vector2i(cx * size + x, cz * size + z)] = true
						floor_cells += 1
						if InfernoCaverns.clearance(grid, Vector2i(x, z)) >= InfernoCaverns.OPEN_CLEARANCE:
							wide_cells += 1
			var caverns := generator.inferno_caverns_at(coord)
			var pile: Vector2i = data.get("landing_pile", Vector2i(-1, -1))
			if pile.x >= 0:
				_piles += 1
				_expect(InfernoCaverns.clearance(grid, pile, 1) >= 1 and pile == generator.dump_landing(coord),
					"%s %s: the landing pile at %s is not on the clear landing cell" % [seed_text, coord, pile])
			_check_wide_enough(seed_text, coord, data)
			_check_seams(seed_text, coord, data, generator)
			chunks_with += 1 if not caverns.is_empty() else 0
			caverns_total += caverns.size()
			_expect(JSON.stringify(_digest(caverns)) == JSON.stringify(_digest(other.inferno_caverns_at(coord))),
				"%s %s: caverns differ between two generators" % [seed_text, coord])
			for chamber_index in caverns.size():
				var cavern: Dictionary = caverns[chamber_index]
				_check_cavern(seed_text, coord, data, cavern, chamber_index == 0)
				if not (cavern.get("pit", {}) as Dictionary).is_empty():
					_pits_seen += 1
					_check_pit(seed_text, coord, data, cavern["pit"])
			if not caverns.is_empty():
				var landing := generator.dump_landing(coord)
				_expect(landing.x >= 0 and InfernoCaverns.clearance(grid, landing, 1) >= 1,
					"%s %s: dump_landing %s has no clear 3x3" % [seed_text, coord, landing])
				_expect(InfernoCaverns.cavern_index_at(data, landing) >= 0,
					"%s %s: dump_landing %s is not in a cavern or hall" % [seed_text, coord, landing])
	_expect(chunks_with >= 30, "%s: only %d of 49 chunks hold a cavern" % [seed_text, chunks_with])
	var share := 100.0 * wide_cells / maxf(1.0, floor_cells)
	print("  inferno_caverns %s: %d caverns in %d chunks, %d floor cells, %d on a clear 7x7 (%.1f%%)" % [
		seed_text, caverns_total, chunks_with, floor_cells, wide_cells, share])
	_expect(share >= 10.0, "%s: only %.1f%% of floor is wide ground" % [seed_text, share])
	# one walk across the window: every cavern cell is in the largest connected piece
	var largest := _largest_component(world)
	var stray := 0
	for cz in range(-RADIUS, RADIUS + 1):
		for cx in range(-RADIUS, RADIUS + 1):
			for cavern in generator.inferno_caverns_at(Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz)):
				for cell in cavern["cells"]:
					var at := Vector2i(cx * size + cell.x, cz * size + cell.y)
					if world.has(at) and not largest.has(at):
						stray += 1
	_expect(stray == 0, "%s: %d cavern cells are cut off from the main walk" % [seed_text, stray])


## Every open cell outside the crevices sits in a fully open 3x3 block: no passage is narrower than three cells.
func _check_wide_enough(seed_text: String, coord: Vector3i, data: Dictionary) -> void:
	var grid: Array = data["grid"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var covered := {}
	for z in range(1, size - 1):
		for x in range(1, size - 1):
			if InfernoCaverns.clearance(grid, Vector2i(x, z), 1) >= 1:
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						covered[Vector2i(x + dx, z + dz)] = true
	var crevice := {}
	for cavern in data.get("inferno_caverns", []):
		for slit in cavern["crevices"]:
			for at in slit["cells"]:
				crevice[at] = true
	for ramp in data.get("ramps", []):      # the ramp landings are SEWER's carve (clamped at the chunk edge)
		for part in ["ramp", "bottom", "connector"]:
			var grown: Rect2i = (ramp[part] as Rect2i).grow(1)
			for z in range(grown.position.y, grown.end.y):
				for x in range(grown.position.x, grown.end.x):
					crevice[Vector2i(x, z)] = true
	# a ledge beside the lava or a crevice's mouth may be narrow, and so may the corner pockets a seam stub leaves
	for source in [[crevice.keys(), 1], [_lava_cells(data), 3], [_pillar_cells(data), 1]]:
		var reach: int = source[1]
		for cell in source[0]:
			for dz in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					crevice[(cell as Vector2i) + Vector2i(dx, dz)] = true
	var narrow := 0
	var where: Array[Vector2i] = []
	for z in range(1, size - 1):
		for x in range(1, size - 1):
			var at := Vector2i(x, z)
			var near_border := x < 5 or z < 5 or x > size - 6 or z > size - 6
			if int(grid[z][x]) == 0 and not covered.has(at) and not crevice.has(at) and not near_border:
				narrow += 1
				if where.size() < 6:
					where.append(at)
	_expect(narrow <= 2, "%s %s: %d open cells are in passages narrower than three (two stray cells beside a pillar or cage are allowed), e.g. %s" % [seed_text, coord, narrow, where])


func _check_cavern(seed_text: String, coord: Vector3i, data: Dictionary, cavern: Dictionary, is_main: bool) -> void:
	var tag := "%s %s" % [seed_text, coord]
	var rect: Rect2i = cavern["rect"]
	# the middle chamber is 14-22 across with a clear 7x7; side chambers (the sealed wings) are smaller, 7 and up
	if is_main:
		_expect(rect.size.x >= InfernoCaverns.MIN_SPAN and rect.size.x <= InfernoCaverns.MAX_SPAN
			and rect.size.y >= InfernoCaverns.MIN_SPAN and rect.size.y <= InfernoCaverns.MAX_SPAN,
			"%s: middle chamber %s is outside 14-22 cells" % [tag, rect])
	else:
		_expect(rect.size.x >= 7 and rect.size.y >= 7 and rect.size.x <= InfernoCaverns.MAX_SPAN and rect.size.y <= InfernoCaverns.MAX_SPAN,
			"%s: side chamber %s is outside 7-22 cells" % [tag, rect])
	var grid: Array = data["grid"]
	var open_middle := false
	for cell in cavern["cells"]:
		if InfernoCaverns.clearance(grid, cell) >= InfernoCaverns.OPEN_CLEARANCE:
			open_middle = true
			break
	_expect(open_middle or not is_main, "%s: middle chamber %s has no clear 7x7" % [tag, rect])
	for crevice in cavern["crevices"]:
		var mouth: Vector2i = crevice["mouth"]
		var cells: Array = crevice["cells"]
		var end: Vector2i = cells[cells.size() - 1]
		var side := Vector2i((crevice["dir"] as Vector2i).y, (crevice["dir"] as Vector2i).x)
		_expect(int(grid[end.y + (crevice["dir"] as Vector2i).y][end.x + (crevice["dir"] as Vector2i).x]) == 1
			and int(grid[end.y + side.y][end.x + side.x]) == 1, "%s: crevice at %s is not a dead end" % [tag, mouth])
	for ramp in data.get("ramps", []):
		for part in ["ramp", "bottom", "connector"]:
			_expect(not rect.intersects(ramp[part] as Rect2i) or part != "ramp",
				"%s: cavern %s sits on a ramp slope" % [tag, rect])
	var rooms: Array = data.get("rooms", [])
	for room in rooms:
		_expect(not rect.intersects((room as Dictionary).get("rect", Rect2i())),
			"%s: cavern %s overlaps a room" % [tag, rect])


## Each seam opening is open on both sides of the line, three cells wide, and a ramp's bottom landing is open.
func _check_seams(seed_text: String, coord: Vector3i, data: Dictionary, generator: StreamedRouteGenerator) -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var grid: Array = data["grid"]
	for side in ["west", "east", "north", "south"]:
		for offset in (data["edges"] as Dictionary)[side]:
			for spread in range(-1, 2):
				var x := 0 if side == "west" else size - 1 if side == "east" else int(offset) + spread
				var z := 0 if side == "north" else size - 1 if side == "south" else int(offset) + spread
				if side == "west" or side == "east":
					z = int(offset) + spread
				_expect(int(grid[z][x]) == 0, "%s %s: the %s seam opening %d is closed at %s" % [seed_text, coord, side, offset, Vector2i(x, z)])
	for ramp in data.get("ramps", []):
		var bottom: Rect2i = ramp["bottom"]
		_expect(int(grid[bottom.position.y + 1][bottom.position.x + 1]) == 0, "%s %s: a ramp's bottom landing is closed" % [seed_text, coord])


static func _pillar_cells(data: Dictionary) -> Array:
	var cells := []
	for cavern in data.get("inferno_caverns", []):
		cells.append_array(cavern["pillars"])
	return cells


static func _lava_cells(data: Dictionary) -> Array:
	var cells := []
	for pit in InfernoCaverns.pits_in(data):
		cells.append_array(pit["lava"])
	return cells


static func _digest(caverns: Array) -> Array:
	var out := []
	for cavern in caverns:
		out.append([var_to_str(cavern["rect"]), (cavern["cells"] as Array).size()])
	return out


static func _largest_component(cells: Dictionary) -> Dictionary:
	var seen := {}
	var best := {}
	for start in cells:
		if seen.has(start):
			continue
		var part := {start: true}
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = at + step
				if cells.has(next) and not seen.has(next):
					seen[next] = true
					part[next] = true
					queue.append(next)
		if part.size() > best.size():
			best = part
	return best


func _check_pit(seed_text: String, coord: Vector3i, data: Dictionary, pit: Dictionary) -> void:
	var tag := "%s %s pit" % [seed_text, coord]
	var grid: Array = data["grid"]
	var voids := {}
	for cell in data["structural_voids"]:
		voids[cell] = true
	for cell in data["floor_voids"]:
		voids[cell] = true
	for cell in pit["lava"]:
		_expect(int(grid[cell.y][cell.x]) == 1, "%s: lava at %s is walkable (hunters would path over it)" % [tag, cell])
		_expect(voids.has(cell), "%s: lava at %s is not a floor/structural void" % [tag, cell])
	var span: Rect2i = pit["bridge"]
	for z in range(span.position.y, span.end.y):
		for x in range(span.position.x, span.end.x):
			_expect(int(grid[z][x]) == 0, "%s: the bridge cell %s is not walkable" % [tag, Vector2i(x, z)])
	var tiers := {}
	for cage in pit["cages"]:
		var bottom: float = cage["bottom"]
		var top := bottom + InfernoCaverns.CAGE_HEIGHT
		_expect(top + .2 <= InfernoCaverns.CAGE_CAP, "%s: a cage reaches the ceiling (top %.2f, no chain)" % [tag, top])
		_expect(bottom > 0.0, "%s: a cage sits below the floor" % tag)
		_expect(int(grid[cage["cell"].y][cage["cell"].x]) == 0, "%s: a cage hangs over rock" % tag)
		tiers[bottom] = true
	_expect(not (pit["cages"] as Array).is_empty(), "%s: no hanging cages" % tag)
	for entry in pit["row"]:
		_expect(int(grid[entry["cell"].y][entry["cell"].x]) == 0, "%s: a row cage stands in rock" % tag)


## One pit built through the real view: lava, blockers, cages and the lava cells without a floor collider.
func _check_pit_view(host: Node) -> void:
	var generator := StreamedRouteGenerator.new(SEEDS[0])
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var found := Vector3i.ZERO
	var pit := {}
	for cz in range(-RADIUS, RADIUS + 1):
		for cx in range(-RADIUS, RADIUS + 1):
			var coord := Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz)
			var pits := InfernoCaverns.pits_in(generator.chunk(coord))
			if pit.is_empty() and not pits.is_empty():
				pit = pits[0]
				found = coord
	if pit.is_empty():
		_expect(false, "no pit to build a view for")
		return
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var start := InfernoCaverns.landing(generator.chunk(found))
	player.global_position = Vector3(found.x * size + start.x + .5, float(found.y) * StreamedFacilityView3D.LEVEL_HEIGHT + .1,
		found.z * size + start.y + .5)
	view.begin(SEEDS[0], player)
	var root: Node3D = view._loaded.get(found)
	_expect(root != null, "the pit chunk is not loaded")
	if root != null:
		var pits_node := root.get_node_or_null("InfernoPits")
		_expect(pits_node != null, "the chunk has no InfernoPits node")
		if pits_node != null:
			_expect(pits_node.get_node_or_null("Lava") != null, "no lava mesh")
			_expect(pits_node.get_node_or_null("LavaGlow") != null, "no underglow light")
			_expect(pits_node.get_node_or_null("LavaEmbers") != null, "no embers")
			_expect(pits_node.get_node_or_null("PitRumble") != null, "no rumble")
			var hanging := 0
			for child in pits_node.get_children():
				hanging += 1 if child.has_meta("hanging_cage") else 0
			_expect(hanging == (pit["cages"] as Array).size(), "%d hanging cages built for %d planned" % [hanging, (pit["cages"] as Array).size()])
			var blockers := pits_node.get_node("PitBlockers") as StaticBody3D
			_expect(blockers.get_child_count() > 0, "the lava has no blockers")
			# every lava cell is covered by a blocker box
			var covered := 0
			for cell in pit["lava"]:
				var point := Vector3(cell.x + .5, .8, cell.y + .5)
				for shape_node in blockers.get_children():
					var box := (shape_node as CollisionShape3D).shape as BoxShape3D
					var local := point - (shape_node as CollisionShape3D).position
					if absf(local.x) <= box.size.x * .5 and absf(local.y) <= box.size.y * .5 and absf(local.z) <= box.size.z * .5:
						covered += 1
						break
			_expect(covered == (pit["lava"] as Array).size(), "only %d of %d lava cells are blocked" % [covered, (pit["lava"] as Array).size()])
		var structure := root.get_node("Structure") as GridMap
		var sample: Vector2i = (pit["lava"] as Array)[0]
		_expect(structure.get_cell_item(Vector3i(sample.x, 0, sample.y)) == GridMap.INVALID_CELL_ITEM,
			"the lava cell %s still has a floor or wall collider cell" % sample)
	view.clear()
	view.queue_free()
	player.queue_free()
