class_name GeometryResolve
extends RefCounted

## Deterministic push-out for solid props that a template, a rotation or a wall-backed shift left poking into a wall
## (GeometryAudit rule prop_in_wall). Runs on every generated chunk before the walkway clean-up, host and guests alike: a
## prop sliding a few centimetres along its own placement offset is better than a collider and a mesh inside a wall.
## Wall-mounted and non-solid props are left alone (they belong to the wall).

const MAX_ROUNDS := 4
const CLEARANCE := 0.01
## Moves above this are not a nudge: the prop is left where it is and the audit keeps reporting it.
const MAX_PUSH := 0.6


static func push_out(grid: Array, props: Array) -> Array:
	var size := grid.size()
	var out := []
	for prop_value in props:
		var prop: Dictionary = prop_value
		if bool(prop.get("room_door", false)) or not bool(prop.get("solid", true)) or bool(prop.get("wall_mounted", false)):
			out.append(prop)
			continue
		var collider: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
		var half := Vector2(collider.x, collider.z) * .5
		var yaw := float(prop.get("yaw", 0.0))
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		var base := Vector2(prop.get("mount_offset", Vector2.ZERO))
		var placement := Vector2(prop.get("placement_offset", Vector2.ZERO))
		var moved := Vector2.ZERO
		for _round in MAX_ROUNDS:
			var centre := Vector2(cell) + Vector2(.5, .5) + base + placement + moved
			var reach := int(ceil(half.length())) + 1
			var fix := Vector2.ZERO
			for dz in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					var wc := Vector2i(floori(centre.x) + dx, floori(centre.y) + dz)
					if GeometryAudit.is_open_cell(grid, size, wc):
						continue
					var push := GeometryAudit.obb_push(centre, half, yaw, Vector2(wc) + Vector2(.5, .5), Vector2(.5, .5), 0.0)
					if push.length() > absf(fix.x) + absf(fix.y):
						fix = push
			if fix == Vector2.ZERO:
				break
			moved += fix + fix.normalized() * CLEARANCE
		if moved != Vector2.ZERO and moved.length() <= MAX_PUSH:
			var copy := prop.duplicate()
			copy["placement_offset"] = placement + moved
			out.append(copy)
		else:
			out.append(prop)
	return out
