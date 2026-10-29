extends RefCounted

## Crawl-under pipes in the sewers (SewerRouteGenerator._crawl_features and the outflow mains, _outflow_features): a low pipe across a utility room's branch leaves
## exactly the crouched capsule + 5 cm underneath, so a crouched player passes and a standing player or normal hunter does not.
## Checked per chunk over many seeds: clearance, at most one pipe per chunk, never in an overflow chamber, the room behind it
## reachable by a crouched player but not by a hunter, every pickup, ladder and hiding spot reachable by a hunter WITHOUT
## crossing a pipe (a relay is never behind a crawl), and no crawl cell outside a three-wide branch.
##
##   godot --headless --path . res://scenes/validate.tscn -- sewer_crawl

const SEEDS := ["CRAWL-A", "CRAWL-B", "CRAWL-C", "CRAWL-D", "ENDLESS-ROUTE"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var pipes := 0
	for seed_text in SEEDS:
		var generator := SewerRouteGenerator.new(StreamedRouteGenerator.new(seed_text))
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				pipes += _check_chunk(generator.chunk(Vector3i(dx, SewerRouteGenerator.LEVEL, dz)), seed_text)
	_expect(pipes >= 8, "only %d crawl pipes in the sampled chunks" % pipes)
	var mains := 0
	for seed_text in SEEDS:
		var generator := SewerRouteGenerator.new(StreamedRouteGenerator.new(seed_text))
		for level in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
			for dz in range(-4, 5):
				for dx in range(-4, 5):
					mains += _check_outflow(generator.chunk(Vector3i(dx, level, dz)), seed_text)
	_expect(mains >= 20, "only %d outflow mains in the sampled chunks (want a few per window)" % mains)
	_expect(SewerRouteGenerator.CRAWL_CLEARANCE < HUNTER_HEIGHT, "a hunter fits under an outflow main")
	# the authored mains follow the crawl clearance (rebuild them when PlayerModels.SCALE changes): over the walkway the whole
	# main's flanges are its underside, the torn stump's stub is nowhere below it (the drop into the channel goes lower)
	for model in [["res://art/props-3d/props/sewer/sewer_outflow_pipe.glb", true, "FlangeA"], [StreamedFacilityView3D.OUTFLOW_STUMP, false, "Stub"]]:
		var visual := ModelSlot.instantiate(String(model[0]))
		_expect(visual != null, "%s does not load" % model[0])
		if visual == null:
			continue
		var part := visual.find_child(String(model[2]), true, false) as MeshInstance3D
		_expect(part != null, "%s has no %s" % [model[0], model[2]])
		if part == null:
			visual.free()
			continue
		var low := (part.transform * part.get_aabb()).position.y
		_expect(low >= SewerRouteGenerator.CRAWL_CLEARANCE - .02 and (not bool(model[1]) or low <= SewerRouteGenerator.CRAWL_CLEARANCE + .02),
			"%s: underside %.3f m, crawl clearance %.3f m (rebuild it with the current PlayerModels.SCALE)" % [
				String(model[0]).get_file(), low, SewerRouteGenerator.CRAWL_CLEARANCE])
		visual.free()
	_expect(SewerRouteGenerator.CRAWL_CLEARANCE + SewerRouteGenerator.OUTFLOW_SIZE.y < SewerRouteGenerator.CEILING_HEIGHT,
		"an outflow main does not fit under the sewer vault")
	_expect(SewerRouteGenerator.CRAWL_CLEARANCE > PlayerController3D.CROUCH_COLLISION_HEIGHT, "crawl clearance does not clear the crouched capsule")
	_expect(SewerRouteGenerator.CRAWL_CLEARANCE < PlayerController3D.STANDING_COLLISION_HEIGHT, "a standing player would walk under the pipe")
	if _failures == 0:
		print("  sewer_crawl  %d crawl pipes: clearance %.3f m (crouched capsule %.3f m), room reachable crouched only, nothing needed is behind one" % [
			pipes, SewerRouteGenerator.CRAWL_CLEARANCE, PlayerController3D.CROUCH_COLLISION_HEIGHT])
	return _failures


## A full-size humanoid hunter (the rig is about 1.8 m before HunterRoster.MODEL_SCALE).
const HUNTER_HEIGHT := 1.8 * HunterRoster.MODEL_SCALE


## Outflow mains (SewerRouteGenerator._outflow_features): at most one per chunk, across a walkway row of dry cells with
## brick behind and the channel in front, clear of links and bridges, crawled under at the crawl clearance; a hunter
## (who cannot pass it) still reaches every cell a crouched runner reaches, except the main's own three.
func _check_outflow(data: Dictionary, seed_text: String) -> int:
	var where := "%s %s" % [seed_text, data["coord"]]
	var mains := (data["region_props"] as Array).filter(func(prop: Dictionary) -> bool: return bool(prop.get("outflow", false)))
	if mains.is_empty():
		return 0
	_expect(mains.size() == 1, "%s: %d outflow mains in one chunk" % [where, mains.size()])
	var main: Dictionary = mains[0]
	var grid: Array = data["sewer_grid"]
	var cells: Array = main["occupied_cells"]
	var wall: Vector2i = main["outflow_wall"]
	var middle: Vector2i = main["cell"]
	_expect(cells.size() == 3 and bool(main["solid"]), "%s: the outflow main is not a solid three-cell piece" % where)
	_expect(is_equal_approx(float(main["collider_y0"]), SewerRouteGenerator.CRAWL_CLEARANCE),
		"%s: outflow collider underside %.3f, not the crawl clearance" % [where, main["collider_y0"]])
	for cell_value in cells:
		var cell: Vector2i = cell_value
		_expect(int(grid[cell.y][cell.x]) == SewerRouteGenerator.DRY, "%s: outflow cell %s is not dry walkway" % [where, cell])
	_expect(int(grid[(middle + wall * 2).y][(middle + wall * 2).x]) == SewerRouteGenerator.SOLID,
		"%s: no brick behind the outflow main at %s" % [where, middle])
	_expect(int(grid[(middle - wall * 2).y][(middle - wall * 2).x]) == SewerRouteGenerator.WATER,
		"%s: the outflow main at %s does not pour into the channel" % [where, middle])
	for link in data["links"]:
		for cell in cells:
			_expect(((link["to_cell"] as Vector2i) - (cell as Vector2i)).length() > 2.5,
				"%s: the outflow main at %s crowds the ladder at %s" % [where, middle, link["to_cell"]])
	for cell_value in cells:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = (cell_value as Vector2i) + Vector2i(dx, dz)
				_expect(int(grid[n.y][n.x]) != SewerRouteGenerator.BRIDGE, "%s: the outflow main at %s is on a bridge" % [where, middle])
	for prop in data["region_props"]:
		if prop == main or String(prop["type"]) == "sewerBridge":
			continue
		for cell in cells:
			var gap: Vector2i = (prop["cell"] as Vector2i) - (cell as Vector2i)
			_expect(maxi(absi(gap.x), absi(gap.y)) > 1, "%s: %s at %s crowds the outflow main at %s" % [
				where, prop["type"], prop["cell"], middle])
	var blocked := {}
	for cell in cells:
		blocked[cell] = true
	var start := Vector2i(SewerRouteGenerator.BRIDGE_OFFSETS[0], SewerRouteGenerator.CENTER)
	var hunter := _flood(grid, start, blocked)
	var crouched := _flood(grid, start, {})
	var cut := crouched.keys().filter(func(cell: Vector2i) -> bool: return not blocked.has(cell) and not hunter.has(cell))
	_expect(cut.is_empty(), "%s: the outflow main at %s cuts %d cells off from hunters (e.g. %s)" % [where, middle, cut.size(), cut.slice(0, 4)])
	return 1


func _check_chunk(data: Dictionary, seed_text: String) -> int:
	var where := "%s %s" % [seed_text, data["coord"]]
	var props: Array = []
	for prop_value in data["region_props"]:
		if bool((prop_value as Dictionary).get("crawl_under", false)):
			props.append(prop_value)
	if props.is_empty():
		return 0
	_expect(props.size() == 2, "%s: %d crawl props (a pipe is two mains)" % [where, props.size()])
	var blocked := {}
	for prop in props:
		_expect(is_equal_approx(float(prop["collider_y0"]), SewerRouteGenerator.CRAWL_CLEARANCE), "%s: crawl collider underside %.3f" % [where, prop["collider_y0"]])
		for cell in prop["occupied_cells"]:
			blocked[cell] = true
	var grid: Array = data["sewer_grid"]
	var size := grid.size()
	for cell in blocked:
		var c: Vector2i = cell
		_expect(int(grid[c.y][c.x]) == SewerRouteGenerator.DRY, "%s: crawl cell %s is not dry floor" % [where, c])
	# the room the pipe leads to
	var room_rect := Rect2i()
	for feature in data["features"]:
		if (feature as Dictionary).has("behind"):
			for room in data["rooms"]:
				if ((feature["behind"] as Array).has((room["rect"] as Rect2i).position + Vector2i(1, 1))):
					room_rect = room["rect"]
			break
	_expect(room_rect.size != Vector2i.ZERO, "%s: no room behind the pipe" % where)
	for room in data["rooms"]:
		if room["room_type"] == "overflow_chamber":
			_expect(not (room["rect"] as Rect2i).has_point(room_rect.position + Vector2i(1, 1)) or room_rect != room["rect"], "%s: crawl pipe leads into an overflow chamber" % where)
	# a bridge deck on the first tunnel arm: the bridges join every walkway quadrant (the confluence is open water)
	var start := Vector2i(SewerRouteGenerator.BRIDGE_OFFSETS[0], SewerRouteGenerator.CENTER)
	_expect(SewerRouteGenerator.is_walkable(int(grid[start.y][start.x])), "%s: flood start %s is not walkable" % [where, start])
	var hunter := _flood(grid, start, blocked)
	var crouched := _flood(grid, start, {})
	var probe := room_rect.position + room_rect.size / 2
	_expect(crouched.has(probe), "%s: a crouched player cannot reach the room behind the pipe" % where)
	_expect(not hunter.has(probe), "%s: a normal hunter can walk past the pipe" % where)
	for pickup in data["pickups"]:
		_expect(hunter.has(pickup["cell"]), "%s: pickup %s at %s is only reachable by crawling" % [where, pickup["kind"], pickup["cell"]])
	for link in data["links"]:
		_expect(hunter.has(link["to_cell"]), "%s: the ladder at %s is only reachable by crawling" % [where, link["to_cell"]])
	return 1


func _flood(grid: Array, start: Vector2i, blocked: Dictionary) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + (step as Vector2i)
			if next.x < 0 or next.y < 0 or next.x >= grid.size() or next.y >= grid.size() or seen.has(next) or blocked.has(next):
				continue
			if not SewerRouteGenerator.is_walkable(int(grid[next.y][next.x])):
				continue
			seen[next] = true
			queue.append(next)
	return seen
