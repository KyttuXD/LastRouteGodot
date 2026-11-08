extends RefCounted

## Regions as data (docs/DATA_DRIVEN_CONTENT.md): every res://data/regions file passes the schema and its references
## resolve, the Mall pilot is exactly the constants it replaced, and generated chunks of every data region are
## connected, deterministic and use only props that have models. The parity fingerprint is printed for the
## before/after comparison. Door clearance at hunter scale stays with the door_clearance suite.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- data_regions

const Parity := preload("res://tests/data_parity.gd")

## The Mall as it was in FloorSets and StreamedRouteGenerator before the pilot moved it to data/regions/mall.json.
const MALL_HALL := {"floor": ["terrazzo0", "terrazzo1"], "runner": false}
const MALL_ROOM_DEFAULT := ["terrazzo0"]
const MALL_ROOMS := ["donut_shop", "cinema", "corner_store", "food_court", "bakery", "laundromat", "electronics",
	"night_diner", "drugstore", "florist", "barber", "pawn_shop", "stationery", "music_store"]
const SHOP_NAMES := {"donut_shop": "DONUT COUNTER", "cinema": "CINEMA", "corner_store": "24/7 CORNER",
	"food_court": "FOOD COURT", "bakery": "BAKERY", "laundromat": "LAUNDROMAT", "electronics": "ARCADE & ELECTRONICS",
	"night_diner": "NIGHT DINER", "drugstore": "PHARMACY", "florist": "FLORIST", "barber": "BARBER",
	"pawn_shop": "PAWN & LOAN", "stationery": "STATIONERY & READING",
	"music_store": "MUSIC & SOUND"}
const MALL_PROP_SET := [
	{"type": "mallBench", "size": Vector3(1.8, .5, .6)},
	{"type": "mallPlanter", "size": Vector3(1.3, 2.4, 1.3)},
	{"type": "shopShelf", "size": Vector3(1.2, 1.9, .5)},
	{"type": "vendingMachine", "size": Vector3(.85, 1.9, .6)},
	{"type": "menuBoard", "size": Vector3(1.5, .9, .08), "solid": false},
]

## The hospital as it was in FloorSets and StreamedRouteGenerator before it moved to data/regions/hospital.json.
## It has no room-door entries: those maps stay without a hospital key.
const HOSPITAL_HALL := {"floor": ["vinyl0", "vinyl1"], "runner": false}
const HOSPITAL_ROOM_DEFAULT := ["vinyl0", "vinyl1"]
const HOSPITAL_ROOMS := ["ward", "nurses_station", "waiting_room", "operating_theatre", "icu", "morgue",
	"pharmacy", "imaging", "supply_closet"]
const HOSPITAL_PROP_SET := [
	{"type": "hospitalBed", "size": Vector3(.95, 1.05, 2.1)},
	{"type": "wheelchair", "size": Vector3(.65, .95, .95)},
	{"type": "ivDripStand", "size": Vector3(.45, 1.95, .45)},
	{"type": "medicalSupplyRack", "size": Vector3(1.2, 1.9, .5)},
	{"type": "waitingChairs", "size": Vector3(2.0, .86, .62)},
	{"type": "hospitalWardSign", "size": Vector3(.95, .36, .06), "solid": false},
	{"type": "xrayLightbox", "size": Vector3(1.3, .85, .08), "solid": false},
]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_expect(ContentRegistry.errors().is_empty(), "res://data has errors: %s" % ", ".join(ContentRegistry.errors()))
	for id in ContentRegistry.ids("regions"):
		var def := ContentRegistry.get_def("regions", id)
		_expect(StreamedRouteGenerator.REGIONS.has(id), "data region %s is not a generator region" % id)
		for choice in def["prop_set"]:
			_expect(PropModelCatalog.has_model(String(choice["type"])), "%s prop_set names %s, which has no model"
				% [id, choice["type"]])
		for key in ["room_door", "double_room_door"]:
			if def.has(key):
				_expect(PropModelCatalog.has_model(String(def[key])), "%s %s %s has no model" % [id, key, def[key]])
		_check_generation(id)
	# pilot parity with the constants as they were
	_same(FloorSets.HALLS.get("mall"), MALL_HALL, "FloorSets.HALLS[mall]")
	_same(FloorSets.ROOM_DEFAULT.get("mall"), MALL_ROOM_DEFAULT, "FloorSets.ROOM_DEFAULT[mall]")
	_same(StreamedRouteGenerator.MALL_ROOMS, MALL_ROOMS, "StreamedRouteGenerator.MALL_ROOMS")
	_same(StreamedRouteGenerator.SHOP_NAMES, SHOP_NAMES, "StreamedRouteGenerator.SHOP_NAMES")
	_same(StreamedRouteGenerator.REGION_ROOM_DOORS.get("mall"), "normalRoomDoor", "REGION_ROOM_DOORS[mall]")
	_same(StreamedRouteGenerator.REGION_DOUBLE_ROOM_DOORS.get("mall"), "normalDoubleRoomDoor", "REGION_DOUBLE_ROOM_DOORS[mall]")
	_same(StreamedRouteGenerator.REGION_PROP_SETS.get("mall"), MALL_PROP_SET, "REGION_PROP_SETS[mall]")
	_same(FloorSets.HALLS.get("hospital"), HOSPITAL_HALL, "FloorSets.HALLS[hospital]")
	_same(FloorSets.ROOM_DEFAULT.get("hospital"), HOSPITAL_ROOM_DEFAULT, "FloorSets.ROOM_DEFAULT[hospital]")
	_same(StreamedRouteGenerator.HOSPITAL_ROOMS, HOSPITAL_ROOMS, "StreamedRouteGenerator.HOSPITAL_ROOMS")
	_same(StreamedRouteGenerator.REGION_PROP_SETS.get("hospital"), HOSPITAL_PROP_SET, "REGION_PROP_SETS[hospital]")
	_expect(not StreamedRouteGenerator.REGION_ROOM_DOORS.has("hospital"), "hospital gained a room door")
	_expect(not StreamedRouteGenerator.REGION_DOUBLE_ROOM_DOORS.has("hospital"), "hospital gained a double room door")
	for table in [FloorSets.HALLS, FloorSets.ROOM_DEFAULT, StreamedRouteGenerator.REGION_ROOM_DOORS,
			StreamedRouteGenerator.REGION_DOUBLE_ROOM_DOORS, StreamedRouteGenerator.REGION_PROP_SETS]:
		_expect(not table.values().has(ContentRegistry.DATA), "an unresolved @data value is left")
		_expect(table.is_read_only(), "a region table became writable")
	_check_rejections()
	print("  parity regions %s" % Parity.region_hash("mall"))
	print("  parity hospital %s" % Parity.region_hash("hospital"))
	if _failures == 0:
		print("  data_regions OK")
	return _failures


func _same(actual, expected, what: String) -> void:
	_expect(var_to_str(actual) == var_to_str(expected), "%s differs from the old constant: %s" % [what, var_to_str(actual)])


## Generate-and-check: four chunks of the region, connected open space, every room with a door cell open, same seed
## gives the same chunk, and every region prop has a model.
func _check_generation(region: String) -> void:
	var first := StreamedRouteGenerator.new("DATA-REGIONS")
	var second := StreamedRouteGenerator.new("DATA-REGIONS")
	var coords := Parity.chunks_of(first, region, 4)
	_expect(not coords.is_empty(), "no %s chunk found near the origin" % region)
	for coord in coords:
		var data := first.chunk(coord)
		_expect(String(data.get("region", "")) == region, "%s: chunk %s is %s" % [region, coord, data.get("region")])
		_expect(StreamedRouteGenerator._open_components(data["grid"]) == 1, "%s: chunk %s open space is split" % [region, coord])
		_expect(var_to_str(data) == var_to_str(second.chunk(coord)), "%s: chunk %s is not deterministic" % [region, coord])
		for prop in data.get("region_props", []):
			var type := String(prop.get("type", ""))
			_expect(PropModelCatalog.has_model(type) or BlockyPropModels.MODELS.has(type),
				"%s: chunk %s places %s, which has no model" % [region, coord, type])


func _check_rejections() -> void:
	var cases := {
		'{"schema": "lr.region/1", "id": "x", "hall_floor": [], "hall_runner": false, "room_default_floor": [], "room_roles": [], "prop_set": [{"type": "a", "size": [1, 2]}]}': "\"prop_set\" must be prop_set",
		'{"schema": "lr.region/1", "id": "x", "hall_floor": [], "hall_runner": false, "room_default_floor": [], "room_roles": []}': "missing \"prop_set\"",
		'{"schema": "lr.region/1", "id": "x", "hall_floor": [], "hall_runner": "no", "room_default_floor": [], "room_roles": [], "prop_set": []}': "\"hall_runner\" must be bool",
	}
	var path := "user://data_regions_fixture.json"
	for text in cases:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var parsed := ContentRegistry.parse_file(path, "regions")
		var joined := " | ".join(parsed["errors"])
		_expect((parsed["defs"] as Array).is_empty() and path in joined and String(cases[text]) in joined,
			"bad region file not rejected clearly (%s): %s" % [cases[text], joined])
	DirAccess.remove_absolute(path)
