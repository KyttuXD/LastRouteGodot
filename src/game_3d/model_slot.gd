class_name ModelSlot
extends RefCounted

## Props imported from the same GLB share source materials. The visual contract
## below is also identical for every instance, so retain one filtered duplicate
## per source RID instead of allocating and compiling another material every
## time streamed terrain brings a couch, locker or pickup into view.
static var _pixel_material_cache := {}
static var _blocky_prop_material_cache := {}

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
	var instance := scene.instantiate() as Node3D
	if instance != null:
		_enable_stable_texture_filtering(instance)
		# Every imported gameplay model shares one pixel-material contract. This
		# covers characters as before, plus relays, lockers, pickups, tools,
		# furniture and future authored interactables without each spawning class
		# needing to remember a second setup call.
		apply_prop_pixel_filter(instance)
	return instance


## Prop-only companion to instantiate(). Character materials keep their
## authored per-pixel lighting; furniture, pickups and interactables use
## coarser vertex lighting and a matte response so their low-poly faces read
## like the block characters and room fabric without rewriting every GLB.
static func instantiate_prop(scene_path: String) -> Node3D:
	var instance := instantiate(scene_path)
	if instance != null:
		apply_blocky_prop_style(instance)
	return instance


static func _enable_stable_texture_filtering(node: Node) -> void:
	# Imported low-resolution atlases are still deliberately nearest-filtered
	# close up, but need mipmaps/anisotropy to avoid crawling striped moire on
	# props and characters as the first-person camera moves.
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface)
				if material is StandardMaterial3D:
					(material as StandardMaterial3D).texture_filter = \
						BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	for child in node.get_children():
		_enable_stable_texture_filtering(child)


## Streamed dressing gets the strongest pixel treatment at material level,
## while walls/floors/stairs retain anisotropic filtering for stable motion.
## Mipmaps remain enabled so a distant couch or rug does not recreate the
## camera-motion moire that plain nearest sampling caused.
static func apply_prop_pixel_filter(node: Node) -> void:
	if node.has_meta("pixel_material_filter_applied"):
		return
	node.set_meta("pixel_material_filter_applied", true)
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var source := mesh_node.get_active_material(surface)
				if source is StandardMaterial3D:
					var source_material := source as StandardMaterial3D
					var key := source_material.get_rid()
					var material := _pixel_material_cache.get(key) as StandardMaterial3D
					if material == null:
						material = source_material.duplicate() as StandardMaterial3D
						material.texture_filter = \
							BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
						material.roughness = maxf(material.roughness, .72)
						_pixel_material_cache[key] = material
					mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		apply_prop_pixel_filter(child)


static func apply_blocky_prop_style(node: Node) -> void:
	if node.has_meta("blocky_prop_style_applied"):
		return
	node.set_meta("blocky_prop_style_applied", true)
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var source := mesh_node.get_active_material(surface)
				if source is StandardMaterial3D:
					var source_material := source as StandardMaterial3D
					var key := source_material.get_rid()
					var material := _blocky_prop_material_cache.get(key) \
						as StandardMaterial3D
					if material == null:
						material = source_material.duplicate() as StandardMaterial3D
						# Per-vertex lighting preserves the flashlight and regional
						# colour while eliminating the smooth/plastic gradient which
						# made authored props clash with block characters.
						material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
						# Keep a little margin above the validation threshold because
						# StandardMaterial stores this property at float precision.
						material.roughness = maxf(material.roughness, .92)
						_blocky_prop_material_cache[key] = material
					mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		apply_blocky_prop_style(child)


## Thin horizontal meshes can be reduced out of an imported mesh's generated
## LOD, or rejected by conservative occlusion bounds, while the room around
## them is still plainly visible. Rugs are sparse and never cast a useful
## shadow, so preserve their full mesh through normal room/corridor distances.
static func keep_floor_dressing_visible(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.lod_bias = 4.0
		geometry.extra_cull_margin = maxf(geometry.extra_cull_margin, 6.0)
		geometry.ignore_occlusion_culling = true
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		keep_floor_dressing_visible(child)


## Combined bounds in a model root's local space. Walking local transforms
## keeps this usable before a PackedScene is attached to the live tree.
static func combined_local_bounds(root: Node3D) -> AABB:
	var state := {"found": false, "bounds": AABB()}
	_collect_local_bounds(root, Transform3D.IDENTITY, state)
	return state["bounds"]


static func _collect_local_bounds(node: Node, relative: Transform3D,
		state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var box := relative * mesh_node.get_aabb()
			state["bounds"] = (state["bounds"] as AABB).merge(box) \
				if bool(state["found"]) else box
			state["found"] = true
	for child in node.get_children():
		var child_transform := relative
		if child is Node3D:
			child_transform = relative * (child as Node3D).transform
		_collect_local_bounds(child, child_transform, state)


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


## Optional per-player colour identity. Zero means the authored texture is
## untouched; 1..360 lightly tints instance-local material duplicates. Admin
## bodies deliberately never call this, preserving their hardcoded skin.
static func apply_character_hue(root: Node, hue_degrees: float) -> void:
	if root == null or hue_degrees <= 0.0:
		return
	var tint := Color.from_hsv(clampf((hue_degrees - 1.0) / 359.0, 0.0, 1.0),
		0.24, 1.0, 1.0)
	_apply_hue_recursive(root, tint)


static func _apply_hue_recursive(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var source := mesh_node.get_active_material(surface)
				if source is StandardMaterial3D:
					var material := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
					var base := material.albedo_color
					material.albedo_color = Color(
						lerpf(base.r, base.r * tint.r, .38),
						lerpf(base.g, base.g * tint.g, .38),
						lerpf(base.b, base.b * tint.b, .38), base.a)
					mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_apply_hue_recursive(child, tint)
