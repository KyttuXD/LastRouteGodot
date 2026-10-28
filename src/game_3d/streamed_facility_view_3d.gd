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
## Initial loads, teleports and level changes build the chunks around the runner
## immediately (see IMMEDIATE_MARGIN); the far part of the window streams.
const STREAM_JOBS_PER_FRAME := 1
const STREAM_CELLS_PER_FRAME := 256
## Streaming work per frame is bounded by time, not by a job count: build steps run until this budget is spent (at least
## one step always runs, so the queue never stalls). Cell batches check the clock every few cells.
const STREAM_BUDGET_MS := 4.0
const STREAM_BUDGET_PER_QUEUED_MS := 1.0
const STREAM_BUDGET_MAX_MS := 9.0
const STREAM_MIN_CELLS := 32
## Teleports, level changes and the first load build synchronously only the chunk under the runner and chunks closer
## than this to it; the rest of the window streams in over the next frames instead of freezing the game.
const IMMEDIATE_MARGIN := 12.0

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
const WALL_HEIGHT := 4.0
## Every wall cell remains a full 1m cube/block so streamed rooms do not
## create slab-like collision gaps or elongated wall seams between chunks.
const LEVEL_TRANSITION_MARGIN := 0.35
## Sewer wall colliders: the storey below the maze, up to the underside of the
## maze's floor slab (which occupies -SLAB..0 of level 0).
const SEWER_WALL_HEIGHT := LEVEL_HEIGHT - SLAB
## Channel railings: height and inset from the walkway edge.
const RAIL_HEIGHT := 1.0
const RAIL_INSET := 0.06
## The channel collider rises this far above the walkways (over the railings).
const CHANNEL_BLOCK_TOP := 1.2
## Ramp tunnels: the slope's collider thickness and its painted floor.
const RAMP_THICKNESS := 0.3
const RAMP_FLOOR_KIND := "concrete1"
## The falls: rough stone on the drop's cliffs, and how far the roar carries.
const CLIFF_WALL_KIND := "stone1"
const FALLS_SOUND_RANGE := 28.0
const SEWER_FALLS_SHADER := preload("res://src/look/sewer_falls.gdshader")

const SEWER_WATER_SHADER := preload("res://src/look/sewer_water.gdshader")
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
	"hospital": Color("b9cfc6"),
	"lab": Color("aebfc6"),
	"greenhouse": Color("a8784e"),
	"mall": Color("c9b8a2"),
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
	"hospital": Color("7fa39a"),
	"lab": Color("8fa8b2"),
	"greenhouse": Color("4f7a4a"),
	"mall": Color("b08a6a"),
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
var _col_floor_item := -1
var _col_wall_item := -1
var _col_sewer_wall_item := -1
var _col_channel_item := -1
var _loaded := {}
## Chunks of the storey the runner just left by a ladder (the 3x3 around the shaft): hidden, lights off, physics
## disabled, but kept built and registered, so climbing back revives them in a frame instead of rebuilding eight
## chunks (each ladder trip used to rebuild the whole other level). Freed once the runner walks out of that 3x3.
var _dormant := {}
var _dormant_data := {}
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
var _stream_deadline_usec := 0
var _prefetching := {}
## Prop scenes stay loaded once streamed (they are shared, small): unloading a chunk used to drop the last reference and
## the next chunk re-read the GLB from disk on the main thread.
static var _scene_keep := {}
## Chunk generation (~30 ms a chunk) runs on a WorkerThreadPool task with a same-seed generator copy; the main thread
## only adopts finished dictionaries. Builds wait for their chunk and its seam neighbours to be ready.
var _gen_worker: StreamedRouteGenerator
var _gen_task := -1
var _gen_task_coords: Array[Vector3i] = []
var _gen_task_results := {}
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
	generator.public_route = RoomState.public_route
	_gen_worker = generator.make_worker_copy()
	tracked_player = player
	world_state = state if state != null else StreamedWorldState.new()
	_tracked_level = snapped_level_for_world_y(
		tracked_player.global_position.y if tracked_player != null else 0.0)
	_refresh_stream(true)


func _exit_tree() -> void:
	if _gen_task != -1:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1


func clear() -> void:
	if _gen_task != -1:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
	_gen_task_results = {}
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
	for node_value in _dormant.values():
		if node_value != null and is_instance_valid(node_value):
			(node_value as Node).queue_free()
	_dormant.clear()
	_dormant_data.clear()
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


## The route is one maze level (0) over the sewer layer (-1). The runner is in
## the sewer once its feet are more than half a storey below the maze floor;
## the hysteresis margin keeps a ladder climb from flickering between the two.
static func snapped_level_for_world_y(world_y: float) -> int:
	return clampi(roundi(world_y / LEVEL_HEIGHT), StreamedRouteGenerator.INFERNO_LEVEL, 0)


## The level stays put until the runner is more than half a storey plus the
## margin away from its floor, so a ladder or ramp never flickers between two.
static func hysteresis_level_for_world_y(world_y: float, current_level_hint: int) -> int:
	var floor_y := float(current_level_hint) * LEVEL_HEIGHT
	if absf(world_y - floor_y) <= LEVEL_HEIGHT * .5 + LEVEL_TRANSITION_MARGIN:
		return current_level_hint
	return snapped_level_for_world_y(world_y)


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


## Every loaded chunk's generated data, for the admin collision overlay.
## True while chunks are queued or being assembled over several frames (benchmarks tag these frames).
func take_frame_stream_cost() -> Array:
	var out := [frame_stream_ms, frame_stream_label]
	frame_stream_ms = 0.0
	frame_stream_label = ""
	_frame_stream_peak = 0.0
	return out


func is_streaming() -> bool:
	return not (_pending_loads.is_empty() and _pending_unloads.is_empty() and _active_build.is_empty())


func loaded_chunk_data() -> Array:
	var out := []
	for coord_value in _loaded.keys():
		var coord: Vector3i = coord_value
		if _chunk_data.has(coord):
			out.append({"coord": coord, "data": _chunk_data[coord]})
	return out


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
	_prestream_ladder_destination()
	_drain_stream_queue()
	_collect_taken_pickups()
	_update_shared_mirror(_delta)
	for index in range(_animated_activity_props.size() - 1, -1, -1):
		var activity := _animated_activity_props[index]
		if activity == null or not is_instance_valid(activity):
			_animated_activity_props.remove_at(index)
		else:
			activity.rotate_y(_delta * .34)


## The chunks the stream window keeps around `center`. Subclasses (the City, OSM maps) override only this.
func _wanted_chunks(center: Vector3i) -> Dictionary:
	var wanted := {}
	for z in range(center.z - STREAM_RADIUS, center.z + STREAM_RADIUS + 1):
		for x in range(center.x - STREAM_RADIUS, center.x + STREAM_RADIUS + 1):
			var coord := Vector3i(x, center.y, z)
			if generator.is_chunk_allowed(coord):
				wanted[coord] = true
	# The far end of a ladder or ramp stays loaded while the runner is in a chunk
	# with one, so a shaft or a ramp tunnel never opens onto an unloaded level.
	# Chunks with no link keep the plain nine-chunk window.
	for link_value in generator.vertical_links(center):
		var link: Dictionary = link_value
		var far := int(LevelLink.other_end(link, center.y)["level"])
		var vertical := Vector3i(center.x, far, center.z)
		if generator.is_chunk_allowed(vertical):
			wanted[vertical] = true
	# You can see across the falls' drop between the two sewers: in a chunk with
	# falls the other level's chamber stays loaded.
	if (center.y == StreamedRouteGenerator.SEWER_LEVEL or center.y == StreamedRouteGenerator.LOWER_SEWER_LEVEL) \
			and not generator.sewer().falls_between(center.x, center.z).is_empty():
		var across := Vector3i(center.x, StreamedRouteGenerator.LOWER_SEWER_LEVEL \
			if center.y == StreamedRouteGenerator.SEWER_LEVEL else StreamedRouteGenerator.SEWER_LEVEL, center.z)
		wanted[across] = true
	return wanted


## Horizontal distance from the runner to a chunk's footprint (0 inside it).
func _distance_to_chunk(coord: Vector3i) -> float:
	if tracked_player == null:
		return 0.0
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)
	var local := tracked_player.global_position - global_position
	var dx := maxf(maxf(coord.x * size - local.x, local.x - (coord.x + 1) * size), 0.0)
	var dz := maxf(maxf(coord.z * size - local.z, local.z - (coord.z + 1) * size), 0.0)
	return sqrt(dx * dx + dz * dz)


func _refresh_stream(force: bool) -> void:
	var center := current_chunk_coord()
	if not force and center == _last_player_chunk:
		return
	var previous := _last_player_chunk
	_last_player_chunk = center
	var wanted := _wanted_chunks(center)
	var jump := force or previous.x == 999999 or previous.y != center.y \
		or absi(previous.x - center.x) > 1 or absi(previous.z - center.z) > 1
	var t_refresh := Time.get_ticks_usec()
	_pending_loads.clear()
	_pending_unloads.clear()
	if not _active_build.is_empty():
		var active_coord: Vector3i = _active_build.get("coord", Vector3i.ZERO)
		if not wanted.has(active_coord):
			_discard_active_build()
	_settle_dormant(center, wanted)
	for coord_value in wanted:
		var coord: Vector3i = coord_value
		if not _loaded.has(coord) and (_active_build.is_empty() \
				or _active_build.get("coord", Vector3i.ZERO) != coord):
			_pending_loads.append(coord)
	for coord_value in _loaded.keys().duplicate():
		var coord: Vector3i = coord_value
		if not wanted.has(coord):
			_pending_unloads.append(coord)
	# Nearest first; ties go to the chunk ahead of the runner's travel direction.
	var heading := Vector2(center.x - previous.x, center.z - previous.z) if previous.x != 999999 else Vector2.ZERO
	_pending_loads.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var da := _chunk_distance(a, center) * 4 - int(heading.dot(Vector2(a.x - center.x, a.z - center.z)))
		var db := _chunk_distance(b, center) * 4 - int(heading.dot(Vector2(b.x - center.x, b.z - center.z)))
		return da < db)
	_pending_unloads.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _chunk_distance(a, center) > _chunk_distance(b, center))
	_stream_queue_center = center
	if jump:
		# Build synchronously only what the runner stands in or could reach/see in the next moments (closer than
		# IMMEDIATE_MARGIN); the rest of the window streams in over the next frames instead of freezing the game.
		var urgent: Array[Vector3i] = []
		for coord in _pending_loads:
			# the floor above/below the runner (a ladder's other end) counts as under them
			if coord.x == center.x and coord.z == center.z or previous.x == 999999 and coord.y == center.y \
					or coord.y == center.y and _distance_to_chunk(coord) < IMMEDIATE_MARGIN:
				urgent.append(coord)
		if not urgent.is_empty():
			_discard_active_build()
			_generate_parallel(urgent)
			for coord in urgent:
				_pending_loads.erase(coord)
				_load_chunk(coord)
		while not _pending_unloads.is_empty():
			_unload_chunk(_pending_unloads.pop_front())
	for coord in _pending_loads:
		_prefetch_chunk(coord)
	_stream_completion_pending = not _pending_loads.is_empty() or not _pending_unloads.is_empty()
	_prof("refresh_immediate" if jump else "refresh", t_refresh)
	t_refresh = Time.get_ticks_usec()
	var data: Dictionary = _chunk_data.get(center,
		generator.chunk(center) if generator != null else {})
	chunk_changed.emit(center, data.duplicate(false))
	_prof("chunk_changed", t_refresh)


## While the runner is on a ladder (between the two storeys), the destination storey's chunks near the shaft join the
## stream queue, so they are built during the climb and the level change has nothing left to build synchronously.
var _prestreamed_for := Vector3i(999999, 999999, 999999)
func _prestream_ladder_destination() -> void:
	var y := tracked_player.global_position.y - global_position.y
	var on_ladder := y < -.6 and y > -LEVEL_HEIGHT + .6
	var center := _last_player_chunk
	if not on_ladder or center == _prestreamed_for or center.x == 999999:
		return
	_prestreamed_for = center
	var target_y := StreamedRouteGenerator.SEWER_LEVEL if center.y == 0 else 0
	for z in range(center.z - STREAM_RADIUS, center.z + STREAM_RADIUS + 1):
		for x in range(center.x - STREAM_RADIUS, center.x + STREAM_RADIUS + 1):
			var coord := Vector3i(x, target_y, z)
			if _loaded.has(coord) or _pending_loads.has(coord) or not generator.is_chunk_allowed(coord) \
					or _distance_to_chunk(coord) >= IMMEDIATE_MARGIN:
				continue
			if _dormant.has(coord):
				_revive(coord)
				continue
			_pending_loads.push_front(coord)
			_prefetch_chunk(coord)
			_stream_completion_pending = true


## Ladder trips: park the storey being left (around the shaft), revive a parked chunk the window wants again, and
## free parked chunks the runner has walked away from.
func _settle_dormant(center: Vector3i, wanted: Dictionary) -> void:
	for coord_value in _loaded.keys().duplicate():
		var coord: Vector3i = coord_value
		if not wanted.has(coord) and coord.y != center.y and _near_column(coord, center):
			_make_dormant(coord)
	for coord_value in _dormant.keys().duplicate():
		var coord: Vector3i = coord_value
		if wanted.has(coord):
			_revive(coord)
		elif not _near_column(coord, center):
			_free_dormant(coord)


static func _near_column(coord: Vector3i, center: Vector3i) -> bool:
	return absi(coord.x - center.x) <= STREAM_RADIUS and absi(coord.z - center.z) <= STREAM_RADIUS


func _make_dormant(coord: Vector3i) -> void:
	var root := _loaded.get(coord) as Node3D
	_loaded.erase(coord)
	if _lamp_field != null:
		_lamp_field.unregister(coord)
	if root == null:
		_chunk_data.erase(coord)
		return
	_dormant[coord] = root
	_dormant_data[coord] = _chunk_data.get(coord, {})
	_chunk_data.erase(coord)
	root.visible = false
	root.process_mode = Node.PROCESS_MODE_DISABLED
	root.remove_from_group("streamed_chunk")


func _revive(coord: Vector3i) -> void:
	var root := _dormant[coord] as Node3D
	_loaded[coord] = root
	_chunk_data[coord] = _dormant_data.get(coord, {})
	_dormant.erase(coord)
	_dormant_data.erase(coord)
	root.visible = true
	root.process_mode = Node.PROCESS_MODE_INHERIT
	root.add_to_group("streamed_chunk")
	if _lamp_field != null:
		_lamp_field.register(coord, root.get_meta("lamp_list", []))
	if not _all_lights_enabled:
		_set_lights_recursive(root, false)


func _free_dormant(coord: Vector3i) -> void:
	var root := _dormant.get(coord) as Node
	_dormant.erase(coord)
	_dormant_data.erase(coord)
	if root != null and is_instance_valid(root):
		_forget_chunk_entities(root)
		root.queue_free()


func dormant_chunk_count() -> int:
	return _dormant.size()


## Start background loads of the prop scenes a queued chunk will need, so its build never reads a GLB on the main thread.
func _prefetch_chunk(coord: Vector3i) -> void:
	if _gen_worker != null and not _chunk_generated(coord):
		return   # its props are prefetched once the worker has generated it (_adopt_generated)
	var data := generator.chunk(coord)
	for prop in data.get("region_props", []):
		var path := _region_prop_path(prop)
		if path.is_empty() or _scene_keep.has(path) or _prefetching.has(path):
			continue
		if ResourceLoader.has_cached(path):
			_scene_keep[path] = load(path)
		elif ResourceLoader.load_threaded_request(path, "PackedScene", true) == OK:
			_prefetching[path] = true


## The chunk itself plus the neighbours its edge cells read for seams (they look at level 0; see _build_structure_cell).
static func _generation_needs(coord: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = [coord]
	for step in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		out.append(Vector3i(coord.x + step.x, 0, coord.z + step.y))
	return out


func _chunk_generated(coord: Vector3i) -> bool:
	if _gen_worker == null:
		return true
	for need in _generation_needs(coord):
		if not generator.has_chunk_cached(need):
			return false
	return true


## Generate every chunk (and seam neighbour) `coords` need at once, one fresh same-seed generator per worker task.
func _generate_parallel(coords: Array[Vector3i]) -> void:
	if _gen_worker == null:
		return
	if _gen_task != -1:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
		for coord in _gen_task_results:
			generator.adopt_chunk(coord, _gen_task_results[coord])
		_gen_task_results = {}
	var needs: Array[Vector3i] = []
	for coord in coords:
		for need in _generation_needs(coord):
			if not generator.has_chunk_cached(need) and not needs.has(need):
				needs.append(need)
	if needs.size() < 2:
		return
	var results := []
	results.resize(needs.size())
	var maker := generator
	var group := WorkerThreadPool.add_group_task(func(index: int) -> void:
		results[index] = maker.make_worker_copy().chunk(needs[index]), needs.size(), -1, true, "chunk generation (jump)")
	WorkerThreadPool.wait_for_group_task_completion(group)
	for index in needs.size():
		generator.adopt_chunk(needs[index], results[index])


func _queue_generation() -> void:
	if _gen_worker == null:
		return
	if _gen_task != -1:
		if not WorkerThreadPool.is_task_completed(_gen_task):
			return
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
		for coord in _gen_task_results:
			generator.adopt_chunk(coord, _gen_task_results[coord])
		for coord in _gen_task_coords:
			if _pending_loads.has(coord):
				_prefetch_chunk(coord)
		_gen_task_results = {}
	var coords: Array[Vector3i] = []
	for coord in _pending_loads:
		for need in _generation_needs(coord):
			if not generator.has_chunk_cached(need) and not coords.has(need):
				coords.append(need)
	if coords.is_empty():
		return
	_gen_task_coords = coords
	var worker := _gen_worker
	var results := {}
	_gen_task_results = results
	_gen_task = WorkerThreadPool.add_task(func() -> void:
		for coord in coords:
			results[coord] = worker.chunk(coord), true, "chunk generation")


func _poll_prefetch() -> void:
	for path in _prefetching.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_scene_keep[path] = ResourceLoader.load_threaded_get(path)
		_prefetching.erase(path)


func _region_prop_path(prop: Dictionary) -> String:
	var type := String(prop.get("type", ""))
	if not PropModelCatalog.has_model(type):
		return ""
	return PropModelCatalog.model_path(type, String(prop.get("id", "")), String(prop.get("room_id", "")))


## A queued chunk's next prop waits (a frame at a time) while its scene is still loading in the background.
func _prop_waiting(prop: Dictionary) -> bool:
	var path := _region_prop_path(prop)
	if path.is_empty() or not _prefetching.has(path):
		return false
	_poll_prefetch()
	return _prefetching.has(path)


## End index of a structure cell batch: everything when immediate, else until the frame's stream budget is spent.
func _cell_batch_done(index: int, started: int, immediate: bool) -> bool:
	if immediate or index - started < STREAM_MIN_CELLS or index % 8 != 0:
		return false
	return Time.get_ticks_usec() >= _stream_deadline_usec


func _drain_stream_queue() -> void:
	if not _prefetching.is_empty():
		_poll_prefetch()
	if not _pending_loads.is_empty() or _gen_task != -1:
		_queue_generation()
	if _pending_loads.is_empty() and _pending_unloads.is_empty() \
			and _active_build.is_empty():
		return
	# A long queue (after a teleport) gets a little more time per frame so the window fills in seconds, not tens.
	var budget := minf(STREAM_BUDGET_MS + STREAM_BUDGET_PER_QUEUED_MS * _pending_loads.size(), STREAM_BUDGET_MAX_MS)
	_stream_deadline_usec = Time.get_ticks_usec() + int(budget * 1000.0)
	while true:
		# Never register new collision and retire an old physics island in the same
		# frame. Freeing first keeps the live server load bounded before the staged
		# replacement starts entering the tree.
		if not _pending_unloads.is_empty() and _active_build.is_empty():
			var tu := Time.get_ticks_usec()
			_unload_chunk(_pending_unloads.pop_front())
			_prof("unload", tu)
			break
		var t0 := Time.get_ticks_usec()
		if _active_build.is_empty() and not _pending_loads.is_empty():
			if not _chunk_generated(_pending_loads[0]):
				break   # the worker is still generating it
			_active_build = _create_chunk_build(_pending_loads.pop_front())
			_prof("create", t0)
			t0 = Time.get_ticks_usec()
		if _active_build.is_empty():
			break
		var phase := int(_active_build["phase"])
		var waiting := int(_active_build.get("prop_index", 0))
		if _advance_chunk_build(_active_build, false):
			_active_build = {}
		_prof("phase%d" % phase, t0)
		# Attaching the GridMap/surface registers whole meshes and colliders with the servers: one of those per frame.
		if phase in [1, 2] or (phase == 4 and int(_active_build.get("prop_index", -1)) == waiting) \
				or Time.get_ticks_usec() >= _stream_deadline_usec:
			break
	if _pending_loads.is_empty() and _pending_unloads.is_empty() \
			and _active_build.is_empty() \
			and _stream_completion_pending:
		_stream_completion_pending = false
		var tc := Time.get_ticks_usec()
		var data: Dictionary = _chunk_data.get(_stream_queue_center,
			generator.chunk(_stream_queue_center) if generator != null else {})
		chunk_changed.emit(_stream_queue_center, data.duplicate(false))
		_prof("chunk_changed_done", tc)


static var profile_stream := OS.get_environment("STREAM_PROFILE") != ""
## Streaming CPU spent this frame and the step that took longest (read and reset by tools/look/stream_bench.gd).
var frame_stream_ms := 0.0
var frame_stream_label := ""
var _frame_stream_peak := 0.0
func _prof(label: String, t0: int) -> void:
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	frame_stream_ms += ms
	if ms > _frame_stream_peak:
		_frame_stream_peak = ms
		frame_stream_label = label
	if profile_stream and ms > 4.0:
		print("PROF %s %.1f ms" % [label, ms])


static func _chunk_distance(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)


func _load_chunk(coord: Vector3i) -> void:
	var build := _create_chunk_build(coord)
	while not _advance_chunk_build(build, true):
		pass


## Chunk builds started since begin() (benchmarks count rebuilds of chunks that were just unloaded).
var chunk_builds := 0
func _create_chunk_build(coord: Vector3i) -> Dictionary:
	chunk_builds += 1
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
	var region := String(data.get("region", "maze"))
	var room_map := _room_type_map(data)
	var heights := RefLook.chunk_heights(data)
	var corridor_h := RefLook.corridor_height(region, coord)
	# Below the maze every storey is LEVEL_HEIGHT: tall Inferno halls stop under
	# the collector's floor instead of rising into the sewer above them.
	if coord.y < 0:
		var cap := LEVEL_HEIGHT - SLAB
		corridor_h = minf(corridor_h, cap)
		for cell_value in heights:
			heights[cell_value] = minf(float(heights[cell_value]), cap)
	var open_above := {}
	var falls: Dictionary = data.get("falls", {})
	if not falls.is_empty() and coord.y == StreamedRouteGenerator.LOWER_SEWER_LEVEL:
		var drop: Rect2i = falls["void"]
		for z in range(drop.position.y, drop.end.y):
			for x in range(drop.position.x, drop.end.x):
				open_above[Vector2i(x, z)] = true
				heights[Vector2i(x, z)] = LEVEL_HEIGHT
	var ramp_cells: Dictionary = data.get("ramp_cells", {})
	for cell_value in ramp_cells:
		# the lower end of a ramp tunnel has no ceiling of its own: it opens up to
		# the level above, so its walls run the full storey
		if not bool((ramp_cells[cell_value] as Dictionary)["upper"]):
			heights[cell_value] = LEVEL_HEIGHT
	root.set_meta("ref_region", region)
	root.set_meta("ref_heights", heights)
	root.set_meta("ref_corridor_h", corridor_h)
	var ceiling_voids := {}
	var floor_voids := {}
	var structural_voids := {}
	for cell_value in data.get("ceiling_voids", []):
		ceiling_voids[cell_value as Vector2i] = true
	for cell_value in data.get("floor_voids", []):
		floor_voids[cell_value as Vector2i] = true
	for cell_value in data.get("structural_voids", []):
		structural_voids[cell_value as Vector2i] = true
	var link_cells := {}
	if coord.y == 0 or coord.y == StreamedRouteGenerator.SEWER_LEVEL:
		for link_value in generator.sewer().links_for(coord):
			link_cells[LevelLink.cell_on(link_value, coord.y)] = link_value
	# The maze end of every ladder: its top section with grab hoops in the shaft,
	# and the manhole lid dragged aside or the floor grate swung up.
	var region_props: Array = data.get("region_props", [])
	if coord.y == 0 and not link_cells.is_empty():
		region_props = region_props.duplicate()
		for cell_value in link_cells:
			var link: Dictionary = link_cells[cell_value]
			var yaw := SewerRouteGenerator.wall_yaw(link.get("wall", Vector2i.ZERO))
			region_props.append({"id": "%s:TOP" % link["id"], "type": "sewerLadderTop", "cell": cell_value,
				"yaw": yaw, "solid": false})
			region_props.append({"id": "%s:COVER" % link["id"], "type": "sewerManhole" \
				if String(link.get("cover", "manhole")) == "manhole" else "sewerFloorGrate",
				"cell": cell_value, "yaw": yaw, "solid": false})
	return {
		"coord": coord,
		"region_props": region_props,
		"link_cells": link_cells,
		"open_above": open_above,
		"sewer_grid": data.get("sewer_grid", []),
		"data": data,
		"root": root,
		"grid": grid,
		"surface": RefSurfaceMesh.new(),
		"region": region,
		"floor_item": int(_floor_items.get(region, _floor_items["maze"])),
		"wall_items": _wall_items.get(region, _wall_items["maze"]),
		"ceiling_voids": ceiling_voids,
		"floor_voids": floor_voids,
		"structural_voids": structural_voids,
		"safe": bool(data.get("safe_room", false)),
		"style": RefLook.REGION_STYLE.get(region, RefLook.REGION_STYLE["maze"]),
		"room_map": room_map,
		"heights": heights,
		"corridor_h": corridor_h,
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
				var started := int(build["cell_index"])
				while int(build["cell_index"]) < total \
						and not _cell_batch_done(int(build["cell_index"]), started, immediate):
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
				var surface_node := MeshInstance3D.new()
				surface_node.name = "Surface"
				surface_node.mesh = (build["surface"] as RefSurfaceMesh).build(
					RefTextures.array_material("floor"), RefTextures.array_material("wall"))
				surface_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(surface_node)
				build["phase"] = 3
				if not immediate:
					return false
			3:
				_spawn_streamed_ceiling_lights(root, data)
				_spawn_shop_signs(root, data)
				if not (build["sewer_grid"] as Array).is_empty():
					_spawn_sewer_water(root, build["sewer_grid"])
				_spawn_ramps(root, data, (build["coord"] as Vector3i).y)
				_spawn_falls(root, data, (build["coord"] as Vector3i).y)
				build["decor"] = RefDecor.new(root, data, build["room_map"], build["heights"], build["corridor_h"])
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
				var region_props: Array = build["region_props"]
				var prison_tasks: Array = build["prison_tasks"]
				var prop_index := int(build["prop_index"])
				if prop_index < region_props.size():
					if not immediate and _prop_waiting(region_props[prop_index]):
						return false
					_spawn_region_prop(root, build["coord"], region_props[prop_index],
						PropModelCatalog.region_finish(String(data.get("region", ""))))
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
				root.set_meta("floor_kinds", build.get("floor_kinds", {}))
				if build["decor"] != null and _lamp_field != null:
					var lamp_list: Array = (build["decor"] as RefDecor).lamps + (root.get_meta("extra_lamps", []) as Array)
					root.set_meta("lamp_list", lamp_list)
					_lamp_field.register(coord, lamp_list)
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
	var surface := build["surface"] as RefSurfaceMesh
	var ceiling_kind := String((build["style"] as Dictionary)["ceiling"])
	var ramp_cells: Dictionary = data.get("ramp_cells", {})
	if ramp_cells.has(cell):
		_build_ramp_cell(build, cell, ramp_cells[cell])
		return
	if int(grid_data[z][x]) == 0:
		var height := _height_in(build, cell)
		var kind := _ref_floor_kind(build, x, z)
		if bool(build["safe"]):
			var center := StreamedRouteGenerator.CHUNK_SIZE / 2
			var edge: int = maxi(abs(x - center), abs(z - center))
			if edge == 0:
				kind = "safe_mark"
			elif edge <= 2:
				kind = "safe_plain"
			elif edge == 3:
				kind = "safe"
		# A bridge or plaza deck over a sewer channel: walkable at floor level (the
		# authored deck prop is the visible floor), with the channel's trench and
		# its water running underneath.
		var on_deck := _sewer_code(build, x, z) == SewerRouteGenerator.BRIDGE
		if on_deck:
			kind = "grate"
			_add_channel_trench(build, cell)
		grid.set_cell_item(Vector3i(x, 0, z), _col_floor_item)
		if not build.has("floor_kinds"):
			build["floor_kinds"] = {}
		(build["floor_kinds"] as Dictionary)[cell] = kind
		var link_here := (build["link_cells"] as Dictionary).has(cell)
		var coord_y := (build["coord"] as Vector3i).y
		# A ladder shaft: the maze keeps its walkable collider over the opening (the
		# climb owns the crossing) but draws no floor, and lines the shaft down to
		# the sewer ceiling; the sewer leaves its ceiling open under it.
		if on_deck:
			pass
		elif not (link_here and coord_y == 0):
			surface.add_floor(x, z, RefTextures.layer("floor", kind),
				RefTextures.params("floor", kind))
		else:
			_add_shaft_lining(build, cell)
		if not (link_here and coord_y == StreamedRouteGenerator.SEWER_LEVEL) \
				and not (build["open_above"] as Dictionary).has(cell):
			surface.add_ceiling(x, z, height, RefTextures.layer("floor", ceiling_kind),
				RefTextures.params("ceiling", ceiling_kind))
		# Where a taller room meets a lower cell (a doorway or corridor mouth) the
		# lower cell's ceiling stops short: close the gap above it with a lintel
		# face on the taller side.
		for step_value in RefDecor.DIRS:
			var step: Vector2i = step_value
			var nx: int = x + step.x
			var nz: int = z + step.y
			var outside := nx < 0 or nz < 0 or nx >= size or nz >= size
			if not outside and int(grid_data[nz][nx]) != 0:
				continue
			var neighbour_height := _seam_height(build, nx, nz) if outside \
				else _height_in(build, Vector2i(nx, nz))
			if outside:
				# only close the gap where the other chunk's cell is really open
				var other := generator.chunk(Vector3i(
					(build["coord"] as Vector3i).x + floori(float(nx) / size), (build["coord"] as Vector3i).y,
					(build["coord"] as Vector3i).z + floori(float(nz) / size)))
				if int((other["grid"] as Array)[posmod(nz, size)][posmod(nx, size)]) != 0:
					continue
			if neighbour_height < height - .01:
				var lintel_kind := _ref_wall_kind(build, nx, nz, x, z)
				surface.add_wall(nx, nz, -step, RefTextures.layer("wall", lintel_kind),
					RefTextures.params("wall", lintel_kind), height, neighbour_height, height)
	elif _sewer_code(build, x, z) == SewerRouteGenerator.WATER:
		# Open channel: a trench of deep water nobody enters. Its collider stands
		# from the bed to above the railing height, so runners and hunters stay on
		# the walkways and decks; the vault continues overhead.
		grid.set_cell_item(Vector3i(x, 0, z), _col_channel_item)
		_add_channel_trench(build, cell)
		if not (build["open_above"] as Dictionary).has(cell):
			surface.add_ceiling(x, z, _height_in(build, cell), RefTextures.layer("floor", ceiling_kind),
				RefTextures.params("ceiling", ceiling_kind))
	elif _sewer_code(build, x, z) == SewerRouteGenerator.FALL:
		# The drop to the collector: blocked to walk like the channels, the vault
		# overhead, and rough stone cliffs from the floor's edge down a full storey.
		grid.set_cell_item(Vector3i(x, 0, z), _col_channel_item)
		surface.add_ceiling(x, z, _height_in(build, cell), RefTextures.layer("floor", ceiling_kind),
			RefTextures.params("ceiling", ceiling_kind))
		for step_value in RefDecor.DIRS:
			var step: Vector2i = step_value
			var n := cell + step
			if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size \
					or _sewer_code(build, n.x, n.y) == SewerRouteGenerator.FALL:
				continue
			surface.add_wall(n.x, n.y, -step, RefTextures.layer("wall", CLIFF_WALL_KIND),
				RefTextures.params("wall", CLIFF_WALL_KIND), 0.0, -LEVEL_HEIGHT)
	else:
		# every level below the maze keeps its wall colliders inside its own storey
		grid.set_cell_item(Vector3i(x, 0, z), _col_sewer_wall_item \
			if (build["coord"] as Vector3i).y < 0 else _col_wall_item)
		for step_value in RefDecor.DIRS:
			var step: Vector2i = step_value
			var nx: int = x + step.x
			var nz: int = z + step.y
			# faces toward another chunk are emitted too; a hidden face is cheaper
			# than a missing one
			var face_height := float(build["corridor_h"])
			if nx >= 0 and nz >= 0 and nx < size and nz < size:
				# ramp tunnels, channels and the falls' drop are open space too, though the
				# grid keeps them off the walk graph
				var open_space := (data.get("ramp_cells", {}) as Dictionary).has(Vector2i(nx, nz)) \
					or _sewer_code(build, nx, nz) in [SewerRouteGenerator.WATER, SewerRouteGenerator.FALL]
				if int(grid_data[nz][nx]) != 0 and not open_space:
					continue
				face_height = _height_in(build, Vector2i(nx, nz))
			var wall_kind := _ref_wall_kind(build, x, z, nx, nz)
			surface.add_wall(x, z, step, RefTextures.layer("wall", wall_kind),
				RefTextures.params("wall", wall_kind), face_height)


static func _sewer_code(build: Dictionary, x: int, z: int) -> int:
	var sewer_grid: Array = build["sewer_grid"]
	return SewerRouteGenerator.DRY if sewer_grid.is_empty() else int(sewer_grid[z][x])


## One cell of a ramp tunnel. On its upper level: the vault overhead and the
## slope underfoot (no flat floor, no floor collider); on its lower level:
## nothing at all, the tunnel opening straight up to the level above. The
## slope's collider is built once per ramp (_spawn_ramps).
func _build_ramp_cell(build: Dictionary, cell: Vector2i, info: Dictionary) -> void:
	if not bool(info["upper"]):
		return
	var surface := build["surface"] as RefSurfaceMesh
	var ceiling_kind := String((build["style"] as Dictionary)["ceiling"])
	surface.add_ceiling(cell.x, cell.y, _height_in(build, cell), RefTextures.layer("floor", ceiling_kind),
		RefTextures.params("ceiling", ceiling_kind))
	var ramp: Dictionary = info["ramp"]
	var y0 := _ramp_surface_y(ramp, float(cell.x))
	var y1 := _ramp_surface_y(ramp, float(cell.x + 1))
	surface.add_quad_floor(Vector3(cell.x, y0, cell.y), Vector3(cell.x + 1, y1, cell.y),
		Vector3(cell.x + 1, y1, cell.y + 1), Vector3(cell.x, y0, cell.y + 1),
		RefTextures.layer("floor", RAMP_FLOOR_KIND), RefTextures.params("floor", RAMP_FLOOR_KIND))


## Height of a ramp's walking surface at chunk-local x, relative to its upper level's floor.
static func _ramp_surface_y(ramp: Dictionary, x: float) -> float:
	var top_x := float(ramp["top_x"])
	var bottom_x := float(ramp["bottom_x"])
	var t := clampf((x - top_x) / (bottom_x - top_x), 0.0, 1.0)
	return -LEVEL_HEIGHT * t


## The waterfall in a chunk with falls: on the first sewer the sheet of water
## pouring over the lip into the drop; on the collector the spray and mist where
## it lands in the cistern's pool. Both carry the loud looping roar.
func _spawn_falls(root: Node3D, data: Dictionary, level: int) -> void:
	var falls: Dictionary = data.get("falls", {})
	if falls.is_empty():
		return
	var lip := Vector3(float(falls["edge_x0"]) + 1.5, 0.0, float(falls["edge_z"]))
	if level == StreamedRouteGenerator.SEWER_LEVEL:
		var sheet := MeshInstance3D.new()
		sheet.name = "Waterfall"
		var quad := QuadMesh.new()
		quad.size = Vector2(3.0, LEVEL_HEIGHT)
		sheet.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = SEWER_FALLS_SHADER
		sheet.material_override = material
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# just past the lip, from the channel's surface down to the pool's
		sheet.position = Vector3(lip.x, SewerRouteGenerator.WATER_SURFACE - LEVEL_HEIGHT * .5,
			lip.z + (-.12 if bool(falls["north"]) else .12))
		root.add_child(sheet)
		_add_falls_sound(root, Vector3(lip.x, 0.0, lip.z))
	elif level == StreamedRouteGenerator.LOWER_SEWER_LEVEL:
		var mist := GPUParticles3D.new()
		mist.name = "FallsMist"
		mist.amount = 48
		mist.lifetime = 2.6
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(1.4, .15, .5)
		process.direction = Vector3(0, 1, 0)
		process.spread = 55.0
		process.initial_velocity_min = .3
		process.initial_velocity_max = 1.1
		process.gravity = Vector3(0, -.15, 0)
		process.scale_min = .6
		process.scale_max = 1.6
		mist.process_material = process
		var puff := QuadMesh.new()
		puff.size = Vector2(.7, .7)
		var puff_material := StandardMaterial3D.new()
		puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		puff_material.albedo_color = Color(.78, .84, .8, .16)
		puff.material = puff_material
		mist.draw_pass_1 = puff
		mist.position = Vector3(lip.x, SewerRouteGenerator.WATER_SURFACE + .1, lip.z + (-.7 if bool(falls["north"]) else .7))
		root.add_child(mist)
		_add_falls_sound(root, mist.position)


func _add_falls_sound(root: Node3D, at: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream := (Sound.render_cue("waterfall") as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 4      # 16-bit stereo frames
	var roar := AudioStreamPlayer3D.new()
	roar.name = "FallsRoar"
	roar.stream = stream
	roar.bus = &"SFX"
	roar.unit_size = 7.0
	roar.max_distance = FALLS_SOUND_RANGE
	roar.volume_db = 3.0
	roar.autoplay = true
	roar.position = at
	root.add_child(roar)


## The sloped collider of every ramp whose upper end is this chunk's level: one
## thin box lying along the slope, its top face through both landings' floors.
func _spawn_ramps(root: Node3D, data: Dictionary, level: int) -> void:
	for ramp_value in data.get("ramps", []):
		var ramp: Dictionary = ramp_value
		if int(ramp["upper"]) != level:
			continue
		var top_x := float(ramp["top_x"])
		var bottom_x := float(ramp["bottom_x"])
		var run := absf(top_x - bottom_x)
		var angle := atan2(LEVEL_HEIGHT, run) * (1.0 if top_x > bottom_x else -1.0)
		var body := StaticBody3D.new()
		body.name = "Ramp"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(sqrt(run * run + LEVEL_HEIGHT * LEVEL_HEIGHT), RAMP_THICKNESS, 3.0)
		shape.shape = box
		var basis := Basis(Vector3.BACK, angle)
		var mid := Vector3((top_x + bottom_x) * .5, -LEVEL_HEIGHT * .5, float(ramp["row"]) + .5)
		shape.transform = Transform3D(basis, mid - basis.y * RAMP_THICKNESS * .5)
		body.add_child(shape)
		root.add_child(body)


static func _is_channel(code: int) -> bool:
	return code == SewerRouteGenerator.WATER or code == SewerRouteGenerator.BRIDGE


## The trench under a channel or deck cell: its bed CHANNEL_DEPTH down and a
## brick side wall wherever it meets a walkway or room (cells over the seam
## continue the channel, so no face there).
func _add_channel_trench(build: Dictionary, cell: Vector2i) -> void:
	var surface := build["surface"] as RefSurfaceMesh
	var depth := SewerRouteGenerator.CHANNEL_DEPTH
	surface.add_floor_at(cell.x, cell.y, -depth, RefTextures.layer("floor", "concrete1"),
		RefTextures.params("floor", "concrete1"))
	var coord: Vector3i = build["coord"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	for step_value in RefDecor.DIRS:
		var step: Vector2i = step_value
		var n := cell + step
		if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size or _is_channel(_sewer_code(build, n.x, n.y)):
			continue
		var kind := RefLook.wall_kind("sewer", "", coord.x * size + n.x, coord.z * size + n.y)
		surface.add_wall(n.x, n.y, -step, RefTextures.layer("wall", kind),
			RefTextures.params("wall", kind), 0.0, -depth)


## Brick lining of a ladder shaft under a maze link cell, from the maze floor
## down to the sewer ceiling (SewerRouteGenerator.CEILING_HEIGHT below the next
## storey), facing into the opening from all four sides.
func _add_shaft_lining(build: Dictionary, cell: Vector2i) -> void:
	var surface := build["surface"] as RefSurfaceMesh
	var bottom := -(LEVEL_HEIGHT - SewerRouteGenerator.CEILING_HEIGHT)
	var coord: Vector3i = build["coord"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	for step_value in RefDecor.DIRS:
		var step: Vector2i = step_value
		var n := cell + step
		var kind := RefLook.wall_kind("sewer", "", coord.x * size + n.x, coord.z * size + n.y)
		surface.add_wall(n.x, n.y, -step, RefTextures.layer("wall", kind),
			RefTextures.params("wall", kind), 0.0, bottom)


## One mesh of flowing water over every channel cell of a sewer chunk. The
## vertex colour's red/blue channels carry the flow direction for the shader:
## the east-west channel flows along x, the north-south one along z.
func _spawn_sewer_water(root: Node3D, sewer_grid: Array) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := SewerRouteGenerator.WATER_SURFACE
	var center := SewerRouteGenerator.CENTER
	var any := false
	for z in sewer_grid.size():
		for x in (sewer_grid[z] as Array).size():
			if not _is_channel(int(sewer_grid[z][x])):
				continue
			any = true
			var along_x := absi(z - center) <= SewerRouteGenerator.CHANNEL_HALF
			tool.set_color(Color(1, 0, 0) if along_x else Color(0, 0, 1))
			tool.set_normal(Vector3.UP)
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var c: Vector2 = corner
				tool.set_uv(Vector2(x + c.x, z + c.y))
				tool.add_vertex(Vector3(x + c.x, y, z + c.y))
	if not any:
		return
	var water := MeshInstance3D.new()
	water.name = "SewerWater"
	water.mesh = tool.commit()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SEWER_WATER_SHADER
	water.material_override = material
	root.add_child(water)
	_spawn_channel_railings(root, sewer_grid)


## Iron railings along every edge where a walkway, room floor or deck meets open
## water: a post at each metre and a top and mid rail, as two MultiMeshes per
## chunk. They are the visible reason the channel collider stops you.
func _spawn_channel_railings(root: Node3D, sewer_grid: Array) -> void:
	var segments: Array[Transform3D] = []
	var size := sewer_grid.size()
	for z in size:
		for x in size:
			if not SewerRouteGenerator.is_walkable(int(sewer_grid[z][x])):
				continue
			for step_value in RefDecor.DIRS:
				var step: Vector2i = step_value
				var n := Vector2i(x, z) + step
				if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size \
						or not int(sewer_grid[n.y][n.x]) in [SewerRouteGenerator.WATER, SewerRouteGenerator.FALL]:
					continue
				# on the walkway side of the edge, running along it
				var mid := Vector3(x + .5 + step.x * (.5 - RAIL_INSET), 0.0, z + .5 + step.y * (.5 - RAIL_INSET))
				var basis := Basis(Vector3.UP, PI / 2.0) if step.x != 0 else Basis.IDENTITY
				segments.append(Transform3D(basis, mid))
	if segments.is_empty():
		return
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("3b3f42")
	MaterialLook.tame(iron, true)
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(1.0, .055, .055)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(.07, RAIL_HEIGHT, .07)
	for part in ["Rails", "Posts"]:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = rail_mesh if part == "Rails" else post_mesh
		multi.instance_count = segments.size() * (2 if part == "Rails" else 1)
		for i in segments.size():
			var t: Transform3D = segments[i]
			if part == "Rails":
				multi.set_instance_transform(i * 2, t.translated(Vector3(0, RAIL_HEIGHT - .03, 0)))
				multi.set_instance_transform(i * 2 + 1, t.translated(Vector3(0, RAIL_HEIGHT * .5, 0)))
			else:
				# a post at the segment's start corner, so a run of segments has one per metre
				multi.set_instance_transform(i, t.translated(t.basis.x * -.5 + Vector3(0, RAIL_HEIGHT * .5, 0)))
		var instance := MultiMeshInstance3D.new()
		instance.name = "Channel" + part
		instance.multimesh = multi
		instance.material_override = iron
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)


## Cell -> room_type for every cell inside a room rectangle of this chunk.
## The painted floor kind under a world point ("" off the loaded chunks): footsteps pick their sound from it.
func floor_kind_at(world_xz: Vector2, level: int = 0) -> String:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cell := Vector2i(floori(world_xz.x), floori(world_xz.y))
	var coord := Vector3i(floori(float(cell.x) / size), level, floori(float(cell.y) / size))
	var root := _loaded.get(coord) as Node
	if root == null:
		return ""
	return String((root.get_meta("floor_kinds", {}) as Dictionary).get(Vector2i(posmod(cell.x, size), posmod(cell.y, size)), ""))


## The room purpose under a world point ("" in halls): the ambience bed follows it.
func room_type_at(world_xz: Vector2, level: int = 0) -> String:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cell := Vector2i(floori(world_xz.x), floori(world_xz.y))
	var coord := Vector3i(floori(float(cell.x) / size), level, floori(float(cell.y) / size))
	var data: Dictionary = _chunk_data.get(coord, {})
	if data.is_empty():
		return ""
	return String(_room_type_map_cached(coord, data).get(Vector2i(posmod(cell.x, size), posmod(cell.y, size)), ""))


var _room_map_cache := {}


func _room_type_map_cached(coord: Vector3i, data: Dictionary) -> Dictionary:
	if not _room_map_cache.has(coord):
		if _room_map_cache.size() > 32:
			_room_map_cache.clear()
		_room_map_cache[coord] = _room_type_map(data)
	return _room_map_cache[coord]


static func _room_type_map(data: Dictionary) -> Dictionary:
	var map := {}
	for room_value in data.get("rooms", []):
		var room: Dictionary = room_value
		var rect: Rect2i = room.get("rect", Rect2i())
		var room_type := String(room.get("room_type", ""))
		# The rect includes the room's wall ring and its door cells. Only the interior belongs to the room: a wall face
		# looking into the hall, a door jamb and the doorway floor all take the HALL theme (the face is themed by the space
		# it faces, the room floor starts inside the door line).
		var grid: Array = data.get("grid", [])
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var on_border := x == rect.position.x or z == rect.position.y or x == rect.end.x - 1 or z == rect.end.y - 1
				if on_border and (_is_wall_at(grid, x, z) or _is_doorway(grid, rect, x, z)):
					continue
				map[Vector2i(x, z)] = room_type
	return map


static func _is_wall_at(grid: Array, x: int, z: int) -> bool:
	return z < 0 or x < 0 or z >= grid.size() or x >= (grid[z] as Array).size() or int(grid[z][x]) != 0


## An open cell on a room's border with wall on both sides along that border: a door, which belongs to the hall.
static func _is_doorway(grid: Array, rect: Rect2i, x: int, z: int) -> bool:
	if x == rect.position.x or x == rect.end.x - 1:
		if _is_wall_at(grid, x, z - 1) and _is_wall_at(grid, x, z + 1):
			return true
	if z == rect.position.y or z == rect.end.y - 1:
		if _is_wall_at(grid, x - 1, z) and _is_wall_at(grid, x + 1, z):
			return true
	return false


## Ceiling height of a cell of the chunk under `root`.
func _cell_height(root: Node, cell: Vector2i) -> float:
	var heights: Dictionary = root.get_meta("ref_heights", {})
	return float(heights.get(cell, float(root.get_meta("ref_corridor_h", 3.3))))


static func _height_in(build: Dictionary, cell: Vector2i) -> float:
	return float((build["heights"] as Dictionary).get(cell, float(build["corridor_h"])))


## Corridor ceiling of the chunk across a seam (the cell there is circulation).
func _seam_height(build: Dictionary, nx: int, nz: int) -> float:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var coord: Vector3i = build["coord"]
	var neighbour := Vector3i(coord.x + floori(float(nx) / size), coord.y, coord.z + floori(float(nz) / size))
	return RefLook.corridor_height(generator.biome_for(neighbour), neighbour)


func _ref_floor_kind(build: Dictionary, x: int, z: int) -> String:
	var style: Dictionary = build["style"]
	var coord: Vector3i = build["coord"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var gx := coord.x * size + x
	var gz := coord.z * size + z
	var room_type: String = (build["room_map"] as Dictionary).get(Vector2i(x, z), "")
	var region := String(build.get("region", generator.biome_for(coord)))
	var kinds: Array
	if room_type != "":
		kinds = FloorSets.room(region, room_type)
	else:
		kinds = FloorSets.hall(region)
		if FloorSets.hall_runner(region):
			var runner := _runner_kind(build["data"]["grid"], x, z)
			if runner != "":
				return runner
	return kinds[RefLook.pick(gx, gz, 1, kinds.size())]


## Carpet runner down the middle three cells of a hall, oriented along the hall:
## left/centre/right strips so the brass borders land on the outer edges. Outside the
## chunk counts as wall; anything not exactly CORRIDOR_WIDTH wide gets no runner.
static func _runner_kind(grid_data: Array, x: int, z: int) -> String:
	var size := grid_data.size()
	var open := func(cx: int, cz: int) -> bool:
		return cx >= 0 and cz >= 0 and cx < size and cz < size \
			and int(grid_data[cz][cx]) == 0
	var runs := [0, 0]
	for axis in 2:
		var step := Vector2i(0, 1) if axis == 0 else Vector2i(1, 0)
		var before := 0
		while before < 6 and open.call(x - step.x * (before + 1), z - step.y * (before + 1)):
			before += 1
		var after := 0
		while after < 6 and open.call(x + step.x * (after + 1), z + step.y * (after + 1)):
			after += 1
		var width := StreamedRouteGenerator.CORRIDOR_WIDTH
		runs[axis] = before + after + 1
		if before + after + 1 != width:
			continue
		var offset := before - width / 2     # across the hall, 0 = middle
		if absi(offset) > 1:
			return ""
		var part := "l" if offset < 0 else ("r" if offset > 0 else "c")
		# axis 0: hall runs along x (the cells vary in z); axis 1: along z
		return ("runner_%s" if axis == 0 else "runnerz_%s") % part
	# A junction (T, cross, corner) cell is crossed by a hall in both directions, so neither run is exactly one hall wide and
	# it used to fall through to the random stone corridor tiles: a grey patch in the middle of the carpet. It carries the
	# hall's own centre strip instead, so the carpet runs unbroken through the opening.
	# Only where a one-hall-wide cell touches it, so a 5-wide hall keeps its own flooring.
	if int(runs[0]) >= StreamedRouteGenerator.CORRIDOR_WIDTH and int(runs[1]) >= StreamedRouteGenerator.CORRIDOR_WIDTH:
		for step_value in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var step: Vector2i = step_value
			for reach in [1, 2]:
				var nx: int = x + step.x * int(reach)
				var nz: int = z + step.y * int(reach)
				if not open.call(nx, nz):
					break
				if _exact_hall_cell(grid_data, nx, nz):
					return "runner_c"
	return ""


## True when the open cell lies in a run of exactly one hall width along either axis.
static func _exact_hall_cell(grid_data: Array, x: int, z: int) -> bool:
	var size := grid_data.size()
	for axis in 2:
		var dx := 0 if axis == 0 else 1
		var dz := 1 if axis == 0 else 0
		var run := 1
		for sign in [-1, 1]:
			var k := 1
			while k < 8:
				var cx: int = x + dx * k * int(sign)
				var cz: int = z + dz * k * int(sign)
				if cx < 0 or cz < 0 or cx >= size or cz >= size or int(grid_data[cz][cx]) != 0:
					break
				run += 1
				k += 1
		if run == StreamedRouteGenerator.CORRIDOR_WIDTH:
			return true
	return false


## Wall kind for the face of wall cell (x, z) that looks into (nx, nz): chosen
## from the room on that side, so a corridor wall and the paper of the room
## behind it can differ.
func _ref_wall_kind(build: Dictionary, x: int, z: int, nx: int, nz: int) -> String:
	var style: Dictionary = build["style"]
	var coord: Vector3i = build["coord"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var room_type: String = (build["room_map"] as Dictionary).get(Vector2i(nx, nz), "")
	var region := String(build.get("region", generator.biome_for(coord) if generator != null else "maze"))
	return RefLook.wall_kind(region, room_type, coord.x * size + x, coord.z * size + z)


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


## Shopping arcade: each shop's name in lit letters over its door, on the hall side (the City's shop signs, ported).
## Visual only (no collision), so hunters and the door keep-clear zone are unaffected.
func _spawn_shop_signs(parent: Node3D, data: Dictionary) -> void:
	if String(data.get("region", "")) != "mall":
		return
	for room_value in data.get("rooms", []):
		var room: Dictionary = room_value
		var shop_name := String(StreamedRouteGenerator.SHOP_NAMES.get(String(room.get("room_type", "")), ""))
		var doorway_value = room.get("doorway")
		if shop_name.is_empty() or not doorway_value is Vector2i:
			continue
		var doorway: Vector2i = doorway_value
		var basis := StreamedRouteGenerator._room_template_basis(room)
		if basis.is_empty():
			continue
		var outward: Vector2i = basis["open"]
		var label := Label3D.new()
		label.name = "ShopSign"
		label.text = shop_name
		label.pixel_size = 0.012
		label.font_size = 48
		label.outline_size = 8
		label.modulate = Color(1.0, 0.55, 0.8) if String(room["room_type"]) == "donut_shop" else Color(0.55, 0.95, 0.95)
		label.outline_modulate = Color(0.05, 0.03, 0.08)
		label.shaded = false
		label.double_sided = true
		label.position = Vector3(doorway.x + .5 + outward.x * .56, 2.75, doorway.y + .5 + outward.y * .56)
		label.rotation.y = atan2(float(outward.x), float(outward.y))
		parent.add_child(label)


func _spawn_streamed_ceiling_lights(parent: Node3D, data: Dictionary) -> void:
	var region := String(data.get("region", "maze"))
	if region not in ["carnival", "maze"]:
		return
	var blocked := {}
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
		anchors.append(Vector3(cell.x + .5, _cell_height(parent, cell) - .12, cell.y + .5))
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
		# The bars run along the cell's hall wall but stop at its doorway: one solid gate across the whole front sealed the
		# cell for the player while the nav grid still walked through the door (playtest GOLF / HOTEL: bots stuck in front
		# of a relay inside a cell).
		var gate_z := rect.end.y - .15 if above_hall else rect.position.y + .15
		var wall_row := rect.end.y - 1 if above_hall else rect.position.y
		var grid_rows: Array = data.get("grid", [])
		var run_start := rect.position.x
		for gx in range(rect.position.x, rect.end.x + 1):
			var is_door := gx < rect.end.x and wall_row >= 0 and wall_row < grid_rows.size() \
				and gx >= 0 and gx < (grid_rows[wall_row] as Array).size() and int(grid_rows[wall_row][gx]) == 0
			if is_door or gx == rect.end.x:
				var run_end := gx
				if run_end - run_start >= 1:
					tasks.append({"path": PRISON_MODELS["gate"],
						"at": Vector3((run_start + run_end) * .5, 0.0, gate_z),
						"yaw": 0.0 if above_hall else PI,
						"size": Vector3(run_end - run_start, 2.4, .16),
						"group": "streamed_prison_prop", "solid": true, "type": ""})
				run_start = gx + 1
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
		# The cage is presentation the nav grid does not know about: a relay or pickup under it was unreachable for the
		# player while bots and hunters walked to it (playtest GOLF). No cage in a cell that holds one.
		var holds_pickup := false
		for pickup_value in data.get("pickups", []):
			if Vector2((pickup_value as Dictionary).get("cell", Vector2i(-99, -99))).distance_to(Vector2(center)) < 2.0:
				holds_pickup = true
		if not holds_pickup:
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
	var finish := PropModelCatalog.region_finish(String(data.get("region", "")))
	for value in data.get("region_props", []):
		_spawn_region_prop(parent, coord, value, finish)


func _spawn_region_prop(parent: Node3D, coord: Vector3i, prop: Dictionary, finish: String = "") -> void:
	var type := String(prop.get("type", ""))
	if not PropModelCatalog.has_model(type):
		return
	if PropModelCatalog.is_room_door(type):
		_spawn_room_door(parent, coord, prop, type)
		return
	var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
	# Ceiling props hang from this room's ceiling; wall props sit at the height a
	# person sees them, however tall the room is.
	var room_height := _cell_height(parent, cell)
	var prop_y := PropModelCatalog.visual_y(type,
		room_height if PropModelCatalog.is_ceiling_mounted(type) else minf(room_height, WALL_HEIGHT),
		float(prop.get("mount_y", 0.0)))
	var mount_offset: Vector2 = prop.get("mount_offset", Vector2.ZERO) \
		+ prop.get("placement_offset", Vector2.ZERO)
	_spawn_authored_prop(parent, PropModelCatalog.model_path(type,
		String(prop.get("id", "")), String(prop.get("room_id", "")), finish),
		Vector3(cell.x + .5 + mount_offset.x,
			prop_y, cell.y + .5 + mount_offset.y),
		float(prop.get("yaw", 0.0)), prop.get("collider_size", prop.get("blocker_size", Vector3.ONE)),
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
		LampField.make_budgeted(light)


func _spawn_fixture_light(parent: Node3D, prop_type: String, at: Vector3) -> void:
	var profile := PropModelCatalog.light_profile(prop_type)
	if profile.is_empty():
		return
	# Authored lamps no longer each get an OmniLight3D: they register with the
	# shared LampField, which lends a handful of real lights to whichever fixtures
	# are nearest the camera. At most four per chunk, like the old per-chunk cap.
	var extras: Array = parent.get_meta("extra_lamps", [])
	if extras.size() >= 4:
		return
	extras.append([parent.position + at + Vector3.UP * float(profile.get("height", .5)),
		profile.get("color", Color.WHITE), clampf(float(profile.get("energy", .4)), .3, 1.4), 0,
		float(profile.get("range", 3.5)) + 1.5])
	parent.set_meta("extra_lamps", extras)


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
	RefLook.grade_prop(visual, .6 if PropModelCatalog.is_floor_dressing(prop_type) else 1.0)
	visual.position = visual_at
	visual.rotation.y = PropModelCatalog.authored_visual_yaw(yaw)
	visual.set_meta("streamed_prop_type", prop_type)
	visual.set_meta("streamed_prop_bounds", visual_bounds)
	visual.add_to_group(group_name)
	_limit_prop_visibility(visual, visual_bounds, prop_type)
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
	for box in PropColliderBoxes.boxes(prop_type, blocker_size, PropColliderBoxes.variant_paths(prop_type).find(path)):
		var local: Vector2 = box["c"]
		var half: Vector2 = box["h"]
		var collision := CollisionShape3D.new()
		collision.shape = _shared_box_shape(Vector3(half.x * 2.0, blocker_size.y, half.y * 2.0))
		collision.position = at + Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, yaw) + Vector3.UP * (blocker_size.y * .5)
		collision.rotation.y = yaw
		body.add_child(collision)
	parent.add_child(body)


## Small and medium props stop drawing beyond a distance where they are a few pixels (visibility ranges: the renderer culls them,
## no per-frame script). Big pieces, floor dressing and animated set pieces always draw.
const PROP_RANGE_SMALL := 42.0     # bounding-box diagonal under 1.0 m
const PROP_RANGE_MEDIUM := 64.0    # under 2.0 m
const PROP_RANGE_MARGIN := 6.0
## Switch for A/B measurements (tools/look/prop_perf.gd).
static var limit_prop_visibility := true


static func prop_visibility_range(bounds: AABB, prop_type: String) -> float:
	if PropModelCatalog.is_floor_dressing(prop_type) or prop_type == "carouselCenterpiece":
		return 0.0
	var diagonal := bounds.size.length()
	if diagonal <= 0.0:
		return 0.0
	if diagonal < 1.0:
		return PROP_RANGE_SMALL
	if diagonal < 2.0:
		return PROP_RANGE_MEDIUM
	return 0.0


func _limit_prop_visibility(visual: Node3D, bounds: AABB, prop_type: String) -> void:
	var range_end := prop_visibility_range(bounds, prop_type) if limit_prop_visibility else 0.0
	if range_end <= 0.0:
		return
	for node in visual.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.visibility_range_end = range_end
		geometry.visibility_range_end_margin = PROP_RANGE_MARGIN


static var _box_shapes := {}


## One BoxShape3D per distinct blocker size: hundreds of chairs and tables share a handful of shapes.
static func _shared_box_shape(size: Vector3) -> BoxShape3D:
	var key := Vector3i(roundi(size.x * 100.0), roundi(size.y * 100.0), roundi(size.z * 100.0))
	var shape := _box_shapes.get(key) as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		shape.size = size
		_box_shapes[key] = shape
	return shape


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
	MaterialLook.tame(material)
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
	light.light_energy = RefLook.SAFE_ROOM_LIGHT_ENERGY
	light.omni_range = RefLook.SAFE_ROOM_LIGHT_RANGE
	parent.add_child(light)
	LampField.make_budgeted(light)


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
	var style := String(fixture.get("style", ""))
	if fixture_kind == "hiding_spot" and not style.is_empty():
		# Furniture hiding spot: the bed or wardrobe prop is already placed; sit on it (docs/HIDING_PROPS.md).
		var local: Vector2 = fixture.get("local_position", Vector2(cell) + Vector2(.5, .5))
		spot.hide_style = style
		spot.hide_size = fixture.get("blocker_size", Vector3.ONE)
		spot.prompt_text = "HIDE UNDER BED" if style == "bed" else "HIDE IN WARDROBE"
		spot.position = Vector3(local.x, .0, local.y)
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
	for coord_value in _dormant.keys().duplicate():
		_free_dormant(coord_value)
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


## RefLook structure: the visuals are one merged mesh per chunk (RefSurfaceMesh);
## the GridMap keeps only collision, so these two items carry shapes and no mesh.
func _add_ref_items(library: MeshLibrary, first_id: int) -> int:
	var next_id := first_id
	_col_floor_item = next_id
	library.create_item(next_id)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(1.0, SLAB, 1.0)
	library.set_item_shapes(next_id, [floor_shape,
		Transform3D(Basis.IDENTITY, Vector3(0.0, -SLAB * .5, 0.0))])
	next_id += 1
	_col_wall_item = next_id
	library.create_item(next_id)
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(1.0, RefLook.MAX_HEIGHT, 1.0)
	library.set_item_shapes(next_id, [wall_shape,
		Transform3D(Basis.IDENTITY, Vector3(0.0, RefLook.MAX_HEIGHT * .5, 0.0))])
	next_id += 1
	# The sewer's walls stop under the maze floor slab above them. A full-height
	# maze wall block placed one storey down rose 3.5 m into level 0 and walled
	# off open maze halls (playtest GOLF).
	_col_sewer_wall_item = next_id
	library.create_item(next_id)
	var sewer_wall_shape := BoxShape3D.new()
	sewer_wall_shape.size = Vector3(1.0, SEWER_WALL_HEIGHT, 1.0)
	library.set_item_shapes(next_id, [sewer_wall_shape,
		Transform3D(Basis.IDENTITY, Vector3(0.0, SEWER_WALL_HEIGHT * .5, 0.0))])
	next_id += 1
	# Open sewer channel: blocks from the trench bed to above the railings.
	_col_channel_item = next_id
	library.create_item(next_id)
	var channel_shape := BoxShape3D.new()
	var channel_h := SewerRouteGenerator.CHANNEL_DEPTH + CHANNEL_BLOCK_TOP
	channel_shape.size = Vector3(1.0, channel_h, 1.0)
	library.set_item_shapes(next_id, [channel_shape,
		Transform3D(Basis.IDENTITY, Vector3(0.0, CHANNEL_BLOCK_TOP - channel_h * .5, 0.0))])
	return next_id + 1


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
	MaterialLook.tame(material)
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
		MaterialLook.tame(material)
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
