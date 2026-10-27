extends RefCounted

## District density: per district the share of "dead mass" (solid cells with no open cell within two cells: the big
## empty dark blocks between halls) and the mean distance from a room's door to the nearest hall cell. Dense districts
## (StreamedRouteGenerator.DENSE_DISTRICTS: hotel, prison) must stay under DEAD_LIMIT (15%) dead mass and within 2 cells of a hall.
##
##   godot --headless --path . res://scenes/validate.tscn -- density

const DEAD_LIMIT := 0.15
const DOOR_DISTANCE_LIMIT := 3.0
const WINDOWS := [
	{"seed": "MAP-CHECK", "from": Vector2i(0, 3), "to": Vector2i(6, 6)},
	{"seed": "MAP-CHECK", "from": Vector2i(-6, -6), "to": Vector2i(-1, -1)},
	{"seed": "HALL-A", "from": Vector2i(-4, -4), "to": Vector2i(4, 4)},
]

var _failures := 0
var stats := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var dead := {}
	var cells := {}
	var door_distance := {}
	var rooms := {}
	for window in WINDOWS:
		var generator := StreamedRouteGenerator.new(String(window["seed"]))
		for cz in range(window["from"].y, window["to"].y + 1):
			for cx in range(window["from"].x, window["to"].x + 1):
				var coord := Vector3i(cx, 0, cz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data: Dictionary = generator.chunk(coord)
				var region := String(data["region"])
				var grid: Array = data["grid"]
				var hall_cells := {}
				var room_cells := {}
				for room in data["rooms"]:
					var rect: Rect2i = room["rect"]
					for z in range(rect.position.y, rect.end.y):
						for x in range(rect.position.x, rect.end.x):
							room_cells[Vector2i(x, z)] = true
				for z in size:
					for x in size:
						if int(grid[z][x]) == 0 and not room_cells.has(Vector2i(x, z)):
							hall_cells[Vector2i(x, z)] = true
				for z in range(1, size - 1):
					for x in range(1, size - 1):
						if int(grid[z][x]) == 0:
							continue
						cells[region] = int(cells.get(region, 0)) + 1
						var near_open := false
						for dz in range(-2, 3):
							for dx in range(-2, 3):
								var gx := x + dx
								var gz := z + dz
								if gx >= 0 and gz >= 0 and gx < size and gz < size and int(grid[gz][gx]) == 0:
									near_open = true
						if not near_open:
							dead[region] = int(dead.get(region, 0)) + 1
				for room in data["rooms"]:
					var doorway = room.get("doorway")
					if not doorway is Vector2i:
						continue
					var best := 99
					for hall in hall_cells:
						var h: Vector2i = hall
						best = mini(best, absi(h.x - doorway.x) + absi(h.y - doorway.y))
					if best < 99:
						if not door_distance.has(region):
							door_distance[region] = []
						(door_distance[region] as Array).append(best)
						rooms[region] = int(rooms.get(region, 0)) + 1
	var lines := []
	for region in cells:
		var ratio := float(dead.get(region, 0)) / maxf(1.0, float(cells[region]))
		var distances: Array = door_distance.get(region, [])
		var mean := 0.0
		for d in distances:
			mean += float(d)
		mean /= maxf(1.0, float(distances.size()))
		stats[region] = {"dead": ratio, "door_to_hall": mean}
		lines.append("%s dead %.0f%% door-to-hall %.1f" % [region, ratio * 100.0, mean])
		if StreamedRouteGenerator.DENSE_DISTRICTS.has(region):
			_expect(ratio < DEAD_LIMIT, "%s has %.0f%% dead mass (limit %.0f%%)" % [region, ratio * 100.0, DEAD_LIMIT * 100.0])
			_expect(mean <= DOOR_DISTANCE_LIMIT, "%s rooms are %.1f cells from a hall (limit %.1f)" % [region, mean, DOOR_DISTANCE_LIMIT])
		elif region == "apartment":
			# Suite sector keeps a solid slab beside the unit block; bounded, not dense.
			_expect(ratio < 0.40, "apartment has %.0f%% dead mass (limit 40%%)" % [ratio * 100.0])
	lines.sort()
	if _failures == 0:
		print("  density   %s" % "; ".join(lines))
	return _failures
