extends RefCounted

## Wall and floor themes (docs/WALL_THEMES.md): every face is themed by the space it FACES, the doorway floor and door jambs
## belong to the hall, every generated district and room purpose has its own floor set, every floor kind exists, and hall
## junctions use the hall floor. Many seeds, every district.
##
##   godot --headless --path . res://scenes/validate.tscn -- wall_themes

const SEEDS := ["WALLS-A", "WALLS-B", "WALLS-C"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		if _failures < 25:
			print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_check_plane_uv()
	for region in StreamedRouteGenerator.BIOMES:
		_expect(FloorSets.HALLS.has(region), "district %s has no hall floor set" % region)
		_expect(FloorSets.ROOM_DEFAULT.has(region), "district %s has no room floor default" % region)
	var all_kinds := []
	for entry in FloorSets.HALLS.values():
		all_kinds.append_array(entry["floor"])
	for entry in FloorSets.ROOM_DEFAULT.values():
		all_kinds.append_array(entry)
	for entry in FloorSets.ROOMS.values():
		all_kinds.append_array(entry)
	for kind in all_kinds:
		_expect(RefTextures.FLOOR_PAINTERS.has(kind), "floor kind %s is not painted" % kind)
	var faces := 0
	var doors := 0
	var purposes := {}
	var mismatches := 0
	var arches := 0
	var hall_arches := 0
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		var view := StreamedFacilityView3D.new()
		view.generator = generator
		for cz in range(-4, 5):
			for cx in range(-4, 5):
				var coord := Vector3i(cx, 0, cz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				var region := String(data.get("region", generator.biome_for(coord)))
				var grid: Array = data["grid"]
				var room_map := StreamedFacilityView3D._room_type_map(data)
				var build := {"style": RefLook.REGION_STYLE.get(region, RefLook.REGION_STYLE["maze"]), "coord": coord,
					"room_map": room_map, "region": region, "data": data}
				for room_value in data.get("rooms", []):
					var room: Dictionary = room_value
					var room_type := String(room.get("room_type", ""))
					purposes[room_type] = true
					_expect(FloorSets.has_room(room_type), "room purpose %s (%s) has no floor set of its own" % [room_type, region])
					var rect: Rect2i = room["rect"]
					# doorways on the border belong to the hall
					for z in range(rect.position.y, rect.end.y):
						for x in range(rect.position.x, rect.end.x):
							if x < 0 or z < 0 or x >= grid.size() or z >= grid.size() or int(grid[z][x]) != 0:
								continue
							if StreamedFacilityView3D._is_doorway(grid, rect, x, z):
								doors += 1
								# a door between two rooms of a suite sits inside the suite's own interior: that is fine
								var enclosed := false
								for other_value in data.get("rooms", []):
									var other: Rect2i = (other_value as Dictionary)["rect"]
									if other != rect and other.grow(-1).has_point(Vector2i(x, z)):
										enclosed = true
								_expect(enclosed or not room_map.has(Vector2i(x, z)), "%s %s: doorway %s is themed as room %s" % [seed_text, coord, Vector2i(x, z), room_type])
				# archways: no default-material blocks, each half in the wall theme of the space it faces
				var has_arch := false
				for prop_value in data.get("region_props", []):
					if bool((prop_value as Dictionary).get("arch", false)):
						has_arch = true
				if has_arch or (cx + cz) % 2 == 0:
					var holder := Node3D.new()
					var decor := RefDecor.new(holder, data, room_map)
					while not decor.step():
						pass
					hall_arches += _check_arch_log(decor, data, region, "%s %s" % [seed_text, coord])
					holder.free()
				if has_arch:
					var holder := Node3D.new()
					var decor := RefDecor.new(holder, data, room_map)
					decor._arches()
					for prop_value in data.get("region_props", []):
						var prop: Dictionary = prop_value
						if not bool(prop.get("arch", false)) or (prop.get("doorway_cells", []) as Array).size() != 3:
							continue
						arches += 1
						var middle: Vector2i = prop["doorway_cells"][1]
						var outward: Vector2i = prop.get("outward", Vector2i.UP)
						for face in [-1, 1]:
							var faced: Vector2i = middle + outward * face
							var want := RefLook.wall_kind(region, String(room_map.get(faced, "")), coord.x * 45 + faced.x, coord.z * 45 + faced.y)
							var got: String = decor.arch_wall_kind(faced)
							var key := "arch_wall:%s@%.1f" % [got, decor._hh(faced)]
							_expect(got == want and decor._transforms.has(key), "%s %s: arch side facing %s is %s, its wall is %s" % [seed_text, coord, faced, got, want])
							var material := (RefDecor.mesh_for(key) as BoxMesh).material as ShaderMaterial
							_expect(material != null and material.get_shader_parameter("albedo_tex") == RefTextures.material("wall", got).albedo_texture \
								and material.shader == RefDecor.PLANE_UV_SHADER,
								"arch material for %s is not the wall's own texture on the wall grid" % got)
					holder.free()
				# every wall face takes the theme of the cell it faces
				for z in grid.size():
					for x in grid.size():
						if int(grid[z][x]) == 0:
							var floor_kind: String = view._ref_floor_kind(build, x, z)
							var owner := String(room_map.get(Vector2i(x, z), ""))
							var allowed: Array = FloorSets.room(region, owner) if owner != "" else FloorSets.hall(region)
							if not allowed.has(floor_kind) and not floor_kind.begins_with("runner"):
								mismatches += 1
								_expect(false, "%s %s cell %s: floor %s is not from %s's set" % [seed_text, coord, Vector2i(x, z), floor_kind, owner if owner != "" else "the hall"])
							if owner == "" and floor_kind.begins_with("runner") and not FloorSets.hall_runner(region):
								_expect(false, "%s %s: a runner in a %s hall" % [seed_text, coord, region])
							continue
						for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							var n: Vector2i = Vector2i(x, z) + step
							if n.x < 0 or n.y < 0 or n.x >= grid.size() or n.y >= grid.size() or int(grid[n.y][n.x]) != 0:
								continue
							faces += 1
							var kind: String = view._ref_wall_kind(build, x, z, n.x, n.y)
							var facing := String(room_map.get(n, ""))
							var wall_set: Array = (RefLook.ROOM_STYLE.get(facing, {}) as Dictionary).get("wall", build["style"]["wall"]) \
								if facing != "" else build["style"]["wall"]
							if not wall_set.has(kind):
								mismatches += 1
								_expect(false, "%s %s: wall face %s->%s is %s, not from the %s set" % [seed_text, coord, Vector2i(x, z), n, kind, facing if facing != "" else "hall"])
		view.free()
	_expect(doors > 50, "only %d doorways sampled" % doors)
	_expect(arches > 5, "only %d archways sampled" % arches)
	_expect(hall_arches > 20, "only %d hall arches sampled" % hall_arches)
	if _failures == 0:
		print("  wall_themes  %d wall faces and every floor cell themed by the space they face (0 mismatches), %d doorways on the hall theme, %d room purposes with their own floors, %d districts, %d arches in their walls' themes on both sides, %d hall arches centred and flush with district trim" % [
			faces, doors, purposes.size(), StreamedRouteGenerator.BIOMES.size(), arches, hall_arches])
	return _failures


## Archways and hall pilasters (KT): themed by the hall's wall with the district's accent (no default gray stone, no
## brass outside the districts that use it, no untextured trim), centred on the hall (under 2 cm), archway faces on the
## wall planes, the span exactly pilaster face to pilaster face, under the ceiling.
func _check_arch_log(decor: RefDecor, data: Dictionary, region: String, where: String) -> int:
	_expect(not decor._transforms.has("arch_header") and not decor._transforms.has("arch_cap"),
		"%s: an arch or pilaster still uses the default gray stone / gold block" % where)
	for key in decor._transforms:
		if not String(key).begins_with("arch_trim:"):
			continue
		_expect(key == "arch_trim:" + region, "%s: trim %s in a %s district" % [where, key, region])
		var m := (RefDecor.mesh_for(key) as BoxMesh).material as ShaderMaterial
		var accent := RefLook.arch_accent(region)
		_expect(m != null and m.shader == RefDecor.PLANE_UV_SHADER and m.get_shader_parameter("albedo_tex") != null \
			and m.get_shader_parameter("albedo_tex") == RefTextures.material(String(accent[0]), String(accent[1])).albedo_texture,
			"%s: trim %s is not the district's textured accent %s" % [where, key, accent[1]])
	var hall := 0
	for entry_value in decor.arch_log:
		var entry: Dictionary = entry_value
		var centre: Vector3 = entry["centre"]
		var hall_centre: Vector3 = entry["hall_centre"]
		var offset := Vector2(centre.x - hall_centre.x, centre.z - hall_centre.z).length()
		_expect(offset < .02, "%s: %s arch is %.3f m off the hall centreline" % [where, entry["kind"], offset])
		_expect(absf(float(entry["span"]) - float(entry["between"])) < .02, "%s: arch span %.2f m, opening %.2f m" % [where, entry["span"], entry["between"]])
		_expect(String(entry["wall_key"]).begins_with("arch_wall:"), "%s: arch not in a wall theme" % where)
		if entry["kind"] == "door3":
			for face_value in entry["faces"]:
				var face: Vector3 = face_value
				var on_grid: bool = absf(face.x - roundf(face.x)) < .005 or absf(face.z - roundf(face.z)) < .005
				_expect(on_grid, "%s: archway face at %s is not on the wall plane" % [where, face])
		else:
			hall += 1
			_expect(float(entry["top"]) <= float(entry["ceiling"]) + .001, "%s: hall arch top %.2f over the ceiling %.2f" % [where, entry["top"], entry["ceiling"]])
	return hall


## Rotated and sloped arches (KT): the arch texture (RefDecor.plane_uv = ref_plane_uv.gdshader) matches the wall faces
## exactly on all four sides and at every ceiling height, and keeps the flat arch's texel density and level courses on an
## arch turned 30 / 45 / 117 degrees and on one standing on a 12 degree ramp, with no seam between blocks in one plane.
## (Measured on the mapping itself: the headless validator has no renderer.)
func _check_plane_uv() -> void:
	for height in [3.3, 4.0, 5.9]:
		for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var surface := RefSurfaceMesh.new()
			surface.add_wall(3, 5, dir, 0.0, Color.WHITE, height, 0.0, height)
			var verts: PackedVector3Array = surface._v[1]
			var uvs: PackedVector2Array = surface._uv[1]
			for index in verts.size():
				var mapped := RefDecor.plane_uv(verts[index], Vector3(dir.x, 0, dir.y), 0.0, height)
				var du := absf(mapped.x - uvs[index].x)
				_expect(absf(du - roundf(du)) < .001 and absf(mapped.y - uvs[index].y) < .001,
					"arch texture does not line up with the wall facing %s at %.1f m: %s vs %s" % [dir, height, mapped, uvs[index]])
	var flat := _density(Vector3(0, 0, 1), 0.0)
	for yaw in [30.0, 45.0, 117.0]:
		var n := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(yaw))
		_expect((_density(n, 0.0) - flat).length() < .001, "a %d degree arch has texel density %s, flat %s" % [yaw, _density(n, 0.0), flat])
		# blocks side by side in the turned wall plane: the texture runs on across the join at the same rate
		var along := Vector3.UP.cross(n).normalized()
		var edge := Vector3(2.3, 1.7, 4.1)
		var step := RefDecor.plane_uv(edge + along * .25, n, 0.0, 4.0) - RefDecor.plane_uv(edge, n, 0.0, 4.0)
		_expect(absf(step.x - .25) < .0001 and absf(step.y) < .0001, "a %d degree arch has a seam or skew between blocks" % yaw)
	# on a ramp the jambs stay plumb and the courses level: same v at the same height above the local floor
	var ramp := deg_to_rad(12.0)
	for run in [0.0, 1.5, 3.0]:
		var floor_y: float = tan(ramp) * float(run)
		var mapped := RefDecor.plane_uv(Vector3(run, floor_y + 1.0, 0.0), Vector3(0, 0, 1), floor_y, 4.0)
		_expect(absf(mapped.y - .75) < .0001, "courses on a ramp arch are not level with the floor")
		_expect((_density(Vector3(0, 0, 1), floor_y) - flat).length() < .001, "a ramp arch is stretched")


## Texture change per metre across and up a face with normal `n`: Vector2(du/dm along, dv/dm up).
func _density(n: Vector3, floor_y: float) -> Vector2:
	var along := Vector3.UP.cross(n).normalized()
	var at := Vector3(1.2, floor_y + 1.4, -.7)
	var base := RefDecor.plane_uv(at, n, floor_y, 4.0)
	return Vector2(absf(RefDecor.plane_uv(at + along * .01, n, floor_y, 4.0).x - base.x) / .01,
		absf(RefDecor.plane_uv(at + Vector3.UP * .01, n, floor_y, 4.0).y - base.y) / .01)
