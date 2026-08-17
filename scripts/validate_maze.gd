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
	var pixel_effect := scene.pixel_signal_effect as PixelSignalEffect
	if pixel_effect == null or pixel_effect.find_child("PixelSignalSurface",
			true, false) == null:
		_fail("the route has no pixel/static post-process")
	elif not is_equal_approx(pixel_effect.strength(),
			Settings.pixel_effect_percent / 100.0):
		_fail("the route post-process ignored the saved Settings intensity")
	if pixel_effect != null and pixel_effect.layer >= scene.hud.layer:
		_fail("the pixel/static post-process also degrades HUD text")
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
		var item := grid.get_cell_item(cell)
		if item == FacilityView3D.ITEM_WALL:
			walls += 1
		else:
			# Region-tinted room tiles get their own MeshLibrary ids but are
			# mechanically still floor and each requires one ceiling cell.
			floors += 1
	lids = lid.get_used_cells().size()
	for id in [FacilityView3D.ITEM_FLOOR, FacilityView3D.ITEM_WALL,
			FacilityView3D.ITEM_CEILING]:
		if not grid.mesh_library.get_item_mesh(id) is BoxMesh:
			_fail("grid item %d is not a box, so it can carry a rotation" % id)
		# A cell is square to the grid, so an item that fills it must be too.
		if grid.mesh_library.get_item_mesh_transform(id).basis != Basis.IDENTITY:
			_fail("grid item %d is placed with a rotation" % id)
	# Floor/ceiling and the wall each carry their OWN dedicated texture
	# (FacilityView3D.FLOOR_TEXTURE / WALL_TEXTURE) rather than a shared atlas
	# cropped down to one patch -- there is no longer a "patch fraction of a
	# bigger sheet" to infer, so this checks the thing that can now actually
	# go wrong: the wrong texture wired to the wrong item, or a repeat that
	# silently reverted to the atlas-cropping era's uv1_offset/scale shape.
	var expected_texture := {
		FacilityView3D.ITEM_FLOOR: FacilityView3D.FLOOR_TEXTURE,
		FacilityView3D.ITEM_WALL: FacilityView3D.WALL_TEXTURE,
		FacilityView3D.ITEM_CEILING: FacilityView3D.FLOOR_TEXTURE,
	}
	for id in expected_texture:
		var mesh := grid.mesh_library.get_item_mesh(id)
		var material := mesh.surface_get_material(0) if mesh != null else null
		if not material is StandardMaterial3D:
			_fail("grid item %d has no StandardMaterial3D at all" % id)
			continue
		var std: StandardMaterial3D = material
		if std.albedo_texture == null or std.albedo_texture.resource_path != expected_texture[id]:
			_fail("grid item %d is not wired to its own dedicated texture (%s)" % [id, expected_texture[id]])
		# A leftover atlas-offset would mean the old cropping heuristic came
		# back; a dedicated texture is read from its own origin, whole.
		if std.uv1_offset != Vector3.ZERO:
			_fail("grid item %d has a nonzero uv1_offset -- looks like a cropped atlas patch, not a whole dedicated texture" % id)

	# Gravity makes the floor a real physics contract. Y-centering must stay off
	# or Godot shifts that collider up half a cell and embeds the player in it.
	if grid.cell_center_y or lid.cell_center_y:
		_fail("the GridMap Y origin is centred instead of floor-based")
	if grid.mesh_library.get_item_shapes(FacilityView3D.ITEM_FLOOR).is_empty():
		_fail("the floor has no collision for player gravity")
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

	# Room identities and their furniture are simulation data now, not merely
	# painted labels. The standard nine-room route guarantees the first five
	# authored landmark types and must remain exactly repeatable from its seed.
	var generator := view.generator
	if generator.props.is_empty():
		_fail("the themed-room population placed no props")
	var room_types: Array[String] = []
	for room in generator.rooms:
		var type := String(room.get("type", ""))
		room_types.append(type)
		if String(room.get("id", "")) != "room-lobby" and type in ["", "generic"]:
			_fail("%s has no themed room identity" % String(room.get("id", "room")))
	for required in ["stage", "arcade", "serviceBay", "prizeGallery",
			"arcadeHallway"]:
		if not room_types.has(required):
			_fail("standard route omitted required themed room '%s'" % required)

	var repeat := FacilityGenerator.new(generator.seed_text,
		RoomState.generator_options())
	if repeat.props != generator.props:
		_fail("the same room seed produced different prop placement")
	var reachable := generator.distance_map(start.x, start.y)
	if not reachable.has(generator.exit_cell):
		_fail("themed props cut the route off from its service lift")
	for group_name in ["relays", "batteries", "safe zones"]:
		var group: Array = generator.relays if group_name == "relays" else (
			generator.batteries if group_name == "batteries" else generator.safe_zones)
		for entry in group:
			var at := Vector2i(int(entry["x"]), int(entry["y"]))
			if not reachable.has(at):
				_fail("themed props cut off %s at %s" % [group_name, at])
	for prop in generator.props:
		if not RoomCatalog.is_solid(String(prop.get("type", ""))):
			continue
		if generator.can_occupy(float(prop["x"]) + .5,
				float(prop["y"]) + .5):
			_fail("solid prop %s does not block navigation" % prop.get("id", "prop"))

	# The renderer consumes every generated entry once. Solid entries need a
	# real collision child; non-solid carpets/chandeliers remain visual-only.
	var rendered_props := 0
	for node in view.get_children():
		if not node.has_meta("prop_type"):
			continue
		rendered_props += 1
		var type := String(node.get_meta("prop_type"))
		if RoomCatalog.is_solid(type) \
				and node.find_child("Collision", false, false) == null:
			_fail("rendered solid prop %s has no collision" % type)
		if PropModelCatalog.has_model(type):
			var model_path := String(node.get_meta("prop_model_path", ""))
			if model_path.is_empty():
				_fail("authored prop %s fell back to a coloured box" % type)
			elif not ResourceLoader.exists(model_path):
				_fail("authored prop %s points at missing %s" % [type, model_path])
			if node.find_child("Visual", false, false) == null:
				_fail("authored prop %s has no instanced visual" % type)
	if rendered_props != generator.props.size():
		_fail("rendered %d of %d generated room props" % [rendered_props,
			generator.props.size()])

	# Looking down at a sealed corridor shows a ceiling, which is why that view
	# went black. It is the original game's primary perspective, so it has to
	# see through the lid rather than lose it.

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

	# The player is in first person, on the floor, and the ceiling is drawn --
	# there is no second view to lift it for any more.
	if absf(scene.player.global_position.y) > 0.25:
		_fail("the player stands at y=%.2f, not on the floor"
			% scene.player.global_position.y)
	if not lid.visible:
		_fail("the ceiling is hidden with no top-down view to hide it for")

	if _failures == 0:
		print("  fabric    %d floors, %d walls, %d ceiling cells, all boxes"
			% [floors, walls, lids])
		print("  spawn     heater at %s, start at %s, lamp on"
			% [view.heater_station.source_cell, start])
		print("  rooms     %d themed rooms, %d deterministic props"
			% [generator.rooms.size(), generator.props.size()])
		print("maze OK")
	scene.queue_free()
	await host.get_tree().process_frame
	return _failures
