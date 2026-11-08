extends RefCounted

## One ceiling fixture family per room, and the mansion's luxury ceilings:
## - the room recipes never leave a chandelier, a fan and a plain ceiling light mixed in one room;
## - the ref-look decor adds no chandelier, pendant or strip lamp to a room whose recipe placed its own ceiling fixture;
## - mansion rooms have no fans or strip lights, every mansion chandelier has a ceiling medallion, and mansion rooms get
##   crown moulding and coffered ceilings.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- ceiling_fixtures

const SEEDS := ["CEIL-A", "CEIL-B", "CEIL-C"]
const DECOR_FIXTURES := ["chandelier", "chandelier_grand", "beach_pendant", "ceiling", "ceiling_small"]

const TOLERANCE := .05

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
	var layout_report := {"rooms": 0, "bad": []}
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
				_check_layout(data, decor, layout_report)
				root.free()
	_expect(rooms_checked > 50, "only %d rooms with ceiling fixtures in the sample" % rooms_checked)
	_expect(mixed.is_empty(), "%d rooms mix ceiling fixture families: %s" % [mixed.size(), mixed.slice(0, 5)])
	_expect(decor_doubles.is_empty(), "%d decor fixtures in rooms whose recipe has its own: %s" % [decor_doubles.size(), decor_doubles.slice(0, 5)])
	_expect(mansion_rooms > 0, "no mansion chunk in the sample")
	_expect(mansion_fans.is_empty(), "plain fans or strip lights in the mansion: %s" % [mansion_fans.slice(0, 5)])
	_expect(int(mansion_decor["medallion"]) >= int(mansion_decor["chandeliers"]) and int(mansion_decor["chandeliers"]) > 0,
		"mansion chandeliers without a ceiling medallion (%d medallions, %d chandeliers)" % [mansion_decor["medallion"], mansion_decor["chandeliers"]])
	_expect(int(mansion_decor["crown"]) > 0 and int(mansion_decor["coffer"]) > 0, "mansion rooms have no crown moulding or coffers")
	_expect(int(layout_report["rooms"]) > 100, "only %d rooms with fixtures checked for layout" % layout_report["rooms"])
	_expect((layout_report["bad"] as Array).is_empty(), "%d rooms with off-centre or uneven fixtures: %s" % [
		(layout_report["bad"] as Array).size(), (layout_report["bad"] as Array).slice(0, 6)])
	metrics = {"rooms": rooms_checked, "layout_rooms": layout_report["rooms"], "mansion": mansion_decor}
	if _failures == 0:
		print("  ceiling_fixtures  %s" % [metrics])
	return _failures


## "center or even with the room". Every room's ceiling fixtures (decor or recipe props) are symmetric about the
## room's interior centre (each mirrors onto another within TOLERANCE) and evenly spaced along each axis.
func _check_layout(data: Dictionary, decor: RefDecor, report: Dictionary) -> void:
	var by_room := {}
	for key in DECOR_FIXTURES:
		for t_value in decor._transforms.get(key, []):
			var at := Vector2((t_value as Transform3D).origin.x, (t_value as Transform3D).origin.z)
			var room_id := decor._room_id_at(Vector2i(floori(at.x), floori(at.y)))
			if not room_id.is_empty():
				if not by_room.has(room_id):
					by_room[room_id] = []
				(by_room[room_id] as Array).append(at)
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if not StreamedRouteGenerator.CEILING_FIXTURE_FAMILY.has(String(prop.get("type", ""))):
			continue
		var room_id := String(prop.get("room_id", ""))
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		if not by_room.has(room_id):
			by_room[room_id] = []
		(by_room[room_id] as Array).append(Vector2(cell) + Vector2(.5, .5) + (prop.get("placement_offset", Vector2.ZERO) as Vector2))
	var rects := {}
	for room_value in data.get("rooms", []):
		rects[String((room_value as Dictionary).get("id", ""))] = (room_value as Dictionary).get("rect", Rect2i())
	for room_id in by_room:
		if not rects.has(room_id):
			continue
		var rect: Rect2i = rects[room_id]
		var centre := Vector2(rect.position) + Vector2(rect.size) * .5
		var points: Array = by_room[room_id]
		report["rooms"] = int(report["rooms"]) + 1
		var problem := ""
		for p_value in points:
			var mirror: Vector2 = centre * 2.0 - (p_value as Vector2)
			if not points.any(func(q: Vector2) -> bool: return q.distance_to(mirror) <= TOLERANCE):
				problem = "not symmetric about the centre"
				break
		if problem.is_empty():
			for axis in 2:
				var values := []
				for p_value in points:
					var v := snappedf((p_value as Vector2)[axis], .01)
					if not values.any(func(w: float) -> bool: return absf(w - v) <= TOLERANCE):
						values.append(v)
				values.sort()
				for i in range(2, values.size()):
					if absf((values[i] - values[i - 1]) - (values[1] - values[0])) > TOLERANCE:
						problem = "uneven spacing"
		if not problem.is_empty():
			(report["bad"] as Array).append("%s %s %s" % [room_id, problem, points.slice(0, 4)])

