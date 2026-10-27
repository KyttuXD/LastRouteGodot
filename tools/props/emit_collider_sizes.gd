extends Node

## Derives every solid prop's collision box from its model, so the collider matches what the player sees (no invisible
## walls, no walking into a bed): the union of all its variants' bounding boxes, padded 4 cm, snapped up to 5 cm.
## Writes src/config/prop_collider_sizes.gd.
##   godot --headless --path . res://tools/props/emit_collider_sizes.tscn
## (a scene, not -s: the generator it reads needs the autoloads)
## Props whose model overhangs the part you collide with keep their authored box (see KEEP_AUTHORED).

const KEEP_AUTHORED := ["beachUmbrella"]
const PAD := 0.04
## A variant whose footprint edge sits further than this inside the type's union gets its own box.
const VARIANT_SLACK := 0.04
const MAX_HEIGHT := 2.2
## Things that stand above the part you collide with (the restaurant table's balloon cluster) are cut off here.
const HEIGHT_CAP := {"restaurantPartyTable": 0.85,
	# the wall mirror over the vanity and the sneeze hood over the serving counter stand above what you bump into (docs/SCALE_FIT.md)
	"bathroomVanity": 0.95, "prisonServingCounter": 1.1}
## Irregular pieces get several boxes. Rectangles in the MODEL frame (x0, z0, x1, z1) read off the top-down occupancy of
## the mesh (tools/look/dump_occupancy.gd); the emitter mirrors them into the collider frame (the view turns the model by yaw + PI).
const MULTI_BOX := {
	# L-shaped corner desk: the +x/+z quadrant is open floor
	"officeCornerWorkstation": [Rect2(-1.00, -1.06, 1.88, 0.72), Rect2(-1.00, -0.34, 0.96, 0.72)],
}


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


func _model_box(type: String) -> AABB:
	var paths: Array = BlockyPropModels.MODELS.get(type, [])
	if paths.is_empty():
		paths = PropModelCatalog.MODEL_PATHS.get(type, [])
	var total := AABB()
	var have := false
	for path in paths:
		var scene := load(String(path)) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate()
		var box := _extent(node)
		node.free()
		total = box if not have else total.merge(box)
		have = true
	return total if have else AABB()


func _up(value: float) -> float:
	return roundf((value + PAD) / 0.01) * 0.01


## Union of every variant's footprint, in the collider frame, as seen through the view's real spawn path.
func _footprint(type: String) -> Rect2:
	var total := Rect2()
	var have := false
	for path in ColliderAudit.variant_paths(type):
		var fp := ColliderAudit.variant_footprint(String(path), type)
		if fp.is_empty():
			continue
		var rect := ColliderAudit.in_collider_frame(fp["rect"] as Rect2)
		total = rect if not have else total.merge(rect)
		have = true
	return total if have else Rect2()


func _ready() -> void:
	var solid_types := {}
	for biome in StreamedRouteGenerator.REGION_PROP_SETS:
		for entry in StreamedRouteGenerator.REGION_PROP_SETS[biome]:
			if bool(entry.get("solid", true)):
				solid_types[String(entry["type"])] = true
	for type in StreamedRouteGenerator.TEMPLATE_PROP_SIZES:
		solid_types[String(type)] = true
	var lines := []
	var offsets := {}
	var extras := {}
	var variants := {}
	for type in solid_types.keys():
		if KEEP_AUTHORED.has(type) or PropModelCatalog.is_wall_mounted(type) or PropModelCatalog.is_ceiling_mounted(type) \
				or PropModelCatalog.is_floor_dressing(type) or RoomCatalog.is_surface_prop(type):
			continue
		var box := _model_box(type)
		if box.size == Vector3.ZERO:
			continue
		var foot := _footprint(type)
		var off := foot.get_center()
		if absf(off.x) >= 0.03 or absf(off.y) >= 0.03:
			offsets[type] = Vector2(snappedf(off.x, 0.01), snappedf(off.y, 0.01))
		# variants of different sizes each get their own box, so a small chair is not walled in by the big one's box
		var per_variant := []
		var differs := false
		for path in ColliderAudit.variant_paths(type):
			var fp := ColliderAudit.variant_footprint(String(path), type)
			if fp.is_empty():
				per_variant.append(Vector4(snappedf(off.x, 0.01), snappedf(off.y, 0.01), _up(foot.size.x), _up(foot.size.y)))
				continue
			var r := ColliderAudit.in_collider_frame(fp["rect"] as Rect2)
			if absf(r.position.x - foot.position.x) > VARIANT_SLACK or absf(r.end.x - foot.end.x) > VARIANT_SLACK \
					or absf(r.position.y - foot.position.y) > VARIANT_SLACK or absf(r.end.y - foot.end.y) > VARIANT_SLACK:
				differs = true
			per_variant.append(Vector4(snappedf(r.get_center().x, 0.01), snappedf(r.get_center().y, 0.01), _up(r.size.x), _up(r.size.y)))
		if differs and not MULTI_BOX.has(type):
			variants[type] = per_variant
		if MULTI_BOX.has(type):
			var parts := []
			for r in MULTI_BOX[type]:
				var m := ColliderAudit.in_collider_frame(r as Rect2).grow(PAD * .5)
				parts.append(Vector4(snappedf(m.get_center().x, 0.01), snappedf(m.get_center().y, 0.01), snappedf(m.size.x, 0.01), snappedf(m.size.y, 0.01)))
			extras[type] = parts
			offsets.erase(type)
			box = AABB(Vector3.ZERO, Vector3(foot.size.x, box.size.y, foot.size.y))
		lines.append([type, Vector3(_up(foot.size.x), minf(box.size.y, float(HEIGHT_CAP.get(type, MAX_HEIGHT))), _up(foot.size.y))])
	lines.sort_custom(func(a, b) -> bool: return String(a[0]) < String(b[0]))
	var out := "class_name PropColliderSizes\nextends RefCounted\n\n## GENERATED by tools/props/emit_collider_sizes.gd: each solid prop's collision box (x, height, z) derived from its model,\n## so the collider is what the player sees. Overrides the authored sizes in StreamedRouteGenerator.\n\nconst SIZES := {\n"
	for line in lines:
		var v: Vector3 = line[1]
		out += "\t\"%s\": Vector3(%.2f, %.2f, %.2f),\n" % [line[0], v.x, v.y, v.z]
	out += "}\n"
	var keys := offsets.keys()
	keys.sort()
	var off_text := ""
	for k in keys:
		off_text += "\t\"%s\": Vector2(%.2f, %.2f),\n" % [k, offsets[k].x, offsets[k].y]
	var extra_text := ""
	var variant_text := ""
	var vkeys := variants.keys()
	vkeys.sort()
	for k in vkeys:
		var items := []
		for v in variants[k]:
			items.append("Vector4(%.2f, %.2f, %.2f, %.2f)" % [v.x, v.y, v.z, v.w])
		variant_text += "\t\"%s\": [%s],\n" % [k, ", ".join(items)]
	var ekeys := extras.keys()
	ekeys.sort()
	for k in ekeys:
		var items := []
		for v in extras[k]:
			items.append("Vector4(%.2f, %.2f, %.2f, %.2f)" % [v.x, v.y, v.z, v.w])
		extra_text += "\t\"%s\": [%s],\n" % [k, ", ".join(items)]
	out = out.replace("const SIZES := {", "## Box centre offset (x, z) from the prop pivot, in the prop frame, for models whose footprint is not centred on it.\nconst OFFSETS := {\n" + off_text + "}\n## Several boxes for L-shaped or irregular pieces: Vector4(centre x, centre z, width, depth) in the prop frame.\nconst EXTRA_BOXES := {\n" + extra_text + "}\n## Per-variant boxes (variant order of PropColliderBoxes.variant_paths) for types whose variants differ in size:\n## Vector4(centre x, centre z, width, depth) in the prop frame.\nconst VARIANT_BOXES := {\n" + variant_text + "}\n\nconst SIZES := {")
	var file := FileAccess.open("res://src/config/prop_collider_sizes.gd", FileAccess.WRITE)
	file.store_string(out)
	file.close()
	print("wrote %d collider sizes" % lines.size())
	get_tree().quit()
