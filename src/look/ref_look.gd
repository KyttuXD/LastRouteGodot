class_name RefLook
extends RefCounted

## The "reference look": a dark, wet, pixel-art facility lit by amber lamps with
## teal terminals as the only cool accent (see docs in LastRoute-3D-refs/).
##
## This owns the global part of the look -- environment, post-process and the
## palette -- so the infinite route and the single-floor mode share it. Room
## dressing lives in RefTextures / RefDecor.

const PIXEL_SHADER := preload("res://src/look/ref_pixel.gdshader")

## Pixel grid height of the post-process. The width follows the window aspect.
const PIXEL_GRID_HEIGHT := 270.0

# -- palette -----------------------------------------------------------------
const BLACK := Color("0a0509")
const PLUM_DEEP := Color("1d0f1b")
const PLUM := Color("2e1729")
const MAROON := Color("4a1a24")
const MAROON_LIGHT := Color("6e2a30")
const BRASS := Color("9a6e26")
const BRASS_DARK := Color("5b3f1c")
const AMBER := Color("ffa63a")
const AMBER_SOFT := Color("f0a050")
const TEAL := Color("5cf0e0")
const TEAL_DEEP := Color("1c8a8c")
const METAL := Color("2a2627")
const METAL_LIGHT := Color("4a4244")
const STONE := Color("3a3532")
const WOOD := Color("3a2418")
const LEAF := Color("22301f")

const POST_NAME := "RefLookPost"


static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("070307")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5a3550")
	env.ambient_light_energy = 2.0
	env.fog_enabled = true
	env.fog_light_color = Color("140812")
	env.fog_density = .03
	env.fog_sky_affect = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = .9
	env.glow_strength = 1.1
	env.glow_bloom = .12
	env.glow_hdr_threshold = .85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = .95
	return env


## Replaces the scene's flat environment and adds the pixel post-process.
## `host` is any node in the tree; `world_env` the scene's WorldEnvironment.
static func install(host: Node, world_env: WorldEnvironment) -> void:
	if world_env != null:
		world_env.environment = make_environment()
	if host.has_node(POST_NAME):
		return
	var layer := CanvasLayer.new()
	layer.name = POST_NAME
	# Below the default canvas (HUD, menus), above the 3D render.
	layer.layer = -1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = PIXEL_SHADER
	rect.material = material
	layer.add_child(rect)
	host.add_child(layer)
	_update_grid(host, material)
	host.get_viewport().size_changed.connect(_update_grid.bind(host, material))


static func _update_grid(host: Node, material: ShaderMaterial) -> void:
	var size := host.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(1.0, size.y)
	material.set_shader_parameter("grid", Vector2(roundf(PIXEL_GRID_HEIGHT * aspect), PIXEL_GRID_HEIGHT))


# -- surface style tables ----------------------------------------------------
#
# Region = the multi-chunk biome the generator picked; room type = the finer
# label on each room rectangle. Floors/walls are chosen per cell from these.
# Kinds are RefTextures keys (floor/wall groups). The room families of the
# references map onto the generator's regions like this:
#   maze      industrial: control rooms, service corridors, offices, arcade
#   mansion   drawing room / grand hall / dining room, wainscoted corridors
#   hotel     lobby and wallpapered corridors with carpet runners
#   apartment two-tone wallpapered flats with parquet
#   beach     garden courtyard: wet flagstone, ivy, lantern pedestals
#   gothic    vaulted brick / stone arcades
#   carnival  prize room: star carpet, brass, checker
#   prison    service bays: riveted metal, hazard striping
#   inferno   warehouse/foundry: hazard plates and ember cracks

const REGION_STYLE := {
	"maze": {"corridor": ["metal0", "metal1", "metal2", "metal3", "grate"],
		"room": ["metal0", "metal1"], "wall": ["panel0", "panel1", "panel2"],
		"ceiling": "ceil0", "runner": false},
	"mansion": {"corridor": ["parquet0", "parquet1"], "room": ["parquet0", "parquet1"],
		"wall": ["paper0", "paper1"], "ceiling": "ceil1", "runner": true},
	"hotel": {"corridor": ["metal0", "metal1"], "room": ["floral0", "floral1"],
		"wall": ["paper1", "paper0"], "ceiling": "ceil1", "runner": true},
	"apartment": {"corridor": ["parquet0", "parquet1"], "room": ["parquet1", "floral1"],
		"wall": ["paper0", "office1"], "ceiling": "ceil1", "runner": true},
	"beach": {"corridor": ["stone0", "stone1", "stone2"], "room": ["stone0", "stone2"],
		"wall": ["hedge0", "hedge1", "stone0"], "ceiling": "glass", "runner": false},
	"gothic": {"corridor": ["stone0", "stone1"], "room": ["stone1", "stone0"],
		"wall": ["brick0", "brick1", "stone1"], "ceiling": "ceil1", "runner": true},
	"carnival": {"corridor": ["check0", "check1"], "room": ["star0", "star1"],
		"wall": ["paper1", "panel1"], "ceiling": "ceil1", "runner": false},
	"prison": {"corridor": ["metal1", "metal2", "grate"], "room": ["metal2", "metal3"],
		"wall": ["corridor0", "corridor1", "panel0"], "ceiling": "ceil0", "runner": false},
	"inferno": {"corridor": ["hazard", "metal3"], "room": ["metal3", "stone1"],
		"wall": ["inferno0", "brick1"], "ceiling": "ceil0", "runner": false},
}

## Room-type overrides: which floor and wall kinds a room gets regardless of
## the region default (offices are carpeted, restrooms are tiled...).
const ROOM_STYLE := {
	"office_reception": {"floor": ["floral0", "floral1"], "wall": ["office0", "office1"]},
	"cubicle_room": {"floor": ["floral1", "floral0"], "wall": ["office1", "office0"]},
	"office_job": {"floor": ["floral0"], "wall": ["office0", "office1"]},
	"private_office": {"floor": ["floral0", "floral1"], "wall": ["paper0", "office0"]},
	"office_suite": {"floor": ["floral0", "floral1"], "wall": ["office0"]},
	"arcade_room": {"floor": ["star0", "star1"], "wall": ["panel1", "paper1"]},
	"restaurant_dining": {"floor": ["check0", "parquet0"], "wall": ["paper0", "paper1"]},
	"public_restroom": {"floor": ["check0", "check1"], "wall": ["corridor0", "office0"]},
	"storage": {"floor": ["hazard", "metal3", "metal2"], "wall": ["panel2", "corridor1"]},
	"hotel_bathroom": {"floor": ["check0", "check1"], "wall": ["office0"]},
	"house_bathroom": {"floor": ["check1", "check0"], "wall": ["office0"]},
	"luxury_bathroom": {"floor": ["check0"], "wall": ["paper0"]},
	"kitchen": {"floor": ["check0", "check1"], "wall": ["office0", "corridor0"]},
	"drawing_room": {"floor": ["floral0", "floral1"], "wall": ["paper0", "paper1"]},
	"dining_room": {"floor": ["floral1", "floral0"], "wall": ["paper1", "paper0"]},
	"family_dining": {"floor": ["floral1", "parquet0"], "wall": ["paper0", "office1"]},
	"bedroom": {"floor": ["floral0", "parquet1"], "wall": ["paper0", "paper1"]},
	"guest_room": {"floor": ["floral0", "floral1"], "wall": ["paper1", "paper0"]},
	"stairwell": {"floor": ["floral0"], "wall": ["paper0"]},
	"prison_cafeteria": {"floor": ["check0", "metal2"], "wall": ["corridor0", "office0"]},
	"prison_cell": {"floor": ["metal2", "metal3"], "wall": ["corridor1", "panel0"]},
	"big_top": {"floor": ["star0", "star1"], "wall": ["paper1"]},
	"backstage": {"floor": ["metal3", "grate"], "wall": ["panel2", "panel0"]},
	"chapel": {"floor": ["stone1", "stone0"], "wall": ["stone0", "brick0"]},
	"crypt": {"floor": ["stone1"], "wall": ["brick1", "stone1"]},
	"cove": {"floor": ["stone2", "stone0"], "wall": ["hedge0", "hedge1"]},
	"tide_pool": {"floor": ["stone2"], "wall": ["hedge1", "stone0"]},
	"thermal_chamber": {"floor": ["hazard", "metal3"], "wall": ["inferno0", "panel2"]},
	"forge": {"floor": ["hazard", "metal3"], "wall": ["inferno0", "panel0"]},
}

## Deterministic 0..n-1 choice from a cell position and a salt, so every peer
## picks the same tile without sharing any state.
static func pick(cell_x: int, cell_z: int, salt: int, count: int) -> int:
	var h := (cell_x * 73856093) ^ (cell_z * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16)) % maxi(1, count)


static var _graded := {}

## Dims and warms an authored prop so Blockbench's bright palette sits in the
## dark world instead of glowing against it. Materials are graded once and
## shared; textures keep nearest filtering.
static func grade_prop(root: Node, strength: float = 1.0) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			for surface in mi.mesh.get_surface_count():
				var source := mi.get_active_material(surface)
				if source is StandardMaterial3D:
					mi.set_surface_override_material(surface,
						_graded_material(source as StandardMaterial3D, strength))
	for child in root.get_children():
		grade_prop(child, strength)


static func _graded_material(source: StandardMaterial3D, strength: float) -> StandardMaterial3D:
	if source.emission_enabled:
		return source
	var cache_key := [source, strength]
	if _graded.has(cache_key):
		return _graded[cache_key]
	var graded := source.duplicate() as StandardMaterial3D
	graded.albedo_color = source.albedo_color * Color(.58, .46, .46) * strength
	graded.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	graded.roughness = clampf(source.roughness, .55, 1.0)
	_graded[cache_key] = graded
	return graded
