class_name CityRouteGenerator
extends StreamedRouteGenerator

## The City as a chunk provider. The route code (hunters, brains, pickups, safe rooms, nav, multiplayer sync) only ever
## asks a generator for chunk dictionaries, so this subclass answers with slices of the one bounded CityLayout instead of
## the endless maze: 5 x 3 chunks (x -2..2, z -1..1) on level 0, everything else sealed. The dictionary has the same keys
## as the maze's (rooms, grid, safe_room, region_props, fixtures, pickups, hunter_spawns, ...), plus a `city` entry the
## City renderer reads (tile kinds, street furniture, buildings).

var layout: CityLayout


func _init(seed_text: String = "CITY") -> void:
	super(seed_text)
	layout = CityLayout.build(world_seed)


func is_chunk_allowed(coord: Vector3i) -> bool:
	return CityLayout.chunk_in_range(coord) and layout.chunk_has_open_cells(coord)


func biome_for(_coord: Vector3i) -> String:
	return "city"


## A shelter (the 9 x 9 kiosk on every chunk centre that has one) is the city's safe room; chunk (0,0) is the spawn one.
func is_safe_room(coord: Vector3i) -> bool:
	return not layout.shelter_for_chunk(coord).is_empty()


## True when a route-space position (route cell units) is inside a building: used by hunters' daytime sight, which only
## applies outdoors.
func is_indoor_route_position(position: Vector2) -> bool:
	var kind := layout.kind_at(floori(position.x) + CityLayout.ORIGIN_OFFSET.x, floori(position.y) + CityLayout.ORIGIN_OFFSET.y)
	return kind == CityLayout.FLOOR or kind == CityLayout.DOOR or kind == CityLayout.KIOSK_FLOOR


func edge_openings(coord: Vector3i, direction: Vector2i) -> Array:
	var neighbour := coord + Vector3i(direction.x, 0, direction.y)
	if not is_chunk_allowed(coord) or not is_chunk_allowed(neighbour):
		return []
	var origin := CityLayout.chunk_origin(coord)
	var out := []
	for index in CHUNK_SIZE:
		var own := Vector2i(origin.x + index, origin.y + CHUNK_SIZE - 1)
		if direction.x < 0:
			own = Vector2i(origin.x, origin.y + index)
		elif direction.x > 0:
			own = Vector2i(origin.x + CHUNK_SIZE - 1, origin.y + index)
		elif direction.y < 0:
			own = Vector2i(origin.x + index, origin.y)
		if layout.is_open(own.x, own.y) and layout.is_open(own.x + direction.x, own.y + direction.y):
			out.append(index)
	return out


func _build_chunk(coord: Vector3i) -> Dictionary:
	if not is_chunk_allowed(coord):
		return {"schema": 2, "coord": coord, "chunk_id": chunk_id(coord),
			"biome": "sealed", "region": "sealed", "rooms": [], "corridors": [], "suites": [],
			"grid": _solid_grid(), "edges": {"west": [], "east": [], "north": [], "south": []},
			"stairs": [], "safe_room": false, "safe_room_data": {}, "region_props": [], "fixtures": [],
			"pickups": [], "hunter_spawns": [], "dual_level_room": {}, "floor_voids": [], "ceiling_voids": [],
			"structural_voids": [], "difficulty": difficulty_for_level(coord.y)}
	var grid := layout.chunk_grid(coord)
	var origin := CityLayout.chunk_origin(coord)
	var chunk_rect := Rect2i(origin, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
	var rooms := []
	var region_props := []
	var buildings := []
	for building in layout.buildings_in_chunk(coord):
		if bool(building.get("sealed", false)):
			continue
		var rect: Rect2i = building["rect"]
		var interior: Rect2i = building["interior"]
		# One cell is kept off every chunk border: the route's fixture placement looks at the cell behind a wall.
		var local_interior := interior.intersection(chunk_rect.grow(-1))
		buildings.append({"id": building["id"], "rect": Rect2i(rect.position - origin, rect.size),
			"kind": building["kind"], "height": building["height"], "style": building["style"],
			"doors": (building["doors"] as Array).map(func(door: Vector2i) -> Vector2i: return door - origin)})
		if local_interior.size.x >= 3 and local_interior.size.y >= 3:
			rooms.append({"id": "%s:%s" % [chunk_id(coord), building["id"]],
				"rect": Rect2i(local_interior.position - origin, local_interior.size),
				"room_type": String(building["kind"]), "kind": String(building["kind"]),
				"center": local_interior.position - origin + local_interior.size / 2})
		for prop in layout.building_props(building):
			var cell: Vector2i = prop["cell"]
			if not chunk_rect.has_point(cell):
				continue
			var type := String(prop["type"])
			if not PropModelCatalog.has_model(type):
				continue
			var local := cell - origin
			region_props.append({"id": "%s:CITYPROP:%s" % [chunk_id(coord), prop["id"]], "type": type,
				"cell": local, "yaw": float(prop["yaw"]), "blocker_size": prop["size"], "solid": true,
				"room_id": String(prop["room_id"]), "region": "city", "occupied_cells": [local]})
	var safe := is_safe_room(coord)
	var fixtures := _fixtures(coord, grid, rooms, [], region_props, safe)
	var pickups := _pickups(coord, grid, [], safe, region_props, fixtures)
	var hunters := _hunter_spawns(coord, grid, [], safe, region_props)
	# The dome gate (the escape objective) is one extra pickup entity in the chunk that holds its interaction cell.
	var gate_local := CityLayout.GATE_CELL - origin
	if gate_local.x >= 0 and gate_local.y >= 0 and gate_local.x < CHUNK_SIZE and gate_local.y < CHUNK_SIZE:
		pickups.append({"id": "%s:PICKUP:GATE:0" % chunk_id(coord), "cell": gate_local, "kind": "gate", "item": ""})
	var shelter := layout.shelter_for_chunk(coord)
	var shelter_local := {}
	if not shelter.is_empty():
		var shelter_rect: Rect2i = shelter["rect"]
		shelter_local = {"id": shelter["id"], "rect": Rect2i(shelter_rect.position - origin, shelter_rect.size),
			"doors": (shelter["doors"] as Array).map(func(door: Vector2i) -> Vector2i: return door - origin)}
	return {
		"schema": 2,
		"coord": coord,
		"chunk_id": chunk_id(coord),
		"biome": "city",
		"region": "city",
		"rooms": rooms,
		"corridors": [],
		"suites": [],
		"difficulty": difficulty_for_level(coord.y),
		"grid": grid,
		"edges": {
			"west": edge_openings(coord, Vector2i(-1, 0)), "east": edge_openings(coord, Vector2i(1, 0)),
			"north": edge_openings(coord, Vector2i(0, -1)), "south": edge_openings(coord, Vector2i(0, 1)),
		},
		"stairs": [],
		"safe_room": safe,
		"safe_room_data": safe_room_data(coord) if safe else {},
		"region_props": region_props,
		"fixtures": fixtures,
		"pickups": pickups,
		"hunter_spawns": hunters,
		"dual_level_room": {},
		"floor_voids": [],
		"ceiling_voids": [],
		"structural_voids": [],
		"city": {"kinds": layout.chunk_kinds(coord), "decor": layout.chunk_decor(coord), "buildings": buildings,
			"shelter": shelter_local},
	}
