extends Node

## Every catalog prop's in-game size as the view spawns it (ModelSlot.instantiate_prop, hunter scale included): the
## union of its variants' mesh bounds, plus its mount (floor, wall, ceiling, surface). Writes JSON for the size table
## (tools/props/prop_size_table.py).
##   godot --headless --path . res://tools/props/dump_prop_sizes.tscn -- /tmp/prop_sizes.json


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "/tmp/prop_sizes.json"
	var types := {}
	for type in PropModelCatalog.MODEL_PATHS:
		types[String(type)] = true
	for type in BlockyPropModels.MODELS:
		types[String(type)] = true
	var out := {}
	for type in types:
		var paths: Array = BlockyPropModels.MODELS.get(type, [])
		if paths.is_empty():
			paths = PropModelCatalog.MODEL_PATHS.get(type, [])
		var total := AABB()
		var have := false
		for path in paths:
			if not ResourceLoader.exists(String(path)):
				continue
			var node := ModelSlot.instantiate_prop(String(path), type)
			if node == null:
				continue
			var box := ModelSlot.combined_local_bounds(node)
			node.free()
			if box.size == Vector3.ZERO:
				continue
			total = box if not have else total.merge(box)
			have = true
		if not have:
			continue
		var mount := "floor"
		if PropModelCatalog.is_wall_mounted(type):
			mount = "wall"
		elif PropModelCatalog.is_ceiling_mounted(type):
			mount = "ceiling"
		elif RoomCatalog.is_surface_prop(type):
			mount = "surface"
		elif PropModelCatalog.is_floor_dressing(type):
			mount = "floor_dressing"
		out[type] = {"x": snappedf(total.size.x, .01), "y": snappedf(total.size.y, .01), "z": snappedf(total.size.z, .01),
			"mount": mount, "scale": PropModelCatalog.hunter_scale(type),
			"collider": PropColliderSizes.SIZES.has(type), "interaction": PropModelCatalog.interaction_for(type)}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t", true))
	file.close()
	print("PROPSIZES wrote %d props to %s" % [out.size(), out_path])
	get_tree().quit()
