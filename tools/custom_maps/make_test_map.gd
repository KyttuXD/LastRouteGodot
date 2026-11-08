extends SceneTree

## Rebuilds assets/custom_maps/test-map.png without an image-editor dependency.
## Run from the repository root with:
##   godot4 --headless --path . --script tools/custom_maps/make_test_map.gd

const SIZE := 49
const OUTPUT := "res://assets/custom_maps/test-map.png"

const WALL := Color8(0, 0, 0)
const FLOOR := Color8(255, 255, 255)
const START := Color8(0, 255, 0)
const EXIT := Color8(255, 0, 0)
const OFFICE := Color8(0x4a, 0x90, 0xd9)
const MAINTENANCE := Color8(0xc9, 0x7a, 0x3d)
const MANSION := Color8(0x8e, 0x5f, 0xd9)
const GARDEN := Color8(0x6f, 0xbf, 0x73)


func _initialize() -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(WALL)

	# Four large themed quadrants with an ordinary-floor cross between them.
	_fill_rect(image, Rect2i(2, 2, 21, 21), OFFICE)
	_fill_rect(image, Rect2i(26, 2, 21, 21), MANSION)
	_fill_rect(image, Rect2i(2, 26, 21, 21), GARDEN)
	_fill_rect(image, Rect2i(26, 26, 21, 21), MAINTENANCE)
	_fill_rect(image, Rect2i(22, 2, 5, 45), FLOOR)
	_fill_rect(image, Rect2i(2, 22, 45, 5), FLOOR)

	# Chunky pillars make each room less box-like while leaving wide routes.
	for center in [Vector2i(9, 9), Vector2i(16, 16), Vector2i(33, 9),
			Vector2i(40, 16), Vector2i(9, 33), Vector2i(16, 40),
			Vector2i(33, 33), Vector2i(40, 40)]:
		_fill_rect(image, Rect2i(center - Vector2i.ONE, Vector2i(3, 3)), WALL)

	# Required authored markers. They remain open cells when parsed.
	image.set_pixel(24, 24, START)
	image.set_pixel(44, 44, EXIT)

	var error := image.save_png(OUTPUT)
	if error != OK:
		push_error("could not write %s (error %d)" % [OUTPUT, error])
	quit(error)


func _fill_rect(image: Image, rect: Rect2i, colour: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			image.set_pixel(x, y, colour)
