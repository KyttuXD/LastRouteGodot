extends RefCounted

## Crawl-under pipes in the sewers (SewerRouteGenerator._crawl_features): a low pipe across a utility room's branch leaves
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
	_expect(SewerRouteGenerator.CRAWL_CLEARANCE > PlayerController3D.CROUCH_COLLISION_HEIGHT, "crawl clearance does not clear the crouched capsule")
	_expect(SewerRouteGenerator.CRAWL_CLEARANCE < PlayerController3D.STANDING_COLLISION_HEIGHT, "a standing player would walk under the pipe")
	if _failures == 0:
		print("  sewer_crawl  %d crawl pipes: clearance %.3f m (crouched capsule %.3f m), room reachable crouched only, nothing needed is behind one" % [
			pipes, SewerRouteGenerator.CRAWL_CLEARANCE, PlayerController3D.CROUCH_COLLISION_HEIGHT])
	return _failures


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
