extends RefCounted

## "a gothic bedroom is nearly empty, no bed". Every bedroom-purpose room (bedroom, guest_room, gothic mourning_room)
## big enough to be furnished holds a bed. The same sample is counted with StreamedRouteGenerator.guarantee_beds off
## (the old behaviour) for the report.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- bedrooms

const SEEDS := ["BED-A", "BED-B", "BED-C"]
const BEDROOM_TYPES := ["bedroom", "guest_room", "mourning_room"]
## Those room types are generated only in these districts (hotel guest rooms, mansion/apartment bedrooms,
## gothic mourning rooms). Other districts in the window have none, so they are not built.
const BED_REGIONS := ["mansion", "gothic", "apartment", "hotel"]

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _count() -> Dictionary:
	var rooms := 0
	var bedless := []
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for level in [0, 1, 2]:
			for dz in range(-6, 7):
				for dx in range(-6, 7):
					var coord := Vector3i(dx, level, dz)
					if not generator.is_chunk_allowed(coord) or not BED_REGIONS.has(generator.region_for(coord)):
						continue
					var data := generator.chunk(coord)
					var beds := {}
					for prop in data.get("region_props", []):
						if PropModelCatalog.interaction_for(String((prop as Dictionary).get("type", ""))) == "lay":
							beds[String((prop as Dictionary).get("room_id", ""))] = true
					for room_value in data.get("rooms", []):
						var room: Dictionary = room_value
						var type := String(room.get("room_type", ""))
						var rect: Rect2i = room.get("rect", Rect2i())
						if not BEDROOM_TYPES.has(type) or rect.size.x < 5 or rect.size.y < 5 or bool(room.get("suite_parent", false)):
							continue
						if type == "mourning_room" and String(data.get("region", "")) != "gothic":
							continue
						rooms += 1
						if not beds.has(String(room.get("id", ""))):
							bedless.append("%s %s %s %s" % [data.get("region", ""), type, room.get("id", ""), rect.size])
	return {"rooms": rooms, "bedless": bedless}


func run(_host: Node) -> int:
	StreamedRouteGenerator.guarantee_beds = false
	var before := _count()
	StreamedRouteGenerator.guarantee_beds = true
	var after := _count()
	metrics = {"bedrooms": after["rooms"], "bedless_before": (before["bedless"] as Array).size(),
		"bedless_after": (after["bedless"] as Array).size()}
	print("  bedrooms  before: %s" % [(before["bedless"] as Array).slice(0, 6)])
	_expect(int(after["rooms"]) > 50, "only %d bedrooms sampled" % after["rooms"])
	_expect((after["bedless"] as Array).is_empty(), "%d bedrooms have no bed: %s" % [(after["bedless"] as Array).size(),
		(after["bedless"] as Array).slice(0, 8)])
	print("  bedrooms  %s" % [metrics])
	return _failures
