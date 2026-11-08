extends RefCounted

## "yeah lets fix that" (a co-op bot stuck in a carnival booth doorway: walkable by physics, blocked for the hunters'
## navigation). Walkability and navigation agree, over many generated chunks:
## - every cell a solid prop reserves where a runner can stand and get to (clear of every collider by the 0.3 m walkway
##   margin, flood-filled from open floor) is
##   either open to the navigation or resolves to an open cell nearby (the navigation's own two-ring fallback), so a
##   hunter or bot standing there can always path off it;
## - a reserved cell whose centre its prop's collider leaves clear (the open corner of an L desk) is open to the
##   navigation;
## - a solid prop low enough to walk onto (StreamedHunterNavigation.WALK_ON_HEIGHT) is floor to the navigation.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- nav_walkable

const SEEDS := ["NAV-A", "NAV-B", "LIVEMIX", "ENDLESS-ROUTE"]
## A spot counts as standable with the walk-through margin the other walkway checks use (PlacementClearance,
## CollisionWorld.MARGIN_RADIUS), not the bare 0.2 m capsule: a sliver the runner can only squeeze into sideways is not floor.
const RADIUS := CollisionWorld.MARGIN_RADIUS
const SAMPLES := [.25, .5, .75]
## The runner's reachable floor is flood-filled on a 0.25 m lattice of points clear of every collider and wall.
const STEP_INV := 4.0

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var reserved := 0
	var standable := 0
	var stuck := {}
	var unreached := {}
	var low := {}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for level in [0, 1]:
			for dz in range(-4, 5):
				for dx in range(-4, 5):
					var coord := Vector3i(dx, level, dz)
					if not generator.is_chunk_allowed(coord):
						continue
					var data := generator.chunk(coord)
					if bool(data.get("safe_room", false)):
						continue
					var nav := StreamedHunterNavigation.new(generator, level)
					nav.refresh(level, [coord])
					var base := Vector2i(coord.x, coord.z) * StreamedRouteGenerator.CHUNK_SIZE
					var grid: Array = data.get("grid", [])
					var solids := []
					for prop_value in data.get("region_props", []):
						var prop: Dictionary = prop_value
						if not bool(prop.get("solid", true)) or bool(prop.get("room_door", false)) or float(prop.get("collider_y0", 0.0)) > 0.0:
							continue
						solids.append(prop)
					var all_rects := []
					for prop in solids:
						if not StreamedHunterNavigation.blocks_nothing(prop):
							all_rects.append_array(StreamedHunterNavigation.collider_plan_rects(prop, RADIUS))
					var reach := _reachable(grid, all_rects, nav, base)
					for prop in solids:
						var type := String(prop.get("type", ""))
						var occupied: Array = prop.get("occupied_cells", [])
						if StreamedHunterNavigation.blocks_nothing(prop):
							for cell_value in occupied:
								if not nav.is_floor(base.x + (cell_value as Vector2i).x + .5, base.y + (cell_value as Vector2i).y + .5) \
										and _open(grid, cell_value):
									low[type] = int(low.get(type, 0)) + 1
							continue
						var own := StreamedHunterNavigation.collider_plan_rects(prop, RADIUS)
						for cell_value in occupied:
							var cell: Vector2i = cell_value
							if not _open(grid, cell):
								continue
							reserved += 1
							var world := base + cell
							var cell_rect := Rect2(Vector2(cell), Vector2.ONE)
							var centre := Vector2(cell) + Vector2(.5, .5)
							var own_nav := StreamedHunterNavigation.collider_plan_rects(prop, StreamedHunterNavigation.NAV_RADIUS)
							if not own_nav.any(func(r: Rect2) -> bool: return r.has_point(centre)) and not nav.is_floor(world.x + .5, world.y + .5):
								unreached[type] = int(unreached.get(type, 0)) + 1
							var can_stand := false
							for sx in SAMPLES:
								for sz in SAMPLES:
									var p := Vector2(cell) + Vector2(sx, sz)
									# standable and walkable to: a free spot the runner reaches from open floor (a cage's
									# sealed interior does not count)
									if reach.has(Vector2i(floori(p.x * STEP_INV), floori(p.y * STEP_INV))):
										can_stand = true
							if not can_stand:
								continue
							standable += 1
							if nav.is_floor(world.x + .5, world.y + .5):
								continue
							# what find_path does from here: the nearest roomy cell (two rings), then a real path out of it
							var off: Vector2i = nav._roomy_cell(world)
							if off.x == StreamedHunterNavigation.INVALID_CELL:
								stuck["%s %s" % [type, world]] = true
	_beta_cafeteria()
	_expect(reserved > 5000, "only %d reserved prop cells in the sample" % reserved)
	_expect(unreached.is_empty(), "navigation blocks cells their prop's collider never reaches: %s" % [unreached])
	_expect(low.is_empty(), "navigation blocks props low enough to walk onto: %s" % [low])
	_expect(stuck.is_empty(), "%d standable prop cells have no open cell nearby to path off from: %s" % [stuck.size(), stuck.keys().slice(0, 8)])
	metrics = {"reserved_cells": reserved, "standable": standable}
	if _failures == 0:
		print("  nav_walkable  %s" % [metrics])
	return _failures


## seed BETA, chunk (-1, 0, -3), the small prison cafeteria (room 2, relay at local (17, 2)). A tray return, a
## table and a kitchen rack stand wall to wall across the room with 0.45-0.49 m slots between them (the runner's capsule
## is 0.5 m) over cells the props do not reserve: the navigation called those slots open, so bots south of the row
## walked into one for good 4 m short of the relay. The slots are solid to the navigation now, and the path from the
## south half to the relay goes round the west end (the 0.98 m gap by the wall).
func _beta_cafeteria() -> void:
	# the run's world seed is the hash of the typed seed (RoomState.run_seed)
	var generator := StreamedRouteGenerator.new(str(maxi(1, absi(int("BETA".hash())))))
	var coord := Vector3i(-1, 0, -3)
	var data := generator.chunk(coord)
	var types := {}
	for prop in data.get("region_props", []):
		if String(prop.get("room_id", "")) == "-1:0:-3:ROOM:2":
			types[String(prop.get("type", ""))] = Vector2i(prop.get("cell", Vector2i.ZERO))
	if types.get("prisonCafeteriaTable") != Vector2i(15, 5) or types.get("prisonKitchenRack") != Vector2i(18, 5) \
			or types.get("prisonTrayReturn") != Vector2i(12, 5):
		print("  note  nav_walkable: BETA cafeteria layout changed (%s), pinned 084 case skipped" % [types])
		return
	var nav := StreamedHunterNavigation.new(generator, 0)
	nav.refresh(0, [coord])
	var base := Vector2i(coord.x, coord.z) * StreamedRouteGenerator.CHUNK_SIZE
	for slot in [Vector2i(13, 5), Vector2i(17, 5), Vector2i(19, 5)]:
		_expect(not nav.is_floor(base.x + slot.x + .5, base.y + slot.y + .5),
			"084: BETA cafeteria slot %s (narrower than the runner) is open to the navigation" % [slot])
	var path := nav.find_path(base + Vector2i(18, 7), base + Vector2i(17, 2))
	_expect(not path.is_empty(), "084: no path from the south half of BETA's cafeteria to its relay")
	for cell in path:
		var local: Vector2i = (cell as Vector2i) - base
		_expect(local.y != 5 or local.x <= 11,
			"084: the path to BETA's cafeteria relay crosses the table row at %s, not round its west end" % [local])


## Lattice points (0.25 m) a runner reaches: clear of every grown collider and on open grid, flood-filled from the centres
## of the cells the navigation calls open.
static func _reachable(grid: Array, rects: Array, nav: StreamedHunterNavigation, base: Vector2i) -> Dictionary:
	var size := StreamedRouteGenerator.CHUNK_SIZE * int(STEP_INV)
	var free := func(k: Vector2i) -> bool:
		var p := (Vector2(k) + Vector2(.5, .5)) / STEP_INV
		return _open(grid, Vector2i(floori(p.x), floori(p.y))) and not rects.any(func(r: Rect2) -> bool: return r.has_point(p))
	var seen := {}
	var frontier := []
	for z in StreamedRouteGenerator.CHUNK_SIZE:
		for x in StreamedRouteGenerator.CHUNK_SIZE:
			if _open(grid, Vector2i(x, z)) and nav.is_floor(base.x + x + .5, base.y + z + .5):
				var k := Vector2i(x * int(STEP_INV) + 2, z * int(STEP_INV) + 2)
				if not seen.has(k) and free.call(k):
					seen[k] = true
					frontier.append(k)
	while not frontier.is_empty():
		var k: Vector2i = frontier.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + d
			if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size or seen.has(n):
				continue
			if free.call(n):
				seen[n] = true
				frontier.append(n)
	return seen


static func _open(grid: Array, cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < grid.size() and cell.x >= 0 and cell.x < (grid[cell.y] as Array).size() and int(grid[cell.y][cell.x]) == 0
