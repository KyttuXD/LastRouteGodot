extends RefCounted

## The Mezzanine (+1) in a real streamed view: the stairwell up from the maze lands on a deck, the catwalk grating and decks
## carry floor colliders while the air between has none, every drop is railed, the stairs belong to the upper chunk, the
## maze below keeps no ceiling under the grating, and the view tracks level +1 (docs/UPPER_LEVELS.md).
##
##   godot --headless --path . res://scenes/validate.tscn -- mezzanine_view

const SEEDS := ["UPPER-A", "UPPER-B", "KYTTU-LAB"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_expect(StreamedFacilityView3D.snapped_level_for_world_y(StreamedFacilityView3D.LEVEL_HEIGHT) == StreamedRouteGenerator.MEZZANINE_LEVEL,
		"a runner standing on the Mezzanine floor is not on level +1")
	_expect(StreamedFacilityView3D.snapped_level_for_world_y(StreamedFacilityView3D.LEVEL_HEIGHT * 3.0) == StreamedRouteGenerator.MEZZANINE_LEVEL,
		"the level clamp lets the view climb past the Mezzanine")
	var checked := 0
	for seed_text in SEEDS:
		checked += await _check_seed(host, seed_text)
	_expect(checked > 0, "no stairwell up to the Mezzanine found to build a view around")
	if _failures == 0:
		print("  mezzanine_view  %d mezzanine chunks built: floors only on catwalk and deck, railed drops, stairs owned by +1, maze ceiling open under grating" % checked)
	return _failures


func _check_seed(host: Node, seed_text: String) -> int:
	var generator := StreamedRouteGenerator.new(seed_text)
	var column := Vector2i(999999, 999999)
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			if column.x == 999999 and not generator.stairwell_between(dx, dz, StreamedRouteGenerator.MEZZANINE_LEVEL).is_empty():
				column = Vector2i(dx, dz)
	if column.x == 999999:
		return 0
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var well := generator.stairwell_between(column.x, column.y, StreamedRouteGenerator.MEZZANINE_LEVEL)
	var landing: Vector2i = well["landing"]
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.global_position = Vector3(column.x * size + landing.x + .5, StreamedFacilityView3D.LEVEL_HEIGHT + .1, column.y * size + landing.y + .5)
	view.begin(seed_text, player)
	var coord := Vector3i(column.x, StreamedRouteGenerator.MEZZANINE_LEVEL, column.y)
	var root: Node3D = view._loaded.get(coord)
	var built := root != null
	_expect(root != null, "%s: the Mezzanine chunk %s is not loaded" % [seed_text, coord])
	if root != null:
		var data := generator.chunk(coord)
		var structure := root.get_node("Structure") as GridMap
		var mezz: Array = data["mezzanine_grid"]
		var floors := 0
		var air_with_collider := 0
		for z in size:
			for x in size:
				var item := structure.get_cell_item(Vector3i(x, 0, z))
				if MezzanineRouteGenerator.is_walkable(int(mezz[z][x])):
					floors += 1
					_expect(item != GridMap.INVALID_CELL_ITEM, "%s: catwalk cell %s has no floor collider" % [seed_text, Vector2i(x, z)])
				elif item != GridMap.INVALID_CELL_ITEM:
					air_with_collider += 1
		_expect(floors > 100, "%s: only %d walkable Mezzanine cells" % [seed_text, floors])
		_expect(air_with_collider == 0, "%s: %d open-air cells carry a collider" % [seed_text, air_with_collider])
		var rails := root.get_node_or_null("CatwalkRails") as StaticBody3D
		_expect(rails != null and rails.get_child_count() > 0, "%s: the Mezzanine chunk has no railings" % seed_text)
		var rail_features := 0
		for feature in data["features"]:
			rail_features += 1 if feature["type"] == "catwalkRail" else 0
		if rails != null:
			_expect(rails.get_child_count() == rail_features, "%s: %d rail colliders for %d rail segments" % [seed_text, rails.get_child_count(), rail_features])
		_expect(root.get_node_or_null("Stairwell_%s" % well["kind"]) != null, "%s: the stairs are not built with the upper chunk" % seed_text)
		_expect(view.current_level() == StreamedRouteGenerator.MEZZANINE_LEVEL, "%s: the view does not track level +1 on the deck" % seed_text)
		_expect(view._loaded.has(Vector3i(column.x, 0, column.y)), "%s: the maze under the Mezzanine is not loaded" % seed_text)
	view.clear()
	view.queue_free()
	player.queue_free()
	await host.get_tree().process_frame
	return 1 if built else 0
