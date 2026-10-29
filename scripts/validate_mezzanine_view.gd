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
	_expect(checked > 0, "no void tower built")
	if _failures == 0:
		print("  mezzanine_view  %d void chunks built across levels -3..+1: floors only on ledges, catwalks, decks and the pit, railed drops, the stair tower" % checked)
	return _failures


func _check_seed(host: Node, seed_text: String) -> int:
	var generator := StreamedRouteGenerator.new(seed_text)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var tower := VoidRegion.tower_chunk(seed_text)
	var well := generator.stairwell_between(tower.x, tower.y, StreamedRouteGenerator.MEZZANINE_LEVEL)
	_expect(not well.is_empty(), "%s: the tower has no stairwell up to the Mezzanine" % seed_text)
	if well.is_empty():
		return 0
	var landing: Vector2i = well["landing"]
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.global_position = Vector3(tower.x * size + landing.x + .5, StreamedFacilityView3D.LEVEL_HEIGHT + .1, tower.y * size + landing.y + .5)
	view.begin(seed_text, player)
	for _i in 12:
		await host.get_tree().process_frame
	var built := 0
	# the whole shaft is loaded: every level of the tower chunk, with colliders only where something stands
	for level in range(VoidRegion.BOTTOM_LEVEL, VoidRegion.TOP_LEVEL + 1):
		var coord := Vector3i(tower.x, level, tower.y)
		var root: Node3D = view._loaded.get(coord)
		_expect(root != null, "%s: void chunk %s is not loaded" % [seed_text, coord])
		if root == null:
			continue
		built += 1
		var data := generator.chunk(coord)
		var structure := root.get_node("Structure") as GridMap
		var mezz: Array = data["mezzanine_grid"]
		var floors := 0
		var air_with_collider := 0
		for z in size:
			for x in size:
				var item := structure.get_cell_item(Vector3i(x, 0, z))
				var code := int(mezz[z][x])
				if MezzanineRouteGenerator.is_walkable(code) or code == MezzanineRouteGenerator.PIT:
					floors += 1
					_expect(item != GridMap.INVALID_CELL_ITEM, "%s: level %d floor cell %s has no collider" % [seed_text, level, Vector2i(x, z)])
				elif item != GridMap.INVALID_CELL_ITEM:
					air_with_collider += 1
		_expect(floors > 100, "%s: level %d has only %d floor cells" % [seed_text, level, floors])
		_expect(air_with_collider == 0, "%s: level %d has %d open-air cells with a collider (a wall in the void)" % [seed_text, level, air_with_collider])
		var rails := root.get_node_or_null("CatwalkRails") as StaticBody3D
		_expect(rails != null and rails.get_child_count() > 0, "%s: level %d has no railings" % [seed_text, level])
		if level > VoidRegion.BOTTOM_LEVEL:
			_expect(root.get_node_or_null("Stairwell_spiral") != null, "%s: level %d stairs are not built by the level above" % [seed_text, level - 1])
	_expect(view.current_level() == StreamedRouteGenerator.MEZZANINE_LEVEL, "%s: the view does not track level +1 on the deck" % seed_text)
	view.clear()
	view.queue_free()
	player.queue_free()
	await host.get_tree().process_frame
	return built
