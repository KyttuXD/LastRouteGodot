class_name FacilityView3D
extends Node3D

## Renders the facility_generator.gd grid data (unchanged, engine-agnostic) via
## a GridMap with
## physics collision. Floor/wall visuals and collision come from
## art/props-3d/environment/ via ModelSlot, not hardcoded geometry — see
## art/props-3d/README.md for the scale/pivot convention this mirrors:
## 1 grid cell = 1 meter, ground plane is XZ (Godot is Y-up).

const CELL_SIZE := 1.0
const LADDER_SCRIPT := preload("res://src/game_3d/climbable_ladder_3d.gd")
## Dedicated single-purpose block textures (Minecraft/Hytale block-format
## style: one small texture per block, no shared atlas to crop), cropped
## once from the wider environment kit sheet by
## tools/environment/bake_block_textures.gd -- see _build_mesh_library()'s
## own note on why this replaced the previous runtime-heuristic approach.
const FLOOR_TEXTURE := "res://art/props-3d/environment/floor_texture.png"
const WALL_TEXTURE := "res://art/props-3d/environment/wall_texture.png"

## Corridor height, and the thickness of the slabs that cap it. 3 m matches the
## office rooms, so a player moving between modes reads the same scale.
const WALL_HEIGHT := 3.0
const SLAB := 0.1

const ITEM_FLOOR := 0
const ITEM_WALL := 1
const ITEM_CEILING := 2

## One-metre mezzanine reached over a shallow 3.6 m run. The visible GLB has
## discrete steps; physics uses one continuous ramp so neither keyboard nor XR
## players need to bunny-hop risers. Hunters read the same profile below.
const STAIR_WIDTH := 1.60
const STAIR_RUN := 3.60
const STAIR_RISE := 1.0
const STAIR_RAMP_CENTER_Z := 0.0
const STAIR_LANDING_DEPTH := 1.40
const STAIR_LANDING_CENTER_Z := STAIR_RUN * .5 + STAIR_LANDING_DEPTH * .5
const STAIR_COLLISION_THICKNESS := .10

## Symmetrical mansion foyer: two shallow diagonal flights converge on one
## broad raised gallery. Visible treads/rails are authored in the GLB; these
## dimensions are the smooth walkable surfaces used by players and hunters.
const FOYER_STAIR_WIDTH := 1.25
const FOYER_STAIR_RISE := 1.20
const FOYER_LEFT_START := Vector2(-1.65, -2.0)
const FOYER_LEFT_END := Vector2(-0.65, 2.0)
const FOYER_RIGHT_START := Vector2(1.65, -2.0)
const FOYER_RIGHT_END := Vector2(0.65, 2.0)
const FOYER_GALLERY_WIDTH := 4.50
const FOYER_GALLERY_DEPTH := 1.40
const FOYER_GALLERY_CENTER_Z := 2.70

## Per-region floor tints, keyed by the same region names CustomMapParser's
## paint palette uses. Real, bespoke floor art per theme (a mansion's own
## herringbone, a beach's own sand) is a much bigger asset pass than this
## session has scope for -- Blockbench isn't connected to author or verify
## one -- so this is a first pass that at least makes a painted region READ
## as a distinct place while a real texture is still future work: the same
## floor material, tinted. `albedo_color` multiplies the existing texture
## rather than replacing it, so the tile pattern underneath still shows
## through, just recoloured.
##
## "frozen tideline" reads as one region here, not two: it is a beach with
## the tide iced over, not a separate room type, so it gets beach's own
## entry rather than inventing a parallel one nothing places yet.
const REGION_FLOOR_TINTS := {
	"mansion": Color(0.55, 0.42, 0.30),
	"bedroom": Color(0.58, 0.43, 0.58),
	"beach": Color(0.68, 0.82, 0.90),
	"office": Color(0.55, 0.62, 0.72),
	"maintenance": Color(0.80, 0.62, 0.35),
	"arcade": Color(0.85, 0.55, 0.85),
	"circus": Color(0.95, 0.55, 0.65),
	"nether": Color(0.70, 0.30, 0.30),
	"garden": Color(0.55, 0.80, 0.55),
}
## region name -> GridMap item id, filled in by _build_mesh_library().
var _region_floor_items := {}
var _region_wall_items := {}
const REGION_FLOOR_REPEAT := {
	"mansion": Vector3(2.0, 2.0, 2.0), "bedroom": Vector3(2.0, 2.0, 2.0),
	"beach": Vector3(1.0, 1.0, 1.0), "office": Vector3(1.0, 1.0, 1.0),
	"maintenance": Vector3(1.5, 1.5, 1.5), "arcade": Vector3(2.0, 2.0, 2.0),
	"circus": Vector3(2.0, 2.0, 2.0), "nether": Vector3(1.0, 1.0, 1.0),
	"garden": Vector3(1.5, 1.5, 1.5),
}
const REGION_WALL_TINTS := {
	"mansion": Color("4c342d"), "bedroom": Color("493747"),
	"beach": Color("61747b"), "office": Color("394958"),
	"maintenance": Color("5a4930"), "arcade": Color("523956"),
	"circus": Color("633b46"), "nether": Color("4f2626"),
	"garden": Color("354b37"),
}

var generator: FacilityGenerator

var _grid_map: GridMap
## The ceiling is its OWN GridMap so it can be hidden wholesale. A GridMap has
## no per-item visibility, and the top-down view has to see through it -- that
## view is the original game's primary perspective, not a debug camera.
var _ceiling_map: GridMap
var _interactables: Array = []
var _room_prop_nodes: Array = []
var _stair_nodes: Array[Node3D] = []
var _room_lights := {}
var _fixture_lights: Array[OmniLight3D] = []
## The floor's single heater station, read by Wynelle's gimmick each frame.
var heater_station: RouteInteractable3D
## Glyra's counterplay, read by GlyraGimmick each frame the same way Wynelle's
## gimmick reads heater_station.
var music_box: RouteInteractable3D
var _ceiling_decor: CeilingDecor


func _ready() -> void:
	_grid_map = GridMap.new()
	_grid_map.cell_size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	# X/Z stay centred so cell (x,z) is at (x+.5,z+.5). Y is floor-based:
	# authored mesh offsets already measure upward from y=0. Leaving Godot's
	# default Y centring on shifts the entire floor/walls/ceiling up 0.5 m and
	# embeds a correctly floor-pivoted player in the slab.
	_grid_map.cell_center_y = false
	var library := _build_mesh_library()
	_grid_map.mesh_library = library
	add_child(_grid_map)
	_ceiling_map = GridMap.new()
	_ceiling_map.cell_size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	_ceiling_map.cell_center_y = false
	_ceiling_map.mesh_library = library
	add_child(_ceiling_map)


func generate_floor(seed_text: String) -> void:
	# Sized by the room, not by the renderer -- see
	# RoomState.generator_options().
	generator = FacilityGenerator.new(seed_text, RoomState.generator_options())
	_paint_grid()
	_spawn_room_props()
	_spawn_interactables()
	_hang_ceiling_lights(seed_text)


## Same as generate_floor(), from a hand-painted PNG instead of procedural
## carving. Returns "" on success or an error to show the admin who asked for
## this floor, matching CustomMapParser.parse()'s own {"ok", "error"} shape.
func generate_floor_from_custom_map(image: Image, seed_text: String) -> String:
	var parsed := CustomMapParser.parse(image)
	if not parsed.get("ok", false):
		return String(parsed.get("error", "custom map failed to parse"))
	generator = FacilityGenerator.new(seed_text, RoomState.generator_options(), parsed)
	_paint_grid()
	_spawn_room_props()
	_spawn_interactables()
	_hang_ceiling_lights(seed_text)
	for warning in parsed.get("warnings", []):
		push_warning("custom map: %s" % warning)
	return ""


## World-space size of the facility footprint on the XZ ground plane.
func facility_extent() -> Vector3:
	return Vector3(generator.cols, 0.0, generator.rows) * CELL_SIZE


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)


func start_world_position() -> Vector3:
	return cell_to_world(generator.start)


func _paint_grid() -> void:
	_grid_map.clear()
	_ceiling_map.clear()
	# Procedural rooms carry no "region" -- only a custom map's flood-filled
	# ones do (see CustomMapParser) -- so this is a no-op lookup, always
	# falling through to the ordinary floor, for every floor that isn't one.
	var has_regions := not _region_floor_items.is_empty() and generator.rooms.any(
		func(r): return not String(r.get("region", "")).is_empty())
	for y in generator.rows:
		for x in generator.cols:
			var open: bool = generator.grid[y][x] == 0
			var floor_item := ITEM_FLOOR
			var wall_item := ITEM_WALL
			if open and has_regions:
				var room := generator.room_at(x + 0.5, y + 0.5)
				var region := String(room.get("region", ""))
				if _region_floor_items.has(region):
					floor_item = _region_floor_items[region]
			elif not open and has_regions:
				var wall_region := _region_next_to_wall(x, y)
				if _region_wall_items.has(wall_region):
					wall_item = _region_wall_items[wall_region]
			_grid_map.set_cell_item(Vector3i(x, 0, y),
				floor_item if open else wall_item)
			# The maze had no lid at all, so corridors opened onto the void and
			# lost every bounce of light. Only open cells need one -- a wall
			# already fills its cell to the ceiling. A GridMap cell holds one
			# item, so the lid lives a layer up.
			if open:
				_ceiling_map.set_cell_item(Vector3i(x, 1, y), ITEM_CEILING)


func _region_next_to_wall(x: int, y: int) -> String:
	for step_value in FacilityGenerator.DIRECTIONS4:
		var step: Vector2i = step_value
		var cell: Vector2i = Vector2i(x, y) + step
		if cell.x < 0 or cell.y < 0 or cell.x >= generator.cols or cell.y >= generator.rows:
			continue
		if generator.grid[cell.y][cell.x] != 0:
			continue
		var room := generator.room_at(cell.x + .5, cell.y + .5)
		var region := String(room.get("region", ""))
		if not region.is_empty():
			return region
	return ""


## Lift the lid for the top-down view.
##
## Looking down from 12 m at a sealed corridor shows a ceiling, which is why
## switching to that view went completely black. Hiding it is not a hack around
## the ceiling -- a plan view of a building never draws the floor above the one
## you are reading.
func set_ceiling_visible(shown: bool) -> void:
	if _ceiling_map != null:
		_ceiling_map.visible = shown


func _spawn_interactables() -> void:
	for node in _interactables:
		node.queue_free()
	_interactables.clear()
	for light_data in _room_lights.values():
		var old_light := light_data.get("light") as OmniLight3D
		if old_light:
			old_light.queue_free()
	_room_lights.clear()

	var cache_count := clampi(roundi(generator.relays.size() *
		GameConfig.LOCKED_RELAY_CACHE_RATIO), 1, maxi(1, generator.relays.size() - 1))
	for relay_index in generator.relays.size():
		var relay: Dictionary = generator.relays[relay_index]
		var relay_node := _spawn_interactable(RouteInteractable3D.Kind.RELAY,
			Vector2i(relay["x"], relay["y"]), "RECOVER SIGNAL RELAY")
		# Keep the earliest relay entries ordinary: hunter fixtures and legacy
		# saved routes use the first relay as their stable reference point.
		if relay_index >= generator.relays.size() - cache_count:
			var style := "barrel" if abs((generator.seed_text + str(relay_index)).hash()) % 2 == 0 \
				else "crate"
			relay_node.configure_locked_cache(style)
	for battery in generator.batteries:
		_spawn_interactable(RouteInteractable3D.Kind.BATTERY, Vector2i(battery["x"], battery["y"]), "COLLECT BATTERY")
	for zone in generator.safe_zones:
		_spawn_interactable(RouteInteractable3D.Kind.SAFE_ZONE, Vector2i(zone["x"], zone["y"]), "REST AT SAFE ZONE")
	_spawn_interactable(RouteInteractable3D.Kind.LIFT, generator.exit_cell, "USE SERVICE LIFT")
	for spot in generator.place_hiding_spots():
		_spawn_interactable(RouteInteractable3D.Kind.HIDING_SPOT,
			Vector2i(spot["x"], spot["y"]), "HIDE")
	# One heater station per floor — Wynelle's counterplay. NEAR the start so
	# it's findable without hunting for it, matching the original's "single
	# station, known location" role, but not ON it: placed on the spawn cell
	# it was the first thing the player saw, at arm's length, blocking the way
	# out of their own spawn.
	heater_station = _spawn_interactable(RouteInteractable3D.Kind.HEATER_STATION,
		_near_start(), "USE HEATER STATION")
	# Glyra's music box: in the spawn room specifically, and Glyra herself
	# never leaves that room either -- she is stationary infrastructure, not
	# a hunter who has to be found.
	music_box = _spawn_interactable(RouteInteractable3D.Kind.MUSIC_BOX,
		_near_start(MUSIC_BOX_MIN_DISTANCE, MUSIC_BOX_MAX_DISTANCE), "WIND MUSIC BOX")
	# Verrine's vent network: one grate per generator.vents entry, at the exact
	# positions VerrineGimmick itself reads -- see FacilityGenerator.place_vents.
	for vent in generator.place_vents(GameConfig.VERRINE_VENT_COUNT):
		var node := _spawn_interactable(RouteInteractable3D.Kind.VENT,
			Vector2i(vent["x"], vent["y"]), "ENTER VENT")
		node.vent_id = String(vent["id"])
		if String(vent.get("mount", "floor")) == "wall":
			var wall_direction: Vector2i = vent.get("wall_dir", Vector2i(0, -1))
			# The authored grate lies on XZ. Tip it upright, move it close to the
			# selected wall, and keep its bottom at knee height rather than the
			# old centre-of-room floor position.
			node.position += Vector3(wall_direction.x * .43, .42,
				wall_direction.y * .43)
			node.rotation = Vector3(PI * .5,
				atan2(float(wall_direction.x), float(wall_direction.y)), 0.0)
			node.set_meta("vent_mount", "low_wall")
		else:
			node.set_meta("vent_mount", "floor")
	# Zellia's economy. Placed last so it reads generator.vents (already
	# built above) and avoids landing on a vent grate, the same collision
	# avoidance relays/batteries/safe_zones/hiding_spots already get.
	for coin in generator.place_coins(GameConfig.COIN_PICKUP_COUNT):
		_spawn_interactable(RouteInteractable3D.Kind.COIN,
			Vector2i(coin["x"], coin["y"]), "COLLECT COINS")
	_spawn_tool_pickups()
	_spawn_room_lights()
	# Boarded room thresholds come last so their cells can be checked against
	# every pickup and fixture placed above. A rejected candidate simply leaves
	# that room open; route-critical objectives are never overlapped.
	var taken := _taken_cells()
	var boarded_spawned := 0
	for barrier in generator.place_boarded_paths(GameConfig.BOARDED_PATH_COUNT * 3):
		var cell := Vector2i(barrier["x"], barrier["y"])
		if taken.has(cell):
			continue
		var node := _spawn_interactable(RouteInteractable3D.Kind.BOARDED_PATH,
			cell, "BREACH BOARDED PATH")
		var direction: Vector2i = barrier.get("dir", Vector2i(0, -1))
		node.rotation.y = PI * .5 if direction.x != 0 else 0.0
		node.set_meta("boarded_room", String(barrier.get("room_type", "")))
		boarded_spawned += 1
		if boarded_spawned >= GameConfig.BOARDED_PATH_COUNT:
			break
	# The hallway variant spans the full 3x3 corridor rather than reading as a
	# one-metre door floating in the middle of a broad passage.
	for barrier in generator.place_boarded_hallways(1):
		var cell := Vector2i(int(barrier["x"]), int(barrier["y"]))
		if _taken_cells().has(cell):
			continue
		var node := _spawn_interactable(RouteInteractable3D.Kind.BOARDED_PATH,
			cell, "BREACH HALLWAY BARRICADE")
		node.configure_boarded_variant("hallway")
		if String(barrier.get("orientation", "vertical")) == "horizontal":
			node.rotation.y = PI * .5
		node.set_meta("boarded_hallway", true)


## One authored pickup for every inventory slot, distributed deterministically
## across reachable floor cells. A room therefore starts with empty hands but
## every tool exists somewhere on the route. Equipment pickups are personal:
## one runner cannot remove the only flashlight from every other runner's map.
func _spawn_tool_pickups() -> void:
	var available: Array = generator.floor_cells()
	var taken := _taken_cells()
	for index in range(available.size() - 1, -1, -1):
		var cell: Vector2i = available[index]
		if taken.has(cell) or cell.distance_to(generator.start) < 3.0 \
				or not generator.can_occupy(cell.x + .5, cell.y + .5):
			available.remove_at(index)
	var rng := SeededRandom.new("%s:EQUIPMENT-PICKUPS" % generator.seed_text)
	for item_id in PlayerController3D.COLLECTIBLE_ITEMS:
		if available.is_empty():
			push_error("NO FREE CELL FOR EQUIPMENT PICKUP // %s" % item_id)
			break
		var chosen_index := rng.next_index(available.size())
		var cell: Vector2i = available[chosen_index]
		available.remove_at(chosen_index)
		var pickup := _spawn_interactable(RouteInteractable3D.Kind.TOOL_PICKUP,
			cell, "COLLECT EQUIPMENT")
		pickup.configure_tool_pickup(item_id)


func _spawn_room_lights() -> void:
	var candidates: Array = []
	for room in generator.rooms:
		if String(room.get("id", "")) != "room-lobby" \
				and int(room.get("width", 0)) >= 5 and int(room.get("height", 0)) >= 5:
			candidates.append(room)
	var rng := SeededRandom.new("%s:TOGGLEABLE-ROOM-LIGHTS" % generator.seed_text)
	var count := mini(3, candidates.size())
	for index in count:
		var chosen := rng.next_index(candidates.size())
		var room: Dictionary = candidates[chosen]
		candidates.remove_at(chosen)
		var id := "room-light-%s" % String(room.get("id", index))
		var center: Vector2i = room.get("center", Vector2i(
			int(room["x"]) + int(room["width"]) / 2,
			int(room["y"]) + int(room["height"]) / 2))
		var light := OmniLight3D.new()
		light.name = id.to_pascal_case()
		light.position = cell_to_world(center) + Vector3(0, WALL_HEIGHT - .34, 0)
		light.light_color = _room_light_color(String(room.get("region", "")))
		light.light_energy = 1.25
		light.omni_range = clampf(mini(int(room["width"]), int(room["height"])) * .55,
			3.5, 6.0)
		add_child(light)
		var switch_cell := Vector2i(int(room["x"]) + 1, int(room["y"]) + 1)
		if _taken_cells().has(switch_cell):
			switch_cell = center
		var switch := _spawn_interactable(RouteInteractable3D.Kind.LIGHT_SWITCH,
			switch_cell, "TOGGLE ROOM LIGHT")
		switch.position += Vector3(0, .9, -.34)
		switch.configure_room_light(id, true, _set_room_light.bind(id))
		_room_lights[id] = {"light": light, "switch": switch, "enabled": true}


func _room_light_color(region: String) -> Color:
	match region:
		"maintenance": return Color("f0a65a")
		"arcade", "circus": return Color("ba83e8")
		"garden": return Color("88d39a")
		"nether": return Color("e16a52")
		_: return Color("d9e3d4")


func _set_room_light(enabled: bool, id: String) -> String:
	var data: Dictionary = _room_lights.get(id, {})
	var light := data.get("light") as OmniLight3D
	if light:
		light.visible = enabled
	data["enabled"] = enabled
	if not data.is_empty():
		_room_lights[id] = data
	return "ROOM LIGHT %s" % ("ON" if enabled else "OFF")


func set_all_room_lights(enabled: bool) -> void:
	for id in _room_lights:
		var data: Dictionary = _room_lights[id]
		var switch := data.get("switch") as RouteInteractable3D
		if switch:
			switch.adopt({"what": "room_light", "light_id": id, "enabled": enabled})
	for light in _fixture_lights:
		if is_instance_valid(light):
			light.visible = enabled


## Mechanical themed-room dressing. Placement, facing and collision remain
## deterministic generator data; PropModelCatalog supplies authored GLB
## presentation without letting visual variants affect co-op simulation.
## Older room types without finished art retain the readable coloured-box
## fallback instead of silently disappearing.
func _spawn_room_props() -> void:
	for node in _room_prop_nodes:
		node.queue_free()
	_room_prop_nodes.clear()
	_fixture_lights.clear()
	_stair_nodes.clear()
	var fixture_light_budget := 10
	for entry in generator.props:
		var type := String(entry.get("type", "prop"))
		var solid := RoomCatalog.is_solid(type)
		var walkable_structure := RoomCatalog.is_walkable_structure(type)
		var root: Node3D = StaticBody3D.new() if solid or walkable_structure \
			else Node3D.new()
		root.name = "RoomProp_%s" % String(entry.get("id", type)).validate_node_name()
		root.set_meta("prop_type", type)
		root.set_meta("room_id", String(entry.get("room_id", "")))
		var base_footprint := RoomCatalog.footprint(type, 0)
		var height := RoomCatalog.display_height(type)
		root.position = cell_to_world(Vector2i(int(entry["x"]), int(entry["y"])))
		root.rotation.y = int(entry.get("rotation", 0)) * PI * .5

		var prop_id := String(entry.get("id", type))
		var model_path := PropModelCatalog.model_path(type, prop_id,
			String(entry.get("room_id", "")))
		var visual: Node3D = ModelSlot.instantiate_prop(model_path) \
			if not model_path.is_empty() else null
		var mount_y := float(entry.get("mount_y", 0.0))
		if visual != null:
			visual.name = "Visual"
			visual.position.y = PropModelCatalog.visual_y(type, WALL_HEIGHT, mount_y)
			ModelSlot.apply_prop_pixel_filter(visual)
			if PropModelCatalog.is_floor_dressing(type):
				ModelSlot.keep_floor_dressing_visible(visual)
			root.set_meta("prop_model_path", model_path)
			root.add_child(visual)
			var light_profile := PropModelCatalog.light_profile(type)
			if not light_profile.is_empty() and fixture_light_budget > 0:
				var fixture_light := OmniLight3D.new()
				fixture_light.name = "FixtureLight"
				fixture_light.position.y = PropModelCatalog.visual_y(
					type, WALL_HEIGHT, mount_y) + float(
					light_profile.get("height", .5))
				fixture_light.light_color = light_profile.get("color", Color.WHITE)
				fixture_light.light_energy = float(light_profile.get("energy", .4))
				fixture_light.omni_range = float(light_profile.get("range", 3.5))
				fixture_light.shadow_enabled = false
				root.add_child(fixture_light)
				_fixture_lights.append(fixture_light)
				fixture_light_budget -= 1
		else:
			root.set_meta("prop_model_path", "")
			root.add_child(_fallback_prop_visual(type, entry, base_footprint,
				height, mount_y))

		var furniture_action := PropModelCatalog.interaction_for(type)
		if not furniture_action.is_empty():
			var furniture := RouteInteractable3D.new()
			furniture.name = "FurnitureInteraction"
			furniture.kind = RouteInteractable3D.Kind.FURNITURE
			furniture.configure_furniture(furniture_action)
			furniture.position.y = .48 if furniture_action == "lay" else .03
			root.add_child(furniture)

		if walkable_structure:
			_add_stair_collision(root as StaticBody3D, type)
			_add_structure_ladder(root, type)
			_stair_nodes.append(root)
		elif solid:
			var shape := CollisionShape3D.new()
			shape.name = "Collision"
			var collision := BoxShape3D.new()
			collision.size = Vector3(base_footprint.x * 2.0, height,
				base_footprint.y * 2.0)
			shape.shape = collision
			shape.position.y = height * .5
			root.add_child(shape)
		add_child(root)
		_room_prop_nodes.append(root)


func _add_structure_ladder(root: Node3D, prop_type: String) -> void:
	var ladder: Node3D = LADDER_SCRIPT.new()
	ladder.name = "ServiceLadder"
	if prop_type == "grandFoyerStaircase":
		ladder.position = Vector3(0.0, 0.0, FOYER_GALLERY_CENTER_Z - .68)
		ladder.climb_height = FOYER_STAIR_RISE + .08
	else:
		ladder.position = Vector3(STAIR_WIDTH * .5 - .22, 0.0,
			STAIR_RAMP_CENTER_Z + STAIR_RUN * .5 + .22)
		ladder.climb_height = STAIR_RISE + .08
	root.add_child(ladder)


func _add_stair_collision(root: StaticBody3D,
		prop_type: String = "grandStaircase") -> void:
	if prop_type == "grandFoyerStaircase":
		_add_foyer_stair_collision(root)
		return
	var angle := atan(STAIR_RISE / STAIR_RUN)
	var ramp := CollisionShape3D.new()
	ramp.name = "WalkableRamp"
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(STAIR_WIDTH, STAIR_COLLISION_THICKNESS,
		sqrt(STAIR_RUN * STAIR_RUN + STAIR_RISE * STAIR_RISE))
	ramp.shape = ramp_shape
	ramp.rotation.x = -angle
	ramp.position = Vector3(0.0,
		STAIR_RISE * .5 - cos(angle) * STAIR_COLLISION_THICKNESS * .5,
		STAIR_RAMP_CENTER_Z)
	root.add_child(ramp)

	var landing := CollisionShape3D.new()
	landing.name = "RaisedLanding"
	var landing_shape := BoxShape3D.new()
	landing_shape.size = Vector3(STAIR_WIDTH, STAIR_COLLISION_THICKNESS,
		STAIR_LANDING_DEPTH)
	landing.shape = landing_shape
	landing.position = Vector3(0.0,
		STAIR_RISE - STAIR_COLLISION_THICKNESS * .5,
		STAIR_LANDING_CENTER_Z)
	root.add_child(landing)


func _add_foyer_stair_collision(root: StaticBody3D) -> void:
	_add_diagonal_ramp(root, "WalkableRampLeft", FOYER_LEFT_START,
		FOYER_LEFT_END, FOYER_STAIR_WIDTH, FOYER_STAIR_RISE)
	_add_diagonal_ramp(root, "WalkableRampRight", FOYER_RIGHT_START,
		FOYER_RIGHT_END, FOYER_STAIR_WIDTH, FOYER_STAIR_RISE)
	var gallery := CollisionShape3D.new()
	gallery.name = "RaisedGallery"
	var gallery_shape := BoxShape3D.new()
	gallery_shape.size = Vector3(FOYER_GALLERY_WIDTH, STAIR_COLLISION_THICKNESS,
		FOYER_GALLERY_DEPTH)
	gallery.shape = gallery_shape
	gallery.position = Vector3(0.0,
		FOYER_STAIR_RISE - STAIR_COLLISION_THICKNESS * .5,
		FOYER_GALLERY_CENTER_Z)
	root.add_child(gallery)


func _add_diagonal_ramp(root: StaticBody3D, shape_name: String,
		start: Vector2, end: Vector2, width: float, rise: float) -> void:
	var direction := end - start
	var run := direction.length()
	var angle := atan(rise / run)
	var ramp := CollisionShape3D.new()
	ramp.name = shape_name
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(width, STAIR_COLLISION_THICKNESS,
		sqrt(run * run + rise * rise))
	ramp.shape = ramp_shape
	ramp.rotation = Vector3(-angle, atan2(direction.x, direction.y), 0.0)
	var center := (start + end) * .5
	ramp.position = Vector3(center.x,
		rise * .5 - cos(angle) * STAIR_COLLISION_THICKNESS * .5, center.y)
	root.add_child(ramp)


## Height used by collision-free hunter presentation. The authoritative brain
## remains deterministic X/Z grid simulation, while its model follows the same
## ramp/landing the physical player walks on.
func surface_height_at(world_xz: Vector2) -> float:
	for stair in _stair_nodes:
		if not is_instance_valid(stair):
			continue
		var local := stair.to_local(Vector3(world_xz.x, 0.0, world_xz.y))
		if String(stair.get_meta("prop_type", "")) == "grandFoyerStaircase":
			var foyer_height := _foyer_surface_height(Vector2(local.x, local.z))
			if foyer_height >= 0.0:
				return foyer_height
			continue
		if absf(local.x) > STAIR_WIDTH * .5:
			continue
		var ramp_start := STAIR_RAMP_CENTER_Z - STAIR_RUN * .5
		var ramp_end := STAIR_RAMP_CENTER_Z + STAIR_RUN * .5
		if local.z >= ramp_start and local.z <= ramp_end:
			return (local.z - ramp_start) / STAIR_RUN * STAIR_RISE
		if local.z > ramp_end \
				and local.z <= ramp_end + STAIR_LANDING_DEPTH:
			return STAIR_RISE
	return 0.0


func _foyer_surface_height(local_xz: Vector2) -> float:
	for branch in [[FOYER_LEFT_START, FOYER_LEFT_END],
			[FOYER_RIGHT_START, FOYER_RIGHT_END]]:
		var start: Vector2 = branch[0]
		var direction: Vector2 = (branch[1] as Vector2) - start
		var run := direction.length()
		var forward := direction / run
		var offset := local_xz - start
		var along := offset.dot(forward)
		var side := absf(offset.dot(Vector2(-forward.y, forward.x)))
		if along >= 0.0 and along <= run and side <= FOYER_STAIR_WIDTH * .5:
			return along / run * FOYER_STAIR_RISE
	if absf(local_xz.x) <= FOYER_GALLERY_WIDTH * .5 \
			and absf(local_xz.y - FOYER_GALLERY_CENTER_Z) \
			<= FOYER_GALLERY_DEPTH * .5:
		return FOYER_STAIR_RISE
	return -1.0


func _fallback_prop_visual(type: String, entry: Dictionary,
		base_footprint: Vector2, height: float, mount_y: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	var box := BoxMesh.new()
	box.size = Vector3(base_footprint.x * 2.0, height,
		base_footprint.y * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = RoomCatalog.color_for_region(
		String(entry.get("region", "")))
	material.roughness = .78
	MaterialLook.tame(material)
	box.material = material
	mesh.mesh = box
	mesh.position.y = PropModelCatalog.visual_y(type, WALL_HEIGHT, mount_y) \
		+ height * .5
	return mesh


## An open cell within reach of the spawn, but not touching it: the spawn's
## safe zone sits ON the start cell, and a heater one step away from that put
## its interaction prompt fighting the safe zone's the moment the player
## turned around -- two "[E]" prompts within arm's reach of each other and no
## room to pick one without the other stealing focus. A short walk apart is
## still "findable without hunting for it" (the design goal in the comment
## this replaces) without the two treading on each other.
const HEATER_MIN_DISTANCE := 3
const HEATER_MAX_DISTANCE := 7
## Glyra's music box: the original keeps it in the spawn room specifically
## ("spawn-room music-box timer"), so its band sits inside the lobby rather
## than the walk-a-bit-further band the heater uses.
const MUSIC_BOX_MIN_DISTANCE := 1
const MUSIC_BOX_MAX_DISTANCE := 4

## Every already-placed interactable's cell, gathered fresh each call so two
## calls in the same floor build (heater, then the music box) cannot land on
## the same cell -- generator.relays/batteries/etc alone would not catch that,
## since neither knows about the OTHER call's pick.
func _taken_cells() -> Dictionary:
	var taken := {}
	for spawn_cell in generator.spawn_points:
		taken[spawn_cell] = true
	for relay in generator.relays:
		taken[Vector2i(relay["x"], relay["y"])] = true
	for battery in generator.batteries:
		taken[Vector2i(battery["x"], battery["y"])] = true
	for zone in generator.safe_zones:
		taken[Vector2i(zone["x"], zone["y"])] = true
	for prop in generator.props:
		if RoomCatalog.is_solid(String(prop.get("type", ""))):
			taken[Vector2i(prop["x"], prop["y"])] = true
	for spot in generator.hiding_spots:
		taken[Vector2i(spot["x"], spot["y"])] = true
	taken[generator.exit_cell] = true
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item:
			taken[item.source_cell] = true
	return taken


func _near_start(min_distance: int = HEATER_MIN_DISTANCE, max_distance: int = HEATER_MAX_DISTANCE) -> Vector2i:
	var taken := _taken_cells()

	# BFS out from the start along actual walkable cells, not straight-line
	# distance -- a cell three tiles away as the crow flies can be on the far
	# side of a wall and a much longer walk, which would defeat the point.
	var visited := {generator.start: true}
	var distance_of := {generator.start: 0}
	var queue: Array = [generator.start]
	var by_distance: Array = []  # [[cell, distance], ...] in BFS (walking) order
	var qi := 0
	while qi < queue.size():
		var cell: Vector2i = queue[qi]
		qi += 1
		var distance: int = distance_of[cell]
		for step in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= generator.cols or next.y >= generator.rows:
				continue
			if not generator.can_occupy(next.x + .5, next.y + .5) or visited.has(next):
				continue
			visited[next] = true
			distance_of[next] = distance + 1
			queue.append(next)
			by_distance.append([next, distance + 1])

	for entry in by_distance:
		var cell: Vector2i = entry[0]
		var distance: int = entry[1]
		if distance < min_distance or distance > max_distance:
			continue
		if taken.has(cell):
			continue
		return cell
	# A facility too small for the preferred band: take the first open cell at
	# or past the minimum distance, whatever it is, rather than fail outright.
	for entry in by_distance:
		if int(entry[1]) >= min_distance and not taken.has(entry[0]):
			return entry[0]
	return generator.start


## Fairy-light strands hung across the ceiling: sparse, and spread out rather
## than clustered, so they read as scattered decoration and not as a landing
## strip. An absolute cap, not a fraction of the floor -- a fixed fraction of
## open cells scales with facility AREA, and the largest scale has thousands
## of them; that turned "a few strands here and there" into well over a
## hundred, spending most of a frame building small meshes and lights nothing
## was ever meant to see all at once.
const LIGHT_COUNT_MIN := 8
const LIGHT_COUNT_MAX := 18
const LIGHT_MIN_SPACING := 6.0

func _hang_ceiling_lights(seed_text: String) -> void:
	if _ceiling_decor != null:
		_ceiling_decor.queue_free()
	_ceiling_decor = CeilingDecor.new()
	add_child(_ceiling_decor)

	var rng := SeededRandom.new("%s:CEILING-LIGHTS" % seed_text)
	var candidates: Array[Vector2i] = []
	for y in generator.rows:
		for x in generator.cols:
			if generator.grid[y][x] == 0:
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return

	var target := clampi(candidates.size() / 60, LIGHT_COUNT_MIN, LIGHT_COUNT_MAX)
	var chosen: Array[Vector2i] = []
	# Shuffled draw-without-replacement rather than a scan with a spacing
	# reject loop: wanting only a handful out of a floor that can run to
	# thousands of open cells, a reject loop over all of them to find those
	# few is the expensive way to do it.
	var pool := candidates.duplicate()
	while chosen.size() < target and not pool.is_empty():
		var pick: Vector2i = pool[rng.next_index(pool.size())]
		pool.erase(pick)
		var clear := true
		for other in chosen:
			if Vector2(pick).distance_to(Vector2(other)) < LIGHT_MIN_SPACING:
				clear = false
				break
		if clear:
			chosen.append(pick)

	var anchors: Array = []
	for cell in chosen:
		var at := cell_to_world(cell)
		# Just under the ceiling slab, not touching it -- a bulb flush with the
		# ceiling reads as embedded in it rather than hanging from it.
		at.y = WALL_HEIGHT - 0.22
		anchors.append(at)
	_ceiling_decor.build(anchors, rng)


func _spawn_interactable(kind: RouteInteractable3D.Kind, cell: Vector2i, prompt_text: String) -> RouteInteractable3D:
	var node := RouteInteractable3D.new()
	node.position = cell_to_world(cell)
	node.kind = kind
	node.prompt_text = prompt_text
	node.source_cell = cell
	node.generator = generator
	node.changed.connect(world_changed.emit)
	add_child(node)
	_interactables.append(node)
	return node


## Anything on this floor the rest of the room has to hear about. Re-emitted
## from the interactables so the scene above has one thing to listen to instead
## of a subscription per relay.
signal world_changed(event: Dictionary)


## Apply an event another peer raised. Cell-addressed, because both peers built
## this floor from the same seed and therefore have an object on that cell.
func apply_event(event: Dictionary) -> void:
	var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
	match String(event.get("what", "")):
		"pickup":
			var node := _at(cell, event.get("kind", -1))
			if node:
				node.adopt(event)
		"heater":
			if heater_station:
				heater_station.adopt(event)
		"hiding_disabled":
			var spot := hiding_spot_at(cell)
			if spot:
				spot.set_disabled(bool(event.get("disabled", false)))
		"sabotage":
			var relay := _at(cell, RouteInteractable3D.Kind.RELAY)
			if relay:
				relay.adopt(event)
		"boarded_path":
			var barrier := _at(cell, RouteInteractable3D.Kind.BOARDED_PATH)
			if barrier:
				barrier.adopt(event)
		"room_light":
			var light_switch := _at(cell, RouteInteractable3D.Kind.LIGHT_SWITCH)
			if light_switch:
				light_switch.adopt(event)


func hiding_spot_at(cell: Vector2i) -> RouteInteractable3D:
	return _at(cell, RouteInteractable3D.Kind.HIDING_SPOT)


func _at(cell: Vector2i, kind: int) -> RouteInteractable3D:
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item and item.source_cell == cell and int(item.kind) == kind:
			return item
	return null


## Zellia's repair offer: whichever relay is currently offline, or null if
## none is. Scans the same _interactables list shared_state() already reads
## sabotage off of, rather than generator.relays -- sabotage is presentation-
## node state (see route_interactable_3d.gd's own note on why), not the
## generator's.
func find_sabotaged_relay() -> RouteInteractable3D:
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item and item.kind == RouteInteractable3D.Kind.RELAY and item.sabotaged:
			return item
	return null


## Everything about this floor that a peer joining halfway through would
## otherwise get wrong.
func shared_state() -> Dictionary:
	var taken := []
	var sabotaged := []
	var disabled_hiding := []
	var opened_paths := []
	var boarded_paths := []
	var room_lights := {}
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item == null:
			continue
		if item.completed and RouteInteractable3D.PICKUPS.has(item.kind):
			taken.append({"cell": item.source_cell, "kind": int(item.kind)})
		if item.kind == RouteInteractable3D.Kind.RELAY and item.sabotaged:
			sabotaged.append(item.source_cell)
		if item.kind == RouteInteractable3D.Kind.HIDING_SPOT and item.disabled:
			disabled_hiding.append(item.source_cell)
		if item.kind == RouteInteractable3D.Kind.BOARDED_PATH and item.opened:
			opened_paths.append(item.source_cell)
		if item.kind == RouteInteractable3D.Kind.BOARDED_PATH:
			boarded_paths.append({"cell": item.source_cell,
				"opened": item.opened,
				"pieces_remaining": item.board_pieces_remaining})
		if item.kind == RouteInteractable3D.Kind.LIGHT_SWITCH:
			room_lights[item.light_id] = item.light_enabled
	return {
		"taken": taken,
		"heater": int(heater_station.heater_state) if heater_station else 0,
		"sabotaged": sabotaged,
		"disabled_hiding": disabled_hiding,
		"opened_paths": opened_paths,
		"boarded_paths": boarded_paths,
		"room_lights": room_lights,
	}


func adopt_state(state: Dictionary) -> void:
	# A snapshot is a canonical set, not a list of additional mutations. Exact
	# reconciliation lets it undo an optimistic guest pickup or a stale sabotage
	# without rebuilding/teleporting everyone on an unchanged custom floor.
	var taken := {}
	for entry in state.get("taken", []):
		var cell = entry.get("cell")
		var kind := int(entry.get("kind", -1))
		if cell is Vector2i and RouteInteractable3D.PICKUPS.has(kind):
			taken[_snapshot_item_key(cell, kind)] = true
	var sabotaged := {}
	for cell in state.get("sabotaged", []):
		if cell is Vector2i:
			sabotaged[cell] = true
	var disabled_hiding := {}
	for cell in state.get("disabled_hiding", []):
		if cell is Vector2i:
			disabled_hiding[cell] = true
	var opened_paths := {}
	for cell in state.get("opened_paths", []):
		if cell is Vector2i:
			opened_paths[cell] = true
	var boarded_paths := {}
	for entry in state.get("boarded_paths", []):
		var cell = entry.get("cell")
		if cell is Vector2i:
			boarded_paths[cell] = entry
	var room_lights: Dictionary = state.get("room_lights", {})
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item == null:
			continue
		if RouteInteractable3D.PICKUPS.has(item.kind):
			item.set_completed(taken.has(_snapshot_item_key(item.source_cell, item.kind)))
		if item.kind == RouteInteractable3D.Kind.RELAY:
			item.adopt({"what": "sabotage", "sabotaged": sabotaged.has(item.source_cell)})
		elif item.kind == RouteInteractable3D.Kind.HIDING_SPOT:
			item.set_disabled(disabled_hiding.has(item.source_cell))
		elif item.kind == RouteInteractable3D.Kind.BOARDED_PATH:
			var barrier_state: Dictionary = boarded_paths.get(item.source_cell, {})
			item.adopt({"what": "boarded_path",
				"opened": bool(barrier_state.get("opened",
					opened_paths.has(item.source_cell))),
				"pieces_remaining": int(barrier_state.get("pieces_remaining",
					0 if opened_paths.has(item.source_cell) else item._board_piece_nodes.size()))})
		elif item.kind == RouteInteractable3D.Kind.LIGHT_SWITCH:
			item.adopt({"what": "room_light", "light_id": item.light_id,
				"enabled": bool(room_lights.get(item.light_id, true))})
	if heater_station:
		heater_station.adopt({"what": "heater", "state": state.get("heater", 0)})


static func _snapshot_item_key(cell: Vector2i, kind: int) -> String:
	return "%d:%d:%d" % [cell.x, cell.y, kind]


## Floor, wall and ceiling as plain boxes.
##
## The wall used to be the imported wall_block model dropped straight into the
## GridMap, and it landed at the wrong orientation -- a cell is a cube and the
## model is not, so every wall carried whatever rotation the export happened to
## bake in. Chasing that per-cell is a losing game when the thing being drawn is
## a 1 m cube: a box is unambiguously square to the grid and cannot be rotated
## wrongly, which is the whole point.
##
## Floor and wall each get their OWN small dedicated texture (FLOOR_TEXTURE /
## WALL_TEXTURE) rather than sharing the wider environment kit sheet the
## original imported models draw from. That kit packs many unrelated swatches
## -- tile, plank trim, hazard stripe, brick, ribbed panelling -- onto one
## atlas per model export, and a plain BoxMesh has no way to know which of
## those patches its own faces are supposed to read: an earlier version of
## this method guessed at runtime (biggest same-facing triangle group wins),
## and got it wrong twice -- once as a collage of several patches at once,
## once as a single 12-pixel trim sliver blown up across a whole wall face
## with nothing else to sample from. A dedicated texture has exactly one
## thing on it, so there is nothing left to guess: `_tile_material()` loads
## it and repeats it, the same shape a Minecraft/Hytale block texture is
## sampled in. See tools/environment/bake_block_textures.gd for how
## FLOOR_TEXTURE/WALL_TEXTURE were cropped out of the kit sheet, once,
## offline -- not at runtime, and not by a heuristic.
func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	# One tile per 1 m cell.
	var floor_material := _tile_material(FLOOR_TEXTURE, Vector3(1.0, 1.0, 1.0))
	# Repeated up the wall's full WALL_HEIGHT so a tile stays roughly
	# proportional rather than stretching one copy across all 3 m.
	var wall_material := _tile_material(WALL_TEXTURE, Vector3(1.0, WALL_HEIGHT, 1.0))
	# A ceiling is a floor seen from underneath.
	var ceiling_material := _tile_material(FLOOR_TEXTURE, Vector3(1.0, 1.0, 1.0))
	# A cell's origin is centred in X and Z but sits at its FLOOR in Y, which
	# is why every offset below is measured up from zero rather than from a
	# centre.
	# Gravity requires a real floor. The slab top and capsule base both meet at
	# y=0; cell_center_y=false above is the important half of that contract.
	# With the default centred GridMap cell the slab top was y=.5, which caused
	# the old depenetration/climbing bug that originally led to collision being
	# removed instead of fixing the grid origin.
	_add_box(library, ITEM_FLOOR, Vector3(CELL_SIZE, SLAB, CELL_SIZE),
		Vector3(0.0, -SLAB * 0.5, 0.0), floor_material, true)
	_add_box(library, ITEM_WALL, Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE),
		Vector3(0.0, WALL_HEIGHT * 0.5, 0.0), wall_material, true)
	# Painted a layer up, so subtract that layer back out of the offset.
	_add_box(library, ITEM_CEILING, Vector3(CELL_SIZE, SLAB, CELL_SIZE),
		Vector3(0.0, WALL_HEIGHT - CELL_SIZE - SLAB * 0.5, 0.0),
		ceiling_material, false)

	_region_floor_items.clear()
	_region_wall_items.clear()
	var next_id := ITEM_CEILING + 1
	for region in REGION_FLOOR_TINTS:
		var tinted: Material = floor_material.duplicate() if floor_material else null
		if tinted is StandardMaterial3D:
			var floor_style := tinted as StandardMaterial3D
			floor_style.albedo_color = REGION_FLOOR_TINTS[region]
			floor_style.uv1_scale = REGION_FLOOR_REPEAT.get(region, Vector3.ONE)
			floor_style.roughness = .72 if region in ["office", "arcade"] else .88
			floor_style.metallic = .12 if region in ["office", "maintenance"] else 0.0
			MaterialLook.tame(floor_style, false, true)
		_add_box(library, next_id, Vector3(CELL_SIZE, SLAB, CELL_SIZE),
			Vector3(0.0, -SLAB * 0.5, 0.0), tinted, true)
		_region_floor_items[region] = next_id
		next_id += 1
		var wall_tinted: Material = wall_material.duplicate() if wall_material else null
		if wall_tinted is StandardMaterial3D:
			var wall_style := wall_tinted as StandardMaterial3D
			wall_style.albedo_color = REGION_WALL_TINTS.get(region, Color.WHITE)
			wall_style.uv1_scale = Vector3(2.0 if region in ["mansion", "arcade"] else 1.0,
				WALL_HEIGHT, 1.0)
			wall_style.roughness = .78 if region in ["office", "maintenance"] else .92
			MaterialLook.tame(wall_style)
		_add_box(library, next_id, Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE),
			Vector3(0.0, WALL_HEIGHT * .5, 0.0), wall_tinted, true)
		_region_wall_items[region] = next_id
		next_id += 1
	return library


static func _add_box(library: MeshLibrary, id: int, size: Vector3,
		offset: Vector3, material: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	if material != null:
		mesh.material = material
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	var placement := Transform3D(Basis.IDENTITY, offset)
	library.set_item_mesh_transform(id, placement)
	# Floors and walls are solid. The lid stays scenery so the small hop never
	# adds a low-ceiling head-bump or traps the player against decorative trim.
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		library.set_item_shapes(id, [shape, placement])


## Loads a dedicated block texture and tiles it -- a BoxMesh's default 0..1
## UVs need nothing more than that, unlike a shared-atlas material, which
## needed cropping to isolate one patch out of many. `repeat` scales those
## UVs directly, so `Vector3(1, 1, 1)` is one copy per face and
## `Vector3(1, 3, 1)` is three copies stacked vertically (used for the wall,
## whose face is three times taller than it is wide).
static func _tile_material(texture_path: String, repeat: Vector3) -> StandardMaterial3D:
	var texture: Texture2D = load(texture_path)
	if texture == null:
		return null
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = \
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale = repeat
	return material
