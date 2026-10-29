class_name CollisionAudit
extends RefCounted

## Walk-through audit on the collision model (CollisionWorld) over real generated chunks: from every room door, can a
## capsule reach the door's inside, every interactable in the room and the room's standable floor, and does any solid prop
## reach into a door's keep-clear zone? Used by the `collision` validator and tools/look/collision_audit.gd.

const RADII := [CollisionWorld.PLAYER_RADIUS, CollisionWorld.MARGIN_RADIUS, CollisionWorld.LANE_RADIUS]


static func run(seeds: Array, per_region_limit: int) -> Dictionary:
	var totals := {"rooms": 0, "zone_violations": 0}
	for r in RADII:
		totals["door_blocked_%.1f" % r] = 0
		totals["target_unreached_%.1f" % r] = 0
		totals["pocket_m2_%.1f" % r] = 0.0
		totals["big_pockets_%.1f" % r] = 0
	var samples := {}
	var per_region := {}
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
					var region := generator.region_for(coord)
					per_region[region] = int(per_region.get(region, 0)) + 1
					if int(per_region[region]) > per_region_limit * seeds.size():
						continue
					chunk_report(generator.chunk(coord), region, coord, RADII, totals, samples)
	return {"totals": totals, "samples": samples}


static func chunk_report(data: Dictionary, region: String, coord: Vector3i, radii: Array, totals: Dictionary, samples: Dictionary) -> void:
	var world := CollisionWorld.from_chunk(data)
	var rooms := {}
	for room in data.get("rooms", []):
		rooms[String(room.get("id", ""))] = room
	for v in world.zone_violations():
		totals["zone_violations"] += 1
		_sample(samples, "zone", "%s %s door %s <- %s" % [region, coord, v["door"], v["prop"]])
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
				_sample(samples, "door_blocked_%.1f" % radius, "%s %s %s door %s room %s" % [region, coord, door["room_id"], cell, rect])
				continue
			for t in targets:
				if not world.reached_near(reached, area, t["at"], t["within"]):
					totals["target_unreached_%.1f" % radius] += 1
					_sample(samples, "target_%.1f" % radius, "%s %s %s %s" % [region, coord, door["room_id"], t["name"]])
			# standable floor in the room that the door cannot reach
			var cut := 0
			var cut_points := {}
			var x := float(rect.position.x) + 0.5
			while x < rect.end.x - 0.5:
				var y := float(rect.position.y) + 0.5
				while y < rect.end.y - 0.5:
					var p := Vector2(x, y)
					if world.can_stand(p, radius) and not world.reached_near(reached, area, p, 0.26):
						cut += 1
						cut_points[Vector2i(roundi(x * 2.0), roundi(y * 2.0))] = true
					y += 0.5
				x += 0.5
			if cut > 0:
				totals["pocket_m2_%.1f" % radius] += float(cut) * 0.25
				# isolated points (a gap between two chairs) are not pockets: a pocket is a connected patch of 1.5 m2 or more
				var largest := _largest_patch(cut_points)
				if largest >= 6:
					totals["big_pockets_%.1f" % radius] += 1
					_sample(samples, "pocket_%.1f" % radius, "%s %s room %s cut-off patch %.1f m2" % [region, coord, rect, largest * 0.25])


static func _largest_patch(points: Dictionary) -> int:
	var seen := {}
	var best := 0
	for start in points:
		if seen.has(start):
			continue
		var size := 0
		var frontier := [start]
		seen[start] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_back()
			size += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = current + d
				if points.has(next) and not seen.has(next):
					seen[next] = true
					frontier.append(next)
		best = maxi(best, size)
	return best


static func _sample(samples: Dictionary, key: String, text: String) -> void:
	var list: Array = samples.get(key, [])
	if list.size() < 4:
		list.append(text)
	samples[key] = list
