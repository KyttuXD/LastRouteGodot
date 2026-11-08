extends SceneTree

## Bounding boxes of every blocky variant of the seating/table prop types.
##   godot --headless --path . -s dev/look/prop_dims.gd -- [TYPES_CSV]
func _aabb(node: Node, into: Array, parent: Transform3D = Transform3D.IDENTITY) -> void:
	var here := parent
	if node is Node3D:
		here = parent * (node as Node3D).transform
	if node is MeshInstance3D:
		into.append(here * (node as MeshInstance3D).get_aabb())
	for c in node.get_children():
		_aabb(c, into, here)


func _init() -> void:
	var types := ["woodenChair", "woodenChairCushion", "diningChair", "diningChairCushion", "woodenTable", "diningTable",
		"restaurantPartyTable", "officeChair", "officeDesk", "normalCoffeeTable", "vanityStool", "bedroomBench", "normalEntryBench",
		"mansionConsoleTable", "gothicHighbackChair", "gothicPedestalTable", "gothicWritingDesk", "gothicVanityStool"]
	if OS.get_cmdline_user_args().size() > 0:
		types = Array(OS.get_cmdline_user_args()[0].split(","))
	for type in types:
		var paths: Array = BlockyPropModels.MODELS.get(type, [])
		if paths.is_empty():
			paths = PropModelCatalog.MODEL_PATHS.get(type, [])
		var lines := []
		for path in paths:
			var scene := load(String(path)) as PackedScene
			if scene == null:
				continue
			var node := scene.instantiate()
			var boxes := []
			_aabb(node, boxes)
			var total: AABB = boxes[0] if not boxes.is_empty() else AABB()
			for b in boxes:
				total = total.merge(b)
			lines.append("%.2fx%.2fx%.2f" % [total.size.x, total.size.y, total.size.z])
			node.free()
		var unique := {}
		for l in lines:
			unique[l] = int(unique.get(l, 0)) + 1
		print("%-22s %s" % [type, unique])
	quit()
