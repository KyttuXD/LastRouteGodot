extends RefCounted

## Collider quality (DONE12): every solid prop's collision box comes from its model (PropColliderSizes, regenerate with
## tools/props/emit_collider_sizes.gd after changing a model), no decor carries a collider, and what generated chunks hand
## the 3D view matches the table.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _extent(node: Node, parent: Transform3D = Transform3D.IDENTITY) -> AABB:
	var here := parent
	if node is Node3D:
		here = parent * (node as Node3D).transform
	var total := AABB()
	var have := false
	if node is MeshInstance3D:
		total = here * (node as MeshInstance3D).get_aabb()
		have = true
	for child in node.get_children():
		var inner := _extent(child, here)
		if inner.size != Vector3.ZERO:
			total = inner if not have else total.merge(inner)
			have = true
	return total


func run(_host: Node) -> int:
	var stale := 0
	var checked := 0
	for type in PropColliderSizes.SIZES:
		var size: Vector3 = PropColliderSizes.SIZES[type]
		_expect(not PropModelCatalog.is_wall_mounted(type) and not PropModelCatalog.is_ceiling_mounted(type)
			and not PropModelCatalog.is_floor_dressing(type) and not RoomCatalog.is_surface_prop(type),
			"%s is decor (wall/ceiling/floor/surface) but has a collider" % type)
		var paths: Array = BlockyPropModels.MODELS.get(type, [])
		if paths.is_empty():
			paths = PropModelCatalog.MODEL_PATHS.get(type, [])
		var total := AABB()
		var have := false
		for path in paths:
			var scene := load(String(path)) as PackedScene
			if scene == null:
				continue
			var node := scene.instantiate()
			var box := _extent(node)
			node.free()
			total = box if not have else total.merge(box)
			have = true
		if not have:
			continue
		checked += 1
		if absf(size.x - total.size.x) > 0.12 or absf(size.z - total.size.z) > 0.12:
			stale += 1
			print("  FAIL  %s collider %.2f x %.2f is out of date against its model %.2f x %.2f (run tools/props/emit_collider_sizes.gd)" % [
				type, size.x, size.z, total.size.x, total.size.z])
			_failures += 1
		_expect(size.y <= 2.21 and size.y > 0.05, "%s collider height %.2f is out of range" % [type, size.y])
	# chunks hand the derived size to the view
	var generator := StreamedRouteGenerator.new("COLLIDERS")
	var seen := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var data := generator.chunk(Vector3i(dx, 0, dz))
			for prop in data.get("region_props", []):
				var type := String(prop.get("type", ""))
				if bool(prop.get("solid", true)) and not bool(prop.get("room_door", false)) and PropColliderSizes.SIZES.has(type):
					seen += 1
					_expect(prop.get("collider_size") == PropColliderSizes.SIZES[type],
						"%s collider %s ignores the derived collider %s" % [type, prop.get("collider_size"), PropColliderSizes.SIZES[type]])
				if not bool(prop.get("solid", true)) and not bool(prop.get("room_door", false)):
					_expect(not prop.has("occupied_cells") or (prop["occupied_cells"] as Array).is_empty(),
						"non-solid %s occupies cells" % type)
	_expect(seen > 50, "only %d solid props in the sampled chunks" % seen)
	if _failures == 0:
		print("  colliders  %d derived collider boxes match their models, no decor colliders, chunks use them" % checked)
	return _failures
