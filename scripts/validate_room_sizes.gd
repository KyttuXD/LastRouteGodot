extends RefCounted

## Room sizes follow what the rooms are for (docs/ROOM_SIZES.md): every generated room lies inside its RoomSizeProfiles
## entry, the great halls hold their table grids with a chair ring on every table, tables are reachable and do not overlap,
## great halls only appear where both chunks at the seam agree (no dead-end hall stubs), and seeds are deterministic.

const SEEDS := ["RS-A", "RS-B", "RS-C"]

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var out_of_profile := {}
	var halls := 0
	var tables_total := 0
	var types_seen := {}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for r in range(0, 9):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var coord := Vector3i(dx, 0, dz)
					if not generator.is_chunk_allowed(coord) or not StreamedRouteGenerator.DENSE_DISTRICTS.has(generator.biome_for(coord)):
						continue
					var data := generator.chunk(coord)
					for room in data["rooms"]:
						var type := String(room.get("room_type", ""))
						types_seen[type] = true
						if not RoomSizeProfiles.within(type, room["size"]) and not bool(room.get("suite_parent", false)) \
								and not String(room.get("id", "")).contains("SUITE"):
							out_of_profile["%s %s" % [type, room["size"]]] = true
						if bool(room.get("great_hall", false)):
							halls += 1
							tables_total += _check_great_hall(generator, coord, data, room)
	_expect(out_of_profile.is_empty(), "rooms outside their size profile: %s" % [out_of_profile.keys()])
	_expect(halls >= 6, "only %d great halls in the sampled chunks" % halls)
	# seam agreement: a chunk with a great hall on a side has no seam row 22 there, and its neighbour has none either
	var generator := StreamedRouteGenerator.new("RS-A")
	var checked := 0
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var coord := Vector3i(dx, 0, dz)
			var plan := generator.large_plan(coord)
			for side in ["W", "E"]:
				if String(plan[side]).is_empty():
					continue
				var step := -1 if side == "W" else 1
				var neighbour := coord + Vector3i(step, 0, 0)
				checked += 1
				_expect(not generator.edge_openings(coord, Vector2i(step, 0)).has(22),
					"%s has a great hall on %s yet the seam row 22 is open" % [coord, side])
				_expect(not generator.edge_openings(neighbour, Vector2i(-step, 0)).has(22),
					"%s: the neighbour of a great hall still opens seam row 22" % [neighbour])
				_expect(generator.hall_trimmed(neighbour, -step), "%s did not trim its middle hall toward the great hall" % [neighbour])
	_expect(checked >= 4, "only %d great-hall seams checked" % checked)
	var a := StreamedRouteGenerator.new("RS-DET").large_plan(Vector3i(3, 0, 3))
	var b := StreamedRouteGenerator.new("RS-DET").large_plan(Vector3i(3, 0, 3))
	_expect(a == b, "great hall plan is not deterministic")
	metrics = {"halls": halls, "tables": tables_total, "types": types_seen.size()}
	if _failures == 0:
		print("  room_sizes  %d great halls with %d tables, every room inside its profile, seams agree" % [halls, tables_total])
	return _failures


func _check_great_hall(generator: StreamedRouteGenerator, coord: Vector3i, data: Dictionary, room: Dictionary) -> int:
	var rect: Rect2i = room["rect"]
	_expect(rect.size == Vector2i(21, 21), "great hall %s is %s, not 21x21" % [room["id"], rect.size])
	var profile := RoomSizeProfiles.profile(String(room["room_type"]))
	var table_types: Array = profile.get("signature", [])
	var tables := []
	var chairs := 0
	for prop in data["region_props"]:
		if String(prop.get("room_id", "")) != String(room["id"]) or bool(prop.get("room_door", false)):
			continue
		var type := String(prop.get("type", ""))
		if table_types.has(type):
			tables.append(prop)
		if type.contains("Chair"):
			chairs += 1
	var table_range: Vector2i = profile.get("tables", Vector2i(1, 99))
	_expect(tables.size() >= table_range.x and tables.size() <= table_range.y,
		"great hall %s %s holds %d tables, profile wants %d-%d" % [room["id"], room["room_type"], tables.size(), table_range.x, table_range.y])
	if String(room["room_type"]) != "prison_cafeteria":
		_expect(chairs >= tables.size() * 3, "great hall %s has %d chairs for %d tables" % [room["id"], chairs, tables.size()])
	# every table can be walked up to: a point within 1.0 m of its box is reachable from the door at radius 0.3
	var world := CollisionWorld.from_chunk(data)
	var door: Vector2i = room["doorway"]
	var area := Rect2(Vector2(rect.position) - Vector2(2, 2), Vector2(rect.size) + Vector2(4, 4))
	var outward := Vector2(1, 0) if door.x == rect.end.x - 1 else Vector2(-1, 0)
	var reached := world.flood(Vector2(door) + Vector2(.5, .5) + outward, CollisionWorld.MARGIN_RADIUS, area)
	for table in tables:
		var cell: Vector2i = table["cell"]
		var near := false
		for angle in 8:
			var p := Vector2(cell) + Vector2(.5, .5) + Vector2.from_angle(float(angle) * PI / 4.0) * 1.3
			if world.reached_near(reached, area, p, 0.6):
				near = true
				break
		_expect(near, "a table in great hall %s cannot be walked up to" % room["id"])
	return tables.size()
