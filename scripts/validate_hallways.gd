extends RefCounted

## Hallways never pinch: across several seeds and every district, no open hallway cell (open, outside every room, not a
## doorway) has fewer than three cells of open width across it in either direction (a one- or two-wide sliver or squeezed
## connector), and every main hall keeps its full three-wide footprint end to end. Wider blobs at junctions and corners are
## allowed (they are not hallways), as are the one-cell room doors.
##
##   godot --headless --path . res://scenes/validate.tscn -- hallways

## seed, first chunk, last chunk. MAP-CHECK's south-east window holds a hotel and a prison; the others cover the mixed districts.
const WINDOWS := [
	{"seed": "MAP-CHECK", "from": Vector2i(0, 3), "to": Vector2i(6, 6)},
	{"seed": "MAP-CHECK", "from": Vector2i(-6, -6), "to": Vector2i(-1, -1)},
	{"seed": "HALL-A", "from": Vector2i(-4, -4), "to": Vector2i(4, 4)},
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
	var chunks_checked := 0
	var covered := {}
	for window in WINDOWS:
		var seed_text: String = window["seed"]
		var generator := StreamedRouteGenerator.new(seed_text)
		var size := StreamedRouteGenerator.CHUNK_SIZE
		var open := {}
		var rooms := {}
		var doors := {}
		var region_at := {}
		for cz in range(window["from"].y, window["to"].y + 1):
			for cx in range(window["from"].x, window["to"].x + 1):
				var coord := Vector3i(cx, 0, cz)
				if not generator.is_chunk_allowed(coord):
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
				for prop in data["region_props"]:
					if prop.get("room_door", false):
						for cell in prop.get("doorway_cells", []):
							doors[origin + (cell as Vector2i)] = true
				for z in size:
					for x in size:
						if int(grid[z][x]) == 0:
							open[origin + Vector2i(x, z)] = true
							region_at[origin + Vector2i(x, z)] = String(data["region"])
				# a main hall keeps all three rows/columns open from end to end
				for corridor in data["corridors"]:
					if corridor.has("rect") and String(corridor.get("id", "")).contains(":HALL:"):
						var rect: Rect2i = corridor["rect"]
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
			if minf(_run(hall, cell, Vector2i(1, 0)), _run(hall, cell, Vector2i(0, 1))) < 3:
				narrow_total += 1
				var region := String(region_at.get(cell, "?"))
				districts[region] = int(districts.get(region, 0)) + 1
				if narrow_samples.size() < 6:
					narrow_samples.append("%s %s %s" % [seed_text, cell, region])
	_expect(covered.has("hotel") and covered.has("prison"), "the scanned windows must include a hotel and a prison (got %s)" % [covered.keys()])
	_expect(narrow_total == 0, "%d hallway cells are narrower than three wide (e.g. %s; by district %s)" % [
		narrow_total, narrow_samples, districts])
	if _failures == 0:
		print("  hallways  %d chunks (%s): no hallway cell narrower than three wide, main halls whole" % [chunks_checked, ", ".join(covered.keys())])
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
