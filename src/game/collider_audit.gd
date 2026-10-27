class_name ColliderAudit
extends RefCounted

## Collider-vs-mesh audit (docs/COLLISION.md). For every solid prop type, every model variant and the four yaws the
## generator uses, compares the footprint of the mesh the view really spawns (pivot, yaw + PI visual turn, ground-seated)
## with the collision box the view places at the prop's position (PropColliderSizes, rotated by the gameplay yaw).
##   oversize   the box is wider than the visible mesh on an axis (invisible wall)
##   undersize  the box is narrower than the mesh (walk-through model)
##   offset     the mesh footprint is not centred on the box (box beside the model)
## A type may carry several boxes (PropColliderSizes.EXTRA_BOXES for L-shaped or irregular pieces); the audit then
## measures how much of the mesh footprint the union covers and how much box area lies outside the mesh footprint.

const TOLERANCE := 0.13        ## relative; the task allows 10-15%
const MIN_ABS := 0.06          ## and at least this many metres, so 4 cm padding never trips a small prop
const YAWS := [0.0, PI * .5, PI, PI * 1.5]


static func variant_paths(type: String) -> Array:
	return PropColliderBoxes.variant_paths(type)


## Footprint of one spawned variant in the prop's own frame (x, z), as Rect2, plus the height. Empty Rect2 when the model is missing.
static func variant_footprint(path: String, type: String) -> Dictionary:
	var visual := ModelSlot.instantiate_prop(path, type)
	if visual == null:
		return {}
	var bounds := ModelSlot.combined_local_bounds(visual)
	visual.free()
	if bounds.size == Vector3.ZERO:
		return {}
	return {"rect": Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z), "height": bounds.size.y}


## The mesh footprint after the view's visual yaw (yaw + PI) expressed in the collider frame (collider turned by `yaw`):
## the relative turn is PI, so a footprint is mirrored through the pivot.
static func in_collider_frame(rect: Rect2) -> Rect2:
	return Rect2(-rect.end.x, -rect.end.y, rect.size.x, rect.size.y)


static func boxes_for(type: String, variant: int = -1) -> Array:
	var out := []
	var size: Vector3 = PropColliderSizes.SIZES.get(type, Vector3.ZERO)
	if size == Vector3.ZERO:
		return out
	for box in PropColliderBoxes.boxes(type, size, variant):
		out.append(Rect2((box["c"] as Vector2) - (box["h"] as Vector2), (box["h"] as Vector2) * 2.0))
	return out


## Top-down occupancy of one spawned variant: centres of the OCC_STEP cells any triangle above the floor reaches, in the
## collider frame. Measures coverage of the mesh itself, so an L-shaped desk is not judged against its bounding box.
const OCC_STEP := 0.06


static func occupancy(path: String, type: String) -> Array:
	var visual := ModelSlot.instantiate_prop(path, type)
	if visual == null:
		return []
	var cells := {}
	var bounds := ModelSlot.combined_local_bounds(visual)
	_rasterise(visual, Transform3D.IDENTITY, bounds.position.y + 0.05, cells)
	visual.free()
	var out := []
	for key in cells:
		var k: Vector2i = key
		out.append(-(Vector2(k) + Vector2(.5, .5)) * OCC_STEP)
	return out


static func _rasterise(node: Node, parent: Transform3D, floor_y: float, cells: Dictionary) -> void:
	var here := parent
	if node is Node3D:
		here = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var faces := mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = faces[Mesh.ARRAY_VERTEX]
			var index = faces[Mesh.ARRAY_INDEX]
			var count: int = index.size() if index != null and index.size() > 0 else verts.size()
			for i in range(0, count - 2, 3):
				var a: Vector3 = here * verts[index[i] if index != null and index.size() > 0 else i]
				var b: Vector3 = here * verts[index[i + 1] if index != null and index.size() > 0 else i + 1]
				var c: Vector3 = here * verts[index[i + 2] if index != null and index.size() > 0 else i + 2]
				if maxf(a.y, maxf(b.y, c.y)) < floor_y:
					continue
				# sample the triangle densely enough for OCC_STEP cells
				var n := int(ceil(maxf(a.distance_to(b), maxf(b.distance_to(c), a.distance_to(c))) / OCC_STEP)) + 1
				for u in n + 1:
					for v in n + 1 - u:
						var p := a + (b - a) * (float(u) / n) + (c - a) * (float(v) / n)
						cells[Vector2i(floori(p.x / OCC_STEP), floori(p.z / OCC_STEP))] = true
	for child in node.get_children():
		_rasterise(child, here, floor_y, cells)


## Findings for one solid type: [{kind, type, detail, ratio}] (empty when box and every variant agree within tolerance).
static func audit_type(type: String) -> Array:
	var out := []
	if boxes_for(type).is_empty():
		return out
	var paths := variant_paths(type)
	for variant in paths.size():
		var path: String = paths[variant]
		var boxes := boxes_for(type, variant)
		var cover := Rect2()
		for box in boxes:
			cover = (box as Rect2) if cover.size == Vector2.ZERO else cover.merge(box)
		var fp := variant_footprint(String(path), type)
		if fp.is_empty():
			continue
		var mesh := in_collider_frame(fp["rect"])
		var name := String(path).get_file().get_basename()
		var mesh_area := mesh.size.x * mesh.size.y
		if mesh_area <= 0.0:
			continue
		var occupied := occupancy(String(path), type)
		var inside_n := 0
		for point in occupied:
			for box in boxes:
				if (box as Rect2).grow(OCC_STEP * .75).has_point(point):
					inside_n += 1
					break
		var covered := float(inside_n) / maxf(1.0, float(occupied.size()))
		var box_area := 0.0
		for box in boxes:
			box_area += (box as Rect2).size.x * (box as Rect2).size.y
		var outside := 0.0
		for box in boxes:
			var inside := (box as Rect2).intersection(mesh)
			outside += (box as Rect2).size.x * (box as Rect2).size.y - inside.size.x * inside.size.y
		if covered < 1.0 - TOLERANCE:
			out.append({"kind": "undersize", "type": type, "ratio": covered,
				"detail": "%s: box covers only %.0f%% of the mesh's occupied footprint %.2f x %.2f" % [name, covered * 100.0, mesh.size.x, mesh.size.y]})
		# box sticking out beyond the mesh footprint, per axis, in metres
		var excess := maxf(maxf(mesh.position.x - cover.position.x, cover.end.x - mesh.end.x),
			maxf(mesh.position.y - cover.position.y, cover.end.y - mesh.end.y))
		var limit := maxf(MIN_ABS, TOLERANCE * maxf(mesh.size.x, mesh.size.y))
		if excess > limit and outside / maxf(box_area, 0.001) > TOLERANCE * .5:
			out.append({"kind": "oversize", "type": type, "ratio": excess,
				"detail": "%s: box sticks out %.2f m beyond the mesh %.2f x %.2f (box %.2f x %.2f)" % [name, excess, mesh.size.x, mesh.size.y, cover.size.x, cover.size.y]})
		var offset := (mesh.get_center() - cover.get_center()).length()
		if offset > maxf(0.10, TOLERANCE * maxf(mesh.size.x, mesh.size.y)):
			out.append({"kind": "offset", "type": type, "ratio": offset,
				"detail": "%s: mesh centre is %.2f m off the box centre" % [name, offset]})
	return out


## Solid types that reach the view with no derived box (they would fall back to the authored blocker size).
static func solid_types_without_box() -> Array:
	var solid := {}
	for biome in StreamedRouteGenerator.REGION_PROP_SETS:
		for entry in StreamedRouteGenerator.REGION_PROP_SETS[biome]:
			if bool(entry.get("solid", true)):
				solid[String(entry["type"])] = true
	for type in StreamedRouteGenerator.TEMPLATE_PROP_SIZES:
		solid[String(type)] = true
	var out := []
	for type in solid:
		if PropModelCatalog.is_wall_mounted(type) or PropModelCatalog.is_ceiling_mounted(type) \
				or PropModelCatalog.is_floor_dressing(type) or RoomCatalog.is_surface_prop(type) \
				or PropModelCatalog.is_room_door(type):
			continue
		if not PropColliderSizes.SIZES.has(type):
			out.append(type)
	out.sort()
	return out


static var _footprint_cache := {}


## The visible mesh footprint of a generated prop as a CollisionWorld-style rect {center, half, yaw}, or {} with no model.
static func mesh_rect(prop: Dictionary) -> Dictionary:
	var type := String(prop.get("type", ""))
	var variant := PropColliderBoxes.variant_of(prop)
	var key := "%s#%d" % [type, variant]
	if not _footprint_cache.has(key):
		var paths := variant_paths(type)
		var fp := variant_footprint(String(paths[variant]), type) if variant >= 0 and variant < paths.size() else {}
		_footprint_cache[key] = in_collider_frame(fp["rect"]) if not fp.is_empty() else Rect2()
	var rect: Rect2 = _footprint_cache[key]
	if rect.size == Vector2.ZERO:
		return {}
	var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
	var at := Vector2(cell) + Vector2(.5, .5) + Vector2(prop.get("mount_offset", Vector2.ZERO)) + Vector2(prop.get("placement_offset", Vector2.ZERO))
	var yaw := float(prop.get("yaw", 0.0))
	return {"center": PropColliderBoxes.world_centre(at, rect.get_center(), yaw), "half": rect.size * .5, "yaw": yaw,
		"type": type, "id": String(prop.get("id", ""))}


## Every occupied mesh cell of every variant, turned by each generator yaw the way the view turns the model (yaw + PI on
## the visual, yaw on the box), must fall inside a box: catches a wrong yaw sign or a box on the wrong side of the pivot.
static func audit_rotations(type: String) -> Array:
	var out := []
	var paths := variant_paths(type)
	for variant in paths.size():
		var boxes := PropColliderBoxes.boxes(type, PropColliderSizes.SIZES[type], variant)
		var points := occupancy(String(paths[variant]), type)
		if points.is_empty():
			continue
		for yaw in YAWS:
			var outside := 0
			var visual := Basis(Vector3.UP, float(yaw) + PI)
			for point in points:
				# back to the model frame (occupancy() mirrored it), then the view's visual turn
				var model: Vector2 = -(point as Vector2)
				var world3 := visual * Vector3(model.x, 0.0, model.y)
				var world := Vector2(world3.x, world3.z)
				var hit := false
				for box in boxes:
					var rect := {"center": PropColliderBoxes.world_centre(Vector2.ZERO, box["c"], yaw), "half": box["h"], "yaw": yaw}
					if CollisionWorld.rect_distance(world, rect) <= OCC_STEP:
						hit = true
						break
				if not hit:
					outside += 1
			if float(outside) / float(points.size()) > TOLERANCE:
				out.append({"kind": "rotation", "type": type, "ratio": float(outside) / points.size(),
					"detail": "%s at yaw %d: %d of %d mesh cells fall outside the turned box" % [String(paths[variant]).get_file(), roundi(rad_to_deg(yaw)), outside, points.size()]})
	return out
