extends RefCounted

## One ceiling fixture family per room, and the mansion's luxury ceilings (docs/MANSION_LUXURY.md):
## - the room recipes never leave a chandelier, a fan and a plain ceiling light mixed in one room;
## - the ref-look decor adds no chandelier, pendant or strip lamp to a room whose recipe placed its own ceiling fixture;
## - mansion rooms have no fans or strip lights, every mansion chandelier has a ceiling medallion, and mansion rooms get
##   crown moulding and coffered ceilings.
##
##   godot --headless --path . res://scenes/validate.tscn -- ceiling_fixtures

const SEEDS := ["CEIL-A", "CEIL-B", "CEIL-C"]
const DECOR_FIXTURES := ["chandelier", "chandelier_grand", "ceiling", "ceiling_small"]

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var rooms_checked := 0
	var mansion_rooms := 0
	var mixed := []
	var mansion_fans := []
	var decor_doubles := []
	var mansion_decor := {"medallion": 0, "chandeliers": 0, "crown": 0, "coffer": 0}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				var region := String(data.get("region", ""))
				var families_by_room := {}
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					var family := String(StreamedRouteGenerator.CEILING_FIXTURE_FAMILY.get(String(prop.get("type", "")), ""))
					var room_id := String(prop.get("room_id", ""))
					if family.is_empty() or room_id.is_empty():
						continue
					var families: Dictionary = families_by_room.get(room_id, {})
					families[family] = true
					families_by_room[room_id] = families
					if region == "mansion" and family != "chandelier":
						mansion_fans.append("%s %s" % [room_id, prop.get("type", "")])
				for room_id in families_by_room:
					rooms_checked += 1
					if (families_by_room[room_id] as Dictionary).size() > 1:
						mixed.append("%s %s" % [room_id, (families_by_room[room_id] as Dictionary).keys()])
				# the decor for this chunk, built headless
				var root := Node3D.new()
				var decor := RefDecor.new(root, data, {}, {}, 3.3)
				var guard := 0
				while not decor.step() and guard < 200:
					guard += 1
				for key in DECOR_FIXTURES:
					for t_value in decor._transforms.get(key, []):
						var t: Transform3D = t_value
						var room_id := decor._room_id_at(Vector2i(floori(t.origin.x), floori(t.origin.z)))
						if families_by_room.has(room_id):
							decor_doubles.append("%s %s over %s" % [room_id, key, (families_by_room[room_id] as Dictionary).keys()])
				if region == "mansion":
					mansion_rooms += (data.get("rooms", []) as Array).size()
					mansion_decor["medallion"] += (decor._transforms.get("medallion", []) as Array).size()
					mansion_decor["crown"] += (decor._transforms.get("crown", []) as Array).size()
					mansion_decor["coffer"] += (decor._transforms.get("coffer", []) as Array).size()
					var hung := (decor._transforms.get("chandelier", []) as Array).size() \
						+ (decor._transforms.get("chandelier_grand", []) as Array).size()
					for prop_value in data.get("region_props", []):
						if String((prop_value as Dictionary).get("type", "")) == "diningChandelier":
							hung += 1
					mansion_decor["chandeliers"] += hung
				root.free()
	_expect(rooms_checked > 50, "only %d rooms with ceiling fixtures in the sample" % rooms_checked)
	_expect(mixed.is_empty(), "%d rooms mix ceiling fixture families: %s" % [mixed.size(), mixed.slice(0, 5)])
	_expect(decor_doubles.is_empty(), "%d decor fixtures in rooms whose recipe has its own: %s" % [decor_doubles.size(), decor_doubles.slice(0, 5)])
	_expect(mansion_rooms > 0, "no mansion chunk in the sample")
	_expect(mansion_fans.is_empty(), "plain fans or strip lights in the mansion: %s" % [mansion_fans.slice(0, 5)])
	_expect(int(mansion_decor["medallion"]) >= int(mansion_decor["chandeliers"]) and int(mansion_decor["chandeliers"]) > 0,
		"mansion chandeliers without a ceiling medallion (%d medallions, %d chandeliers)" % [mansion_decor["medallion"], mansion_decor["chandeliers"]])
	_expect(int(mansion_decor["crown"]) > 0 and int(mansion_decor["coffer"]) > 0, "mansion rooms have no crown moulding or coffers")
	metrics = {"rooms": rooms_checked, "mansion": mansion_decor}
	if _failures == 0:
		print("  ceiling_fixtures  %s" % [metrics])
	return _failures
