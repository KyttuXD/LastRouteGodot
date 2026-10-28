class_name ModelSlot
extends RefCounted

## Props imported from the same GLB share source materials. The visual contract
## below is also identical for every instance, so retain one filtered duplicate
## per source RID instead of allocating and compiling another material every
## time streamed terrain brings a couch, locker or pickup into view.
static var _pixel_material_cache := {}
static var _blocky_prop_material_cache := {}
## Every blocky prop GLB (art/props-3d/props/blocky) carries its own extracted copy of the same 128x64 pixel atlas (the builder is
## deterministic and scripts/validate_props_rework.gd checks the size), so keying the material caches by the source material's RID gave
## each of the ~600 models its own materials (and two duplicates each). Their atlas is keyed by name instead, so all of them share one
## material per style profile. No pixels are read back: Texture2D.get_image() on a GPU texture stalls the renderer.
const BLOCKY_ATLAS_DIR := "res://art/props-3d/props/blocky/"
## Switch for A/B measurements (tools/look/prop_perf.gd): false gives every model its own materials again.
static var share_blocky_materials := true

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
	# turns legitimate transparent torso overlays (Elise/Quenelle) into black
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


## Hunter visual: the 2D billboard cutout when the identity (HunterRoster.get_identity)
## carries sprite paths, otherwise the rigged 3D model. Callers get a Node3D that
## behaves the same either way: an AnimationPlayer with the usual clip names, and
## a "Head" node when the model has one.
static func instantiate_hunter(identity: Dictionary) -> Node3D:
	var front := String(identity.get("sprite_front", ""))
	if not front.is_empty():
		var sprite := SpriteBillboard.create(front, String(identity.get("sprite_back", "")))
		if sprite != null:
			return sprite
	var model := instantiate(String(identity.get("model_scene", "")))
	if model != null:
		# data-driven rig add-ons (extra bones, parts, held props): docs/HUNTER_ADDONS.md
		HunterAddons.mount(model, String(identity.get("id", "")))
	return model


## Prop-only companion to instantiate(). Character materials keep their
## authored per-pixel lighting; furniture, pickups and interactables use
## coarser vertex lighting and a matte response so their low-poly faces read
## like the block characters and room fabric without rewriting every GLB.
static func instantiate_prop(scene_path: String, style_hint: String = "") -> Node3D:
	var instance := instantiate(scene_path)
	if instance != null:
		apply_blocky_prop_style(instance,
			style_hint if not style_hint.is_empty() else scene_path)
		# hunter-scale rescale (PropModelCatalog.HUNTER_SCALE): scaling the children keeps the root free for the
		# view's yaw and position, and the local bounds everyone measures include it
		var factor := PropModelCatalog.hunter_scale(style_hint)
		if factor != 1.0:
			for child in instance.get_children():
				if child is Node3D:
					(child as Node3D).transform = Transform3D(Basis.from_scale(Vector3.ONE * factor), Vector3.ZERO) * (child as Node3D).transform
	return instance


static func _enable_stable_texture_filtering(node: Node) -> void:
	# Imported low-resolution atlases are still deliberately nearest-filtered
	# close up. Opaque surfaces keep mipmaps/anisotropy to avoid crawling
	# striped moire. Alpha-scissor cutouts cannot: mipmaps average opaque
	# pixels with atlas padding and the MASK test then discards whole faces.
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface)
				if material is StandardMaterial3D:
					var standard := material as StandardMaterial3D
					standard.texture_filter = \
						BaseMaterial3D.TEXTURE_FILTER_NEAREST \
						if standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
						else BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	for child in node.get_children():
		_enable_stable_texture_filtering(child)


## Streamed dressing gets the strongest pixel treatment at material level,
## while walls/floors/stairs retain anisotropic filtering for stable motion.
## Mipmaps remain enabled so a distant couch or rug does not recreate the
## camera-motion moire that plain nearest sampling caused.
## Content key of a material: the shared blocky atlas (any GLB) gives one key, everything else keeps its own resource identity.
static func material_content_key(source: StandardMaterial3D) -> String:
	var texture_key := "none"
	var texture := source.albedo_texture
	if texture != null:
		var path := texture.resource_path
		if share_blocky_materials and path.begins_with(BLOCKY_ATLAS_DIR) and path.ends_with("_BlockyAtlas.png") \
				and texture.get_size() == Vector2(128, 64):
			texture_key = "blocky_atlas"
		else:
			texture_key = "rid%d" % texture.get_rid().get_id()
	else:
		texture_key = "mat%d" % source.get_rid().get_id()
	# the name keeps trim / hardware / inset reads apart now that matte-ing makes their roughness and metallic identical
	return "%s|%s|%.3f|%.3f|%d|%d|%d|%s|%s" % [texture_key, source.albedo_color.to_html(true), source.roughness, source.metallic,
		source.transparency, source.cull_mode, source.shading_mode, str(source.emission_enabled), source.resource_name]


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
					var key := material_content_key(source_material)
					var material := _pixel_material_cache.get(key) as StandardMaterial3D
					if material == null:
						material = source_material.duplicate() as StandardMaterial3D
						# MASK + mipmaps is what made hunters flicker out under the
						# flashlight: a 64px atlas's unused padding dilutes alpha in
						# every coarser mip, then the default 0.5 scissor drops the
						# face. Cutouts stay nearest-only; opaque dressing keeps mips.
						material.texture_filter = \
							BaseMaterial3D.TEXTURE_FILTER_NEAREST \
							if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
							else BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
						MaterialLook.tame(material)
						_pixel_material_cache[key] = material
					mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		apply_prop_pixel_filter(child)


static func apply_blocky_prop_style(node: Node, style_hint: String = "") -> void:
	if node.has_meta("blocky_prop_style_applied"):
		return
	node.set_meta("blocky_prop_style_applied", true)
	if style_hint.is_empty() and node.has_meta("blocky_prop_style_hint"):
		style_hint = String(node.get_meta("blocky_prop_style_hint"))
	elif not style_hint.is_empty():
		node.set_meta("blocky_prop_style_hint", style_hint)
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var source := mesh_node.get_active_material(surface)
				if source is StandardMaterial3D:
					var source_material := source as StandardMaterial3D
					var profile_key := _blocky_style_key(style_hint)
					var key := "%s|%s" % [material_content_key(source_material), profile_key]
					var material := _blocky_prop_material_cache.get(key) \
						as StandardMaterial3D
					if material == null:
						material = source_material.duplicate() as StandardMaterial3D
						# Per-vertex lighting preserves the flashlight and regional
						# colour while eliminating the smooth/plastic gradient which
						# made authored props clash with block characters.
						material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
						_apply_blocky_style_profile(material, profile_key)
						MaterialLook.tame(material)
						_blocky_prop_material_cache[key] = material
					mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		apply_blocky_prop_style(child, style_hint)


static func _blocky_style_key(style_hint: String) -> String:
	var hint := style_hint.to_lower()
	if _hint_has_any(hint, ["relay", "locked_relay", "signal_relay"]):
		return "relay"
	if _hint_has_any(hint, ["door", "boarded", "gate"]):
		return "door"
	if _hint_has_any(hint, ["locker", "filingcabinet", "photocopier", "shredder",
			"watercooler", "serverrack", "vendingmachine", "computer", "printer",
			"terminal", "switch", "manifold"]):
		return "machine"
	if _hint_has_any(hint, ["carpet", "rug", "mat", "pool", "tideline"]):
		return "floor_dressing"
	if _hint_has_any(hint, ["desk", "table", "nightstand", "wardrobe", "dresser",
			"sideboard", "bookcase", "bench", "chair", "couch", "tvconsole",
			"booth", "stall", "bar", "rack", "crate"]):
		return "furniture"
	if _hint_has_any(hint, ["inferno", "lava", "ember", "magma", "basalt",
			"brazier", "crystal", "altar"]):
		return "inferno"
	return "default"


static func _apply_blocky_style_profile(material: StandardMaterial3D,
		profile_key: String) -> void:
	match profile_key:
		"relay":
			material.roughness = maxf(material.roughness, .58)
			material.metallic = maxf(material.metallic, .38)
			if material.emission_enabled:
				material.emission_energy_multiplier = maxf(
					material.emission_energy_multiplier, 1.25)
		"door":
			material.roughness = maxf(material.roughness, .72)
			material.metallic = maxf(material.metallic, .18)
		"machine":
			material.roughness = maxf(material.roughness, .74)
			material.metallic = maxf(material.metallic, .24)
		"floor_dressing":
			material.roughness = maxf(material.roughness, .97)
			material.metallic = 0.0
		"furniture":
			material.roughness = maxf(material.roughness, .88)
			material.metallic = maxf(material.metallic, .04)
		"inferno":
			material.roughness = maxf(material.roughness, .82)
			material.metallic = maxf(material.metallic, .14)
			if material.emission_enabled:
				material.emission_energy_multiplier = maxf(
					material.emission_energy_multiplier, 1.18)
		_:
			# Keep a little margin above the validation threshold because
			# StandardMaterial stores this property at float precision.
			material.roughness = maxf(material.roughness, .92)


static func _hint_has_any(hint: String, needles: Array) -> bool:
	for value in needles:
		if hint.contains(String(value)):
			return true
	return false


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
		if mesh_node.mesh != null and not HunterAddons.is_addon(mesh_node):
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


## Crouching and stealth silhouettes use per-instance transparency so the
## shared imported mesh stays untouched. ALPHA_SCISSOR (the Blockbench MASK
## import) still has to leave the scissor path while faded: Godot multiplies
## instance transparency into fragment alpha *before* the cutoff, so a 0.62 /
## 0.72 ghost (remaining 0.38 / 0.28) is discarded by the default 0.5
## threshold and the hunter renders as nothing. Unique ALPHA overrides keep
## the authored cutouts on the shared material and only exist while faded.
static func set_character_fade(root: Node, amount: float) -> void:
	if root == null:
		return
	var fade := clampf(amount, 0.0, 0.85)
	if root is GeometryInstance3D:
		var geometry := root as GeometryInstance3D
		geometry.transparency = fade
		_apply_fade_material_mode(geometry, fade)
	for child in root.get_children():
		set_character_fade(child, fade)


## True when `amount` would still produce visible fragments on this model.
## Used by validation so a GeometryInstance3D.transparency assignment cannot
## pass while ALPHA_SCISSOR is still throwing every faded pixel away.
static func fade_survives_alpha_test(root: Node, amount: float) -> bool:
	if root == null:
		return false
	var remaining := 1.0 - clampf(amount, 0.0, 0.85)
	if remaining <= 0.001:
		return false
	var found_material := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh != null:
				for surface in mesh_node.mesh.get_surface_count():
					var material := mesh_node.get_active_material(surface)
					if not material is StandardMaterial3D:
						continue
					found_material = true
					var standard := material as StandardMaterial3D
					if standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
							and remaining + 0.001 < standard.alpha_scissor_threshold:
						return false
		for child in node.get_children():
			stack.append(child)
	return found_material


static func _apply_fade_material_mode(geometry: GeometryInstance3D, fade: float) -> void:
	if not geometry is MeshInstance3D:
		return
	var mesh_node := geometry as MeshInstance3D
	if mesh_node.mesh == null:
		return
	if fade <= 0.001:
		_restore_fade_materials(mesh_node)
		return
	if mesh_node.has_meta("character_fade_armed"):
		return
	var originals: Array = []
	for surface in mesh_node.mesh.get_surface_count():
		var previous := mesh_node.get_surface_override_material(surface)
		originals.append(previous)
		var source := mesh_node.get_active_material(surface)
		if source is StandardMaterial3D \
				and (source as StandardMaterial3D).transparency \
					== BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			var faded := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
			faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_node.set_surface_override_material(surface, faded)
	mesh_node.set_meta("character_fade_armed", true)
	mesh_node.set_meta("character_fade_originals", originals)


static func _restore_fade_materials(mesh_node: MeshInstance3D) -> void:
	if not mesh_node.has_meta("character_fade_armed"):
		return
	var originals: Array = mesh_node.get_meta("character_fade_originals", [])
	var surface_count := mesh_node.mesh.get_surface_count() if mesh_node.mesh != null else 0
	for surface in mini(originals.size(), surface_count):
		mesh_node.set_surface_override_material(surface, originals[surface])
	mesh_node.remove_meta("character_fade_armed")
	mesh_node.remove_meta("character_fade_originals")


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
