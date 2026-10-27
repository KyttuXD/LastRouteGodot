class_name CityAtlas
extends RefCounted

## The City's pixel texture atlas (art/city/city_atlas.png + city_emission.png): 8 x 8 tiles of 32 x 32 px, built by
## tools/city/make_city_atlas.py from the NAMES below (keep the order; the validator checks the sheet size).
## One tile is one metre of street, facade or prop.

const TILE_PX := 32
const COLUMNS := 8
const ROWS := 8
const SHEET_PX := 256
const ALBEDO_PATH := "res://art/city/city_atlas.png"
const EMISSION_PATH := "res://art/city/city_emission.png"
const RIM_PATH := "res://art/city/rim_wall.png"

const NAMES := ["cobble", "cobble_wet", "sidewalk", "plaza", "grass", "path", "water", "compass",
	"cross_ns", "cross_ew", "alley", "wood_floor", "kiosk_floor", "bridge", "flowers", "hedge",
	"brick_a", "brick_b", "brick_c", "win_dark_bot", "win_dark_top", "win_lit_bot", "win_lit_top", "win_cyan_bot",
	"win_cyan_top", "shop_bot", "shop_top", "stone_base", "cornice", "civic_a", "civic_arch_bot", "civic_arch_top",
	"ind_panel", "ind_port", "kiosk_wall", "kiosk_sign", "plaster", "ceiling", "rim_wall", "door",
	"pole", "lantern", "cyan_lamp", "trunk", "blossom", "cypress", "wood_bench", "planter",
	"statue_stone", "water_edge", "dome_strut", "stone_dark", "petals", "hedge_top", "bed_edge", "kiosk_roof"]

static var _index := {}


static func tile(name: String) -> int:
	if _index.is_empty():
		for i in NAMES.size():
			_index[NAMES[i]] = i
	return int(_index.get(name, 0))


## UV rectangle (u0, v0, u1, v1) of a tile, inset half a texel so nearest sampling never bleeds a neighbour.
static func uv_rect(tile_index: int) -> Rect2:
	var column := tile_index % COLUMNS
	var row := tile_index / COLUMNS
	var inset := 0.5 / float(SHEET_PX)
	var size := float(TILE_PX) / float(SHEET_PX)
	return Rect2(Vector2(column * size + inset, row * size + inset), Vector2(size - inset * 2.0, size - inset * 2.0))
