extends RefCounted

## "re-do the maze hallway styles, with twists and turns, scattered rooms" and "make the 5x5 hallways longer, less
## twisty". Over 8 seeds: about half the maze chunks are warrens; their narrow corridors turn often (turns per 100 m of
## corridor) and have some dead ends, while the five-wide spine cross runs straight and unbroken across every maze
## chunk; every room door, every seam opening and the whole walk grid of a warren chunk is reachable from the spine.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- maze_winding

const SEEDS := ["MAZE-LOOK", "ENDLESS-ROUTE", "SOAKTEST", "KYTTU-LAB", "REAL-B", "BIOME-A", "PICKUPS", "WARREN-A"]
const RADIUS := 8
const MIN_TURNS_PER_100M := 3.5
const DEAD_ENDS := Vector2(.05, .6)

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var maze := 0
	var warrens := 0
	var length := 0.0
	var turns := 0
	var dead_ends := 0
	var nodes := 0
	var per_region := {}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				var coord := Vector3i(dx, 0, dz)
				var region := generator.region_for(coord)
				if not generator.is_chunk_allowed(coord) or not StreamedRouteGenerator.WARREN_REGIONS.has(region) or generator.is_safe_room(coord):
					continue
				# Warren layout runs only for is_warren_chunk, and the spine check outside the maze applies only to
				# those chunks. A bank chunk of another region still counts in the warren share, without a build.
				if region != "maze" and not generator.is_warren_chunk(coord):
					per_region[region] = (per_region.get(region, Vector2i.ZERO) as Vector2i) + Vector2i(1, 0)
					continue
				var data := generator.chunk(coord)
				if data.has("mezzanine_grid"):
					continue
				var is_warren := not (data.get("warren", {}) as Dictionary).is_empty()
				per_region[region] = (per_region.get(region, Vector2i.ZERO) as Vector2i) + Vector2i(1, 1 if is_warren else 0)
				if region != "maze" and not is_warren:
					continue   # stairs (or a pod room) kept the bank layout; no five-wide spine to check
				maze += 1
				var where := "%s %s" % [seed_text, coord]
				# the spine: five wide, straight, the whole chunk
				var spine := 0
				for corridor in data["corridors"]:
					var id := String(corridor.get("id", ""))
					if id.ends_with(":HALL:1") or id.ends_with(":HALL:3"):
						var rect: Rect2i = corridor["rect"]
						spine += 1
						_expect(mini(rect.size.x, rect.size.y) == 5 and maxi(rect.size.x, rect.size.y) >= 22,
							"%s spine hall %s is %s, not five wide and long" % [where, id, rect.size])
				_expect(spine == 2, "%s has %d spine halls" % [where, spine])
				var metrics: Dictionary = data.get("warren", {})
				if metrics.is_empty():
					continue
				warrens += 1
				length += float(metrics["corridor_cells"]) / 3.0
				turns += int(metrics["turns"])
				dead_ends += int(metrics["dead_ends"])
				nodes += int(metrics["nodes"])
				var grid: Array = data["grid"]
				var reached := _flood(grid, Vector2i(22, 22))
				for room in data["rooms"]:
					var door = room.get("doorway")
					if door is Vector2i:
						_expect(reached.has(door), "%s room %s door %s is cut off" % [where, room.get("room_type", ""), door])
				var size := grid.size()
				var open := 0
				for z in size:
					for x in size:
						if int(grid[z][x]) == 0:
							open += 1
							if x == 0 or z == 0 or x == size - 1 or z == size - 1:
								_expect(reached.has(Vector2i(x, z)), "%s seam opening %s is cut off" % [where, Vector2i(x, z)])
				_expect(reached.size() >= open * 0.97, "%s only %d of %d open cells reachable" % [where, reached.size(), open])
	for region in per_region:
		var counts: Vector2i = per_region[region]
		_expect(counts.x < 8 or (counts.y >= counts.x * .3 and counts.y <= counts.x * .8),
			"%s: %d warrens among %d chunks" % [region, counts.y, counts.x])
	# level 0 only: a TOP_LEVEL_ONLY_REGIONS region (greenhouse) never stands here; it is on +1
	var expected := StreamedRouteGenerator.WARREN_REGIONS.filter(func(r) -> bool: return not StreamedRouteGenerator.TOP_LEVEL_ONLY_REGIONS.has(r))
	_expect(per_region.size() == expected.size(), "regions sampled %s, warren regions %s" % [per_region.keys(), StreamedRouteGenerator.WARREN_REGIONS])
	var rate := float(turns) / maxf(length / 100.0, .01)
	var dead_share := float(dead_ends) / maxf(nodes, 1)
	_expect(rate >= MIN_TURNS_PER_100M, "warren corridors turn only %.1f times per 100 m" % rate)
	_expect(dead_share >= DEAD_ENDS.x and dead_share <= DEAD_ENDS.y, "warren dead-end share %.2f outside %s" % [dead_share, DEAD_ENDS])
	if _failures == 0:
		print("  maze_winding  %s (chunks, warrens); %d spine chunks, %d warrens: %.1f turns per 100 m of corridor (spine: 0), %.0f%% dead ends, every door and seam reachable" % [
			per_region, maze, warrens, rate, dead_share * 100.0])
	return _failures


static func _flood(grid: Array, from: Vector2i) -> Dictionary:
	var size := grid.size()
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + step
			if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size or seen.has(n) or int(grid[n.y][n.x]) != 0:
				continue
			seen[n] = true
			queue.append(n)
	return seen
