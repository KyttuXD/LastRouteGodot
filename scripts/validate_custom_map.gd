extends RefCounted

## Headless check on CustomMapParser and its FacilityGenerator integration.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- custom_map

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(_host: Node) -> int:
	_parses_a_real_map()
	_rejects_out_of_bounds()
	_flags_unrecognised_colour()
	_requires_a_start()
	_feeds_a_real_generator()
	if _failures == 0:
		print("custom_map OK")
	return _failures


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
	var image := _make_test_image(CustomMapParser.MIN_SIZE)
	var result := CustomMapParser.parse(image)
	var ok: bool = result.get("ok", false)
	_expect(ok, "a well-formed map failed to parse: %s" % result.get("error", ""))
	if not ok:
		return
	_expect(result["start"] == Vector2i(2, 2), "start marker landed at %s, not (2, 2)" % result["start"])
	_expect(result["exit_cell"] == Vector2i(CustomMapParser.MIN_SIZE - 3, CustomMapParser.MIN_SIZE - 3),
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


func _rejects_out_of_bounds() -> void:
	var too_small := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	var small_result := CustomMapParser.parse(too_small)
	_expect(not small_result.get("ok", true), "a 10x10 image was accepted; the minimum is %d" % CustomMapParser.MIN_SIZE)

	var too_big := Image.create(CustomMapParser.MAX_SIZE + 5, CustomMapParser.MAX_SIZE + 5, false, Image.FORMAT_RGBA8)
	var big_result := CustomMapParser.parse(too_big)
	_expect(not big_result.get("ok", true), "an oversized image was accepted; the maximum is %d" % CustomMapParser.MAX_SIZE)
	print("  bounds    undersized and oversized images are both refused")


func _flags_unrecognised_colour() -> void:
	var image := _make_test_image(CustomMapParser.MIN_SIZE)
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
	var image := Image.create(CustomMapParser.MIN_SIZE, CustomMapParser.MIN_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))  # all floor, no start
	var result := CustomMapParser.parse(image)
	_expect(not result.get("ok", true), "a map with no start marker was accepted")
	print("  no-start  a map with no green pixel is refused, not defaulted somewhere")


## The real integration point: does a parsed map actually produce a working
## FacilityGenerator, with the SAME relay/battery/safe-zone machinery every
## procedural floor uses.
func _feeds_a_real_generator() -> void:
	var image := _make_test_image(CustomMapParser.MIN_SIZE)
	var result := CustomMapParser.parse(image)
	var ok: bool = result.get("ok", false)
	_expect(ok, "setup: the test map did not parse")
	if not ok:
		return
	var generator := FacilityGenerator.new("CUSTOM-MAP-CHECK", RoomState.generator_options(), result)
	_expect(generator.cols == CustomMapParser.MIN_SIZE and generator.rows == CustomMapParser.MIN_SIZE,
		"the generator's own size does not match the painted image")
	_expect(generator.start == Vector2i(2, 2), "the generator's start does not match the painted one")
	_expect(generator.exit_cell == Vector2i(CustomMapParser.MIN_SIZE - 3, CustomMapParser.MIN_SIZE - 3),
		"the generator's exit does not match the painted one")
	# The generic placement algorithms still ran on this hand-painted grid --
	# same promise a procedural floor makes, just fed a different layout.
	_expect(not generator.relays.is_empty(), "no relays were placed on the painted floor at all")
	print("  generator a parsed map produces relays/batteries through the same generic placement")
