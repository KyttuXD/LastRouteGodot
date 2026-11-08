class_name RefTextures
extends RefCounted

## Procedural pixel-art surfaces for the reference look. Nothing is imported:
## every texel is painted from a seeded RandomNumberGenerator the first time a
## kind is requested, so the look is identical on every machine. 32 texels per
## metre, sampled nearest-neighbour (see material()).
##
## Floors are 32x32 (one grid cell). Walls are 32x128 and cover the whole face
## of a wall block (wainscot, rail, wallpaper, cornice), so one texture is one
## storey of wall rather than a tile that repeats vertically.

const PX := 32
const WALL_H := 128

static var _images := {}
static var _textures := {}
static var _materials := {}
## Content packs' replacement images (docs/modding/content-types.md, "Surfaces"), "floor:<kind>" / "wall:<kind>" -> a
## loaded pack's PNG path. Empty without packs, so every kind is painted as before.
static var _pack_images: Dictionary = _collect_pack_images()
static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


## Packs changed (ContentRegistry.load_packs / unload_packs): drop every cached image, texture, material and array so
## they are rebuilt from the current packs. Packs change between rooms, so no world mixes old and new layers.
static func rebuild_from_registry() -> void:
	_pack_images = _collect_pack_images()
	for cache in [_images, _textures, _materials, _array_textures, _array_layers, _array_materials]:
		cache.clear()


static func _collect_pack_images() -> Dictionary:
	var out := {}
	for def in ContentRegistry.pack_defs("floors"):
		out["floor:" + String(def["id"])] = String(def["image"])
	for def in ContentRegistry.pack_defs("walls"):
		out["wall:" + String(def["id"])] = String(def["image"])
	# ceilings share the floor array (32x32); their glow (the sewer vault only; glass lost its fake glow) stays in params(), keyed by kind
	for def in ContentRegistry.pack_defs("ceilings"):
		out["ceiling:" + String(def["id"])] = String(def["image"])
	return out


## One kind's image: a loaded pack's replacement (RGBA8, nearest-scaled to this group's size, so the shared arrays stay
## uniform), else the painter's.
static func _paint(group: String, kind: String, entry: Array) -> Image:
	var path := String(_pack_images.get("%s:%s" % [group, kind], ""))
	if not path.is_empty():
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(PX, WALL_H if group == "wall" else PX, Image.INTERPOLATE_NEAREST)
			return img
	return Callable(RefTextures, entry[0]).call(entry[1])

# -- tiny painter --------------------------------------------------------------

static func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng


static func _mul(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


static func _dot(img: Image, x: int, y: int, c: Color, w: int = 1, h: int = 1) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	for yy in h:
		for xx in w:
			var px := x + xx
			var py := y + yy
			if px >= 0 and py >= 0 and px < iw and py < ih:
				img.set_pixel(px, py, c)


## Three-step brightness noise, the same dithered grain the references show.
static func _noise(img: Image, x0: int, y0: int, w: int, h: int, base: Color,
		amp: float, rng: RandomNumberGenerator, cell: int = 1) -> void:
	for y in range(0, h, cell):
		for x in range(0, w, cell):
			var step := rng.randi_range(-1, 1)
			_dot(img, x0 + x, y0 + y, _mul(base, 1.0 + step * amp), cell, cell)


static func _rivet(img: Image, x: int, y: int, base: Color) -> void:
	_dot(img, x, y, _mul(base, .35), 2, 2)
	_dot(img, x, y, _mul(base, 1.7))


static func _crack(img: Image, rng: RandomNumberGenerator, x: int, y: int, length: int, c: Color) -> void:
	var cx := x
	var cy := y
	for i in length:
		_dot(img, cx, cy, c)
		var r := rng.randf()
		if r < .4:
			cx += 1
		elif r < .7:
			cy += 1
		elif r < .85:
			cx -= 1
		else:
			cy -= 1


static func _new_image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	return img


# -- floors --------------------------------------------------------------------

static func _paint_metal(variant: int) -> Image:
	var rng := _rng("metal%d" % variant)
	var img := _new_image(PX, PX)
	var base := _mul(RefLook.METAL, .86)
	_noise(img, 0, 0, PX, PX, base, .14, rng)
	for i in 3:
		_dot(img, rng.randi_range(1, 28), rng.randi_range(1, 28), _mul(base, .78), rng.randi_range(2, 4), 1)
	# lit top/left edges, dark seams bottom/right: a bevelled riveted plate
	_dot(img, 0, 0, _mul(base, 2.0), PX, 1)
	_dot(img, 0, 1, _mul(base, 1.4), PX, 1)
	_dot(img, 0, 0, _mul(base, 1.6), 1, PX)
	_dot(img, PX - 1, 0, Color("080607"), 1, PX)
	_dot(img, 0, PX - 1, Color("080607"), PX, 1)
	for r in [[3, 3], [26, 3], [3, 26], [26, 26]]:
		_rivet(img, r[0], r[1], base)
	if rng.randf() < .35:
		_crack(img, rng, rng.randi_range(5, 25), rng.randi_range(5, 25), rng.randi_range(4, 9), Color("1c1819"))
	if rng.randf() < .5:
		for i in 4:
			_dot(img, rng.randi_range(2, 29), rng.randi_range(2, 29), Color("4a2c14"))
	if rng.randf() < .4:
		_dot(img, rng.randi_range(4, 26), 5, Color("3b3836"), 1, rng.randi_range(8, 18))
	if variant == 3:
		# service plate with a drain grille
		for gy in range(11, 22, 2):
			_dot(img, 9, gy, Color("0b090a"), 14, 1)
	return img


static func _mosaic(img: Image, base: Color, rng: RandomNumberGenerator) -> void:
	_noise(img, 0, 0, PX, PX, base, .22, rng, 2)
	for i in 20:
		_dot(img, rng.randi_range(0, 30), rng.randi_range(0, 30), _mul(base, .55), 2, 1)


static func _flower(img: Image, cx: int, cy: int, petal: Color, core: Color) -> void:
	for a in 5:
		var ang := float(a) / 5.0 * TAU - PI * .5
		var px := roundi(cx + cos(ang) * 3.0)
		var py := roundi(cy + sin(ang) * 3.0)
		_dot(img, px - 1, py - 1, petal, 3, 3)
		_dot(img, px, py, _mul(petal, 1.25))
	_dot(img, cx - 1, cy - 1, core, 3, 3)


static func _paint_floral(variant: int) -> Image:
	var rng := _rng("floral%d" % variant)
	var img := _new_image(PX, PX)
	var alt := variant == 1
	_mosaic(img, Color("2a1526") if alt else Color("2e1729"), rng)
	var petal := Color("6e5c52")
	var core := Color("94601f")
	_flower(img, 22 if alt else 9, 9, petal, core)
	_flower(img, 9 if alt else 24, 24, _mul(petal, .85), core)
	for i in 6:
		_dot(img, rng.randi_range(1, 30), rng.randi_range(1, 30), Color("3d2138"), 2, 1)
	return img


static func _star(img: Image, cx: int, cy: int, outer: int, c: Color) -> void:
	var inner := outer * .45
	for y in range(-outer, outer + 1):
		for x in range(-outer, outer + 1):
			var r := Vector2(x, y).length()
			var ang := atan2(y, x) + PI * .5
			var seg := fposmod(ang, TAU / 5.0)
			var t := absf(seg / (PI / 5.0) - 1.0)
			if r <= outer + (inner - outer) * t + .4:
				_dot(img, cx + x, cy + y, c)


static func _paint_star(variant: int) -> Image:
	var rng := _rng("star%d" % variant)
	var img := _new_image(PX, PX)
	var alt := variant == 1
	_mosaic(img, Color("2b1220") if alt else Color("2f1424"), rng)
	_star(img, 22 if alt else 9, 10, 5, Color("7a561e"))
	_star(img, 8 if alt else 23, 25, 3, Color("55391a"))
	for a in 40:
		_dot(img, roundi((10 if alt else 24) + cos(a / 40.0 * TAU) * 5.0),
			roundi((24 if alt else 8) + sin(a / 40.0 * TAU) * 5.0), Color("5a1d26"))
	return img


static func _paint_parquet(variant: int) -> Image:
	var rng := _rng("parquet%d" % variant)
	var img := _new_image(PX, PX)
	var base := RefLook.WOOD
	# herringbone-ish: 8px planks, alternating direction per half
	for band in 4:
		var y0 := band * 8
		var shade := rng.randf_range(.8, 1.25)
		_noise(img, 0, y0, PX, 8, _mul(base, shade), .1, rng)
		_dot(img, 0, y0 + 7, Color("0c0705"), PX, 1)
		var joint := (rng.randi() % 20) + 4 + (band % 2) * 6
		_dot(img, joint % PX, y0, Color("0c0705"), 1, 8)
		for g in 3:
			_dot(img, rng.randi_range(0, 30), y0 + rng.randi_range(1, 6), _mul(base, .7), rng.randi_range(3, 7), 1)
	_dot(img, 0, 0, _mul(base, 1.5), PX, 1)
	return img


static func _paint_stone(variant: int) -> Image:
	var rng := _rng("stone%d" % variant)
	var img := _new_image(PX, PX)
	var base := RefLook.STONE
	_noise(img, 0, 0, PX, PX, base, .12, rng, 2)
	# flagstone mortar lines
	var split := rng.randi_range(10, 20)
	_dot(img, 0, split, Color("0d0b0b"), PX, 1)
	_dot(img, rng.randi_range(6, 26), 0, Color("0d0b0b"), 1, split)
	_dot(img, rng.randi_range(6, 26), split + 1, Color("0d0b0b"), 1, PX - split)
	_dot(img, 0, 0, Color("0d0b0b"), PX, 1)
	_dot(img, 0, 0, Color("0d0b0b"), 1, PX)
	# wet sheen: cold teal-grey speckle + dark damp patches
	for i in 26:
		_dot(img, rng.randi_range(0, 31), rng.randi_range(0, 31), Color("3e4a4c") if i % 3 == 0 else Color("141012"))
	_crack(img, rng, rng.randi_range(4, 26), rng.randi_range(4, 26), rng.randi_range(5, 10), Color("0f0c0c"))
	# (variant 2 used to paint a few magenta "fallen petal" dots here; they read as glitter on the floor, so they are gone)
	return img


static func _paint_check(variant: int) -> Image:
	var rng := _rng("check%d" % variant)
	var img := _new_image(PX, PX)
	var a := Color("1d1618")
	var b := Color("3a2a2c") if variant == 0 else Color("4a2024")
	for cy in 2:
		for cx in 2:
			_noise(img, cx * 16, cy * 16, 16, 16, a if (cx + cy) % 2 == 0 else b, .1, rng)
	_dot(img, 0, 0, Color("0a0708"), PX, 1)
	_dot(img, 0, 0, Color("0a0708"), 1, PX)
	_dot(img, 15, 0, Color("0a0708"), 1, PX)
	_dot(img, 0, 15, Color("0a0708"), PX, 1)
	return img


## Patterned carpet (FLOOR_SETS): 0 gothic red with a gold diamond lattice, 1 hotel teal with gold medallions,
## 2 library green with a fine border, 3 plum lounge.
static func _paint_carpet(variant: int) -> Image:
	var rng := _rng("carpet%d" % variant)
	var img := _new_image(PX, PX)
	var bases := [Color("3a1014"), Color("0f2a2c"), Color("132a17"), Color("2a1430")]
	var accents := [Color("6e4a1c"), Color("6a5420"), Color("2e4a24"), Color("5a3a52")]
	var base: Color = bases[variant]
	var accent: Color = accents[variant]
	_noise(img, 0, 0, PX, PX, base, .1, rng, 2)
	match variant:
		0:
			for i in PX:
				_dot(img, i, (i + 16) % PX, accent)
				_dot(img, i, (PX - i + 15) % PX, accent)
			_dot(img, 15, 15, _mul(accent, 1.3), 2, 2)
		1:
			for a in 32:
				_dot(img, roundi(16 + cos(a / 32.0 * TAU) * 7.0), roundi(16 + sin(a / 32.0 * TAU) * 7.0), accent)
			_dot(img, 15, 15, _mul(accent, 1.2), 2, 2)
			_dot(img, 0, 0, _mul(accent, .8), 2, 2)
		2:
			_dot(img, 1, 1, accent, PX - 2, 1)
			_dot(img, 1, PX - 2, accent, PX - 2, 1)
			_dot(img, 1, 1, accent, 1, PX - 2)
			_dot(img, PX - 2, 1, accent, 1, PX - 2)
		3:
			for y in range(4, PX, 8):
				for x in range(4, PX, 8):
					_dot(img, x, y, accent, 2, 2)
	return img


## Office carpet tiles: 16 px squares with alternating pile direction (two greys), thin seams.
static func _paint_carpet_tile(variant: int) -> Image:
	var rng := _rng("carpet_tile%d" % variant)
	var img := _new_image(PX, PX)
	var a := Color("2a2b30") if variant == 0 else Color("23262e")
	var b := _mul(a, 1.12)
	for cy in 2:
		for cx in 2:
			_noise(img, cx * 16, cy * 16, 16, 16, a if (cx + cy) % 2 == 0 else b, .08, rng)
	_dot(img, 0, 0, _mul(a, .6), PX, 1)
	_dot(img, 0, 0, _mul(a, .6), 1, PX)
	_dot(img, 16, 0, _mul(a, .7), 1, PX)
	_dot(img, 0, 16, _mul(a, .7), PX, 1)
	return img


## Lab / clinic vinyl: pale sheet with fine flecks and a welded seam.
static func _paint_vinyl(variant: int) -> Image:
	var rng := _rng("vinyl%d" % variant)
	var img := _new_image(PX, PX)
	var base := Color("3c4240") if variant == 0 else Color("3a3c44")
	_noise(img, 0, 0, PX, PX, base, .05, rng, 2)
	for i in 18:
		_dot(img, rng.randi_range(0, 31), rng.randi_range(0, 31), _mul(base, .75 if i % 2 == 0 else 1.15))
	_dot(img, 0, 0, _mul(base, .7), PX, 1)
	return img


## Bare concrete (prison, service corridors): mottled grey, a saw-cut joint, a few stains.
static func _paint_concrete(variant: int) -> Image:
	var rng := _rng("concrete%d" % variant)
	var img := _new_image(PX, PX)
	var base := Color("2c2a2a") if variant == 0 else Color("272828")
	_noise(img, 0, 0, PX, PX, base, .08, rng, 2)
	_noise(img, 0, 0, PX, PX, base, .05, rng, 4)
	_dot(img, 0, 0, _mul(base, .55), PX, 1)
	if variant == 1:
		_dot(img, 0, 16, _mul(base, .6), PX, 1)
	for i in 3:
		_dot(img, rng.randi_range(2, 26), rng.randi_range(2, 26), _mul(base, .8), rng.randi_range(2, 4), rng.randi_range(1, 3))
	_crack(img, rng, rng.randi_range(4, 26), rng.randi_range(4, 26), rng.randi_range(4, 8), _mul(base, .5))
	return img


static func _paint_hazard(variant: int) -> Image:
	var rng := _rng("hazard%d" % variant)
	var img := _paint_metal(0)
	for y in 7:
		for x in PX:
			var yellow := ((x + y) >> 2) & 1
			_dot(img, x, y, Color("7a5c12") if yellow == 1 else Color("14110e"))
	_dot(img, 0, 7, Color("070606"), PX, 1)
	if rng.randf() < .5:
		_crack(img, rng, 4, 3, 6, Color("0a0808"))
	return img



## Mall terrazzo: polished cream chips in a warm binder, a brass divider strip every metre.
static func _paint_terrazzo(variant: int) -> Image:
	var rng := _rng("terrazzo%d" % variant)
	var img := _new_image(PX, PX)
	var base := Color("5a5048") if variant == 0 else Color("4c4a50")
	_noise(img, 0, 0, PX, PX, base, .04, rng, 2)
	for i in 40:
		var chip: Color = [Color("8a8278"), Color("2e2a28"), Color("7a5a44"), Color("6a7470")][i % 4]
		_dot(img, rng.randi_range(0, PX - 2), rng.randi_range(0, PX - 2), chip, 1 + i % 2, 1)
	_dot(img, 0, 0, Color("7a5c2c"), PX, 1)
	_dot(img, 0, 0, Color("7a5c2c"), 1, PX)
	return img


## Lab epoxy floor: light grey poured resin on a metre grid, cyan line markers at the joints.
static func _paint_epoxy(variant: int) -> Image:
	var rng := _rng("epoxy%d" % variant)
	var img := _new_image(PX, PX)
	var base := Color("4b5155")
	_noise(img, 0, 0, PX, PX, base, .04, rng, 2)
	_dot(img, 0, 0, _mul(base, .62), PX, 1)
	_dot(img, 0, 0, _mul(base, .62), 1, PX)
	_dot(img, 0, 0, Color("2a8f9c"), 3, 1)
	_dot(img, 0, 0, Color("2a8f9c"), 1, 3)
	if variant == 1:
		# yellow keep-clear hatch along one edge
		for x in PX:
			if ((x >> 2) & 1) == 0:
				_dot(img, x, PX - 4, Color("7a5c12"), 1, 3)
	return img


## Greenhouse floor: worn terracotta quarry tiles in dark grout, the odd moss tuft.
static func _paint_terracotta(variant: int) -> Image:
	var rng := _rng("terra%d" % variant)
	var img := _new_image(PX, PX)
	var grout := Color("1c1612")
	_dot(img, 0, 0, grout, PX, PX)
	for ty in 2:
		for tx in 2:
			var tone := Color("6a3a26") if (tx + ty + variant) % 2 == 0 else Color("5c3424")
			_noise(img, tx * 16 + 1, ty * 16 + 1, 14, 14, tone, .1, rng)
	for i in 3:
		_dot(img, rng.randi_range(0, PX - 2), rng.randi_range(0, PX - 2), Color("2f4a22"), 2, 1)
	return img

## Maroon carpet with a brass-edged runner stripe down the middle (used under
## long corridors so a run of cells reads as one runner like the references).
static func _paint_runner(variant: int) -> Image:
	var rng := _rng("runner%d" % variant)
	var img := _new_image(PX, PX)
	var base := Color("3a1522")
	_mosaic(img, base, rng)
	# brass guide lines top and bottom edge
	_dot(img, 0, 3, Color("6e4e1c"), PX, 1)
	_dot(img, 0, 5, Color("3e2a14"), PX, 1)
	_dot(img, 0, PX - 4, Color("6e4e1c"), PX, 1)
	_dot(img, 0, PX - 6, Color("3e2a14"), PX, 1)
	# diamond motif
	var cx := 16
	var cy := 16
	for d in range(0, 7):
		_dot(img, cx - d, cy - (6 - d), Color("9a7a50"))
		_dot(img, cx + d, cy - (6 - d), Color("9a7a50"))
		_dot(img, cx - d, cy + (6 - d), Color("9a7a50"))
		_dot(img, cx + d, cy + (6 - d), Color("9a7a50"))
	_dot(img, cx - 1, cy - 1, Color("b97a2a"), 3, 3)
	return img


## One strip of a three-cell-wide runner: brass borders only on the outer edge.
static func _paint_runner_part(part: int, rotated: bool) -> Image:
	var rng := _rng("runnerp%d" % part)
	var img := _new_image(PX, PX)
	_mosaic(img, Color("3a1522"), rng)
	if part == 0:
		_dot(img, 0, 3, Color("6e4e1c"), PX, 1)
		_dot(img, 0, 5, Color("3e2a14"), PX, 1)
	elif part == 2:
		_dot(img, 0, PX - 4, Color("6e4e1c"), PX, 1)
		_dot(img, 0, PX - 6, Color("3e2a14"), PX, 1)
	if part == 1:
		for d in range(0, 7):
			_dot(img, 16 - d, 16 - (6 - d), Color("9a7a50"))
			_dot(img, 16 + d, 16 - (6 - d), Color("9a7a50"))
			_dot(img, 16 - d, 16 + (6 - d), Color("9a7a50"))
			_dot(img, 16 + d, 16 + (6 - d), Color("9a7a50"))
		_dot(img, 15, 15, Color("b97a2a"), 3, 3)
	if rotated:
		img.rotate_90(COUNTERCLOCKWISE)
	return img


static func _paint_runner_l(_v: int) -> Image: return _paint_runner_part(0, false)
static func _paint_runner_c(_v: int) -> Image: return _paint_runner_part(1, false)
static func _paint_runner_r(_v: int) -> Image: return _paint_runner_part(2, false)
static func _paint_runnerz_l(_v: int) -> Image: return _paint_runner_part(0, true)
static func _paint_runnerz_c(_v: int) -> Image: return _paint_runner_part(1, true)
static func _paint_runnerz_r(_v: int) -> Image: return _paint_runner_part(2, true)


static func _paint_runner_z(_variant: int) -> Image:
	var img := _paint_runner(0)
	img.rotate_90(COUNTERCLOCKWISE)
	return img


static func _paint_safe(_variant: int) -> Image:
	# ring of the safe-room pad: plain plate, one thin teal inlay line near the edge
	var img := _paint_metal(0)
	for i in PX:
		_dot(img, i, 1, Color("1c8a8c"))
		_dot(img, i, PX - 3, Color("1c8a8c"))
		_dot(img, 1, i, Color("1c8a8c"))
		_dot(img, PX - 3, i, Color("1c8a8c"))
	return img


static func _paint_safe_plain(_variant: int) -> Image:
	# interior of the pad: undecorated dark plate, so the pad reads as one slab, not a grid of marked tiles
	return _paint_metal(0)


static func _paint_safe_mark(_variant: int) -> Image:
	# the single centre tile carries the mark (a large cross)
	var img := _paint_metal(0)
	var c := PX / 2
	_dot(img, c - 3, 4, Color("1c8a8c"), 6, PX - 8)
	_dot(img, 4, c - 3, Color("1c8a8c"), PX - 8, 6)
	_dot(img, c - 1, 6, Color("5cf0e0"), 2, PX - 12)
	_dot(img, 6, c - 1, Color("5cf0e0"), PX - 12, 2)
	return img


static func _paint_grate(variant: int) -> Image:
	var rng := _rng("grate%d" % variant)
	var img := _paint_metal(1)
	for gy in range(8, 26, 3):
		_dot(img, 6, gy, Color("0a0809"), 20, 2)
		_dot(img, 6, gy + 2, Color("4a4244"), 20, 1)
	return img


# -- walls ---------------------------------------------------------------------

## Shared bands. y is measured from the TOP of the 128px texture.
const SKIRT_H := 8       # baseboard at the bottom
const RAIL_Y := 70       # chair rail / top of wainscot
const CORNICE_H := 10    # top cornice

static func _wall_base(img: Image, rng: RandomNumberGenerator, lower: Color,
		upper: Color) -> void:
	var rail := RAIL_Y
	_noise(img, 0, 0, PX, rail, upper, .1, rng)
	_noise(img, 0, rail, PX, WALL_H - rail, lower, .1, rng)


static func _cornice(img: Image, c: Color) -> void:
	_dot(img, 0, 0, _mul(c, .45), PX, CORNICE_H)
	_dot(img, 0, CORNICE_H - 3, _mul(c, 1.4), PX, 1)
	_dot(img, 0, CORNICE_H, Color("060405"), PX, 1)


static func _skirt(img: Image, c: Color) -> void:
	_dot(img, 0, WALL_H - SKIRT_H, _mul(c, .5), PX, SKIRT_H)
	_dot(img, 0, WALL_H - SKIRT_H, _mul(c, 1.5), PX, 1)
	_dot(img, 0, WALL_H - SKIRT_H - 1, Color("060405"), PX, 1)


static func _rail(img: Image) -> void:
	_dot(img, 0, RAIL_Y - 2, Color("070405"), PX, 1)
	_dot(img, 0, RAIL_Y - 1, Color("8a6a2c"), PX, 1)
	_dot(img, 0, RAIL_Y, Color("5a4220"), PX, 1)
	_dot(img, 0, RAIL_Y + 1, Color("070405"), PX, 1)


static func _grime(img: Image, rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var x := rng.randi_range(0, PX - 1)
		var y := rng.randi_range(CORNICE_H, WALL_H - SKIRT_H - 2)
		var len := rng.randi_range(4, 22)
		var c := Color("0a0707") if rng.randf() < .6 else Color("2a1810")
		_dot(img, x, y, c, 1, len)


static func _paint_wall_panel(variant: int) -> Image:
	# industrial plating: riveted plates, a maroon lower half, vertical pipe
	var rng := _rng("wpanel%d" % variant)
	var img := _new_image(PX, WALL_H)
	_wall_base(img, rng, Color("32202a"), RefLook.METAL)
	# plate seams every 32px vertically, one vertical seam
	for y in range(0, WALL_H, 32):
		_dot(img, 0, y, Color("0a0809"), PX, 1)
		_dot(img, 0, y + 1, _mul(RefLook.METAL, 1.7), PX, 1)
	_dot(img, 0, 0, Color("0a0809"), 1, WALL_H)
	_dot(img, PX - 1, 0, Color("0a0809"), 1, WALL_H)
	for y in range(4, WALL_H, 32):
		for x in [3, PX - 5]:
			_rivet(img, x, y, RefLook.METAL)
	_rail(img)
	_skirt(img, Color("2a1418"))
	_cornice(img, RefLook.METAL)
	if variant == 1:
		# vertical brass pipe + bracket clamps
		var px := 4 + rng.randi_range(0, 18)
		_dot(img, px, 0, Color("3a2a14"), 3, WALL_H)
		_dot(img, px, 0, Color("8a6a2c"), 1, WALL_H)
		for y in range(12, WALL_H, 36):
			_dot(img, px - 1, y, Color("1a1209"), 5, 3)
	if variant == 2:
		# service panel with a vent grille
		for gy in range(40, 62, 3):
			_dot(img, 8, gy, Color("070506"), 16, 1)
		_dot(img, 7, 38, Color("5a4a40"), 18, 1)
		_dot(img, 7, 62, Color("5a4a40"), 18, 1)
	_grime(img, rng, 5)
	return img


static func _paint_wall_wallpaper(variant: int) -> Image:
	# damask paper over a dark panelled wainscot with brass trim
	var rng := _rng("wpaper%d" % variant)
	var img := _new_image(PX, WALL_H)
	var paper := Color("2c1a26") if variant == 0 else Color("2e1a22")
	_noise(img, 0, 0, PX, RAIL_Y, paper, .1, rng)
	# damask motif: stacked flowers + diamond lattice, repeated twice vertically
	for row in range(0, RAIL_Y - 12, 28):
		for col in 2:
			var cx: int = 8 + col * 16
			var cy: int = CORNICE_H + 8 + row + (col * 14) % 28
			if cy < RAIL_Y - 8:
				_flower(img, cx, cy, Color("4a2634"), Color("7a5a2c"))
		for dx in PX:
			var cy2 := CORNICE_H + 22 + row
			if cy2 < RAIL_Y - 4 and (dx % 8) < 2:
				_dot(img, dx, cy2 + (dx % 8), Color("4a2230"))
	# dark wood wainscot with two recessed panels
	var wood := Color("2a1a14") if variant == 0 else Color("241612")
	_noise(img, 0, RAIL_Y, PX, WALL_H - RAIL_Y, wood, .12, rng)
	for pr in [[RAIL_Y + 6, 22], [RAIL_Y + 6 + 26, 22]]:
		_dot(img, 3, pr[0], _mul(wood, .45), PX - 6, pr[1])
		_dot(img, 3, pr[0], _mul(wood, 1.6), PX - 6, 1)
		_dot(img, 3, pr[0], _mul(wood, 1.3), 1, pr[1])
		_dot(img, PX - 4, pr[0], Color("060303"), 1, pr[1])
	_rail(img)
	_skirt(img, wood)
	_cornice(img, Color("3a2820"))
	_grime(img, rng, 3)
	return img


static func _paint_wall_brick(variant: int) -> Image:
	var rng := _rng("wbrick%d" % variant)
	var img := _new_image(PX, WALL_H)
	var base := Color("2e1c1a") if variant == 0 else Color("261a1c")
	var mortar := Color("0e0a0a")
	_noise(img, 0, 0, PX, WALL_H, base, .13, rng)
	var row := 0
	for y in range(0, WALL_H, 6):
		_dot(img, 0, y, mortar, PX, 1)
		var off := 0 if row % 2 == 0 else 8
		for x in range(off, PX + 8, 16):
			_dot(img, x % PX, y, mortar, 1, 6)
			# per brick tone shift
			_dot(img, (x + 2) % PX, y + 2, _mul(base, rng.randf_range(.7, 1.3)), 6, 3)
		row += 1
	# wet streaks and moss near the bottom
	for i in 5:
		_dot(img, rng.randi_range(0, 31), rng.randi_range(0, WALL_H - 24), Color("141018"), 1, rng.randi_range(8, 28))
	for i in 10:
		_dot(img, rng.randi_range(0, 31), WALL_H - rng.randi_range(2, 22), Color("1c2a1c"), 2, 1)
	_dot(img, 0, WALL_H - 4, Color("0a0707"), PX, 4)
	_cornice(img, Color("2a2022"))
	return img


static func _paint_wall_stone(variant: int) -> Image:
	var rng := _rng("wstone%d" % variant)
	var img := _new_image(PX, WALL_H)
	var base := Color("2c2a2c")
	var mortar := Color("0b0a0c")
	_noise(img, 0, 0, PX, WALL_H, base, .12, rng, 2)
	var y := 0
	while y < WALL_H:
		var h: int = [10, 14, 18][rng.randi() % 3]
		_dot(img, 0, y, mortar, PX, 1)
		_dot(img, rng.randi_range(4, 27), y, mortar, 1, h)
		_dot(img, 0, y + 1, _mul(base, 1.4), PX, 1)
		y += h
	# water stains
	for i in 4:
		_dot(img, rng.randi_range(0, 31), rng.randi_range(0, 60), Color("17141a"), 2, rng.randi_range(10, 40))
	for i in 12:
		_dot(img, rng.randi_range(0, 31), rng.randi_range(0, WALL_H - 1), Color("3a4648"))
	_dot(img, 0, WALL_H - 5, Color("0b090a"), PX, 5)
	_cornice(img, Color("2a2628"))
	return img


static func _leaf_cluster(img: Image, rng: RandomNumberGenerator, cx: int, cy: int, r: int, base: Color) -> void:
	for i in r * 6:
		var a := rng.randf() * TAU
		var d := rng.randf() * r
		var x := cx + roundi(cos(a) * d)
		var y := cy + roundi(sin(a) * d * .8)
		_dot(img, x, y, _mul(base, rng.randf_range(.5, 1.6)), 2, 1)


static func _paint_wall_hedge(variant: int) -> Image:
	# ivy over an iron-banded masonry base: the conservatory / courtyard walls
	var rng := _rng("whedge%d" % variant)
	var img := _new_image(PX, WALL_H)
	var base := Color("26301f")
	_noise(img, 0, 0, PX, WALL_H, base, .22, rng)
	for i in 28:
		_leaf_cluster(img, rng, rng.randi_range(0, 31), rng.randi_range(4, WALL_H - 6), rng.randi_range(2, 5), Color("2a3a26"))
	# a few dusky flowers
	for i in 10:
		var fx := rng.randi_range(2, 28)
		var fy := rng.randi_range(14, WALL_H - 20)
		_dot(img, fx, fy, Color("8a2e52") if i % 2 == 0 else Color("b09a88"), 3, 3)
	# brass-banded masonry plinth
	_dot(img, 0, WALL_H - 30, Color("3a3030"), PX, 30)
	for by in range(WALL_H - 30, WALL_H, 10):
		_dot(img, 0, by, Color("0a0808"), PX, 1)
	_dot(img, 0, WALL_H - 31, Color("8a6a2c"), PX, 1)
	_skirt(img, Color("2a2224"))
	# hanging vines
	for i in 4:
		var vx := rng.randi_range(1, 30)
		_dot(img, vx, rng.randi_range(0, 20), Color("162016"), 1, rng.randi_range(26, 70))
	return img


static func _paint_wall_office(variant: int) -> Image:
	# two-tone plaster: maroon lower half, dull grey-green upper, cork/paper hints
	var rng := _rng("woffice%d" % variant)
	var img := _new_image(PX, WALL_H)
	_wall_base(img, rng, Color("36202a"), Color("2c2a28"))
	_rail(img)
	_skirt(img, Color("1c1214"))
	_cornice(img, Color("2a2828"))
	if variant == 1:
		# pinned papers
		for i in 3:
			var x := rng.randi_range(3, 22)
			var y := rng.randi_range(18, 52)
			_dot(img, x, y, Color("4c4842"), 5, 6)
			_dot(img, x + 2, y, Color("7a2a2a"))
	_grime(img, rng, 4)
	return img



static func _paint_wall_hospital(variant: int) -> Image:
	# clinical two-tone: washable mint lower wall, off-white upper, a teal crash rail between
	var rng := _rng("whosp%d" % variant)
	var img := _new_image(PX, WALL_H)
	_wall_base(img, rng, Color("39504b"), Color("575a55"))
	_dot(img, 0, RAIL_Y - 4, Color("0a0c0c"), PX, 1)
	_dot(img, 0, RAIL_Y - 3, Color("2f6a74"), PX, 4)
	_dot(img, 0, RAIL_Y + 1, Color("173a40"), PX, 1)
	_skirt(img, Color("2a3a38"))
	_cornice(img, Color("4a4c48"))
	if variant == 1:
		# a ward direction stripe and a small room plate
		_dot(img, 0, RAIL_Y + 14, Color("2c5f8a"), PX, 2)
		_dot(img, 10, 30, Color("1b3a5c"), 12, 6)
		_dot(img, 12, 32, Color("c8cfd0"), 8, 2)
	_grime(img, rng, 3)
	return img


static func _paint_wall_lab(variant: int) -> Image:
	# white composite panels with shadow seams, a cyan guide line, a hazard foot on variant 1
	var rng := _rng("wlab%d" % variant)
	var img := _new_image(PX, WALL_H)
	_noise(img, 0, 0, PX, WALL_H, Color("5a5f63"), .04, rng, 2)
	for y in range(CORNICE_H, WALL_H, 40):
		_dot(img, 0, y, Color("1e2224"), PX, 1)
	_dot(img, PX - 1, 0, Color("1e2224"), 1, WALL_H)
	_dot(img, 0, RAIL_Y, Color("1d8a96"), PX, 2)
	for y in [CORNICE_H + 4, CORNICE_H + 44]:
		_rivet(img, 3, y, Color("5a5f63"))
		_rivet(img, PX - 5, y, Color("5a5f63"))
	if variant == 1:
		for y in range(WALL_H - 12, WALL_H):
			for x in PX:
				_dot(img, x, y, Color("7a5c12") if ((x + y) >> 2) & 1 == 1 else Color("14110e"))
	else:
		_skirt(img, Color("2c3134"))
	_cornice(img, Color("3a3f42"))
	return img


static func _paint_wall_glasshouse(variant: int) -> Image:
	# conservatory glazing: green-painted iron bars over night panes, a low brick plinth
	var rng := _rng("wglass%d" % variant)
	var img := _new_image(PX, WALL_H)
	_noise(img, 0, 0, PX, WALL_H, Color("1e2a2e"), .08, rng, 2)
	for i in 5:
		var x := rng.randi_range(2, PX - 6)
		var y := rng.randi_range(CORNICE_H + 2, RAIL_Y)
		_dot(img, x, y, Color("3a4e52"), 1, 6)
	var bar := Color("2b4a30")
	for x in [0, 15, PX - 2]:
		_dot(img, x, 0, bar, 2, WALL_H)
	for y in range(CORNICE_H, WALL_H - 26, 24):
		_dot(img, 0, y, bar, PX, 2)
	for by in range(WALL_H - 26, WALL_H, 6):
		for bx in range(-((by / 6) % 2) * 4, PX, 8):
			_noise(img, maxi(0, bx), by, 7, 5, Color("4a2a22"), .1, rng)
	if variant == 1:
		# leaves pressed against the glass
		for i in 10:
			_dot(img, rng.randi_range(0, PX - 3), rng.randi_range(RAIL_Y - 20, WALL_H - 28), Color("2f5a28"), 3, 2)
	_cornice(img, bar)
	return img

static func _paint_wall_mall(variant: int) -> Image:
	# arcade wall: warm cream plaster over a dark tiled dado, a lit cove strip under the cornice
	var rng := _rng("wmall%d" % variant)
	var img := _new_image(PX, WALL_H)
	_wall_base(img, rng, Color("3a2c2a"), Color("5c524a"))
	for y in range(RAIL_Y + 2, WALL_H - SKIRT_H, 8):
		_dot(img, 0, y, Color("1e1614"), PX, 1)
	for x in [0, 16]:
		_dot(img, x, RAIL_Y, Color("1e1614"), 1, WALL_H - RAIL_Y - SKIRT_H)
	_dot(img, 0, RAIL_Y - 2, Color("7a5c2c"), PX, 2)
	_dot(img, 0, CORNICE_H + 2, Color("c89a5a") if variant == 0 else Color("5fb0b8"), PX, 2)
	_skirt(img, Color("1e1614"))
	_cornice(img, Color("4a423c"))
	_grime(img, rng, 2)
	return img


static func _paint_wall_corridor(variant: int) -> Image:
	# service corridor: bay of dark metal with hazard-striped foot and an amber conduit
	var rng := _rng("wcorr%d" % variant)
	var img := _new_image(PX, WALL_H)
	_wall_base(img, rng, Color("2c2224"), Color("232022"))
	for y in range(0, WALL_H, 42):
		_dot(img, 0, y, Color("080607"), PX, 1)
	for x in [0, PX - 1]:
		_dot(img, x, 0, Color("080607"), 1, WALL_H)
	for y in range(WALL_H - 14, WALL_H):
		for x in PX:
			var yellow := ((x + y) >> 2) & 1
			_dot(img, x, y, Color("6a5010") if yellow == 1 else Color("100d0b"))
	# conduit
	var cy := 22 + variant * 10
	_dot(img, 0, cy, Color("2a1a0c"), PX, 3)
	_dot(img, 0, cy, Color("9a6a2a"), PX, 1)
	for x in [5, 21]:
		_dot(img, x, cy - 1, Color("140d06"), 3, 5)
	_cornice(img, Color("262224"))
	_grime(img, rng, 5)
	return img


static func _paint_wall_inferno(variant: int) -> Image:
	var rng := _rng("winferno%d" % variant)
	var img := _new_image(PX, WALL_H)
	_wall_base(img, rng, Color("2a1210"), Color("1c1214"))
	for i in 6:
		var x := rng.randi_range(2, 29)
		var y := rng.randi_range(14, WALL_H - 20)
		_crack(img, rng, x, y, rng.randi_range(10, 26), Color("c8481a") if i % 2 == 0 else Color("7a2a14"))
	_cornice(img, Color("261614"))
	_skirt(img, Color("1a0e0e"))
	return img


## Basalt for the Inferno's caves: no paving, no panels. A dark volcanic ground with grit, pits, paler flecks and the odd ember
## crack, so a chunk of cave floor never reads as plates.
static func _paint_rock_floor(variant: int) -> Image:
	var rng := _rng("rockfloor%d" % variant)
	var img := _new_image(PX, PX)
	var base := Color("2c2527") if variant != 1 else Color("30272a")
	_noise(img, 0, 0, PX, PX, base, .2, rng, 2)
	_noise(img, 0, 0, PX, PX, base, .1, rng)
	for i in 34:
		var shade := Color("0f0b0c") if i % 3 != 0 else Color("4a403f")
		_dot(img, rng.randi_range(0, 31), rng.randi_range(0, 31), shade, rng.randi_range(1, 3), rng.randi_range(1, 2))
	for i in 3:
		_crack(img, rng, rng.randi_range(2, 29), rng.randi_range(2, 29), rng.randi_range(5, 12), Color("0c0809"))
	if variant == 2:
		for i in 2:
			_crack(img, rng, rng.randi_range(2, 29), rng.randi_range(2, 29), rng.randi_range(5, 11), Color("c8481a") if i == 0 else Color("7a2a14"))
	return img


## Cave wall: strata in uneven bands, vertical weathering streaks, ember cracks, and a ragged dark top instead of a cornice.
static func _paint_wall_rock(variant: int) -> Image:
	var rng := _rng("rockwall%d" % variant)
	var img := _new_image(PX, WALL_H)
	var base := Color("2a2224") if variant % 2 == 0 else Color("2f2325")
	_noise(img, 0, 0, PX, WALL_H, base, .16, rng, 2)
	var y := 0
	while y < WALL_H:
		var band := rng.randi_range(6, 18)
		var tone := rng.randf_range(.78, 1.18)
		for x in PX:
			if rng.randf() < .7:
				_dot(img, x, y, _mul(base, tone * rng.randf_range(.9, 1.1)), 1, band)
		_dot(img, 0, y, Color("0d0909"), PX, 1)
		y += band
	for i in 10:
		_dot(img, rng.randi_range(0, 31), rng.randi_range(0, WALL_H - 8), Color("0c0808"), 1, rng.randi_range(4, 20))
	# ember cracks: how many (none on some variants) and where differs per variant, so no pattern repeats along a wall
	var cracks: int = [3, 0, 2, 4, 1, 0, 3, 2][variant % 8]
	for i in cracks:
		_crack(img, rng, rng.randi_range(2, 29), rng.randi_range(12, WALL_H - 16), rng.randi_range(8, 24),
			Color("c8481a") if i % 2 == 0 else Color("7a2a14"))
	# ragged top: the rock above the cave ceiling bites down unevenly
	for x in PX:
		_dot(img, x, 0, Color("0c0809"), 1, rng.randi_range(2, 9))
	_dot(img, 0, WALL_H - 3, Color("100b0c"), PX, 3)
	return img


static func _paint_rock_ceiling(variant: int) -> Image:
	var rng := _rng("rockceil%d" % variant)
	var img := _new_image(PX, PX)
	var base := Color("151012")
	_noise(img, 0, 0, PX, PX, base, .22, rng, 2)
	for i in 14:
		_dot(img, rng.randi_range(0, 31), rng.randi_range(0, 31), Color("07040a") if i % 2 == 0 else Color("2a2022"), rng.randi_range(2, 5), rng.randi_range(2, 4))
	return img


# -- ceilings ------------------------------------------------------------------

static func _paint_ceiling(variant: int) -> Image:
	var rng := _rng("ceil%d" % variant)
	var img := _new_image(PX, PX)
	var base := Color("100d0f") if variant == 0 else Color("120a0c")
	_noise(img, 0, 0, PX, PX, base, .14, rng)
	# coffered grid with raised beams
	_dot(img, 0, 0, _mul(base, 2.2), PX, 2)
	_dot(img, 0, 0, _mul(base, 2.2), 2, PX)
	_dot(img, 2, 2, Color("050304"), PX - 2, 1)
	_dot(img, 2, 2, Color("050304"), 1, PX - 2)
	for r in [[8, 8], [22, 22]]:
		_rivet(img, r[0], r[1], base)
	if variant == 1:
		_dot(img, 14, 14, _mul(base, .6), 6, 6)
	return img


## The sewer's barrel vault: damp concrete with a faint course line in one
## direction only, so a long tunnel ceiling reads as a plain vault instead of
## the coffered beam grid (whose 1 m beams read as a lattice of crosses). Light
## enough to read as a slab under the lamps ("floating lights" — at 110e0e
## the vault rendered as black space and every ceiling lamp hung in a void).
static func _paint_vault(_variant: int) -> Image:
	var rng := _rng("vault")
	var img := _new_image(PX, PX)
	var base := Color("4a443d")
	_noise(img, 0, 0, PX, PX, base, .18, rng)
	_dot(img, 0, 0, _mul(base, 1.35), PX, 1)
	for i in 4:
		_dot(img, rng.randi_range(1, PX - 3), rng.randi_range(3, PX - 3), _mul(base, .55), 2, 1)
	return img


static func _paint_glass(_variant: int) -> Image:
	# glass-and-iron conservatory roof: night panes in a black lattice
	var rng := _rng("glass")
	var img := _new_image(PX, PX)
	for y in PX:
		for x in PX:
			var shade := 1.0 + rng.randf_range(-.15, .15)
			_dot(img, x, y, _mul(Color("0c1426"), shade))
	for i in 5:
		_dot(img, rng.randi_range(2, 29), rng.randi_range(2, 29), Color("2a4a66"))
	for k in [0, 16]:
		_dot(img, k, 0, Color("07070a"), 2, PX)
		_dot(img, 0, k, Color("07070a"), PX, 2)
		_dot(img, k + 2, 0, Color("3a2e1c"), 1, PX)
		_dot(img, 0, k + 2, Color("3a2e1c"), PX, 1)
	return img


# -- beach -------------------------------------------------
#
# A stylised daylight beach for the Beach district: warm pale sand, damp sand, bleached boardwalk planks, sea-washed
# stone, whitewashed and turquoise-painted planking and a bright sky-blue skylight ceiling. Painted values stay under
# ~0.7 per channel because floors and walls are lifted by 1.25-1.4 at draw time. No purple or magenta anywhere here.

const SAND := Color("9a8460")
const WET_SAND := Color("6c6150")
const DRIFTWOOD := Color("8a7c68")
const SEA_STONE := Color("78807a")
const SEA_TEAL := Color("3f8a8a")
const SEA_CREAM := Color("b0a68c")


## Sand floors, 32x32: 0 dry sand with faint ripple lines, 1 sand with shell and pebble flecks, 2 darker damp sand with
## a cool sheen. The ripples are whole sine periods across the 32 texels so the tile repeats without a seam.
static func _paint_sand(variant: int) -> Image:
	var rng := _rng("sand%d" % variant)
	var img := _new_image(PX, PX)
	var wet: bool = variant == 2
	var base: Color = WET_SAND if wet else SAND
	_noise(img, 0, 0, PX, PX, base, .06, rng, 2)
	for i in 90:
		var speck: Color = _mul(base, .86 if rng.randf() < .5 else 1.12)
		_dot(img, rng.randi_range(0, PX - 1), rng.randi_range(0, PX - 1), speck)
	var ripples: int = [2, 1, 3][variant]
	for r in ripples:
		var y0: int = rng.randi_range(5, PX - 6)
		var amp: float = rng.randf_range(1.0, 2.0)
		var phase: float = rng.randf() * TAU
		for x in PX:
			var y: int = y0 + roundi(sin(float(x) / PX * TAU + phase) * amp)
			_dot(img, x, y, _mul(base, .8 if wet else .84))
			_dot(img, x, y - 1, _mul(base, 1.12))
	if wet:
		# damp sheen: cool grey flecks and a few dark soaked patches
		for i in 14:
			_dot(img, rng.randi_range(0, PX - 2), rng.randi_range(0, PX - 1), Color("8a8878"), rng.randi_range(1, 2), 1)
		for i in 3:
			_dot(img, rng.randi_range(0, PX - 5), rng.randi_range(0, PX - 3), Color("52483a"), rng.randi_range(3, 5), 2)
	elif variant == 1:
		# shell fragments (cream) and small pebbles (grey-tan with a shadow underneath)
		for i in 7:
			_dot(img, rng.randi_range(0, PX - 2), rng.randi_range(0, PX - 2), Color("c4b896"), rng.randi_range(1, 2), 1)
		for i in 4:
			var px: int = rng.randi_range(0, PX - 3)
			var py: int = rng.randi_range(0, PX - 4)
			_dot(img, px, py + 1, Color("4a4238"), 2, 2)
			_dot(img, px, py, Color("6e6658"), 2, 2)
	else:
		for i in 2:
			_dot(img, rng.randi_range(0, PX - 2), rng.randi_range(0, PX - 2), Color("c4b896"), 2, 1)
	return img


## Bleached boardwalk planks, 32x32: 0 runs across, 1 runs down. 8 px boards in sun-greyed tan with light seams
## (nothing near black), staggered end joints, nail heads and long grain streaks.
static func _paint_driftwood(variant: int) -> Image:
	var rng := _rng("driftwood%d" % variant)
	var img := _new_image(PX, PX)
	var seam: Color = Color("4e4436")
	var nail: Color = Color("3e362c")
	for band in 4:
		var shade: float = rng.randf_range(.86, 1.14)
		var board: Color = _mul(DRIFTWOOD, shade)
		var joint: int = (rng.randi() % 20) + 4 + (band % 2) * 6
		if variant == 0:
			var y0: int = band * 8
			_noise(img, 0, y0, PX, 8, board, .08, rng)
			_dot(img, 0, y0 + 7, seam, PX, 1)
			_dot(img, joint % PX, y0, seam, 1, 8)
			for g in 4:
				_dot(img, rng.randi_range(0, 30), y0 + rng.randi_range(1, 6), _mul(board, .78), rng.randi_range(3, 8), 1)
			_dot(img, rng.randi_range(0, 28), y0 + rng.randi_range(1, 6), _mul(board, 1.18), rng.randi_range(2, 5), 1)
			_dot(img, (joint + 2) % PX, y0 + 3, nail, 1, 1)
			_dot(img, (joint + PX - 3) % PX, y0 + 3, nail, 1, 1)
		else:
			var x0: int = band * 8
			_noise(img, x0, 0, 8, PX, board, .08, rng)
			_dot(img, x0 + 7, 0, seam, 1, PX)
			_dot(img, x0, joint % PX, seam, 8, 1)
			for g in 4:
				_dot(img, x0 + rng.randi_range(1, 6), rng.randi_range(0, 24), _mul(board, .78), 1, rng.randi_range(3, 8))
			_dot(img, x0 + rng.randi_range(1, 6), rng.randi_range(0, 26), _mul(board, 1.18), 1, rng.randi_range(2, 5))
			_dot(img, x0 + 3, (joint + 2) % PX, nail, 1, 1)
			_dot(img, x0 + 3, (joint + PX - 3) % PX, nail, 1, 1)
	return img


## Light caps for the beach walls: the stock cornice and skirt darken their colour to about half, which would paint a
## dark stripe along a pale wall, so these keep the wall's own value.
static func _sea_cornice(img: Image, c: Color) -> void:
	_dot(img, 0, 0, _mul(c, .82), PX, CORNICE_H)
	_dot(img, 0, CORNICE_H - 3, _mul(c, 1.15), PX, 1)
	_dot(img, 0, CORNICE_H, _mul(c, .55), PX, 1)


static func _sea_skirt(img: Image, c: Color) -> void:
	_dot(img, 0, WALL_H - SKIRT_H, _mul(c, .78), PX, SKIRT_H)
	_dot(img, 0, WALL_H - SKIRT_H, _mul(c, 1.15), PX, 1)
	_dot(img, 0, WALL_H - SKIRT_H - 1, _mul(c, .55), PX, 1)


## Seawall: pale sea-washed stone blocks with light mortar, algae-teal staining and a few shells towards the foot.
static func _paint_wall_seawall(variant: int) -> Image:
	var rng := _rng("wseawall%d" % variant)
	var img := _new_image(PX, WALL_H)
	var base: Color = _mul(SEA_STONE, 1.0 if variant == 0 else .94)
	var mortar: Color = _mul(base, .68)
	_noise(img, 0, 0, PX, WALL_H, base, .08, rng, 2)
	var y: int = CORNICE_H + 1
	while y < WALL_H - SKIRT_H:
		var h: int = [14, 18, 22][rng.randi() % 3]
		_dot(img, 0, y, mortar, PX, 1)
		_dot(img, rng.randi_range(4, 27), y, mortar, 1, h)
		_dot(img, 0, y + 1, _mul(base, 1.18), PX, 1)
		y += h
	# algae staining that thickens towards the tide line
	var algae: Color = Color("4f8478")
	for i in 46:
		var ay: int = WALL_H - SKIRT_H - 1 - int(pow(rng.randf(), 1.8) * 46.0)
		_dot(img, rng.randi_range(0, PX - 1), ay, algae if i % 3 != 0 else _mul(algae, .8), 1, rng.randi_range(2, 6))
	for i in 5:
		_dot(img, rng.randi_range(0, PX - 2), rng.randi_range(WALL_H - 40, WALL_H - SKIRT_H - 3), Color("c0b89c"), 2, 1)
	_sea_cornice(img, _mul(base, 1.1))
	_sea_skirt(img, _mul(base, .95))
	return img


## Whitewashed planks: cream vertical boards with light seams and flaking paint over grey wood; variant 0 has a turquoise
## stripe under a cream chair rail, variant 1 a full turquoise dado.
static func _paint_wall_whitewash(variant: int) -> Image:
	var rng := _rng("wwhitewash%d" % variant)
	var img := _new_image(PX, WALL_H)
	var cream: Color = SEA_CREAM
	for band in 4:
		var x0: int = band * 8
		var board: Color = _mul(cream, rng.randf_range(.92, 1.06))
		_noise(img, x0, CORNICE_H, 8, WALL_H - CORNICE_H, board, .05, rng)
		_dot(img, x0 + 7, CORNICE_H, _mul(cream, .66), 1, WALL_H - CORNICE_H)
		_dot(img, x0, CORNICE_H, _mul(cream, 1.08), 1, WALL_H - CORNICE_H)
	for i in 14:
		_dot(img, rng.randi_range(1, 30), rng.randi_range(CORNICE_H + 2, RAIL_Y - 4), _mul(cream, .8), 1, rng.randi_range(4, 14))
	# flaked paint showing the grey wood
	for i in 9:
		_dot(img, rng.randi_range(0, 29), rng.randi_range(CORNICE_H + 4, WALL_H - SKIRT_H - 4), Color("7a7466"), rng.randi_range(1, 3), 1)
	if variant == 1:
		for band in 4:
			_dot(img, band * 8, RAIL_Y, _mul(SEA_TEAL, rng.randf_range(.94, 1.06)), 8, WALL_H - RAIL_Y)
			_dot(img, band * 8 + 7, RAIL_Y, _mul(SEA_TEAL, .7), 1, WALL_H - RAIL_Y)
	else:
		_dot(img, 0, RAIL_Y + 2, SEA_TEAL, PX, 6)
	_dot(img, 0, RAIL_Y - 1, _mul(cream, 1.2), PX, 2)
	_dot(img, 0, RAIL_Y + 1, _mul(cream, .6), PX, 1)
	_sea_cornice(img, cream)
	_sea_skirt(img, _mul(SEA_TEAL if variant == 1 else cream, .9))
	return img


## Turquoise painted panelling: vertical beadboard with a cream cap rail and inset panels; variant 1 is a lighter aqua
## over a sandy upper wall.
static func _paint_wall_tealpanel(variant: int) -> Image:
	var rng := _rng("wtealpanel%d" % variant)
	var img := _new_image(PX, WALL_H)
	var paint: Color = SEA_TEAL if variant == 0 else Color("58a8a0")
	var upper: Color = paint if variant == 0 else Color("a89c80")
	_noise(img, 0, CORNICE_H, PX, RAIL_Y - CORNICE_H, upper, .05, rng)
	_noise(img, 0, RAIL_Y, PX, WALL_H - RAIL_Y, paint, .05, rng)
	# beadboard grooves, every 4 px
	for x in range(3, PX, 4):
		_dot(img, x, CORNICE_H + 1, _mul(upper, .72), 1, RAIL_Y - CORNICE_H - 2)
		_dot(img, x, RAIL_Y + 3, _mul(paint, .72), 1, WALL_H - RAIL_Y - SKIRT_H - 4)
	# inset panel frame on the dado
	_dot(img, 0, RAIL_Y + 8, _mul(paint, 1.2), PX, 1)
	_dot(img, 0, WALL_H - SKIRT_H - 6, _mul(paint, .7), PX, 1)
	# cream cap rail
	_dot(img, 0, RAIL_Y - 2, Color("c0b698"), PX, 3)
	_dot(img, 0, RAIL_Y + 1, _mul(paint, .6), PX, 1)
	for i in 6:
		_dot(img, rng.randi_range(0, 30), rng.randi_range(CORNICE_H + 4, WALL_H - SKIRT_H - 4), _mul(paint, .85), 1, rng.randi_range(2, 5))
	_sea_cornice(img, Color("a89c80") if variant == 1 else SEA_CREAM)
	_sea_skirt(img, paint)
	return img


## Bright sky ceiling, 32x32: pale sky-blue panes with a few cloud flecks inside a warm timber lattice, so the beach
## halls read as roofed in daylight rather than a night glass roof.
static func _paint_skylight(_variant: int) -> Image:
	var rng := _rng("skylight")
	var img := _new_image(PX, PX)
	var sky: Color = Color("7a9fb2")
	_noise(img, 0, 0, PX, PX, sky, .04, rng, 2)
	for i in 7:
		_dot(img, rng.randi_range(2, 28), rng.randi_range(2, 28), Color("a8c4cc"), rng.randi_range(2, 4), 1)
	var beam: Color = Color("a8946e")
	for k in [0, 16]:
		_dot(img, k, 0, beam, 2, PX)
		_dot(img, 0, k, beam, PX, 2)
		_dot(img, k + 2, 0, _mul(beam, .6), 1, PX)
		_dot(img, 0, k + 2, _mul(beam, .6), PX, 1)
	return img


# -- public API ----------------------------------------------------------------

const FLOOR_PAINTERS := {
	"metal0": [&"_paint_metal", 0], "metal1": [&"_paint_metal", 1],
	"metal2": [&"_paint_metal", 2], "metal3": [&"_paint_metal", 3],
	"floral0": [&"_paint_floral", 0], "floral1": [&"_paint_floral", 1],
	"star0": [&"_paint_star", 0], "star1": [&"_paint_star", 1],
	"parquet0": [&"_paint_parquet", 0], "parquet1": [&"_paint_parquet", 1],
	"stone0": [&"_paint_stone", 0], "stone1": [&"_paint_stone", 1],
	"stone2": [&"_paint_stone", 2],
	"check0": [&"_paint_check", 0], "check1": [&"_paint_check", 1],
	"hazard": [&"_paint_hazard", 0], "runner": [&"_paint_runner", 0],
	"grate": [&"_paint_grate", 0], "runnerz": [&"_paint_runner_z", 0],
	"safe": [&"_paint_safe", 0], "safe_plain": [&"_paint_safe_plain", 0], "safe_mark": [&"_paint_safe_mark", 0],
	"runner_l": [&"_paint_runner_l", 0], "runner_c": [&"_paint_runner_c", 0], "runner_r": [&"_paint_runner_r", 0],
	"carpet_red": [&"_paint_carpet", 0], "carpet_teal": [&"_paint_carpet", 1], "carpet_green": [&"_paint_carpet", 2],
	"carpet_plum": [&"_paint_carpet", 3], "carpet_tile0": [&"_paint_carpet_tile", 0], "carpet_tile1": [&"_paint_carpet_tile", 1],
	"vinyl0": [&"_paint_vinyl", 0], "vinyl1": [&"_paint_vinyl", 1], "concrete0": [&"_paint_concrete", 0],
	"concrete1": [&"_paint_concrete", 1],
	"runnerz_l": [&"_paint_runnerz_l", 0], "runnerz_c": [&"_paint_runnerz_c", 0], "runnerz_r": [&"_paint_runnerz_r", 0],
	"terrazzo0": [&"_paint_terrazzo", 0], "terrazzo1": [&"_paint_terrazzo", 1],
	"epoxy0": [&"_paint_epoxy", 0], "epoxy1": [&"_paint_epoxy", 1],
	"terracotta0": [&"_paint_terracotta", 0], "terracotta1": [&"_paint_terracotta", 1],
	"rock0": [&"_paint_rock_floor", 0], "rock1": [&"_paint_rock_floor", 1], "rock2": [&"_paint_rock_floor", 2],
	# beach: sand, damp sand, bleached boardwalk planks. Appended: ceiling layers shift, lookups are by name
	"sand0": [&"_paint_sand", 0], "sand1": [&"_paint_sand", 1], "wetsand0": [&"_paint_sand", 2],
	"driftwood0": [&"_paint_driftwood", 0], "driftwood1": [&"_paint_driftwood", 1],
}
const WALL_PAINTERS := {
	"panel0": [&"_paint_wall_panel", 0], "panel1": [&"_paint_wall_panel", 1],
	"panel2": [&"_paint_wall_panel", 2],
	"paper0": [&"_paint_wall_wallpaper", 0], "paper1": [&"_paint_wall_wallpaper", 1],
	"brick0": [&"_paint_wall_brick", 0], "brick1": [&"_paint_wall_brick", 1],
	"stone0": [&"_paint_wall_stone", 0], "stone1": [&"_paint_wall_stone", 1],
	"hedge0": [&"_paint_wall_hedge", 0], "hedge1": [&"_paint_wall_hedge", 1],
	"office0": [&"_paint_wall_office", 0], "office1": [&"_paint_wall_office", 1],
	"corridor0": [&"_paint_wall_corridor", 0], "corridor1": [&"_paint_wall_corridor", 1],
	"inferno0": [&"_paint_wall_inferno", 0],
	"rockwall0": [&"_paint_wall_rock", 0], "rockwall1": [&"_paint_wall_rock", 1], "rockwall2": [&"_paint_wall_rock", 2],
	"rockwall3": [&"_paint_wall_rock", 3], "rockwall4": [&"_paint_wall_rock", 4], "rockwall5": [&"_paint_wall_rock", 5], "rockwall6": [&"_paint_wall_rock", 6],
	"rockwall7": [&"_paint_wall_rock", 7],
	"hospital0": [&"_paint_wall_hospital", 0], "hospital1": [&"_paint_wall_hospital", 1],
	"lab0": [&"_paint_wall_lab", 0], "lab1": [&"_paint_wall_lab", 1],
	"mall0": [&"_paint_wall_mall", 0], "mall1": [&"_paint_wall_mall", 1],
	"glasshouse0": [&"_paint_wall_glasshouse", 0], "glasshouse1": [&"_paint_wall_glasshouse", 1],
	"seawall0": [&"_paint_wall_seawall", 0], "seawall1": [&"_paint_wall_seawall", 1],
	"whitewash0": [&"_paint_wall_whitewash", 0], "whitewash1": [&"_paint_wall_whitewash", 1],
	"tealpanel0": [&"_paint_wall_tealpanel", 0], "tealpanel1": [&"_paint_wall_tealpanel", 1],
}
const CEILING_PAINTERS := {
	"ceil0": [&"_paint_ceiling", 0], "ceil1": [&"_paint_ceiling", 1],
	"glass": [&"_paint_glass", 0],
	"rockceil": [&"_paint_rock_ceiling", 0],
	"vault": [&"_paint_vault", 0],
	"skylight0": [&"_paint_skylight", 0],
}


static func texture(group: String, kind: String) -> Texture2D:
	var key := "%s:%s" % [group, kind]
	if _textures.has(key):
		return _textures[key]
	var table: Dictionary = {"floor": FLOOR_PAINTERS, "wall": WALL_PAINTERS,
		"ceiling": CEILING_PAINTERS}[group]
	var known := table.has(kind)
	var entry: Array = table[kind] if known else table[table.keys()[0]]
	var img: Image = _paint(group, kind if known else String(table.keys()[0]), entry)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## Shared material per (group, kind). Floors get a wet, low-roughness sheen
## except fabric; the colour multiplier is white so palette lives in the texels.
static func material(group: String, kind: String) -> StandardMaterial3D:
	var key := "%s:%s" % [group, kind]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(group, kind)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = MaterialLook.ROUGHNESS_MATTE
	m.metallic_specular = MaterialLook.SPECULAR_DEFAULT
	# painted values are deliberately dark; lift them so a lamp pool reads
	m.albedo_color = Color(1.4, 1.4, 1.45)
	if group == "ceiling":
		m.albedo_color = Color(.8, .78, .85)
		if kind == "glass":
			# no self-glow: the conservatory roof's night panes lit nothing, so they read as a fake blue lamp
			m.albedo_color = Color(1.2, 1.2, 1.3)
			RefDecor.cheap_dark(m)    # dark-only glass: Lambert, no specular (perf)
	elif group == "floor" and (kind.begins_with("metal") or kind == "grate" or kind == "hazard"):
		m.albedo_color = Color(1.2, 1.2, 1.25)
	if group == "floor":
		if not (kind.begins_with("floral") or kind.begins_with("star") or kind == "runner"):
			var response := MaterialLook.floor_response(kind)
			m.roughness = response.x
			m.metallic = response.y
			m.metallic_specular = response.z
	_materials[key] = m
	return m


# -- vent ducts ----------------------------------------------------------------

const DUCT_PAINTERS := {
	"sheet": &"_paint_duct_sheet",
	"flange": &"_paint_duct_flange",
	"grille": &"_paint_duct_grille",
}
const DUCT_STEEL := Color("5d666c")


## Galvanised duct sheet, one 32x32 tile per metre of run: a standing seam and a rivet row at the joint, the
## cross-break "X" pressed into every panel, spangle grain, and grime pooled towards the bottom edge (v = 1).
static func _paint_duct_sheet() -> Image:
	var rng := _rng("duct_sheet")
	var img := _new_image(PX, PX)
	_noise(img, 0, 0, PX, PX, DUCT_STEEL, .07, rng)
	for i in 10:   # spangle: the crystalline flecks of hot-dip galvanising
		_dot(img, rng.randi_range(2, 29), rng.randi_range(2, 29), _mul(DUCT_STEEL, 1.22), rng.randi_range(1, 3), 1)
	for i in PX:   # cross-break, a shallow pressed X: lit on one stroke, shaded on the other
		_dot(img, i, i, _mul(DUCT_STEEL, 1.14))
		_dot(img, PX - 1 - i, i, _mul(DUCT_STEEL, .86))
	for y in range(20, PX):   # dust and condensation streaks settling low on the sheet
		for x in PX:
			if rng.randf() < float(y - 20) / 40.0:
				_dot(img, x, y, _mul(img.get_pixel(x, y), .8))
	for i in 3:
		_dot(img, rng.randi_range(4, 27), rng.randi_range(18, 26), Color("3d3027"), 1, rng.randi_range(3, 6))
	# the joint: a raised standing seam (lit lip, shadowed fold) and its rivets
	_dot(img, 0, 0, _mul(DUCT_STEEL, 1.55), 2, PX)
	_dot(img, 2, 0, _mul(DUCT_STEEL, .5), 1, PX)
	_dot(img, PX - 1, 0, _mul(DUCT_STEEL, .7), 1, PX)
	for ry in [4, 12, 20, 28]:
		_rivet(img, 4, ry, DUCT_STEEL)
	# the folded edges along the run
	_dot(img, 0, 0, _mul(DUCT_STEEL, 1.3), PX, 1)
	_dot(img, 0, PX - 1, _mul(DUCT_STEEL, .55), PX, 1)
	return img


## The bolted joint ring between two duct sections: a darker angle-iron band with bolt heads.
static func _paint_duct_flange() -> Image:
	var rng := _rng("duct_flange")
	var img := _new_image(PX, PX)
	var base := _mul(DUCT_STEEL, .62)
	_noise(img, 0, 0, PX, PX, base, .1, rng)
	_dot(img, 0, 0, _mul(base, 1.6), PX, 2)
	_dot(img, 0, PX - 2, _mul(base, .5), PX, 2)
	for by in [6, 16, 26]:
		_dot(img, 13, by - 1, _mul(base, .4), 6, 4)
		_dot(img, 14, by - 1, _mul(base, 1.7), 4, 2)
	for i in 3:
		_dot(img, rng.randi_range(2, 28), rng.randi_range(3, 28), Color("4a2c14"), 2, 1)
	return img


## A louvred return grille in a frame, screwed at the corners, seen from below where a hatch opens.
static func _paint_duct_grille() -> Image:
	var img := _new_image(PX, PX)
	var frame := _mul(DUCT_STEEL, 1.1)
	img.fill(frame)
	_dot(img, 0, 0, _mul(frame, 1.35), PX, 1)
	_dot(img, 0, 0, _mul(frame, 1.35), 1, PX)
	_dot(img, PX - 1, 0, _mul(frame, .55), 1, PX)
	_dot(img, 0, PX - 1, _mul(frame, .55), PX, 1)
	_dot(img, 4, 4, Color("07080a"), PX - 8, PX - 8)
	for gy in range(5, PX - 5, 3):   # slats: lit top lip, mid face, shadow beneath, dark gap
		_dot(img, 4, gy, _mul(frame, 1.25), PX - 8, 1)
		_dot(img, 4, gy + 1, _mul(frame, .75), PX - 8, 1)
	for s in [[1, 1], [PX - 3, 1], [1, PX - 3], [PX - 3, PX - 3]]:
		_rivet(img, s[0], s[1], frame)
	return img


static func duct_material(kind: String) -> StandardMaterial3D:
	var key := "duct:%s" % kind
	if _materials.has(key):
		return _materials[key]
	var img: Image = Callable(RefTextures, DUCT_PAINTERS.get(kind, DUCT_PAINTERS["sheet"])).call()
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	m.albedo_color = Color(1.12, 1.12, 1.16)
	m.roughness = MaterialLook.ROUGHNESS_METAL
	m.metallic = MaterialLook.METALLIC_METAL
	m.metallic_specular = MaterialLook.SPECULAR_METAL
	_materials[key] = m
	return m


# -- texture arrays (one material per chunk surface) ----------------------------

static var _array_textures := {}
static var _array_layers := {}
static var _array_materials := {}
const ARRAY_SHADER := preload("res://game/look/ref_surface.gdshader")


## Floors and ceilings share one 32x32 array ("floor"); walls have their own
## 32x128 array ("wall"). Layer order is the painter tables' order.
static func _array_kinds(group: String) -> Array:
	if group == "wall":
		return WALL_PAINTERS.keys()
	return FLOOR_PAINTERS.keys() + CEILING_PAINTERS.keys()


static func _build_array(group: String) -> void:
	var kinds := _array_kinds(group)
	var images: Array[Image] = []
	var layers := {}
	for i in kinds.size():
		var kind: String = kinds[i]
		layers[kind] = i
		var table: Dictionary = WALL_PAINTERS if group == "wall" else (
			FLOOR_PAINTERS if FLOOR_PAINTERS.has(kind) else CEILING_PAINTERS)
		var entry: Array = table[kind]
		var img: Image = _paint("wall" if group == "wall" else ("floor" if FLOOR_PAINTERS.has(kind) else "ceiling"), kind,
			entry)
		img.generate_mipmaps()
		images.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	_array_textures[group] = arr
	_array_layers[group] = layers


static func layer(group: String, kind: String) -> float:
	if not _array_layers.has(group):
		_build_array(group)
	return float((_array_layers[group] as Dictionary).get(kind, 0))


## Daylight floor of the beach kinds: the share of the painted texel the surface shows with no lamp
## near, so a sand, seawall or whitewash room reads as sunlit at a glance instead of black away from a lantern. Only the
## beach's own kinds are listed (no other region paints them), so no other district changes.
const BEACH_EMIT_FLOOR := .6
const BEACH_EMIT_WALL := .6
const BEACH_EMIT_SKY := .9
const BEACH_DAYLIGHT := {
	"floor": {"sand0": BEACH_EMIT_FLOOR, "sand1": BEACH_EMIT_FLOOR, "wetsand0": BEACH_EMIT_FLOOR,
		"driftwood0": BEACH_EMIT_FLOOR, "driftwood1": BEACH_EMIT_FLOOR},
	"wall": {"seawall0": BEACH_EMIT_WALL, "seawall1": BEACH_EMIT_WALL, "whitewash0": BEACH_EMIT_WALL,
		"whitewash1": BEACH_EMIT_WALL, "tealpanel0": BEACH_EMIT_WALL, "tealpanel1": BEACH_EMIT_WALL},
	"ceiling": {"skylight0": BEACH_EMIT_SKY},
}


## Vertex-colour surface response: r = roughness, g = metallic, b = emission.
static func params(group: String, kind: String) -> Color:
	var rough := MaterialLook.ROUGHNESS_MATTE
	var metal := MaterialLook.METALLIC_DEFAULT
	var emit := 0.0
	if group == "floor":
		var response := MaterialLook.floor_response(kind)
		rough = response.x
		metal = response.y
	elif group == "ceiling" and kind == "vault":
		# the sewer has no ambient fill and its lamps light downward: a faint glow keeps the vault a visible slab
		# over the fittings instead of black space ("floating lights")
		emit = .16
	# the beach is a daylight seaside: its own kinds carry a daylight floor that rides in the
	# vertex colour, a beach-only ambient with no light and no shader change
	if BEACH_DAYLIGHT.has(group) and (BEACH_DAYLIGHT[group] as Dictionary).has(kind):
		emit = float((BEACH_DAYLIGHT[group] as Dictionary)[kind])
	return Color(rough, metal, emit)


static func array_material(group: String) -> ShaderMaterial:
	if _array_materials.has(group):
		return _array_materials[group]
	if not _array_textures.has(group):
		_build_array(group)
	var m := ShaderMaterial.new()
	# ref_surface.gdshader unless the shader-lights mode is on (ShaderLights): then its lit twin
	m.shader = ShaderLights.surface_shader(ARRAY_SHADER)
	m.set_shader_parameter("tex", _array_textures[group])
	m.set_shader_parameter("tint", Vector3(1.25, 1.22, 1.3))
	m.set_shader_parameter("specular_base", MaterialLook.SPECULAR_DEFAULT)
	m.set_shader_parameter("specular_metal", MaterialLook.SPECULAR_METAL)
	ShaderLights.register_material(m, ARRAY_SHADER)
	_array_materials[group] = m
	return m
