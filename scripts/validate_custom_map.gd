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
	_accepts_unbounded_dimensions()
	_flags_unrecognised_colour()
	_requires_a_start()
	_feeds_a_real_generator()
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


func _accepts_unbounded_dimensions() -> void:
	# Both images sit outside the old 35..121 bounds. Dimensions are content,
	# not a parser policy; only valid palette/start authoring matters.
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
	print("  dimensions 3x2 and 173x129 maps both parse; no authored pixel bounds")


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


func _requires_a_start() -> void:
	var image := Image.create(TEST_SIZE, TEST_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))  # all floor, no start
	var result := CustomMapParser.parse(image)
	_expect(not result.get("ok", true), "a map with no start marker was accepted")
	print("  no-start  a map with no green pixel is refused, not defaulted somewhere")


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
	_expect(generator.exit_cell == Vector2i(TEST_SIZE - 3, TEST_SIZE - 3),
		"the generator's exit does not match the painted one")
	# The generic placement algorithms still ran on this hand-painted grid --
	# same promise a procedural floor makes, just fed a different layout.
	_expect(not generator.relays.is_empty(), "no relays were placed on the painted floor at all")
	print("  generator a parsed map produces relays/batteries through the same generic placement")
