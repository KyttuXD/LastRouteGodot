extends RefCounted

## The Mezzanine void (VoidRegion): one huge shaft per map. Static checks over many seeds: the footprint is SIZE x SIZE
## chunks, off the spawn and inside the sealed border, and deterministic; no maze, sewer or Inferno chunk is made in it
## (only void chunks, levels -3..+1) and level +1 exists nowhere else; every level has a railed ledge ring with the
## neighbouring chunks' seam openings leading onto it, a catwalk cross, every walkable cell reachable, a rail on every
## edge that drops, the roof only on top and the pit only at the bottom; the stair tower is continuous; hunters' walk
## grid is ledges and decks only.
##
##   godot --headless --path . res://scenes/validate.tscn -- void

const SEEDS := ["VOID-A", "VOID-B", "ENDLESS-ROUTE", "SOAKTEST", "KYTTU-LAB", "PICKUPS", "BIOME-A", "REAL-B"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var chunks := 0
	var towers := 0
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		var rect := VoidRegion.footprint(seed_text)
		_expect(rect.size == Vector2i(VoidRegion.SIZE, VoidRegion.SIZE), "%s footprint is %s" % [seed_text, rect.size])
		_expect(not rect.intersects(Rect2i(-VoidRegion.SPAWN_CLEAR, -VoidRegion.SPAWN_CLEAR, 5, 5)), "%s void is on the spawn: %s" % [seed_text, rect])
		var limit: int = SealRules.BORDER_RADIUS
		_expect(rect.position.x >= -limit and rect.position.y >= -limit and rect.end.x - 1 <= limit and rect.end.y - 1 <= limit,
			"%s void %s is outside the sealed border" % [seed_text, rect])
		# inside the footprint every level is a void chunk; outside it level +1 is the ordinary deck where a patch is
		for dz in range(-10, 11):
			for dx in range(-10, 11):
				var inside := rect.has_point(Vector2i(dx, dz))
				var deck := generator.is_chunk_allowed(Vector3i(dx, 1, dz))
				_expect(deck == (inside or DeckPatches.is_deck(seed_text, dx, dz)), "%s level +1 at (%d, %d): allowed=%s, void=%s" % [
					seed_text, dx, dz, deck, inside])
				if deck and not inside:
					_expect(not (generator.chunk(Vector3i(dx, 1, dz)) as Dictionary).has("void_cap"), "%s the +1 deck at (%d, %d) is a void chunk" % [seed_text, dx, dz])
		var tower := VoidRegion.tower_chunk(seed_text)
		var last_landing := Vector2i(-1, -1)
		for level in range(VoidRegion.BOTTOM_LEVEL, VoidRegion.TOP_LEVEL + 1):
			for dz in range(rect.position.y, rect.end.y):
				for dx in range(rect.position.x, rect.end.x):
					chunks += 1
					var coord := Vector3i(dx, level, dz)
					var where := "%s %s" % [seed_text, coord]
					var data := generator.chunk(coord)
					_expect(String(data.get("region", "")) == "mezzanine" and data.has("mezzanine_grid"), "%s is not a void chunk" % where)
					var grid: Array = data["mezzanine_grid"]
					_expect(bool(data.get("void_cap", false)) == (level == VoidRegion.TOP_LEVEL), "%s roof flag wrong" % where)
					_expect(bool(data.get("void_floor", false)) == (level == VoidRegion.BOTTOM_LEVEL), "%s pit flag wrong" % where)
					# the walk grid is the walkable codes only
					var walk: Array = data["grid"]
					var size := StreamedRouteGenerator.CHUNK_SIZE
					for z in size:
						for x in size:
							var code := int(grid[z][x])
							_expect((int(walk[z][x]) == 0) == MezzanineRouteGenerator.is_walkable(code), "%s walk grid disagrees at %s" % [where, Vector2i(x, z)])
							if VoidRegion.on_ledge(seed_text, coord, x, z):
								_expect(MezzanineRouteGenerator.is_walkable(code), "%s ledge cell %s is not walkable" % [where, Vector2i(x, z)])
							if code == MezzanineRouteGenerator.PIT:
								_expect(level == VoidRegion.BOTTOM_LEVEL, "%s has pit floor above the bottom" % where)
					_expect(_all_reached(walk), "%s has walkable cells cut off from the catwalks" % where)
					# every edge that drops is railed
					var railed := {}
					for feature in data["features"]:
						if feature["type"] == "catwalkRail":
							railed["%s:%s" % [feature["cell"], feature["side"]]] = true
					for z in size:
						for x in size:
							if not MezzanineRouteGenerator.is_walkable(int(grid[z][x])):
								continue
							for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
								var n: Vector2i = Vector2i(x, z) + dir
								if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size:
									continue
								var beyond := int(grid[n.y][n.x])
								if beyond == MezzanineRouteGenerator.OPEN or beyond == MezzanineRouteGenerator.PIT:
									_expect(railed.has("%s:%s" % [Vector2i(x, z), dir]), "%s: the drop at %s has no rail" % [where, Vector2i(x, z)])
					# the neighbouring maze chunks' seam openings lead onto the ledge
					for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						var next: Vector2i = Vector2i(dx, dz) + dir
						if rect.has_point(next) or level > 0 or not generator.is_chunk_allowed(Vector3i(next.x, level, next.y)):
							continue
						var wanted := generator.edge_openings(Vector3i(next.x, level, next.y), -dir) if level == 0 else []
						for lane in wanted:
							var x: int = (0 if dir.x < 0 else size - 1) if dir.x != 0 else int(lane)
							var z: int = (0 if dir.y < 0 else size - 1) if dir.y != 0 else int(lane)
							_expect(MezzanineRouteGenerator.is_walkable(int(grid[z][x])), "%s: the seam opening %d from %s ends in air at %s" % [where, lane, next, Vector2i(x, z)])
					if dx == tower.x and dz == tower.y:
						towers += 1
						_expect(not (data["stairwells"] as Array).is_empty() or level == VoidRegion.BOTTOM_LEVEL and not VoidRegion.tower_well(seed_text, level + 1).is_empty(),
							"%s tower chunk has no stairwell" % where)
					else:
						_expect((data["stairwells"] as Array).is_empty(), "%s has stairs outside the tower chunk" % where)
				# normal chunks next to the void are untouched maze/sewer/Inferno chunks
		# the tower is one continuous spiral
		for upper in range(VoidRegion.BOTTOM_LEVEL + 1, VoidRegion.TOP_LEVEL + 1):
			var well := VoidRegion.tower_well(seed_text, upper)
			_expect(not well.is_empty() and String(well["kind"]) == "spiral", "%s tower missing at %d" % [seed_text, upper])
			if well.is_empty():
				continue
			if last_landing != Vector2i(-1, -1):
				_expect(well["landing"] == last_landing, "%s tower landing moves between levels" % seed_text)
			last_landing = well["landing"]
		_expect(VoidRegion.tower_well(seed_text, VoidRegion.BOTTOM_LEVEL).is_empty() and VoidRegion.tower_well(seed_text, VoidRegion.TOP_LEVEL + 1).is_empty(),
			"%s tower extends past the void's ends" % seed_text)
		# outside the footprint nothing changed: a maze chunk at level 0 next to the void is a normal maze chunk
		var outside := Vector3i(rect.position.x - 1, 0, rect.position.y)
		if generator.is_chunk_allowed(outside):
			_expect(not (generator.chunk(outside) as Dictionary).has("mezzanine_grid"), "%s the chunk beside the void is a void chunk" % seed_text)
	if _failures == 0:
		print("  void  %d void chunks over %d seeds, levels -3..+1: railed ledge rings, catwalks, one stair tower each, +1 only inside" % [chunks, SEEDS.size()])
	return _failures


## Every walkable cell is reachable from the chunk's catwalk cross through walkable cells.
func _all_reached(walk: Array) -> bool:
	var size := walk.size()
	var seen := {}
	var queue: Array[Vector2i] = [Vector2i(size / 2, size / 2)]
	seen[queue[0]] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + dir
			if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size or seen.has(n) or int(walk[n.y][n.x]) != 0:
				continue
			seen[n] = true
			queue.append(n)
	for z in size:
		for x in size:
			if int(walk[z][x]) == 0 and not seen.has(Vector2i(x, z)):
				return false
	return true
