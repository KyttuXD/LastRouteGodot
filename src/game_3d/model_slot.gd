class_name ModelSlot
extends RefCounted

## Loads visuals from art/props-3d/ scene files so gameplay code never
## hardcodes placeholder geometry — swap a slot's .tscn contents for a real
## imported model and the game picks it up with no code changes. See
## art/props-3d/README.md for the required scene structure per use.

## For GridMap items (wall/floor): extracts a Mesh (with the scene's
## surface_material_override baked in, if any — only meaningful for the
## placeholder PrimitiveMeshes; a real imported model's own multi-surface
## materials are already baked into its mesh and need no override) plus the
## MeshInstance3D's own local transform (a Mesh resource has no position of
## its own — e.g. the floor tile's "flush at y=0" offset lives on the node,
## not the mesh, and is lost if you only keep .mesh), and an optional
## collision Shape3D + its local transform, read from the scene's
## MeshInstance3D/CollisionShape3D children. "mesh"/"shape" are null if the
## scene has no such child.
static func load_gridmap_item(scene_path: String) -> Dictionary:
	var result := {
		"mesh": null, "mesh_transform": Transform3D.IDENTITY,
		"shape": null, "shape_transform": Transform3D.IDENTITY,
	}
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_warning("ModelSlot: could not load %s" % scene_path)
		return result

	var instance := scene.instantiate()
	var mesh_instance := _find_mesh_instance(instance)
	if mesh_instance and mesh_instance.mesh:
		var mesh: Mesh = mesh_instance.mesh.duplicate()
		var material := mesh_instance.get_surface_override_material(0)
		if material and mesh is PrimitiveMesh:
			(mesh as PrimitiveMesh).material = material
		result["mesh"] = mesh
		result["mesh_transform"] = mesh_instance.transform

	var collision := _find_collision_shape(instance)
	if collision and collision.shape:
		result["shape"] = collision.shape
		result["shape_transform"] = collision.transform

	instance.queue_free()
	return result


## Matched by type, not node name — a hand-authored placeholder happens to
## name its nodes "MeshInstance3D"/"CollisionShape3D", but a real glTF import
## names them after the source Blender object, so name-matching would break
## the moment a real model is dropped in.
static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null


static func _find_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node
	for child in node.get_children():
		var found := _find_collision_shape(child)
		if found:
			return found
	return null


## For everything else (characters, interactables, standalone props):
## instances the whole scene as-is, so a real model can be as complex as it
## needs to be (skeleton, AnimationPlayer, multiple mesh parts) with no
## assumptions about its internal structure at all.
static func instantiate(scene_path: String) -> Node3D:
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_warning("ModelSlot: could not load %s" % scene_path)
		return null
	return scene.instantiate()
