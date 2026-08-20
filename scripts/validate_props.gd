extends RefCounted

## Shipping-asset contract for the first detailed modular route prop. Geometry
## changes are welcome; these checks only protect the cell footprint, floor
## pivot, useful height, material/detail budget, and live hiding-state wiring.

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_validate_room_model_catalog()
	_validate_room_palette_contract()
	_validate_light_fixture_contract()
	_validate_streamed_furniture_contract()
	await _validate_room_door_animation(host)
	var item := RouteInteractable3D.new()
	item.kind = RouteInteractable3D.Kind.HIDING_SPOT
	host.get_tree().root.add_child(item)
	await host.get_tree().process_frame

	var model: Node3D = item._visual
	_expect(model != null, "the hiding-spot route slot did not load its GLB scene")
	if model != null:
		var authored_model := model.find_child("Model", true, false) as Node3D
		_expect(authored_model != null and is_equal_approx(
			absf(authored_model.rotation.y), PI),
			"the +Z-authored locker door is not corrected to the route's -Z front")
		var mesh_nodes := model.find_children("*", "MeshInstance3D", true, false)
		_expect(mesh_nodes.size() >= 25,
			"the locker regressed to %d mesh parts; expected its detailed modular model" \
			% mesh_nodes.size())
		var combined := AABB()
		var has_bounds := false
		var material_names := {}
		var stable_filtered_materials := 0
		var blocky_lit_materials := 0
		var non_blocky_surfaces := []
		for value in mesh_nodes:
			var mesh_node := value as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			var bounds: AABB = mesh_node.global_transform * mesh_node.get_aabb()
			combined = combined.merge(bounds) if has_bounds else bounds
			has_bounds = true
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface)
				if material != null:
					material_names[material.resource_name] = true
				if material is StandardMaterial3D:
					var standard := material as StandardMaterial3D
					var filtering := standard.texture_filter
					if filtering in [
							BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,
							BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC,
					]:
						stable_filtered_materials += 1
					if standard.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX \
							and standard.roughness >= .9:
						blocky_lit_materials += 1
					elif filtering in [
							BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,
							BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC,
					]:
						non_blocky_surfaces.append("%s:%d:%s:%d:%.2f" % [
							mesh_node.name, surface, standard.resource_name,
							standard.shading_mode, standard.roughness])
		_expect(has_bounds, "the detailed locker contains no renderable mesh bounds")
		if has_bounds:
			_expect(combined.position.y >= -0.025 and combined.position.y <= 0.025,
				"locker pivot is not floor-flush (minimum y %.3f)" % combined.position.y)
			_expect(combined.end.y >= 1.80 and combined.end.y <= 2.05,
				"locker height %.3fm is outside the human-scale prop range" % combined.end.y)
			_expect(combined.size.x <= 0.90 and combined.size.z <= 0.90,
				"locker footprint %.3fx%.3fm spills outside one route cell" % [
					combined.size.x, combined.size.z])
		_expect(material_names.size() >= 4,
			"locker retained only %d materials; inset/trim/hardware reads were lost" \
			% material_names.size())
		_expect(stable_filtered_materials > 0,
			"imported props use unmipmapped nearest filtering and will stripe while moving")
		_expect(blocky_lit_materials == stable_filtered_materials,
				"props are not using the shared matte per-vertex block style (%d/%d): %s" % [
					blocky_lit_materials, stable_filtered_materials, non_blocky_surfaces])
		for slat_index in range(1, 4):
			_expect(model.find_child("SightSlat_%d" % slat_index, true, false) != null,
				"locker door is missing authored sight slat %d" % slat_index)
		item.set_local_hiding_view(true)
		_expect(item.local_hiding_view_open() and model.visible,
			"hiding erased the locker instead of preserving its narrow sight cracks")
		item.set_local_hiding_view(false)
		_expect(model.visible, "leaving hiding did not restore the local locker shell")

		item.set_disabled(true)
		_expect(not model.visible, "a burned hiding spot left its detailed locker visible")
		item.set_disabled(false)
		_expect(model.visible, "a regenerated hiding spot did not restore its locker")
		print("  locker    %d mesh parts, %d materials, %.2fm high, %.2fx%.2fm footprint" % [
			mesh_nodes.size(), material_names.size(), combined.end.y,
			combined.size.x, combined.size.z])

	item.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("props OK")
	return _failures


func _validate_streamed_furniture_contract() -> void:
	for region_value in StreamedRouteGenerator.REGION_PROP_SETS:
		var region := String(region_value)
		for choice_value in StreamedRouteGenerator.REGION_PROP_SETS[region]:
			var choice: Dictionary = choice_value
			_expect(String(choice.get("type", "")) != "loungeCouch",
				"%s still selects the undersized one-seat couch" % region)
	_expect(not (StreamedRouteGenerator.REGION_PROP_SETS["maze"] as Array).any(
		func(choice: Dictionary) -> bool:
			return String(choice.get("type", "")) == "corridorCarpet"),
		"maze corridors still spawn the floor-length purple overlay")

	var view := StreamedFacilityView3D.new()
	var prop_root := Node3D.new()
	view._spawn_authored_prop(prop_root,
		PropModelCatalog.model_path("loungeCouchWide", "PROP-SCALE-CHECK"),
		Vector3.ZERO, 0.0, Vector3(1.8, 1.0, .8),
		"validation_prop", true, "loungeCouchWide")
	var visual: Node3D = prop_root.get_child(0) as Node3D \
		if prop_root.get_child_count() > 0 else null
	_expect(visual != null, "wide streamed couch did not instantiate")
	if visual != null:
		var bounds := ModelSlot.combined_local_bounds(visual)
		_expect(maxf(bounds.size.x, bounds.size.z) >= 1.7,
			"wide couch is still miniature (%.2fx%.2fm)" % [bounds.size.x, bounds.size.z])
		_expect(absf(visual.position.y + bounds.position.y) <= .015,
			"streamed couch remains buried below the floor")
		_expect(absf(angle_difference(visual.rotation.y, PI)) <= .001,
			"authored prop front still points into its backing wall")
	prop_root.free()
	view.free()
	print("  furniture wide couch is human-scale, floor-seated and room-facing")


func _validate_room_palette_contract() -> void:
	var expected_themes := {
		"woodenChair": ["oak", "walnut", "mahogany", "ash"],
		"woodenChairCushion": ["oak", "walnut", "mahogany", "ash"],
		"woodenTable": ["oak", "walnut", "mahogany", "ash"],
		"woodenDresserSideboard": ["oak", "walnut", "mahogany", "ash"],
		"retroComputerCompact": ["ivory", "charcoal", "teal", "burgundy"],
		"retroComputerTower": ["ivory", "charcoal", "teal", "burgundy"],
		"retroComputerDesktop": ["ivory", "charcoal", "teal", "burgundy"],
		"retroComputerTerminal": ["ivory", "charcoal", "teal", "burgundy"],
		"officeDesk": ["neutral", "charcoal", "teal"],
		"officeChair": ["neutral", "charcoal", "teal"],
		"officeCrtSecurityConsole": ["neutral", "charcoal", "teal"],
		"officeCubiclePartition": ["neutral", "charcoal", "teal"],
		"officePrinter": ["neutral", "charcoal", "teal"],
		"officeWaterCooler": ["neutral", "charcoal", "teal"],
		"officePhotocopier": ["neutral", "charcoal", "teal"],
		"officeShredder": ["neutral", "charcoal", "teal"],
		"officeFileBoxes": ["neutral", "charcoal", "teal"],
		"officeCornerWorkstation": ["neutral", "charcoal", "teal"],
	}
	for type in expected_themes:
		var paths: Array = PropModelCatalog.MODEL_PATHS.get(type, [])
		var themes: Array = PropModelCatalog.VARIANT_THEMES.get(type, [])
		_expect(paths.size() == (expected_themes[type] as Array).size(),
			"%s does not expose every room-coherent variant" % type)
		_expect(themes == expected_themes[type],
			"%s variant ordering no longer matches its named room palette" % type)
		_expect(paths.size() == themes.size(),
			"%s has %d model paths but %d palette labels" % [
				type, paths.size(), themes.size()])

	# Regional floor dressing must remain purpose-built. Re-aliasing one of
	# these to bedroom or bathroom art caused the old purple rug confusion.
	var regional_floor_paths := {}
	for type in ["corridorCarpet", "hotelCarpet", "apartmentCarpet", "beachMat"]:
		for path_value in PropModelCatalog.MODEL_PATHS.get(type, []):
			var path := String(path_value)
			_expect(not path.contains("bedroom_rug") \
				and not path.contains("house_bath_mat"),
				"%s still aliases unrelated floor art: %s" % [type, path])
			_expect(not regional_floor_paths.has(path),
				"regional floor types share the same GLB: %s" % path)
			regional_floor_paths[path] = type

	# Different silhouettes in the same room must resolve to the same finish,
	# even though their individual prop ids differ.
	for room_index in range(12):
		var room_id := "VALIDATE:PALETTE:ROOM:%d" % room_index
		var wood_theme := PropModelCatalog.variant_theme(
			"woodenChair", "CHAIR:%d" % room_index, room_id)
		var computer_theme := PropModelCatalog.variant_theme(
			"retroComputerCompact", "COMPACT:%d" % room_index, room_id)
		var office_theme := PropModelCatalog.variant_theme(
			"officeDesk", "OFFICE:DESK:%d" % room_index, room_id)
		for type in ["woodenChairCushion", "woodenTable",
				"woodenDresserSideboard"]:
			_expect(PropModelCatalog.variant_theme(type,
				"WOOD:%s:%d" % [type, room_index], room_id) == wood_theme,
				"%s breaks the shared wood finish in %s" % [type, room_id])
		for type in ["retroComputerTower", "retroComputerDesktop",
				"retroComputerTerminal"]:
			_expect(PropModelCatalog.variant_theme(type,
				"COMPUTER:%s:%d" % [type, room_index], room_id) == computer_theme,
				"%s breaks the shared computer colour in %s" % [type, room_id])
		for type in ["officeChair", "officeCrtSecurityConsole",
				"officeCubiclePartition", "officePrinter", "officeWaterCooler",
				"officePhotocopier", "officeShredder", "officeFileBoxes",
				"officeCornerWorkstation"]:
			_expect(PropModelCatalog.variant_theme(type,
				"OFFICE:%s:%d" % [type, room_index], room_id) == office_theme,
				"%s breaks the shared office finish in %s" % [type, room_id])

	for type in ["retroComputerCompact", "retroComputerTower",
			"retroComputerDesktop", "retroComputerTerminal"]:
		_expect(RoomCatalog.is_surface_prop(type),
			"%s is not mounted to desks/tables" % type)
		_expect(not RoomCatalog.is_solid(type),
			"%s adds a duplicate collider on top of its desk/table" % type)
		_expect(PropModelCatalog.interaction_for(type) == "use",
			"%s has no use interaction" % type)
		var scene := load(PropModelCatalog.model_path(
			type, "VALIDATE:%s" % type, "VALIDATE:COMPUTER:ROOM")) as PackedScene
		if scene == null:
			continue
		var computer := scene.instantiate() as Node3D
		if computer == null:
			continue
		var bounds := ModelSlot.combined_local_bounds(computer)
		_expect(bounds.size.x >= 1.0 and bounds.size.z >= .58,
			"%s is too small for a usable desk computer: %s" % [type, bounds])
		_expect(bounds.position.y >= -.015 and bounds.position.y <= .015,
			"%s is not surface-flush: minimum y %.3f" % [type, bounds.position.y])
		_expect(.78 + bounds.end.y <= 1.80,
			"%s clips the A-Z hunter head envelope when desk-mounted at %.2fm" % [
				type, .78 + bounds.end.y])
		computer.free()
	print("  palettes  4 wood + 4 computer + 3 office finishes; 10 unique regional textiles")


func _validate_light_fixture_contract() -> void:
	var expected_variants := {
		"floorLamp": 3,
		"ceilingLight": 3,
		"ceilingFan": 3,
		"tableLamp": 3,
		"diningChandelier": 3,
		"wallSconce": 3,
	}
	for type in expected_variants:
		var paths: Array = PropModelCatalog.MODEL_PATHS.get(type, [])
		_expect(paths.size() == int(expected_variants[type]),
			"%s does not expose its three deterministic colour/style variants" % type)
		_expect(not PropModelCatalog.light_profile(type).is_empty(),
			"%s has no runtime illumination profile" % type)
		for path_value in paths:
			var path := String(path_value)
			if not ResourceLoader.exists(path):
				continue
			var scene := load(path) as PackedScene
			if scene == null:
				continue
			var fixture := scene.instantiate() as Node3D
			if fixture == null:
				continue
			var bounds := ModelSlot.combined_local_bounds(fixture)
			if type in ["ceilingLight", "ceilingFan", "diningChandelier"]:
				var mounted_bottom := 3.0 - bounds.end.y + bounds.position.y
				_expect(mounted_bottom >= 2.25,
					"%s clips the 2.20m A-Z hunter envelope at %.2fm" % [
						path.get_file(), mounted_bottom])
			fixture.free()
	print("  lighting  18 fixture variants load, illuminate and clear A-Z hunters")


func _validate_room_door_animation(host: Node) -> void:
	for type in PropModelCatalog.ROOM_DOOR_TYPES:
		var door := RouteInteractable3D.new()
		var door_id := "VALIDATE:%s" % type
		var expected_span := 2 if type.contains("Double") else 1
		door.configure_room_door(door_id,
			PropModelCatalog.model_path(type, door_id), false, false,
			Callable(), expected_span)
		host.get_tree().root.add_child(door)
		await host.get_tree().process_frame
		_expect(door._door_hinge != null,
			"%s has no imported DoorHinge animation pivot" % type)
		_expect(door._door_collision != null and not door._door_collision.disabled,
			"closed %s does not block its doorway" % type)
		if door._door_collision != null \
				and door._door_collision.shape is BoxShape3D:
			var barrier := door._door_collision.shape as BoxShape3D
			_expect(is_equal_approx(barrier.size.x,
				1.92 if expected_span == 2 else .92),
				"%s collision does not span %d grid cell(s)" % [type, expected_span])
		var authored_bounds := ModelSlot.combined_local_bounds(door._visual)
		_expect(authored_bounds.size.x >= (2.05 if expected_span == 2 else 1.05),
			"%s frame is too narrow for its %d-cell opening" % [type, expected_span])
		if door._door_hinge != null:
			var closed_angle := door._door_hinge.rotation.y
			door.apply_room_door_state(true, false)
			door._process(.5)
			await host.get_tree().process_frame
			_expect(absf(angle_difference(closed_angle,
				door._door_hinge.rotation.y)) > deg_to_rad(45.0),
				"%s did not swing open around its hinge" % type)
			_expect(door._door_collision.disabled,
				"open %s still blocks its doorway" % type)
			door.apply_room_door_state(true, true)
			door._process(.5)
			_expect(absf(door._door_hinge.rotation.x) > deg_to_rad(55.0),
				"breached %s did not fall out of its frame" % type)
		if type.contains("Double"):
			_expect(door._door_hinge_right != null,
				"%s has no independently animated second leaf" % type)
		door.queue_free()
		await host.get_tree().process_frame
	print("  doors     6 tall regional doors hinge, close, open and breach")


func _validate_room_model_catalog() -> void:
	var imported := 0
	# Referenced types without a registered model silently disappear at runtime.
	# Reject that state instead of accepting invisible placeholder furniture.
	for room_value in RoomCatalog.TYPES:
		var room: Dictionary = room_value
		for prop_value in room.get("props", []):
			var prop_type := String(prop_value)
			_expect(PropModelCatalog.has_model(prop_type),
				"%s references model-less prop %s" % [
					String(room.get("id", "ROOM")), prop_type])
	for region_value in StreamedRouteGenerator.REGION_PROP_SETS:
		var region := String(region_value)
		for choice_value in StreamedRouteGenerator.REGION_PROP_SETS[region]:
			var choice: Dictionary = choice_value
			var prop_type := String(choice.get("type", ""))
			_expect(PropModelCatalog.has_model(prop_type),
				"%s streamed dressing references model-less prop %s" % [
					region, prop_type])
	for type in PropModelCatalog.MODEL_PATHS:
		for value in PropModelCatalog.MODEL_PATHS[type]:
			var path := String(value)
			_expect(ResourceLoader.exists(path),
				"room prop %s points at missing model %s" % [type, path])
			if not ResourceLoader.exists(path):
				continue
			var scene := load(path) as PackedScene
			_expect(scene != null, "room prop %s is not an imported scene" % path)
			if scene == null:
				continue
			var instance := scene.instantiate()
			_expect(instance is Node3D, "room prop %s has a non-3D root" % path)
			_expect(not instance.find_children("*", "MeshInstance3D", true, false).is_empty(),
				"room prop %s contains no meshes" % path)
			instance.free()
			imported += 1
	for required_type in [
			"restaurantPartyTable", "carnivalTicketBooth", "popcornCart",
			"ringTossStall", "strengthTester", "circusPedestal",
			"carouselCenterpiece", "frozenTidelinePool", "bathroomStall",
			"publicRestroomToilet", "publicMensShowerStall",
			"publicWomensShowerStall", "houseBathtub", "houseToilet",
			"houseShowerEnclosure", "bathroomVanity", "bathroomMirror",
			"retroComputerCompact", "retroComputerTower",
			"retroComputerDesktop", "retroComputerTerminal",
			"officeDesk", "officeChair", "officeCrtSecurityConsole",
			"officeCubiclePartition", "officePrinter", "officeWaterCooler",
			"officePhotocopier", "officeShredder", "officeFileBoxes",
			"officeCornerWorkstation", "prisonCafeteriaTable",
			"prisonServingCounter", "prisonTrayReturn", "prisonKitchenRack",
			"corridorCarpet", "hotelCarpet", "apartmentCarpet", "beachMat",
			"bunkBed",
		]:
		_expect(PropModelCatalog.has_model(required_type),
			"furnished-room prop is not registered: %s" % required_type)
	var party_scene := load(PropModelCatalog.model_path(
		"restaurantPartyTable", "VALIDATE:PARTY")) as PackedScene
	if party_scene != null:
		var party := party_scene.instantiate() as Node3D
		var party_bounds := ModelSlot.combined_local_bounds(party)
		_expect(party_bounds.size.x >= 2.45 and party_bounds.end.y >= 2.0,
			"restaurant party table lost its long table/balloon silhouette: %s" \
			% party_bounds)
		party.free()
	var carousel_scene := load(PropModelCatalog.model_path(
		"carouselCenterpiece", "VALIDATE:CAROUSEL")) as PackedScene
	if carousel_scene != null:
		var carousel := carousel_scene.instantiate() as Node3D
		var carousel_bounds := ModelSlot.combined_local_bounds(carousel)
		_expect(carousel_bounds.end.y >= 6.0 \
			and maxf(carousel_bounds.size.x, carousel_bounds.size.z) >= 5.0,
			"dual-level carousel no longer occupies its authored tall ride volume: %s" \
			% carousel_bounds)
		carousel.free()
	_expect(PropModelCatalog.interaction_for("carouselCenterpiece") == "ride" \
		and PropModelCatalog.interaction_for("ringTossStall") == "play" \
		and PropModelCatalog.interaction_for("strengthTester") == "play",
		"carnival attractions lost their runtime use/ride interactions")
	print("  room art  %d authored GLB variants load as complete 3D scenes" % imported)
