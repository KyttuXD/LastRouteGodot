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
##   godot4 --headless res://tests/scenes/validate.tscn -- maze

var _host: Node
var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	_host = host
	# This suite verifies exact authored route guarantees (including a usable
	# three-wide hallway barricade), so do not inherit whichever random room an
	# earlier suite happened to leave in the RoomState autoload.
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "MAZE-CHECK"
	var scene: Node = load("res://game/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	var view: FacilityView3D = scene.facility_view
	var pixel_effect := scene.pixel_signal_effect as PixelSignalEffect
	if pixel_effect == null or pixel_effect.find_child("PixelSignalSurface",
			true, false) == null:
		_fail("the route has no pixel-blur post-process")
	elif not is_equal_approx(pixel_effect.strength(),
			Settings.pixel_effect_percent / 100.0):
		_fail("the route post-process ignored the saved Settings intensity")
	if pixel_effect != null and pixel_effect.layer >= scene.hud.layer:
		_fail("the pixel-blur post-process also degrades HUD text")
	if PixelSignalEffect.SHADER_CODE.contains("TIME") \
			or PixelSignalEffect.SHADER_CODE.contains("scanline") \
			or PixelSignalEffect.SHADER_CODE.contains("grain"):
		_fail("the pixel effect still contains the removed static/scanline treatment")
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
	var wall_items: Array = [FacilityView3D.ITEM_WALL]
	wall_items.append_array(view._region_wall_items.values())
	for cell in grid.get_used_cells():
		var item := grid.get_cell_item(cell)
		if wall_items.has(item):
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
	for region in view._region_floor_items:
		var region_item: int = view._region_floor_items[region]
		if grid.mesh_library.get_item_shapes(region_item).is_empty():
			_fail("the %s region floor has no collision for player gravity" % region)
	for region in view._region_wall_items:
		var region_item: int = view._region_wall_items[region]
		if not grid.mesh_library.get_item_mesh(region_item) is BoxMesh:
			_fail("the %s regional wall is not a box" % region)
		if grid.mesh_library.get_item_shapes(region_item).is_empty():
			_fail("the %s regional wall has no collision" % region)
	if not grid.mesh_library.get_item_shapes(FacilityView3D.ITEM_CEILING).is_empty():
		_fail("the ceiling has collision, so the player has a head to bump")

	_expect_walkable_stairs(view, scene)
	_expect_ladders_and_lights(view, scene)
	if scene.player.flashlight_enabled \
			or not scene.player.owns_inventory_item("flashlight"):
		_fail("the player does not begin with an owned but switched-off flashlight")
	_expect_tool_gates(view, scene)

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
	_expect_vent_placements(generator)
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
	# real collision child; non-solid chandeliers and wall art remain visual-only.
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

	# Equipment is discovered in the facility now, so the player starts empty
	# and the beam cannot exist before its authored pickup is collected.

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
		print("  spawn     heater at %s, start at %s, starter flashlight"
			% [view.heater_station.source_cell, start])
		print("  rooms     %d themed rooms, %d deterministic props"
			% [generator.rooms.size(), generator.props.size()])
		print("maze OK")
	scene.queue_free()
	await host.get_tree().process_frame
	return _failures


func _expect_tool_gates(view: FacilityView3D, scene: Node) -> void:
	for model_path in [
			"res://assets/interactables/locked_relay_crate.glb",
			"res://assets/interactables/locked_relay_barrel.glb",
			"res://assets/interactables/boarded_door.glb",
			"res://assets/interactables/boarded_hallway.glb",
			"res://assets/interactables/flashlight_item.glb",
			"res://assets/interactables/taser_item.glb",
			"res://assets/interactables/lockpick_set.glb",
			"res://assets/interactables/crowbar.glb",
			"res://assets/interactables/rescue_axe.glb",
			"res://assets/interactables/service_ladder.glb",
			"res://assets/interactables/wall_light_switch.glb"]:
		if not ResourceLoader.exists(model_path) or load(model_path) == null:
			_fail("authored inventory/barrier model is missing: %s" % model_path)
	var locked: RouteInteractable3D
	var barrier: RouteInteractable3D
	var hallway_barrier: RouteInteractable3D
	var pickups := {}
	for candidate in view._interactables:
		var item := candidate as RouteInteractable3D
		if item == null:
			continue
		if item.kind == RouteInteractable3D.Kind.RELAY and item.locked_cache:
			locked = item
		elif item.kind == RouteInteractable3D.Kind.BOARDED_PATH:
			if item.boarded_variant == "hallway":
				hallway_barrier = item
			else:
				barrier = item
		elif item.kind == RouteInteractable3D.Kind.TOOL_PICKUP:
			pickups[item.tool_item_id] = item
	for item_id in PlayerController3D.INVENTORY_ITEMS:
		if item_id == "flashlight":   # the player starts with it and the world spawns no flashlight pickups
			if pickups.has(item_id):
				_fail("the world spawned a flashlight pickup")
			continue
		if not pickups.has(item_id):
			_fail("the seeded facility has no %s pickup" % item_id)
		elif (pickups[item_id] as RouteInteractable3D).find_child(
				"AuthoredPickup_%s" % item_id, true, false) == null:
			_fail("the %s pickup is not using its authored GLB" % item_id)
	if locked == null:
		_fail("the route generated no locked relay crate/barrel")
	else:
		var meshes := locked.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() < 4:
			_fail("the locked relay cache is not using its authored model")
		scene.player.grant_inventory_item("lockpick")
		var durability: int = scene.player.item_durability("lockpick")
		var message := locked.activate(scene.player)
		if not locked.completed or scene.player.item_durability("lockpick") != durability - 1:
			_fail("lockpicking a relay cache did not collect it and spend durability")
		if not message.contains("SIGNAL RELAY RECOVERED"):
			_fail("lockpicking returned an unclear result: %s" % message)
	if barrier == null:
		# A small board is optional when the generated floor has no true
		# one-cell doorway. It must never be substituted into a wide threshold.
		pass
	else:
		var outward: Vector3 = -barrier.global_transform.basis.z.normalized()
		var across := Vector2i(0, 1) if absf(outward.x) > .5 else Vector2i(1, 0)
		var outside := barrier.source_cell + Vector2i(roundi(outward.x), roundi(outward.z))
		if view.generator._valid_open_cell(outside + across) \
				or view.generator._valid_open_cell(outside - across):
			_fail("the one-metre door barricade was placed in a wide passage")
		if barrier.find_children("*", "MeshInstance3D", true, false).size() < 8:
			_fail("the boarded path is not using its authored door model")
		scene.player.grant_inventory_item("crowbar")
		var durability: int = scene.player.item_durability("crowbar")
		var pieces := barrier.board_pieces_remaining
		for hit in pieces:
			barrier.activate(scene.player)
			if barrier.opened != (hit == pieces - 1):
				_fail("boarded path opened before its individual planks were broken")
		if scene.player.item_durability("crowbar") != durability - pieces:
			_fail("piece-by-piece breaching did not spend one durability per board")
		var body := barrier.find_child("ToolBarrier", false, false) as StaticBody3D
		if body != null and body.process_mode != Node.PROCESS_MODE_DISABLED:
			_fail("an opened boarded path still has active collision")
	if hallway_barrier == null:
		_fail("the 3-wide procedural hallway generated no full-width barricade")
	else:
		var body := hallway_barrier.find_child("ToolBarrier", false, false) as StaticBody3D
		var collision: CollisionShape3D = body.get_child(0) as CollisionShape3D \
			if body else null
		if collision == null or not collision.shape is BoxShape3D \
				or (collision.shape as BoxShape3D).size.x < 2.9:
			_fail("the hallway barricade does not block the full three-metre width")
	print("  tools     authored caches, boards and durable breach tools active")


func _expect_ladders_and_lights(view: FacilityView3D, _scene: Node) -> void:
	var ladder_fixture := Node3D.new()
	view.add_child(ladder_fixture)
	view._add_structure_ladder(ladder_fixture, "grandStaircase")
	var ladders: Array = []
	for candidate in _host.get_tree().get_nodes_in_group("climbable_ladder"):
		var node := candidate as Node3D
		if node and view.is_ancestor_of(node):
			ladders.append(node)
	if ladders.is_empty():
		_fail("walkable raised structures have no climbable ladder alternative")
	else:
		var ladder := ladders[0] as Node3D
		if ladder.find_child("AuthoredLadderModel", true, false) == null:
			_fail("the climbable ladder is not using its authored GLB")
		if not bool(ladder.call("can_climb", ladder.global_position + Vector3(0, .4, 0))):
			_fail("the authored ladder has no usable climb volume")
	ladder_fixture.free()
	var switches: Array[RouteInteractable3D] = []
	for candidate in view._interactables:
		var item := candidate as RouteInteractable3D
		if item and item.kind == RouteInteractable3D.Kind.LIGHT_SWITCH:
			switches.append(item)
	if switches.size() < 2:
		_fail("the route generated fewer than two toggleable room lights")
	elif view._room_lights.size() != switches.size():
		_fail("room light fixtures and switches do not have a one-to-one mapping")
	else:
		view.set_all_room_lights(false)
		for light_data in view._room_lights.values():
			var light := light_data.get("light") as OmniLight3D
			if light and light.visible:
				_fail("admin all-lights-off left a room light visible")
		view.set_all_room_lights(true)
	print("  access    authored ladders and shared room-light switches active")


func _expect_walkable_stairs(view: FacilityView3D, scene: Node) -> void:
	if not RoomCatalog.is_walkable_structure("grandStaircase") \
			or RoomCatalog.is_solid("grandStaircase"):
		_fail("grand stairs are not registered as traversable architecture")
	var stair_path := PropModelCatalog.model_path("grandStaircase", "validation")
	if stair_path.is_empty() or load(stair_path) == null:
		_fail("the grand staircase GLB is missing from the prop catalog")
	if not RoomCatalog.is_walkable_structure("grandFoyerStaircase") \
			or RoomCatalog.is_solid("grandFoyerStaircase"):
		_fail("the twin foyer stairs are not registered as traversable architecture")
	var foyer_path := PropModelCatalog.model_path("grandFoyerStaircase", "validation")
	if foyer_path.is_empty() or load(foyer_path) == null:
		_fail("the twin grand-foyer staircase GLB is missing from the prop catalog")

	var stair := StaticBody3D.new()
	stair.position = Vector3(4.0, 0.0, 4.0)
	view.add_child(stair)
	view._add_stair_collision(stair)
	view._stair_nodes.append(stair)
	var shapes := stair.find_children("*", "CollisionShape3D", true, false)
	if shapes.size() != 2:
		_fail("grand stairs have %d collision surfaces instead of ramp + landing"
			% shapes.size())
	var ramp_start := Vector2(4.0, 4.0 - FacilityView3D.STAIR_RUN * .5)
	var ramp_middle := Vector2(4.0, 4.0)
	var landing := Vector2(4.0, 4.0 + FacilityView3D.STAIR_RUN * .5 + .4)
	if absf(view.surface_height_at(ramp_start)) > .03:
		_fail("stair ramp does not begin flush with the room floor")
	if absf(view.surface_height_at(ramp_middle) - .5) > .03:
		_fail("stair ramp midpoint is not half-height")
	if absf(view.surface_height_at(landing) - FacilityView3D.STAIR_RISE) > .03:
		_fail("stair landing does not reach its declared raised level")

	var foyer := StaticBody3D.new()
	foyer.position = Vector3(12.0, 0.0, 12.0)
	foyer.set_meta("prop_type", "grandFoyerStaircase")
	view.add_child(foyer)
	view._add_stair_collision(foyer, "grandFoyerStaircase")
	view._stair_nodes.append(foyer)
	var foyer_shapes := foyer.find_children("*", "CollisionShape3D", true, false)
	if foyer_shapes.size() != 3:
		_fail("twin foyer has %d collision surfaces instead of two ramps + gallery"
			% foyer_shapes.size())
	var left_start := Vector2(12.0, 12.0) + FacilityView3D.FOYER_LEFT_START
	var left_mid := Vector2(12.0, 12.0) + (FacilityView3D.FOYER_LEFT_START
		+ FacilityView3D.FOYER_LEFT_END) * .5
	var gallery_at := Vector2(12.0, 12.0 + FacilityView3D.FOYER_GALLERY_CENTER_Z)
	if absf(view.surface_height_at(left_start)) > .03:
		_fail("twin foyer flight does not start flush with the floor")
	if absf(view.surface_height_at(left_mid) - FacilityView3D.FOYER_STAIR_RISE * .5) > .03:
		_fail("twin foyer flight midpoint does not match its smooth ramp")
	if absf(view.surface_height_at(gallery_at) - FacilityView3D.FOYER_STAIR_RISE) > .03:
		_fail("twin foyer gallery does not reach its declared raised level")
	if scene.hunter_view == null \
			or not scene.hunter_view.surface_height_provider.is_valid():
		_fail("hunter presentation is not connected to stair surface heights")
	elif scene.hunter_view._animation_player == null:
		_fail("route hunter has no AnimationPlayer for the stun reaction")
	else:
		var old_stun: float = scene.hunter_view.brain.stun_timer
		scene.hunter_view.brain.stun_timer = 1.0
		scene.hunter_view.sync_from_brain()
		if scene.hunter_view._animation_player.current_animation != "stun":
			_fail("a stunned hunter did not switch to the dizzy stun clip")
		scene.hunter_view.brain.stun_timer = old_stun
		scene.hunter_view.sync_from_brain()
	view._stair_nodes.erase(stair)
	stair.free()
	view._stair_nodes.erase(foyer)
	foyer.free()


func _expect_vent_placements(generator: FacilityGenerator) -> void:
	var sampled_room: Dictionary = {}
	for room in generator.rooms:
		if not RoomCatalog.room_has_walkable_structure(String(room.get("type", ""))):
			sampled_room = room
			break
	if sampled_room.is_empty():
		_fail("no ordinary room exists to validate varied vent placement")
		return
	var candidates: Array = generator._vent_candidates(sampled_room, {})
	var has_floor := candidates.any(func(entry): return entry["mount"] == "floor")
	var has_wall := candidates.any(func(entry): return entry["mount"] == "wall")
	if not has_floor or not has_wall:
		_fail("vent placement cannot choose both room-floor and low-wall mounts")
	for vent in generator.vents:
		var mount := String(vent.get("mount", ""))
		if not ["floor", "wall"].has(mount):
			_fail("generated vent has invalid mount '%s'" % mount)
		if mount == "wall" and vent.get("wall_dir", Vector2i.ZERO) == Vector2i.ZERO:
			_fail("a low-wall vent has no wall direction")
