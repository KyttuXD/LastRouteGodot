extends SceneTree

## Compares every authored blocker size (scatter sets + template sizes) with the model it stands in for.
##   godot --headless --path . -s tools/look/collider_audit.gd

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


func _model_box(type: String) -> AABB:
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
	return total if have else AABB()


func _init() -> void:
	var sizes := {}
	for region in StreamedRouteGenerator.REGION_PROP_SETS:
		for entry in StreamedRouteGenerator.REGION_PROP_SETS[region]:
			sizes[String(entry["type"])] = {"size": entry["size"], "solid": bool(entry.get("solid", true)), "src": "scatter:" + String(region)}
	for type in StreamedRouteGenerator.TEMPLATE_PROP_SIZES:
		if not sizes.has(type):
			sizes[String(type)] = {"size": StreamedRouteGenerator.TEMPLATE_PROP_SIZES[type], "solid": true, "src": "template"}
	var decor_solid := []
	var giant := []
	var tiny := []
	var low_tall := []
	var missing := []
	for type in sizes:
		var info: Dictionary = sizes[type]
		var size: Vector3 = info["size"]
		var box := _model_box(String(type))
		if box.size == Vector3.ZERO:
			missing.append(type)
			continue
		var decor := PropModelCatalog.is_floor_dressing(type) or PropModelCatalog.is_wall_mounted(type) or PropModelCatalog.is_ceiling_mounted(type)
		if decor and bool(info["solid"]):
			decor_solid.append(type)
		if not bool(info["solid"]):
			continue
		var dx := size.x - box.size.x
		var dz := size.z - box.size.z
		if maxf(dx, dz) > 0.45:
			giant.append("%s blocker %.2fx%.2f vs model %.2fx%.2f (%s)" % [type, size.x, size.z, box.size.x, box.size.z, info["src"]])
		if minf(dx, dz) < -0.2:
			tiny.append("%s blocker %.2fx%.2f vs model %.2fx%.2f (%s)" % [type, size.x, size.z, box.size.x, box.size.z, info["src"]])
		if absf(size.y - box.size.y) > 0.6:
			low_tall.append("%s blocker h %.2f vs model %.2f" % [type, size.y, box.size.y])
	print("types: ", sizes.size(), " no model: ", missing.size())
	print("decor marked solid (%d): %s" % [decor_solid.size(), decor_solid])
	print("giant (%d):" % giant.size())
	for g in giant: print("  ", g)
	print("tiny (%d):" % tiny.size())
	for g in tiny: print("  ", g)
	print("height mismatch (%d):" % low_tall.size())
	for g in low_tall: print("  ", g)
	quit()
