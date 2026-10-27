class_name CityFacadeDetails
extends RefCounted

## Street-facing facade dressing for the City, drawn from the same atlas as the walls: wall materials per building, shop
## awnings and neon signs, balconies, fire escapes, drainpipes and rooftop chimneys. Everything here is visual only: it hangs
## above head height (awnings 2.4 m, balconies 5 m+) or is a thin pipe on the wall, so it adds no collision and no nav change.

const VARIANTS := 6
## Facade base (below and between the windows) for the "brick" style, by variant.
const BASES := ["", "", "brick_dark", "stucco", "ashlar", "ivy"]


static func variant_of(salt: int) -> int:
	return salt % VARIANTS


## The wall tile between windows. Variant 0/1 keep the three-brick mix, the rest give the building its own material; ivy
## climbs the lower floors only.
static func base_tile(variant: int, y: int, h: int) -> int:
	var name: String = BASES[variant]
	if name == "":
		return CityAtlas.tile(["brick_a", "brick_b", "brick_c"][h % 3])
	if name == "ivy" and y > 5:
		return CityAtlas.tile("brick_b")
	return CityAtlas.tile(name)


## A box standing off a cell's face: `d` metres out, `h` tall from `y`, `width` across the face (centred).
static func _protrude(surface: CitySurface, x: int, z: int, dir: Vector2i, y: float, h: float, d: float, width: float,
		tile: int, top_tile: int = -1, gap: float = 0.0) -> void:
	var across := (1.0 - width) * .5
	if dir.y != 0:
		var z0 := z + 1.0 + gap if dir.y > 0 else z - d - gap
		surface.box(Vector3(x + across, y, z0), Vector3(width, h, d), tile, top_tile)
	else:
		var x0 := x + 1.0 + gap if dir.x > 0 else x - d - gap
		surface.box(Vector3(x0, y, z + across), Vector3(d, h, width), tile, top_tile)


## Dressing for one outdoor face of a facade cell. `pier` is the cell's index along the face.
static func add_face(surface: CitySurface, building: Dictionary, dir: Vector2i, x: int, z: int, pier: int, top: int, salt: int) -> void:
	var kind := String(building.get("kind", ""))
	var window_pier := pier % 3 == 1
	var awning := CityAtlas.tile("awning_red" if salt % 2 == 0 else "awning_teal")
	var steel := CityAtlas.tile("fire_escape")
	if (kind == "shop" or kind == "cafe") and window_pier:
		# Striped awning over the shop window, a lit sign above it on every other bay.
		_protrude(surface, x, z, dir, 2.45, .12, 1.0, .92, awning, awning)
		if (pier / 3) % 2 == 0:
			_protrude(surface, x, z, dir, 3.05, .7, .18, .92, CityAtlas.tile("neon_sign"))
	elif kind == "office" or kind == "lobby":
		if pier % 5 == 2:
			_protrude(surface, x, z, dir, 3.2, .6, .16, .8, CityAtlas.tile("neon_sign"))
	if kind == "apartment" and window_pier and top >= 10:
		for floor_y in [5.0, 9.0]:
			_protrude(surface, x, z, dir, floor_y, .12, .9, .92, CityAtlas.tile("stone_dark"))
			_protrude(surface, x, z, dir, floor_y + .12, .8, .06, .92, steel, -1, .84)
	if (kind == "apartment" or kind == "workshop" or kind == "office") and salt % 3 == 0 and pier % 9 == 4 and top >= 10:
		# A fire escape: landings every four metres and a ladder column between them, from above head height.
		for landing in range(4, top - 2, 4):
			_protrude(surface, x, z, dir, float(landing), .1, .9, .9, steel, steel)
		_protrude(surface, x, z, dir, 3.4, float(top - 6), .08, .5, steel)
	if pier % 11 == 0 and top >= 8:
		_protrude(surface, x, z, dir, 0.0, float(top - 1), .1, .12, CityAtlas.tile("pole"))


## Chimneys and a rooftop box on the roof of one building (seen against the dome from the street).
static func add_roof(surface: CitySurface, building: Dictionary, salt: int) -> void:
	var rect: Rect2i = building["rect"]
	var height := float(building.get("height", 12.0))
	var brick := CityAtlas.tile("brick_dark")
	for index in 2:
		var cx := rect.position.x + 2 + ((salt >> (index * 3)) % maxi(1, rect.size.x - 5))
		var cz := rect.position.y + 2 + ((salt >> (index * 3 + 5)) % maxi(1, rect.size.y - 5))
		surface.box(Vector3(cx, height, cz), Vector3(.9, 2.2 + float((salt >> (index + 2)) % 3), .9), brick, CityAtlas.tile("stone_dark"))
		surface.box(Vector3(cx - .08, height + 2.2 + float((salt >> (index + 2)) % 3), cz - .08), Vector3(1.06, .16, 1.06), CityAtlas.tile("stone_dark"))
