extends Node

## Measures the player mannequin (height, eye, shoulder, hip, knee, hand) and prints every prop collider footprint with its
## type, for the scale-fit table (docs/SCALE_FIT.md).
##
##   godot --headless --path . res://tools/look/scale_measure.tscn

func _ready() -> void:
	var body := (load(PlayerModels.SCENE) as PackedScene).instantiate() as Node3D
	add_child(body)
	await get_tree().process_frame
	var box := _extent(body)
	print("PLAYER scene=%s aabb_min=%s aabb_size=%s" % [PlayerModels.SCENE, box.position, box.size])
	for skel in body.find_children("*", "Skeleton3D", true, false):
		var s := skel as Skeleton3D
		for i in s.get_bone_count():
			var p := s.global_transform * s.get_bone_global_rest(i).origin
			print("BONE %s y=%.3f x=%.3f z=%.3f" % [s.get_bone_name(i), p.y, p.x, p.z])
	for n in body.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower()
		if nm.contains("eye") or nm.contains("hand") or nm.contains("head"):
			print("NODE %s y=%.3f" % [n.name, (n as Node3D).global_position.y])
	for type in PropColliderSizes.SIZES:
		var v: Vector3 = PropColliderSizes.SIZES[type]
		print("PROP %s %.2f %.2f %.2f" % [type, v.x, v.y, v.z])
	get_tree().quit(0)


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
