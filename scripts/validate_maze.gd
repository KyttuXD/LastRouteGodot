extends RefCounted

## Headless check on the 3D maze's fabric.
##
## Three things were wrong in a live build and none of them are visible to a
## script that only reads the generator: the walls were imported models dropped
## into a cube grid and landed rotated, there was no ceiling at all, and the
## heater station spawned on the player's own spawn cell -- at arm's length,
## in the way.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- maze

var _host: Node
var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	_host = host
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	var view: FacilityView3D = scene.facility_view
	var grid: GridMap = view.get_child(0) as GridMap
	# The ceiling lives on its own GridMap so the top-down view can hide it.
	var lid: GridMap = view.get_child(1) as GridMap
	if grid == null or lid == null:
		_fail("no GridMap under the facility view")
		scene.queue_free()
		return _failures

	# Cubes, not imported models: an item whose mesh is not a box can be
	# rotated wrongly by its own baked transform, which is the bug this fixes.
	var floors := 0
	var walls := 0
	var lids := 0
	for cell in grid.get_used_cells():
		match grid.get_cell_item(cell):
			FacilityView3D.ITEM_FLOOR: floors += 1
			FacilityView3D.ITEM_WALL: walls += 1
	lids = lid.get_used_cells().size()
	for id in [FacilityView3D.ITEM_FLOOR, FacilityView3D.ITEM_WALL,
			FacilityView3D.ITEM_CEILING]:
		if not grid.mesh_library.get_item_mesh(id) is BoxMesh:
			_fail("grid item %d is not a box, so it can carry a rotation" % id)
		# A cell is square to the grid, so an item that fills it must be too.
		if grid.mesh_library.get_item_mesh_transform(id).basis != Basis.IDENTITY:
			_fail("grid item %d is placed with a rotation" % id)
	# A cube that samples most of the atlas is showing several unrelated
	# materials at once -- the collage that made every floor tile a mess. One
	# patch is a small fraction of the sheet; half of it is not a patch.
	for id in [FacilityView3D.ITEM_FLOOR, FacilityView3D.ITEM_WALL,
			FacilityView3D.ITEM_CEILING]:
		var mesh := grid.mesh_library.get_item_mesh(id)
		var material := mesh.surface_get_material(0) if mesh != null else null
		if material is StandardMaterial3D:
			var scale: Vector3 = (material as StandardMaterial3D).uv1_scale
			if scale.x > 0.5 or scale.y > 0.5:
				_fail("grid item %d samples %.0f%% x %.0f%% of its atlas, not one patch"
					% [id, scale.x * 100.0, scale.y * 100.0])

	# The floor has to stop things. It did not, and nothing noticed because the
	# player has no gravity -- a floor that only works because nothing pulls
	# down is not a floor.
	# The floor is deliberately collider-less until there is gravity: a slab
	# whose top is flush with the capsule's base ejects the player upward every
	# frame, half a metre at a time, with nothing to bring him back down.
	if not grid.mesh_library.get_item_shapes(FacilityView3D.ITEM_FLOOR).is_empty():
		_fail("the floor has collision again, which makes the player climb")
	if not grid.mesh_library.get_item_shapes(FacilityView3D.ITEM_CEILING).is_empty():
		_fail("the ceiling has collision, so the player has a head to bump")

	if lids == 0:
		_fail("the maze still has no ceiling")
	elif lids != floors:
		_fail("%d ceiling cells over %d floor cells" % [lids, floors])

	# Nothing may spawn on the cell the player stands up in.
	var start: Vector2i = view.generator.start
	if view.heater_station != null and view.heater_station.source_cell == start:
		_fail("the heater station is still on the spawn cell")

	# Looking down at a sealed corridor shows a ceiling, which is why that view
	# went black. It is the original game's primary perspective, so it has to
	# see through the lid rather than lose it.
	view.set_ceiling_visible(false)
	if lid.visible:
		_fail("the ceiling stayed visible for the top-down view")
	view.set_ceiling_visible(true)
	if not lid.visible:
		_fail("the ceiling did not come back for first person")

	# A collected relay used to stay exactly where it was with its glow off,
	# which reads as the interaction having failed rather than as a pickup.
	var relay: RouteInteractable3D = null
	for node in host.get_tree().get_nodes_in_group("interactable"):
		if node is RouteInteractable3D \
				and (node as RouteInteractable3D).kind == RouteInteractable3D.Kind.RELAY:
			relay = node
			break
	if relay == null:
		_fail("the floor generated no signal relays")
	else:
		var before: int = GameState.relays_collected
		relay.activate(scene.player)
		if not relay.completed:
			_fail("activating a relay did not collect it")
		if GameState.relays_collected != before + 1:
			_fail("collecting a relay did not count toward the objective")
		var seen := false
		for child in relay.get_children():
			if child is Node3D and (child as Node3D).visible and not child is Light3D:
				seen = true
		if seen:
			_fail("a collected relay is still standing there")

	# The maze is lit almost entirely by the lamp; starting dark reads as a
	# broken build rather than as atmosphere.
	if not scene.player.flashlight_enabled:
		_fail("the player spawns with the flashlight off")

	# The top-down view is the ORIGINAL game's primary perspective and it has
	# come back black twice. Check the three things that make it a picture at
	# all: something to look through, something lit, and no lid in the way.
	var top_down: Camera3D = scene.player.top_down_camera
	view.set_ceiling_visible(false)
	if not top_down.current:
		_fail("the top-down camera is not the current one at startup")
	if lid.visible:
		_fail("the ceiling is still drawn over the top-down view")
	if scene.player._overhead_light == null or not scene.player._overhead_light.visible:
		_fail("the top-down view has no overhead light")
	# Guessing at this view has failed twice. Measure what is actually inside
	# the camera's box: an orthographic camera at 12 m with size 10 sees a
	# 10 m tall slice, and if no geometry falls in it the picture is black
	# whatever the lights are doing.
	var eye := top_down.global_position
	var half := top_down.size * 0.5
	var window := AABB(Vector3(eye.x - half, eye.y - top_down.far, eye.z - half),
		Vector3(half * 2.0, top_down.far, half * 2.0))
	# Count the GRID, not MeshInstance3D nodes. A GridMap is a single node
	# however many cells it draws, so counting mesh instances counted the
	# player's own 21-piece body and called that "the world is in view".
	var cells := 0
	for cell in grid.get_used_cells():
		var at := grid.to_global(grid.map_to_local(cell))
		if absf(at.x - eye.x) <= half and absf(at.z - eye.z) <= half:
			cells += 1
	print("  camview   eye %s, player %s, %d grid cells under it"
		% [eye.round(), scene.player.global_position.round(), cells])
	if cells == 0:
		_fail("no floor or wall falls inside the top-down camera's box")
	# The player standing a metre above the floor is not a view bug, but it is
	# a bug, and it would put the body inside the ceiling of a 3 m corridor.
	if absf(scene.player.global_position.y) > 0.25:
		_fail("the player stands at y=%.2f, not on the floor"
			% scene.player.global_position.y)

	var span: float = top_down.size
	var reach: float = top_down.global_position.y - top_down.far
	print("  topdown   ortho %.0f units, floor %.1f above the far plane, lid %s"
		% [span, -reach, "hidden" if not lid.visible else "SHOWN"])
	if reach > 0.0:
		_fail("the far plane sits %.1f above the floor, so nothing renders" % reach)

	if _failures == 0:
		print("  fabric    %d floors, %d walls, %d ceiling cells, all boxes"
			% [floors, walls, lids])
		print("  spawn     heater at %s, start at %s, lamp on"
			% [view.heater_station.source_cell, start])
		print("maze OK")
	scene.queue_free()
	await host.get_tree().process_frame
	return _failures
