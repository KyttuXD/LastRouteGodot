extends RefCounted

## The upper levels and vents over many seeds: the mezzanine (+1), the attic (+2) and the vent ducts generate
## deterministically, every walkable cell of a level is reachable from its seam cross, seams meet, both ends of every
## ladder agree, every attic hatch is reachable standing, the eaves' hide spots are crawl-only (a standing hunter cannot
## reach them, a crouching runner can), and every vent grate opens onto a walkable cell and a duct.

const SEEDS := ["UPPER-A", "UPPER-B", "KYTTU-LAB", "ENDLESS-ROUTE", "PICKUPS"]
const RADIUS := 4
## A full-size humanoid hunter: the rig is about 1.8 m tall before HunterRoster.MODEL_SCALE.
const HUNTER_HEIGHT := 1.8 * HunterRoster.MODEL_SCALE

var _failures := 0


func run(_host: Node) -> int:
	var counts := {"mezz": 0, "attic": 0, "ladders": 0, "stairs": 0, "grates": 0, "hides": 0}
	_expect(AtticRouteGenerator.passable(AtticRouteGenerator.CRAWL, PlayerController3D.CROUCH_COLLISION_HEIGHT),
		"a crouching runner does not fit the attic crawlspace")
	_expect(not AtticRouteGenerator.passable(AtticRouteGenerator.CRAWL, HUNTER_HEIGHT),
		"a full-size hunter fits the attic crawlspace")
	_expect(VentNetwork.DUCT_HEIGHT < HUNTER_HEIGHT, "a hunter fits the vents")
	for seed_text in SEEDS:
		var surface := StreamedRouteGenerator.new(seed_text)
		var mezz := MezzanineRouteGenerator.new(surface)
		var attic := AtticRouteGenerator.new(mezz)
		var vents := VentNetwork.new(surface, mezz, attic)
		var mezz2 := MezzanineRouteGenerator.new(StreamedRouteGenerator.new(seed_text))
		var attic2 := AtticRouteGenerator.new(mezz2)
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				var where := "%s (%d,%d)" % [seed_text, dx, dz]
				var m: Dictionary = mezz.chunk(Vector3i(dx, 1, dz))
				var a: Dictionary = attic.chunk(Vector3i(dx, 2, dz))
				counts["mezz"] += 1
				counts["attic"] += 1
				_expect(m["mezzanine_grid"] == mezz2.chunk(Vector3i(dx, 1, dz))["mezzanine_grid"]
					and a["attic_grid"] == attic2.chunk(Vector3i(dx, 2, dz))["attic_grid"], "%s not deterministic" % where)
				_expect(_all_reached(m["grid"]), "%s mezzanine has unreachable walkway" % where)
				_expect(_all_reached(a["grid"]), "%s attic has unreachable floor" % where)
				_expect(_seams_open(m["grid"], m["edges"]) and _seams_open(a["grid"], a["edges"]),
					"%s seam cross is not walkable" % where)
				var standing := _flood(a["attic_grid"], [AtticRouteGenerator.STAND])
				for feature in a["features"]:
					var cell: Vector2i = feature["cell"]
					if feature["type"] == "atticHatch":
						_expect(standing.has(cell), "%s attic hatch %s not reachable standing" % [where, cell])
					elif feature.get("hide", false):
						counts["hides"] += 1
						_expect(int(a["attic_grid"][cell.y][cell.x]) == AtticRouteGenerator.CRAWL and not standing.has(cell),
							"%s attic hide %s is reachable by a standing hunter" % [where, cell])
				var below: Array = surface.chunk(Vector3i(dx, 0, dz))["grid"]
				var hatches := 0
				var chunk_ladders := 0
				for link in m["links"]:
					var top: Vector2i = link["from_cell"]
					var foot: Vector2i = link["to_cell"]
					if link["kind"] == "ladder":
						counts["ladders"] += 1
						chunk_ladders += 1
						_expect(int(m["grid"][foot.y][foot.x]) == 0 and int(a["grid"][top.y][top.x]) == 0,
							"%s ladder ends not walkable" % where)
					elif link["kind"] == "stairs":
						counts["stairs"] += 1
						_expect(int(m["grid"][top.y][top.x]) == 0 and int(below[foot.y][foot.x]) == 0,
							"%s stair landing not walkable on both levels" % where)
				for feature in a["features"]:
					if feature["type"] == "atticHatch":
						hatches += 1
				_expect(hatches == chunk_ladders,
					"%s attic hatches do not match mezzanine ladders" % where)
				var v: Dictionary = vents.chunk(Vector3i(dx, 0, dz))
				for link in v["links"]:
					counts["grates"] += 1
					var cell: Vector2i = link["from_cell"]
					var level_grid: Array = [below, m["grid"], a["grid"]][int(link["from_level"])]
					_expect(int(level_grid[cell.y][cell.x]) == 0 and int(v["grid"][cell.y][cell.x]) == VentNetwork.DUCT,
						"%s vent grate %s does not join a duct to a walkable cell" % [where, cell])
	_expect(counts["ladders"] > 0 and counts["stairs"] > 0 and counts["grates"] > 0 and counts["hides"] > 0,
		"missing link kinds: %s" % [counts])
	if _failures == 0:
		print("  upper_levels  %s: deterministic, connected, seams meet, ladders agree, crawl hides out of hunter reach"
			% [counts])
	return _failures


static func _flood(grid: Array, codes: Array) -> Dictionary:
	var size := grid.size()
	var center := Vector2i(size / 2, size / 2)
	var seen := {}
	if not codes.has(int(grid[center.y][center.x])):
		return seen
	var queue := [center]
	seen[center] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + dir
			if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size or seen.has(n):
				continue
			if codes.has(int(grid[n.y][n.x])):
				seen[n] = true
				queue.append(n)
	return seen


static func _all_reached(grid: Array) -> bool:
	var seen := _flood(grid, [0])
	for z in grid.size():
		for x in grid.size():
			if int(grid[z][x]) == 0 and not seen.has(Vector2i(x, z)):
				return false
	return true


static func _seams_open(grid: Array, edges: Dictionary) -> bool:
	var last := grid.size() - 1
	for i in edges["west"]:
		if int(grid[i][0]) != 0 or int(grid[i][last]) != 0 or int(grid[0][i]) != 0 or int(grid[last][i]) != 0:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1
