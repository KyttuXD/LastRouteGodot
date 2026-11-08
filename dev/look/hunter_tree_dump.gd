extends Node

## Every mesh a live HunterView3D draws, with its parent and world position relative to the Head pivot (finds geometry the model file
## does not have). HUNTER=dovelle godot --headless --path . res://dev/look/hunter_tree_dump.tscn

func _ready() -> void:
	var id := OS.get_environment("HUNTER") if OS.get_environment("HUNTER") != "" else "dovelle"
	var brain := HunterBrain.new(Vector2.ZERO, "DUMP", id, "standard")
	brain.activate_at(Vector2.ZERO)
	var view := HunterView3D.new()
	view.brain = brain
	add_child(view)
	view.sync_from_brain()
	for i in 20:
		await get_tree().process_frame
	var head := view.find_child("Head", true, false) as Node3D
	for node in view.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		var box := m.get_aabb()
		print("MESH %-22s parent %-14s vis %s  rel head %s  size %s" % [m.name, m.get_parent().name, m.is_visible_in_tree(),
			(m.global_position - head.global_position).snapped(Vector3(0.01, 0.01, 0.01)), box.size.snapped(Vector3(0.01, 0.01, 0.01))])
	for node in view.find_children("*", "CSGShape3D", true, false) + view.find_children("*", "Sprite3D", true, false) + view.find_children("*", "Decal", true, false):
		print("OTHER %s %s" % [node.get_class(), node.get_path()])
	get_tree().quit()
