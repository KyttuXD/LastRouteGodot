class_name StreamedFacilityView3D
extends Node3D

## Live debug renderer for StreamedRouteGenerator. It keeps a 3x3 horizontal
## window around the runner plus the matching chunks immediately above/below,
## so the route can extend forever without retaining every visited mesh.

signal chunk_changed(coord: Vector3i, data: Dictionary)
signal pickup_claimed(entity_id: String)
## A tool swing hit a breakable (Breach): the route asks the host what it did.
signal breakable_hit(id: String, tool: String)

const CELL_SIZE := 1.0
const LEVEL_HEIGHT := 4.0
## Roof height of the ring of cells on the edge of every level -3 chunk: both neighbours use it, so seams have no step.
const INFERNO_SEAM_ROOF := 3.4
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
## A runner this close (cells) to a ramp landing pre-streams the ramp's other end.
const RAMP_PRESTREAM_CELLS := 6.0
## The falls: rough stone on the drop's cliffs, and how far the roar carries.
const CLIFF_WALL_KIND := "stone1"
## How far past the lip the sheet hangs.
const FALLS_SPOUT := .12
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
## The route scene's shared music-box clock; each box's tune follows it (MusicBoxTune).
var music_boxes: MusicBoxes
## Carnival booths (CarnivalBooth3D): requester(player, booth_id, prop_type) -> String starts a game through the host; reporter(event) sends a finished / cancelled game to it.
var booth_requester: Callable
var booth_reporter: Callable
var _booth_nodes := {}
## the merry-go-round lever: requester(player, ride_id) -> String asks the host to start or stop the ride
var carousel_requester: Callable
var _carousel_nodes := {}
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
## Vertical preloading: the 3x3 on every level a link in the runner's 3x3 reaches is built in the background after
## the current window and parked at once (a level change is then a visibility/physics swap, not a build); levels two
## away keep generated data only. Parked chunks are bounded to those sets (at most 2 x 9 here).
const PREBUILD_LEVEL_RANGE := 1
## Only links this close to the runner are pre-built (re-checked as the runner moves, see _process).
const PREBUILD_LINK_RADIUS := 24.0
## A parked chunk in the runner's column is kept up to this many levels away. With ramps on -1 and -2 the level
## beyond a link is pre-built too (on -1 the ready set is 0 and -2): freeing it on the way back up would rebuild
## those nine chunks on every round trip, so parking reaches one level past the pre-build range (at most 3 x 9).
const PARK_LEVEL_RANGE := PREBUILD_LEVEL_RANGE + 1
const PREDATA_LEVEL_RANGE := 2
## Links walked from level to level (no shaft hides the other storey), and how far around each end of one both
## levels stay loaded: the deepest look up or down a stairwell or along a ramp tunnel.
const WALKED_LINKS := ["stairs", "spiral", "ramp"]
const LINK_VIEW_MARGIN := 20.0
## Height of a ramp tunnel's vault over its upper level's floor (the sewer ceiling; ramps start on sewer levels).
const RAMP_VAULT := SewerRouteGenerator.CEILING_HEIGHT
var _ready_set := {}
var _wanted_now := {}
var _pending_prebuild: Array[Vector3i] = []
var _pending_data: Array[Vector3i] = []
var _ready_dirty := false
var _ready_recheck := 0.0
var _chunk_data := {}
var _pickup_nodes := {}
var _door_nodes := {}
## Room light switches (docs/LIGHT_SWITCHES.md): room id -> [[lamp, full energy], ...] for every lamp (decor and fixture
## props) of a lit room, the switch node per room, and the chunk each room's lamps came from. Switching zeroes the lamps'
## energy in place: the LampField pool and LightField.exposure_at read the same arrays, so the rendered light and the
## mutual-light-sight rule go dark together, and parked storeys keep the state (their lamp arrays are kept).
var _room_lamps := {}
var _switch_nodes := {}
var _room_lamp_coord := {}
## Callable(on: bool, room_id: String) -> String, set by the route (host-authoritative toggle; the room id is bound).
var room_light_requester: Callable
const SWITCH_HEIGHT := 1.45      # hunter-scale world, still within a 1.60 m runner's reach (2.15 m)
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
## Chunks other systems asked the worker for (request_generation), beyond the view's own queue.
var _extra_generation := {}
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
	_walked_link_cache.clear()
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
	_pending_prebuild.clear()
	_pending_data.clear()
	_ready_set = {}
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
	return clampi(roundi(world_y / LEVEL_HEIGHT), StreamedRouteGenerator.INFERNO_LEVEL, StreamedRouteGenerator.MEZZANINE_LEVEL)


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
	if PlatformProfile.maze_culling:
		_update_maze_culling()
	_ready_recheck -= _delta
	if _ready_recheck <= 0.0 and _last_player_chunk.x != 999999:
		_ready_recheck = .5
		var ready := _vertical_ready_set(_last_player_chunk)
		if ready != _ready_set:
			_ready_set = ready
			_settle_dormant(_last_player_chunk, _wanted_now)
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
	# The maze and the Mezzanine above it look through each other (grating, the open balcony edges). On the Mezzanine the
	# 3x3 of the maze below stays loaded; in the maze only the Mezzanine chunk overhead (the neighbours stream in when a
	# stairwell is walked, and are seen through the open-air edges only from above).
	if center.y == 0 or center.y == StreamedRouteGenerator.MEZZANINE_LEVEL:
		var other_level := StreamedRouteGenerator.MEZZANINE_LEVEL if center.y == 0 else 0
		var reach := 0 if center.y == 0 else 1
		for z in range(center.z - reach, center.z + reach + 1):
			for x in range(center.x - reach, center.x + reach + 1):
				var other := Vector3i(x, other_level, z)
				if generator.is_chunk_allowed(other):
					wanted[other] = true
	# The far end of a ladder or ramp stays loaded while the runner is in a chunk
	# with one, so a shaft or a ramp tunnel never opens onto an unloaded level.
	# Chunks with no link keep the plain nine-chunk window.
	for link_value in generator.vertical_links(center):
		var link: Dictionary = link_value
		var far := int(LevelLink.other_end(link, center.y)["level"])
		var vertical := Vector3i(center.x, far, center.z)
		if generator.is_chunk_allowed(vertical):
			wanted[vertical] = true
	# Stairwells and ramps are walked, not climbed: the other level comes into view
	# from the landing and the runner's level flips half way along, so in a chunk
	# with one both levels keep every chunk of the 3x3 column within
	# LINK_VIEW_MARGIN of the link's ends (KT: a blank, unloaded area beyond the
	# stairs). Only the runner's own column: the extras then stay inside the
	# window that parks them, and a jump to another column frees nothing extra.
	for link_value in _walked_links(center):
		var link: Dictionary = link_value
		for level in [int(link["from_level"]), int(link["to_level"])]:
			var end := LadderTraffic.ladder_point(link, level)
			for dz in range(-STREAM_RADIUS, STREAM_RADIUS + 1):
				for dx in range(-STREAM_RADIUS, STREAM_RADIUS + 1):
					var near := Vector3i(center.x + dx, level, center.z + dz)
					if not wanted.has(near) and generator.is_chunk_allowed(near) \
							and _distance_from_point_to_chunk(end, near) < LINK_VIEW_MARGIN:
						wanted[near] = true
	# You can see across the falls' drop between the two sewers: in a chunk with
	# falls the other level's chamber stays loaded.
	if (center.y == StreamedRouteGenerator.SEWER_LEVEL or center.y == StreamedRouteGenerator.LOWER_SEWER_LEVEL) \
			and not generator.sewer().falls_between(center.x, center.z).is_empty():
		var across := Vector3i(center.x, StreamedRouteGenerator.LOWER_SEWER_LEVEL \
			if center.y == StreamedRouteGenerator.SEWER_LEVEL else StreamedRouteGenerator.SEWER_LEVEL, center.z)
		wanted[across] = true
	return wanted


## The stairwells and ramps touching `coord`'s level in its column. Deterministic per seed, so it is kept: every
## level change re-runs _wanted_chunks, and planning the stairwells again there cost a frame.
var _walked_link_cache := {}
func _walked_links(coord: Vector3i) -> Array:
	if _walked_link_cache.has(coord):
		return _walked_link_cache[coord]
	var out := []
	for link_value in generator.vertical_links(coord):
		if WALKED_LINKS.has(String((link_value as Dictionary)["kind"])):
			out.append(link_value)
	if _walked_link_cache.size() >= 64:
		_walked_link_cache.clear()      # bounded to the window, not to the distance walked
	_walked_link_cache[coord] = out
	return out


## Horizontal distance from a point (view-local x/z) to a chunk's footprint; INF for Vector2.INF.
static func _distance_from_point_to_chunk(point: Vector2, coord: Vector3i) -> float:
	if point == Vector2.INF:
		return INF
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)
	var dx := maxf(maxf(coord.x * size - point.x, point.x - (coord.x + 1) * size), 0.0)
	var dz := maxf(maxf(coord.z * size - point.y, point.y - (coord.z + 1) * size), 0.0)
	return Vector2(dx, dz).length()


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
	_wanted_now = wanted
	_pending_data.clear()
	_ready_set = _vertical_ready_set(center)
	if not _active_build.is_empty():
		# a chunk still wanted or still to pre-build keeps building (restarting it on every level change wasted the work)
		var active_coord: Vector3i = _active_build.get("coord", Vector3i.ZERO)
		# so does one in the runner's column a storey or two away: it gets parked when done (cancelling it on a level
		# change meant building it again on the way back)
		if not wanted.has(active_coord) and not _ready_set.has(active_coord) \
				and not (_near_column(active_coord, center) and absi(active_coord.y - center.y) <= PARK_LEVEL_RANGE):
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
			# the floor above/below the runner (a ladder's other end) counts as under them; another link's
			# far end in the same column (a ramp down to the Inferno from the collector) streams in normally
			var column := coord.x == center.x and coord.z == center.z \
				and (coord.y == center.y or coord.y == previous.y or previous.x == 999999)
			if column or previous.x == 999999 and coord.y == center.y \
					or coord.y == center.y and _distance_to_chunk(coord) < IMMEDIATE_MARGIN:
				urgent.append(coord)
		if not urgent.is_empty():
			if not _active_build.is_empty() and urgent.has(_active_build.get("coord")):
				while not _advance_chunk_build(_active_build, true):
					pass
				_active_build = {}
				urgent = urgent.filter(func(c: Vector3i) -> bool: return not _loaded.has(c))
			if not _active_build.is_empty():
				var keep: Vector3i = _active_build.get("coord")
				if _near_column(keep, center) and absi(keep.y - center.y) <= PARK_LEVEL_RANGE:
					while not _advance_chunk_build(_active_build, true):   # finish it: it is parked, not rebuilt later
						pass
					_active_build = {}
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


## Lower quality tiers (the Quest) skip a deterministic share of pure dressing: props with no collider, no interaction
## and no door. Gameplay, navigation and every peer's world are unchanged (the props only exist as visuals).
func _thinned_out(prop: Dictionary, type: String) -> bool:
	var density := PlatformProfile.prop_density
	if density >= 1.0 or bool(prop.get("solid", true)) or PropModelCatalog.is_room_door(type) \
			or not PropModelCatalog.interaction_for(type).is_empty():
		return false
	return absi(hash(String(prop.get("id", "")) + ":thin")) % 100 >= int(density * 100.0)


## Maze culling (every renderer, the web included): when the runner enters a new cell, a worker floods out through open
## cells (closed room doors block) to MAZE_CULL_RADIUS metres and the prop visuals on the runner's level whose cell the
## flood did not reach are hidden. Any straight line of sight through the maze is a run of open cells, so the flood is
## a superset of what can be seen; one extra ring of cells covers lines that graze a corner. Only visuals hide:
## colliders, hunters, audio and lamps are untouched. scripts/validate_maze_culling.gd guards against popping.
const MAZE_CULL_RADIUS := 64
var _cull_task := -1
var _cull_result := {}
var _cull_cell := Vector2i(999999, 999999)
var _cull_level := 999999
var _cull_visible := {}
var maze_cull_hidden := 0
var maze_cull_props := 0
var maze_cull_tiles_hidden := 0
var maze_cull_tiles := 0


func _update_maze_culling() -> void:
	if _cull_task != -1:
		if not WorkerThreadPool.is_task_completed(_cull_task):
			return
		WorkerThreadPool.wait_for_task_completion(_cull_task)
		_cull_task = -1
		_cull_visible = _cull_result.get("visible", {})
		_apply_maze_culling()
	var local := tracked_player.global_position - global_position
	var cell := Vector2i(floori(local.x), floori(local.z))
	var level := current_level()
	if cell == _cull_cell and level == _cull_level:
		return
	_cull_cell = cell
	_cull_level = level
	var grids := {}
	for coord_value in _loaded:
		var coord: Vector3i = coord_value
		if coord.y == level and _chunk_data.has(coord):
			grids[Vector2i(coord.x, coord.z)] = (_chunk_data[coord] as Dictionary).get("grid", [])
	var closed := {}
	for door_value in _door_nodes.values():
		var door := door_value as Node3D
		if door != null and is_instance_valid(door) and not bool(door.get("room_door_open")):
			var at := door.global_position - global_position
			if floori(at.y / LEVEL_HEIGHT + .5) == level:
				closed[Vector2i(floori(at.x), floori(at.z))] = true
	var result := {}
	_cull_result = result
	_cull_task = WorkerThreadPool.add_task(func() -> void:
		result["visible"] = maze_visible_cells(grids, closed, cell, MAZE_CULL_RADIUS), false, "maze culling")


## Cells reachable through open cells from `start` within `radius` (closed doors block), plus one ring around them.
static func maze_visible_cells(grids: Dictionary, closed: Dictionary, start: Vector2i, radius: int) -> Dictionary:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var open := func(c: Vector2i) -> bool:
		var chunk := Vector2i(floori(float(c.x) / size), floori(float(c.y) / size))
		var grid: Array = grids.get(chunk, [])
		if grid.is_empty() or closed.has(c):
			return false
		var lx := posmod(c.x, size)
		var lz := posmod(c.y, size)
		return lz < grid.size() and lx < (grid[lz] as Array).size() and int(grid[lz][lx]) == 0
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	var r2 := radius * radius
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or (n - start).length_squared() > r2 or not open.call(n):
				continue
			seen[n] = true
			frontier.append(n)
	var out := seen.duplicate()
	for c in seen:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				out[Vector2i(c.x + dx, c.y + dz)] = true
	return out


func _apply_maze_culling() -> void:
	var hidden := 0
	var total := 0
	for node in get_tree().get_nodes_in_group("cull_prop"):
		var prop := node as Node3D
		var root := prop.get_parent() as Node3D
		if root == null or not root.visible or roundi(root.position.y / LEVEL_HEIGHT) != _cull_level:
			continue
		total += 1
		var show := _cull_visible.has(prop.get_meta("cull_cell", Vector2i.ZERO))
		if prop.visible != show:
			prop.visible = show
		if not show:
			hidden += 1
	maze_cull_hidden = hidden
	maze_cull_props = total
	var tiles_seen := {}
	for c in _cull_visible:
		var cell: Vector2i = c
		tiles_seen[Vector2i(floori(float(cell.x) / RefSurfaceMesh.TILE), floori(float(cell.y) / RefSurfaceMesh.TILE))] = true
	var tiles_hidden := 0
	var tiles_total := 0
	for node in get_tree().get_nodes_in_group("cull_tile"):
		var tile := node as Node3D
		var root := tile.get_parent() as Node3D
		if root == null or not root.visible or roundi(root.position.y / LEVEL_HEIGHT) != _cull_level:
			continue
		tiles_total += 1
		var show := tiles_seen.has(tile.get_meta("cull_tile", Vector2i.ZERO))
		if tile.visible != show:
			tile.visible = show
		if not show:
			tiles_hidden += 1
	maze_cull_tiles_hidden = tiles_hidden
	maze_cull_tiles = tiles_total


## While the runner is on a ladder (between the two storeys), the destination storey's chunks near the shaft join the
## stream queue, so they are built during the climb and the level change has nothing left to build synchronously.
var _prestreamed_for := Vector3i(999999, 999999, 999999)
func _prestream_ladder_destination() -> void:
	var center := _last_player_chunk
	if center.x == 999999:
		return
	# Between storeys on a ladder: the storey being climbed toward. Walking a ramp
	# has no pause at the boundary, so a runner near a ramp landing pre-streams
	# the other end before setting foot on the slope.
	var dy := tracked_player.global_position.y - global_position.y - float(center.y) * LEVEL_HEIGHT
	var target_y := center.y
	var far_landing := Vector2.INF
	if dy < -.6:
		target_y = center.y - 1
	elif dy > .6:
		target_y = center.y + 1
	else:
		var here := Vector2(tracked_player.global_position.x - global_position.x,
			tracked_player.global_position.z - global_position.z)
		for link_value in generator.vertical_links(center):
			var link: Dictionary = link_value
			if String(link["kind"]) in ["ramp", "stairs", "spiral"] \
					and LadderTraffic.ladder_point(link, center.y).distance_to(here) <= RAMP_PRESTREAM_CELLS:
				target_y = int(LevelLink.other_end(link, center.y)["level"])
				# the runner arrives at the far landing: stream what is near it too
				far_landing = LadderTraffic.ladder_point(link, target_y)
	var key := Vector3i(center.x, target_y, center.z)
	if target_y == center.y or key == _prestreamed_for or not generator.is_chunk_allowed(key):
		return
	_prestreamed_for = key
	for z in range(center.z - STREAM_RADIUS, center.z + STREAM_RADIUS + 1):
		for x in range(center.x - STREAM_RADIUS, center.x + STREAM_RADIUS + 1):
			var coord := Vector3i(x, target_y, z)
			if _loaded.has(coord) or _pending_loads.has(coord) or not generator.is_chunk_allowed(coord) \
					or _distance_to_chunk(coord) >= IMMEDIATE_MARGIN \
					and _distance_from_point_to_chunk(far_landing, coord) >= IMMEDIATE_MARGIN:
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
		if not wanted.has(coord) and (_ready_set.has(coord) or coord.y != center.y and _near_column(coord, center)):
			_make_dormant(coord)
	for coord_value in _dormant.keys().duplicate():
		var coord: Vector3i = coord_value
		if wanted.has(coord):
			_revive(coord)
		elif not _ready_set.has(coord) and not (_near_column(coord, center) and absi(coord.y - center.y) <= PARK_LEVEL_RANGE):
			_free_dormant(coord)
	_pending_prebuild.clear()
	for coord_value in _ready_set:
		var coord: Vector3i = coord_value
		if not wanted.has(coord) and not _dormant.has(coord) and not _loaded.has(coord):
			_pending_prebuild.append(coord)
	_pending_prebuild.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _chunk_distance(a, center) < _chunk_distance(b, center))
	# Data only (no nodes) for the levels around this one: hunter navigation reads them (one level each way), and
	# without pre-built storeys (phones, the Quest) it used to generate them on the main thread at every chunk crossing.
	for level in range(center.y - PREDATA_LEVEL_RANGE, center.y + PREDATA_LEVEL_RANGE + 1):
		if level == center.y:
			continue
		for z in range(center.z - STREAM_RADIUS, center.z + STREAM_RADIUS + 1):
			for x in range(center.x - STREAM_RADIUS, center.x + STREAM_RADIUS + 1):
				var coord := Vector3i(x, level, z)
				if generator.is_chunk_allowed(coord) and not generator.has_chunk_cached(coord) and not _pending_data.has(coord):
					_pending_data.append(coord)


## Links (ladder, ramp, stairwell ...) in the runner's 3x3. Generators with vertical_links(coord) (every level) are asked
## directly; otherwise the sewer's ladders link 0 and -1.
func _nearby_links(center: Vector3i) -> Array:
	var out := []
	for z in range(center.z - STREAM_RADIUS, center.z + STREAM_RADIUS + 1):
		for x in range(center.x - STREAM_RADIUS, center.x + STREAM_RADIUS + 1):
			var coord := Vector3i(x, center.y, z)
			var links: Array = []
			var own_column := x == center.x and z == center.z
			if generator.has_method("vertical_links"):
				# ladders live in the sewer chunk under the column: read them only once it is generated (or under the
				# runner), queue the rest for the worker
				links = generator.call("vertical_links", coord, not own_column)
				var ladder_coord := Vector3i(x, StreamedRouteGenerator.SEWER_LEVEL, z)
				if not own_column and center.y in [0, StreamedRouteGenerator.SEWER_LEVEL] \
						and not generator.has_chunk_cached(ladder_coord) and generator.is_chunk_allowed(ladder_coord) \
						and not _pending_data.has(ladder_coord):
					_pending_data.append(ladder_coord)
					_ready_dirty = true
			elif center.y in [0, StreamedRouteGenerator.SEWER_LEVEL]:
				# The sewer chunk under this column holds its ladders. Only read it once generated: generating it here
				# (~30 ms) on every chunk change was a main-thread stall; queue it for the worker instead.
				var sewer_coord := Vector3i(x, StreamedRouteGenerator.SEWER_LEVEL, z)
				if generator.has_chunk_cached(sewer_coord) or sewer_coord == Vector3i(center.x, sewer_coord.y, center.z):
					links = generator.chunk(sewer_coord).get("links", [])
				elif generator.is_chunk_allowed(sewer_coord) and not _pending_data.has(sewer_coord):
					_pending_data.append(sewer_coord)
					_ready_dirty = true
			# The waterfall plunge (-1 -> -2) is a jump, not a LevelLink: pre-build its landing like a link's far end.
			if center.y in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL] and generator.has_method("sewer"):
				var falls: Dictionary = generator.sewer().falls_between(x, z)
				if not falls.is_empty():
					var jump: Dictionary = falls["jump"]
					var land: Vector2 = jump["land"]
					links = links + [{"from_level": SewerRouteGenerator.LEVEL, "to_level": SewerRouteGenerator.LOWER_LEVEL,
						"from_cell": jump["cell"], "to_cell": Vector2i(floori(land.x), floori(land.y))}]
			for link_value in links:
				var link: Dictionary = link_value
				out.append({"chunk": Vector3i(x, 0, z), "link": link})
	return out


## What gets pre-built on the levels a nearby link reaches: the link's own chunk column plus the chunks within
## IMMEDIATE_MARGIN of the link cell (what the runner sees on arrival). Pre-building the whole 3x3 kept building
## the other storey on every chunk crossed while walking (-15 % average FPS in the sewer).
func _vertical_ready_set(center: Vector3i) -> Dictionary:
	var out := {}
	if not PlatformProfile.prebuild_linked_levels:
		return out   # low-memory phones and Quest: a ladder trip rebuilds the other storey instead of parking it (~30 MB)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	for entry in _nearby_links(center):
		var link: Dictionary = entry["link"]
		var column: Vector3i = entry["chunk"]
		var cell: Vector2i = link.get("from_cell", Vector2i(size / 2, size / 2))
		var at := Vector2(column.x * size + cell.x + .5, column.z * size + cell.y + .5)
		if tracked_player != null and Vector2(tracked_player.global_position.x, tracked_player.global_position.z) \
				.distance_to(at) > PREBUILD_LINK_RADIUS:
			continue   # a ladder the runner is only passing: walking past it must not build the other storey
		# both ends: the cell the link leaves from and the cell it lands on (a plunge or drop lands metres away)
		var landing: Vector2i = link.get("to_cell", cell)
		var points: Array[Vector2] = [at, Vector2(column.x * size + landing.x + .5, column.z * size + landing.y + .5)]
		for key in ["from_level", "to_level"]:
			var level := int(link.get(key, center.y))
			if level == center.y or absi(level - center.y) > PREBUILD_LEVEL_RANGE:
				continue
			for point in points:
				var home := Vector2i(floori(point.x / size), floori(point.y / size))
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var coord := Vector3i(home.x + dx, level, home.y + dz)
						var lo := Vector2(coord.x * size, coord.z * size)
						var nearest := Vector2(clampf(point.x, lo.x, lo.x + size), clampf(point.y, lo.y, lo.y + size))
						# inside the runner's 3x3 column only: parked chunks outside it are freed on the next level change
						if (dx == 0 and dz == 0 or nearest.distance_to(point) < IMMEDIATE_MARGIN) \
								and _near_column(coord, center) and generator.is_chunk_allowed(coord):
							out[coord] = true
	return out


## True while linked levels are still being pre-built in the background (the current window is already complete).
func is_preloading() -> bool:
	return not _pending_prebuild.is_empty() or (not _active_build.is_empty() and not _wanted_now.has(_active_build.get("coord")))


func prebuilt_chunk_count() -> int:
	var count := 0
	for coord in _dormant:
		if _ready_set.has(coord):
			count += 1
	return count


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


## The chunk itself plus the neighbours its edge cells read for seams (on its own level; see _build_structure_cell).
static func _generation_needs(coord: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = [coord]
	for step in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		out.append(Vector3i(coord.x + step.x, coord.y, coord.z + step.y))
	return out


## True when `coord` (and the seam neighbours it reads) is generated, so asking
## the generator for it costs nothing on this thread. Hunters' navigation on
## the levels next to the runner's waits for this instead of generating there.
func chunk_ready(coord: Vector3i) -> bool:
	return _chunk_generated(coord)


## Asks the background worker to generate `coord` ahead of need.
func request_generation(coord: Vector3i) -> void:
	if _gen_worker != null and not _chunk_generated(coord):
		_extra_generation[coord] = true


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
	# Only block on the background task when these chunks actually need generating:
	# it may be busy with chunks nobody is waiting for (another level's hunters).
	var needs: Array[Vector3i] = []
	for coord in coords:
		for need in _generation_needs(coord):
			if not generator.has_chunk_cached(need) and not needs.has(need):
				needs.append(need)
	if needs.is_empty():
		return
	if _gen_task != -1:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
		for coord in _gen_task_results:
			generator.adopt_chunk(coord, _gen_task_results[coord])
		_gen_task_results = {}
		needs = needs.filter(func(need: Vector3i) -> bool: return not generator.has_chunk_cached(need))
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
		if _ready_dirty and _last_player_chunk.x != 999999:
			# link data for the 3x3 has arrived: recompute which levels to pre-build
			_ready_dirty = false
			_ready_set = _vertical_ready_set(_last_player_chunk)
			_settle_dormant(_last_player_chunk, _wanted_now)
	var coords: Array[Vector3i] = []
	for coord in _pending_loads + _pending_prebuild + _extra_generation.keys():
		for need in _generation_needs(coord):
			if not generator.has_chunk_cached(need) and not coords.has(need):
				coords.append(need)
	for coord in _pending_data:
		if not generator.has_chunk_cached(coord) and not coords.has(coord):
			coords.append(coord)
	_pending_data.clear()
	for coord in _extra_generation.keys():
		if _chunk_generated(coord):
			_extra_generation.erase(coord)
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
	if not _pending_loads.is_empty() or not _pending_prebuild.is_empty() or not _pending_data.is_empty() or _gen_task != -1 \
			or not _extra_generation.is_empty():
		_queue_generation()
	if _pending_loads.is_empty() and _pending_unloads.is_empty() \
			and _active_build.is_empty() and _pending_prebuild.is_empty():
		return
	# A long queue (after a teleport) gets a little more time per frame so the window fills in seconds, not tens.
	var budget := minf(PlatformProfile.stream_budget_ms + STREAM_BUDGET_PER_QUEUED_MS * _pending_loads.size(),
		PlatformProfile.stream_budget_max_ms)
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
		if _active_build.is_empty() and _pending_loads.is_empty() and not _pending_prebuild.is_empty():
			# the current window is complete: pre-build the linked levels (parked when done)
			var next: Vector3i = _pending_prebuild[0]
			if not _chunk_generated(next):
				break
			_pending_prebuild.pop_front()
			if not _loaded.has(next) and not _dormant.has(next):
				_active_build = _create_chunk_build(next)
				_prefetch_chunk(next)
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


## Chunks built synchronously in one frame (teleports, the first load, level changes without pre-built chunks).
var sync_builds := 0
func _load_chunk(coord: Vector3i) -> void:
	sync_builds += 1
	var build := _create_chunk_build(coord)
	while not _advance_chunk_build(build, true):
		pass


## Chunk builds finished since begin() (benchmarks count rebuilds of chunks that were just unloaded). Counted when a
## build completes, so a background pre-build that a level change cancels and restarts is not a "rebuild".
var chunk_builds := 0
## The last chunks whose build finished (validators name a rebuilt chunk with it).
var recent_builds: Array[Vector3i] = []
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
	# Cave ceilings are uneven: the tunnels' roof steps between 3.1 and 3.7 m in 3-cell patches, the chambers rise to the
	# full storey.
	if coord.y == StreamedRouteGenerator.INFERNO_LEVEL:
		var cave_grid: Array = data["grid"]
		for z in StreamedRouteGenerator.CHUNK_SIZE:
			for x in StreamedRouteGenerator.CHUNK_SIZE:
				if x == 0 or z == 0 or x == StreamedRouteGenerator.CHUNK_SIZE - 1 or z == StreamedRouteGenerator.CHUNK_SIZE - 1:
					# the seam ring has one roof height on both sides, so the two chunks' roofs and walls meet exactly
					heights[Vector2i(x, z)] = INFERNO_SEAM_ROOF
				elif int(cave_grid[z][x]) == 0:
					heights[Vector2i(x, z)] = 3.1 + .2 * RefLook.pick(coord.x * StreamedRouteGenerator.CHUNK_SIZE / 3 + x / 3, coord.z * StreamedRouteGenerator.CHUNK_SIZE / 3 + z / 3, 9, 4)
	for cavern in data.get("inferno_caverns", []):
		for cell_value in (cavern as Dictionary)["cells"]:
			heights[cell_value] = LEVEL_HEIGHT - SLAB
		for hall in (cavern as Dictionary)["halls"]:
			var rect: Rect2i = hall
			for z in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					if x > 0 and z > 0 and x < StreamedRouteGenerator.CHUNK_SIZE - 1 and z < StreamedRouteGenerator.CHUNK_SIZE - 1:
						heights[Vector2i(x, z)] = LEVEL_HEIGHT - SLAB
	var open_above := {}
	var falls: Dictionary = data.get("falls", {})
	if not falls.is_empty() and coord.y == StreamedRouteGenerator.LOWER_SEWER_LEVEL:
		var drop: Rect2i = falls["void"]
		for z in range(drop.position.y, drop.end.y):
			for x in range(drop.position.x, drop.end.x):
				open_above[Vector2i(x, z)] = true
				heights[Vector2i(x, z)] = LEVEL_HEIGHT
	# Under the Mezzanine's grating the maze has no ceiling: the grating is the roof, and hunters see up through it
	if coord.y == 0 and generator.is_chunk_allowed(Vector3i(coord.x, StreamedRouteGenerator.MEZZANINE_LEVEL, coord.z)):
		for cell_value in generator.mezzanine().sight_cells(coord):
			open_above[cell_value as Vector2i] = true
	var shaft_cells: Dictionary = data.get("shaft_cells", {})
	for cell_value in shaft_cells:
		# a stairwell's lower level opens straight up the well: full-storey walls
		if not bool((shaft_cells[cell_value] as Dictionary)["upper"]):
			heights[cell_value] = LEVEL_HEIGHT
			# and so does its foot landing, under the head landing one storey up: a
			# sewer-height ceiling there was a slab across the well at mid-height (KT)
			for landing_value in ((shaft_cells[cell_value] as Dictionary)["well"] as Dictionary)["lower_landing"]:
				heights[landing_value] = LEVEL_HEIGHT - SLAB
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
		"room_anchor": room_anchor_map(data),
		"heights": heights,
		"corridor_h": corridor_h,
		"decor": null,
		"cell_index": 0,
		"phase": 0,
		"prop_index": 0,
		"fixture_index": 0,
		"pickup_index": 0,
		"prison_tasks": _prison_prop_tasks(data) if region == "prison" else [],
		"door_headers": door_headers(region_props, heights, corridor_h),
	}


## Set once a chunk build came back without its root (a script error while it was created hands back an empty Dictionary): the callers loop on
## "not finished", so an unguarded access threw the same SCRIPT ERROR every iteration and flooded the logs. Logged once, the build is dropped.
var _reported_broken_build := false


func _advance_chunk_build(build: Dictionary, immediate: bool) -> bool:
	if not build.has("root"):
		if not _reported_broken_build:
			_reported_broken_build = true
			push_warning("StreamedFacilityView3D: a chunk build has no root (the error that emptied it is logged above); dropping it")
		return true
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
				if PlatformProfile.maze_culling:
					# maze culling: one surface mesh per 15 x 15 tile, hidden when no line of sight reaches it
					var tiles: Dictionary = (build["surface"] as RefSurfaceMesh).build_tiles(
						RefTextures.array_material("floor"), RefTextures.array_material("wall"))
					var coord: Vector3i = build["coord"]
					var size := StreamedRouteGenerator.CHUNK_SIZE
					for t in tiles:
						var tile_node := MeshInstance3D.new()
						tile_node.name = "Surface%d" % t
						tile_node.mesh = tiles[t]
						tile_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						tile_node.set_meta("cull_tile", Vector2i(coord.x * size / RefSurfaceMesh.TILE + t % 3,
							coord.z * size / RefSurfaceMesh.TILE + t / 3))
						tile_node.add_to_group("cull_tile")
						root.add_child(tile_node)
				else:
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
				_spawn_stairwells(root, data, (build["coord"] as Vector3i).y)
				_spawn_mezzanine_rails(root, data)
				_spawn_shop_signs(root, data)
				if not (build["sewer_grid"] as Array).is_empty():
					_spawn_sewer_water(root, build["sewer_grid"], _jump_cell(data))
				_spawn_ramps(root, data, (build["coord"] as Vector3i).y)
				_spawn_falls(root, data, (build["coord"] as Vector3i).y)
				InfernoPitView.build(root, data)
				InfernoLandingPile.build(root, data)
				_spawn_breakables(root, data)
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
				_spawn_music_boxes(root, data)
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
					_bind_room_lights(root, data, coord, lamp_list)
				if not _all_lights_enabled:
					_set_lights_recursive(root, false)
				_loaded[coord] = root
				_chunk_data[coord] = data
				chunk_builds += 1
				recent_builds.append(coord)
				if recent_builds.size() > 32:
					recent_builds.pop_front()
				if not _wanted_now.has(coord) and (_ready_set.has(coord) or coord.y != _last_player_chunk.y \
						and _near_column(coord, _last_player_chunk)):
					_make_dormant(coord)
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
	if data.has("mezzanine_grid"):
		_build_mezzanine_cell(build, cell)
		return
	var ramp_cells: Dictionary = data.get("ramp_cells", {})
	if ramp_cells.has(cell):
		_build_ramp_cell(build, cell, ramp_cells[cell])
		return
	if (build["structural_voids"] as Dictionary).has(cell) and int(data.get("coord", Vector3i.ZERO).y) == StreamedRouteGenerator.INFERNO_LEVEL:
		# a lava channel: no wall and no floor here (InfernoPitView draws the lava, the rails and the blockers), the vault stays
		surface.add_ceiling(x, z, _height_in(build, cell), RefTextures.layer("floor", ceiling_kind),
			RefTextures.params("ceiling", ceiling_kind))
		return
	var shaft_cells: Dictionary = data.get("shaft_cells", {})
	if shaft_cells.has(cell):
		# a stairwell's well: the stairs (built per stairwell) fill it; the upper
		# level keeps its vault overhead, the lower one opens up to it over a
		# solid floor (the spiral's helix leaves a quarter of the well's floor bare)
		if bool((shaft_cells[cell] as Dictionary)["upper"]):
			surface.add_ceiling(x, z, _height_in(build, cell), RefTextures.layer("floor", ceiling_kind),
				RefTextures.params("ceiling", ceiling_kind))
		else:
			grid.set_cell_item(Vector3i(x, 0, z), _col_floor_item)
			surface.add_floor(x, z, RefTextures.layer("floor", "concrete1"), RefTextures.params("floor", "concrete1"))
		return
	if int(grid_data[z][x]) == 0:
		var height := _height_in(build, cell)
		var kind := _ref_floor_kind(build, x, z)
		if (data.get("crawl_cells", []) as Array).has(cell):
			kind = "hazard"   # the hazard plate under a sewer crawl-under pipe
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
			if not outside and _is_lava(build, Vector2i(nx, nz)):
				# the lip of a lava channel: the ground's own wall runs down to the basin, so the pit has sides
				var lip_kind := _ref_wall_kind(build, x, z, nx, nz)
				surface.add_wall(x, z, step, RefTextures.layer("wall", lip_kind), RefTextures.params("wall", lip_kind),
					0.0, InfernoPitView.BASIN_Y, LEVEL_HEIGHT)
				continue
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
		# The one jump cell behind the railing gap is open: stepping into it is the plunge.
		if cell != _jump_cell(data):
			grid.set_cell_item(Vector3i(x, 0, z), _col_channel_item)
		surface.add_ceiling(x, z, _height_in(build, cell), RefTextures.layer("floor", ceiling_kind),
			RefTextures.params("ceiling", ceiling_kind))
		for step_value in RefDecor.DIRS:
			var step: Vector2i = step_value
			var n := cell + step
			if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size \
					or _sewer_code(build, n.x, n.y) == SewerRouteGenerator.FALL:
				continue
			# the shaft is lined in the sewer's own brick, so it reads as part of the network, not a rock box
			var shaft_kind := _ref_wall_kind(build, n.x, n.y, x, z)
			surface.add_wall(n.x, n.y, -step, RefTextures.layer("wall", shaft_kind),
				RefTextures.params("wall", shaft_kind), 0.0, -LEVEL_HEIGHT, LEVEL_HEIGHT)
	else:
		# every level below the maze keeps its wall colliders inside its own storey
		grid.set_cell_item(Vector3i(x, 0, z), _col_sewer_wall_item \
			if (build["coord"] as Vector3i).y < 0 else _col_wall_item)
		# a room door's cell: wall over the frame up to both rooms' ceilings, and a soffit on the frame (no see-through)
		var header: Dictionary = (build["door_headers"] as Dictionary).get(cell, {})
		if not header.is_empty():
			var across: Vector2i = header["normal"]
			var front_kind := _ref_wall_kind(build, x, z, x + across.x, z + across.y)
			var back_kind := _ref_wall_kind(build, x, z, x - across.x, z - across.y)
			add_door_header(surface, cell, header, [RefTextures.layer("wall", front_kind), RefTextures.params("wall", front_kind)],
				[RefTextures.layer("wall", back_kind), RefTextures.params("wall", back_kind)])
		for step_value in RefDecor.DIRS:
			var step: Vector2i = step_value
			var nx: int = x + step.x
			var nz: int = z + step.y
			# faces toward another chunk are emitted too; a hidden face is cheaper
			# than a missing one
			var face_height := float(build["corridor_h"])
			var room_top := -1.0
			var room_floor := 0.0
			var face_bottom := 0.0
			if nx >= 0 and nz >= 0 and nx < size and nz < size:
				# ramp tunnels, channels and the falls' drop are open space too, though the
				# grid keeps them off the walk graph
				var open_space := (data.get("ramp_cells", {}) as Dictionary).has(Vector2i(nx, nz)) \
					or (data.get("shaft_cells", {}) as Dictionary).has(Vector2i(nx, nz)) \
					or _sewer_code(build, nx, nz) in [SewerRouteGenerator.WATER, SewerRouteGenerator.FALL] \
					or _is_lava(build, Vector2i(nx, nz))
				if int(grid_data[nz][nx]) != 0 and not open_space:
					continue
				face_height = _height_in(build, Vector2i(nx, nz))
				if _is_lava(build, Vector2i(nx, nz)):
					face_bottom = InfernoPitView.BASIN_Y      # the rock round a lava channel runs down to its basin
				var ramp_info: Dictionary = (data.get("ramp_cells", {}) as Dictionary).get(Vector2i(nx, nz), {})
				if not ramp_info.is_empty():
					# a ramp tunnel is one room two storeys tall: both levels' side walls
					# paint one span, lower floor to the slope's vault, in a single repeat (two
					# put a cornice and skirting across the shaft at 3.6 m instead)
					room_floor = -LEVEL_HEIGHT if bool(ramp_info["upper"]) else 0.0
					room_top = face_height if bool(ramp_info["upper"]) else LEVEL_HEIGHT + RAMP_VAULT
			var wall_kind := _ref_wall_kind(build, x, z, nx, nz)
			if room_top > 0.0:
				wall_kind = _ramp_wall_kind(build, nx, nz)
			surface.add_wall(x, z, step, RefTextures.layer("wall", wall_kind),
				RefTextures.params("wall", wall_kind), face_height, face_bottom, room_top, room_floor, 1 if room_top > 0.0 else 0)


## A lava channel cell of level -3 (rock to the walk grid, no wall and no floor of its own: InfernoPitView draws it).
static func _is_lava(build: Dictionary, cell: Vector2i) -> bool:
	return int((build["coord"] as Vector3i).y) == StreamedRouteGenerator.INFERNO_LEVEL \
		and (build["structural_voids"] as Dictionary).has(cell)


## One cell of a Mezzanine chunk: grating or deck underfoot (a floor collider, drawn), open air everywhere else (no wall,
## no collider, no ceiling: the double-height void over the maze). The railings come in _spawn_mezzanine_rails.
func _build_mezzanine_cell(build: Dictionary, cell: Vector2i) -> void:
	var data: Dictionary = build["data"]
	var code := int((data["mezzanine_grid"] as Array)[cell.y][cell.x])
	if not MezzanineRouteGenerator.is_walkable(code):
		return
	var kind := "grate" if code == MezzanineRouteGenerator.GRATE else "metal2"
	(build["grid"] as GridMap).set_cell_item(Vector3i(cell.x, 0, cell.y), _col_floor_item)
	(build["surface"] as RefSurfaceMesh).add_floor(cell.x, cell.y, RefTextures.layer("floor", kind),
		RefTextures.params("floor", kind))


## Railings on every Mezzanine edge that drops to open air: an iron top bar and a collider, waist high.
func _spawn_mezzanine_rails(root: Node3D, data: Dictionary) -> void:
	if not data.has("mezzanine_grid"):
		return
	var body := StaticBody3D.new()
	body.name = "CatwalkRails"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shapes := {}
	for feature_value in data.get("features", []):
		var feature: Dictionary = feature_value
		if String(feature.get("type", "")) != "catwalkRail":
			continue
		var cell: Vector2i = feature["cell"]
		var side: Vector2i = feature["side"]
		var mid := Vector3(cell.x + .5 + side.x * .47, MezzanineRouteGenerator.RAIL_HEIGHT * .5, cell.y + .5 + side.y * .47)
		var size := Vector3(.06 if side.x != 0 else 1.0, MezzanineRouteGenerator.RAIL_HEIGHT, .06 if side.y != 0 else 1.0)
		var along_x := side.x == 0
		if not shapes.has(along_x):    # two shared boxes, one per direction, not one per rail segment
			var box := BoxShape3D.new()
			box.size = size
			shapes[along_x] = box
		var collider := CollisionShape3D.new()
		collider.shape = shapes[along_x]
		collider.position = mid
		body.add_child(collider)
		_add_rail_bar(surface, Vector3(mid.x, MezzanineRouteGenerator.RAIL_HEIGHT - .04, mid.z), Vector3(size.x, .06, size.z))
		_add_rail_bar(surface, Vector3(mid.x, MezzanineRouteGenerator.RAIL_HEIGHT * .5, mid.z), Vector3(size.x, .04, size.z))
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Rails"
	mesh.mesh = surface.commit()
	mesh.material_override = _stair_iron()
	root.add_child(mesh)


func _add_rail_bar(surface: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var lo := center - size * .5
	var hi := center + size * .5
	var corners := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	for face in [[0, 2, 1, 0, 3, 2], [4, 5, 6, 4, 6, 7], [0, 4, 7, 0, 7, 3], [1, 2, 6, 1, 6, 5], [3, 7, 6, 3, 6, 2], [0, 1, 5, 0, 5, 4]]:
		for index in face:
			surface.add_vertex(corners[index])


static func _sewer_code(build: Dictionary, x: int, z: int) -> int:
	var sewer_grid: Array = build["sewer_grid"]
	return SewerRouteGenerator.DRY if sewer_grid.is_empty() else int(sewer_grid[z][x])


## One cell of a ramp tunnel. On its upper level: the vault overhead and the
## slope underfoot (no flat floor, no floor collider); on its lower level:
## nothing at all, the tunnel opening straight up to the level above. The
## slope's collider is built once per ramp (_spawn_ramps).
func _build_ramp_cell(build: Dictionary, cell: Vector2i, info: Dictionary) -> void:
	var surface := build["surface"] as RefSurfaceMesh
	var ramp: Dictionary = info["ramp"]
	# The tunnel mouth at the slope's foot: the slope's ceiling is its upper level's,
	# a storey above the foot landing's, and nothing closed the step between them
	# on the lower level, so looking down the ramp showed the storey above through
	# it (KT, LEVEL -2). A header wall faces up the slope from the landing's ceiling
	# to the top of the storey; above that the upper level's rock wall already
	# faces the slope.
	var down := int(signf(float(ramp["bottom_x"]) - float(ramp["top_x"])))
	var end_x := int(ramp["bottom_x"]) - (1 if down > 0 else 0)
	if cell.x == end_x and not bool(info["upper"]):
		var landing := Vector2i(end_x + down, cell.y)
		var kind := _ramp_wall_kind(build, cell.x, cell.y)
		var lintel := _height_in(build, landing)
		if LEVEL_HEIGHT > lintel:
			surface.add_wall(landing.x, landing.y, Vector2i(-down, 0), RefTextures.layer("wall", kind),
				RefTextures.params("wall", kind), LEVEL_HEIGHT, lintel, LEVEL_HEIGHT + RAMP_VAULT, 0.0, 1)
	if not bool(info["upper"]):
		_close_ramp_sides(build, cell)
		return
	var ceiling_kind := String((build["style"] as Dictionary)["ceiling"])
	surface.add_ceiling(cell.x, cell.y, _height_in(build, cell), RefTextures.layer("floor", ceiling_kind),
		RefTextures.params("ceiling", ceiling_kind))
	var y0 := _ramp_surface_y(ramp, float(cell.x))
	var y1 := _ramp_surface_y(ramp, float(cell.x + 1))
	surface.add_quad_floor(Vector3(cell.x, y0, cell.y), Vector3(cell.x + 1, y1, cell.y),
		Vector3(cell.x + 1, y1, cell.y + 1), Vector3(cell.x, y0, cell.y + 1),
		RefTextures.layer("floor", RAMP_FLOOR_KIND), RefTextures.params("floor", RAMP_FLOOR_KIND))


## The slope's side on its lower level where open floor runs alongside it (an
## Inferno maze corridor beside the collector ramp, INFERNO): the grid keeps the
## slope solid, so neither side had a face and the slope hung in a gap with the
## corridor's far wall behind it. A ramp wall two storeys of paint tall faces
## into the tunnel, and the corridor gets its own wall facing out.
func _close_ramp_sides(build: Dictionary, cell: Vector2i) -> void:
	var data: Dictionary = build["data"]
	var grid_data: Array = data["grid"]
	var ramp_cells: Dictionary = data.get("ramp_cells", {})
	var surface := build["surface"] as RefSurfaceMesh
	var size := StreamedRouteGenerator.CHUNK_SIZE
	for step in [Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + step
		if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size or ramp_cells.has(n) or int(grid_data[n.y][n.x]) != 0:
			continue
		var inside := _ramp_wall_kind(build, cell.x, cell.y)
		surface.add_wall(n.x, n.y, -step, RefTextures.layer("wall", inside), RefTextures.params("wall", inside),
			LEVEL_HEIGHT, 0.0, LEVEL_HEIGHT + RAMP_VAULT, 0.0, 1)
		var outside := _ref_wall_kind(build, cell.x, cell.y, n.x, n.y)
		surface.add_wall(cell.x, cell.y, step, RefTextures.layer("wall", outside), RefTextures.params("wall", outside),
			_height_in(build, n))


## A ramp tunnel's wall paint on both its levels: the sewer brick of the level it
## starts on (ramps start on sewer levels), so the Inferno storey under the
## collector ramp does not switch style half way up the tunnel wall.
func _ramp_wall_kind(build: Dictionary, x: int, z: int) -> String:
	var coord: Vector3i = build["coord"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	return RefLook.wall_kind("sewer", "", coord.x * size + x, coord.z * size + z)


## Height of a ramp's walking surface at chunk-local x, relative to its upper level's floor.
static func _ramp_surface_y(ramp: Dictionary, x: float) -> float:
	var top_x := float(ramp["top_x"])
	var bottom_x := float(ramp["bottom_x"])
	var t := clampf((x - top_x) / (bottom_x - top_x), 0.0, 1.0)
	return -LEVEL_HEIGHT * t


## Every stairwell whose upper end is this chunk's level (the upper chunk owns the
## stairs, as with ramps, so its colliders stay inside its own storey band):
## the switchback's flights, mid landing and divider, or the spiral's helix and
## post; handrails, guard rails round the top landing's opening, level signs and
## a landing light. Walkable surfaces are smooth slopes whose colliders are the
## visible surfaces themselves (no snagging steps).
func _spawn_stairwells(root: Node3D, data: Dictionary, level: int) -> void:
	for well_value in data.get("stairwells", []):
		var well: Dictionary = well_value
		if int(well["upper"]) != level:
			continue
		var holder := Node3D.new()
		holder.name = "Stairwell_%s" % well["kind"]
		root.add_child(holder)
		var body := StaticBody3D.new()
		body.name = "StairCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		holder.add_child(body)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var floor_y := -LEVEL_HEIGHT
		if String(well["kind"]) == "stairs":
			for flight_value in well["flights"]:
				var f: Dictionary = flight_value
				_add_stair_wedge(surface, body, float(f["x0"]), float(f["x1"]), float(f["z_low"]), float(f["z_high"]),
					floor_y, floor_y + float(f["y_low"]), floor_y + float(f["y_high"]))
			var interior: Rect2i = well["interior"]
			var north := bool(well["north"])
			var mid_z0 := float(interior.position.y) if north else float(interior.end.y - 2)
			_add_stair_box(surface, body, Vector3(interior.position.x, floor_y, mid_z0),
				Vector3(interior.end.x, floor_y + RISE_HALF, mid_z0 + 2.0))
			# the divider between the flights, floor to the upper floor
			var div_x := float(interior.position.x + 2)
			var div_z0 := float(interior.position.y + 2) if north else float(interior.position.y + 2)
			_add_stair_box(surface, body, Vector3(div_x, floor_y, div_z0), Vector3(div_x + 1.0, 0.0, float(interior.end.y - 2)))
			_add_handrails_switchback(holder, well)
		else:
			_add_spiral(surface, body, holder, well, floor_y)
		_add_landing_guards(body, holder, well)
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "Stairs"
		mesh.mesh = surface.commit()
		var material := StandardMaterial3D.new()
		material.albedo_texture = RefTextures.texture("floor", "concrete1")
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		MaterialLook.tame(material)
		mesh.material_override = material
		holder.add_child(mesh)
		_add_stairwell_signs_and_light(holder, well)


const RISE_HALF := 2.0
const STAIR_RAIL_HEIGHT := 0.95


## A solid wedge under a straight flight: its top is the walking slope from
## (z_low, y_low) to (z_high, y_high) across x0..x1, its bottom the floor.
func _add_stair_wedge(surface: SurfaceTool, body: StaticBody3D, x0: float, x1: float, z_low: float, z_high: float,
		floor_y: float, y_low: float, y_high: float) -> void:
	var points := PackedVector3Array([Vector3(x0, floor_y, z_low), Vector3(x1, floor_y, z_low),
		Vector3(x0, floor_y, z_high), Vector3(x1, floor_y, z_high),
		Vector3(x0, y_low, z_low), Vector3(x1, y_low, z_low), Vector3(x0, y_high, z_high), Vector3(x1, y_high, z_high)])
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	_quad_up(surface, points[4], points[5], points[7], points[6])
	_quad_up(surface, points[0], points[1], points[5], points[4])
	_quad_up(surface, points[2], points[6], points[7], points[3])


func _add_stair_box(surface: SurfaceTool, body: StaticBody3D, lo: Vector3, hi: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = hi - lo
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = (lo + hi) * .5
	body.add_child(collider)
	_quad_up(surface, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z))
	_quad_up(surface, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z))
	_quad_up(surface, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z))
	_quad_up(surface, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z))
	_quad_up(surface, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z))


## Two triangles of a quad, wound both ways so it shows from either side.
static func _quad_up(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d], [a, c, b], [a, d, c]]:
		for p in tri:
			surface.add_vertex(p)


## The spiral: a smooth helicoid from the post out to the shaft's square walls,
## 270 degrees from the landing round to the landing one storey up, its
## collider the same triangles; the post, and a handrail spiralling round it.
func _add_spiral(surface: SurfaceTool, body: StaticBody3D, holder: Node3D, well: Dictionary, floor_y: float) -> void:
	var center: Vector2 = well["spiral_center"]
	var start := float(well["spiral_start"])
	var steps := 54
	var faces := PackedVector3Array()
	var inner := 0.55
	for i in steps:
		var a0 := deg_to_rad(start + 270.0 * float(i) / steps)
		var a1 := deg_to_rad(start + 270.0 * float(i + 1) / steps)
		var y0 := floor_y + LEVEL_HEIGHT * float(i) / steps
		var y1 := floor_y + LEVEL_HEIGHT * float(i + 1) / steps
		var d0 := Vector2(sin(a0), cos(a0))
		var d1 := Vector2(sin(a1), cos(a1))
		# Each triangle's slope is set by the arc at its inner edge (atan(rise per radian / r)), so the
		# helix is cut into rings: only the one hugging the post is steeper than a walkable floor, and
		# the walking line (r ~1.6) stays near the true 28 degree pitch instead of snagging on a
		# 57 degree sliver spanning post to wall.
		var radii := [inner, .95, 1.4, 1.9]
		radii.append(2.48 / maxf(absf(d0.x), absf(d0.y)))
		var radii1 := radii.duplicate()
		radii1[radii1.size() - 1] = 2.48 / maxf(absf(d1.x), absf(d1.y))
		for ring in radii.size() - 1:
			var a := float(radii[ring])
			var b0 := float(radii[ring + 1])
			var b1 := float(radii1[ring + 1])
			var p0 := Vector3(center.x + d0.x * a, y0, center.y + d0.y * a)
			var p1 := Vector3(center.x + d0.x * b0, y0, center.y + d0.y * b0)
			var p2 := Vector3(center.x + d1.x * b1, y1, center.y + d1.y * b1)
			var p3 := Vector3(center.x + d1.x * a, y1, center.y + d1.y * a)
			faces.append_array(PackedVector3Array([p0, p1, p2, p0, p2, p3]))
			_quad_up(surface, p0, p1, p2, p3)
	# The top end: the wedge between the helix's last radial and the landing row
	# is open well at the upper floor, so a slab fills it (the helix's end and the
	# landing then meet along an edge, not at one corner); a rail runs along the
	# start radial, where the helix begins a storey below.
	var outward := float(well["outward"])
	var interior: Rect2i = well["interior"]
	var landing_z := float(interior.end.y - 1) if outward > 0 else float(interior.position.y + 1)
	var corners: Array[Vector3] = [Vector3(center.x, 0.0, center.y)]
	for angle in [start + 270.0, start]:
		var dir := Vector2(sin(deg_to_rad(angle)), cos(deg_to_rad(angle)))
		var t := (landing_z - center.y) / dir.y
		corners.append(Vector3(center.x + dir.x * t, 0.0, landing_z))
	var slab := ConvexPolygonShape3D.new()
	var slab_points := PackedVector3Array()
	for corner in corners:
		slab_points.append(corner)
		slab_points.append(corner + Vector3(0, -.2, 0))
	slab.points = slab_points
	var slab_collider := CollisionShape3D.new()
	slab_collider.shape = slab
	body.add_child(slab_collider)
	for tri in [[corners[0], corners[1], corners[2]], [corners[0], corners[2], corners[1]]]:
		for p in tri:
			surface.add_vertex(p)
	var rail_dir := (corners[2] - corners[0]).normalized()
	var rail_from: Vector3 = corners[0] + rail_dir * .4
	var rail_len := rail_from.distance_to(corners[2])
	var rail_shape := BoxShape3D.new()
	rail_shape.size = Vector3(.06, 1.1, rail_len)
	var rail := CollisionShape3D.new()
	rail.shape = rail_shape
	body.add_child(rail)
	rail.position = (rail_from + corners[2]) * .5 + Vector3(0, .55, 0)
	rail.rotation.y = atan2(rail_dir.x, rail_dir.z)
	_add_rail_polyline(holder, [rail_from + Vector3(0, STAIR_RAIL_HEIGHT, 0), corners[2] + Vector3(0, STAIR_RAIL_HEIGHT, 0)])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var post_shape := CylinderShape3D.new()
	post_shape.radius = .4
	post_shape.height = LEVEL_HEIGHT
	var post := CollisionShape3D.new()
	post.shape = post_shape
	post.position = Vector3(center.x, floor_y + LEVEL_HEIGHT * .5, center.y)
	body.add_child(post)
	var post_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .4
	cylinder.bottom_radius = .4
	cylinder.height = LEVEL_HEIGHT
	post_mesh.mesh = cylinder
	post_mesh.position = post.position
	post_mesh.material_override = _stair_iron()
	holder.add_child(post_mesh)
	var rail_points: Array[Vector3] = []
	for i in 28:
		var a := deg_to_rad(start + 270.0 * float(i) / 27.0)
		rail_points.append(Vector3(center.x + sin(a) * (inner + .12), floor_y + LEVEL_HEIGHT * float(i) / 27.0 + STAIR_RAIL_HEIGHT,
			center.y + cos(a) * (inner + .12)))
	_add_rail_polyline(holder, rail_points)


## Handrails along both walls of each flight of a switchback.
func _add_handrails_switchback(holder: Node3D, well: Dictionary) -> void:
	for flight_value in well["flights"]:
		var f: Dictionary = flight_value
		for x in [float(f["x0"]) + .06, float(f["x1"]) - .06]:
			_add_rail_polyline(holder, [Vector3(x, -LEVEL_HEIGHT + float(f["y_low"]) + STAIR_RAIL_HEIGHT, float(f["z_low"])),
				Vector3(x, -LEVEL_HEIGHT + float(f["y_high"]) + STAIR_RAIL_HEIGHT, float(f["z_high"]))])


func _add_rail_polyline(holder: Node3D, points: Array) -> void:
	var iron := _stair_iron()
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var segment := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(.05, .05, a.distance_to(b) + .02)
		segment.mesh = bar
		segment.material_override = iron
		segment.position = (a + b) * .5
		holder.add_child(segment)
		segment.look_at_from_position(segment.position, b, Vector3.UP if absf((b - a).normalized().y) < .99 else Vector3.RIGHT)


## Guard rails round the top landing where it meets the open well, with a gap
## where the stairs arrive: a solid 1.1 m rail (collider) and its iron bars.
func _add_landing_guards(body: StaticBody3D, holder: Node3D, well: Dictionary) -> void:
	var interior: Rect2i = well["interior"]
	var north := bool(well["north"])
	var landing_cells: Dictionary = well["upper_landing"]
	var shaft: Dictionary = well["shaft"]
	# the well cell the stairs arrive from: just back along the path from its top
	var path: Array = well["link"]["path"]
	var top_point: Vector3 = path[path.size() - 2]
	var before: Vector3 = path[path.size() - 3]
	var back := top_point + (before - top_point).normalized() * .3
	var arrival := Vector2i(floori(back.x), floori(back.z))
	for cell_value in landing_cells:
		var cell: Vector2i = cell_value
		for step_value in RefDecor.DIRS:
			var step: Vector2i = step_value
			var n: Vector2i = cell + step
			if not shaft.has(n) or n == arrival:
				continue
			# a spiral's landing row opens onto its top slab; the slab's own rail guards the drop
			if String(well["kind"]) == "spiral" and step == Vector2i(0, -int(well["outward"])):
				continue
			# the arriving flight of a switchback is two cells wide
			if String(well["kind"]) == "stairs" and absi(n.x - arrival.x) <= 1 and n.y == arrival.y:
				continue
			var mid := Vector3(cell.x + .5 + step.x * .48, .55, cell.y + .5 + step.y * .48)
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.0 if step.y != 0 else .06, 1.1, .06 if step.y != 0 else 1.0)
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = mid
			body.add_child(collider)
			var bar := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(shape.size.x, .05, shape.size.z)
			bar.mesh = box
			bar.material_override = _stair_iron()
			bar.position = Vector3(mid.x, STAIR_RAIL_HEIGHT, mid.z)
			holder.add_child(bar)


## A level sign on each landing ("LEVEL n") and a budgeted light over the well.
func _add_stairwell_signs_and_light(holder: Node3D, well: Dictionary) -> void:
	var interior: Rect2i = well["interior"]
	var north := bool(well["north"])
	var mid_x := float(interior.position.x) + 2.5
	# on the side wall beside the landing (the doorway end is open), facing into the well
	var landing: Vector2i = well["landing"]
	for level_value in [int(well["upper"]), int(well["upper"]) - 1]:
		var level := int(level_value)
		var sign := Label3D.new()
		sign.text = "LEVEL %+d" % level if level != 0 else "LEVEL 0"
		sign.font_size = 48
		sign.pixel_size = .006
		sign.modulate = Color("e8c25a")
		sign.position = Vector3(float(interior.position.x) + .04, float(level - int(well["upper"])) * LEVEL_HEIGHT + 2.1,
			float(landing.y) + .5)
		sign.rotation.y = PI / 2.0
		holder.add_child(sign)
	var light := OmniLight3D.new()
	light.light_color = Color("ffd29a")
	light.light_energy = .7
	light.omni_range = 7.0
	light.position = Vector3(mid_x, -LEVEL_HEIGHT * .5 + 1.4, float(interior.position.y) + float(interior.size.y) * .5)
	holder.add_child(light)
	LampField.make_budgeted(light)


func _stair_iron() -> StandardMaterial3D:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("3b3f42")
	MaterialLook.tame(iron, true)
	return iron


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
			lip.z + (-FALLS_SPOUT if bool(falls["north"]) else FALLS_SPOUT))
		root.add_child(sheet)
		_add_falls_spillway(root, lip, bool(falls["north"]))
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
		mist.position = Vector3(lip.x, SewerRouteGenerator.WATER_SURFACE + .1, lip.z + (-FALLS_SPOUT - .65 if bool(falls["north"]) else FALLS_SPOUT + .65))
		root.add_child(mist)
		_add_falls_impact(root, Vector3(lip.x, SewerRouteGenerator.WATER_SURFACE, lip.z + (-FALLS_SPOUT - .75 if bool(falls["north"]) else FALLS_SPOUT + .75)))
		_add_falls_sound(root, mist.position)


## The top of a fall (level -1): the spur channel's water runs on over the lip with a crest of foam, and a cool light on
## the spur shows the water, the sheet's top and the shaft walls (it read as a dark box). No slab behind it (KT).
func _add_falls_spillway(root: Node3D, lip: Vector3, north: bool) -> void:
	var dir := -1.0 if north else 1.0                  # the way the water runs, toward and over the lip
	var y := SewerRouteGenerator.WATER_SURFACE
	var crest := MeshInstance3D.new()
	crest.name = "FallsCrest"
	var strip := QuadMesh.new()
	strip.size = Vector2(3.0, 1.0)
	crest.mesh = strip
	crest.rotation = Vector3(-PI / 2.0 + dir * .22, 0, 0)
	crest.position = Vector3(lip.x, y + .02, lip.z - dir * .45)
	crest.material_override = _foam_material(.8)
	crest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(crest)
	var light := OmniLight3D.new()
	light.name = "FallsLipLight"
	light.position = Vector3(lip.x, y + 1.6, lip.z - dir * 1.2)
	light.light_color = Color("7fd1b0")
	light.light_energy = 1.4
	light.omni_range = 9.0
	light.shadow_enabled = false
	root.add_child(light)


## The bottom of a fall (level -2): foam churning where the sheet lands, a standing ring that spreads over the cistern,
## and a cool light that lights the pool and the shaft above it.
func _add_falls_impact(root: Node3D, at: Vector3) -> void:
	var churn := MeshInstance3D.new()
	churn.name = "FallsFoam"
	var disc := QuadMesh.new()
	disc.size = Vector2(4.2, 2.6)
	churn.mesh = disc
	churn.rotation = Vector3(-PI / 2.0, 0, 0)
	churn.position = at + Vector3(0, .03, 0)
	churn.material_override = _foam_material(1.0)
	churn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(churn)
	var light := OmniLight3D.new()
	light.name = "FallsPoolLight"
	light.position = at + Vector3(0, 1.4, 0)
	light.light_color = Color("8fe0c0")
	light.light_energy = 1.8
	light.omni_range = 10.0
	light.shadow_enabled = false
	root.add_child(light)


static var _foam_cache := {}


static func _foam_material(strength: float) -> ShaderMaterial:
	if _foam_cache.has(strength):
		return _foam_cache[strength]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
uniform float strength = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 c = UV - vec2(.5);
	float edge = smoothstep(.5, .15, length(c * vec2(1.0, 1.5)));
	float t = TIME * .6;
	float f = n(UV * vec2(14.0, 9.0) + vec2(t, -t * .7)) * .6 + n(UV * vec2(31.0, 20.0) - vec2(t * 1.3, t)) * .4;
	ALBEDO = mix(vec3(.55, .66, .6), vec3(.92, .97, .93), f);
	ALPHA = edge * smoothstep(.25, .85, f) * strength;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("strength", strength)
	_foam_cache[strength] = material
	return material


var _breakable_nodes := {}


## One interactable per breakable spec of the chunk (seals across tunnels, boards, pipes), at its spec's state.
func _spawn_breakables(root: Node3D, data: Dictionary) -> void:
	for spec_value in data.get("breakables", []):
		var spec: Dictionary = spec_value
		var extras: Dictionary = spec.get("extras", {})
		var centre: Vector2 = extras.get("centre", Vector2(spec["cell"]) + Vector2(.5, .5))
		var node := RouteInteractable3D.new()
		node.name = "Breakable_%s" % String(spec["id"]).replace(":", "_")
		node.kind = RouteInteractable3D.Kind.BREAKABLE
		node.position = Vector3(centre.x, 0.0, centre.y)
		node.rotation.y = BreakableView.yaw_of(spec)
		node.configure_breakable(spec, world_state.breach_hp(spec), world_state.breach_open(String(spec["id"])))
		node.changed.connect(func(event: Dictionary) -> void:
			if String(event.get("what", "")) == "breakable_hit":
				breakable_hit.emit(String(event["id"]), String(event["tool"])))
		root.add_child(node)
		_breakable_nodes[String(spec["id"])] = node


## The state of a breakable changed (the host's "stream_breach"): its piece, if its chunk is loaded.
func apply_breach(id: String, hp: int, opened: bool) -> void:
	var node := _breakable_nodes.get(id) as RouteInteractable3D
	if node == null or not is_instance_valid(node):
		_breakable_nodes.erase(id)
		return
	node.apply_breakable_state(hp, opened)


func _add_falls_sound(root: Node3D, at: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream := FallsLoop.stream()
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
func _spawn_sewer_water(root: Node3D, sewer_grid: Array, gap: Vector2i = Vector2i(-1, -1)) -> void:
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
	_spawn_channel_railings(root, sewer_grid, gap)


## The falls' jump cell of a chunk, or (-1, -1): the railing gap and the open collider sit on it.
static func _jump_cell(data: Dictionary) -> Vector2i:
	var falls: Dictionary = data.get("falls", {})
	return (falls["jump"] as Dictionary)["cell"] if falls.has("jump") and int(data.get("level", 0)) == StreamedRouteGenerator.SEWER_LEVEL \
		else Vector2i(-1, -1)


## Iron railings along every edge where a walkway, room floor or deck meets open
## water: a post at each metre and a top and mid rail, as two MultiMeshes per
## chunk. They are the visible reason the channel collider stops you.
func _spawn_channel_railings(root: Node3D, sewer_grid: Array, gap: Vector2i = Vector2i(-1, -1)) -> void:
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
				if n == gap:
					continue            # the deliberate jump: no rail where the ledge meets the open drop cell
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


## Cell -> the rect origin of the room it belongs to, built by the same pass as _room_type_map (same cells, same
## last-room-wins order), so a room's floor is one kind.
static func room_anchor_map(data: Dictionary) -> Dictionary:
	var map := {}
	var grid: Array = data.get("grid", [])
	for room_value in data.get("rooms", []):
		var rect: Rect2i = (room_value as Dictionary).get("rect", Rect2i())
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var on_border := x == rect.position.x or z == rect.position.y or x == rect.end.x - 1 or z == rect.end.y - 1
				if on_border and (_is_wall_at(grid, x, z) or _is_doorway(grid, rect, x, z)):
					continue
				map[Vector2i(x, z)] = rect.position
	return map


## The cells a room door stands in -> {"normal" (through the door), "front_h" / "back_h" (the ceilings either side)}:
## the header over the frame closes the opening up to both ceilings (docs/DOORWAY_CLEARANCE.md).
static func door_headers(region_props: Array, heights: Dictionary, corridor_h: float) -> Dictionary:
	var out := {}
	for prop_value in region_props:
		var prop: Dictionary = prop_value
		if not PropModelCatalog.is_room_door(String(prop.get("type", ""))):
			continue
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		var centre := Vector2(cell) + Vector2(.5, .5) + (prop.get("placement_offset", Vector2.ZERO) as Vector2)
		var yaw := float(prop.get("yaw", 0.0))
		var along := Vector2(cos(yaw), -sin(yaw))
		var through := Vector2(sin(yaw), cos(yaw))
		var normal := Vector2i(roundi(through.x), roundi(through.y))
		var span := int(prop.get("door_span", 1))
		var cells: Array[Vector2i] = []
		if span == 2:
			cells = [Vector2i((centre - along * .5).floor()), Vector2i((centre + along * .5).floor())]
		else:
			cells = [Vector2i(centre.floor())]
		for door_cell in cells:
			out[door_cell] = {"normal": normal, "header_y": DoorwayFrames.header_y(String(prop.get("type", ""))),
				"front_h": float(heights.get(door_cell + normal, corridor_h)),
				"back_h": float(heights.get(door_cell - normal, corridor_h))}
	return out


## The header's faces on `surface`: a wall face toward each side from the soffit up to that side's ceiling, and the
## soffit itself. `front` / `back`: [texture layer, params] of the wall theme on each side.
static func add_door_header(surface: RefSurfaceMesh, cell: Vector2i, header: Dictionary, front: Array, back: Array) -> void:
	var across: Vector2i = header["normal"]
	for side in [across, -across]:
		var look: Array = front if side == across else back
		var top := float(header["front_h"] if side == across else header["back_h"])
		var soffit := float(header.get("header_y", DoorwayFrames.HEADER_Y))
		if top > soffit:
			surface.add_wall(cell.x, cell.y, side, float(look[0]), look[1], top, soffit, top)
	surface.add_ceiling(cell.x, cell.y, float(header.get("header_y", DoorwayFrames.HEADER_Y)), float(front[0]), front[1])


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
	if coord.y == StreamedRouteGenerator.INFERNO_LEVEL:
		return INFERNO_SEAM_ROOF
	var neighbour := Vector3i(coord.x + floori(float(nx) / size), coord.y, coord.z + floori(float(nz) / size))
	return RefLook.corridor_height(generator.region_for(neighbour), neighbour)


func _ref_floor_kind(build: Dictionary, x: int, z: int) -> String:
	var region := String(build.get("region", generator.region_for(build["coord"])))
	return ref_floor_kind(build["data"], region, build["room_map"], build["room_anchor"], x, z)


## The floor kind of cell (x, z): one kind per room (FloorSets.room_kind, keyed on the room's origin) and one per chunk
## for its halls (the carpet runner strips still follow the hall). Picking per cell scattered two floors checkerboard-style.
static func ref_floor_kind(data: Dictionary, region: String, room_map: Dictionary, room_anchor: Dictionary,
		x: int, z: int) -> String:
	var coord: Vector3i = data["coord"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cell := Vector2i(x, z)
	if region == "inferno":
		# the caves are rock; only walkways (the chain bridge, a ramp's landing and its connector) are plated
		for pit in InfernoCaverns.pits_in(data):
			if (pit["bridge"] as Rect2i).has_point(cell):
				return "hazard"
		for ramp in data.get("ramps", []):
			if (ramp["bottom"] as Rect2i).has_point(cell) or (ramp["connector"] as Rect2i).has_point(cell):
				return "hazard"
		return "rock%d" % posmod(RefLook.pick(coord.x * size + x, coord.z * size + z, 7, 3), 3)
	var room_type: String = room_map.get(cell, "")
	if room_type != "":
		var origin: Vector2i = room_anchor.get(cell, cell)
		return FloorSets.room_kind(region, room_type, Vector2i(coord.x * size, coord.z * size) + origin)
	if FloorSets.hall_runner(region):
		var runner := _runner_kind(data["grid"], x, z)
		if runner != "":
			return runner
	# One hall floor per chunk: the set varies chunk to chunk, never tile to tile.
	var kinds := FloorSets.hall(region)
	return kinds[RefLook.pick(coord.x, coord.z, 1, kinds.size())]


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
	var region := String(build.get("region", generator.region_for(coord) if generator != null else "maze"))
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
	for room_id in _room_lamp_coord.keys().duplicate():
		if _room_lamp_coord[room_id] == coord:
			_room_lamps.erase(room_id)
			_room_lamp_coord.erase(room_id)
			_switch_nodes.erase(room_id)
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
				if is_door:
					# no lintel, but the jambs stand a cell apart: the hunters turn side-on (DoorwayFrames)
					tasks.append({"doorway": true, "at": Vector3(gx + .5, 0.0, gate_z), "width": 1.0})
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
	if bool(task.get("doorway", false)):
		var marker := Node3D.new()
		marker.name = "PrisonDoorway"
		marker.position = task.get("at", Vector3.ZERO)
		parent.add_child(marker)
		DoorwayFrames.register(marker, float(task.get("width", 1.0)), DoorwayFrames.NO_HEADER, .34)
		return
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
	if _thinned_out(prop, type):
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
		"streamed_region_prop", bool(prop.get("solid", true)), type,
		"%d:%d:%d:%s:%d:%d" % [coord.x, coord.y, coord.z, type, cell.x, cell.y] if CarnivalBooths.is_booth(type) or type == "carouselCenterpiece" else "",
		float(prop.get("collider_y0", 0.0)))
	if bool(prop.get("crawl_under", false)) and int(prop.get("crawl_side", 1)) == -1:
		_add_pipe_drips(parent, Vector3(cell.x + .5, float(prop.get("collider_y0", 1.0)), cell.y + .5), prop)
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


## Water dripping off a sewer crawl-under pipe: a few small blue streaks falling from its underside to the floor.
func _add_pipe_drips(parent: Node3D, at: Vector3, prop: Dictionary) -> void:
	var drips := GPUParticles3D.new()
	drips.name = "PipeDrips"
	drips.position = at
	drips.amount = 8
	drips.lifetime = 0.5
	drips.visibility_aabb = AABB(Vector3(-2, -1.5, -2), Vector3(4, 2, 4))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var step: Vector2i = prop.get("crawl_step", Vector2i(1, 0))
	process.emission_box_extents = Vector3(0.05, 0.0, 1.4) if step.x != 0 else Vector3(1.4, 0.0, 0.05)
	process.direction = Vector3.DOWN
	process.spread = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.2
	process.gravity = Vector3(0, -9.8, 0)
	drips.process_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.07, 0.02)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.65, 0.8)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	drips.draw_pass_1 = mesh
	parent.add_child(drips)


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


## How far past the door opening's edge a light switch sits (KT: "doors collide with light switches"): clear of the
## frame post and its trim, and of the leaf, which swings on the opening's side of its hinge and stands square to the wall.
const SWITCH_PAST_OPENING := .75


## Where a room's light switch goes beside its door (chunk-local plan position), on the inside wall face: one side of the
## door, else the other, wherever the wall carries on past the frame (solid behind, open room in front). INF: no room.
static func switch_spot(door: Dictionary, grid: Array = []) -> Vector2:
	var cells: Array = door.get("doorway_cells", [door.get("cell", Vector2i.ZERO)])
	var centre := Vector2.ZERO
	for cell_value in cells:
		centre += Vector2(cell_value as Vector2i) + Vector2(.5, .5)
	centre /= float(maxi(1, cells.size()))
	var inward := Vector2(door.get("inward", Vector2i(0, 1)) as Vector2i)
	var across := Vector2(door.get("across", Vector2i(1, 0)) as Vector2i)
	for side in [1.0, -1.0]:
		var at: Vector2 = centre + inward * .54 + across * side * (cells.size() * .5 + SWITCH_PAST_OPENING)
		if grid.is_empty() or (_grid_solid(grid, at - inward * .6) and not _grid_solid(grid, at + inward * .3)):
			return at
	return Vector2(INF, INF)


static func _grid_solid(grid: Array, at: Vector2) -> bool:
	var cell := Vector2i(floori(at.x), floori(at.y))
	if cell.y < 0 or cell.y >= grid.size() or cell.x < 0 or cell.x >= (grid[cell.y] as Array).size():
		return true
	return int(grid[cell.y][cell.x]) != 0


## Groups a built chunk's lamps by room, applies each room's saved/seeded state, and puts a switch inside every lit room
## beside its main doorway, on the wall at SWITCH_HEIGHT, facing into the room.
func _bind_room_lights(root: Node3D, data: Dictionary, coord: Vector3i, lamp_list: Array) -> void:
	var room_ids := RefLook.chunk_room_ids(data)
	var groups := {}
	for lamp_value in lamp_list:
		var lamp: Array = lamp_value
		var local: Vector3 = (lamp[0] as Vector3) - root.position
		var room_id := String(room_ids.get(Vector2i(floori(local.x), floori(local.z)), ""))
		if room_id.is_empty():
			continue
		if not groups.has(room_id):
			groups[room_id] = []
		(groups[room_id] as Array).append([lamp, float(lamp[2])])
	var doors := {}
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if bool(prop.get("room_door", false)) and not doors.has(String(prop.get("room_id", ""))):
			doors[String(prop.get("room_id", ""))] = prop
	for room_id in groups:
		_room_lamps[room_id] = groups[room_id]
		_room_lamp_coord[room_id] = coord
		var on := world_state.room_light_on(room_id)
		_set_room_lamps(room_id, on)
		if not doors.has(room_id):
			continue
		var door: Dictionary = doors[room_id]
		var inward := Vector2(door.get("inward", Vector2i(0, 1)) as Vector2i)
		var at := switch_spot(door, data.get("grid", []))
		if at.x == INF:
			continue
		var switch := RouteInteractable3D.new()
		switch.name = "LightSwitch_%s" % room_id.replace(":", "_")
		switch.kind = RouteInteractable3D.Kind.LIGHT_SWITCH
		switch.prompt_text = "TOGGLE ROOM LIGHT"
		switch.position = Vector3(at.x, SWITCH_HEIGHT, at.y)
		switch.rotation.y = atan2(-inward.x, -inward.y)
		switch.source_cell = Vector2i(coord.x * StreamedRouteGenerator.CHUNK_SIZE + floori(at.x),
			coord.z * StreamedRouteGenerator.CHUNK_SIZE + floori(at.y))
		switch.add_to_group("streamed_light_switch")
		switch.set_meta("room_id", room_id)
		root.add_child(switch)
		switch.configure_room_light(room_id, on,
			room_light_requester.bind(room_id) if room_light_requester.is_valid() else Callable())
		_switch_nodes[room_id] = switch


func _set_room_lamps(room_id: String, on: bool) -> void:
	for entry_value in _room_lamps.get(room_id, []):
		var entry: Array = entry_value
		(entry[0] as Array)[2] = float(entry[1]) if on else 0.0


## Applies a room's light state (from the world state, any peer): lamps, light field and the switch's position.
func apply_room_light(room_id: String, on: bool) -> bool:
	var changed := world_state.set_room_light(room_id, on)
	_set_room_lamps(room_id, on)
	var switch := room_light_switch(room_id)
	if switch != null and switch.light_enabled != on:
		switch.light_enabled = on
		switch.configure_room_light(room_id, on, switch.light_resolver)
	return changed


func room_light_switch(room_id: String) -> RouteInteractable3D:
	# a switch in an unloaded chunk is freed: check before the cast (casting a freed object is an error), and forget it
	var value: Variant = _switch_nodes.get(room_id)
	if value == null:
		return null
	if not is_instance_valid(value):
		_switch_nodes.erase(room_id)
		return null
	return value as RouteInteractable3D


func lit_rooms() -> Array:
	return _room_lamps.keys()


func room_lamp_energy(room_id: String) -> float:
	var total := 0.0
	for entry_value in _room_lamps.get(room_id, []):
		total += float(((entry_value as Array)[0] as Array)[2])
	return total


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


## A playable carnival booth: the animated booth node beside the prop, and the interact prompt and request wired to it.
func _attach_booth(parent: Node3D, furniture: RouteInteractable3D, booth_id: String, prop_type: String, at: Vector3, yaw: float, blocker_size: Vector3) -> void:
	var booth := CarnivalBooth3D.new()
	booth.setup(booth_id, prop_type, blocker_size)
	booth.position = at
	booth.rotation.y = yaw
	booth.reporter = booth_reporter
	booth.rest_resolver = func() -> float:
		return world_state.booth_cooldown_left(booth_id, Time.get_unix_time_from_system()) if world_state != null else 0.0
	parent.add_child(booth)
	furniture.prompt_resolver = booth.prompt_text
	if booth_requester.is_valid():
		furniture.activation_override = booth_requester.bind(booth_id, prop_type)
	_booth_nodes[booth_id] = booth
	booth.tree_exited.connect(func() -> void:
		if _booth_nodes.get(booth_id) == booth:
			_booth_nodes.erase(booth_id))


## The working merry-go-round: the ride node at the prop, its state from the world state, and a lever interactable on its panel.
func _attach_carousel(parent: Node3D, ride_id: String, at: Vector3) -> CarouselRide3D:
	var ride := CarouselRide3D.new()
	ride.state_resolver = func() -> Dictionary:
		if world_state == null:
			return {"on": false, "angle": 0.0}
		var now := Time.get_unix_time_from_system()
		return {"on": world_state.carousel_on(ride_id), "angle": world_state.carousel_angle(ride_id, now)}
	ride.setup(ride_id)
	ride.position = at
	parent.add_child(ride)
	if tracked_player != null and not tracked_player.is_in_group("carousel_riders"):
		tracked_player.add_to_group("carousel_riders")
	var lever := RouteInteractable3D.new()
	lever.name = "CarouselLever"
	lever.kind = RouteInteractable3D.Kind.FURNITURE
	lever.configure_furniture("play")
	lever.position = at + ride.lever_point.position + Vector3(0, 0.5, 0)
	lever.prompt_resolver = ride.prompt_text
	if carousel_requester.is_valid():
		lever.activation_override = carousel_requester.bind(ride_id)
	parent.add_child(lever)
	_carousel_nodes[ride_id] = ride
	ride.tree_exited.connect(func() -> void:
		if _carousel_nodes.get(ride_id) == ride:
			_carousel_nodes.erase(ride_id))
	return ride


func carousel_node(ride_id: String) -> CarouselRide3D:
	var node := _carousel_nodes.get(ride_id) as CarouselRide3D
	return node if node != null and is_instance_valid(node) else null


func booth_node(booth_id: String) -> CarnivalBooth3D:
	var node := _booth_nodes.get(booth_id) as CarnivalBooth3D
	return node if node != null and is_instance_valid(node) else null


## Height of a bed's sleeping surface above the floor: the highest upward face over the middle of the model (the head and
## foot boards and rails stand at the ends and sides, outside that patch). Cached per model path.
static var _mattress_tops := {}


static func mattress_top(visual: Node3D, path: String) -> float:
	if _mattress_tops.has(path):
		return float(_mattress_tops[path])
	var height := _upward_top(visual, Vector2(.2, .15), 0.0, 1.0)
	_mattress_tops[path] = height
	return height


## Height of a seat pan above the floor: the level with the most upward-facing area over the middle of the seat, a little
## in front of centre (the model's back is -Z), above the bottom fifth (bases, feet, star legs). Armrest caps and
## backrest tops are narrow; the pan is the widest flat. Cached per model path.
static var _seat_tops := {}


static func seat_top(visual: Node3D, path: String, type: String = "") -> float:
	if _seat_tops.has(path):
		return float(_seat_tops[path])
	# a booth's middle is its table: measure over its first bench row (model frame: the gameplay z is mirrored)
	var rows: Array = PropModelCatalog.SEAT_ROWS.get(type, [])
	var height := _largest_flat(visual, Vector2(.18, .12), -float((rows[0] as Dictionary)["z"])) if not rows.is_empty() \
		else _largest_flat(visual, Vector2(.18, .3), .08)
	_seat_tops[path] = height
	return height


static func _largest_flat(visual: Node3D, reach_frac: Vector2, z_shift: float) -> float:
	var inverse := visual.global_transform.affine_inverse()
	var bounds := ModelSlot.combined_local_bounds(visual)
	var centre := bounds.get_center() + Vector3(0.0, 0.0, bounds.size.z * z_shift)
	var reach := Vector2(bounds.size.x * reach_frac.x, bounds.size.z * reach_frac.y)
	var floor_cut := bounds.position.y + bounds.size.y * .2
	var areas := {}
	for mesh_value in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mesh_value as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xf := inverse * mesh_node.global_transform
		var faces := mesh_node.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := xf * faces[i]
			var b := xf * faces[i + 1]
			var c := xf * faces[i + 2]
			var normal := (b - a).cross(c - a)
			if normal.y <= normal.length() * .9:
				continue
			var mid := (a + b + c) / 3.0
			if mid.y < floor_cut or absf(mid.x - centre.x) > reach.x or absf(mid.z - centre.z) > reach.y:
				continue
			var level := int(roundf(mid.y / .03))
			areas[level] = float(areas.get(level, 0.0)) + normal.length() * .5
	var best := -1
	for level in areas:
		if best < 0 or float(areas[level]) > float(areas[best]):
			best = int(level)
	if best < 0:
		return 0.0
	return (float(best) * .03 - bounds.position.y) * visual.scale.y


## The highest upward-facing triangle within a patch around the model's centre (`reach` x and z as fractions of the
## bounds, the patch shifted `z_shift` of the depth toward the front), below `cap` of the model's height.
static func _upward_top(visual: Node3D, reach_frac: Vector2, z_shift: float, cap: float) -> float:
	var inverse := visual.global_transform.affine_inverse()
	var bounds := ModelSlot.combined_local_bounds(visual)
	var centre := bounds.get_center() + Vector3(0.0, 0.0, bounds.size.z * z_shift)
	var reach := Vector2(bounds.size.x * reach_frac.x, bounds.size.z * reach_frac.y)
	var ceiling := bounds.position.y + bounds.size.y * cap
	var top := bounds.position.y
	for mesh_value in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mesh_value as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xf := inverse * mesh_node.global_transform
		var faces := mesh_node.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := xf * faces[i]
			var b := xf * faces[i + 1]
			var c := xf * faces[i + 2]
			var normal := (b - a).cross(c - a)
			if absf(normal.y) < normal.length() * .9:
				continue
			var mid := (a + b + c) / 3.0
			if absf(mid.x - centre.x) <= reach.x and absf(mid.z - centre.z) <= reach.y and mid.y <= ceiling + .001:
				top = maxf(top, mid.y)
	return (top - bounds.position.y) * visual.scale.y


func _spawn_authored_prop(parent: Node3D, path: String, at: Vector3,
		yaw: float, blocker_size: Vector3,
		group_name: String = "streamed_prison_prop", solid: bool = true,
		prop_type: String = "", booth_id: String = "", collider_y0: float = 0.0) -> void:
	var visual := ModelSlot.instantiate_prop(path, prop_type)
	if visual == null:
		return
	var visual_at := at
	var visual_bounds := ModelSlot.combined_local_bounds(visual)
	if not PropModelCatalog.is_wall_mounted(prop_type) \
			and not PropModelCatalog.is_ceiling_mounted(prop_type) \
			and not PropModelCatalog.keeps_authored_pivot(prop_type) \
			and visual_bounds.size.length_squared() > 0.0:
		# Preview-friendly centre pivots buried half of couches, chairs and beds
		# below the GridMap. Seat every ordinary prop on its lowest mesh point.
		visual_at.y -= visual_bounds.position.y
	RefLook.grade_prop(visual, .6 if PropModelCatalog.is_floor_dressing(prop_type) else 1.0)
	visual.position = visual_at
	visual.rotation.y = PropModelCatalog.authored_visual_yaw(yaw)
	visual.set_meta("streamed_prop_type", prop_type)
	visual.set_meta("streamed_prop_bounds", visual_bounds)
	# maze culling: the world cell this prop stands in (its visual hides when no open path of sight reaches the cell)
	var world_at := (parent.position if parent != null else Vector3.ZERO) + at
	visual.set_meta("cull_cell", Vector2i(floori(world_at.x), floori(world_at.z)))
	visual.add_to_group("cull_prop")
	visual.add_to_group(group_name)
	_limit_prop_visibility(visual, visual_bounds, prop_type)
	parent.add_child(visual)
	if PropModelCatalog.is_empty_frame(prop_type):
		_add_blank_frame_canvas(visual, prop_type)
	var carousel_ride: CarouselRide3D = null
	if prop_type == "carouselCenterpiece":
		if booth_id.is_empty():
			_animated_activity_props.append(visual)
		else:
			visual.visible = false   # the single turning model is replaced by the working ride (CarouselRide3D)
			carousel_ride = _attach_carousel(parent, booth_id, at)
	if PropModelCatalog.is_floor_dressing(prop_type):
		ModelSlot.keep_floor_dressing_visible(visual)
	var furniture_action := PropModelCatalog.interaction_for(prop_type)
	if carousel_ride != null:
		furniture_action = ""   # the lever starts it; nobody sits on a turning ride's centre
	if furniture_action == "mirror":
		_spawn_mirror_surface(parent, at, yaw)
	if not furniture_action.is_empty():
		# a multi-seat (waiting-room row, bench, couch, booth) gets one interactable per seat (docs/SEATING.md)
		var seat_points: Array = PropModelCatalog.seat_points(prop_type, blocker_size) if furniture_action == "sit" \
			else [{"x": 0.0, "z": 0.0, "turn": 0.0, "width": blocker_size.x}]
		var seat_height := seat_top(visual, path, prop_type) if furniture_action == "sit" else 0.0
		for seat_index in seat_points.size():
			var point: Dictionary = seat_points[seat_index]
			var furniture := RouteInteractable3D.new()
			furniture.name = "Furniture_%s" % prop_type if seat_points.size() == 1 else "Furniture_%s_%d" % [prop_type, seat_index]
			furniture.kind = RouteInteractable3D.Kind.FURNITURE
			furniture.configure_furniture(furniture_action)
			furniture.set_meta("prop_type", prop_type)
			# PlayerController3D.rest_spot: where the body and eye go (a booth seat is one bench's half, not the table)
			furniture.set_meta("rest_size", Vector3(float(point["width"]), blocker_size.y,
				blocker_size.z * (.28 if PropModelCatalog.SEAT_ROWS.has(prop_type) else 1.0)) if seat_points.size() > 1 else blocker_size)
			if furniture_action == "lay":
				furniture.set_meta("rest_top", mattress_top(visual, path))
			elif furniture_action == "sit":
				furniture.set_meta("seat_top", seat_height)
				furniture.set_meta("seat_index", seat_index)
			furniture.position = at + Vector3.UP * (.48 if furniture_action == "lay" else .03) \
				+ Vector3(float(point["x"]), 0.0, float(point["z"])).rotated(Vector3.UP, yaw)
			furniture.rotation.y = yaw + float(point["turn"])
			parent.add_child(furniture)
			if furniture_action == "play" and not booth_id.is_empty():
				_attach_booth(parent, furniture, booth_id, prop_type, at, yaw, blocker_size)
	if not solid:
		return
	var body := StaticBody3D.new()
	for box in PropColliderBoxes.boxes(prop_type, blocker_size, PropColliderBoxes.variant_paths(prop_type).find(path)):
		var local: Vector2 = box["c"]
		var half: Vector2 = box["h"]
		var collision := CollisionShape3D.new()
		collision.shape = _shared_box_shape(Vector3(half.x * 2.0, blocker_size.y, half.y * 2.0))
		collision.position = at + Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, yaw) + Vector3.UP * (blocker_size.y * .5)
		if collider_y0 > 0.0:
			# a raised collider (a crawl-under pipe): its underside is collider_y0 above the floor, whatever the visual's origin
			collision.position.y = collider_y0 + blocker_size.y * .5
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
	range_end *= PlatformProfile.prop_range_scale   # quality tier: lower tiers stop drawing small props sooner
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


## Music boxes (at most one per chunk): hold [E] to wind, resolved by the route scene's player.music_box_resolver.
func _spawn_music_boxes(parent: Node3D, data: Dictionary) -> void:
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	for box_value in data.get("music_boxes", []):
		var box: Dictionary = box_value
		var cell: Vector2i = box.get("cell", Vector2i.ZERO)
		var node := RouteInteractable3D.new()
		node.kind = RouteInteractable3D.Kind.MUSIC_BOX
		node.music_box_id = String(box.get("id", ""))
		node.music_boxes = music_boxes
		node.name = "MusicBox_%s" % node.music_box_id.replace(":", "_")
		node.prompt_text = "HOLD INTERACT // WIND MUSIC BOX"
		node.source_cell = Vector2i(coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x,
			coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y)
		node.position = Vector3(cell.x + .5, .04, cell.y + .5)
		node.add_to_group("streamed_music_box")
		parent.add_child(node)


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
