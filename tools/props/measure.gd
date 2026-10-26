extends Node

## Writes the footprint of every catalogued prop model (first variant) to
## OUT/prop_bounds.json so the blocky rebuild matches each prop's size exactly.
##   godot --headless --path . res://tools/props/measure.tscn -- OUTDIR

func _ready() -> void:
	var out_dir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var result := {}
	for type in PropModelCatalog.MODEL_PATHS:
		var paths: Array = PropModelCatalog.MODEL_PATHS[type]
		if paths.is_empty():
			continue
		var node: Node3D = ModelSlot.instantiate(String(paths[0]))
		if node == null:
			continue
		add_child(node)
		var box := ModelSlot.combined_local_bounds(node)
		result[type] = {"path": String(paths[0]), "variants": paths.size(),
			"size": [box.size.x, box.size.y, box.size.z],
			"center": [box.get_center().x, box.get_center().z], "min_y": box.position.y}
		node.queue_free()
	var f := FileAccess.open(out_dir.path_join("prop_bounds.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	get_tree().quit()
