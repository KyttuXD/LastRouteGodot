class_name PropMeshMerge
extends RefCounted

## Perf: a static prop model drawn as one mesh per material instead of one MeshInstance3D per part.
## The sewer kit (tools/props/rebuild_hytale_props.py SEWER_BUILDERS) builds every bridge slat, pipe clamp, lamp cage bar
## and ladder rung as its own glTF node, so ~1500 of a route's ~2050 prop meshes were sewer parts: a bridge alone was 48
## draw calls (and 48 shadow-pass draws), a lamp 11. Merged, a bridge or lamp is one draw per material it uses.
##
## The merged ArrayMesh is built once per model (same parts, same shared materials) and reused by every copy, so the
## SurfaceTool work is paid for the first bridge only. Nothing else about the prop changes: its root, metas, groups,
## colliders, seats and hide spots stay; the merged geometry sits in the root's own space, so bounds, seat/mattress tops
## and the sewer bridge deck scan read the same faces. Visibility ranges are applied after this by the view (owns
## those numbers); materials are the already graded, shared ones (no glow or material change).
##
## Left alone: props whose parts move (sluice gate leaf, valve wheel), parts with children (lights, particles, attach
## points), hidden parts, skinned or blend-shape meshes, non-triangle surfaces and alpha-blended surfaces (their draw order
## matters). Ladder rungs keep an empty Node3D marker under their name, which PlayerController3D.find_ladder_rungs reads.

## Switch for A/B measurements (tests/validate_prop_perf.gd).
static var enabled := true
## Props a script rigs by part name after spawning (StreamedFacilityView3D._rig_gate / _rig_valve).
const NEVER_MERGE := ["sewerSluiceGate", "sewerValveWheel"]
## Part names other code looks up after the merge: an empty marker keeps the transform.
const MARKER_PREFIXES := ["Rung", "LadderRung_"]

static var _cache := {}
static var _watching: bool = ContentRegistry.watch(clear_cache)
## Counters for the perf note: parts folded away and merged meshes made.
static var merged_parts := 0
static var merged_meshes := 0


static func clear_cache() -> void:
	_cache.clear()


static func _mergeable(mesh_node: MeshInstance3D) -> bool:
	if mesh_node.mesh == null or not mesh_node.visible or mesh_node.get_child_count() > 0:
		return false
	if mesh_node.skin != null or not mesh_node.skeleton.is_empty() or mesh_node.mesh.get_blend_shape_count() > 0:
		return false
	for surface in mesh_node.mesh.get_surface_count():
		if mesh_node.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var material := mesh_node.get_active_material(surface)
		if material is BaseMaterial3D and (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			return false
	return true


## The draw settings that must match for parts to share one instance.
static func _bucket_key(mesh_node: MeshInstance3D) -> String:
	return "%d|%d|%d|%.3f|%d" % [mesh_node.cast_shadow, mesh_node.layers, mesh_node.gi_mode, mesh_node.transparency,
		int(mesh_node.ignore_occlusion_culling)]


static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	return xf


## Every ancestor up to the root is visible (the root's own flag is the maze cull's and stays its business).
static func _shown_under(root: Node3D, node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D and not (parent as Node3D).visible:
			return false
		parent = parent.get_parent()
	return true


static func _is_marker(name_text: String) -> bool:
	for prefix in MARKER_PREFIXES:
		if name_text.begins_with(prefix):
			return true
	return false


## Folds `visual`'s static parts into merged meshes. Returns the number of MeshInstance3D nodes removed.
static func merge(visual: Node3D, prop_type: String, model_path: String) -> int:
	if not enabled or visual == null or prop_type in NEVER_MERGE:
		return 0
	var parts: Array[MeshInstance3D] = []
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if _mergeable(mesh_node) and _shown_under(visual, mesh_node):
			parts.append(mesh_node)
	if parts.size() < 2:
		return 0
	# bucket -> parts; the cache key names every part's mesh, materials and placement so a different variant never reuses
	var buckets := {}
	var bucket_order: Array = []
	var key_parts := PackedStringArray([model_path, prop_type])
	for mesh_node in parts:
		var bucket := _bucket_key(mesh_node)
		if not buckets.has(bucket):
			buckets[bucket] = []
			bucket_order.append(bucket)
		(buckets[bucket] as Array).append(mesh_node)
		var materials := PackedStringArray()
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface)
			materials.append(str(material.get_rid().get_id()) if material != null else "-")
		# each copy of a glTF model gets its own Mesh resources, so a part is named by its node path, size and surfaces
		key_parts.append("%s|%s|%s|%d|%s|%s" % [bucket, visual.get_path_to(mesh_node), mesh_node.mesh.get_aabb(),
			mesh_node.mesh.get_surface_count(), ",".join(materials), _relative(visual, mesh_node)])
	var cache_key := "\n".join(key_parts).sha256_text()
	var meshes: Dictionary = _cache.get(cache_key, {})
	if meshes.is_empty():
		for bucket in bucket_order:
			meshes[bucket] = _build(visual, buckets[bucket])
		_cache[cache_key] = meshes
	var removed := 0
	for bucket in bucket_order:
		var bucket_parts: Array = buckets[bucket]
		var first := bucket_parts[0] as MeshInstance3D
		var merged := MeshInstance3D.new()
		merged.name = "MergedProp%d" % bucket_order.find(bucket)
		merged.mesh = meshes[bucket]
		merged.cast_shadow = first.cast_shadow
		merged.layers = first.layers
		merged.gi_mode = first.gi_mode
		merged.transparency = first.transparency
		merged.ignore_occlusion_culling = first.ignore_occlusion_culling
		merged.lod_bias = first.lod_bias
		merged.extra_cull_margin = first.extra_cull_margin
		visual.add_child(merged)
		for part_value in bucket_parts:
			var part := part_value as MeshInstance3D
			var holder := part.get_parent()
			if _is_marker(String(part.name)):
				var marker := Node3D.new()
				marker.transform = part.transform
				holder.add_child(marker)
				holder.move_child(marker, part.get_index())
				holder.remove_child(part)
				marker.name = part.name
			else:
				holder.remove_child(part)
			part.free()
			removed += 1
	merged_parts += removed
	merged_meshes += bucket_order.size()
	return removed


## One surface per material across the bucket's parts, in the visual root's space.
static func _build(visual: Node3D, bucket_parts: Array) -> ArrayMesh:
	var tools := {}
	var order: Array = []
	for part_value in bucket_parts:
		var part := part_value as MeshInstance3D
		var xf := _relative(visual, part)
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface)
			if not tools.has(material):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material] = tool
				order.append(material)
			(tools[material] as SurfaceTool).append_from(part.mesh, surface, xf)
	var mesh := ArrayMesh.new()
	for material in order:
		(tools[material] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh
