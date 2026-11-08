extends SceneTree

## One-off: bakes the two dedicated block textures used by
## facility_view_3d.gd's GridMap floor/wall boxes, cropped once from the
## shared environment kit sheet. See that file's _build_mesh_library() for
## why this replaced the old runtime UV-guessing heuristic.

func _init() -> void:
	var floor_img := Image.load_from_file("res://assets/environment/floor_tile_0.png")
	var floor_crop := floor_img.get_region(Rect2i(4, 14, 72, 24))
	floor_crop.save_png("res://assets/environment/floor_texture.png")

	var wall_img := Image.load_from_file("res://assets/environment/wall_block_0.png")
	var wall_crop := wall_img.get_region(Rect2i(165, 4, 85, 36))
	wall_crop.save_png("res://assets/environment/wall_texture.png")

	var palettes := {
		"maze": [Color("8f665b"), Color("624a48")],
		"mansion": [Color("9a6654"), Color("71483f")],
		"hotel": [Color("aa865f"), Color("82634c")],
		"apartment": [Color("6f8c9e"), Color("526878")],
		"beach": [Color("a9c8c5"), Color("789e9c")],
		"gothic": [Color("6f5685"), Color("493b5e")],
		"prison": [Color("697c86"), Color("46565f")],
		"inferno": [Color("9c4b3c"), Color("522f32")],
		"carnival": [Color("704667"), Color("6f3445")],
		"hospital": [Color("8fa59c"), Color("7d948c")],
		"lab": [Color("9aa7ad"), Color("8496a0")],
		"greenhouse": [Color("8a5a3c"), Color("4c6a46")],
		"mall": [Color("9a8a76"), Color("7a5e52")],
	}
	for region in palettes:
		var colors: Array = palettes[region]
		_procedural_surface(region, colors[0], false).save_png(
			"res://assets/environment/floor_%s.png" % region)
		_procedural_surface(region, colors[1], true).save_png(
			"res://assets/environment/wall_%s.png" % region)
	quit()


func _procedural_surface(region: String, base: Color, wall: bool) -> Image:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var seed := region.unicode_at(0) + (71 if wall else 17)
	for y in 32:
		for x in 32:
			var noise := float(posmod(x * 17 + y * 31 + seed * 13, 11) - 5) / 150.0
			var color := base.lightened(maxf(0.0, noise)).darkened(maxf(0.0, -noise))
			var seam := false
			var accent := false
			match region:
				"maze":
					seam = x % 8 == 0 or y % 8 == 0
					accent = (x % 8 in [1, 7]) and (y % 8 in [1, 7])
				"mansion":
					seam = (x % (6 if wall else 8)) == 0
					accent = wall and posmod(x + y, 12) == 0
				"hotel":
					seam = wall and x % 6 == 0
					accent = (not wall) and (posmod(x + y, 8) == 0 \
						or posmod(x - y, 8) == 0)
				"apartment":
					seam = x % (8 if wall else 6) == 0 or y % (4 if wall else 6) == 0
					accent = wall and y % 8 == 0 and x % 16 < 8
				"beach":
					seam = (y if wall else x) % 8 == 0
					accent = posmod(x * 3 + y * 5, 23) == 0
				"gothic":
					seam = y % 8 == 0 or (x + (4 if floori(float(y) / 8.0) % 2 == 1 else 0)) % 12 == 0
					accent = posmod(x + y * 2, 19) == 0
				"prison":
					seam = y % 8 == 0 or (x + (8 if floori(float(y) / 8.0) % 2 == 1 else 0)) % 16 == 0
					accent = (x % 16 in [1, 14]) and (y % 8 in [1, 6])
				"inferno":
					seam = posmod(x * 2 + y * 3 + seed, 17) == 0
					accent = posmod(x * 5 - y * 2 + seed, 29) == 0
				"carnival":
					# Muted checker flooring and striped big-top wall panels keep
					# carnival chunks readable without turning them neon-bright.
					seam = (x % 8 == 0 or y % 8 == 0) if not wall \
						else x % 6 == 0
					accent = posmod(floori(float(x) / 4.0) \
						+ floori(float(y) / 4.0), 2) == 0 if not wall \
						else posmod(floori(float(x) / 6.0), 2) == 0
			if seam:
				color = color.darkened(.22)
			elif accent:
				color = color.lightened(.18 if region != "inferno" else .32)
			image.set_pixel(x, y, color)
	return image
