extends RefCounted

## Collider quality (DONE12): every solid prop's collision box comes from its model (PropColliderSizes, regenerate with
## tools/props/emit_collider_sizes.gd after changing a model), no decor carries a collider, and what generated chunks hand
## the 3D view matches the table.
## Hitboxes (KT): every type, variant and generator yaw agrees with the mesh the view spawns within ColliderAudit.TOLERANCE
## (no invisible wall, no walk-through model, no box beside its model, L-shaped pieces use several boxes), and a walk-test
## on real chunks: the player capsule cannot stand inside a visible solid, can stand in the visible gap beside one, and no
## hall cell centre or doorway is blocked by a box where the mesh itself leaves room.

const WALK_SEEDS := ["HITBOX-A", "HITBOX-B", "HITBOX-C"]
const WALK_RING := 2

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


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


func run(_host: Node) -> int:
	var stale := 0
	var checked := 0
	for type in PropColliderSizes.SIZES:
		var size: Vector3 = PropColliderSizes.SIZES[type]
		_expect(not PropModelCatalog.is_wall_mounted(type) and not PropModelCatalog.is_ceiling_mounted(type)
			and not PropModelCatalog.is_floor_dressing(type) and not RoomCatalog.is_surface_prop(type),
			"%s is decor (wall/ceiling/floor/surface) but has a collider" % type)
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
		if not have:
			continue
		checked += 1
		if absf(size.x - total.size.x) > 0.12 or absf(size.z - total.size.z) > 0.12:
			stale += 1
			print("  FAIL  %s collider %.2f x %.2f is out of date against its model %.2f x %.2f (run tools/props/emit_collider_sizes.gd)" % [
				type, size.x, size.z, total.size.x, total.size.z])
			_failures += 1
		_expect(size.y <= 2.21 and size.y > 0.05, "%s collider height %.2f is out of range" % [type, size.y])
	# chunks hand the derived size to the view
	var generator := StreamedRouteGenerator.new("COLLIDERS")
	var seen := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var data := generator.chunk(Vector3i(dx, 0, dz))
			for prop in data.get("region_props", []):
				var type := String(prop.get("type", ""))
				if bool(prop.get("solid", true)) and not bool(prop.get("room_door", false)) and PropColliderSizes.SIZES.has(type):
					seen += 1
					_expect(prop.get("collider_size") == PropColliderSizes.SIZES[type],
						"%s collider %s ignores the derived collider %s" % [type, prop.get("collider_size"), PropColliderSizes.SIZES[type]])
				if not bool(prop.get("solid", true)) and not bool(prop.get("room_door", false)):
					_expect(not prop.has("occupied_cells") or (prop["occupied_cells"] as Array).is_empty(),
						"non-solid %s occupies cells" % type)
	_expect(seen > 50, "only %d solid props in the sampled chunks" % seen)
	# every type, every variant, every yaw against the spawned mesh
	var mesh_findings := 0
	for type in PropColliderSizes.SIZES:
		for finding in ColliderAudit.audit_type(String(type)) + ColliderAudit.audit_rotations(String(type)):
			mesh_findings += 1
			if mesh_findings <= 12:
				print("  FAIL  %s %s: %s" % [finding["kind"], finding["type"], finding["detail"]])
	_expect(mesh_findings == 0, "%d collider-vs-mesh disagreements (tools/look/collider_mesh_report.gd)" % mesh_findings)
	_expect(ColliderAudit.solid_types_without_box() == ["beachUmbrella"],
		"solid props with no derived collider: %s" % [ColliderAudit.solid_types_without_box()])
	var walk := walk_test()
	_expect(int(walk["props"]) > 300, "walk-test saw only %d solid props" % walk["props"])
	_expect(int(walk["inside_mesh"]) == 0, "%d points inside a visible solid are standable (walk-through model), e.g. %s" % [walk["inside_mesh"], walk["samples_inside"]])
	_expect(int(walk["phantom"]) == 0, "%d visible gaps beside a prop are blocked by its box (invisible wall), e.g. %s" % [walk["phantom"], walk["samples_phantom"]])
	_expect(int(walk["hall_blocked"]) == 0, "%d hall/door centres blocked by a box bigger than its prop, e.g. %s" % [walk["hall_blocked"], walk["samples_hall"]])
	var map := map_check()
	_expect(int(map["solid"]) > 300, "map check saw only %d solid props" % map["solid"])
	_expect(int(map["mismatch"]) == 0, "%d minimap boxes differ from the 3D view's colliders, e.g. %s" % [map["mismatch"], map["samples"]])
	if _failures == 0:
		print("  minimap    %d solid props on %d chunks drawn as their %d real collider boxes (%d decor props draw none)" % [map["solid"], map["chunks"], map["boxes"], map["decor"]])
		print("  colliders  %d derived collider boxes match their models (every variant and yaw), no decor colliders, chunks use them;" % checked)
		print("  walk-test  %d props in %d chunks: 0 standable mesh points, 0 phantom walls in %d side gaps, 0 of %d hall/door centres over-blocked" % [
			walk["props"], walk["chunks"], walk["gaps"], walk["hall_points"]])
	return _failures


## The walk-test on CollisionWorld (what the player capsule meets) against the visible mesh footprints of the same chunk.
static func walk_test(seeds: Array = WALK_SEEDS, ring: int = WALK_RING) -> Dictionary:
	var out := {"props": 0, "chunks": 0, "inside_mesh": 0, "phantom": 0, "gaps": 0, "hall_blocked": 0, "hall_points": 0,
		"samples_inside": [], "samples_phantom": [], "samples_hall": []}
	var radius := CollisionWorld.PLAYER_RADIUS
	for seed_text in seeds:
		var generator := StreamedRouteGenerator.new(String(seed_text))
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				var world := CollisionWorld.from_chunk(data)
				out["chunks"] += 1
				var meshes := []
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					if bool(prop.get("room_door", false)) or not bool(prop.get("solid", true)) \
							or not PropColliderSizes.SIZES.has(String(prop.get("type", ""))):
						continue
					var mesh := ColliderAudit.mesh_rect(prop)
					if not mesh.is_empty():
						meshes.append(mesh)
				out["props"] += meshes.size()
				for mesh in meshes:
					var half: Vector2 = mesh["half"]
					var yaw := float(mesh["yaw"])
					# 1. inside the visible solid (inset 5 cm): never standable (L-shaped pieces: the rotation audit covers their occupancy)
					for local in ([] if PropColliderSizes.EXTRA_BOXES.has(mesh["type"]) else [Vector2.ZERO, Vector2(half.x - .05, 0), Vector2(-half.x + .05, 0), Vector2(0, half.y - .05), Vector2(0, -half.y + .05)]):
						var p := PropColliderBoxes.world_centre(mesh["center"], local, yaw)
						if _mesh_occupied(p, mesh) and world.can_stand(p, radius):
							out["inside_mesh"] += 1
							_note(out["samples_inside"], "%s %s at %s" % [mesh["type"], mesh["id"], p])
					# 2. the gap beside each side: a capsule standing 2 cm clear of the mesh must fit unless something else is there
					for side in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
						var local: Vector2 = side * (Vector2(half.x, half.y) + Vector2.ONE * (radius + .05))
						var p := PropColliderBoxes.world_centre(mesh["center"], local, yaw)
						if not _clear_of_walls(world, p, radius + .05) or _near_other_mesh(p, meshes, mesh, radius + .05):
							continue
						out["gaps"] += 1
						if not world.can_stand(p, radius):
							out["phantom"] += 1
							_note(out["samples_phantom"], "%s %s side %s at %s" % [mesh["type"], mesh["id"], side, p])
				# 3. hall cell centres and doorways: a box may only block where its mesh does too
				var points := []
				for door in world.doors:
					points.append(Vector2(door.get("cell", Vector2i.ZERO)) + Vector2(.5, .5))
				var rooms: Array = []
				for room in data.get("rooms", []):
					rooms.append(room.get("rect", Rect2i()))
				for z in world.grid.size():
					for x in (world.grid[z] as Array).size():
						if int(world.grid[z][x]) != 0:
							continue
						var inside_room := false
						for r in rooms:
							if (r as Rect2i).has_point(Vector2i(x, z)):
								inside_room = true
								break
						if not inside_room:
							points.append(Vector2(x, z) + Vector2(.5, .5))
				for p in points:
					if not _clear_of_walls(world, p, radius):
						continue
					out["hall_points"] += 1
					for rect in world.rects:
						if CollisionWorld.rect_distance(p, rect) >= radius:
							continue
						if not _near_other_mesh(p, meshes, {}, radius + .05):
							out["hall_blocked"] += 1
							_note(out["samples_hall"], "%s %s blocks %s" % [rect["type"], rect["id"], p])
						break
	return out


## Minimap boxes (FacilityMap.collider_boxes, what the HUD map draws) against the shapes the 3D view builds
## (_spawn_authored_prop: one box per PropColliderBoxes entry at at + offset.rotated(UP, yaw), turned by yaw), corner by
## corner, over every size class of prop on sample seeds; decor and removed props draw nothing.
static func map_check(seeds: Array = ["MAP-A", "MAP-B"], ring: int = 1) -> Dictionary:
	var out := {"chunks": 0, "solid": 0, "decor": 0, "boxes": 0, "mismatch": 0, "samples": []}
	for seed_text in seeds:
		var generator := StreamedRouteGenerator.new(String(seed_text))
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				out["chunks"] += 1
				var drawn := FacilityMap.collider_boxes(data)
				var ids := {}
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					var id := String(prop.get("id", ""))
					ids[id] = true
					if bool(prop.get("room_door", false)):
						continue
					var mine: Array = drawn.get(id, [])
					if not bool(prop.get("solid", true)):
						out["decor"] += 1
						if not mine.is_empty():
							out["mismatch"] += 1
							_note(out["samples"], "decor %s drawn as a box" % prop.get("type", ""))
						continue
					out["solid"] += 1
					# the view's own formula
					var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
					var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
					var offset := Vector2(prop.get("mount_offset", Vector2.ZERO)) + Vector2(prop.get("placement_offset", Vector2.ZERO))
					var at := Vector3(cell.x + .5 + offset.x, 0.0, cell.y + .5 + offset.y)
					var yaw := float(prop.get("yaw", 0.0))
					var view_boxes := PropColliderBoxes.boxes(String(prop.get("type", "")), size,
						PropColliderBoxes.variant_paths(String(prop.get("type", ""))).find(
							PropModelCatalog.model_path(String(prop.get("type", "")), id, String(prop.get("room_id", "")))))
					if view_boxes.size() != mine.size():
						out["mismatch"] += 1
						_note(out["samples"], "%s: %d map boxes, %d view boxes" % [prop.get("type", ""), mine.size(), view_boxes.size()])
						continue
					for i in view_boxes.size():
						var local: Vector2 = view_boxes[i]["c"]
						var half: Vector2 = view_boxes[i]["h"]
						var shape := Transform3D(Basis(Vector3.UP, yaw), at + Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, yaw))
						var corners := FacilityMap.collider_corners(mine[i])
						var worst := 0.0
						for k in 4:
							var sign_x: float = [-1.0, 1.0, 1.0, -1.0][k]
							var sign_z: float = [-1.0, -1.0, 1.0, 1.0][k]
							var p := shape * Vector3(half.x * sign_x, 0.0, half.y * sign_z)
							worst = maxf(worst, Vector2(p.x, p.z).distance_to(corners[k]))
						out["boxes"] += 1
						if worst > 0.01:
							out["mismatch"] += 1
							_note(out["samples"], "%s box %d off by %.2f m" % [prop.get("type", ""), i, worst])
				for id in drawn:
					if not ids.has(id):
						out["mismatch"] += 1
						_note(out["samples"], "box drawn for a prop not in the chunk: %s" % id)
	return out


static func _note(list: Array, text: String) -> void:
	if list.size() < 4:
		list.append(text)


static func _mesh_occupied(point: Vector2, mesh: Dictionary) -> bool:
	return CollisionWorld.rect_distance(point, mesh) <= 0.0


static func _near_other_mesh(point: Vector2, meshes: Array, skip: Dictionary, within: float) -> bool:
	for other in meshes:
		if skip.is_empty() or other["id"] != skip["id"]:
			if CollisionWorld.rect_distance(point, other) < within:
				return true
	return false


## Capsule disc over open cells only (no props), the wall half of CollisionWorld.can_stand().
static func _clear_of_walls(world: CollisionWorld, point: Vector2, radius: float) -> bool:
	var saved := world.use_local
	var saved_rects := world.local_rects
	world.use_local = true
	world.local_rects = []
	var ok := world.can_stand(point, radius)
	world.use_local = saved
	world.local_rects = saved_rects
	return ok
