extends SceneTree

## Prints every solid prop whose collision box disagrees with the mesh the view spawns (ColliderAudit).
##   godot --headless --path . -s dev/look/collider_mesh_report.gd

func _init() -> void:
	var counts := {"oversize": 0, "undersize": 0, "offset": 0}
	var types := PropColliderSizes.SIZES.keys()
	types.sort()
	for type in types:
		for f in ColliderAudit.audit_type(String(type)):
			counts[f["kind"]] += 1
			print("%-9s %-26s %s" % [f["kind"], f["type"], f["detail"]])
	print("types checked %d  oversize %d  undersize %d  offset %d" % [types.size(), counts["oversize"], counts["undersize"], counts["offset"]])
	print("solid types with no derived box: ", ColliderAudit.solid_types_without_box())
	quit()
