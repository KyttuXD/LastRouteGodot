extends SceneTree

## Set-dressing audit per room type over real generated chunks: how many rooms, floor area, solid props, floor coverage of
## the colliders, wall decor, lights, rugs, distinct prop types, so sparse and cluttered rooms stand out.
##   godot --headless --path . -s tools/look/room_audit.gd -- [SEEDS_CSV]

func _init() -> void:
	var seeds := ["DRESS-A", "DRESS-B", "DRESS-C"]
	if OS.get_cmdline_user_args().size() > 0:
		seeds = Array(OS.get_cmdline_user_args()[0].split(","))
	var stats := {}
	for seed_text in seeds:
		var generator := StreamedRouteGenerator.new(String(seed_text))
		var per_biome := {}
		for r in range(0, 10):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var coord := Vector3i(dx, 0, dz)
					if not generator.is_chunk_allowed(coord):
						continue
					var biome := generator.biome_for(coord)
					per_biome[biome] = int(per_biome.get(biome, 0)) + 1
					if int(per_biome[biome]) > 10:
						continue
					_chunk(generator.chunk(coord), biome, stats)
	var keys := stats.keys()
	keys.sort()
	print("%-34s %5s %6s %6s %6s %6s %6s %6s %6s" % ["region/type", "rooms", "area", "solid", "cover%", "wall", "light", "rug", "types"])
	for key in keys:
		var s: Dictionary = stats[key]
		var n := float(s["rooms"])
		print("%-34s %5d %6.0f %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f" % [key, s["rooms"], float(s["area"]) / n, float(s["solid"]) / n,
			100.0 * float(s["cover"]) / maxf(1.0, float(s["area"])), float(s["wall"]) / n, float(s["light"]) / n, float(s["rug"]) / n,
			float(s["types"]) / n])
	quit()


func _chunk(data: Dictionary, biome: String, stats: Dictionary) -> void:
	for room in data.get("rooms", []):
		if bool(room.get("suite_parent", false)):
			continue
		var rect: Rect2i = room["rect"]
		var key := "%s/%s" % [biome, room.get("room_type", "")]
		if not stats.has(key):
			stats[key] = {"rooms": 0, "area": 0.0, "solid": 0, "cover": 0.0, "wall": 0, "light": 0, "rug": 0, "types": 0}
		var s: Dictionary = stats[key]
		s["rooms"] += 1
		s["area"] += float(rect.size.x * rect.size.y)
		var types := {}
		for prop in data.get("region_props", []):
			var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
			if not rect.has_point(cell) or bool(prop.get("room_door", false)):
				continue
			var type := String(prop.get("type", ""))
			types[type] = true
			if not bool(prop.get("solid", true)):
				if bool(prop.get("wall_mounted", false)) or PropModelCatalog.is_wall_mounted(type):
					s["wall"] += 1
				elif PropModelCatalog.is_ceiling_mounted(type):
					s["light"] += 1
				elif PropModelCatalog.is_floor_dressing(type):
					s["rug"] += 1
				continue
			s["solid"] += 1
			var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
			s["cover"] += size.x * size.z
		s["types"] += types.size()
