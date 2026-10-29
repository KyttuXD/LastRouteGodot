extends SceneTree

## Furniture placement audit over real generated chunks (every district, several seeds):
## solid-prop footprint overlaps, props crowding a doorway, rooms whose floor the doorway cannot reach once props are
## placed, chairs with no table near them or not facing one.
##   godot --headless --path . -s tools/look/furniture_audit.gd -- [SEEDS_CSV]

const CHAIR_WORDS := ["Chair", "Stool"]
const TABLE_WORDS := ["Table", "Desk"]


func _is(type: String, words: Array) -> bool:
	for w in words:
		if type.contains(w):
			return true
	return false


func _init() -> void:
	var seeds := ["AUDIT-A", "AUDIT-B", "AUDIT-C"]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = Array(args[0].split(","))
	var totals := {"chunks": 0, "rooms": 0, "props": 0, "chairs": 0, "tables": 0, "overlaps": 0, "door_crowded": 0,
		"blocked_rooms": 0, "pockets": 0, "stray_chairs": 0, "bad_facing": 0}
	var samples := {}
	var per_region := {}
	for seed_text in seeds:
		var generator := StreamedRouteGenerator.new(String(seed_text))
		var visited := {}
		for r in range(0, 10):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var coord := Vector3i(dx, 0, dz)
					if not generator.is_chunk_allowed(coord):
						continue
					var region := generator.region_for(coord)
					per_region[region] = int(per_region.get(region, 0)) + 1
					if int(per_region[region]) > 14:
						continue
					_audit_chunk(generator, coord, region, totals, samples)
	print("FURNITURE AUDIT  ", totals)
	for key in samples:
		print("  %s: %s" % [key, samples[key]])
	quit()


func _audit_chunk(generator: StreamedRouteGenerator, coord: Vector3i, region: String, totals: Dictionary, samples: Dictionary) -> void:
	var data := generator.chunk(coord)
	totals["chunks"] += 1
	var grid: Array = data.get("grid", [])
	var props: Array = data.get("region_props", [])
	var solid_cells := {}
	var solids := []
	for prop_value in props:
		var prop: Dictionary = prop_value
		if not bool(prop.get("solid", true)) or bool(prop.get("room_door", false)):
			continue
		var occupied: Array = prop.get("occupied_cells", [])
		if occupied.is_empty():
			occupied = [prop.get("cell", Vector2i.ZERO)]
		solids.append(prop)
		totals["props"] += 1
		var type := String(prop.get("type", ""))
		if _is(type, CHAIR_WORDS):
			totals["chairs"] += 1
		if _is(type, TABLE_WORDS):
			totals["tables"] += 1
		for c_value in occupied:
			var c: Vector2i = c_value
			if solid_cells.has(c) and solid_cells[c] != prop:
				totals["overlaps"] += 1
				_sample(samples, "overlap", "%s %s %s vs %s at %s" % [region, coord, type, String(solid_cells[c].get("type", "")), c])
			solid_cells[c] = prop
	# chair / table relations
	for prop in solids:
		var type := String(prop.get("type", ""))
		if not _is(type, CHAIR_WORDS):
			continue
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		var best := INF
		var best_table: Dictionary = {}
		for other in solids:
			if _is(String(other.get("type", "")), TABLE_WORDS):
				var d := Vector2(cell).distance_to(Vector2(other.get("cell", Vector2i.ZERO)))
				if d < best:
					best = d
					best_table = other
		if best > 3.0:
			totals["stray_chairs"] += 1
			_sample(samples, "stray_chair", "%s %s %s (nearest table %.1f)" % [region, coord, type, best])
		else:
			var target = prop.get("facing_target", cell)
			var to_table := Vector2(best_table.get("cell", Vector2i.ZERO)) - Vector2(cell)
			var facing := Vector2(target) - Vector2(cell) if target is Vector2i else Vector2.ZERO
			if to_table.length() > 0.1 and facing.length() > 0.1 and facing.normalized().dot(to_table.normalized()) < 0.3:
				totals["bad_facing"] += 1
				_sample(samples, "bad_facing", "%s %s %s faces %s, table at %s" % [region, coord, type, facing, to_table])
	# rooms: doorway crowding and reachability
	for room_value in data.get("rooms", []):
		var room: Dictionary = room_value
		totals["rooms"] += 1
		var rect: Rect2i = room.get("rect", Rect2i())
		var doorway = room.get("doorway")
		if not doorway is Vector2i or rect.size.x < 3:
			continue
		var door: Vector2i = doorway
		var crowded := false
		for c in solid_cells:
			var cc: Vector2i = c
			if maxi(absi(cc.x - door.x), absi(cc.y - door.y)) <= 1:
				crowded = true
		if crowded:
			totals["door_crowded"] += 1
			_sample(samples, "door_crowded", "%s %s room %s door %s" % [region, coord, rect, door])
		# flood from the doorway through open, non-prop cells
		var open := {}
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2i(x, z)
				if z >= 0 and z < grid.size() and x >= 0 and x < (grid[z] as Array).size() \
						and int(grid[z][x]) == 0 and not solid_cells.has(c):
					open[c] = true
		var start := door
		if not open.has(start):
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if open.has(door + d):
					start = door + d
					break
		if not open.has(start):
			totals["blocked_rooms"] += 1
			_sample(samples, "blocked_room", "%s %s room %s door %s" % [region, coord, rect, door])
			continue
		var seen := {start: true}
		var frontier := [start]
		while not frontier.is_empty():
			var cur: Vector2i = frontier.pop_back()
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var n: Vector2i = cur + d
				if open.has(n) and not seen.has(n):
					seen[n] = true
					frontier.append(n)
		var cut_off := open.size() - seen.size()
		if cut_off >= 4:
			totals["pockets"] += 1
			_sample(samples, "pocket", "%s %s room %s cut-off cells %d" % [region, coord, rect, cut_off])


func _sample(samples: Dictionary, key: String, text: String) -> void:
	var list: Array = samples.get(key, [])
	if list.size() < 4:
		list.append(text)
	samples[key] = list
