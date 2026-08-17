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
		# GridMap fabric is intentionally opaque. This is independent from the
		# character path below, which must retain authored alpha for hair, wing,
		# and clothing-overlay cards. ArrayMesh only: a PrimitiveMesh's
		# placeholder material is always a freshly-made StandardMaterial3D.
		if mesh is ArrayMesh:
			for surface in mesh.get_surface_count():
				var surface_material := mesh.surface_get_material(surface)
				if surface_material is StandardMaterial3D \
						and (surface_material as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					var fixed: StandardMaterial3D = (surface_material as StandardMaterial3D).duplicate()
					fixed.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					(mesh as ArrayMesh).surface_set_material(surface, fixed)
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
	# Preserve the Blockbench atlas's authored alpha. The old exporter divided
	# UVs by a stale 64x64 project grid instead of the embedded PNG's true atlas
	# height, which made solid faces sample transparent padding and prompted a
	# blanket opaque-material workaround. With atlas UVs fixed, that workaround
	# turns legitimate transparent torso overlays (Eirys/Quirith) into black
	# boxes and hair/wing cards into rectangles.
	return scene.instantiate()


## Finds an AnimationPlayer anywhere under `root` by type — same reasoning as
## _find_mesh_instance: a real character import's AnimationPlayer could be
## named anything. Character controllers call this once, right after
## instantiate(), and keep the result (or null — every placeholder today has
## no AnimationPlayer at all, which is a supported, silent no-op state, not
## an error).
static func find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := find_animation_player(child)
		if found:
			return found
	return null


## Plays `name` on `player` if both exist and it isn't already the current
## animation — safe to call every frame regardless of model complexity. A
## no-op whenever `player` is null or has no clip called `name`, which is
## every placeholder scene as of this writing: dropping in a rigged model
## with clips named per art/props-3d/README.md's convention is the entire
## remaining step to make these calls do something.
static func play_if_available(player: AnimationPlayer, name: String) -> void:
	if player == null or not player.has_animation(name):
		return
	if player.current_animation != name or not player.is_playing():
		player.play(name)


## Crouching currently adds a subdued body fade as a gameplay readability
## choice. Godot's per-instance transparency leaves the shared imported
## mesh/materials alone, including authored alpha-masked hair, overlays, and
## wings; the corrected imported crouch clip remains available independently.
static func set_character_fade(root: Node, amount: float) -> void:
	if root == null:
		return
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).transparency = clampf(amount, 0.0, 0.85)
	for child in root.get_children():
		set_character_fade(child, amount)
