extends RefCounted

## KT: "room generation seeds are too specific". Over 8 seeds, the furnished rooms of each type (12 or more of them) come in
## many different layouts: the share of distinct layouts (prop types at room-relative cells) is at least MIN_DISTINCT, and
## the same seed builds the same rooms (co-op guests match the host).
##
##   godot --headless --path . res://scenes/validate.tscn -- room_variety

const SEEDS := ["VARIETY-A", "VARIETY-B", "SOAKTEST", "ENDLESS-ROUTE", "KYTTU-LAB", "REAL-B", "BIOME-A", "PICKUPS"]
const RADIUS := 3
const MIN_DISTINCT := 0.45
const MIN_ROOMS := 12

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var layouts := {}
	var counts := {}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				for room in data.get("rooms", []):
					if bool(room.get("suite_parent", false)):
						continue   # a suite's parent room holds only its rooms
					var signature := _signature(data, room)
					if signature.is_empty():
						continue
					var type := String(room.get("room_type", ""))
					counts[type] = int(counts.get(type, 0)) + 1
					if not layouts.has(type):
						layouts[type] = {}
					(layouts[type] as Dictionary)[signature] = true
		if seed_text == SEEDS[0]:
			var twin := StreamedRouteGenerator.new(seed_text)
			_expect(_signature(twin.chunk(Vector3i(1, 0, 1)), {}) == _signature(generator.chunk(Vector3i(1, 0, 1)), {}),
				"the same seed builds different rooms")
	var low := []
	var checked := 0
	var total_share := 0.0
	for type in counts:
		if int(counts[type]) < MIN_ROOMS:
			continue
		checked += 1
		var share := float((layouts[type] as Dictionary).size()) / float(counts[type])
		total_share += share
		if share < MIN_DISTINCT:
			low.append("%s %d/%d" % [type, (layouts[type] as Dictionary).size(), counts[type]])
	_expect(checked >= 10, "only %d room types with %d+ rooms sampled" % [checked, MIN_ROOMS])
	_expect(low.is_empty(), "room types with too few distinct layouts (below %d%%): %s" % [roundi(MIN_DISTINCT * 100), low])
	if _failures == 0:
		print("  room_variety  %d room types, mean %.0f%% distinct layouts (min %d%%)" % [checked, 100.0 * total_share / maxi(checked, 1), roundi(MIN_DISTINCT * 100)])
	return _failures


## The room's props as type@cell relative to the room's rect, sorted; empty for an unfurnished room. With an empty room,
## the whole chunk's props.
static func _signature(data: Dictionary, room: Dictionary) -> String:
	var parts: Array[String] = []
	var rect: Rect2i = room.get("rect", Rect2i())
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if not room.is_empty() and String(prop.get("room_id", "")) != String(room.get("id", "")):
			continue
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		parts.append("%s@%s" % [prop.get("type", ""), cell - rect.position])
	parts.sort()
	return "|".join(parts)
