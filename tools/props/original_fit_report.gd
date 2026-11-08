extends Node

## Measures every prop type that has BOTH an original model and a blocky one (PropModelCatalog.PREFER_ORIGINAL_PROPS) and
## prints one `FIT|` line per type: triangles, footprint and height of the original against the gameplay collider (solid
## types) or the blocky model (decor), in the collider frame and at hunter scale. The deny list in PropModelCatalog.ORIGINAL_DENY
## and tests/validate_original_props.gd are built on these numbers.
##   godot --headless --path . res://tools/props/original_fit_report.tscn
## (a scene, not -s: ModelSlot and the catalog need the autoloads). Read-only; writes nothing.
## row() and verdict() are also what tests/validate_original_props.gd enforces, so the list and the numbers cannot drift apart.

const BLOCKY_DIR := "res://assets/props/blocky/"


static func original_paths(type: String) -> Array:
	var out := []
	for path in PropModelCatalog.MODEL_PATHS.get(type, []):
		if not String(path).begins_with(BLOCKY_DIR) and not String(path).begins_with("user://"):
			out.append(String(path))
	return out


static func tris_of(visual: Node) -> int:
	var total := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var index = arrays[Mesh.ARRAY_INDEX]
			total += (index.size() if index != null and index.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total


## {rect: footprint in the collider frame (union over the paths), top, bottom, tris: [per path], nodes: [mesh nodes per path]}
static func measure(paths: Array, type: String) -> Dictionary:
	var rect := Rect2()
	var have := false
	var top := -INF
	var bottom := INF
	var tris := []
	var nodes := []
	for path in paths:
		var visual := ModelSlot.instantiate_prop(String(path), type)
		if visual == null:
			continue
		var bounds := ModelSlot.combined_local_bounds(visual)
		tris.append(tris_of(visual))
		nodes.append(visual.find_children("*", "MeshInstance3D", true, false).size())
		visual.free()
		var r := ColliderAudit.in_collider_frame(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z))
		rect = r if not have else rect.merge(r)
		have = true
		top = maxf(top, bounds.end.y)
		bottom = minf(bottom, bounds.position.y)
	return {"rect": rect, "top": top, "bottom": bottom, "tris": tris, "nodes": nodes, "have": have}


static func collider_rect(type: String) -> Rect2:
	var size: Vector3 = PropColliderSizes.SIZES.get(type, Vector3.ZERO)
	if size == Vector3.ZERO:
		return Rect2()
	var rect := Rect2()
	var have := false
	var variants := maxi(1, (PropColliderSizes.VARIANT_BOXES.get(type, []) as Array).size())
	for variant in variants:
		for box in PropColliderBoxes.boxes(type, size, variant if PropColliderSizes.VARIANT_BOXES.has(type) else -1):
			var r := Rect2((box["c"] as Vector2) - (box["h"] as Vector2), (box["h"] as Vector2) * 2.0)
			rect = r if not have else rect.merge(r)
			have = true
	return rect


## The numbers for one type, or {} when it has no original or no blocky twin. Distances are metres at hunter scale, in the
## collider frame; positive = the original sticks out past (or stands above) the reference.
##   reference: the gameplay collider for a solid type, the blocky model's footprint otherwise
##   dtop: original top - collider height (solid) or - blocky top;  dtopb: original top - blocky top;  dbot: blocky bottom - original bottom
static func row(type: String) -> Dictionary:
	var originals := original_paths(type)
	var blocky: Array = BlockyPropModels.MODELS.get(type, [])
	if originals.is_empty() or blocky.is_empty():
		return {}
	var o := measure(originals, type)
	var b := measure(blocky, type)
	if not o["have"] or not b["have"]:
		return {}
	var solid := PropColliderSizes.SIZES.has(type)
	var reference: Rect2 = collider_rect(type) if solid else b["rect"]
	var orect: Rect2 = o["rect"]
	var ref_top: float = PropColliderSizes.SIZES[type].y if solid else b["top"]
	var xn := reference.position.x - orect.position.x
	var xp := orect.end.x - reference.end.x
	var zn := reference.position.y - orect.position.y
	var zp := orect.end.y - reference.end.y
	var otris: Array = o["tris"]
	var btris: Array = b["tris"]
	var bmean := 0.0
	for t in btris:
		bmean += float(t) / btris.size()
	return {"type": type, "solid": solid, "wall": PropModelCatalog.is_wall_mounted(type), "ceil": PropModelCatalog.is_ceiling_mounted(type),
		"act": PropModelCatalog.interaction_for(type), "door": PropModelCatalog.is_room_door(type),
		"o_tris": otris, "b_tris": btris, "o_max": otris.max(), "b_mean": bmean, "o_nodes": o["nodes"],
		"xn": xn, "xp": xp, "zn": zn, "zp": zp, "dev": maxf(maxf(absf(xn), absf(xp)), maxf(absf(zn), absf(zp))),
		"dtop": o["top"] - ref_top, "dtopb": o["top"] - b["top"], "dbot": b["bottom"] - o["bottom"],
		"o_variants": originals.size(), "b_variants": blocky.size(),
		"o_size": Vector3(orect.size.x, o["top"] - o["bottom"], orect.size.y), "ref_size": reference.size}


## "" when the original may be drawn, "fit" when its footprint/height/mount is outside the tolerance, "heavy" when it is over
## PropModelCatalog.MAX_ORIGINAL_TRIS and heavier than the blocky model. Same order as ORIGINAL_DENY's fit/heavy rows.
static func verdict(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if float(r["dev"]) > (PropModelCatalog.ORIGINAL_FIT_SOLID if r["solid"] else PropModelCatalog.ORIGINAL_FIT_DECOR):
		return "fit"
	var dtopb: float = r["dtopb"]
	if dtopb < -0.30 or dtopb > 0.60 or (r["solid"] and float(r["dtop"]) < -0.30):
		return "fit"
	if r["wall"] and (absf(dtopb) > 0.15 or absf(float(r["dbot"])) > 0.15):
		return "fit"
	if r["ceil"] and absf(dtopb) > 0.10:
		return "fit"
	if int(r["o_max"]) > PropModelCatalog.MAX_ORIGINAL_TRIS and float(r["o_max"]) > float(r["b_mean"]):
		return "heavy"
	return ""


func _ready() -> void:
	await get_tree().process_frame
	var types := PropModelCatalog.MODEL_PATHS.keys()
	types.sort()
	for type in types:
		var r := row(type)
		if r.is_empty():
			continue
		print("FIT|%s|act=%s|door=%d|wall=%d|ceil=%d|solid=%d|o_tris=%s|b_tris=%s|o_nodes=%s|xn=%.3f|xp=%.3f|zn=%.3f|zp=%.3f|dtop=%.3f|dtopb=%.3f|dbot=%.3f|o_n=%d|b_n=%d|o_size=%.2fx%.2fx%.2f|ref_size=%.2fx%.2f|verdict=%s|deny=%s" % [
			type, r["act"], int(r["door"]), int(r["wall"]), int(r["ceil"]), int(r["solid"]),
			",".join(PackedStringArray((r["o_tris"] as Array).map(func(v): return str(v)))),
			",".join(PackedStringArray((r["b_tris"] as Array).map(func(v): return str(v)))),
			",".join(PackedStringArray((r["o_nodes"] as Array).map(func(v): return str(v)))),
			r["xn"], r["xp"], r["zn"], r["zp"], r["dtop"], r["dtopb"], r["dbot"], r["o_variants"], r["b_variants"],
			(r["o_size"] as Vector3).x, (r["o_size"] as Vector3).y, (r["o_size"] as Vector3).z,
			(r["ref_size"] as Vector2).x, (r["ref_size"] as Vector2).y, verdict(r), PropModelCatalog.ORIGINAL_DENY.get(type, "")])
	print("FIT|done")
	get_tree().quit()
