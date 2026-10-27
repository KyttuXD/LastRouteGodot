extends RefCounted

## Floor connectivity over chunk seams: from a hall cell of each sampled chunk, a flood over the 3x3 chunk window must reach
## every open cell of that chunk. Catches halls cut short, closed seams, great halls and trimmed halls that strand rooms
## (the maze's lower hall once ended before the vertical hall and cut off a wing of rooms), and anything else that walls a
## room or suite off from the route. The long version is tools/look/connectivity_audit.gd.

const SEEDS := ["CONN-A", "CONN-B"]
const RADIUS := 5

var _failures := 0


func run(_host: Node) -> int:
	var checked := 0
	var bad := []
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord) or generator.is_safe_room(coord):
					continue
				var missing := _cut_off(generator, coord)
				checked += 1
				if missing > 0:
					bad.append("%s %s %s: %d cells" % [seed_text, coord, generator.biome_for(coord), missing])
	if not bad.is_empty():
		print("  FAIL  %d of %d chunks have floor cut off from their halls (e.g. %s)" % [bad.size(), checked, bad.slice(0, 4)])
		_failures += 1
	if _failures == 0:
		print("  connectivity  %d chunks: every open cell reachable from the halls across seams" % checked)
	return _failures


static func _cut_off(generator: StreamedRouteGenerator, coord: Vector3i) -> int:
	var cells := {}
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var c := Vector3i(coord.x + ox, 0, coord.z + oz)
			if not generator.is_chunk_allowed(c):
				continue
			var grid: Array = generator.chunk(c)["grid"]
			for z in grid.size():
				for x in (grid[z] as Array).size():
					if int(grid[z][x]) == 0:
						cells[Vector2i(c.x * 45 + x, c.z * 45 + z)] = true
	var start := Vector2i(coord.x * 45 + 22, coord.z * 45 + 10)
	if not cells.has(start):
		return 0
	var seen := {start: true}
	var frontier := [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + d
			if cells.has(next) and not seen.has(next):
				seen[next] = true
				frontier.append(next)
	var own: Array = generator.chunk(coord)["grid"]
	var missing := 0
	for z in own.size():
		for x in (own[z] as Array).size():
			if int(own[z][x]) == 0 and not seen.has(Vector2i(coord.x * 45 + x, coord.z * 45 + z)):
				missing += 1
	return missing
