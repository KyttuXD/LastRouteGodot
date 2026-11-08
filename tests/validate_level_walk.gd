extends RefCounted

## Every level a runner can stand on streams in a complete chunk window: each loaded chunk has its Structure collider
## GridMap with items and its Surface mesh (walls, floors, ceilings) within a second, and nothing logs an error
## ("the wall and ceiling are just non-existent, only props are visible").
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- level_walk

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var log := PlaytestLog.new()
	OS.add_logger(log)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "SOAKTEST"
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 30:
		await host.get_tree().process_frame
	var facility: StreamedFacilityView3D = route.facility
	var generator: StreamedRouteGenerator = facility.generator
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var checked := 0
	var tower := VoidRegion.tower_chunk(generator.world_seed)
	for level in [0, -1, 1, -2, -3, 0]:
		# inside the void (its stair tower) and in the ordinary maze beside it
		for column in [tower, Vector2i(0, 0), Vector2i(-3, 2)]:
			if not generator.is_chunk_allowed(Vector3i(column.x, level, column.y)):
				continue
			route._admin_teleport_to(Vector3(column.x * size + 22.5, float(level) * 4.0 + 0.3, column.y * size + 22.5))
			for _i in 90:
				await host.get_tree().process_frame
			for coord_value in facility._loaded:
				var coord: Vector3i = coord_value
				var root: Node3D = facility._loaded[coord]
				if root == null or not is_instance_valid(root):
					continue
				checked += 1
				var structure := root.get_node_or_null("Structure") as GridMap
				var surface := root.get_node_or_null("Surface") as MeshInstance3D
				var where := "level %d walk at column %s: chunk %s" % [level, column, coord]
				_expect(structure != null and not structure.get_used_cells().is_empty(), "%s has no Structure colliders" % where)
				_expect(surface != null and surface.mesh != null and surface.mesh.get_surface_count() > 0, "%s has no Surface mesh (walls/ceilings/floors)" % where)
	_expect(log.errors == 0, "the walk logged %d errors: %s" % [log.errors, str(log.since(0).slice(0, 4))])
	route.queue_free()
	await host.get_tree().process_frame
	OS.remove_logger(log)
	if _failures == 0:
		print("  level_walk  %d loaded chunks over levels 0 / -1 / +1 / -2 / -3, in the void and in the maze: all have colliders and surface meshes, no errors" % checked)
	return _failures
