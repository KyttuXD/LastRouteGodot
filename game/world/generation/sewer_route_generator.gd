class_name SewerRouteGenerator
extends RefCounted

## Deterministic sewer/waterworks layer streamed one level below the Last Route
## maze (level -1). Like StreamedRouteGenerator it owns topology only; the view
## consumes chunk dictionaries of the same CHUNK_SIZE so both layers stream on
## the same coordinates.
##
## Every chunk carries the same main cross so seams always meet: a nine-wide
## brick tunnel along x = 22 and z = 22, made of a three-wide central channel
## of deep flowing water sunk below two railed three-wide walkways. Bridge decks
## cross the channel at regular spacing so nobody is trapped on one bank, and
## the tunnels meet in a junction chamber whose confluence is decked over with
## a cross-shaped grate plaza. Up to two quadrants hold a utility room (pump or valve) on
## a three-wide dry branch; the others may hold an access shaft that climbs to
## an open maze hallway cell above: every entrance is a climbable ladder
## (LevelLink kind "ladder") under a manhole lid or a floor grate ("cover").

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := -1
const SURFACE_LEVEL := 0
## The deep collector: a second sewer level under the first, reached down sloped
## ramp tunnels (no ladder, no loading break). The Inferno maze lies under it.
const LOWER_LEVEL := -2
const INFERNO_LEVEL := -3
## How often a sewer chunk holds a second relay (always when it has a sealed room). Objective, so code, not loot data.
const SEWER_EXTRA_RELAY_CHANCE := .55

## Grid codes. Water is open channel nobody walks in; bridge cells are walkable
## decks with the channel running underneath.
const SOLID := 1
const DRY := 0
const WATER := 2
const BRIDGE := 3
## A cell of a sloped ramp tunnel between two levels (on both of them): no floor
## on the upper level, no ceiling on the lower one, walled on both sides.
const RAMP := 4
## An open drop on the first sewer: the floor is gone and the spur channel pours
## over the edge as a waterfall into the collector's cistern below (blocked to walk).
const FALL := 5
## A stairwell's open well on the sewer side (the stairs themselves, off the walk grid).
const SHAFT := 6
## About one chunk in four has falls from the sewer into the collector.
const FALLS_CHANCE := .28

## Ramps (docs/SEWERS.md): a three-wide tunnel dropping one storey over RAMP_RUN
## cells (about 18 degrees), in one quadrant of a chunk that both levels reserve.
const RAMP_RUN := 12
const RAMP_CHANCE := {-1: .35, -2: .3}

## Seal ids start here so they never meet the pipes' (Breach ids count up from 0)
const SEAL_FIRST_INDEX := 100
const CENTER := CHUNK_SIZE / 2
const TUNNEL_HALF := 4           # 22 - 4 .. 22 + 4: walkway 18-20, water 21-23, walkway 24-26
const CHANNEL_HALF := 1
const JUNCTION_HALF := 6         # 13 x 13 chamber
## One bridge on each tunnel arm either side of the junction (plus the junction's
## grate plaza): a crossing about every 24 m along the channel.
const BRIDGE_OFFSETS := [10, 34]
## The junction's confluence is open water: no grate plaza over it. The
## two bridges on every arm are the way across, and they join all four walkway
## quadrants around the junction.
const QUADRANT_CENTERS := [Vector2i(9, 9), Vector2i(35, 9), Vector2i(9, 35), Vector2i(35, 35)]
const ROOM_HALF := 3             # 7 x 7 utility rooms
const SHAFT_HALF := 1            # 3 x 3 dry shaft chamber under a manhole
## Rooms reserve their cells: no channel, basin, bridge, railing or falls lip
## inside one (the overflow chamber's railed basin read as the channel
## running through a room, so that kind is retired).
const ROOM_KINDS := ["pump_room", "valve_room"]
const LINK_CHANCE := 0.55
## Every sewer space has the same low brick ceiling, so a ladder shaft always
## spans exactly LEVEL_HEIGHT - CEILING_HEIGHT between it and the maze floor.
const CEILING_HEIGHT := 3.2
## Crawl-under pipes (docs/GEOMETRY_AUDIT.md): a low iron main across a utility room's three-wide branch. The underside is the
## crouched capsule plus 5 cm, so a crouched player passes and a standing one (or any normal hunter) does not. The authored
## sewerPipeRun is two stacked mains, the lower 0.11 m in radius about 0.30 m above its origin.
const CRAWL_CLEARANCE := PlayerController3D.CROUCH_COLLISION_HEIGHT + 0.05
const CRAWL_PIPE_MOUNT_Y := CRAWL_CLEARANCE + 0.11
const CRAWL_PIPE_SIZE := Vector3(2.0, 0.55, 0.5)
const CRAWL_CHANCE := 0.6
## Outflow mains ("a massive rusted pipe you crawl under or go around"): a 1.5 m main out of a tunnel's outer wall
## straight across its three-wide walkway, the mouth over the channel. Its underside is CRAWL_CLEARANCE, so a crouched
## runner crawls under; hunters go round over a bridge and the junction (it only sits between the two). At most one per
## chunk, on either sewer, from its own seed stream (the rest of the layout is unchanged).
const OUTFLOW_CHANCE := 0.35
## Collider (local x across the main, z along it from the wall to the mouth), from CRAWL_CLEARANCE up.
const OUTFLOW_SIZE := Vector3(1.64, 1.64, 3.2)
## Offsets along a tunnel arm between its bridge (BRIDGE_OFFSETS) and the junction (CENTER +- JUNCTION_HALF): a hunter
## at the pipe always has a crossing on both sides of it.
const OUTFLOW_OFFSETS := [13, 14, 30, 31]
## Deep channels: the bed lies CHANNEL_DEPTH below the walkways and the water
## surface WATER_SURFACE below them (negative = down). Nobody wades: railings
## line every walkway edge and the channel cells block movement, so the water
## is crossed only on the bridges and the junction's grate plaza.
const CHANNEL_DEPTH := 1.0
const WATER_SURFACE := -0.3

var world_seed: String
var surface: StreamedRouteGenerator
var _cache := {}


func _init(p_surface: StreamedRouteGenerator) -> void:
	surface = p_surface
	world_seed = p_surface.world_seed


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y == LEVEL or coord.y == LOWER_LEVEL


func chunk_id(coord: Vector3i) -> String:
	return "SEWER:%d:%d:%d" % [coord.x, coord.y, coord.z]


func chunk(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if not _cache.has(key):
		# a copy the view's worker generated and the surface adopted
		_cache[key] = surface._chunk_cache[coord] if surface._chunk_cache.has(coord) else _build_chunk(coord)
	return _cache[key]


## The links touching the surface chunk above `coord` (any y). Surface code asks
## this to place manholes/grates; the sewer view uses it for ladders.
func links_for(coord: Vector3i) -> Array:
	return chunk(Vector3i(coord.x, LEVEL, coord.z))["links"]


## The ramp from `upper_level` down one storey in the chunk column (x, z), or {}.
## Deterministic from the seed alone, so the upper and lower chunks (and the
## Inferno maze chunk under the collector) agree without reading each other.
## {quadrant, upper, top (landing on the upper level), ramp, bottom (landing on
## the lower level), connector (lower level, from the landing to its halls),
## top_x / bottom_x (where the slope starts and ends, chunk-local), row, link}.
func ramp_between(x: int, z: int, upper_level: int) -> Dictionary:
	if not RAMP_CHANCE.has(upper_level) or surface.is_void_column(Vector3i(x, 0, z)):
		return {}   # nothing of the sewers or the Inferno is built inside the Mezzanine void
	var rng := SeededRandom.new("%s:RAMP:%d:%d:%d" % [world_seed, x, z, upper_level])
	if rng.next_float() >= float(RAMP_CHANCE[upper_level]):
		return {}
	var quadrant := rng.next_index(QUADRANT_CENTERS.size())
	if upper_level == LOWER_LEVEL:
		# the collector already hosts the bottom of the upper ramp in one quadrant
		var above := ramp_between(x, z, LEVEL)
		if not above.is_empty() and int(above["quadrant"]) == quadrant:
			quadrant = (quadrant + 1) % QUADRANT_CENTERS.size()
	var qc: Vector2i = QUADRANT_CENTERS[quadrant]
	var west := qc.x < CENTER
	var north := qc.y < CENTER
	var walkway := CENTER - TUNNEL_HALF if west else CENTER + TUNNEL_HALF
	# top landing beside the north-south tunnel's outer walkway, the slope running
	# away from it, the bottom landing at the chunk edge
	var top_x0 := walkway - 3 if west else walkway + 1
	var ramp_x0 := top_x0 - RAMP_RUN if west else top_x0 + 3
	var bottom_x0 := ramp_x0 - 3 if west else ramp_x0 + RAMP_RUN
	var row0 := qc.y - 1
	# the lower level's halls: the collector's tunnel walkway, or the Inferno maze's central hall
	var hall_edge := (CENTER - TUNNEL_HALF if north else CENTER + TUNNEL_HALF) if upper_level == LEVEL \
		else (CENTER - 1 if north else CENTER + 1)
	var conn_z0 := row0 if north else hall_edge + 1
	var conn_z1 := hall_edge - 1 if north else row0 + 2
	if upper_level == LOWER_LEVEL:
		conn_z1 = hall_edge if north else conn_z1
		conn_z0 = conn_z0 if north else hall_edge
	var chunk := Vector3i(x, 0, z)
	var top_cell := Vector2i(top_x0 + 1, qc.y)
	var bottom_cell := Vector2i(bottom_x0 + 1, qc.y)
	var link := LevelLink.make("ramp", chunk, upper_level, top_cell, upper_level - 1, bottom_cell)
	# where the slope starts and ends (chunk-local x): bodies walking the link
	# follow the same surface the collider has, flat over the landings
	link["top_x"] = float(top_x0) if west else float(top_x0 + 3)
	link["bottom_x"] = float(ramp_x0) if west else float(ramp_x0 + RAMP_RUN)
	return {"quadrant": quadrant, "upper": upper_level, "row": qc.y,
		"top": Rect2i(top_x0, row0, 3, 3), "ramp": Rect2i(ramp_x0, row0, RAMP_RUN, 3),
		"bottom": Rect2i(bottom_x0, row0, 3, 3),
		"connector": Rect2i(bottom_x0, conn_z0, 3, conn_z1 - conn_z0 + 1),
		"top_x": float(top_x0) if west else float(top_x0 + 3),
		"bottom_x": float(ramp_x0) if west else float(ramp_x0 + RAMP_RUN),
		"link": link}


## The waterfall from the first sewer into the collector in chunk column (x, z),
## or {}. Deterministic and in a quadrant no ramp uses on either level.
## {quadrant, void (the drop on -1, open above the cistern on -2), spur (the
## channel running to the edge), spur_deck (where it crosses the walkway),
## overlook (a railed ledge beside it), chamber + pool (the cistern on -2),
## edge_z / edge_x0 (the lip the water pours over), north}.
func falls_between(x: int, z: int) -> Dictionary:
	if surface.is_void_column(Vector3i(x, 0, z)):
		return {}
	var rng := SeededRandom.new("%s:FALLS:%d:%d" % [world_seed, x, z])
	if rng.next_float() >= FALLS_CHANCE:
		return {}
	var free := [0, 1, 2, 3]
	for upper in [LEVEL, LOWER_LEVEL]:
		var ramp := ramp_between(x, z, upper)
		if not ramp.is_empty():
			free.erase(int(ramp["quadrant"]))
	if free.is_empty():
		return {}
	var quadrant: int = free[rng.next_index(free.size())]
	var qc: Vector2i = QUADRANT_CENTERS[quadrant]
	var north := qc.y < CENTER
	var walk_lo := CENTER - TUNNEL_HALF if north else CENTER + CHANNEL_HALF + 1
	# north quadrants: the drop is rows qc-3..qc+3 and the spur comes up from the
	# main channel (south of it); south quadrants mirror that
	var void_rect := Rect2i(qc.x - 3, qc.y - 3, 7, 7)
	var spur_z0 := qc.y + 4 if north else CENTER + CHANNEL_HALF + 1
	var spur_z1 := CENTER - CHANNEL_HALF - 1 if north else qc.y - 4
	var spur := Rect2i(qc.x - 1, spur_z0, 3, spur_z1 - spur_z0 + 1)
	var deck := Rect2i(qc.x - 1, walk_lo, 3, 3)
	var ledge_z0 := qc.y + 4 if north else CENTER + TUNNEL_HALF + 1
	var ledge_z1 := CENTER - TUNNEL_HALF - 1 if north else qc.y - 4
	var overlook := Rect2i(qc.x + 2, ledge_z0, 3, ledge_z1 - ledge_z0 + 1)
	var chamber := Rect2i(qc.x - 5, qc.y - 5 if north else qc.y - 6, 11, 12)
	var pool := Rect2i(qc.x - 2, qc.y - 2 if north else qc.y - 3, 5, 6)
	# The deliberate jump (docs/SEWERS.md): one gap in the overlook's railing, in front of the drop. Stepping through it
	# off the ledge (`cell` is the first drop cell, `start` the ledge cell before it, `dir` the way out) is a plunge into the
	# cistern: the arc lands at `land` in the pool, the swim ends at `exit` on the walkway ring (chunk-local, cell centres).
	var jump_dir := Vector2i(0, -1) if north else Vector2i(0, 1)
	var jump_cell := Vector2i(qc.x + 3, void_rect.end.y - 1 if north else void_rect.position.y)
	var jump := {"cell": jump_cell, "start": jump_cell - jump_dir, "dir": jump_dir,
		"land": Vector2(qc.x + 1.5, qc.y + .5 if north else qc.y - .5),
		"exit": Vector2(qc.x + 1.5, float(pool.end.y) + .5 if north else float(pool.position.y) - .5)}
	return {"quadrant": quadrant, "north": north, "void": void_rect, "spur": spur, "spur_deck": deck,
		"overlook": overlook, "chamber": chamber, "pool": pool, "center": qc, "jump": jump,
		"edge_z": float(void_rect.end.y) if north else float(void_rect.position.y),
		"edge_x0": float(qc.x - 1)}


## Cells of the chunk (x, `level`, z) under the channel trench of the sewer storey above it: the trench bed lies
## CHANNEL_DEPTH under that storey's floor, deeper than the slab, so this storey's vault stops short of it there.
## The main cross's channels on both sewers, the falls' spur channel on the first sewer and its cistern pool on the
## collector. Pure seed maths, like ramps and falls.
func trench_cells_below(x: int, z: int, level: int) -> Array:
	var above := level + 1
	if above not in [LEVEL, LOWER_LEVEL] or not is_chunk_allowed(Vector3i(x, above, z)):
		return []
	var rects := [Rect2i(0, CENTER - CHANNEL_HALF, CHUNK_SIZE, CHANNEL_HALF * 2 + 1),
		Rect2i(CENTER - CHANNEL_HALF, 0, CHANNEL_HALF * 2 + 1, CHUNK_SIZE)]
	var falls := falls_between(x, z)
	if not falls.is_empty():
		rects.append(falls["spur"] if above == LEVEL else falls["pool"])
	var out := []
	for rect_value in rects:
		var rect: Rect2i = rect_value
		for cz in range(maxi(rect.position.y, 0), mini(rect.end.y, CHUNK_SIZE)):
			for cx in range(maxi(rect.position.x, 0), mini(rect.end.x, CHUNK_SIZE)):
				out.append(Vector2i(cx, cz))
	return out


## Every ramp touching level `level` in the chunk column (x, z).
func ramps_at(x: int, z: int, level: int) -> Array:
	var out := []
	for upper in [level, level + 1]:
		var ramp := ramp_between(x, z, upper)
		if not ramp.is_empty():
			out.append(ramp)
	return out


## Cell -> true when it is part of a ramp's slope, for `level` in column (x, z).
func ramp_cells(x: int, z: int, level: int) -> Dictionary:
	var cells := {}
	for ramp in ramps_at(x, z, level):
		var rect: Rect2i = ramp["ramp"]
		for cz in range(rect.position.y, rect.end.y):
			for cx in range(rect.position.x, rect.end.x):
				cells[Vector2i(cx, cz)] = {"upper": int(ramp["upper"]) == level, "ramp": ramp}
	return cells


func _build_chunk(coord: Vector3i) -> Dictionary:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(SOLID)
		grid.append(row)
	if not is_chunk_allowed(coord):
		return _streamed_schema(coord, grid, [], [], [])
	_carve_main_cross(grid)
	# the collector gets its own rooms and dressing; the first sewer keeps its seed stream
	var salt := "SEWER" if coord.y == LEVEL else "SEWER%d" % -coord.y
	var rng := SeededRandom.new("%s:%s:%d:%d" % [world_seed, salt, coord.x, coord.z])
	var rooms := []
	var links := []
	var features := []
	var order := [0, 1, 2, 3]
	var ramps := ramps_at(coord.x, coord.z, coord.y)
	# Deterministic shuffle so rooms and shafts land in different quadrants per chunk.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.next_index(i + 1)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	var room_count := 1 + rng.next_index(2)
	var wants_link := coord.x == 0 and coord.z == 0 or rng.next_float() < LINK_CHANCE
	# ladders come down from the maze only into the first sewer
	if coord.y != LEVEL:
		wants_link = false
	# ramp quadrants are taken: no room or shaft there
	for ramp in ramps:
		order.erase(int(ramp["quadrant"]))
		_carve_ramp(grid, ramp, coord.y)
	var falls := falls_between(coord.x, coord.z)
	if not falls.is_empty():
		order.erase(int(falls["quadrant"]))
		_carve_falls(grid, falls, coord.y)
		if coord.y == LEVEL:
			# the spur crosses the tunnel walkway on a bridge like the channels do
			var deck: Rect2i = falls["spur_deck"]
			features.append({"type": "sewerBridge", "cell": deck.position + Vector2i(1, 1), "yaw": PI / 2.0})
	# a stairwell up to the maze takes its quadrant too, and so does one from the
	# maze up a storey: its foot box covers that quadrant of the maze, so no
	# ladder lid may come up there
	var wells: Array = surface.stairwells_at(coord.x, coord.z, coord.y) if coord.y == LEVEL else []
	var shaft_cells := {}
	for well in wells:
		order.erase(int(well["quadrant"]))
		_carve_stairwell(grid, well, coord.y, shaft_cells)
	if coord.y == LEVEL:
		for well in surface.stairwells_at(coord.x, coord.z, SURFACE_LEVEL):
			order.erase(int(well["quadrant"]))
	# rooms never take the last free quadrant while a ladder is still wanted (the maze's wells erase up to two)
	if wants_link:
		room_count = mini(room_count, maxi(order.size() - 1, 0))
	var surface_data: Dictionary = surface.chunk(Vector3i(coord.x, SURFACE_LEVEL, coord.z))
	var blocked := _surface_blocked_cells(surface_data)
	var covers := ["manhole", "grate"]
	for slot in order.size():
		var quadrant: int = order[slot]
		var qc: Vector2i = QUADRANT_CENTERS[quadrant]
		if slot < room_count:
			var kind: String = ROOM_KINDS[rng.next_index(ROOM_KINDS.size())]
			var half := ROOM_HALF
			var rect := Rect2i(qc - Vector2i(half, half), Vector2i.ONE * (half * 2 + 1))
			_carve_rect(grid, rect, DRY)
			_carve_branch(grid, qc, half)
			rooms.append({"kind": kind, "rect": rect, "center": qc})
			features.append_array(_room_features(kind, rect, qc))
		elif wants_link and links.size() < 2:
			var spot := _shaft_cell(qc, surface_data["grid"], blocked)
			if spot.is_empty():
				continue
			var up: Vector2i = spot["cell"]
			var cover: String = covers[rng.next_index(covers.size())]
			# The ladder hangs flush on a hallway wall in the maze and on the brick of
			# the same side below: the 3x3 shaft chamber opens away from that wall and
			# its branch leaves from the chamber's middle, so the wall behind the rungs
			# stays solid on both levels.
			var wall: Vector2i = spot["wall"]
			var chamber_center := up - wall
			_carve_rect(grid, Rect2i(chamber_center - Vector2i(SHAFT_HALF, SHAFT_HALF), Vector2i(3, 3)), DRY)
			_carve_branch(grid, chamber_center, SHAFT_HALF)
			var link := LevelLink.make("ladder", coord, SURFACE_LEVEL, up, LEVEL, up)
			link["cover"] = cover
			link["wall"] = wall
			links.append(link)
			features.append({"type": "sewerLadder", "cell": up, "link": links.back()["id"], "wall": wall})
	features.append_array(_crawl_features(rooms, grid, rng))
	features.append_array(_tunnel_features())
	features.append_array(_crossing_features())
	features = _centre_room_lamps(grid, rooms, features)
	features = _pair_tunnel_lamps(grid, features)
	features = _mount_on_walls(grid, features)
	features.append_array(_outflow_features(coord, grid, features, links))
	features.append_array(_flood_valve_features(grid, features, links))
	features.append_array(_gate_features(coord, grid, features, links))
	var schema := _streamed_schema(coord, grid, rooms, links, features, ramps)
	schema["stairwells"] = wells
	schema["shaft_cells"] = shaft_cells
	schema["hunter_spawns"] = _hunter_spawns(coord, grid, schema, wells, falls)
	return schema


## Dormant hunter spawn candidates on a sewer chunk (102, hunters may spawn in the sewers), the sewer twin of
## StreamedRouteGenerator._hunter_spawns: the same danger-scaled chance per chunk, one candidate (two on the rare deep
## roll), at least six cells apart, admitted at runtime by the same relay-scaled population budget. Only on dry walkway
## or room floor whose four neighbours are dry too (never water, a bridge deck, a ramp slope, a falls lip or a well), off
## sealed rooms and their gates, clear of ladders, ramp landings, stairwells, the falls overlook, dressing and pickups.
## Spawning only: who follows a runner down or climbs back up is still HunterRoster.sewer_affinity, so the identity is
## drawn from the hunters who go below (never a sewer-shy "avoid" one). The columns round the arrival chunk and under a
## maze safe room stay empty: a sewer candidate one storey down would otherwise outrank the guaranteed arrival hunter.
## Its own seed stream (SEWER-HUNTERS), so no other sewer content shifts.
func _hunter_spawns(coord: Vector3i, sewer_grid: Array, data: Dictionary, wells: Array, falls: Dictionary) -> Array:
	if not is_chunk_allowed(coord):
		return []
	if absi(coord.x) <= 1 and absi(coord.z) <= 1:
		return []
	if surface.is_safe_room(Vector3i(coord.x, SURFACE_LEVEL, coord.z)):
		return []
	var profile := surface.difficulty_for_level(coord.y)
	var danger := float(profile["danger"])
	var rng := SeededRandom.new("%s:SEWER-HUNTERS:%s" % [world_seed, chunk_id(coord)])
	if rng.next_float() >= lerpf(0.16, 0.42, danger):
		return []
	var excluded := {}
	for cell in data.get("sealed_cells", []):
		excluded[cell] = true
	for spec in data.get("breakables", []):
		for cell in (spec as Dictionary).get("extras", {}).get("cells", []):
			StreamedRouteGenerator._exclude_neighbourhood(excluded, cell, 2)
	for link in data.get("links", []):
		StreamedRouteGenerator._exclude_neighbourhood(excluded, link["to_cell"], 2)
		StreamedRouteGenerator._exclude_neighbourhood(excluded, link["from_cell"], 2)
	for ramp in data.get("ramps", []):
		for key in ["top", "bottom", "ramp"]:
			_exclude_rect(excluded, (ramp[key] as Rect2i).grow(2))
		var ramp_link: Dictionary = ramp["link"]
		StreamedRouteGenerator._exclude_neighbourhood(excluded, ramp_link["from_cell"], 2)
		StreamedRouteGenerator._exclude_neighbourhood(excluded, ramp_link["to_cell"], 2)
	for well in wells:
		_exclude_rect(excluded, (well["box"] as Rect2i).grow(2))
	if not falls.is_empty():
		_exclude_rect(excluded, (falls["overlook"] as Rect2i).grow(1))
		_exclude_rect(excluded, (falls["void"] as Rect2i).grow(1))
	for key in ["features", "region_props", "pickups", "fixtures"]:
		for entry_value in data.get(key, []):
			var entry: Dictionary = entry_value
			if entry.has("cell"):
				StreamedRouteGenerator._exclude_neighbourhood(excluded, entry["cell"], 1)
			for cell in entry.get("occupied_cells", []) + entry.get("cells", []):
				StreamedRouteGenerator._exclude_neighbourhood(excluded, cell, 1)
			for cell in entry.get("behind", []):
				excluded[cell] = true
	var candidates: Array[Vector2i] = []
	for z in range(3, CHUNK_SIZE - 3):
		for x in range(3, CHUNK_SIZE - 3):
			var cell := Vector2i(x, z)
			if excluded.has(cell):
				continue
			var dry := true
			for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var at: Vector2i = cell + (offset as Vector2i)
				if int(sewer_grid[at.y][at.x]) != DRY:
					dry = false
					break
			if dry:
				candidates.append(cell)
	if candidates.is_empty():
		return []
	var identities := []
	for id_value in StreamedRouteGenerator.STREAMED_HUNTER_IDS:
		if HunterRoster.sewer_affinity(String(id_value)) != "avoid":
			identities.append(id_value)
	var count := 1
	if coord.y <= -6 and rng.next_float() < minf(0.22, danger * 0.18):
		count = 2
	var result := []
	for index in count:
		if candidates.is_empty():
			break
		var cell: Vector2i = candidates.pop_at(rng.next_index(candidates.size()))
		var identity := String(identities[rng.next_index(identities.size())])
		if coord.y <= -2 and rng.next_float() < .015:
			identity = HunterRoster.office_void_for("%s:%s:%d" % [world_seed, chunk_id(coord), index])
		result.append({"id": surface.hunter_id(coord, index), "hunter_id": identity, "cell": cell,
			"level": coord.y, "origin_chunk": coord})
		candidates = candidates.filter(func(other: Vector2i) -> bool:
			return other.distance_to(cell) >= 6.0)
	return result


static func _exclude_rect(excluded: Dictionary, rect: Rect2i) -> void:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			excluded[Vector2i(x, z)] = true


## A stairwell's sewer end: the walled box, its landing and doorway, and a
## three-wide branch to the tunnel's walkway; the well cells stay SHAFT.
static func _carve_stairwell(grid: Array, well: Dictionary, level: int, shaft_cells: Dictionary) -> void:
	_carve_rect(grid, well["box"], SOLID)
	var hall_edge := CENTER - TUNNEL_HALF if bool(well["north"]) else CENTER + TUNNEL_HALF
	_carve_rect(grid, Stairwells.corridor(well, hall_edge), DRY)
	var cells := Stairwells.cells_for(well, level)
	for cell in cells["walk"]:
		grid[cell.y][cell.x] = DRY
	for cell in cells["shaft"]:
		grid[cell.y][cell.x] = SHAFT
		shaft_cells[cell] = {"upper": level == int(well["upper"]), "well": well}


## The falls' cells on this level. On the first sewer: the drop, the spur
## channel to its edge (decked where it crosses the walkway) and the railed
## overlook ledge beside it. On the collector: the cistern chamber with its deep
## pool under the drop, joined to the tunnel by a branch.
static func _carve_falls(grid: Array, falls: Dictionary, level: int) -> void:
	if level == LEVEL:
		_carve_rect(grid, falls["overlook"], DRY)
		_carve_rect(grid, falls["spur"], WATER)
		_carve_rect(grid, falls["spur_deck"], BRIDGE)
		_carve_rect(grid, falls["void"], FALL)
	else:
		_carve_rect(grid, falls["chamber"], DRY)
		_carve_branch(grid, falls["center"], 5)
		_carve_rect(grid, falls["pool"], WATER)


## One ramp's cells on this level: the top landing and slope on the upper level,
## the slope, bottom landing and connector on the lower one.
static func _carve_ramp(grid: Array, ramp: Dictionary, level: int) -> void:
	_carve_rect(grid, ramp["ramp"], RAMP)
	if int(ramp["upper"]) == level:
		_carve_rect(grid, ramp["top"], DRY)
	else:
		_carve_rect(grid, ramp["bottom"], DRY)
		_carve_rect(grid, ramp["connector"], DRY)


## The chunk in StreamedRouteGenerator's schema so the streamed view, minimap and
## audits read it like any maze chunk: "grid" is 0 for every walkable cell
## (water included) and 1 for brick; "sewer_grid" keeps the dry/water/bridge codes.
func _streamed_schema(coord: Vector3i, sewer_grid: Array, rooms: Array, links: Array, features: Array,
		ramps: Array = []) -> Dictionary:
	var grid := []
	for row_value in sewer_grid:
		var row := []
		for code in row_value:
			row.append(0 if is_walkable(int(code)) else 1)
		grid.append(row)
	var room_entries := []
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		room_entries.append({"id": "%s:ROOM:%d" % [chunk_id(coord), index], "room_type": room["kind"],
			"rect": room["rect"], "center": room["center"]})
	var seam := range(CENTER - TUNNEL_HALF, CENTER + TUNNEL_HALF + 1)
	# sealed utility rooms (SealPlanner / SealRules, "more sealed"): a gate across each shut room's branch
	var breakables: Array = []
	var sealed := {}
	var gate_cells := {}
	if is_chunk_allowed(coord) and not rooms.is_empty():
		var seal_plan := SealPlanner.plan_rooms(world_seed, coord, grid, room_entries)
		breakables = SealPlanner.specs(world_seed, coord, seal_plan, coord.y, SEAL_FIRST_INDEX)
		for spec in breakables:
			_frame_door_seal(spec, grid, sewer_grid, coord.y)
		for cell in seal_plan["sealed"]:
			sealed[cell] = true
		for spec in breakables:
			for cell in spec["extras"]["cells"]:
				StreamedRouteGenerator._exclude_neighbourhood(gate_cells, cell, 1)
	var region_props := _feature_props(coord, features)
	breakables = _pipe_breakables(coord, sewer_grid, region_props) + breakables   # the pipes' ids count from 0, the seals' from 100
	var gates := _gates(region_props)
	return {"schema": 2, "coord": coord, "chunk_id": chunk_id(coord), "level": coord.y,
		"biome": "sewer", "region": "sewer", "grid": grid, "sewer_grid": sewer_grid,
		"rooms": room_entries, "corridors": [], "suites": [],
		"edges": {"west": seam, "east": seam, "north": seam, "south": seam},
		"stairs": [], "safe_room": false, "safe_room_data": {}, "region_props": region_props,
		"gates": gates,
		"fixtures": _fixtures(coord, grid, room_entries, features),
		"pickups": _pickups(coord, sewer_grid, grid, features, links, sealed, gate_cells),
		"breakables": breakables, "sealed_cells": sealed.keys(),
		"hunter_spawns": [], "dual_level_room": {},
		"floor_voids": [], "ceiling_voids": [], "structural_voids": [],
		"difficulty": surface.difficulty_for_level(coord.y),
		"links": links, "features": features, "ramps": ramps,
		"falls": falls_between(coord.x, coord.z) if is_chunk_allowed(coord) else {},
		"ramp_cells": ramp_cells(coord.x, coord.z, coord.y), "crawl_cells": _crawl_stripe_cells(features)}


## A locked-door seal is a door in a frame (a door standing alone on a walkway). SealPlanner gates a room's branch three
## cells wide, one cell outside the room, so the door needs a wall on both jambs: where the opening is exactly those three
## cells (brick beyond both ends) the two outer cells become brick and the door fills the middle one; anywhere wider the
## seal becomes a barricade instead, which spans the whole gate on its own.
static func _frame_door_seal(spec: Dictionary, grid: Array, sewer_grid: Array, level: int) -> void:
	var extras: Dictionary = spec["extras"]
	if String(extras.get("seal", "")) != "locked_door":
		return
	var cells: Array = extras["cells"]
	var along: Vector2i = (cells[1] as Vector2i) - (cells[0] as Vector2i)
	var jambs := [(cells[0] as Vector2i) - along, (cells[2] as Vector2i) + along]
	var framed := jambs.all(func(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < CHUNK_SIZE and c.y < CHUNK_SIZE and int(sewer_grid[c.y][c.x]) == SOLID)
	if framed:
		for side in [cells[0], cells[2]]:
			var c: Vector2i = side
			sewer_grid[c.y][c.x] = SOLID
			grid[c.y][c.x] = 1
		extras["door_frame"] = jambs
		return
	extras["seal"] = "barricade"
	spec["variant"] = SealRules.seal_prop(level, "barricade")
	spec["hp"] = int(SealRules.SEAL_HP.get("barricade", 3))
	spec["tools"] = SealPlanner._tools(level, "barricade")
	spec["locked"] = false


static func _carve_rect(grid: Array, rect: Rect2i, code: int) -> void:
	for z in range(maxi(rect.position.y, 0), mini(rect.end.y, CHUNK_SIZE)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, CHUNK_SIZE)):
			grid[z][x] = code


func _carve_main_cross(grid: Array) -> void:
	var lo := CENTER - TUNNEL_HALF
	var width := TUNNEL_HALF * 2 + 1
	_carve_rect(grid, Rect2i(0, lo, CHUNK_SIZE, width), DRY)
	_carve_rect(grid, Rect2i(lo, 0, width, CHUNK_SIZE), DRY)
	_carve_rect(grid, Rect2i(CENTER - JUNCTION_HALF, CENTER - JUNCTION_HALF,
		JUNCTION_HALF * 2 + 1, JUNCTION_HALF * 2 + 1), DRY)
	var c_lo := CENTER - CHANNEL_HALF
	var c_w := CHANNEL_HALF * 2 + 1
	_carve_rect(grid, Rect2i(0, c_lo, CHUNK_SIZE, c_w), WATER)
	_carve_rect(grid, Rect2i(c_lo, 0, c_w, CHUNK_SIZE), WATER)
	# Three-cell bridge decks over each channel along the tunnels: the water
	# keeps flowing under every deck, and meets in the open at the junction.
	for offset in BRIDGE_OFFSETS:
		_carve_rect(grid, Rect2i(offset - 1, c_lo, 3, c_w), BRIDGE)
		_carve_rect(grid, Rect2i(c_lo, offset - 1, c_w, 3), BRIDGE)


## A three-wide dry branch from a room/shaft centre straight to the nearer
## tunnel's outer walkway.
static func _carve_branch(grid: Array, from: Vector2i, half: int) -> void:
	var walk_lo := CENTER - TUNNEL_HALF
	var walk_hi := CENTER + TUNNEL_HALF
	var dx := absi(from.x - CENTER)
	var dz := absi(from.y - CENTER)
	if dx <= dz:
		# Toward the north-south tunnel along x.
		var start := from.x + half + 1 if from.x < CENTER else walk_hi + 1
		var finish := walk_lo if from.x < CENTER else from.x - half
		_carve_rect(grid, Rect2i(start, from.y - 1, finish - start, 3), DRY)
	else:
		var start := from.y + half + 1 if from.y < CENTER else walk_hi + 1
		var finish := walk_lo if from.y < CENTER else from.y - half
		_carve_rect(grid, Rect2i(from.x - 1, start, 3, finish - start), DRY)


## Hiding spots in the utility rooms: a cabinet or locker backed against a room
## wall, one per room, kept off the dressing. Same fixture records as the maze.
func _fixtures(coord: Vector3i, grid: Array, rooms: Array, features: Array) -> Array:
	var used := {}
	for feature in features:
		StreamedRouteGenerator._exclude_neighbourhood(used, feature["cell"], 1)
	var rng := SeededRandom.new("%s:SEWER-FIXTURES:%d:%d" % [world_seed, coord.x, coord.z])
	var result := []
	for room in rooms:
		var rect: Rect2i = room["rect"]
		var candidates := []
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, z)
				if not used.has(cell) and int(grid[z][x]) == 0 and StreamedRouteGenerator._wall_count(grid, cell) == 1:
					candidates.append(cell)
		if candidates.is_empty():
			continue
		var cell: Vector2i = candidates[rng.next_index(candidates.size())]
		var backing := StreamedRouteGenerator._backing_wall_direction(grid, cell)
		result.append({"id": "%s:FIXTURE:HIDING_SPOT:%d" % [chunk_id(coord), result.size()], "kind": "hiding_spot",
			"cell": cell, "yaw": StreamedRouteGenerator._room_facing_yaw(cell, cell - backing),
			"backing_wall": backing, "open_direction": -backing})
	return result


## Relays and batteries on dry walkways (never in the water, on a bridge or by
## a ladder), at a little under the maze's density, sometimes a tool.
func _pickups(coord: Vector3i, sewer_grid: Array, grid: Array, features: Array, links: Array,
		sealed: Dictionary = {}, gate_cells: Dictionary = {}) -> Array:
	var excluded := gate_cells.duplicate()   # nothing lies in a seal's gate or against it
	for feature in features:
		StreamedRouteGenerator._exclude_neighbourhood(excluded, feature["cell"], 1)
		for behind in feature.get("behind", []):
			excluded[behind] = true
	for link in links:
		StreamedRouteGenerator._exclude_neighbourhood(excluded, link["to_cell"], 2)
	var candidates := []
	for z in range(1, CHUNK_SIZE - 1):
		for x in range(1, CHUNK_SIZE - 1):
			var cell := Vector2i(x, z)
			if int(sewer_grid[z][x]) == DRY and not excluded.has(cell) \
					and StreamedRouteGenerator._open_spawn_neighbourhood(grid, cell):
				candidates.append(cell)
	# Sealed rooms (SealRules): the first relay and the tools stay on open ground, the second relay usually sits behind a seal
	var sealed_candidates := []
	if not sealed.is_empty():
		var open_candidates := []
		for candidate in candidates:
			if sealed.has(candidate):
				sealed_candidates.append(candidate)
			else:
				open_candidates.append(candidate)
		candidates = open_candidates
	var rng := SeededRandom.new("%s:SEWER-PICKUPS:%d:%d" % [world_seed, coord.x, coord.z])
	# The relays and a sealed room's guaranteed tool are the objective (code); the rest is the `sewer` loot table
	# (res://data/loot/sewer.json, or a pack's table for "sewer").
	var loot := LootTables.table_for("sewer")
	var plans := ["relay"] + Array(loot.get("base", []))
	if rng.next_float() < SEWER_EXTRA_RELAY_CHANCE or not sealed_candidates.is_empty():
		plans.append("relay")
	plans.append_array(LootTables.roll(loot, rng))
	if not plans.has("tool") and not sealed.is_empty() and SealRules.guaranteed_tool(coord):
		plans.append("tool")
	var result := []
	var kind_indices := {}
	for kind_value in plans:
		if candidates.is_empty() and sealed_candidates.is_empty():
			break
		var kind := String(kind_value)
		var index := int(kind_indices.get(kind, 0))
		var from_sealed := kind == "relay" and index >= 1 and not sealed_candidates.is_empty() \
			and (index >= 2 or rng.next_float() < SealRules.SECOND_RELAY_SEALED)
		var pool: Array = sealed_candidates if from_sealed or candidates.is_empty() else candidates
		var cell: Vector2i = pool.pop_at(rng.next_index(pool.size()))
		kind_indices[kind] = index + 1
		var item := LootTables.item_for(kind, loot, rng, coord)
		result.append({"id": surface.pickup_id(coord, index, kind), "cell": cell, "kind": kind, "item": item})
	# Aid items (none in the built-in sewer table) roll from their own stream after everything above, like the route's.
	var aid_rng := SeededRandom.new("%s:SEWER-PICKUPS-AID:%d:%d" % [world_seed, coord.x, coord.z])
	for item_value in LootTables.roll_aid(loot, aid_rng, surface.coop):
		var pool: Array = candidates if not candidates.is_empty() else sealed_candidates
		if pool.is_empty():
			break
		var cell: Vector2i = pool.pop_at(aid_rng.next_index(pool.size()))
		var index := int(kind_indices.get("tool", 0))
		kind_indices["tool"] = index + 1
		result.append({"id": surface.pickup_id(coord, index, "tool"), "cell": cell, "kind": "tool", "item": String(item_value)})
	return result


## Unit step from a ladder cell to the wall its rungs are fixed to: away from
## the tunnel the shaft's branch runs to (the same axis _carve_branch picks).
static func _ladder_wall(cell: Vector2i) -> Vector2i:
	if absi(cell.x - CENTER) <= absi(cell.y - CENTER):
		return Vector2i(-1, 0) if cell.x < CENTER else Vector2i(1, 0)
	return Vector2i(0, -1) if cell.y < CENTER else Vector2i(0, 1)


## Maze cells the manhole must keep clear of: anything a prop, fixture, pickup
## or hunter spawn claims (with a one-cell ring), so no lid sits under furniture.
static func _surface_blocked_cells(data: Dictionary) -> Dictionary:
	var blocked := {}
	for key in ["region_props", "fixtures", "pickups", "hunter_spawns"]:
		for entry in data.get(key, []):
			var cells: Array = [entry.get("cell", Vector2i(-99, -99))]
			cells.append_array(entry.get("occupied_cells", []))
			cells.append_array(entry.get("doorway_cells", []))
			for cell in cells:
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						blocked[Vector2i(cell) + Vector2i(dx, dz)] = true
	for room in data.get("rooms", []):
		# Hallway cells only: rooms keep their own floor plans.
		# The rect includes the room's wall ring, so the hall cell just outside it
		# stays free: that is where a ladder can stand flush against the wall.
		var rect: Rect2i = room.get("rect", Rect2i())
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				blocked[Vector2i(x, z)] = true
	return blocked


## The maze hallway cell nearest the quadrant centre where a ladder can stand
## flush against a hallway wall: open floor with solid wall directly behind it
## (toward `wall`), open floor in front (where the lid lies) and to both sides.
## The wall may face any way but toward the tunnel (the sewer chamber's branch
## would then run through the brick behind the rungs). Returns {cell, wall} or {}.
static func _shaft_cell(quadrant_center: Vector2i, surface_grid: Array, blocked: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1 << 30
	var open := func(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < CHUNK_SIZE and c.y < CHUNK_SIZE and int(surface_grid[c.y][c.x]) == 0
	for z in range(quadrant_center.y - 7, quadrant_center.y + 8):
		for x in range(quadrant_center.x - 7, quadrant_center.x + 8):
			var cell := Vector2i(x, z)
			# Stay out of the tunnel band and off the chunk edge (the chamber reaches two cells out).
			if absi(x - CENTER) <= TUNNEL_HALF + SHAFT_HALF + 1 or absi(z - CENTER) <= TUNNEL_HALF + SHAFT_HALF + 1:
				continue
			if x < 4 or z < 4 or x > CHUNK_SIZE - 5 or z > CHUNK_SIZE - 5:
				continue
			if blocked.has(cell) or not open.call(cell):
				continue
			var toward_tunnel := -_ladder_wall(cell)
			for wall_value in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var wall: Vector2i = wall_value
				if wall == toward_tunnel or open.call(cell + wall):
					continue
				# the rails and lid keep a cell clear of the hall's pilasters and the arches they spring
				if RefDecor.near_pilaster(cell, wall):
					continue
				var side := Vector2i(absi(wall.y), absi(wall.x))
				if not open.call(cell - wall) or blocked.has(cell - wall) \
						or not open.call(cell + side) or not open.call(cell - side):
					continue
				var d := (cell - quadrant_center).length_squared()
				if d < best_d:
					best_d = d
					best = {"cell": cell, "wall": wall}
	return best


## Room dressing. "wall" is the unit step from the cell to the brick the piece
## is fixed to (Vector2i.ZERO for free-standing pieces).
static func _room_features(kind: String, rect: Rect2i, center: Vector2i) -> Array:
	var north := Vector2i(center.x, rect.position.y)
	var west := Vector2i(rect.position.x, center.y)
	var east := Vector2i(rect.end.x - 1, center.y)
	match kind:
		"pump_room":
			return [{"type": "sewerPump", "cell": north, "wall": Vector2i(0, -1)},
				{"type": "sewerPipeRun", "cell": west, "wall": Vector2i(-1, 0)},
				{"type": "sewerLamp", "cell": east, "wall": Vector2i(1, 0)}]
		_:
			return [{"type": "sewerValveWheel", "cell": north, "wall": Vector2i(0, -1)},
				{"type": "sewerValveWheel", "cell": east, "wall": Vector2i(1, 0)},
				{"type": "sewerPipeRun", "cell": west, "wall": Vector2i(-1, 0)}]


## Deliberate crawl-under spots: at most one per chunk, in the branch of a pump or valve room (never an overflow chamber, never a
## shaft with a ladder), as two overlapping mains that span the three-wide passage. "behind" lists the cells past the pipe
## (the rest of the branch and the room): no pickup is placed there, so a relay is never reachable only by crawling.
func _crawl_features(rooms: Array, grid: Array, rng: SeededRandom) -> Array:
	var out := []
	for room_value in rooms:
		var room: Dictionary = room_value
		if room["kind"] == "overflow_chamber" or rng.next_float() >= CRAWL_CHANCE:
			continue
		var rect: Rect2i = room["rect"]
		var centre: Vector2i = room["center"]
		var dx := absi(centre.x - CENTER)
		var dz := absi(centre.y - CENTER)
		# the branch runs along x toward the north-south tunnel (dx <= dz) or along z; the pipe lies across its width
		var along_x := dx <= dz
		var step := Vector2i(1, 0) if (centre.x < CENTER) else Vector2i(-1, 0)
		if not along_x:
			step = Vector2i(0, 1) if centre.y < CENTER else Vector2i(0, -1)
		# first branch cell outside the room wall, then three cells further: well inside the passage
		var half := (rect.size.x - 1) / 2
		var pipe_cell := centre + step * (half + 3)
		var across := Vector2i(0, 1) if along_x else Vector2i(1, 0)
		if not (is_walkable(int(grid[pipe_cell.y][pipe_cell.x])) and int(grid[(pipe_cell + across).y][(pipe_cell + across).x]) == DRY \
				and int(grid[(pipe_cell - across).y][(pipe_cell - across).x]) == DRY \
				and int(grid[(pipe_cell + across * 2).y][(pipe_cell + across * 2).x]) == SOLID):
			continue
		var behind := []
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				behind.append(Vector2i(x, z))
		var k := 1
		while k <= half + 3:
			for w in range(-1, 2):
				behind.append(centre + step * k + across * w)
			k += 1
		var cells := [pipe_cell - across, pipe_cell, pipe_cell + across]
		# two 2 m mains, half a metre either side of the middle, cover the whole 3 m width
		for side in [-1, 1]:
			out.append({"type": "sewerPipeRun", "cell": pipe_cell, "wall": Vector2i.ZERO, "crawl": true,
				"yaw": PI / 2.0 if along_x else 0.0, "across": across, "side": side, "step": step,
				"cells": cells, "behind": behind})
		break
	return out


## The chunk's outflow main, or nothing: a walkway row at one of OUTFLOW_OFFSETS on one of the four arms and either
## walkway, all three cells dry with dry walkway either side along the arm, solid brick behind it (no doorway within a
## cell, so no branch, stairwell, ladder chamber or ramp opens at it), the channel in front of its mouth, and no
## other piece (lamps, wall mains, bridges) within a cell.
func _outflow_features(coord: Vector3i, grid: Array, features: Array, links: Array) -> Array:
	var rng := SeededRandom.new("%s:OUTFLOW:%d:%d:%d" % [world_seed, coord.x, coord.y, coord.z])
	if rng.next_float() >= OUTFLOW_CHANCE:
		return []
	var taken := {}
	for feature in features:
		StreamedRouteGenerator._exclude_neighbourhood(taken, feature["cell"], 1)
	for link in links:
		StreamedRouteGenerator._exclude_neighbourhood(taken, link["to_cell"], 2)
	var options := []
	for offset in OUTFLOW_OFFSETS:
		for along_x in [true, false]:
			for side in [-1, 1]:
				# the walkway row's outer, middle and channel-side cells, and the step toward the wall
				var wall: Vector2i = Vector2i(0, int(side)) if along_x else Vector2i(int(side), 0)
				var outer: int = CENTER + int(side) * TUNNEL_HALF
				var middle: Vector2i = Vector2i(int(offset), outer - int(side)) if along_x else Vector2i(outer - int(side), int(offset))
				options.append({"middle": middle, "wall": wall, "along": Vector2i(1, 0) if along_x else Vector2i(0, 1)})
	var start := rng.next_index(options.size())
	for k in options.size():
		var option: Dictionary = options[(start + k) % options.size()]
		var middle: Vector2i = option["middle"]
		var wall: Vector2i = option["wall"]
		var along: Vector2i = option["along"]
		var cells := [middle + wall, middle, middle - wall]
		var fits := int(grid[(middle - wall * 2).y][(middle - wall * 2).x]) == WATER
		for cell_value in cells:
			var cell: Vector2i = cell_value
			for a in [-1, 0, 1]:
				var c: Vector2i = cell + along * int(a)
				fits = fits and int(grid[c.y][c.x]) == DRY and not taken.has(c)
		for a in [-1, 0, 1]:
			var brick: Vector2i = middle + wall * 2 + along * int(a)
			fits = fits and int(grid[brick.y][brick.x]) == SOLID
		if fits:
			# its brick is two cells behind the middle one: "outflow_wall", not a wall-backed "wall"
			return [{"type": "sewerOutflowPipe", "cell": middle, "yaw": wall_yaw(wall), "outflow_wall": wall,
				"outflow": true, "cells": cells, "step": along}]
	return []


## The Axe (or the crowbar) breaks the sewer's pipes (docs/BREACH.md, KIND_PIPE, variant "authored": the view draws and removes the pipe
## itself). One spec per crawl pipe (its two mains) and per outflow main, in feature order so the ids are stable per seed.
## Each names its props (they carry "breakable_id") and the walkway cells its burst floods: dry floor within
## FLOOD_REACH steps of the pipe's cells, at most FLOOD_MAX_CELLS of them.
const PIPE_TOOLS := ["rescue_axe", "crowbar"]
const PIPE_HP := {"crawl": 3, "outflow": 4}
## The flood spreads (SewerFloods.reach_at) up to FLOOD_REACH steps over dry walkway, at most FLOOD_MAX_CELLS cells.
const FLOOD_REACH := 12
const FLOOD_MAX_CELLS := 160


func _pipe_breakables(coord: Vector3i, sewer_grid: Array, region_props: Array) -> Array:
	var out := []
	var by_cells := {}     # a crawl pipe's two mains share their cells: one spec for both
	for prop_value in region_props:
		var prop: Dictionary = prop_value
		var pipe := "outflow" if bool(prop.get("outflow", false)) else ("crawl" if bool(prop.get("crawl_under", false)) else "")
		if pipe.is_empty():
			continue
		var cells: Array = prop["occupied_cells"]
		var key := str(cells)
		if by_cells.has(key):
			var spec: Dictionary = out[int(by_cells[key])]
			(spec["extras"]["props"] as Array).append(prop["id"])
			prop["breakable_id"] = spec["id"]
			continue
		var middle: Vector2i = cells[cells.size() / 2]
		var along: Vector2i = prop["crawl_step"]
		var flood := _flood_cells(sewer_grid, cells)
		var id := Breach.make_id(coord, out.size())
		prop["breakable_id"] = id
		by_cells[key] = out.size()
		out.append(Breach.make_spec(id, Breach.KIND_PIPE, "authored", coord, middle, int(PIPE_HP[pipe]), PIPE_TOOLS, {
			"pipe": pipe, "props": [prop["id"]], "cells": cells.duplicate(),
			"centre": Vector2(middle) + Vector2(.5, .5), "dir": Vector2(along),
			"flood_cells": flood["cells"], "flood_steps": flood["steps"],
			"wall": Vector2(prop.get("outflow_wall", Vector2i.ZERO))}))
	return out


## The chunk's sluice gates: {id, cells (the channel cells it bridges when open), valve (its valve prop's id), prop}.
static func _gates(region_props: Array) -> Array:
	var out := []
	for prop_value in region_props:
		var prop: Dictionary = prop_value
		if String(prop.get("type", "")) != "sewerSluiceGate":
			continue
		var valve := ""
		for other in region_props:
			if String(other.get("type", "")) == "sewerValveWheel" and other.get("gate", "") == prop["gate"]:
				valve = String(other["id"])
		out.append({"id": prop["gate"], "cells": prop["gate_cells"], "valve": valve, "prop": prop["id"]})
	return out


## Dry walkway cells a burst pipe can flood: a walk outward from its cells over the bank's dry floor (no bridge deck),
## FLOOD_REACH steps,
## nearest first, at most FLOOD_MAX_CELLS (the pipe's own cells included): {cells, steps (each cell's step from the pipe)}.
static func _flood_cells(sewer_grid: Array, cells: Array) -> Dictionary:
	var seen := {}
	var queue := []
	for cell in cells:
		seen[cell] = 0
		queue.append(cell)
	var cursor := 0
	while cursor < queue.size() and queue.size() < FLOOD_MAX_CELLS:
		var cell: Vector2i = queue[cursor]
		cursor += 1
		if int(seen[cell]) >= FLOOD_REACH:
			continue
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + (step as Vector2i)
			if seen.has(next) or next.x < 0 or next.y < 0 or next.x >= CHUNK_SIZE or next.y >= CHUNK_SIZE:
				continue
			# the bank's own floor only: a bridge deck spans the channel, and the water drains into it there instead of
			# standing on the deck and running on to the far bank ("do not overflow")
			if int(sewer_grid[next.y][next.x]) != DRY:
				continue
			seen[next] = int(seen[cell]) + 1
			queue.append(next)
			if queue.size() >= FLOOD_MAX_CELLS:
				break
	return {"cells": queue, "steps": queue.map(func(c: Vector2i) -> int: return int(seen[c]))}


## Valve wheels (docs/SEWERS.md) do one of VALVE_EFFECTS: "flood" (shuts the chunk's running floods, else turns its pipes'
## drips off and on) or "gate" (opens a sluice across a channel). A chunk with pipes the Axe can burst always has a flood
## valve: a room's, or one on a tunnel wall clear of every other piece.
const VALVE_EFFECTS := ["flood", "gate"]
const TUNNEL_VALVE_OFFSETS := [4, 40, 16, 28]


func _flood_valve_features(grid: Array, features: Array, links: Array) -> Array:
	var has_pipe := features.any(func(f: Dictionary) -> bool: return f.has("crawl") or f.has("outflow"))
	var has_valve := features.any(func(f: Dictionary) -> bool:
		return String(f["type"]) == "sewerValveWheel" and String(f.get("valve_effect", "flood")) == "flood")
	if not has_pipe or has_valve:
		return []
	var taken := {}
	for feature in features:
		StreamedRouteGenerator._exclude_neighbourhood(taken, feature["cell"], 1)
		for cell in feature.get("cells", []):
			StreamedRouteGenerator._exclude_neighbourhood(taken, cell, 1)
	for link in links:
		StreamedRouteGenerator._exclude_neighbourhood(taken, link["to_cell"], 2)
	for offset in TUNNEL_VALVE_OFFSETS:
		for along_x in [true, false]:
			for side in [-1, 1]:
				var outer: int = CENTER + int(side) * TUNNEL_HALF
				var cell: Vector2i = Vector2i(int(offset), outer) if along_x else Vector2i(outer, int(offset))
				var wall: Vector2i = Vector2i(0, int(side)) if along_x else Vector2i(int(side), 0)
				if not taken.has(cell) and wall_backed(grid, cell, wall):
					return [{"type": "sewerValveWheel", "cell": cell, "wall": wall, "valve_effect": "flood"}]
	return []


## Sluice gates (a valve that opens a shortcut across a channel): a lifting leaf hinged on one walkway edge, raised
## (the channel stays uncrossable) until its gate valve is turned, then lowered flat across the three channel cells as a
## crossing. At most one per chunk on either sewer (GATE_CHANCE, own seed stream), out on an arm past its bridge
## (GATE_OFFSETS), with dry walkway at both ends, nothing within a cell, and its valve on the hinge side's outer wall.
## Open or shut the level stays connected (the bridges and the junction still cross); open, it is a shortcut for runners
## and hunters alike.
const GATE_CHANCE := .4
const GATE_OFFSETS := [5, 39]


func _gate_features(coord: Vector3i, grid: Array, features: Array, links: Array) -> Array:
	var rng := SeededRandom.new("%s:GATE:%d:%d:%d" % [world_seed, coord.x, coord.y, coord.z])
	if rng.next_float() >= GATE_CHANCE:
		return []
	var taken := {}
	for feature in features:
		StreamedRouteGenerator._exclude_neighbourhood(taken, feature["cell"], 1)
		for cell in feature.get("cells", []):
			StreamedRouteGenerator._exclude_neighbourhood(taken, cell, 1)
	for link in links:
		StreamedRouteGenerator._exclude_neighbourhood(taken, link["to_cell"], 2)
	var options := []
	for offset in GATE_OFFSETS:
		for along_x in [true, false]:
			for side in [-1, 1]:
				options.append([int(offset), along_x, int(side)])
	var start := rng.next_index(options.size())
	for k in options.size():
		var option: Array = options[(start + k) % options.size()]
		var offset: int = option[0]
		var along_x: bool = option[1]
		var side: int = option[2]
		# across the channel: from the hinge-side walkway (side) to the far one
		var across: Vector2i = Vector2i(0, side) if along_x else Vector2i(side, 0)
		var along: Vector2i = Vector2i(1, 0) if along_x else Vector2i(0, 1)
		var middle: Vector2i = Vector2i(offset, CENTER) if along_x else Vector2i(CENTER, offset)
		var cells := [middle - across, middle, middle + across]
		var hinge_end: Vector2i = middle + across * (CHANNEL_HALF + 1)
		var far_end: Vector2i = middle - across * (CHANNEL_HALF + 1)
		var fits := int(grid[hinge_end.y][hinge_end.x]) == DRY and int(grid[far_end.y][far_end.x]) == DRY
		for cell_value in cells + [hinge_end, far_end]:
			var c: Vector2i = cell_value
			fits = fits and not taken.has(c)
		for cell_value in cells:
			var c: Vector2i = cell_value
			fits = fits and int(grid[c.y][c.x]) == WATER
		if not fits:
			continue
		# its valve: on the hinge side's outer wall, a couple of cells along
		var outer: int = CENTER + side * TUNNEL_HALF
		for shift in [2, -2, 3, -3]:
			var spot: Vector2i = Vector2i(offset + int(shift), outer) if along_x else Vector2i(outer, offset + int(shift))
			if not taken.has(spot) and wall_backed(grid, spot, across):
				var gate_id := "GATE:%d:%d:%d:0" % [coord.x, coord.y, coord.z]
				return [
					{"type": "sewerSluiceGate", "cell": middle, "yaw": wall_yaw(across), "gate": gate_id, "gate_cells": cells,
						"along": along},
					{"type": "sewerValveWheel", "cell": spot, "wall": across, "valve_effect": "gate", "gate": gate_id},
				]
	return []


## Floor cells under a crawl pipe and one row either side of it: laid with the hazard plate so the low pipe reads from afar.
static func _crawl_stripe_cells(features: Array) -> Array:
	var cells := []
	for feature in features:
		if not feature.has("crawl") or int(feature["side"]) != -1:
			continue
		var step: Vector2i = feature["step"]
		for cell_value in feature["cells"]:
			for k in [-1, 0, 1]:
				cells.append((cell_value as Vector2i) + step * k)
	return cells


## Caged lamps far apart on the tunnels' outer walls, and pipe runs between them.
static func _tunnel_features() -> Array:
	var out := []
	for offset in [7, 37]:
		out.append({"type": "sewerLamp", "cell": Vector2i(offset, CENTER - TUNNEL_HALF), "wall": Vector2i(0, -1)})
		out.append({"type": "sewerLamp", "cell": Vector2i(CENTER + TUNNEL_HALF, offset), "wall": Vector2i(1, 0)})
	for offset in [14, 30]:
		out.append({"type": "sewerPipeRun", "cell": Vector2i(offset, CENTER + TUNNEL_HALF), "wall": Vector2i(0, 1)})
		out.append({"type": "sewerPipeRun", "cell": Vector2i(CENTER - TUNNEL_HALF, offset), "wall": Vector2i(-1, 0)})
	return out


## A room's lamp hangs at the MIDDLE of a wall. The planned wall can be the one a branch opens through (no brick there), where
## _mount_on_walls would slide the lamp two cells off centre; it moves to the middle of a room wall that is brick instead
## (GeometryAudit rule sewer_lamp_symmetry), preferring the planned one, then the walls not already carrying a piece.
static func _centre_room_lamps(grid: Array, rooms: Array, features: Array) -> Array:
	var out := []
	for feature_value in features:
		var feature: Dictionary = feature_value
		if String(feature.get("type", "")) != "sewerLamp":
			out.append(feature)
			continue
		var cell: Vector2i = feature["cell"]
		var room := {}
		for r in rooms:
			if (r["rect"] as Rect2i).has_point(cell):
				room = r
		if room.is_empty() or wall_backed(grid, cell, feature["wall"]):
			out.append(feature)
			continue
		var rect: Rect2i = room["rect"]
		var centre: Vector2i = room["center"]
		var used := {}
		for other_value in features:
			var other: Dictionary = other_value
			if other != feature and rect.has_point(other["cell"]):
				used[other["cell"]] = true
		var options := [[Vector2i(centre.x, rect.position.y), Vector2i(0, -1)], [Vector2i(centre.x, rect.end.y - 1), Vector2i(0, 1)],
			[Vector2i(rect.position.x, centre.y), Vector2i(-1, 0)], [Vector2i(rect.end.x - 1, centre.y), Vector2i(1, 0)]]
		var moved := feature
		for option in options:
			if not used.has(option[0]) and wall_backed(grid, option[0], option[1]):
				moved = feature.duplicate()
				moved["cell"] = option[0]
				moved["wall"] = option[1]
				break
		out.append(moved)
	return out


## Tunnel lamps come in mirror pairs about the chunk centre. A branch doorway can interrupt the wall under one of them, and
## sliding it alone left the pair uneven; both move inward by the same number of cells until both have brick behind them.
static func _pair_tunnel_lamps(grid: Array, features: Array) -> Array:
	var out := features.duplicate()
	for i in out.size():
		var lamp: Dictionary = out[i]
		if String(lamp.get("type", "")) != "sewerLamp":
			continue
		var wall: Vector2i = lamp["wall"]
		var cell: Vector2i = lamp["cell"]
		var along_x := wall.y != 0
		var a := cell.x if along_x else cell.y
		if a >= CENTER or absi((cell.y if along_x else cell.x) - CENTER) != TUNNEL_HALF:
			continue
		var mirror_cell := Vector2i(2 * CENTER - cell.x, cell.y) if along_x else Vector2i(cell.x, 2 * CENTER - cell.y)
		var j := -1
		for k in out.size():
			if out[k]["type"] == "sewerLamp" and out[k]["cell"] == mirror_cell and out[k]["wall"] == wall:
				j = k
		if j < 0:
			continue
		for s in range(0, 9):
			var left := cell + (Vector2i(s, 0) if along_x else Vector2i(0, s))
			var right := mirror_cell - (Vector2i(s, 0) if along_x else Vector2i(0, s))
			if wall_backed(grid, left, wall) and wall_backed(grid, right, wall):
				var moved_left: Dictionary = lamp.duplicate()
				moved_left["cell"] = left
				var moved_right: Dictionary = (out[j] as Dictionary).duplicate()
				moved_right["cell"] = right
				out[i] = moved_left
				out[j] = moved_right
				break
	return out


## Every wall-mounted piece (valves, lamps, pipe runs, pumps) must have brick
## behind it. Rooms, branches and shaft chambers carved after the dressing was
## planned can open a doorway exactly where a piece wanted its wall (playtest:
## a valve wheel hanging in mid-air in a pump-room doorway): such a piece slides
## along its wall to the nearest walkable cell that is backed by brick, or is
## left out when there is none within reach.
const MOUNT_SLIDE := 3


static func _mount_on_walls(grid: Array, features: Array) -> Array:
	var out := []
	for feature_value in features:
		var feature: Dictionary = feature_value
		var wall: Vector2i = feature.get("wall", Vector2i.ZERO)
		# free-standing pieces stay put, and so do ladders (their cell is the link)
		if wall == Vector2i.ZERO or feature.has("link"):
			out.append(feature)
			continue
		var cell: Vector2i = feature["cell"]
		var along := Vector2i(absi(wall.y), absi(wall.x))
		for k in [0, 1, -1, 2, -2, 3, -3]:
			if absi(k) > MOUNT_SLIDE:
				continue
			var spot: Vector2i = cell + along * k
			if wall_backed(grid, spot, wall):
				var moved := feature.duplicate()
				moved["cell"] = spot
				out.append(moved)
				break
	return out


## True when `cell` is walkable floor and the cell beyond it toward `wall` is brick.
static func wall_backed(grid: Array, cell: Vector2i, wall: Vector2i) -> bool:
	var back := cell + wall
	for c in [cell, back]:
		if c.x < 0 or c.y < 0 or c.x >= CHUNK_SIZE or c.y >= CHUNK_SIZE:
			return false
	return int(grid[cell.y][cell.x]) == DRY and int(grid[back.y][back.x]) == SOLID


## The decks: an authored bridge over the channel at each tunnel crossing and
## grate tiles over the confluence. "yaw" turns the span across the water
## (authored spanning local z, i.e. across an east-west channel).
static func _crossing_features() -> Array:
	var out := []
	for offset in BRIDGE_OFFSETS:
		out.append({"type": "sewerBridge", "cell": Vector2i(offset, CENTER), "yaw": 0.0})
		out.append({"type": "sewerBridge", "cell": Vector2i(CENTER, offset), "yaw": PI / 2.0})
	return out


## Wall-mounted height and whether a piece blocks movement; everything but the
## pump stands aside of the walkway or in the water.
const FEATURE_MOUNT_Y := {"sewerLamp": 2.35, "sewerValveWheel": 1.15, "sewerPipeRun": 2.55}
const SOLID_FEATURES := {"sewerPump": Vector3(1.3, 1.5, 0.9)}


## Yaw that turns an authored piece's back toward `wall` (PropModelCatalog adds
## the half turn authored models need).
static func wall_yaw(wall: Vector2i) -> float:
	if wall == Vector2i.ZERO:
		return 0.0
	return atan2(float(wall.x), float(wall.y))


func _feature_props(coord: Vector3i, features: Array) -> Array:
	var props := []
	for index in features.size():
		var feature: Dictionary = features[index]
		var type := String(feature["type"])
		var wall: Vector2i = feature.get("wall", Vector2i.ZERO)
		var prop := {"id": "%s:PROP:%d" % [chunk_id(coord), index], "type": type, "cell": feature["cell"],
			"yaw": float(feature.get("yaw", wall_yaw(wall))), "solid": SOLID_FEATURES.has(type), "sewer_feature": true}
		if feature.has("crawl"):
			var across: Vector2i = feature["across"]
			prop["solid"] = true
			prop["crawl_under"] = true
			prop["crawl_step"] = feature["step"]
			prop["crawl_side"] = feature["side"]
			prop["mount_y"] = CRAWL_PIPE_MOUNT_Y
			prop["collider_size"] = CRAWL_PIPE_SIZE
			prop["collider_y0"] = CRAWL_CLEARANCE
			prop["placement_offset"] = Vector2(across) * (.5 * float(feature["side"]))
			prop["occupied_cells"] = (feature["cells"] as Array).duplicate()
		elif feature.has("outflow"):
			# the main stands on its own (authored at its height): solid across its three cells, the box from the
			# crawl clearance up to its flanges' top
			prop["solid"] = true
			prop["outflow"] = true
			prop["outflow_wall"] = feature["outflow_wall"]
			prop["crawl_step"] = feature["step"]
			prop["collider_size"] = OUTFLOW_SIZE
			prop["collider_y0"] = CRAWL_CLEARANCE
			prop["occupied_cells"] = (feature["cells"] as Array).duplicate()
		elif FEATURE_MOUNT_Y.has(type):
			prop["mount_y"] = FEATURE_MOUNT_Y[type]
			prop["mount_offset"] = Vector2(wall) * .5
		elif type == "sewerPump":
			prop["mount_offset"] = Vector2(wall) * .05
		if SOLID_FEATURES.has(type) and not feature.has("crawl"):
			prop["collider_size"] = SOLID_FEATURES[type]
		if feature.has("link"):
			prop["link"] = feature["link"]
		if type == "sewerValveWheel":
			prop["valve_effect"] = String(feature.get("valve_effect", "flood"))
			if feature.has("gate"):
				prop["gate"] = feature["gate"]
		if type == "sewerSluiceGate":
			prop["solid"] = false
			prop["gate"] = feature["gate"]
			prop["gate_cells"] = (feature["gate_cells"] as Array).duplicate()
		props.append(prop)
	return props


static func is_walkable(code: int) -> bool:
	return code == DRY or code == BRIDGE


static func is_dry(code: int) -> bool:
	return code == DRY or code == BRIDGE
