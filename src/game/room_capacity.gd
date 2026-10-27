class_name RoomCapacity
extends RefCounted

## Room-vs-props capacity (docs/ROOM_SIZES.md): for every generated room, how much of its open floor the solid props'
## collision boxes take, how much of the remaining floor a capsule with margin (CollisionWorld.MARGIN_RADIUS) reaches
## from the door, and whether the room got its signature props (RoomSizeProfiles). Summarised per room type and seed, so
## a room type that cannot hold its furniture plus a walking margin shows up as a type, not as one unlucky room.

## Largest share of open floor solid boxes may take (same limit as GeometryAudit's room_capacity rule).
const FILL_LIMIT := 0.45
## Smallest share of the free floor (open minus boxes) a capsule with margin must reach from the door.
const REACH_MIN := 0.70
## Signature props: share of a type's rooms that must carry at least one.
const SIGNATURE_MIN := 0.80


## {types: {room_type: {rooms, fill_max, fill_sum, reach_min, signature_rooms, worst}}, rooms, over_fill: [], under_reach: []}
static func survey(seeds: Array, ring: int) -> Dictionary:
	var out := {"types": {}, "rooms": 0, "over_fill": [], "under_reach": []}
	for seed_text in seeds:
		var generator := StreamedRouteGenerator.new(String(seed_text))
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				chunk_rooms(generator.chunk(coord), "%s %s" % [seed_text, coord], out)
	return out


static func chunk_rooms(data: Dictionary, where: String, out: Dictionary) -> void:
	var world := CollisionWorld.from_chunk(data)
	world.step = CollisionWorld.COARSE_STEP
	var grid: Array = data.get("grid", [])
	var types_by_room := {}
	for prop in data.get("region_props", []):
		var room_id := String(prop.get("room_id", ""))
		if not room_id.is_empty():
			var seen: Dictionary = types_by_room.get(room_id, {})
			seen[String(prop.get("type", ""))] = true
			types_by_room[room_id] = seen
	for room in data.get("rooms", []):
		if bool(room.get("suite_parent", false)):
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		var type := String(room.get("room_type", ""))
		var open := 0
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if world.is_open_cell(Vector2i(x, z)):
					open += 1
		if open <= 0:
			continue
		var used := 0.0
		for rect_value in world.rects:
			var box: Dictionary = rect_value
			if Rect2(rect).has_point(box["center"]):
				used += (box["half"] as Vector2).x * (box["half"] as Vector2).y * 4.0
		var fill := used / float(open)
		var area := Rect2(Vector2(rect.position) - Vector2.ONE, Vector2(rect.size) + Vector2(2, 2))
		world.focus(Rect2(rect))
		var standable := world.standable_set(area, CollisionWorld.MARGIN_RADIUS)
		var reached := {}
		var door: Vector2i = room.get("doorway", Vector2i(-1, -1))
		if door.x >= 0:
			reached = world.flood_in(standable, area, Vector2(door) + Vector2(.5, .5))
		world.focus(Rect2())
		world.use_local = false
		# raster points inside the room, standable or reached
		var free_points := 0
		var reached_points := 0
		for key in standable:
			var p := world.point_of(key, area)
			if Rect2(rect).has_point(p):
				free_points += 1
				if reached.has(key):
					reached_points += 1
		var reach := float(reached_points) / maxf(1.0, float(free_points)) if door.x >= 0 else 1.0
		var signature: Array = RoomSizeProfiles.profile(type).get("signature", [])
		var has_signature := signature.is_empty()
		for sig in signature:
			if (types_by_room.get(String(room.get("id", "")), {}) as Dictionary).has(sig):
				has_signature = true
		var t: Dictionary = out["types"].get(type, {"rooms": 0, "fill_max": 0.0, "fill_sum": 0.0, "reach_min": 1.0,
			"signature_rooms": 0, "wants_signature": not signature.is_empty()})
		t["rooms"] += 1
		t["fill_max"] = maxf(float(t["fill_max"]), fill)
		t["fill_sum"] += fill
		t["reach_min"] = minf(float(t["reach_min"]), reach)
		if has_signature:
			t["signature_rooms"] += 1
		out["types"][type] = t
		out["rooms"] += 1
		var label := "%s %s %s %s" % [where, room.get("id", ""), type, rect.size]
		if fill > FILL_LIMIT:
			out["over_fill"].append("%s fill %.0f%%" % [label, fill * 100.0])
		if reach < REACH_MIN:
			out["under_reach"].append("%s reach %.0f%%" % [label, reach * 100.0])


static func table(survey_result: Dictionary) -> String:
	var lines := ["  %-22s %5s %6s %6s %6s %5s" % ["room type", "rooms", "fill~", "fill^", "reach_", "sig"]]
	var types: Array = survey_result["types"].keys()
	types.sort()
	for type in types:
		var t: Dictionary = survey_result["types"][type]
		lines.append("  %-22s %5d %5.0f%% %5.0f%% %5.0f%% %5s" % [type, t["rooms"], float(t["fill_sum"]) / t["rooms"] * 100.0,
			float(t["fill_max"]) * 100.0, float(t["reach_min"]) * 100.0,
			("%d%%" % roundi(float(t["signature_rooms"]) / t["rooms"] * 100.0)) if bool(t["wants_signature"]) else "-"])
	return "\n".join(lines)
