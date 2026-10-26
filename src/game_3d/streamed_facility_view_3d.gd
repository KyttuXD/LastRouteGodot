class_name StreamedFacilityView3D
extends Node3D

## Live debug renderer for StreamedRouteGenerator. It keeps a 3x3 horizontal
## window around the runner plus the matching chunks immediately above/below,
## so the route can extend forever without retaining every visited mesh.

signal chunk_changed(coord: Vector3i, data: Dictionary)
signal pickup_claimed(entity_id: String)

const CELL_SIZE := 1.0
const LEVEL_HEIGHT := 4.0
const STREAM_RADIUS := 1
## New chunks are outside the runner's already-collidable 3x3 window, giving us
## time to assemble them incrementally. A 45x45 GridMap used to issue more than
## four thousand live cell updates and instantiate every prop in one frame.
## Keep each streaming frame to one registration job and a bounded cell batch.
## Initial loads, teleports and level changes remain immediate because control
## cannot begin until their collision window is complete.
const STREAM_JOBS_PER_FRAME := 1
const STREAM_CELLS_PER_FRAME := 256
## Larger GridMap octants turn each 45x45 chunk into nine structural batches
## instead of thirty-six. This substantially reduces renderer/physics server
## registration overhead while preserving useful room-scale culling.
const GRID_OCTANT_SIZE := 16
const SLAB := 0.1
## Air gap between the top of a lower ceiling slab and the bottom of the next
## floor slab. The two 10 cm solids previously overlapped by 8 cm, which made
## lower-floor ceiling colours bleed through upper floors as the camera moved.
const CEILING_INSET := 0.02
## Stop at the underside of the next floor instead of occupying its slab.
## A four-metre wall plus a floor which extends 10 cm downward overlapped in
## stacked chunks, producing upper-floor stripes and solid columns across stair
## landings. The ceiling closes this small remainder without overlapping either.
const WALL_HEIGHT := LEVEL_HEIGHT - SLAB - CEILING_INSET
## Every wall cell remains a full 1m cube/block so streamed rooms do not
## create slab-like collision gaps or elongated wall seams between chunks.
const STAIR_RUN := 8.0
const STAIR_RISE := LEVEL_HEIGHT
const STAIR_WIDTH := 3.0
const STAIR_STEPS := 16
const LEVEL_TRANSITION_MARGIN := 0.35

const FLOOR_TEXTURE := "res://art/props-3d/environment/floor_texture.png"
const WALL_TEXTURE := "res://art/props-3d/environment/wall_texture.png"
const REGION_FLOOR_TEXTURE := "res://art/props-3d/environment/floor_%s.png"
const REGION_WALL_TEXTURE := "res://art/props-3d/environment/wall_%s.png"
const FLOOR_TILE_SCENE := "res://art/props-3d/environment/floor_tile.tscn"
const WALL_BLOCK_SCENE := "res://art/props-3d/environment/wall_block.tscn"
const PRISON_MODELS := {
	"gate": "res://art/props-3d/props/prison/prison_cell_gate.glb",
	"bunk": "res://art/props-3d/props/prison/prison_bunk.glb",
	"cage": "res://art/props-3d/props/prison/dungeon_cage.glb",
	"chair": "res://art/props-3d/props/prison/restraint_chair.glb",
}
const REGION_COLORS := {
	"maze": Color("d1aa94"),
	"mansion": Color("c58c7c"),
	"hotel": Color("c8aa82"),
	"apartment": Color("88a2b5"),
	"beach": Color("a5d4da"),
	"gothic": Color("82659a"),
	"prison": Color("748895"),
	"inferno": Color("c45b45"),
	"carnival": Color("d58aa9"),
}
const REGION_WALL_COLORS := {
	"maze": Color("b47d6e"),
	"mansion": Color("a96b61"),
	"hotel": Color("aa8869"),
	"apartment": Color("6f879c"),
	"beach": Color("88afb9"),
	"gothic": Color("674d79"),
	"prison": Color("61717d"),
	"inferno": Color("9f493d"),
	"carnival": Color("8e3f61"),
}

var generator: StreamedRouteGenerator
var world_state: StreamedWorldState
var tracked_player: PlayerController3D
var pickup_requester: Callable
var door_requester: Callable

var _library: MeshLibrary
var _floor_items := {}
var _wall_items := {}
var _safe_floor_item := -1
## RefLook surface items: kind -> MeshLibrary id.
var _ref_floor_items := {}
var _ref_wall_items := {}
var _ref_ceiling_items := {}
var _loaded := {}
var _chunk_data := {}
var _pickup_nodes := {}
var _door_nodes := {}
var _fixture_nodes := {}
var _last_player_chunk := Vector3i(999999, 999999, 999999)
var _pending_loads: Array[Vector3i] = []
var _pending_unloads: Array[Vector3i] = []
var _active_build := {}
var _stream_queue_center := Vector3i(999999, 999999, 999999)
var _stream_completion_pending := false
var _all_lights_enabled := true
## One low-resolution planar camera is shared by every streamed mirror. Only
## the nearest mirror within interaction distance enables it, at 10 Hz, so a
## hotel full of mirrors never becomes a stack of extra full scene renders.
var _mirror_viewport: SubViewport
var _mirror_camera: Camera3D
var _mirror_surfaces: Array[MeshInstance3D] = []
var _mirror_refresh_elapsed := 0.0
var _animated_activity_props: Array[Node3D] = []
var _tracked_level := 0
var _lamp_field: LampField


func _ready() -> void:
	_library = _build_mesh_library()
	_build_shared_mirror()
	_lamp_field = LampField.new()
	add_child(_lamp_field)


func begin(seed_text: String, player: PlayerController3D,
		state: StreamedWorldState = null) -> void:
	clear()
	generator = StreamedRouteGenerator.new(seed_text)
	tracked_player = player
	world_state = state if state != null else StreamedWorldState.new()
	_tracked_level = snapped_level_for_world_y(
		tracked_player.global_position.y if tracked_player != null else 0.0)
	_refresh_stream(true)


func clear() -> void:
	if _lamp_field != null:
		_lamp_field.clear()
	# Mirror surfaces are children of streamed chunks. Drop the references before
	# queueing those chunks so the 10 Hz mirror pass can never inspect a freed
	# typed-object entry during a rebuild or scene shutdown.
	_mirror_surfaces.clear()
	_animated_activity_props.clear()
	for node_value in _loaded.values():
		var node := node_value as Node
		if node != null:
			node.queue_free()
	_loaded.clear()
	_chunk_data.clear()
	_pickup_nodes.clear()
	_door_nodes.clear()
	_fixture_nodes.clear()
	_pending_loads.clear()
	_pending_unloads.clear()
	_discard_active_build()
	_stream_completion_pending = false
	_last_player_chunk = Vector3i(999999, 999999, 999999)
	_tracked_level = 0


func spawn_position() -> Vector3:
	if generator == null:
		return Vector3.ZERO
	var cell := generator.spawn_cell()
	return Vector3(cell.x + .5, .04, cell.y + .5)


## Admin teleports bypass CharacterBody movement, so the normal _process()
## stream transition has not happened yet when the same button callback closes
## its modal. Rebuild the collision/map window synchronously at the new runner
## position so the next fullscreen-map draw cannot observe an empty old floor.
func refresh_at_tracked_player() -> void:
	if generator == null or tracked_player == null:
		return
	_tracked_level = snapped_level_for_world_y(tracked_player.global_position.y)
	_refresh_stream(true)


func current_level() -> int:
	if tracked_player == null:
		return 0
	_tracked_level = hysteresis_level_for_world_y(tracked_player.global_position.y,
		_tracked_level)
	return _tracked_level


static func snapped_level_for_world_y(world_y: float) -> int:
	return roundi(world_y / LEVEL_HEIGHT)


static func hysteresis_level_for_world_y(world_y: float, current_level_hint: int) -> int:
	var level := current_level_hint
	var snapped_level := snapped_level_for_world_y(world_y)
	if absi(snapped_level - level) > 1:
		return snapped_level
	while world_y >= float(level + 1) * LEVEL_HEIGHT - LEVEL_TRANSITION_MARGIN:
		level += 1
	while world_y <= float(level - 1) * LEVEL_HEIGHT + LEVEL_TRANSITION_MARGIN:
		level -= 1
	return level


func current_chunk_coord() -> Vector3i:
	if tracked_player == null:
		return Vector3i.ZERO
	return Vector3i(
		floori(tracked_player.global_position.x / StreamedRouteGenerator.CHUNK_SIZE),
		current_level(),
		floori(tracked_player.global_position.z / StreamedRouteGenerator.CHUNK_SIZE))


func current_chunk_data() -> Dictionary:
	var coord := current_chunk_coord()
	if _chunk_data.has(coord):
		return (_chunk_data[coord] as Dictionary).duplicate(false)
	return generator.chunk(coord) if generator != null else {}


func loaded_chunk_count() -> int:
	return _loaded.size()


func set_all_lights(enabled: bool) -> void:
	_all_lights_enabled = enabled
	if _lamp_field != null:
		_lamp_field.set_enabled(enabled)
	for root_value in _loaded.values():
		_set_lights_recursive(root_value as Node, enabled)


func all_lights_enabled() -> bool:
	return _all_lights_enabled


static func _set_lights_recursive(node: Node, enabled: bool) -> void:
	if node == null:
		return
	if node is Light3D:
		(node as Light3D).visible = enabled
	for child in node.get_children():
		_set_lights_recursive(child, enabled)


func loaded_horizontal_coords() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var level := current_level()
	for value in _loaded.keys():
		var coord: Vector3i = value
		if coord.y == level:
			result.append(coord)
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.z < b.z or (a.z == b.z and a.x < b.x))
	return result


func streamed_surface_height(_world_xz: Vector2, level: int) -> float:
	# Hunter brains remain X/Z grid simulations. Their presentation is pinned
	# to the owning streamed level; vertical transfer is handled as a discrete
	# world-state transition rather than allowing unloaded CharacterBodies to
	# fall through a missing floor.
	return float(level) * LEVEL_HEIGHT


func _process(_delta: float) -> void:
	if generator == null or tracked_player == null:
		return
	_refresh_stream(false)
	_drain_stream_queue()
	_collect_taken_pickups()
	_update_shared_mirror(_delta)
	for index in range(_animated_activity_props.size() - 1, -1, -1):
		var activity := _animated_activity_props[index]
		if activity == null or not is_instance_valid(activity):
			_animated_activity_props.remove_at(index)
		else:
			activity.rotate_y(_delta * .34)


func _refresh_stream(force: bool) -> void:
	var center := current_chunk_coord()
	if not force and center == _last_player_chunk:
		return
	var previous := _last_player_chunk
	_last_player_chunk = center
	var wanted := {}
	for z in range(center.z - STREAM_RADIUS, center.z + STREAM_RADIUS + 1):
		for x in range(center.x - STREAM_RADIUS, center.x + STREAM_RADIUS + 1):
			var coord := Vector3i(x, center.y, z)
			if generator.is_chunk_allowed(coord):
				wanted[coord] = true
	# The current shaft remains present on both adjacent floors while walking a
	# flight, preventing the ramp from unloading halfway through the crossing.
	for vertical in [Vector3i(center.x, center.y - 1, center.z),
			Vector3i(center.x, center.y + 1, center.z)]:
		if generator.is_chunk_allowed(vertical):
			wanted[vertical] = true
	var immediate := force or previous.x == 999999 or previous.y != center.y \
		or absi(previous.x - center.x) > 1 or absi(previous.z - center.z) > 1
	_pending_loads.clear()
	_pending_unloads.clear()
	if not _active_build.is_empty():
		var active_coord: Vector3i = _active_build.get("coord", Vector3i.ZERO)
		if not wanted.has(active_coord):
			_discard_active_build()
	for coord_value in wanted:
		var coord: Vector3i = coord_value
		if not _loaded.has(coord) and (_active_build.is_empty() \
				or _active_build.get("coord", Vector3i.ZERO) != coord):
			_pending_loads.append(coord)
	for coord_value in _loaded.keys().duplicate():
		var coord: Vector3i = coord_value
		if not wanted.has(coord):
			_pending_unloads.append(coord)
	_pending_loads.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _chunk_distance(a, center) < _chunk_distance(b, center))
	_pending_unloads.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _chunk_distance(a, center) > _chunk_distance(b, center))
	_stream_queue_center = center
	_stream_completion_pending = not immediate \
		and (not _pending_loads.is_empty() or not _pending_unloads.is_empty())
	if immediate:
		_discard_active_build()
		while not _pending_loads.is_empty():
			_load_chunk(_pending_loads.pop_front())
		while not _pending_unloads.is_empty():
			_unload_chunk(_pending_unloads.pop_front())
	var data: Dictionary = _chunk_data.get(center,
		generator.chunk(center) if generator != null else {})
	chunk_changed.emit(center, data.duplicate(false))


func _drain_stream_queue() -> void:
	if _pending_loads.is_empty() and _pending_unloads.is_empty() \
			and _active_build.is_empty():
		return
	for _index in STREAM_JOBS_PER_FRAME:
		# Never register new collision and retire an old physics island in the same
		# frame. Freeing first keeps the live server load bounded before the staged
		# replacement starts entering the tree.
		if not _pending_unloads.is_empty() and _active_build.is_empty():
			_unload_chunk(_pending_unloads.pop_front())
			continue
		if _active_build.is_empty() and not _pending_loads.is_empty():
			_active_build = _create_chunk_build(_pending_loads.pop_front())
		if not _active_build.is_empty() \
				and _advance_chunk_build(_active_build, false):
			_active_build = {}
	if _pending_loads.is_empty() and _pending_unloads.is_empty() \
			and _active_build.is_empty() \
			and _stream_completion_pending:
		_stream_completion_pending = false
		var data: Dictionary = _chunk_data.get(_stream_queue_center,
			generator.chunk(_stream_queue_center) if generator != null else {})
		chunk_changed.emit(_stream_queue_center, data.duplicate(false))


static func _chunk_distance(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)


func _load_chunk(coord: Vector3i) -> void:
	var build := _create_chunk_build(coord)
	while not _advance_chunk_build(build, true):
		pass


func _create_chunk_build(coord: Vector3i) -> Dictionary:
	var data := generator.chunk(coord)
	var root := Node3D.new()
	root.name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
	root.position = Vector3(coord.x * StreamedRouteGenerator.CHUNK_SIZE,
		coord.y * LEVEL_HEIGHT, coord.z * StreamedRouteGenerator.CHUNK_SIZE)
	# The empty root can enter the tree cheaply. Its populated GridMaps, props and
	# interactables are then attached over subsequent frames while the chunk is
	# still outside the player's existing collision window.
	add_child(root)
	var grid := GridMap.new()
	grid.name = "Structure"
	_configure_grid(grid)
	var ceiling := GridMap.new()
	ceiling.name = "Ceiling"
	_configure_grid(ceiling)
	var region := String(data.get("region", "maze"))
	var ceiling_voids := _stair_voids(data, "up")
	var floor_voids := _stair_voids(data, "down")
	var structural_voids := {}
	for cell_value in data.get("ceiling_voids", []):
		ceiling_voids[cell_value as Vector2i] = true
	for cell_value in data.get("floor_voids", []):
		floor_voids[cell_value as Vector2i] = true
	for cell_value in data.get("structural_voids", []):
		structural_voids[cell_value as Vector2i] = true
	return {
		"coord": coord,
		"data": data,
		"root": root,
		"grid": grid,
		"ceiling": ceiling,
		"region": region,
		"floor_item": int(_floor_items.get(region, _floor_items["maze"])),
		"wall_items": _wall_items.get(region, _wall_items["maze"]),
		"ceiling_voids": ceiling_voids,
		"floor_voids": floor_voids,
		"structural_voids": structural_voids,
		"safe": bool(data.get("safe_room", false)),
		"style": RefLook.REGION_STYLE.get(region, RefLook.REGION_STYLE["maze"]),
		"room_map": _room_type_map(data),
		"decor": null,
		"cell_index": 0,
		"phase": 0,
		"prop_index": 0,
		"fixture_index": 0,
		"pickup_index": 0,
		"prison_tasks": _prison_prop_tasks(data) if region == "prison" else [],
	}


func _advance_chunk_build(build: Dictionary, immediate: bool) -> bool:
	var root := build["root"] as Node3D
	if root == null or not is_instance_valid(root):
		return true
	var data: Dictionary = build["data"]
	var keep_working := true
	while keep_working:
		match int(build["phase"]):
			0:
				var total := StreamedRouteGenerator.CHUNK_SIZE \
					* StreamedRouteGenerator.CHUNK_SIZE
				var finish := total if immediate else mini(total,
					int(build["cell_index"]) + STREAM_CELLS_PER_FRAME)
				while int(build["cell_index"]) < finish:
					_build_structure_cell(build, int(build["cell_index"]))
					build["cell_index"] = int(build["cell_index"]) + 1
				if int(build["cell_index"]) < total:
					return false
				build["phase"] = 1
				if not immediate:
					return false
			1:
				root.add_child(build["grid"] as GridMap)
				build["phase"] = 2
				if not immediate:
					return false
			2:
				root.add_child(build["ceiling"] as GridMap)
				build["phase"] = 3
				if not immediate:
					return false
			3:
				_spawn_stairs(root, data)
				_spawn_streamed_ceiling_lights(root, data)
				build["decor"] = RefDecor.new(root, data, build["room_map"])
				build["phase"] = 31
				if not immediate:
					return false
			31:
				# lamps, pipes, frames: a few grid rows per frame while streaming
				var decor: RefDecor = build["decor"]
				if not decor.step() and not immediate:
					return false
				while immediate and not decor.step():
					pass
				build["phase"] = 4
				if not immediate:
					return false
			4:
				# Prison still needs generated region_props: cafeteria templates,
				# wall art, and any other authored dressing. The cell-block
				# dresser is extra presentation for prison_cell rooms only and
				# must not replace those props.
				var region_props: Array = data.get("region_props", [])
				var prison_tasks: Array = build["prison_tasks"]
				var prop_index := int(build["prop_index"])
				if prop_index < region_props.size():
					_spawn_region_prop(root, build["coord"], region_props[prop_index])
					build["prop_index"] = prop_index + 1
					if not immediate:
						return false
					continue
				var prison_index := prop_index - region_props.size()
				if prison_index < prison_tasks.size():
					_spawn_prison_prop_task(root, prison_tasks[prison_index])
					build["prop_index"] = prop_index + 1
					if not immediate:
						return false
					continue
				build["phase"] = 5
			5:
				if bool(build["safe"]):
					_spawn_safe_room_light(root)
				if build["coord"] == Vector3i.ZERO:
					_spawn_start_marker(root)
				build["phase"] = 6
				if not immediate:
					return false
			6:
				var fixtures: Array = data.get("fixtures", [])
				var fixture_index := int(build["fixture_index"])
				if fixture_index < fixtures.size():
					_spawn_fixture(root, data, fixtures[fixture_index])
					build["fixture_index"] = fixture_index + 1
					if not immediate:
						return false
					continue
				build["phase"] = 7
			7:
				var pickups: Array = data.get("pickups", [])
				var pickup_index := int(build["pickup_index"])
				if pickup_index < pickups.size():
					_spawn_pickup(root, data, pickups[pickup_index])
					build["pickup_index"] = pickup_index + 1
					if not immediate:
						return false
					continue
				build["phase"] = 8
			8:
				var coord: Vector3i = build["coord"]
				root.add_to_group("streamed_chunk")
				if build["decor"] != null and _lamp_field != null:
					_lamp_field.register(coord, (build["decor"] as RefDecor).lamps)
				if not _all_lights_enabled:
					_set_lights_recursive(root, false)
				_loaded[coord] = root
				_chunk_data[coord] = data
				return true
			_:
				return true
	return false


func _build_structure_cell(build: Dictionary, index: int) -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var x := index % size
	var z := floori(float(index) / float(size))
	var cell := Vector2i(x, z)
	var data: Dictionary = build["data"]
	var grid_data: Array = data["grid"]
	var grid := build["grid"] as GridMap
	var ceiling := build["ceiling"] as GridMap
	if (build["structural_voids"] as Dictionary).has(cell):
		# The upper half of a two-storey room is genuine air. It owns neither an
		# upper floor slab nor wall collision, but it still receives this level's
		# ceiling so the combined room closes at eight metres.
		if not (build["ceiling_voids"] as Dictionary).has(cell):
			ceiling.set_cell_item(Vector3i(x, 1, z), _ref_ceiling_item(build))
		return
	if int(grid_data[z][x]) == 0:
		if not (build["floor_voids"] as Dictionary).has(cell):
			var item := _ref_floor_item(build, x, z)
			if bool(build["safe"]):
				var center := StreamedRouteGenerator.CHUNK_SIZE / 2
				if abs(x - center) <= 3 and abs(z - center) <= 3:
					item = _safe_floor_item
			grid.set_cell_item(Vector3i(x, 0, z), item)
		if not (build["ceiling_voids"] as Dictionary).has(cell):
			ceiling.set_cell_item(Vector3i(x, 1, z), _ref_ceiling_item(build))
	else:
		grid.set_cell_item(Vector3i(x, 0, z), _ref_wall_item(build, x, z))



## Cell -> room_type for every cell inside a room rectangle of this chunk.
static func _room_type_map(data: Dictionary) -> Dictionary:
	var map := {}
	for room_value in data.get("rooms", []):
		var room: Dictionary = room_value
		var rect: Rect2i = room.get("rect", Rect2i())
		var room_type := String(room.get("room_type", ""))
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				map[Vector2i(x, z)] = room_type
	return map


func _ref_ceiling_item(build: Dictionary) -> int:
	var style: Dictionary = build["style"]
	return int(_ref_ceiling_items.get(String(style["ceiling"]), 1))


func _ref_floor_item(build: Dictionary, x: int, z: int) -> int:
	var style: Dictionary = build["style"]
	var coord: Vector3i = build["coord"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var gx := coord.x * size + x
	var gz := coord.z * size + z
	var room_type: String = (build["room_map"] as Dictionary).get(Vector2i(x, z), "")
	var kinds: Array
	if room_type != "":
		kinds = (RefLook.ROOM_STYLE.get(room_type, {}) as Dictionary).get("floor", style["room"])
	else:
		kinds = style["corridor"]
		if bool(style["runner"]):
			var runner := _runner_kind(build["data"]["grid"], x, z)
			if runner != "":
				return int(_ref_floor_items.get(runner, build["floor_item"]))
	var kind: String = kinds[RefLook.pick(gx, gz, 1, kinds.size())]
	return int(_ref_floor_items.get(kind, build["floor_item"]))


## The middle cell of a three-wide corridor gets the carpet runner, oriented
## along the corridor. Outside the chunk counts as wall.
static func _runner_kind(grid_data: Array, x: int, z: int) -> String:
	var size := grid_data.size()
	var open := func(cx: int, cz: int) -> bool:
		return cx >= 0 and cz >= 0 and cx < size and cz < size \
			and int(grid_data[cz][cx]) == 0
	if open.call(x, z - 1) and open.call(x, z + 1) \
			and not open.call(x, z - 2) and not open.call(x, z + 2):
		return "runner"
	if open.call(x - 1, z) and open.call(x + 1, z) \
			and not open.call(x - 2, z) and not open.call(x + 2, z):
		return "runnerz"
	return ""


func _ref_wall_item(build: Dictionary, x: int, z: int) -> int:
	var style: Dictionary = build["style"]
	var coord: Vector3i = build["coord"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var grid_data: Array = build["data"]["grid"]
	var room_type := ""
	var touches_open := false
	for step_value in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var step: Vector2i = step_value
		var nx: int = x + step.x
		var nz: int = z + step.y
		if nx < 0 or nz < 0 or nx >= size or nz >= size:
			continue
		if int(grid_data[nz][nx]) == 0:
			touches_open = true
			var found: String = (build["room_map"] as Dictionary).get(Vector2i(nx, nz), "")
			if found != "":
				room_type = found
				break
	var kinds: Array = (RefLook.ROOM_STYLE.get(room_type, {}) as Dictionary).get(
		"wall", style["wall"]) if room_type != "" else style["wall"]
	var kind: String = kinds[RefLook.pick(coord.x * size + x, coord.z * size + z, 2, kinds.size())]
	return int(_ref_wall_items.get(kind, int((build["wall_items"] as Dictionary)["full"])))


static func _wall_item_for(grid_data: Array, x: int, z: int,
		items: Dictionary) -> int:
	# Restore the original collision model expectation: every wall cell is a
	# full 1m grid block. This avoids thin-wall collision gaps when adjacent
	# cells across chunk boundaries or room connectors are streamed/unstreamed.
	return int(items["full"])


static func _wall_cell_is_junction(grid_data: Array, x: int, z: int) -> bool:
	if x <= 0 or z <= 0 or z >= grid_data.size() - 1 \
			or x >= grid_data[0].size() - 1 or int(grid_data[z][x]) == 0:
		return false
	var horizontal := int(grid_data[z][x - 1]) != 0 \
		or int(grid_data[z][x + 1]) != 0
	var vertical := int(grid_data[z - 1][x]) != 0 \
		or int(grid_data[z + 1][x]) != 0
	return horizontal and vertical


func _discard_active_build() -> void:
	if _active_build.is_empty():
		return
	var root := _active_build.get("root") as Node
	if root != null and is_instance_valid(root):
		_forget_chunk_entities(root)
		root.queue_free()
	_active_build = {}


func _unload_chunk(coord: Vector3i) -> void:
	if _lamp_field != null:
		_lamp_field.unregister(coord)
	var root := _loaded.get(coord) as Node
	if root != null:
		_forget_chunk_entities(root)
		root.queue_free()
	_loaded.erase(coord)
	_chunk_data.erase(coord)


func _forget_chunk_entities(root: Node) -> void:
	for entity_id in _pickup_nodes.keys().duplicate():
		var pickup := _pickup_nodes[entity_id] as Node
		if pickup == null or root.is_ancestor_of(pickup):
			_pickup_nodes.erase(entity_id)
	for door_id in _door_nodes.keys().duplicate():
		var door := _door_nodes[door_id] as Node
		if door == null or root.is_ancestor_of(door):
			_door_nodes.erase(door_id)


func _configure_grid(grid: GridMap) -> void:
	grid.cell_size = Vector3.ONE * CELL_SIZE
	grid.cell_center_y = false
	grid.cell_octant_size = GRID_OCTANT_SIZE
	grid.mesh_library = _library


func _stair_voids(data: Dictionary, direction: String) -> Dictionary:
	var result := {}
	for stair_value in data.get("stairs", []):
		var stair: Dictionary = stair_value
		if String(stair.get("direction", "")) != direction:
			continue
		var path := _stair_path(stair)
		# The last path cell is the upper landing. The old full-path cut removed
		# that tile too, leaving a square pit immediately after the top tread.
		# Keep the landing floor solid while the preceding cells remain the
		# actual stairwell opening. The lower ceiling stays open for the complete
		# flight, so this does not reintroduce head clipping from below.
		if direction == "down" and path.size() > 1:
			path.resize(path.size() - 1)
		var travel := path[1] - path[0] if path.size() > 1 else Vector2i.RIGHT
		var across := Vector2i(-travel.y, travel.x)
		for cell in path:
			# Match the three-metre physical tread. Cutting only the centre tile
			# made both outer thirds intersect the floor/ceiling slab.
			for offset in range(-1, 2):
				result[cell + across * offset] = true
	return result


func _stair_path(stair: Dictionary) -> Array[Vector2i]:
	var start: Vector2i = stair.get("cell", Vector2i.ZERO)
	return StreamedRouteGenerator.stair_path_cells(start)


func _spawn_stairs(parent: Node3D, data: Dictionary) -> void:
	var region := String(data.get("region", "maze"))
	var stair_texture := load(REGION_FLOOR_TEXTURE % region) as Texture2D
	if stair_texture == null:
		stair_texture = load(FLOOR_TEXTURE) as Texture2D
	var region_tint: Color = REGION_COLORS.get(region, REGION_COLORS["maze"])
	for stair_value in data.get("stairs", []):
		var stair: Dictionary = stair_value
		if String(stair.get("direction", "")) != "up":
			continue
		var path := _stair_path(stair)
		if path.size() < 2:
			continue
		var start_cell := path[0]
		var direction_2d := path[1] - path[0]
		var direction := Vector3(direction_2d.x, 0.0, direction_2d.y)
		var start := Vector3(start_cell.x + .5, 0.0, start_cell.y + .5)
		var stair_root := Node3D.new()
		stair_root.name = String(stair.get("id", "Stair")).replace(":", "_")
		stair_root.add_to_group("streamed_stair")
		parent.add_child(stair_root)
		var stair_tint := region_tint.lightened(.10)
		if String(stair.get("style", "")) == "grand_foyer":
			stair_tint = Color("80694e")
		var material := _material(stair_texture, stair_tint,
			Vector3(STAIR_WIDTH, 1.0, STAIR_RUN / STAIR_STEPS))
		var tread_depth := STAIR_RUN / STAIR_STEPS
		# The upper floor itself is the final tread. Rendering a sixteenth box
		# there both overlapped its collision and exposed a void behind it.
		for step_index in range(STAIR_STEPS - 1):
			var progress := float(step_index + 1) / STAIR_STEPS
			var step := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(STAIR_WIDTH, .12, tread_depth)
			mesh.material = material
			step.mesh = mesh
			step.position = start + direction * ((step_index + .5) * tread_depth)
			step.position.y = progress * STAIR_RISE - .06
			step.rotation.y = atan2(direction.x, direction.z)
			stair_root.add_child(step)
		var ramp := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var flight_run := STAIR_RUN - tread_depth
		var slope_length := Vector2(flight_run, STAIR_RISE).length()
		shape.size = Vector3(STAIR_WIDTH, .12, slope_length)
		collision.shape = shape
		var yaw := atan2(direction.x, direction.z)
		var angle := atan2(STAIR_RISE, flight_run)
		collision.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -angle)
		collision.position = start + direction * (flight_run * .5) \
			+ Vector3.UP * (STAIR_RISE * .5)
		ramp.add_child(collision)
		stair_root.add_child(ramp)


func _spawn_streamed_ceiling_lights(parent: Node3D, data: Dictionary) -> void:
	var region := String(data.get("region", "maze"))
	if region not in ["carnival", "maze"]:
		return
	var blocked := _stair_voids(data, "up")
	for cell_value in data.get("ceiling_voids", []):
		blocked[cell_value as Vector2i] = true
	var candidates: Array[Vector2i] = []
	var grid: Array = data.get("grid", [])
	for z in range(2, grid.size() - 2):
		for x in range(2, (grid[z] as Array).size() - 2):
			var cell := Vector2i(x, z)
			if int(grid[z][x]) == 0 and not blocked.has(cell):
				candidates.append(cell)
	if candidates.is_empty():
		return
	var rng := SeededRandom.new("%s:STREAMED-FAIRY-LIGHTS" % String(
		data.get("chunk_id", "")))
	var target := 5 if region == "carnival" else 2
	var chosen: Array[Vector2i] = []
	while chosen.size() < target and not candidates.is_empty():
		var pick: Vector2i = candidates[rng.next_index(candidates.size())]
		candidates.erase(pick)
		if chosen.any(func(other: Vector2i) -> bool:
			return pick.distance_to(other) < 7.0):
			continue
		chosen.append(pick)
	if chosen.is_empty():
		return
	var anchors := []
	for cell in chosen:
		anchors.append(Vector3(cell.x + .5, WALL_HEIGHT - .12, cell.y + .5))
	var decor := CeilingDecor.new()
	decor.name = "FiniteFairyLights"
	decor.add_to_group("streamed_ceiling_decor")
	parent.add_child(decor)
	decor.build(anchors, rng)


func _spawn_prison_props(parent: Node3D, data: Dictionary) -> void:
	for task_value in _prison_prop_tasks(data):
		_spawn_prison_prop_task(parent, task_value)


func _prison_prop_tasks(data: Dictionary) -> Array:
	var tasks := []
	var rooms: Array = data.get("rooms", [])
	# Dedicated cafeteria/stairwell templates own their full interior. The old
	# cell-block dresser used to drop gates and bunks into every prison room,
	# stacking them through cafeteria furniture and blocking its serving aisle.
	var prison_cells := []
	for room_value in rooms:
		var candidate: Dictionary = room_value
		if String(candidate.get("room_type", "")) == "prison_cell":
			prison_cells.append(candidate)
	var cage_room_index: int = mini(prison_cells.size() - 1, 2) \
		if not prison_cells.is_empty() else -1
	for room_index in mini(prison_cells.size(), 6):
		var room: Dictionary = prison_cells[room_index]
		var rect: Rect2i = room.get("rect", Rect2i())
		var above_hall := rect.position.y < StreamedRouteGenerator.CHUNK_SIZE / 2
		var gate_at := Vector3(rect.position.x + rect.size.x * .5, 0.0,
			rect.end.y - .15 if above_hall else rect.position.y + .15)
		tasks.append({"path": PRISON_MODELS["gate"], "at": gate_at,
			"yaw": 0.0 if above_hall else PI,
			"size": Vector3(rect.size.x, 2.4, .16),
			"group": "streamed_prison_prop", "solid": true, "type": ""})
		# The dedicated cage fills this cell; do not bury a bunk/chair through it.
		if room_index == cage_room_index:
			continue
		var inside_z := rect.position.y + 1.0 if above_hall else rect.end.y - 1.0
		tasks.append({"path": PRISON_MODELS["bunk"],
			"at": Vector3(rect.position.x + 1.0, 0.0, inside_z),
			"yaw": PI * .5, "size": Vector3(.8, 1.55, 2.1),
			"group": "streamed_prison_prop", "solid": true,
			"type": "prisonBunk"})
		if room_index % 3 == 1:
			tasks.append({"path": PRISON_MODELS["chair"],
				"at": Vector3(rect.end.x - 1.0, 0.0, inside_z),
				"yaw": 0.0, "size": Vector3(.7, 1.2, .7),
				"group": "streamed_prison_prop", "solid": true,
				"type": "restraintChair"})
	if not prison_cells.is_empty():
		var room: Dictionary = prison_cells[cage_room_index]
		var center: Vector2i = room.get("center", Vector2i(
			StreamedRouteGenerator.CHUNK_SIZE / 2,
			StreamedRouteGenerator.CHUNK_SIZE / 2))
		tasks.append({"path": PRISON_MODELS["cage"],
			"at": Vector3(center.x + .5, 0.0, center.y + .5),
			"yaw": 0.0, "size": Vector3(2.2, 2.3, 2.2),
			"group": "streamed_prison_prop", "solid": true, "type": ""})
	return tasks


func _spawn_prison_prop_task(parent: Node3D, task: Dictionary) -> void:
	_spawn_authored_prop(parent, String(task.get("path", "")),
		task.get("at", Vector3.ZERO), float(task.get("yaw", 0.0)),
		task.get("size", Vector3.ONE),
		String(task.get("group", "streamed_prison_prop")),
		bool(task.get("solid", true)), String(task.get("type", "")))


func _spawn_region_props(parent: Node3D, data: Dictionary) -> void:
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	for value in data.get("region_props", []):
		_spawn_region_prop(parent, coord, value)


func _spawn_region_prop(parent: Node3D, coord: Vector3i, prop: Dictionary) -> void:
	var type := String(prop.get("type", ""))
	if not PropModelCatalog.has_model(type):
		return
	if PropModelCatalog.is_room_door(type):
		_spawn_room_door(parent, coord, prop, type)
		return
	var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
	var prop_y := PropModelCatalog.visual_y(type, WALL_HEIGHT,
		float(prop.get("mount_y", 0.0)))
	var mount_offset: Vector2 = prop.get("mount_offset", Vector2.ZERO) \
		+ prop.get("placement_offset", Vector2.ZERO)
	_spawn_authored_prop(parent, PropModelCatalog.model_path(type,
		String(prop.get("id", "")), String(prop.get("room_id", ""))),
		Vector3(cell.x + .5 + mount_offset.x,
			prop_y, cell.y + .5 + mount_offset.y),
		float(prop.get("yaw", 0.0)), prop.get("blocker_size", Vector3.ONE),
		"streamed_region_prop", bool(prop.get("solid", true)), type)
	_spawn_fixture_light(parent, type, Vector3(cell.x + .5 + mount_offset.x,
		prop_y, cell.y + .5 + mount_offset.y))
	if type in ["emberBrazier", "magmaCrystalCluster"]:
		var light := OmniLight3D.new()
		light.position = Vector3(cell.x + .5, 1.0, cell.y + .5)
		light.light_color = Color("ff6b35")
		light.light_energy = .72
		light.omni_range = 4.5
		parent.add_child(light)


func _spawn_fixture_light(parent: Node3D, prop_type: String, at: Vector3) -> void:
	var profile := PropModelCatalog.light_profile(prop_type)
	if profile.is_empty():
		return
	# Per-chunk cap prevents authored furnishing from multiplying shadowless
	# point lights until streamed generation becomes a frame-time spike.
	var count := int(parent.get_meta("fixture_light_count", 0))
	if count >= 4:
		return
	parent.set_meta("fixture_light_count", count + 1)
	var light := OmniLight3D.new()
	light.name = "FixtureLight_%s_%d" % [prop_type, count]
	light.position = at + Vector3.UP * float(profile.get("height", .5))
	light.light_color = profile.get("color", Color.WHITE)
	light.light_energy = float(profile.get("energy", .4))
	light.omni_range = float(profile.get("range", 3.5))
	light.shadow_enabled = false
	light.visible = _all_lights_enabled
	parent.add_child(light)


func _spawn_room_door(parent: Node3D, coord: Vector3i,
		prop: Dictionary, prop_type: String) -> void:
	var door_id := String(prop.get("id", ""))
	if door_id.is_empty():
		return
	var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
	var placement_offset: Vector2 = prop.get("placement_offset", Vector2.ZERO)
	var status := world_state.room_door_status(door_id)
	var door := RouteInteractable3D.new()
	door.name = "RoomDoor_%s" % door_id.replace(":", "_")
	door.position = Vector3(cell.x + .5 + placement_offset.x, 0.0,
		cell.y + .5 + placement_offset.y)
	door.rotation.y = float(prop.get("yaw", 0.0))
	door.source_cell = Vector2i(
		coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y)
	var requester := door_requester.bind(door_id) if door_requester.is_valid() \
		else Callable()
	door.configure_room_door(door_id, PropModelCatalog.model_path(prop_type,
		door_id), bool(status.get("open", false)),
		bool(status.get("broken", false)), requester,
		int(prop.get("door_span", 1)))
	parent.add_child(door)
	_door_nodes[door_id] = door


func apply_room_door_state(door_id: String, open: bool, broken: bool) -> bool:
	var changed := world_state.apply_room_door_state(door_id, open, broken)
	var door := _door_nodes.get(door_id) as RouteInteractable3D
	if door != null and is_instance_valid(door):
		door.apply_room_door_state(open, broken)
	return changed


func room_doors_on_level(level: int) -> Array[RouteInteractable3D]:
	var result: Array[RouteInteractable3D] = []
	for door_value in _door_nodes.values():
		var door := door_value as RouteInteractable3D
		if door != null and is_instance_valid(door) \
				and snapped_level_for_world_y(door.global_position.y) == level:
			result.append(door)
	return result


func _spawn_authored_prop(parent: Node3D, path: String, at: Vector3,
		yaw: float, blocker_size: Vector3,
		group_name: String = "streamed_prison_prop", solid: bool = true,
		prop_type: String = "") -> void:
	var visual := ModelSlot.instantiate_prop(path, prop_type)
	if visual == null:
		return
	var visual_at := at
	var visual_bounds := ModelSlot.combined_local_bounds(visual)
	if not PropModelCatalog.is_wall_mounted(prop_type) \
			and not PropModelCatalog.is_ceiling_mounted(prop_type) \
			and visual_bounds.size.length_squared() > 0.0:
		# Preview-friendly centre pivots buried half of couches, chairs and beds
		# below the GridMap. Seat every ordinary prop on its lowest mesh point.
		visual_at.y -= visual_bounds.position.y
	RefLook.grade_prop(visual)
	visual.position = visual_at
	visual.rotation.y = PropModelCatalog.authored_visual_yaw(yaw)
	visual.set_meta("streamed_prop_type", prop_type)
	visual.set_meta("streamed_prop_bounds", visual_bounds)
	visual.add_to_group(group_name)
	parent.add_child(visual)
	if PropModelCatalog.is_empty_frame(prop_type):
		_add_blank_frame_canvas(visual, prop_type)
	if prop_type == "carouselCenterpiece":
		_animated_activity_props.append(visual)
	if PropModelCatalog.is_floor_dressing(prop_type):
		ModelSlot.keep_floor_dressing_visible(visual)
	var furniture_action := PropModelCatalog.interaction_for(prop_type)
	if furniture_action == "mirror":
		_spawn_mirror_surface(parent, at, yaw)
	if not furniture_action.is_empty():
		var furniture := RouteInteractable3D.new()
		furniture.name = "Furniture_%s" % prop_type
		furniture.kind = RouteInteractable3D.Kind.FURNITURE
		furniture.configure_furniture(furniture_action)
		furniture.position = at + Vector3.UP * (.48 if furniture_action == "lay" else .03)
		furniture.rotation.y = yaw
		parent.add_child(furniture)
	if not solid:
		return
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = blocker_size
	collision.shape = shape
	collision.position = at + Vector3.UP * (blocker_size.y * .5)
	collision.rotation.y = yaw
	body.add_child(collision)
	parent.add_child(body)


func _add_blank_frame_canvas(frame: Node3D, prop_type: String) -> void:
	# The original "empty" frame meshes intentionally had no centre surface,
	# which made them read as holes in the wall at runtime. Add a small, flat,
	# double-sided white canvas without changing the authored frame geometry.
	# Keeping it as a child also makes the result deterministic for every peer.
	var canvas := MeshInstance3D.new()
	canvas.name = "BlankWhiteCanvas"
	var quad := QuadMesh.new()
	match prop_type:
		"normalPictureFrameEmpty":
			quad.size = Vector2(.58, .70)
		"normalPaintingFrameEmpty":
			quad.size = Vector2(1.02, 1.28)
		"luxuryPictureFrameEmpty", "gothicPictureFrameEmpty":
			quad.size = Vector2(.62, .74)
		_:
			quad.size = Vector2(1.04, 1.30)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f4f4f1")
	material.roughness = .86
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	canvas.mesh = quad
	# Frame origins place the centre opening around this height. The small
	# forward offset prevents depth fighting with the inner trim.
	canvas.position = Vector3(0.0, 1.38, .066)
	frame.add_child(canvas)


func _build_shared_mirror() -> void:
	_mirror_viewport = SubViewport.new()
	_mirror_viewport.name = "SharedMirrorViewport"
	_mirror_viewport.size = Vector2i(192, 192)
	_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mirror_viewport.world_3d = get_viewport().world_3d
	add_child(_mirror_viewport)
	_mirror_camera = Camera3D.new()
	_mirror_camera.name = "MirrorCamera"
	# Reflective quads live on layer 2, preventing feedback recursion.
	_mirror_camera.cull_mask = 1
	_mirror_viewport.add_child(_mirror_camera)


func _spawn_mirror_surface(parent: Node3D, at: Vector3, yaw: float) -> void:
	if _mirror_viewport == null:
		return
	var surface := MeshInstance3D.new()
	surface.name = "WorkingMirrorSurface"
	var quad := QuadMesh.new()
	quad.size = Vector2(.82, 1.08)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _mirror_viewport.get_texture()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	surface.mesh = quad
	surface.position = at + Vector3.UP * 1.22
	surface.rotation.y = yaw
	surface.layers = 2
	surface.visible = false
	parent.add_child(surface)
	_mirror_surfaces.append(surface)


func _update_shared_mirror(delta: float) -> void:
	_mirror_refresh_elapsed += delta
	if _mirror_refresh_elapsed < .10 or tracked_player == null \
			or _mirror_camera == null:
		return
	_mirror_refresh_elapsed = 0.0
	var source := tracked_player.active_camera()
	if source == null:
		return
	var chosen: MeshInstance3D
	var chosen_distance := 5.0
	# Typed object arrays cannot erase an already-freed object by value. Walk
	# backwards and remove by index so chunk eviction is safe between frames.
	for index in range(_mirror_surfaces.size() - 1, -1, -1):
		var surface := _mirror_surfaces[index]
		if not is_instance_valid(surface):
			_mirror_surfaces.remove_at(index)
			continue
		surface.visible = false
		var distance := source.global_position.distance_to(surface.global_position)
		if distance < chosen_distance:
			chosen_distance = distance
			chosen = surface
	if chosen == null:
		_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	chosen.visible = true
	var plane_point := chosen.global_position
	var normal := -chosen.global_basis.z.normalized()
	if (source.global_position - plane_point).dot(normal) < 0.0:
		normal = -normal
	var reflected_position := _reflect_point(source.global_position, plane_point, normal)
	var source_forward := -source.global_basis.z
	var source_up := source.global_basis.y
	var reflected_forward := source_forward - 2.0 * normal * source_forward.dot(normal)
	var reflected_up := source_up - 2.0 * normal * source_up.dot(normal)
	_mirror_camera.global_position = reflected_position
	_mirror_camera.fov = source.fov
	_mirror_camera.look_at(reflected_position + reflected_forward, reflected_up)
	_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


static func _reflect_point(point: Vector3, plane_point: Vector3,
		normal: Vector3) -> Vector3:
	return point - 2.0 * normal * (point - plane_point).dot(normal)


func _spawn_safe_room_light(parent: Node3D) -> void:
	var light := OmniLight3D.new()
	light.name = "CheckpointLight"
	light.position = Vector3(StreamedRouteGenerator.CHUNK_SIZE * .5,
		2.35, StreamedRouteGenerator.CHUNK_SIZE * .5)
	light.light_color = Color("85d6ad")
	# Bright enough to identify a checkpoint, dim enough that the player's
	# white flashlight remains readable inside the spawn/safe-room wash.
	light.light_energy = .82
	light.omni_range = 8.0
	parent.add_child(light)


func _spawn_start_marker(parent: Node3D) -> void:
	var center := StreamedRouteGenerator.CHUNK_SIZE / 2
	var marker := RouteInteractable3D.new()
	marker.name = "StartingSafeZoneMarker"
	marker.kind = RouteInteractable3D.Kind.SAFE_ZONE
	marker.prompt_text = "REST AT STARTING SAFE ZONE"
	marker.source_cell = Vector2i(center, center)
	marker.position = Vector3(center + .5, .04, center + .5)
	marker.add_to_group("streamed_spawn_marker")
	parent.add_child(marker)


func _spawn_fixtures(parent: Node3D, data: Dictionary) -> void:
	for fixture_value in data.get("fixtures", []):
		_spawn_fixture(parent, data, fixture_value)


func _spawn_fixture(parent: Node3D, data: Dictionary, fixture: Dictionary) -> void:
	var fixture_kind := String(fixture.get("kind", ""))
	if fixture_kind not in ["hiding_spot", "vent"]:
		return
	var entity_id := String(fixture.get("id", ""))
	if fixture_kind == "hiding_spot" and not entity_id.is_empty() \
			and not world_state.pickup_available(entity_id):
		return
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	var cell: Vector2i = fixture.get("cell", Vector2i.ZERO)
	var spot := RouteInteractable3D.new()
	spot.name = "%s_%s" % [fixture_kind.to_pascal_case(), entity_id.replace(":", "_")]
	spot.kind = RouteInteractable3D.Kind.VENT if fixture_kind == "vent" \
		else RouteInteractable3D.Kind.HIDING_SPOT
	spot.prompt_text = "ENTER VENT" if fixture_kind == "vent" else "HIDE"
	spot.vent_id = entity_id if fixture_kind == "vent" else ""
	spot.source_cell = Vector2i(
		coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y)
	spot.position = Vector3(cell.x + .5, .04, cell.y + .5)
	spot.rotation.y = float(fixture.get("yaw", 0.0))
	spot.add_to_group("streamed_vent" if fixture_kind == "vent" \
		else "streamed_hiding_spot")
	if fixture_kind == "hiding_spot":
		spot.changed.connect(func(event: Dictionary) -> void:
			if String(event.get("what", "")) == "hiding_disabled" and not entity_id.is_empty():
				if bool(event.get("disabled", false)):
					world_state.claim_pickup(entity_id)
				else:
					world_state.claimed_pickups.erase(entity_id)
		)
	parent.add_child(spot)
	if not entity_id.is_empty():
		_fixture_nodes[entity_id] = spot


func _spawn_pickups(parent: Node3D, data: Dictionary) -> void:
	for pickup_value in data.get("pickups", []):
		_spawn_pickup(parent, data, pickup_value)


func _spawn_pickup(parent: Node3D, data: Dictionary,
		pickup_data: Dictionary) -> void:
	var entity_id := String(pickup_data.get("id", ""))
	var kind := String(pickup_data.get("kind", "tool"))
	var repairable_relay := kind == "relay" \
		and world_state.relay_sabotaged(entity_id)
	if not world_state.pickup_available(entity_id) and not repairable_relay:
		return
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	var cell: Vector2i = pickup_data.get("cell", Vector2i.ZERO)
	var pickup := RouteInteractable3D.new()
	pickup.name = "Pickup_%s" % entity_id.replace(":", "_")
	match kind:
		"relay":
			pickup.kind = RouteInteractable3D.Kind.RELAY
			pickup.prompt_text = "RECOVER SIGNAL RELAY"
		"battery":
			pickup.kind = RouteInteractable3D.Kind.BATTERY
			pickup.prompt_text = "COLLECT BATTERY"
		"coin":
			pickup.kind = RouteInteractable3D.Kind.COIN
			pickup.prompt_text = "COLLECT COINS"
		_:
			pickup.kind = RouteInteractable3D.Kind.TOOL_PICKUP
	pickup.source_cell = Vector2i(
		coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y)
	pickup.position = Vector3(cell.x + .5, .04, cell.y + .5)
	pickup.set_meta("streamed_entity_id", entity_id)
	if pickup_requester.is_valid():
		pickup.activation_override = pickup_requester.bind(entity_id, kind,
			String(pickup_data.get("item", "")))
		pickup.changed.connect(func(event: Dictionary) -> void:
			if String(event.get("what", "")) == "sabotage" \
					and not bool(event.get("sabotaged", true)):
				pickup_requester.call(tracked_player, entity_id, "relay", ""))
	parent.add_child(pickup)
	if repairable_relay:
		pickup.completed = true
		pickup.sabotaged = true
		pickup.call_deferred("_refresh_visual")
	if kind in ["tool", "backpack"]:
		pickup.configure_tool_pickup(String(pickup_data.get("item", "")))
	_pickup_nodes[entity_id] = pickup


func _collect_taken_pickups() -> void:
	if pickup_requester.is_valid():
		return
	for entity_id_value in _pickup_nodes.keys().duplicate():
		var entity_id := String(entity_id_value)
		var pickup := _pickup_nodes.get(entity_id) as RouteInteractable3D
		if pickup == null or not is_instance_valid(pickup):
			_pickup_nodes.erase(entity_id)
			continue
		if pickup.completed and world_state.claim_pickup(entity_id):
			pickup_claimed.emit(entity_id)
			_pickup_nodes.erase(entity_id)


func apply_pickup_claim(entity_id: String) -> bool:
	if not world_state.claim_pickup(entity_id):
		return false
	var pickup := _pickup_nodes.get(entity_id) as RouteInteractable3D
	if pickup != null and is_instance_valid(pickup):
		pickup.completed = true
		pickup.queue_free()
	_pickup_nodes.erase(entity_id)
	pickup_claimed.emit(entity_id)
	return true


func refresh_mutations() -> void:
	# Rebuild only the bounded local window after a late-join snapshot. The
	# deterministic base stays identical; claimed entities are filtered through
	# StreamedWorldState as chunks return.
	for coord_value in _loaded.keys().duplicate():
		var coord: Vector3i = coord_value
		_unload_chunk(coord)
	_last_player_chunk = Vector3i(999999, 999999, 999999)
	_refresh_stream(true)


func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var floor_texture := load(FLOOR_TEXTURE) as Texture2D
	_add_scene_item(library, 1, FLOOR_TILE_SCENE, floor_texture, Color("77756d"),
		.88, false, Vector3.ONE,
		# GridMap cell Y=1 contributes one metre. Place the ceiling below the
		# next floor's downward slab instead of inside it:
		# ceiling top = LEVEL_HEIGHT - SLAB - CEILING_INSET.
		Vector3(0.0, LEVEL_HEIGHT - 1.0 - SLAB * 1.5 - CEILING_INSET, 0.0))
	var next_id := 2
	for region in REGION_COLORS:
		var region_floor_texture := load(REGION_FLOOR_TEXTURE % region) as Texture2D
		var region_wall_texture := load(REGION_WALL_TEXTURE % region) as Texture2D
		if region_floor_texture == null:
			region_floor_texture = floor_texture
		if region_wall_texture == null:
			region_wall_texture = load(WALL_TEXTURE) as Texture2D
		_add_scene_item(library, next_id, FLOOR_TILE_SCENE, region_floor_texture,
			REGION_COLORS[region], .88, true, Vector3.ONE, Vector3(0.0, -SLAB * .5, 0.0))
		_floor_items[region] = next_id
		next_id += 1
		var full_wall_id := next_id
		_add_box_item(library, full_wall_id,
			Vector3(1.0, WALL_HEIGHT, 1.0),
			Vector3(0.0, WALL_HEIGHT * .5, 0.0),
			_material(region_wall_texture, REGION_WALL_COLORS[region], Vector3(1.0, WALL_HEIGHT, 1.0)),
			true)
		next_id += 1
		_wall_items[region] = {"full": full_wall_id}
	_safe_floor_item = next_id
	_add_scene_item(library, next_id, FLOOR_TILE_SCENE, floor_texture, Color("5f9b78"),
		.88, true, Vector3.ONE, Vector3(0.0, -SLAB * .5, 0.0))
	next_id += 1
	next_id = _add_ref_items(library, next_id)
	return library


## RefLook surfaces: one library item per painted floor / wall / ceiling kind.
func _add_ref_items(library: MeshLibrary, first_id: int) -> int:
	var next_id := first_id
	for kind in RefTextures.FLOOR_PAINTERS:
		_add_scene_item_material(library, next_id, FLOOR_TILE_SCENE,
			RefTextures.material("floor", kind), true, Vector3.ONE,
			Vector3(0.0, -SLAB * .5, 0.0))
		_ref_floor_items[kind] = next_id
		next_id += 1
	for kind in RefTextures.CEILING_PAINTERS:
		_add_scene_item_material(library, next_id, FLOOR_TILE_SCENE,
			RefTextures.material("ceiling", kind), false, Vector3.ONE,
			Vector3(0.0, LEVEL_HEIGHT - 1.0 - SLAB * 1.5 - CEILING_INSET, 0.0))
		_ref_ceiling_items[kind] = next_id
		next_id += 1
	var wall_mesh := _wall_mesh()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, WALL_HEIGHT, 1.0)
	var offset := Vector3(0.0, WALL_HEIGHT * .5, 0.0)
	for kind in RefTextures.WALL_PAINTERS:
		var mesh := wall_mesh.duplicate() as ArrayMesh
		mesh.surface_set_material(0, RefTextures.material("wall", kind))
		library.create_item(next_id)
		library.set_item_mesh(next_id, mesh)
		library.set_item_mesh_transform(next_id, Transform3D(Basis.IDENTITY, offset))
		library.set_item_shapes(next_id, [shape, Transform3D(Basis.IDENTITY, offset)])
		_ref_wall_items[kind] = next_id
		next_id += 1
	return next_id


## A wall block with a full 0..1 UV on every side face (BoxMesh splits one
## texture across its six faces, which cannot carry a one-storey wall texture).
static func _wall_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := WALL_HEIGHT
	var corners := [Vector3(-.5, -h * .5, -.5), Vector3(.5, -h * .5, -.5),
		Vector3(.5, -h * .5, .5), Vector3(-.5, -h * .5, .5)]
	for side in 4:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var normal := (b - a).cross(Vector3.UP).normalized()
		var quad := [[a + Vector3(0, h, 0), Vector2(0, 0)], [b + Vector3(0, h, 0), Vector2(1, 0)],
			[b, Vector2(1, 1)], [a, Vector2(0, 1)]]
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_normal(normal)
			st.set_uv(quad[index][1])
			st.add_vertex(quad[index][0])
	var top_a := Vector3(-.5, h * .5, -.5)
	for index in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(.0, .0))
		st.add_vertex(top_a + Vector3(index[0], 0, index[1]))
	return st.commit()


static func _add_scene_item_material(library: MeshLibrary, id: int,
		scene_path: String, material: Material, solid: bool, scale: Vector3,
		offset: Vector3) -> void:
	var item := ModelSlot.load_gridmap_item(scene_path)
	var mesh := item.get("mesh") as Mesh
	if mesh == null:
		push_warning("StreamedFacilityView3D: could not load structural item %s" % scene_path)
		return
	mesh = mesh.duplicate()
	for surface in mesh.get_surface_count():
		mesh.surface_set_material(surface, material)
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	var mesh_transform := (item.get("mesh_transform", Transform3D.IDENTITY) as Transform3D).scaled_local(scale)
	mesh_transform.origin += offset
	library.set_item_mesh_transform(id, mesh_transform)
	if solid:
		var shape := item.get("shape") as Shape3D
		if shape == null:
			shape = BoxShape3D.new()
			(shape as BoxShape3D).size = Vector3(1.0, SLAB, 1.0)
		else:
			shape = shape.duplicate()
		var shape_transform := (item.get("shape_transform",
			Transform3D.IDENTITY) as Transform3D).scaled_local(scale)
		shape_transform.origin += offset
		library.set_item_shapes(id, [shape, shape_transform])


static func _material(texture: Texture2D, color: Color,
		repeat: Vector3) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = color
	# Pure nearest sampling crawls into vertical moire bands as a detailed wall
	# recedes or the camera turns. Nearest anisotropic mipmaps preserve the
	# blocky close-up look while stabilizing oblique/far surfaces in motion.
	material.texture_filter = \
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale = repeat
	material.roughness = .88
	return material


static func _add_box_item(library: MeshLibrary, id: int, size: Vector3,
		offset: Vector3, material: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	if material != null:
		mesh.material = material
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	var mesh_transform := Transform3D(Basis.IDENTITY, offset)
	library.set_item_mesh_transform(id, mesh_transform)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		library.set_item_shapes(id, [shape, Transform3D(Basis.IDENTITY, offset)])


static func _add_scene_item(library: MeshLibrary, id: int, scene_path: String,
		texture: Texture2D, color: Color, roughness: float, solid: bool,
		scale: Vector3, offset: Vector3) -> void:
	var item := ModelSlot.load_gridmap_item(scene_path)
	var mesh := item.get("mesh") as Mesh
	if mesh == null:
		push_warning("StreamedFacilityView3D: could not load structural item %s" % scene_path)
		return
	mesh = mesh.duplicate()
	_apply_gridmap_style(mesh, texture, color, roughness)
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	var mesh_transform := (item.get("mesh_transform", Transform3D.IDENTITY) as Transform3D).scaled_local(scale)
	mesh_transform.origin += offset
	library.set_item_mesh_transform(id, mesh_transform)
	if solid:
		var shape := item.get("shape") as Shape3D
		if shape == null:
			shape = BoxShape3D.new()
			(shape as BoxShape3D).size = Vector3(1.0, WALL_HEIGHT, 1.0) \
				if scene_path == WALL_BLOCK_SCENE else Vector3(1.0, SLAB, 1.0)
		else:
			shape = shape.duplicate()
		var shape_transform := (item.get("shape_transform",
			Transform3D.IDENTITY) as Transform3D).scaled_local(scale)
		shape_transform.origin += offset
		library.set_item_shapes(id, [shape, shape_transform])


static func _apply_gridmap_style(mesh: Mesh, texture: Texture2D, color: Color,
		roughness: float) -> void:
	if mesh == null:
		return
	for surface in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface)
		var material := StandardMaterial3D.new()
		if source is StandardMaterial3D:
			material = (source as StandardMaterial3D).duplicate()
		material.albedo_texture = texture
		material.albedo_color = color
		material.texture_filter = \
			BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
		material.roughness = roughness
		mesh.surface_set_material(surface, material)


static func _add_box(library: MeshLibrary, id: int, size: Vector3,
		offset: Vector3, material: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	var placement := Transform3D(Basis.IDENTITY, offset)
	library.set_item_mesh_transform(id, placement)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		library.set_item_shapes(id, [shape, placement])
