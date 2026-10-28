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
	var multi_kind_rooms := {}
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
					"room_map": room_map, "room_anchor": StreamedFacilityView3D.room_anchor_map(data), "region": region,
					"data": data}
				# one floor kind per room: kind seen per room origin
				var room_floor := {}
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
				if has_arch:
					var holder := Node3D.new()
					var decor := RefDecor.new(holder, data, room_map)
					decor._arches()
					_expect(not decor._transforms.has("arch_header"), "%s %s: an arch still uses the default stone block" % [seed_text, coord])
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
							_expect(got == want and decor._transforms.has("arch_wall:" + got), "%s %s: arch side facing %s is %s, its wall is %s" % [seed_text, coord, faced, got, want])
							var material := (RefDecor.mesh_for("arch_wall:" + got) as BoxMesh).material as StandardMaterial3D
							_expect(material != null and material.albedo_texture == RefTextures.material("wall", got).albedo_texture and material.uv1_world_triplanar,
								"arch material for %s is not the wall's own texture on the wall grid" % got)
					holder.free()
				# every wall face takes the theme of the cell it faces
				for z in grid.size():
					for x in grid.size():
						if int(grid[z][x]) == 0:
							var floor_kind: String = view._ref_floor_kind(build, x, z)
							var owner := String(room_map.get(Vector2i(x, z), ""))
							if owner == "" and not floor_kind.begins_with("runner"):
								if room_floor.has("hall") and room_floor["hall"] != floor_kind:
									_expect(false, "%s %s: hall floor mixes %s and %s" % [seed_text, coord, room_floor["hall"], floor_kind])
								room_floor["hall"] = floor_kind
							if owner != "":
								var origin := str((build["room_anchor"] as Dictionary)[Vector2i(x, z)], owner)
								if FloorSets.room(region, owner).size() > 1:
									multi_kind_rooms[str(seed_text, coord, origin)] = true
								if room_floor.has(origin) and room_floor[origin] != floor_kind:
									_expect(false, "%s %s: room %s at %s is laid in two floors (%s and %s)" % [seed_text, coord,
										owner, origin, room_floor[origin], floor_kind])
								room_floor[origin] = floor_kind
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
	_expect(multi_kind_rooms.size() > 20, "only %d rooms with a multi-kind floor set sampled" % multi_kind_rooms.size())
	_expect(doors > 50, "only %d doorways sampled" % doors)
	_expect(arches > 5, "only %d archways sampled" % arches)
	if _failures == 0:
		print("  wall_themes  %d wall faces and every floor cell themed by the space they face (0 mismatches), %d doorways on the hall theme, %d room purposes with their own floors, %d districts, %d arches in their walls' themes on both sides" % [
			faces, doors, purposes.size(), StreamedRouteGenerator.BIOMES.size(), arches])
	return _failures
