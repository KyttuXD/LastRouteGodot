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

## Lighting balance, in one place: the flashlight is the main tool in most spaces. Ambient is a dim plum wash; lamps are
## fewer, softer and shorter; many rooms and long hall stretches are dark. Safe rooms/checkpoints ignore the lit-room
## scale and keep a stronger checkpoint light so they stay comfortably lit.
const AMBIENT_ENERGY := 0.8
const LAMP_ENERGY_SCALE := 0.7
const LAMP_RANGE_SCALE := 0.8
## Multiplies each district's own share of lit rooms (RefDecor.STYLE lit_rooms) outside safe rooms.
const LIT_ROOMS_SCALE := 0.55
## Percent of 14x14-cell corridor blocks that carry lamps at all.
const CORRIDOR_LIT_PERCENT := 40
## Emissive bulb/lamp meshes are dimmer than before so they do not read as light sources the pool is not lending light to.
const BULB_EMISSION_SCALE := 0.6
const SAFE_ROOM_LIGHT_ENERGY := 1.7
const SAFE_ROOM_LIGHT_RANGE := 11.0

## Single switch for every full-screen / screen-space effect (pixel grid, dither,
## vignette, grade, glow, heavy fog). OFF by default: the look comes from the
## world itself (textures, lamps, emissives). Turn on to compare.
const POST_EFFECTS := false


static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("070307")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5a3550")
	env.ambient_light_energy = AMBIENT_ENERGY
	# No reflections of the flat background colour: that is what put pale sheen over dark surfaces.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_light_color = Color("140812")
	env.fog_density = .03 if POST_EFFECTS else .006
	env.fog_sky_affect = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = POST_EFFECTS
	env.glow_intensity = .9
	env.glow_strength = 1.1
	env.glow_bloom = .12
	env.glow_hdr_threshold = .85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = POST_EFFECTS
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = .95
	return env


## Replaces the scene's flat environment and adds the pixel post-process.
## `host` is any node in the tree; `world_env` the scene's WorldEnvironment.
static func install(host: Node, world_env: WorldEnvironment) -> void:
	MaterialLook.install(host.get_tree())
	if world_env != null:
		world_env.environment = make_environment()
	if not POST_EFFECTS or host.has_node(POST_NAME):
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
#   hospital  sage vinyl, mint/white walls with a teal crash rail
#   lab       Kyttu's Lab: white epoxy and composite panels, cyan guide line, hazard feet
#   greenhouse terracotta quarry tiles, iron-and-glass glazing, glass roofs over the glasshouses

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
	"inferno": {"corridor": ["rock0", "rock1"], "room": ["rock0", "rock1"],
		"wall": ["rockwall0", "rockwall1", "rockwall0"], "ceiling": "rockceil", "runner": false},
	# the sewer under the maze: brick tunnels over worn stone walkways
	"sewer": {"corridor": ["stone0", "stone1"], "room": ["concrete0", "concrete1"],
		"wall": ["brick0", "brick1", "brick1"], "ceiling": "vault", "runner": false},
	"hospital": {"corridor": ["vinyl0", "vinyl1"], "room": ["vinyl0", "vinyl1"],
		"wall": ["hospital0", "hospital1"], "ceiling": "ceil0", "runner": false},
	"lab": {"corridor": ["epoxy0", "epoxy0", "epoxy1"], "room": ["epoxy0"],
		"wall": ["lab0", "lab0", "lab1"], "ceiling": "ceil0", "runner": false},
	"mall": {"corridor": ["terrazzo0", "terrazzo1"], "room": ["terrazzo0"],
		"wall": ["mall0", "mall1"], "ceiling": "ceil1", "runner": false},
	"greenhouse": {"corridor": ["terracotta0", "terracotta1", "stone2"], "room": ["terracotta0", "terracotta1"],
		"wall": ["glasshouse0", "glasshouse1"], "ceiling": "glass", "runner": false},
}

## The trim of archways and hall pilasters (caps, mouldings, keystones) per district: [texture group, kind, tint, metal].
## The jambs and arches themselves are the hall's own wall (RefDecor.arch_wall_material); this is only the accent. Gold
## only where the district uses it.
const ARCH_ACCENT := {
	"mansion": ["floor", "metal0", Color("c9a25a"), true], "hotel": ["floor", "metal0", Color("c9a25a"), true],
	"apartment": ["floor", "metal0", Color("b8955a"), true], "carnival": ["floor", "metal0", Color("d4a84a"), true],
	"maze": ["floor", "concrete0", Color("b0aaa0"), false], "office": ["floor", "concrete0", Color("b0aaa0"), false],
	"prison": ["floor", "metal1", Color("8a96a0"), true], "inferno": ["floor", "metal3", Color("9a6a50"), true],
	"lab": ["floor", "metal1", Color("c8d4dc"), true], "hospital": ["floor", "metal1", Color("e4e8ea"), true],
	"industrial": ["floor", "metal1", Color("6f8a96"), true],
	"gothic": ["floor", "stone1", Color("a8a29a"), false], "sewer": ["floor", "stone0", Color("9a948a"), false],
	"beach": ["floor", "stone2", Color("d8ccb0"), false], "mall": ["floor", "terrazzo0", Color("e0dcd4"), false],
	"greenhouse": ["floor", "metal2", Color("5f7a5a"), true],
}


static func arch_accent(region: String) -> Array:
	return ARCH_ACCENT.get(region, ARCH_ACCENT["maze"])


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
	"living_room": {"floor": ["floral1", "parquet0"], "wall": ["paper0", "office1"]},
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
	"operating_theatre": {"floor": ["check1", "vinyl0"], "wall": ["hospital0"]},
	"morgue": {"floor": ["metal2", "check1"], "wall": ["corridor0", "hospital0"]},
	"waiting_room": {"floor": ["vinyl1"], "wall": ["hospital1"]},
	"supply_closet": {"floor": ["metal2"], "wall": ["panel0", "hospital0"]},
	"containment": {"floor": ["epoxy1", "hazard"], "wall": ["lab1"]},
	"server_hall": {"floor": ["grate", "epoxy0"], "wall": ["lab0", "panel2"]},
	"decon": {"floor": ["grate", "epoxy1"], "wall": ["lab1"]},
	"cold_storage": {"floor": ["metal1", "epoxy0"], "wall": ["lab0"]},
	"lab_office": {"floor": ["floral1", "epoxy0"], "wall": ["office0", "lab0"]},
	"potting_shed": {"floor": ["parquet1", "terracotta1"], "wall": ["glasshouse0"]},
	"irrigation_room": {"floor": ["grate", "terracotta0"], "wall": ["glasshouse0", "panel2"]},
	"cactus_room": {"floor": ["stone2", "terracotta1"], "wall": ["glasshouse0"]},
	"overgrown_room": {"floor": ["stone2", "terracotta0"], "wall": ["glasshouse1", "hedge1"]},
}

## The wall kind of a face that looks into a space: the room purpose's paper if the space is a room interior, else the
## district wall. Patches of four cells so a wall changes paper in runs. Walls, door jambs, lintels and archways all call this.
static func wall_kind(region: String, room_type: String, gx: int, gz: int) -> String:
	var style: Dictionary = REGION_STYLE.get(region, REGION_STYLE["maze"])
	var kinds: Array = (ROOM_STYLE.get(room_type, {}) as Dictionary).get("wall", style["wall"]) if room_type != "" else style["wall"]
	return kinds[pick(gx / 4, gz / 4, 2, kinds.size())]


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


# -- heights -------------------------------------------------------------------
#
# The route is one level, so every room picks its own ceiling height from a
# range for its kind. The pick is a hash of the room id (corridors: of the chunk
# coordinate), so every co-op peer builds the same ceilings.

## Above this a room counts as "tall": pendants on chains, roof ribs, tiered walls.
const TALL_ROOM := 4.6
const CORRIDOR_RANGE := Vector2(4.0, 4.6)   # taller than wide so a hall does not read as a low box
## Low end raised so every door frame (raised for the 1.5x hunters, DoorwayFrames.FRAME_TOP_CAP) fits under it.
const ROOM_RANGE := Vector2(3.7, 4.4)
const HALL_RANGE := Vector2(4.8, 6.0)
const GREENHOUSE_RANGE := Vector2(6.4, 7.5)
const MAX_HEIGHT := 7.5
## Metres of wall one repeat of the painted wall texture covers.
const WALL_TEXTURE_SPAN := 4.0

const GREENHOUSE_ROOMS := ["cove", "tide_pool", "beach_hut", "boardwalk_room"]
## The greenhouse biome's glasshouses get the same vaulted glass roof and canopy as the beach conservatories;
## its potting sheds and plant rooms keep an ordinary ceiling.
const GLASSHOUSE_ROOMS := ["glasshouse", "palm_house", "cactus_room", "overgrown_room", "dome_atrium"]
const HALL_ROOMS := ["drawing_room", "dining_room", "lobby", "big_top", "chapel",
	"crypt", "archive", "storage", "forge", "thermal_chamber", "lava_gallery",
	"altar_room", "prison_cafeteria", "midway", "restaurant_dining",
	"ward", "operating_theatre", "server_hall", "containment", "clean_room"]


## True for rooms that read as a glass conservatory (tall glazed roof, canopy and greenery).
static func is_glasshouse(region: String, room_type: String) -> bool:
	return (region == "beach" and GREENHOUSE_ROOMS.has(room_type)) \
		or (region == "greenhouse" and GLASSHOUSE_ROOMS.has(room_type))


static func _ranged(key: String, bounds: Vector2) -> float:
	var unit := float(absi(hash(key)) % 10_000) / 10_000.0
	return snappedf(lerpf(bounds.x, bounds.y, unit), .1)


static func room_range(region: String, room_type: String) -> Vector2:
	if region == "sewer":
		# one fixed low vault so every ladder shaft has the same height
		return Vector2(SewerRouteGenerator.CEILING_HEIGHT, SewerRouteGenerator.CEILING_HEIGHT)
	if region == "gothic" and not HALL_ROOMS.has(room_type):
		# the gothic door frames' crest (DoorwayFrames.GOTHIC_FRAME_TOP_CAP) needs the headroom, on both sides of a door
		return Vector2(4.1, 4.6)
	if room_type == "":
		return ROOM_RANGE if region in ["beach", "greenhouse"] else CORRIDOR_RANGE
	if is_glasshouse(region, room_type):
		return GREENHOUSE_RANGE
	if HALL_ROOMS.has(room_type):
		return HALL_RANGE
	return ROOM_RANGE


## Ceiling height of one room (key = its id).
static func room_height(region: String, room_type: String, key: String) -> float:
	return _ranged("H:%s" % key, room_range(region, room_type))


## Corridor ceiling of a chunk (all its circulation space).
static func corridor_height(region: String, coord: Vector3i) -> float:
	return _ranged("C:%d:%d" % [coord.x, coord.z], room_range(region, ""))


## Cell -> ceiling height for every cell inside a room of this chunk.
static func chunk_heights(data: Dictionary) -> Dictionary:
	var region := String(data.get("region", "maze"))
	var heights := {}
	for room_value in data.get("rooms", []):
		var room: Dictionary = room_value
		var rect: Rect2i = room.get("rect", Rect2i())
		var h := room_height(region, String(room.get("room_type", "")), String(room.get("id", "")))
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				heights[Vector2i(x, z)] = h
	return heights


## Cell -> room id, for budgets that count fixtures per room.
static func chunk_room_ids(data: Dictionary) -> Dictionary:
	var ids := {}
	for room_value in data.get("rooms", []):
		var room: Dictionary = room_value
		var rect: Rect2i = room.get("rect", Rect2i())
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				ids[Vector2i(x, z)] = String(room.get("id", ""))
	return ids


## Number of wall-texture repeats a face of this height carries.
static func wall_tiers(height: float) -> int:
	return maxi(1, roundi(height / WALL_TEXTURE_SPAN))
