extends RefCounted

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var world := StreamedRouteGenerator.new("STREAM-CHECK")
	var coords := [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-3, 1, 4)]
	for coord in coords:
		_expect(world.chunk(coord) == world.chunk(coord),
			"chunk %s does not regenerate identically" % coord)

	for z in range(-3, 4):
		for x in range(-3, 4):
			var at := Vector3i(x, 0, z)
			_expect(world.edge_openings(at, Vector2i(1, 0)) \
				== world.edge_openings(at + Vector3i(1, 0, 0), Vector2i(-1, 0)),
				"east/west seam disagrees at %s" % at)
			_expect(world.edge_openings(at, Vector2i(0, 1)) \
				== world.edge_openings(at + Vector3i(0, 0, 1), Vector2i(0, -1)),
				"north/south seam disagrees at %s" % at)

	var lower := world.chunk(Vector3i.ZERO)
	var upper := world.chunk(Vector3i(0, 1, 0))
	var lower_link: Dictionary = lower["stairs"][0]
	var matching := false
	for link in upper["stairs"]:
		if link["id"] == lower_link["id"] and link["cell"] == lower_link["cell"] \
				and link["style"] == lower_link["style"]:
			matching = true
	_expect(matching, "the forced origin stair does not agree across vertical chunks")
	_expect(lower_link["direction"] == "up", "lower vertical link is not an up stair")
	_expect(world.is_safe_room(Vector3i.ZERO), "origin chunk is not a temporary safe room")

	var biomes := {}
	var pickup_ids := {}
	for z in range(-8, 9):
		for x in range(-8, 9):
			var data := world.chunk(Vector3i(x, 0, z))
			biomes[data["biome"]] = true
			for pickup in data["pickups"]:
				_expect(not pickup_ids.has(pickup["id"]),
					"duplicate streamed pickup id %s" % pickup["id"])
				pickup_ids[pickup["id"]] = true
	_expect(biomes.size() == StreamedRouteGenerator.BIOMES.size(),
		"seeded sample did not produce every biome: %s" % [biomes.keys()])
	_expect(not pickup_ids.is_empty(), "streamed chunks produced no collectible ids")
	var active := world.coordinates_around(Vector2(17.0, -1.0), 2, 2)
	_expect(active.size() == 25 and active.has(Vector3i(1, 2, -1)),
		"stream radius did not produce the expected 5x5 active set")

	if _failures == 0:
		print("  chunks    deterministic topology, canonical seams and stable pickup ids")
		print("  vertical  shared stair links connect level chunks; origin is a safe room")
		print("  biomes    maze, mansion, hotel and apartment regions all reachable")
		print("streamed_world OK")
	return _failures
