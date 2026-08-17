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
	var item := RouteInteractable3D.new()
	item.kind = RouteInteractable3D.Kind.HIDING_SPOT
	host.get_tree().root.add_child(item)
	await host.get_tree().process_frame

	var model: Node3D = item._visual
	_expect(model != null, "the hiding-spot route slot did not load its GLB scene")
	if model != null:
		var mesh_nodes := model.find_children("*", "MeshInstance3D", true, false)
		_expect(mesh_nodes.size() >= 25,
			"the locker regressed to %d mesh parts; expected its detailed modular model" \
			% mesh_nodes.size())
		var combined := AABB()
		var has_bounds := false
		var material_names := {}
		for value in mesh_nodes:
			var mesh_node := value as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			var bounds: AABB = mesh_node.global_transform * mesh_node.get_aabb()
			combined = combined.merge(bounds) if has_bounds else bounds
			has_bounds = true
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.mesh.surface_get_material(surface)
				if material != null:
					material_names[material.resource_name] = true
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
