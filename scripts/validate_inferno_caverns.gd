extends RefCounted

## Level -3's caverns (InfernoCaverns): each is 14-22 cells across with a clear 7x7 middle, joined to the maze by a
## 5-wide hall, rimmed with dead-end crevices, deterministic per seed, off every ramp footprint; the walk through a
## window of chunks still holds together; dump_landing() gives a clear 3x3 inside a cavern or hall.
##
##   godot --headless --path . res://scenes/validate.tscn -- inferno_caverns

const SEEDS := ["INFERNO-CAV-A", "INFERNO-CAV-B"]
const RADIUS := 3

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	for seed_text in SEEDS:
		_check_seed(seed_text)
	return _failures


func _check_seed(seed_text: String) -> void:
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
			chunks_with += 1 if not caverns.is_empty() else 0
			caverns_total += caverns.size()
			_expect(JSON.stringify(_digest(caverns)) == JSON.stringify(_digest(other.inferno_caverns_at(coord))),
				"%s %s: caverns differ between two generators" % [seed_text, coord])
			for cavern in caverns:
				_check_cavern(seed_text, coord, data, cavern)
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
					if not largest.has(Vector2i(cx * size + cell.x, cz * size + cell.y)):
						stray += 1
	_expect(stray == 0, "%s: %d cavern cells are cut off from the main walk" % [seed_text, stray])


func _check_cavern(seed_text: String, coord: Vector3i, data: Dictionary, cavern: Dictionary) -> void:
	var tag := "%s %s" % [seed_text, coord]
	var rect: Rect2i = cavern["rect"]
	_expect(rect.size.x >= InfernoCaverns.MIN_SPAN and rect.size.x <= InfernoCaverns.MAX_SPAN
		and rect.size.y >= InfernoCaverns.MIN_SPAN and rect.size.y <= InfernoCaverns.MAX_SPAN,
		"%s: cavern %s is outside 14-22 cells" % [tag, rect])
	var grid: Array = data["grid"]
	var open_middle := false
	for cell in cavern["cells"]:
		if InfernoCaverns.clearance(grid, cell) >= InfernoCaverns.OPEN_CLEARANCE:
			open_middle = true
			break
	_expect(open_middle, "%s: cavern %s has no clear 7x7" % [tag, rect])
	_expect(not (cavern["halls"] as Array).is_empty(), "%s: cavern %s has no hall" % [tag, rect])
	for hall in cavern["halls"]:
		var h: Rect2i = hall
		_expect(mini(h.size.x, h.size.y) >= InfernoCaverns.HALL_WIDTH, "%s: hall %s is narrower than 5" % [tag, h])
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
