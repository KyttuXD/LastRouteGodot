extends SceneTree

## Renders assets/branding/logo.svg to the PNG icon set with Godot's own SVG rasteriser
## (no external tools):
##   godot --headless --path . -s tools/branding/build_logo.gd
## Writes assets/branding/logo_<size>.png (1024..16), the Android launcher/adaptive layers
## and a copy of the SVG as the project's root icon.svg. The colours live in the SVG;
## keep them in step with src/config/palette.gd (ACCENT*, TEAL*, BACKDROP*).

const SIZES := [1024, 512, 256, 192, 180, 144, 128, 64, 32, 16]
const OUT := "res://assets/branding/"


func _init() -> void:
	var svg := FileAccess.get_file_as_string(OUT + "logo.svg")
	if svg.is_empty():
		push_error("logo.svg missing")
		quit(1)
		return
	for size in SIZES:
		var image := Image.new()
		var error := image.load_svg_from_string(svg, float(size) / 64.0)
		if error != OK:
			push_error("svg render failed at %d" % size)
			quit(1)
			return
		if image.get_width() != size:
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		image.save_png(OUT + "logo_%d.png" % size)
		print("logo_%d.png" % size)
	# Android adaptive icon: 432 px layers, the mark sits in the central 66% safe zone.
	var plain := svg.replace('<rect x="2" y="2" width="60" height="60" rx="14" fill="url(#ground)"/>', "") \
		.replace(' clip-path="url(#tile)"', "").replace('<rect x="4" y="4" width="56" height="56" rx="12" fill="none" stroke="#8a6396" stroke-width="3"/>', "")
	var fg := Image.new()
	fg.load_svg_from_string(plain, 432.0 * 0.66 / 64.0)
	var layer := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	layer.blit_rect(fg, Rect2i(Vector2i.ZERO, fg.get_size()), (Vector2i(432, 432) - fg.get_size()) / 2)
	layer.save_png(OUT + "logo_adaptive_foreground_432.png")
	var back := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	back.fill(Color("1a1019"))
	back.save_png(OUT + "logo_adaptive_background_432.png")
	var mono: Image = layer.duplicate()
	for y in mono.get_height():
		for x in mono.get_width():
			var c: Color = mono.get_pixel(x, y)
			mono.set_pixel(x, y, Color(1, 1, 1, c.a))
	mono.save_png(OUT + "logo_adaptive_monochrome_432.png")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(OUT + "logo.svg"),
		ProjectSettings.globalize_path("res://icon.svg"))
	print("LOGO OK")
	quit(0)
