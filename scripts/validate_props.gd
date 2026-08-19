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


func _validate_room_door_animation(host: Node) -> void:
	for type in PropModelCatalog.ROOM_DOOR_TYPES:
		var door := RouteInteractable3D.new()
		var door_id := "VALIDATE:%s" % type
		door.configure_room_door(door_id,
			PropModelCatalog.model_path(type, door_id), false, false)
		host.get_tree().root.add_child(door)
		await host.get_tree().process_frame
		_expect(door._door_hinge != null,
			"%s has no imported DoorHinge animation pivot" % type)
		_expect(door._door_collision != null and not door._door_collision.disabled,
			"closed %s does not block its doorway" % type)
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
		door.queue_free()
		await host.get_tree().process_frame
	print("  doors     3 regional doors hinge, close, open and breach")


func _validate_room_model_catalog() -> void:
	var imported := 0
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
	print("  room art  %d authored GLB variants load as complete 3D scenes" % imported)
