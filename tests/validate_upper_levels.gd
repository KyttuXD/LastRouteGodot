extends RefCounted

## Upper levels and vents. The Mezzanine (+1) and the void are removed from play, so no storey above level 0 exists:
## this suite checks that (no +1..+4 chunk, no stairwell up from level 0, the view clamps at level 0), plus the vent and
## crawl sizes and the sealed-map tables every level shares. The Offices/Archive/Attic generators stay in the tree unused
## (they stacked on the Mezzanine and were never wired into play).

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
			# at least one tool that opens it spawns there (a tool carried in from another level may open it too)
			var tools := SealRules.seal_tools(level, kind)
			_expect(tools.any(func(tool) -> bool: return SealRules.tool_mix(level).has(tool)),
				"level %d seal %s needs one of %s, none of which spawns there" % [level, kind, tools])
		# the crowbar and the axe are both break tools, on every seal a tool breaks
		for kind in SealRules.SEAL_TOOLS:
			var tools := SealRules.seal_tools(level, kind)
			_expect(tools.has("axe") and tools.has("crowbar"), "level %d seal %s is not open to both break tools: %s" % [level, kind, tools])
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
	# the Mezzanine (+1, deck patches and the void) is removed from play, and with it the experimental stack the
	# Offices (+2), Archive (+3) and Attic (+4) generators stood on: no storey above level 0 exists in a streamed world.
	_expect(not StreamedRouteGenerator.MEZZANINE_ENABLED and StreamedRouteGenerator.top_level() == 0,
		"an upper level is still in play (the route tops out at level 0)")
	var columns := 0
	for seed_text in SEEDS:
		var surface := StreamedRouteGenerator.new(seed_text)
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				columns += 1
				for level in range(1, 5):
					_expect(not surface.is_chunk_allowed(Vector3i(dx, level, dz)), "%s +%d exists at (%d, %d)" % [seed_text, level, dx, dz])
				_expect(surface.stairwells_at(dx, dz, 0).all(func(well) -> bool: return int(well["upper"]) <= 0),
					"%s a stairwell leads up from level 0 at (%d, %d)" % [seed_text, dx, dz])
	_expect(StreamedFacilityView3D.snapped_level_for_world_y(StreamedFacilityView3D.LEVEL_HEIGHT * 2.0) == 0,
		"the view's level clamp still climbs above level 0")
	if _failures == 0:
		print("  upper_levels  removed: %d columns over %d seeds have no storey above level 0 and no way up; seal tables and vent sizes as before" % [columns, SEEDS.size()])
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
