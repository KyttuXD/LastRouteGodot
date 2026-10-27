class_name CollisionAudit
extends RefCounted

## Walk-through audit on the collision model (CollisionWorld) over real generated chunks: from every room door, can a
## capsule reach the door's inside, every interactable in the room and the room's standable floor, and does any solid prop
## reach into a door's keep-clear zone? Used by the `collision` validator and tools/look/collision_audit.gd.

const RADII := [CollisionWorld.PLAYER_RADIUS, CollisionWorld.MARGIN_RADIUS, CollisionWorld.LANE_RADIUS]


static func run(seeds: Array, per_biome_limit: int) -> Dictionary:
	var totals := {"rooms": 0, "zone_violations": 0}
	for r in RADII:
		totals["door_blocked_%.1f" % r] = 0
		totals["target_unreached_%.1f" % r] = 0
		totals["pocket_m2_%.1f" % r] = 0.0
		totals["big_pockets_%.1f" % r] = 0
	var samples := {}
	var per_biome := {}
	for seed_text in seeds:
		var generator := StreamedRouteGenerator.new(String(seed_text))
		for r in range(0, 12):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var coord := Vector3i(dx, 0, dz)
					if not generator.is_chunk_allowed(coord):
						continue
					var biome := generator.biome_for(coord)
					per_biome[biome] = int(per_biome.get(biome, 0)) + 1
					if int(per_biome[biome]) > per_biome_limit * seeds.size():
						continue
					chunk_report(generator.chunk(coord), biome, coord, RADII, totals, samples)
	return {"totals": totals, "samples": samples}


static func chunk_report(data: Dictionary, biome: String, coord: Vector3i, radii: Array, totals: Dictionary, samples: Dictionary) -> void:
	var world := CollisionWorld.from_chunk(data)
	var rooms := {}
	for room in data.get("rooms", []):
		rooms[String(room.get("id", ""))] = room
	for v in world.zone_violations():
		totals["zone_violations"] += 1
		_sample(samples, "zone", "%s %s door %s <- %s" % [biome, coord, v["door"], v["prop"]])
	for door in world.doors:
		var room: Dictionary = rooms.get(String(door.get("room_id", "")), {})
		if room.is_empty():
			continue
		totals["rooms"] += 1
		var rect: Rect2i = room["rect"]
		var cell: Vector2i = door["cell"]
		var inward: Vector2i = door.get("inward", Vector2i(0, -1))
		var outward: Vector2i = door.get("outward", Vector2i(0, 1))
		var area := Rect2(Vector2(rect.position) - Vector2(4, 4), Vector2(rect.size) + Vector2(8, 8))
		var outside := Vector2(cell) + Vector2(.5, .5) + Vector2(outward) * 1.0
		var targets := []
		for pickup in data.get("pickups", []):
			if rect.has_point(pickup["cell"]):
				targets.append({"name": "pickup %s" % pickup["kind"], "at": Vector2(pickup["cell"]) + Vector2(.5, .5), "within": 0.8})
		for fixture in data.get("fixtures", []):
			if rect.has_point(fixture["cell"]):
				var open: Vector2i = fixture.get("open_direction", Vector2i.ZERO)
				targets.append({"name": "fixture %s" % fixture["kind"], "at": Vector2(fixture["cell"]) + Vector2(.5, .5) + Vector2(open) * 0.6, "within": 0.6})
		for radius in radii:
			var reached := world.flood(outside, radius, area)
			var inside := Vector2(cell) + Vector2(.5, .5) + Vector2(inward) * 1.0
			if not world.reached_near(reached, area, inside, 0.3):
				totals["door_blocked_%.1f" % radius] += 1
				_sample(samples, "door_blocked_%.1f" % radius, "%s %s %s door %s room %s" % [biome, coord, door["room_id"], cell, rect])
				continue
			for t in targets:
				if not world.reached_near(reached, area, t["at"], t["within"]):
					totals["target_unreached_%.1f" % radius] += 1
					_sample(samples, "target_%.1f" % radius, "%s %s %s %s" % [biome, coord, door["room_id"], t["name"]])
			# standable floor in the room that the door cannot reach
			var cut := 0
			var x := float(rect.position.x) + 0.5
			while x < rect.end.x - 0.5:
				var y := float(rect.position.y) + 0.5
				while y < rect.end.y - 0.5:
					var p := Vector2(x, y)
					if world.can_stand(p, radius) and not world.reached_near(reached, area, p, 0.26):
						cut += 1
					y += 0.5
				x += 0.5
			if cut > 0:
				totals["pocket_m2_%.1f" % radius] += float(cut) * 0.25
				if cut >= 6:
					totals["big_pockets_%.1f" % radius] += 1
					_sample(samples, "pocket_%.1f" % radius, "%s %s room %s cut-off %.1f m2" % [biome, coord, rect, cut * 0.25])


static func _sample(samples: Dictionary, key: String, text: String) -> void:
	var list: Array = samples.get(key, [])
	if list.size() < 4:
		list.append(text)
	samples[key] = list
