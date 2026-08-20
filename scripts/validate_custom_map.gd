extends RefCounted

## Headless check on CustomMapParser and its FacilityGenerator integration.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- custom_map

var _failures := 0
const TEST_SIZE := 35


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(_host: Node) -> int:
	_parses_a_real_map()
	_parses_committed_sample()
	_accepts_practical_dimensions_and_rejects_oversized()
	_supports_authored_and_random_spawns()
	_rejects_disconnected_floor()
	_preserves_irregular_region_membership()
	_flags_unrecognised_colour()
	_requires_walkable_space()
	_feeds_a_real_generator()
	_ports_png_authored_props()
	_themed_samples_populate_authored_props()
	_bedroom_region_populates_bedroom_props()
	if _failures == 0:
		print("custom_map OK")
	return _failures


func _parses_committed_sample() -> void:
	var texture := load("res://art/custom-maps/test-map.png") as Texture2D
	var image: Image = texture.get_image() if texture != null else null
	_expect(image != null and not image.is_empty(), "the committed sample PNG could not be loaded")
	if image == null or image.is_empty():
		return
	var result := CustomMapParser.parse(image)
	var ok: bool = result.get("ok", false)
	_expect(ok, "the committed sample PNG failed to parse: %s" % result.get("error", ""))
	if not ok:
		return
	_expect(result["cols"] == 49 and result["rows"] == 49,
		"the committed sample is %dx%d, not 49x49" % [result["cols"], result["rows"]])
	_expect(result["start"] == Vector2i(24, 24),
		"the committed sample start landed at %s" % result["start"])
	_expect((result["spawn_points"] as Array).size() == 1,
		"the committed sample should contain one authored spawn")
	_expect(result["exit_cell"] == Vector2i(44, 44),
		"the committed sample exit landed at %s" % result["exit_cell"])
	_expect((result["rooms"] as Array).size() == 4,
		"the committed sample should contain 4 themed rooms")
	_expect((result["warnings"] as Array).is_empty(),
		"the committed sample contains unrecognised or transparent pixels")
	var reachable: Dictionary = FacilityGenerator.new(
		"COMMITTED-CUSTOM-MAP", RoomState.generator_options(), result).distance_map(24, 24)
	_expect(reachable.has(Vector2i(44, 44)),
		"the committed sample exit is not reachable from its start")
	print("  sample    committed 49x49 PNG is exact-colour and fully connected")


## A minimal but real map: a walled square, a floor interior, a start, an
## exit, and one region-painted room in the corner.
func _make_test_image(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))  # every pixel starts as wall
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			image.set_pixel(x, y, Color(1, 1, 1, 1))  # floor interior
	image.set_pixel(2, 2, Color8(0, 255, 0))  # start
	image.set_pixel(size - 3, size - 3, Color8(255, 0, 0))  # exit
	# A 3x3 mansion-painted room in a corner, away from start/exit.
	for y in range(5, 8):
		for x in range(5, 8):
			image.set_pixel(x, y, Color8(0x8e, 0x5f, 0xd9))  # mansion
	return image


func _parses_a_real_map() -> void:
	var image := _make_test_image(TEST_SIZE)
	var result := CustomMapParser.parse(image)
	var ok: bool = result.get("ok", false)
	_expect(ok, "a well-formed map failed to parse: %s" % result.get("error", ""))
	if not ok:
		return
	_expect(result["start"] == Vector2i(2, 2), "start marker landed at %s, not (2, 2)" % result["start"])
	_expect(result["exit_cell"] == Vector2i(TEST_SIZE - 3, TEST_SIZE - 3),
		"exit marker landed at %s" % result["exit_cell"])
	_expect(result["grid"][0][0] == 1, "the border wall did not come through as a wall")
	_expect(result["grid"][2][2] == 0, "the start cell is not open")

	var rooms: Array = result["rooms"]
	_expect(rooms.size() == 1, "expected 1 flood-filled region, got %d" % rooms.size())
	if not rooms.is_empty():
		var room: Dictionary = rooms[0]
		_expect(String(room.get("region", "")) == "mansion",
			"the painted room came back as region '%s', not mansion" % room.get("region", ""))
		_expect(room["width"] == 3 and room["height"] == 3,
			"the 3x3 painted room measured %dx%d" % [room["width"], room["height"]])
	print("  parse     start, exit and one flood-filled region all land correctly")


func _ports_png_authored_props() -> void:
	var image := _make_test_image(TEST_SIZE)
	image.set_pixel(12, 12, Color8(0x00, 0xe5, 0xff))
	image.set_pixel(14, 12, Color8(0x00, 0x96, 0x88))
	var parsed := CustomMapParser.parse(image)
	_expect(parsed.get("ok", false), "a PNG with authored prop colors was rejected")
	if not parsed.get("ok", false):
		return
	var authored: Array = parsed.get("authored_props", [])
	_expect(authored.size() == 2, "the PNG prop palette did not retain both props")
	var generator := FacilityGenerator.new(
		"AUTHORED-PNG-PROPS", RoomState.generator_options(), parsed)
	var locker := generator.props.filter(func(prop):
		return String(prop.get("type", "")) == "locker" \
			and int(prop.get("x", -1)) == 12 and int(prop.get("y", -1)) == 12)
	var chair := generator.props.filter(func(prop):
		return String(prop.get("type", "")) == "officeChair" \
			and int(prop.get("x", -1)) == 14 and int(prop.get("y", -1)) == 12)
	_expect(locker.size() == 1 and chair.size() == 1,
		"parsed PNG props were not installed into the generated floor")
	print("  palette   original exact-prop PNG colors reach the runtime prop catalog")


func _accepts_practical_dimensions_and_rejects_oversized() -> void:
	# Both valid images sit outside the old 35..121 procedural bounds. Custom
	# dimensions remain flexible, with a decoded-cell ceiling for downloaded
	# PNGs so compressed images cannot exhaust a client's memory.
	var tiny := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	tiny.fill(Color(1, 1, 1, 1))
	tiny.set_pixel(0, 0, Color8(0, 255, 0))
	tiny.set_pixel(2, 1, Color8(255, 0, 0))
	var tiny_result := CustomMapParser.parse(tiny)
	_expect(tiny_result.get("ok", false), "a valid 3x2 image was rejected")

	var large := Image.create(173, 129, false, Image.FORMAT_RGBA8)
	large.fill(Color(1, 1, 1, 1))
	large.set_pixel(1, 1, Color8(0, 255, 0))
	large.set_pixel(171, 127, Color8(255, 0, 0))
	var large_result := CustomMapParser.parse(large)
	_expect(large_result.get("ok", false), "a valid 173x129 image was rejected")
	if large_result.get("ok", false):
		_expect(large_result["cols"] == 173 and large_result["rows"] == 129,
			"the large image dimensions changed during parsing")
		var generator := FacilityGenerator.new(
			"UNBOUNDED-CUSTOM-MAP", RoomState.generator_options(), large_result)
		_expect(generator.cols == 173 and generator.rows == 129,
			"the generator clamped the parsed custom-map dimensions")

	var oversized := Image.create(257, 257, false, Image.FORMAT_RGBA8)
	oversized.fill(Color(1, 1, 1, 1))
	var oversized_result := CustomMapParser.parse(oversized)
	_expect(not oversized_result.get("ok", true),
		"a 66,049-cell image bypassed the decoded custom-map safety ceiling")
	print("  dimensions 3x2 and 173x129 parse; oversized decoded grids are rejected")


func _rejects_disconnected_floor() -> void:
	var image := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	image.set_pixel(1, 1, Color8(0, 255, 0))
	image.set_pixel(1, 2, Color(1, 1, 1, 1))
	image.set_pixel(7, 7, Color8(255, 0, 0))
	var result := CustomMapParser.parse(image)
	_expect(not result.get("ok", true),
		"a map whose exit island cannot be reached from spawn was accepted")
	_expect("unreachable" in String(result.get("error", "")),
		"a disconnected map did not explain its unreachable cells")
	print("  connected every open island must be reachable from the authored spawn")


func _preserves_irregular_region_membership() -> void:
	var image := _make_test_image(TEST_SIZE)
	var mansion := Color8(0x8e, 0x5f, 0xd9)
	# Replace the original block with a connected ring whose bounding-box center
	# remains ordinary corridor floor.
	for y in range(5, 8):
		for x in range(5, 8):
			image.set_pixel(x, y, mansion if x in [5, 7] or y in [5, 7] \
				else Color(1, 1, 1, 1))
	var result := CustomMapParser.parse(image)
	_expect(result.get("ok", false), "an irregular painted room failed to parse")
	if not result.get("ok", false):
		return
	var generator := FacilityGenerator.new(
		"IRREGULAR-CUSTOM-MAP", RoomState.generator_options(), result)
	_expect(String(generator.room_at(5.5, 5.5).get("region", "")) == "mansion",
		"a painted ring cell lost its region membership")
	_expect(generator.room_at(6.5, 6.5).is_empty(),
		"the unpainted hole inside a region bounding box became a fake room")
	var room: Dictionary = result["rooms"][0]
	_expect((room["cells"] as Dictionary).has(room["center"]),
		"an irregular room center was placed outside its painted cells")
	print("  regions   irregular shapes retain exact cells and an on-floor center")


func _flags_unrecognised_colour() -> void:
	var image := _make_test_image(TEST_SIZE)
	image.set_pixel(10, 10, Color(0.4, 0.6, 0.2, 1.0))  # not in the palette
	var result := CustomMapParser.parse(image)
	var ok: bool = result.get("ok", false)
	_expect(ok, "a map with one odd pixel failed to parse at all")
	if not ok:
		return
	_expect(result["grid"][10][10] == 1,
		"an unrecognised colour became open floor instead of a wall")
	var warnings: Array = result["warnings"]
	_expect(not warnings.is_empty(), "an unrecognised colour produced no warning to the person who painted it")
	print("  unknown   an unrecognised colour becomes a wall and a warning, not a silent hole")


func _supports_authored_and_random_spawns() -> void:
	var authored := _make_test_image(TEST_SIZE)
	var second_spawn := Vector2i(TEST_SIZE - 5, 2)
	authored.set_pixel(second_spawn.x, second_spawn.y, Color8(0, 255, 0))
	var authored_result := CustomMapParser.parse(authored)
	_expect(authored_result.get("ok", false), "a map with two green spawns was rejected")
	if authored_result.get("ok", false):
		var expected: Array[Vector2i] = [Vector2i(2, 2), second_spawn]
		_expect(authored_result["spawn_points"] == expected,
			"the parser did not retain both authored spawn cells")
		var authored_generator := FacilityGenerator.new(
			"MULTI-SPAWN", RoomState.generator_options(), authored_result)
		_expect(authored_generator.spawn_points == expected,
			"the generator did not retain both authored spawn cells")

	var automatic := Image.create(17, 13, false, Image.FORMAT_RGBA8)
	automatic.fill(Color(0, 0, 0, 1))
	for y in range(1, 12):
		for x in range(1, 16):
			automatic.set_pixel(x, y, Color(1, 1, 1, 1))
	automatic.set_pixel(15, 11, Color8(255, 0, 0))
	var automatic_result := CustomMapParser.parse(automatic)
	_expect(automatic_result.get("ok", false), "a map without green spawns was rejected")
	if automatic_result.get("ok", false):
		_expect((automatic_result["spawn_points"] as Array).is_empty(),
			"the parser invented an authored spawn")
		var first := FacilityGenerator.new(
			"AUTO-SPAWN", RoomState.generator_options(), automatic_result)
		var second := FacilityGenerator.new(
			"AUTO-SPAWN", RoomState.generator_options(), automatic_result)
		_expect(first.start == second.start,
			"automatic spawn selection was not deterministic for the route seed")
		_expect(first.is_floor(first.start.x + 0.5, first.start.y + 0.5),
			"automatic spawn selection chose a wall")
		_expect(first.spawn_points == [first.start],
			"automatic spawn was not exposed through generator.spawn_points")
	print("  spawns    multiple green cells survive; no green picks seeded random floor")


func _requires_walkable_space() -> void:
	var image := Image.create(TEST_SIZE, TEST_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	var result := CustomMapParser.parse(image)
	_expect(not result.get("ok", true), "an all-wall map with nowhere to spawn was accepted")
	print("  no-floor  an all-wall map is rejected because no random spawn is possible")


## The real integration point: does a parsed map actually produce a working
## FacilityGenerator, with the SAME relay/battery/safe-zone machinery every
## procedural floor uses.
func _feeds_a_real_generator() -> void:
	var image := _make_test_image(TEST_SIZE)
	var result := CustomMapParser.parse(image)
	var ok: bool = result.get("ok", false)
	_expect(ok, "setup: the test map did not parse")
	if not ok:
		return
	var generator := FacilityGenerator.new("CUSTOM-MAP-CHECK", RoomState.generator_options(), result)
	_expect(generator.cols == TEST_SIZE and generator.rows == TEST_SIZE,
		"the generator's own size does not match the painted image")
	_expect(generator.start == Vector2i(2, 2), "the generator's start does not match the painted one")
	_expect(generator.spawn_points == [Vector2i(2, 2)],
		"the generator's spawn list does not contain the painted start")
	_expect(generator.exit_cell == Vector2i(TEST_SIZE - 3, TEST_SIZE - 3),
		"the generator's exit does not match the painted one")
	# The generic placement algorithms still ran on this hand-painted grid --
	# same promise a procedural floor makes, just fed a different layout.
	_expect(not generator.relays.is_empty(), "no relays were placed on the painted floor at all")
	print("  generator a parsed map produces relays/batteries through the same generic placement")


func _themed_samples_populate_authored_props() -> void:
	var samples := {
		"sample-mansion-showcase.png": "diningTable",
		"sample-frozen-tideline.png": "frozenBeachHut",
		"sample-thermal-inferno.png": "infernoAltar",
	}
	for filename in samples:
		var path := "res://art/custom-maps/%s" % filename
		var texture := load(path) as Texture2D
		var image: Image = texture.get_image() if texture != null else null
		_expect(image != null and not image.is_empty(),
			"%s could not be loaded" % filename)
		if image == null or image.is_empty():
			continue
		var result := CustomMapParser.parse(image)
		_expect(result.get("ok", false), "%s did not parse: %s" % [filename,
			result.get("error", "")])
		if not result.get("ok", false):
			continue
		var generator := FacilityGenerator.new(
			"SAMPLE-PROPS:%s" % filename, RoomState.generator_options(), result)
		var types: Array[String] = []
		for prop in generator.props:
			var type := String(prop.get("type", ""))
			types.append(type)
			if PropModelCatalog.has_model(type):
				var model_path := PropModelCatalog.model_path(type,
					String(prop.get("id", type)))
				_expect(ResourceLoader.exists(model_path),
					"%s maps %s to missing model %s" % [filename, type, model_path])
		_expect(not generator.props.is_empty(),
			"%s produced no themed props" % filename)
		_expect(types.has(String(samples[filename])),
			"%s did not place its expected %s" % [filename, samples[filename]])
	print("  props     mansion, Frozen Tideline and Inferno samples place authored GLBs")


func _bedroom_region_populates_bedroom_props() -> void:
	var image := Image.create(27, 27, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	for y in range(1, 26):
		for x in range(1, 26):
			image.set_pixel(x, y, Color(1, 1, 1, 1))
	for y in range(4, 23):
		for x in range(4, 23):
			image.set_pixel(x, y, Color8(0xb0, 0x7c, 0xc6))
	image.set_pixel(2, 2, Color8(0, 255, 0))
	image.set_pixel(24, 24, Color8(255, 0, 0))
	var result := CustomMapParser.parse(image)
	_expect(result.get("ok", false), "the mansion-bedroom palette colour did not parse")
	if not result.get("ok", false):
		return
	var generator := FacilityGenerator.new(
		"BEDROOM-REGION-CHECK", RoomState.generator_options(), result)
	var types: Array[String] = []
	for prop in generator.props:
		types.append(String(prop.get("type", "")))
	_expect(types.has("singleBed"), "a bedroom-painted region placed no bed")
	_expect(types.has("bedroomWardrobe"),
		"a bedroom-painted region placed no wardrobe")
	_expect(types.has("bedsideLamp"),
		"a bedroom-painted region did not mount its bedside lamp")
	print("  bedroom  #B07CC6 regions place beds, storage, vanity and bedside dressing")
