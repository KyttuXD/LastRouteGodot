extends RefCounted

## The upper levels and vents over many seeds: Mezzanine (+1), Offices (+2), Archive (+3) and Attic (+4) generate
## deterministically, every walkable cell of a level is reachable from its seam cross, seams meet, both ends of every
## way up are walkable on their own level, ways up thin out going higher, no level's ceiling rises into the slab of
## the one above, the attic eaves' hide spots are crawl-only (a standing hunter cannot reach them, a crouching runner
## can), and every vent grate opens onto a walkable cell and a duct.

const SEEDS := ["UPPER-A", "UPPER-B", "KYTTU-LAB", "ENDLESS-ROUTE", "PICKUPS"]
const RADIUS := 8
## A full-size humanoid hunter: the rig is about 1.8 m tall before HunterRoster.MODEL_SCALE.
const HUNTER_HEIGHT := 1.8 * HunterRoster.MODEL_SCALE
const OWN_GRID := {1: "mezzanine_grid", 2: "offices_grid", 3: "archive_grid", 4: "attic_grid"}

var _failures := 0


func run(_host: Node) -> int:
	_expect(AtticRouteGenerator.passable(AtticRouteGenerator.CRAWL, PlayerController3D.CROUCH_COLLISION_HEIGHT),
		"a crouching runner does not fit the attic crawlspace")
	_expect(not AtticRouteGenerator.passable(AtticRouteGenerator.CRAWL, HUNTER_HEIGHT),
		"a full-size hunter fits the attic crawlspace")
	_expect(VentNetwork.DUCT_HEIGHT < HUNTER_HEIGHT, "a hunter stands up in the vents")
	_expect(VentNetwork.DUCT_HEIGHT >= VentNetwork.HUNTER_CRAWL_HEIGHT + 0.04, "a crawling hunter does not fit the vents")
	_expect(VentNetwork.DUCT_HEIGHT >= 1.15 and VentNetwork.DUCT_FLOOR >= HUNTER_HEIGHT, "ducts are not about 1.2 m inside over a hunter's headroom")
	_expect(VentNetwork.DUCT_HEIGHT >= PlayerController3D.CROUCH_COLLISION_HEIGHT, "a crouching runner does not fit the vents")
	# the shared sealed-map table reads the same on every level
	for level in range(0, 6):
		var mix := SealRules.seal_mix(level)
		var total := 0.0
		for kind in mix:
			total += float(mix[kind])
			_expect(SealRules.seal_prop(level, kind) != "", "level %d uses seal %s with no themed prop" % [level, kind])
			for tool in SealRules.seal_tools(level, kind):
				_expect(SealRules.tool_mix(level).has(tool), "level %d seal %s needs %s, which never spawns there" % [level, kind, tool])
		_expect(not mix.is_empty() and absf(total - 1.0) < 0.001, "level %d seal mix does not sum to 1: %s" % [level, mix])
	var last_open := 1.0
	for entry in SealRules.RINGS:
		_expect(float(entry[1]) <= last_open, "open share does not shrink going out: %s" % [SealRules.RINGS])
		last_open = float(entry[1])
	_expect(is_equal_approx(SealRules.open_share(Vector3i(0, 0, 0)), 0.75) and is_equal_approx(SealRules.open_share(Vector3i(9, 0, -3)), 0.25),
		"ring lookup does not match the approved table")
	# with the border on, the outermost reachable band still paces relays and tools (second-tool chance, seals)
	if SealRules.BORDER_RADIUS > 0:
		var edge := Vector3i(SealRules.BORDER_RADIUS, 0, 0)
		_expect(SealRules.inside_border(edge) and not SealRules.inside_border(edge + Vector3i(1, 0, 0)), "border ring misplaced")
		_expect(SealRules.second_tool_chance(edge) > 0.0 and SealRules.guaranteed_tool(edge),
			"tools do not keep pace at the border ring")
		_expect(SealRules.BORDER_RADIUS >= SealRules.SECOND_TOOL_RING, "the border cuts off the second-tool band")
	var chunks := 0
	var up_chunks := {}
	var kinds := {}
	var hides := 0
	var spots := 0
	var grates := 0
	var mezz_wells := 0
	for seed_text in SEEDS:
		var stack := _stack(seed_text)
		var twin := _stack(seed_text)
		var vents := VentNetwork.new(stack[0], stack.slice(1))
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				# the Offices, Archive and Attic stack on a deck patch (DeckPatches); the void has its own suite
				if not stack[0].is_chunk_allowed(Vector3i(dx, 1, dz)) or stack[0].is_void_column(Vector3i(dx, 0, dz)):
					continue
				chunks += 1
				var where := "%s (%d,%d)" % [seed_text, dx, dz]
				var grids := {0: stack[0].chunk(Vector3i(dx, 0, dz))["grid"]}
				for level in range(1, 5):
					var data: Dictionary = stack[level].chunk(Vector3i(dx, level, dz))
					grids[level] = data["grid"]
					var own: String = OWN_GRID[level]
					_expect(data[own] == twin[level].chunk(Vector3i(dx, level, dz))[own], "%s +%d not deterministic" % [where, level])
					_expect(_all_reached(data["grid"]), "%s +%d has unreachable floor" % [where, level])
					_expect(_seams_open(data["grid"], data["edges"]), "%s +%d seam cross is not walkable" % [where, level])
					_expect(float(data["ceiling_height"]) <= UpperLevelTools.LEVEL_HEIGHT - UpperLevelTools.SLAB,
						"%s +%d ceiling rises into the slab above" % [where, level])
				for level in range(0, 5):
					var links: Array = stack[level].links_for(Vector3i(dx, level, dz)) if level > 0 else \
						UpperLevelTools.links_up_to(stack[1], Vector3i(dx, 1, dz), 1)
					var has_up := false
					for link in links:
						if int(link["to_level"]) != level or int(link["from_level"]) != level + 1:
							continue
						has_up = true
						kinds[link["kind"]] = int(kinds.get(link["kind"], 0)) + 1
						var top: Vector2i = link["from_cell"]
						var foot: Vector2i = link["to_cell"]
						_expect(int(grids[level + 1][top.y][top.x]) == 0 and int(grids[level][foot.y][foot.x]) == 0,
							"%s %s %d->%d ends not walkable" % [where, link["kind"], level, level + 1])
					if has_up:
						up_chunks[level] = int(up_chunks.get(level, 0)) + 1
				# the Mezzanine's way up is the maze chunk's own stairwell: both levels carve the same cells
				var mezz_data: Dictionary = stack[1].chunk(Vector3i(dx, 1, dz))
				var maze_well: Dictionary = stack[0].stairwell_between(dx, dz, 1)
				_expect((mezz_data["stairwells"] as Array).size() == (0 if maze_well.is_empty() else 1),
					"%s mezzanine and maze disagree on the way up" % where)
				if not maze_well.is_empty():
					mezz_wells += 1
					var landing: Vector2i = maze_well["landing"]
					_expect(int(grids[0][landing.y][landing.x]) == 0 and int(grids[1][landing.y][landing.x]) == 0,
						"%s the +1 stairwell landing %s is not walkable on both levels" % [where, landing])
					for shaft_cell in maze_well["shaft"]:
						_expect(int(mezz_data["mezzanine_grid"][shaft_cell.y][shaft_cell.x]) == MezzanineRouteGenerator.OPEN,
							"%s the +1 stairwell shaft %s is not open air upstairs" % [where, shaft_cell])
				var attic: Dictionary = stack[4].chunk(Vector3i(dx, 4, dz))
				var standing := _flood(attic["attic_grid"], [AtticRouteGenerator.STAND])
				for feature in attic["features"]:
					var cell: Vector2i = feature["cell"]
					if feature["type"] == "atticHatch":
						_expect(standing.has(cell), "%s attic hatch %s not reachable standing" % [where, cell])
					elif feature.get("hide", false):
						hides += 1
						_expect(int(attic["attic_grid"][cell.y][cell.x]) == AtticRouteGenerator.CRAWL and not standing.has(cell),
							"%s attic hide %s is reachable by a standing hunter" % [where, cell])
				for feature in stack[3].chunk(Vector3i(dx, 3, dz))["features"]:
					if feature["type"] == "stackSpot":
						spots += 1
						var cell: Vector2i = feature["cell"]
						_expect(int(grids[3][cell.y][cell.x]) == 0, "%s archive spot %s inside the shelving" % [where, cell])
				var v: Dictionary = vents.chunk(Vector3i(dx, 0, dz))
				for link in v["links"]:
					grates += 1
					var cell: Vector2i = link["from_cell"]
					_expect(int(grids[int(link["from_level"])][cell.y][cell.x]) == 0
						and int(v["grid"][cell.y][cell.x]) == VentNetwork.DUCT,
						"%s vent grate %s does not join a duct to a walkable cell" % [where, cell])
	for level in range(0, 4):
		_expect(int(up_chunks.get(level, 0)) > 0, "no way up from level %d" % level)
		# the maze vetoes a way up that does not fit its halls and suites (_maze_stairwell_fits), so level 0 may sit a few
		# percent under the pure chance that thins the levels above it
		_expect(int(up_chunks.get(level + 1, 0)) <= int(up_chunks.get(level, 0)) * (1.1 if level == 0 else 1.0),
			"ways up do not thin out going higher: %s" % [up_chunks])
	_expect(mezz_wells > 0, "no stairwell up to the Mezzanine in the sampled chunks")
	_expect(hides > 0 and spots > 0 and grates > 0, "missing attic hides, archive spots or vent grates")
	if _failures == 0:
		print("  upper_levels  %d chunks x 4 levels: deterministic, connected, seams meet, under the slab; ways up per level %s (%s); %d crawl-only hides, %d stack spots, %d vent grates, %d stairwells to the mezzanine"
			% [chunks, up_chunks, kinds, hides, spots, grates, mezz_wells])
	return _failures


static func _stack(seed_text: String) -> Array:
	var surface := StreamedRouteGenerator.new(seed_text)
	var mezz := MezzanineRouteGenerator.new(surface)
	var offices := OfficesRouteGenerator.new(mezz)
	var archive := ArchiveRouteGenerator.new(offices)
	return [surface, mezz, offices, archive, AtticRouteGenerator.new(archive)]


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
