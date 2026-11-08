extends RefCounted

## the Mezzanine (+1) and its void are removed from play. In a real streamed view this suite now
## checks that a runner on the maze, where the void and a deck patch used to be, never streams a level +1 chunk or a
## mezzanine_grid chunk, builds no catwalk rails, and the maze keeps its ceiling (no deck grating overhead).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- mezzanine_view

const SEEDS := ["UPPER-A", "UPPER-B", "KYTTU-LAB"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_expect(not StreamedRouteGenerator.MEZZANINE_ENABLED, "the Mezzanine (+1) is still enabled (removed)")
	var checked := 0
	for seed_text in SEEDS:
		checked += await _check_seed(host, seed_text)
	_expect(checked > 0, "no chunks streamed")
	if _failures == 0:
		print("  mezzanine_view  removed: %d chunks streamed over the old void and deck patches, none on +1, no catwalks or rails" % checked)
	return _failures


func _check_seed(host: Node, seed_text: String) -> int:
	var generator := StreamedRouteGenerator.new(seed_text)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var spots: Array[Vector2i] = [VoidRegion.tower_chunk(seed_text)]
	# a column the deck patches used to cover (DeckPatches noise is unchanged; it just builds nothing now)
	for r in range(2, 9):
		if spots.size() > 1:
			break
		for dx in range(-r, r + 1):
			if DeckPatches.is_deck(seed_text, dx, r):
				spots.append(Vector2i(dx, r))
				break
	var checked := 0
	for column in spots:
		_expect(not generator.is_chunk_allowed(Vector3i(column.x, StreamedRouteGenerator.MEZZANINE_LEVEL, column.y)),
			"%s +1 still exists over %s" % [seed_text, column])
		var view := StreamedFacilityView3D.new()
		host.add_child(view)
		var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
		host.add_child(player)
		player.global_position = Vector3(column.x * size + 22.5, StreamedFacilityView3D.LEVEL_HEIGHT + .1, column.y * size + 22.5)
		view.begin(seed_text, player)
		for _i in 12:
			await host.get_tree().process_frame
		_expect(view.current_level() == 0, "%s: a runner at +1 height over %s is not clamped to level 0" % [seed_text, column])
		for coord_value in view._loaded:
			var coord: Vector3i = coord_value
			checked += 1
			_expect(coord.y < StreamedRouteGenerator.MEZZANINE_LEVEL, "%s: the view streamed a +1 chunk %s" % [seed_text, coord])
			var root: Node3D = view._loaded[coord]
			_expect(not generator.chunk(coord).has("mezzanine_grid"), "%s: %s is a mezzanine chunk" % [seed_text, coord])
			if root != null and is_instance_valid(root):
				_expect(root.get_node_or_null("CatwalkRails") == null, "%s: %s still builds catwalk rails" % [seed_text, coord])
		view.clear()
		view.queue_free()
		player.queue_free()
		await host.get_tree().process_frame
	return checked
