extends RefCounted

## Hallways never pinch: across several seeds and every district, no open hallway cell (open, outside every room, not a
## doorway) has fewer than three cells of open width across it in either direction (a one- or two-wide sliver or squeezed
## connector), and every main hall keeps its full three-wide footprint end to end. Wider blobs at junctions and corners are
## allowed (they are not hallways), as are the one-cell room doors.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hallways

## seed, first chunk, last chunk. the windows together hold a hotel and a prison and cover the mixed districts.
const WINDOWS := [
	{"seed": "MAP-CHECK", "from": Vector2i(0, 3), "to": Vector2i(6, 6)},
	{"seed": "MAP-CHECK", "from": Vector2i(-6, -6), "to": Vector2i(-1, -1)},
	{"seed": "HALL-A", "from": Vector2i(-4, -4), "to": Vector2i(4, 4)},
	{"seed": "MAP-CHECK", "from": Vector2i(2, -6), "to": Vector2i(6, -1)},
]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var districts := {}
	var narrow_total := 0
	var narrow_samples := []
	var doubled_total := 0
	var doubled_samples := []
	var doubled_districts := {}
	var chunks_checked := 0
	var covered := {}
	var maze_halls := 0
	for window in WINDOWS:
		var seed_text: String = window["seed"]
		var generator := StreamedRouteGenerator.new(seed_text)
		var size := StreamedRouteGenerator.CHUNK_SIZE
		var open := {}
		var rooms := {}
		var doors := {}
		var region_at := {}
		var warren_cells := {}   # a warren's corridors wind side by side on purpose (twists and turns)
		for cz in range(window["from"].y, window["to"].y + 1):
			for cx in range(window["from"].x, window["to"].x + 1):
				var coord := Vector3i(cx, 0, cz)
				if not generator.is_chunk_allowed(coord) or generator.is_void_column(coord):
					continue
				chunks_checked += 1
				var data: Dictionary = generator.chunk(coord)
				covered[String(data["region"])] = true
				var grid: Array = data["grid"]
				var origin := Vector2i(cx * size, cz * size)
				for room in data["rooms"]:
					var rect: Rect2i = room["rect"]
					for z in range(rect.position.y, rect.end.y):
						for x in range(rect.position.x, rect.end.x):
							rooms[origin + Vector2i(x, z)] = true
				# a stairwell is an enclosed well, not a hallway: its landing is not a second hall beside the centre one
				for well in data.get("stairwells", []):
					var box: Rect2i = well["box"]
					for z in range(box.position.y, box.end.y):
						for x in range(box.position.x, box.end.x):
							rooms[origin + Vector2i(x, z)] = true
				for prop in data["region_props"]:
					if prop.get("room_door", false):
						for cell in prop.get("doorway_cells", []):
							doors[origin + (cell as Vector2i)] = true
				var warren := not (data.get("warren", {}) as Dictionary).is_empty()
				for z in size:
					for x in size:
						if warren:
							warren_cells[origin + Vector2i(x, z)] = true
						if int(grid[z][x]) == 0:
							open[origin + Vector2i(x, z)] = true
							region_at[origin + Vector2i(x, z)] = String(data["region"])
				# a main hall keeps all three rows/columns open from end to end
				for corridor in data["corridors"]:
					if corridor.has("rect") and String(corridor.get("id", "")).contains(":HALL:"):
						var rect: Rect2i = corridor["rect"]
						# "5 wide maze region hallways": the maze's centre cross (halls 1 and 3) is five wide
						var hall_id := String(corridor["id"])
						if String(data["region"]) == "maze" and (hall_id.ends_with(":HALL:1") or hall_id.ends_with(":HALL:3")):
							maze_halls += 1
							_expect(mini(rect.size.x, rect.size.y) == 5, "%s maze main hall %s is %d wide" % [seed_text,
								hall_id, mini(rect.size.x, rect.size.y)])
						for z in range(rect.position.y, rect.end.y):
							for x in range(rect.position.x, rect.end.x):
								if int(grid[z][x]) != 0:
									_expect(false, "%s hall cell %s is blocked in %s" % [seed_text, Vector2i(x, z), data["chunk_id"]])
		var hall := {}
		for cell in open:
			if not rooms.has(cell) and not doors.has(cell):
				hall[cell] = true
		for cell_value in hall:
			var cell: Vector2i = cell_value
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var gap := 0
				var cursor: Vector2i = cell + step
				while gap < 5 and not hall.has(cursor):
					gap += 1
					cursor += step
				# gap cells 1..5 then a hall cell; the cell right beside it (gap 0) is the same hall
				if gap >= 1 and gap <= 3 and hall.has(cursor) and not warren_cells.has(cell) and _hall_pair_is_parallel(hall, cell, cursor, step):
					doubled_total += 1
					var region_d := String(region_at.get(cell, "?"))
					doubled_districts[region_d] = int(doubled_districts.get(region_d, 0)) + 1
					if doubled_samples.size() < 6:
						doubled_samples.append("%s %s->%s" % [seed_text, cell, cursor])
			if minf(_run(hall, cell, Vector2i(1, 0)), _run(hall, cell, Vector2i(0, 1))) < 3:
				narrow_total += 1
				var region := String(region_at.get(cell, "?"))
				districts[region] = int(districts.get(region, 0)) + 1
				if narrow_samples.size() < 6:
					narrow_samples.append("%s %s %s" % [seed_text, cell, region])
	# no two hallways within a few cells of each other (a double line with a sliver between): from a hall cell, scanning
	# straight along either axis, 1-3 non-hall cells and then another hall cell (both strips 6+ long) is a violation: a double line with a sliver between.
	_expect(doubled_total == 0, "%d hall cells have another hallway within 3 cells across a thin wall (e.g. %s; by district %s)" % [
		doubled_total, doubled_samples, doubled_districts])
	_expect(covered.has("hotel") and covered.has("prison"), "the scanned windows must include a hotel and a prison (got %s)" % [covered.keys()])
	_expect(narrow_total == 0, "%d hallway cells are narrower than three wide (e.g. %s; by district %s)" % [
		narrow_total, narrow_samples, districts])
	_expect(maze_halls > 0, "the scanned windows must include a maze chunk")
	# "make the maze the most common spawn point": the spawn region is the maze about 60% of the time, else another
	var spawn_regions := {}
	for i in 400:
		var region := StreamedRouteGenerator.new("SPAWN-%d" % i).biome_for(Vector3i.ZERO)
		spawn_regions[region] = int(spawn_regions.get(region, 0)) + 1
	var maze_share := float(spawn_regions.get("maze", 0)) / 400.0
	_expect(maze_share > .5 and maze_share < .7 and spawn_regions.size() >= 6,
		"spawn regions over 400 seeds should be ~60%% maze and still varied: %s" % [spawn_regions])
	if _failures == 0:
		print("  hallways  %d chunks (%s): no hallway cell narrower than three wide, main halls whole, maze centre cross 5 wide (%d halls), spawn %d%% maze" % [chunks_checked, ", ".join(covered.keys()), maze_halls, roundi(maze_share * 100.0)])
	return _failures


## Length of the open hall run through `cell` along `step`.
static func _run(hall: Dictionary, cell: Vector2i, step: Vector2i) -> int:
	var length := 1
	var cursor := cell + step
	while hall.has(cursor):
		length += 1
		cursor += step
	cursor = cell - step
	while hall.has(cursor):
		length += 1
		cursor -= step
	return length


## The two hall cells face each other across a gap along `step`: both sit in a strip at least 6 long perpendicular to the
## scan (two hallways running side by side), not a short stub, a corner or a doorway.
static func _hall_pair_is_parallel(hall: Dictionary, a: Vector2i, b: Vector2i, step: Vector2i) -> bool:
	var side := Vector2i(step.y, step.x)
	# both strips run on for at least 6 cells along the scan's perpendicular: two real corridors, not a stub or a corner
	return _run(hall, a, side) >= 6 and _run(hall, b, side) >= 6
