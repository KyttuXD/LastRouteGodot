class_name FacilityMap
extends Control

signal waypoint_requested(world_position: Vector2, level: int)
## Admin-only: middle-click on the full map asks the route to safe-teleport here.
## The route sets `admin_teleport` only when this player has the player admin scope.
signal admin_teleport_requested(world_position: Vector2, level: int)

## The full-screen facility map — the original's "radar".
##
## It replaces a placeholder that was a coloured rectangle with the words
## FACILITY MAP on it. That was harmless while nothing depended on it, and stops
## being harmless with Porcelle on the floor: she is invisible in the room and
## visible ONLY here, so this panel is the whole of her counterplay. The cost
## the original charges for using it is exactly what makes her fair — reading
## the map means giving up your view of the room you are standing in.
##
## Everything drawn is passed in rather than looked up, so this stays a widget:
## it never reaches into the world for a hunter or a player.

const WALL := 0
const RELAY_TEAL_BLUE := Color("32c9d8")
const STAIR_ICON_WHITE := Color("f4f7f6")
const SEWER_WATER_TINT := Color("2f5a52")
const LADDER_ICON_TINT := Color("e8c25a")
## Solid props on the map: their real collision boxes (see _draw_collider_box).
const PROP_BOX_TINT := Color("7899a1")
const COOP_PLAYER_BLUE := Color("63d9f1")
const PORCELLE_GHOST := Color("c9b6e4")
const MIN_MAP_ZOOM := 0.75
const MAX_MAP_ZOOM := 8.0
const REGION_COLORS := {
	"maze": Color("bc786f"),
	"mansion": Color("c28b68"),
	"hotel": Color("d1aa68"),
	"apartment": Color("6f9fc0"),
	"beach": Color("4fb8c8"),
	"gothic": Color("8a68ad"),
	"prison": Color("778994"),
	"inferno": Color("d45b3f"),
	"sewer": Color("5e7a5c"),
	"carnival": Color("ce5d96"),
	"hospital": Color("9fd0c2"),
	"lab": Color("5fd4e4"),
	"greenhouse": Color("7fbf5a"),
	"mall": Color("e8b05a"),
}

@export var interactive := false
## When true, middle-click emits admin_teleport_requested instead of doing nothing.
var admin_teleport := false

var generator: FacilityGenerator
var player_at := Vector2.ZERO
var player_facing := Vector2(0, 1)
## [{ "at": Vector2, "name": String, "active": bool }]
var hunters: Array = []
## Porcelle's marks pulse (RadarPing) instead of sitting on the map: the HUD minimap turns this on. `radar_time` < 0 uses
## the real clock (tests pin it).
var ghost_ping := false
## Quick-chat pings: {at (map units like player marks), colour, label, until (msec)}; drawn for PING_SECONDS.
var pings: Array = []
const PING_SECONDS := 6.0
## Full-map player arrow: a constant on-screen size (HUD units, tip reach) at every zoom, so zooming in shows more map
## around it instead of growing the arrow over several rooms. Kept within [MIN, MAX].
const PLAYER_ARROW_MIN := 7.0
const PLAYER_ARROW_SIZE := 8.0
const PLAYER_ARROW_MAX := 9.0
## Minimap redraw cap while a mark is only sliding inside a cell. 12 Hz is the
## middle of the 10–15 Hz band: one minimap cell is about two pixels, so extra
## frames do not move the picture. A cell crossing or a new marker still
## redraws on that frame (see _publish_map_redraw).
const MINIMAP_REDRAW_HZ := 12.0
const MINIMAP_REDRAW_INTERVAL := 1.0 / MINIMAP_REDRAW_HZ
## Perf probe (dev and benches only, default off). When on, each map tallies its redraws, the draw calls _draw_streamed
## issues (per kind) and the CPU time of _draw. Play never turns it on; off costs one static bool read per chunk.
static var perf_probe := false
var perf_redraws := 0
var perf_draws := 0
var perf_draw_usec := 0
var perf_by_kind := {}
var perf_mesh_builds := 0
## Full map static layer: one cached ArrayMesh per discovered chunk (backdrop, walls, water and solid-prop boxes in one draw
## call), rebuilt only when that chunk's key changes (see _chunk_static_key). The minimap keeps its per-cell draws.
var _chunk_meshes := {}     # Vector3i -> {"key": int, "mesh": ArrayMesh or null}
var _chunk_keys := {}       # Vector3i -> int, for the chunks of the current feed (full map only)
var _visible_coords: Array[Vector3i] = []
var _bounds_min := Vector2i.ZERO   # lowest chunk x,z of the current feed
var _bounds_max := Vector2i.ZERO   # highest chunk x,z of the current feed (inclusive)
## Open full map: the signature of what was last queued, so an idle open map does not redraw every feed tick.
var _has_full_sig := false
var _last_full_sig := 0
var _mesh_verts := PackedVector2Array()
var _mesh_colours := PackedColorArray()
var _mesh_indices := PackedInt32Array()
## Full map dots (decor and pickup circles, 1 px minimum radius): one mesh per chunk, built for the cell size it is drawn at
## (the minimum radius is then exact), rebuilt when the chunk's dots change or the cell size does (zoom, discovery).
var perf_dot_builds := 0
var _dot_meshes := {}      # Vector3i -> {"key": int, "cell": float, "mesh": ArrayMesh or null}
var _dot_keys := {}        # Vector3i -> int, for the chunks of the current feed (full map only)
const CIRCLE_SEGMENTS := 12


## How far the player arrow reaches from its centre at `cell` HUD units per cell: the minimap scales with its cells, the
## full map keeps a fixed on-screen size.
static func arrow_reach(cell: float, full_map: bool) -> float:
	return clampf(PLAYER_ARROW_SIZE, PLAYER_ARROW_MIN, PLAYER_ARROW_MAX) if full_map else cell * 0.95
var radar_time := -1.0:
	set(value):
		radar_time = value
		_mark_dirty(true)
## Other runners are deliberately separate from hunter intelligence: co-op
## teammates remain visible on both maps while hunter markers still require
## the admin reveal permission.
var players: Array = []
## Admin pulses (host-approved, a few seconds): [{at: Vector2, level: int, until_msec: int, name: String}] drawn as expanding rings.
var pulses: Array = []
var dropped_tools: Array = []
var safe_rooms: Array = []
## Infinite mode supplies compact discovered chunks rather than a finite
## FacilityGenerator. Unknown chunks are intentionally absent and therefore
## remain blank on both map surfaces.
var streamed_chunks: Dictionary = {}
var streamed_level := 0
var streamed_chunk_size := 0
var streamed_show_stairs := false
## Authenticated visual admins receive region-tinted floor cells and boundaries.
## The flag is supplied by the scene controller so ordinary players cannot
## enable this information by editing a UI node.
var streamed_show_regions := false
## Local player-authored marks for the current streamed floor.
var waypoints: Array = []
## Walkable, discovery-limited route from the runner through the active floor's
## waypoints. InfiniteRoute owns navigation; this widget only draws the result.
var waypoint_path: Array = []
## Zero fits every supplied chunk (fullscreen map). A positive value creates a
## player-centred square with this many cells of reach (minimap).
var streamed_focus_radius_cells := 0
var map_zoom := 1.0:
	set(value):
		map_zoom = value
		if interactive:
			remembered_zoom = value
## The full map's zoom survives closing and reopening it (and a new HUD).
static var remembered_zoom := 1.0
## Full map: while true the view stays centred on the runner (smoothly); a manual pan turns it off, recenter() turns it on.
var follow_player := true
## Seconds-to-catch-up feel of the follow (exponential smoothing rate; higher = tighter).
const FOLLOW_RATE := 10.0
var _view_center := Vector2.ZERO
var _view_center_valid := false
var _touches := {}
var _pinch_distance := 0.0
var _dragging := false
var _last_cell_scale := 1.0
var _last_world_origin := Vector2.ZERO
var _last_world_center := Vector2.ZERO
var _base_cell_scale := 1.0
var _last_screen_origin := Vector2.ZERO
## Minimap throttle. The full map (interactive) is not capped while it is open.
var _minimap_due := false
var _minimap_wait := 0.0
var _anim_was_full := false
var _anim_was_capped := false
var _have_redraw_stamp := false
var _last_structural := ""
var _last_soft := 0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	if interactive:
		map_zoom = remembered_zoom


## Centre on the runner and follow again (the RECENTER control). `snap` jumps there instead of gliding (opening the map).
func recenter(snap: bool = false) -> void:
	follow_player = true
	if snap or not _view_center_valid:
		_view_center = player_at
		_view_center_valid = true
	queue_redraw()


## The world point at the centre of the full map.
func view_center() -> Vector2:
	return _view_center


## Redraw the minimap immediately, or on the next capped tick. The full map
## redraws on the spot while it is open so panning and the follow stay smooth.
func _mark_dirty(immediate: bool) -> void:
	if interactive:
		if is_visible_in_tree():
			queue_redraw()
		return
	_arm_minimap(immediate)


func _arm_minimap(immediate: bool) -> void:
	if immediate:
		if is_visible_in_tree():
			_minimap_due = false
			_minimap_wait = MINIMAP_REDRAW_INTERVAL
			queue_redraw()
		else:
			_minimap_due = true
			_minimap_wait = 0.0
		return
	_minimap_due = true


## Minimap: redraw now when the picture's structure changed (a cell was crossed,
## a marker or chunk appeared, a pickup was taken). Sliding inside a cell only
## arms the 12 Hz cap. The open full map is not capped.
func _publish_map_redraw() -> void:
	if interactive:
		# The open map redraws only when something it draws changed: an idle feed with the same picture costs nothing.
		if is_visible_in_tree():
			var signature := _full_map_signature()
			if not _has_full_sig or signature != _last_full_sig:
				_has_full_sig = true
				_last_full_sig = signature
				queue_redraw()
		return
	var structural := _structural_key()
	var soft := _soft_key()
	var structural_changed := not _have_redraw_stamp or structural != _last_structural
	var soft_changed := soft != _last_soft
	_have_redraw_stamp = true
	_last_structural = structural
	_last_soft = soft
	if structural_changed:
		_arm_minimap(true)
	elif soft_changed:
		_arm_minimap(false)


func _tick_minimap_redraw(delta: float, visible: bool) -> void:
	if not visible:
		if _minimap_due:
			_minimap_wait = 0.0
		return
	_minimap_wait = maxf(0.0, _minimap_wait - delta)
	if _anim_full_rate():
		_anim_was_full = true
		queue_redraw()
		return
	if _anim_was_full:
		_anim_was_full = false
		queue_redraw()
		return
	var capped := _anim_capped()
	if capped and _minimap_wait <= 0.0:
		_anim_was_capped = true
		_minimap_due = false
		_minimap_wait = MINIMAP_REDRAW_INTERVAL
		queue_redraw()
		return
	if _anim_was_capped and not capped:
		_anim_was_capped = false
		queue_redraw()
		return
	if _minimap_due and _minimap_wait <= 0.0:
		_minimap_due = false
		_minimap_wait = MINIMAP_REDRAW_INTERVAL
		queue_redraw()


## Frame-rate motion that would look stepped at 12 Hz: a live radar blip, a
## quick-chat ping, an admin pulse, a save-point flash, or a revive heartbeat.
func _anim_full_rate() -> bool:
	if _pings_live() or _pulses_live() or _save_flash_live() or _downed_live():
		return true
	if not ghost_ping or Settings.reduced_motion:
		return false
	return _ghost_mark_present() and float(RadarPing.sample(_ping_clock())["strength"]) > 0.001


## Slow motion that still has to move, sampled on the minimap cap: reduced-motion
## Porcelle (a 6 s fade) stays visually the same at 12 Hz.
func _anim_capped() -> bool:
	return ghost_ping and Settings.reduced_motion and _ghost_mark_present()


func _ghost_mark_present() -> bool:
	for mark in hunters:
		if bool(mark.get("ghost", false)) and bool(mark.get("active", true)):
			return true
	return false


func _downed_live() -> bool:
	for mark in players:
		if mark.has("down_left") and float(mark.get("down_left", 0.0)) > 0.0:
			return true
	return false


func _pings_live() -> bool:
	var now := Time.get_ticks_msec()
	for ping in pings:
		if int(ping.get("until", 0)) > now:
			return true
	return false


func _pulses_live() -> bool:
	var now := Time.get_ticks_msec()
	for mark in pulses:
		if int(mark.get("until_msec", 0)) > now:
			return true
	return false


func _player_cell() -> Vector2i:
	return Vector2i(floori(player_at.x), floori(player_at.y))


## Everything the open full map draws, at full precision where the picture can show it: the view, the zoom and size, the
## runner, and the structural and soft keys of the feed. Equal signatures mean an identical picture.
func _full_map_signature() -> int:
	return hash([_view_center, map_zoom, size, player_at, player_facing,
		streamed_show_regions, _structural_key(), _soft_key()])


func _structural_key() -> String:
	return "%d,%d|%d|%d|%d|%d|%d|%d|%s|%s|%s|%s|%s" % [
		_player_cell().x, _player_cell().y,
		streamed_level, streamed_chunk_size, streamed_focus_radius_cells,
		int(streamed_show_stairs), int(streamed_show_regions),
		_geometry_hash(), _generator_stamp(),
		_identity_stamp(hunters), _identity_stamp(players),
		_identity_stamp(dropped_tools), _identity_stamp(safe_rooms),
	]


func _geometry_hash() -> int:
	var h := streamed_chunks.size()
	for coord in streamed_chunks:
		h ^= hash(coord)
		var chunk: Dictionary = streamed_chunks[coord]
		h ^= hash(String(chunk.get("region", "")))
		var pickups: Array = chunk.get("pickups", [])
		h ^= pickups.size() * 131
		for pickup in pickups:
			if pickup is Dictionary:
				h ^= hash(String((pickup as Dictionary).get("id", "")))
		h ^= (chunk.get("props", []) as Array).size() * 17
		h ^= (chunk.get("stairs", []) as Array).size() * 64
		h ^= (chunk.get("ladders", []) as Array).size() * 8
		if chunk.has("walls"):
			h ^= hash(chunk["walls"])
		if chunk.has("water"):
			h ^= hash(chunk["water"])
	return h


func _generator_stamp() -> String:
	if generator == null:
		return ""
	var collected := 0
	for entry in generator.relays:
		if entry.get("collected", false):
			collected += 1
	for entry in generator.batteries:
		if entry.get("collected", false):
			collected += 1
	var grid_hash := 0
	for y in mini(generator.rows, generator.grid.size()):
		var row: Array = generator.grid[y]
		for x in mini(generator.cols, row.size()):
			grid_hash = (grid_hash * 33) ^ int(row[x])
	return "%d,%d,%s,%d,%d" % [generator.cols, generator.rows, str(generator.exit_cell), collected, grid_hash]


func _identity_stamp(marks: Array) -> String:
	var parts := PackedStringArray()
	for mark_value in marks:
		var mark: Dictionary = mark_value
		var at: Vector2 = mark.get("at", Vector2.ZERO)
		parts.append("%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s,%d" % [
			floori(at.x), floori(at.y),
			int(mark.get("level", streamed_level)),
			int(bool(mark.get("ghost", false))),
			int(bool(mark.get("active", true))),
			int(bool(mark.get("spectating", false))),
			int(bool(mark.get("other_floor", false))),
			int(bool(mark.get("breached", false))),
			int(bool(mark.get("stale", false))),
			String(mark.get("name", "")),
			String(mark.get("hunter_id", "")),
			String(mark.get("exit_direction", "")),
			int(mark.get("peer_id", int(mark.get("peer", -1)))),
		])
	parts.sort()
	return "|".join(parts)


## Sub-cell motion. Quantized so idle jitter does not redraw, and so a teammate
## walking inside a cell still arms the cap instead of waiting for the next cell.
func _soft_key() -> int:
	var h := hash(Vector2i(roundi(player_at.x * 16.0), roundi(player_at.y * 16.0)))
	h ^= hash(Vector2i(roundi(player_facing.x * 32.0), roundi(player_facing.y * 32.0)))
	for group in [hunters, players, dropped_tools]:
		for mark in group:
			var at: Vector2 = mark.get("at", Vector2.ZERO)
			h ^= hash(Vector2i(roundi(at.x * 16.0), roundi(at.y * 16.0)))
			var facing: Vector2 = mark.get("facing", Vector2.ZERO)
			if facing != Vector2.ZERO:
				h ^= hash(Vector2i(roundi(facing.x * 32.0), roundi(facing.y * 32.0)))
			if mark.has("down_left"):
				h ^= ceili(float(mark.get("down_left", 0.0))) * 17
	return h


func _process(delta: float) -> void:
	var visible := is_visible_in_tree()
	if not interactive:
		_tick_minimap_redraw(delta, visible)
		return
	if not visible:
		_has_full_sig = false
	elif not _has_full_sig:
		queue_redraw()   # opened, and no feed has queued the picture yet
	if visible and follow_player and streamed_chunk_size > 0:
		if not _view_center_valid:
			recenter(true)
		var step := 1.0 - exp(-FOLLOW_RATE * delta)
		var before := _view_center
		_view_center = _view_center.lerp(player_at, step)
		if _view_center.distance_squared_to(player_at) < 0.0001:
			_view_center = player_at
		if before != _view_center:
			queue_redraw()
	# Pings, pulses, save flashes and a live radar blip stay at frame rate on
	# the open map. The minimap's copy of that motion is handled above.
	if visible and _anim_full_rate():
		queue_redraw()
	if not visible or not has_focus() or streamed_chunk_size <= 0:
		return
	if Input.is_action_just_pressed("jump"):
		recenter()
	# Full-map controller controls: left stick pans, shoulders zoom, and X drops
	# a waypoint at the centre crosshair. Gameplay is already frozen while this
	# surface is open, so these actions never leak into tools or movement.
	var pan := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if pan.length_squared() <= .01:
		pan = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if pan.length_squared() > .01:
		pan_screen(-pan * 120.0 * delta)
	if Input.is_action_just_pressed("flashlight"):
		zoom_at(1.22)
	if Input.is_action_just_pressed("taser"):
		zoom_at(1.0 / 1.22)
	if Input.is_action_just_pressed("interact"):
		waypoint_requested.emit(_screen_to_streamed_world(size * .5), streamed_level)


func _gui_input(event: InputEvent) -> void:
	if not interactive or streamed_chunk_size <= 0:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			zoom_at(1.22, button.position)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			zoom_at(1.0 / 1.22, button.position)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed and button.double_click:
				waypoint_requested.emit(_screen_to_streamed_world(button.position),
					streamed_level)
				_dragging = false
				accept_event()
				return
			_dragging = button.pressed
			accept_event()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			waypoint_requested.emit(_screen_to_streamed_world(button.position),
				streamed_level)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_MIDDLE and button.pressed and admin_teleport:
			admin_teleport_requested.emit(_screen_to_streamed_world(button.position),
				streamed_level)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		pan_screen((event as InputEventMouseMotion).relative)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at((event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)
		accept_event()
	elif event is InputEventPanGesture:
		pan_screen(-(event as InputEventPanGesture).delta * 8.0)
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_pinch_distance = _touch_spread()
		accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			var spread := _touch_spread()
			if _pinch_distance > 1.0 and spread > 1.0:
				zoom_at(spread / _pinch_distance, _touch_centre())
			_pinch_distance = spread
		elif not _dragging:
			pan_screen(drag.relative)
		accept_event()


func _touch_spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _touch_centre() -> Vector2:
	var points: Array = _touches.values()
	return ((points[0] as Vector2) + (points[1] as Vector2)) * .5


func zoom_at(factor: float, screen_position: Vector2 = Vector2(-1, -1)) -> void:
	if not interactive or factor <= 0.0:
		return
	var focus := screen_position
	if focus.x < 0.0 or focus.y < 0.0 or follow_player:
		focus = size * .5   # following: zoom about the runner so they stay centred
	var old_cell := maxf(.0001, _last_cell_scale)
	var old_world_at_focus := _last_world_origin + focus / old_cell
	var next_zoom := clampf(map_zoom * factor, MIN_MAP_ZOOM, MAX_MAP_ZOOM)
	if is_equal_approx(next_zoom, map_zoom):
		return
	map_zoom = next_zoom
	var new_cell := maxf(.0001, _base_cell_scale * map_zoom)
	# Keep the same world coordinate under the pointer, as conventional web maps
	# do, instead of pulling the map toward its centre on every wheel step.
	var wanted_origin := old_world_at_focus - focus / new_cell
	if not follow_player:
		_view_center = wanted_origin + size / (2.0 * new_cell)
	queue_redraw()


func pan_screen(screen_delta: Vector2) -> void:
	if not interactive:
		return
	if screen_delta.length_squared() < 0.0001:
		return
	# Dragging right moves the paper right, so the viewed world origin moves left. Panning by hand stops following.
	follow_player = false
	if not _view_center_valid:
		_view_center = player_at
		_view_center_valid = true
	_view_center -= screen_delta / maxf(.0001, _last_cell_scale)
	queue_redraw()


## True once there is a map to draw (a generated facility or discovered streamed chunks). The HUD hides the
## minimap panel while this is false rather than showing an empty dark box.
func has_data() -> bool:
	return generator != null or not streamed_chunks.is_empty()


func reset_view() -> void:
	map_zoom = 1.0
	_dragging = false
	recenter(true)


func set_waypoints(marks: Array) -> void:
	if waypoints == marks:
		return
	waypoints = marks.duplicate(true)
	_mark_dirty(true)


func set_waypoint_path(points: Array) -> void:
	if waypoint_path == points:
		return
	waypoint_path = points.duplicate()
	_mark_dirty(true)


func _screen_to_streamed_world(screen_position: Vector2) -> Vector2:
	return _last_world_origin \
		+ (screen_position - _last_screen_origin) / maxf(.0001, _last_cell_scale)


func show_state(from: FacilityGenerator, at: Vector2, facing: Vector2, marks: Array,
		player_marks: Array = [], drop_marks: Array = [],
		safe_room_marks: Array = []) -> void:
	generator = from
	streamed_chunks.clear()
	streamed_chunk_size = 0
	streamed_show_stairs = false
	streamed_show_regions = false
	streamed_focus_radius_cells = 0
	waypoint_path.clear()
	player_at = at
	player_facing = facing
	hunters = marks
	players = player_marks.duplicate(true)
	dropped_tools = drop_marks.duplicate(true)
	safe_rooms = safe_room_marks.duplicate(true)
	_index_streamed_chunks()
	_publish_map_redraw()


func show_streamed_state(chunks: Dictionary, level: int, chunk_size: int,
		at: Vector2, facing: Vector2, marks: Array,
		show_stairs: bool = false, focus_radius_cells: int = 0,
		player_marks: Array = [], show_regions: bool = false,
		drop_marks: Array = [], safe_room_marks: Array = []) -> void:
	generator = null
	# Keep the widget's own data floor-pure. Drawing also checks the level as a
	# defensive guard, but retaining other floors here allowed later bounds and
	# marker changes to leak vertically even when the first draw looked right.
	streamed_chunks = {}
	for value in chunks.keys():
		if value is Vector3i:
			var coord: Vector3i = value
			if coord.y == level:
				streamed_chunks[coord] = chunks[value]
	streamed_level = level
	streamed_chunk_size = chunk_size
	streamed_show_stairs = show_stairs
	streamed_show_regions = show_regions
	streamed_focus_radius_cells = maxi(0, focus_radius_cells)
	player_at = at
	player_facing = facing
	hunters = []
	for mark_value in marks:
		var mark: Dictionary = mark_value
		if not mark.has("level") or int(mark["level"]) == level:
			hunters.append(mark)
	players = []
	for mark_value in player_marks:
		var mark: Dictionary = mark_value
		if not mark.has("level") or int(mark["level"]) == level or bool(mark.get("other_floor", false)):
			players.append(mark)
	dropped_tools = []
	for mark_value in drop_marks:
		var mark: Dictionary = mark_value
		if not mark.has("level") or int(mark["level"]) == level:
			dropped_tools.append(mark)
	safe_rooms = []
	for mark_value in safe_room_marks:
		var mark: Dictionary = mark_value
		if not mark.has("level") or int(mark["level"]) == level or bool(mark.get("other_floor", false)):
			safe_rooms.append(mark)
	_index_streamed_chunks()
	_publish_map_redraw()


## Per feed: the visible coords and their bounds (the draw used to walk every chunk for them each frame), and on the full
## map the static key of each chunk. Cached meshes of chunks that left the feed are dropped.
func _index_streamed_chunks() -> void:
	_visible_coords.clear()
	_chunk_keys.clear()
	_dot_keys.clear()
	var first := true
	for value in streamed_chunks.keys():
		var coord: Vector3i = value
		_visible_coords.append(coord)
		if first:
			_bounds_min = Vector2i(coord.x, coord.z)
			_bounds_max = _bounds_min
			first = false
		else:
			_bounds_min = Vector2i(mini(_bounds_min.x, coord.x), mini(_bounds_min.y, coord.z))
			_bounds_max = Vector2i(maxi(_bounds_max.x, coord.x), maxi(_bounds_max.y, coord.z))
		if streamed_focus_radius_cells <= 0:
			_chunk_keys[coord] = _chunk_static_key(streamed_chunks[coord])
			_dot_keys[coord] = _chunk_dot_key(streamed_chunks[coord])
	for value in _chunk_meshes.keys():
		if not streamed_chunks.has(value):
			_chunk_meshes.erase(value)
	for value in _dot_meshes.keys():
		if not streamed_chunks.has(value):
			_dot_meshes.erase(value)


## What a chunk's dots depend on: its decor and pickups (the lists only change by discovery and by pickups taken).
func _chunk_dot_key(chunk: Dictionary) -> int:
	var h := (chunk.get("props", []) as Array).size() * 977
	for pickup_value in chunk.get("pickups", []):
		var pickup: Dictionary = pickup_value
		h = h * 31 ^ hash(String(pickup.get("id", "")))
	return h


## What a chunk's cached mesh depends on: its walls and water, its region tint (with the region overlay on), and its props
## (the solid-prop boxes). The prop count stands in for the prop list: the list only grows as props are discovered.
func _chunk_static_key(chunk: Dictionary) -> int:
	var h := hash(chunk.get("walls", PackedByteArray()))
	h ^= hash(chunk.get("water", PackedByteArray())) * 3
	h ^= hash(String(chunk.get("region", "")))
	h ^= (chunk.get("props", []) as Array).size() * 977
	h ^= int(streamed_show_regions) * 7919
	return h


func _tally(kind: String, count: int = 1) -> void:
	perf_draws += count
	perf_by_kind[kind] = int(perf_by_kind.get(kind, 0)) + count


func _draw() -> void:
	if perf_probe:
		perf_redraws += 1
		var started := Time.get_ticks_usec()
		_draw_map()
		perf_draw_usec += Time.get_ticks_usec() - started
		return
	_draw_map()


func _draw_map() -> void:
	if streamed_chunk_size > 0:
		_draw_streamed()
		return
	if generator == null or generator.cols <= 0:
		return
	var cell := minf(size.x / float(generator.cols), size.y / float(generator.rows))
	var origin := (size - Vector2(generator.cols, generator.rows) * cell) * 0.5

	# Floor first as one rect, then walls over it: two thousand cells of
	# per-tile floor drawing is most of the frame, and the floor is one colour.
	draw_rect(Rect2(origin, Vector2(generator.cols, generator.rows) * cell),
		Palette.BACKDROP)
	var wall_size := Vector2(cell, cell)
	for y in generator.rows:
		var row: Array = generator.grid[y]
		for x in generator.cols:
			if row[x] != WALL:
				continue
			draw_rect(Rect2(origin + Vector2(x, y) * cell, wall_size), Palette.PANEL)

	_dots(origin, cell, generator.relays, RELAY_TEAL_BLUE, 0.34)
	_dots(origin, cell, generator.batteries, Color(0.95, 0.82, 0.25), 0.26)
	if generator.exit_cell.x >= 0:
		draw_circle(origin + (Vector2(generator.exit_cell) + Vector2(0.5, 0.5)) * cell,
			cell * 0.4, Color(0.76, 0.55, 0.96))

	# Hunters over objectives, because a hunter standing on a relay is the thing
	# you most need to see.
	for mark in hunters:
		if not bool(mark.get("active", true)):
			continue
		var at: Vector2 = origin + (mark["at"] as Vector2) * cell
		_draw_hunter_marker(at, cell, mark)
	for mark in players:
		_draw_remote_player(origin + (mark.get("at", Vector2.ZERO) as Vector2) * cell,
			cell, mark)
	_draw_pings(origin, Vector2.ZERO, cell)
	_draw_pulses(origin, Vector2.ZERO, cell)
	for mark in dropped_tools:
		_draw_dropped_tool(origin + (mark.get("at", Vector2.ZERO) as Vector2) * cell,
			cell, mark)
	for mark in safe_rooms:
		_draw_safe_room_status(origin + (mark.get("at", Vector2.ZERO) as Vector2) * cell,
			cell, mark)

	_draw_player(origin, cell)


func _draw_streamed() -> void:
	var visible_coords := _visible_coords
	if visible_coords.is_empty():
		return
	var min_x := _bounds_min.x
	var min_z := _bounds_min.y
	var discovered_min := Vector2(min_x * streamed_chunk_size,
		min_z * streamed_chunk_size)
	var discovered_size := Vector2((_bounds_max.x - min_x + 1) * streamed_chunk_size,
		(_bounds_max.y - min_z + 1) * streamed_chunk_size)
	var world_min_x := floori(discovered_min.x)
	var world_min_z := floori(discovered_min.y)
	var cols := roundi(discovered_size.x)
	var rows := roundi(discovered_size.y)
	var origin := Vector2.ZERO
	var cell := 1.0
	var world_origin := discovered_min
	if streamed_focus_radius_cells > 0:
		cols = streamed_focus_radius_cells * 2
		rows = streamed_focus_radius_cells * 2
		world_min_x = floori(player_at.x) - streamed_focus_radius_cells
		world_min_z = floori(player_at.y) - streamed_focus_radius_cells
		cell = minf(size.x / float(cols), size.y / float(rows))
		origin = (size - Vector2(cols, rows) * cell) * .5
		world_origin = Vector2(world_min_x, world_min_z)
	else:
		_base_cell_scale = minf(size.x / maxf(1.0, discovered_size.x),
			size.y / maxf(1.0, discovered_size.y))
		cell = _base_cell_scale * map_zoom
		_last_world_center = discovered_min + discovered_size * .5
		if not _view_center_valid:
			_view_center = player_at
			_view_center_valid = true
		world_origin = _view_center - size / (2.0 * cell)
		world_min_x = floori(world_origin.x)
		world_min_z = floori(world_origin.y)
		cols = ceili(size.x / cell) + 1
		rows = ceili(size.y / cell) + 1
	_last_cell_scale = cell
	_last_world_origin = world_origin
	_last_screen_origin = origin
	var world_bounds := Rect2i(world_min_x, world_min_z, cols, rows)
	# Full map: backdrop, walls, water and solid-prop boxes come from each chunk's cached mesh, one draw per chunk in view.
	# The minimap (focus radius) keeps the per-cell draws, clipped to its square.
	var mesh_path := streamed_focus_radius_cells <= 0
	var mesh_transform := Transform2D(0.0, Vector2.ONE * cell, 0.0, origin - world_origin * cell)
	for coord in visible_coords:
		var chunk: Dictionary = streamed_chunks[coord]
		var chunk_region := String(chunk.get("region", "maze"))
		var floor_tint := Palette.PANEL
		if streamed_show_regions:
			floor_tint = Palette.PANEL.lerp(region_color(chunk_region), .52)
		var chunk_world_origin := Vector2i(coord.x * streamed_chunk_size,
			coord.z * streamed_chunk_size)
		var chunk_bounds := Rect2i(chunk_world_origin,
			Vector2i.ONE * streamed_chunk_size)
		var visible_bounds := chunk_bounds.intersection(world_bounds)
		if visible_bounds.size.x <= 0 or visible_bounds.size.y <= 0:
			continue
		var local_origin := origin + (Vector2(chunk_world_origin) - world_origin) * cell
		if mesh_path:
			_draw_chunk_mesh(coord, chunk, mesh_transform)
			_draw_chunk_dots(coord, chunk, mesh_transform, cell)
		else:
			draw_rect(Rect2(origin + (Vector2(visible_bounds.position) - world_origin) * cell,
				Vector2(visible_bounds.size) * cell), Palette.BACKDROP)
			if perf_probe:
				_tally("backdrop")
		var wall_draws := 0
		var walls: PackedByteArray = PackedByteArray() if mesh_path else chunk.get("walls", PackedByteArray())
		if walls.size() == streamed_chunk_size * streamed_chunk_size:
			for index in walls.size():
				if walls[index] == WALL:
					continue
				var x := index % streamed_chunk_size
				var z := index / streamed_chunk_size
				if not world_bounds.has_point(chunk_world_origin + Vector2i(x, z)):
					continue
				draw_rect(Rect2(local_origin + Vector2(x, z) * cell,
					Vector2.ONE * cell), floor_tint)
				wall_draws += 1
		if perf_probe:
			_tally("wall_rect", wall_draws)
		var water: PackedByteArray = PackedByteArray() if mesh_path else chunk.get("water", PackedByteArray())
		if water.size() == streamed_chunk_size * streamed_chunk_size:
			for index in water.size():
				if water[index] == 0:
					continue
				var wx := index % streamed_chunk_size
				var wz := index / streamed_chunk_size
				if world_bounds.has_point(chunk_world_origin + Vector2i(wx, wz)):
					draw_rect(Rect2(local_origin + Vector2(wx, wz) * cell, Vector2.ONE * cell), SEWER_WATER_TINT)
					if perf_probe:
						_tally("water_rect")
		for ladder_value in chunk.get("ladders", []):
			var ladder: Dictionary = ladder_value
			var ladder_cell: Vector2i = ladder.get("cell", Vector2i.ZERO)
			if world_bounds.has_point(chunk_world_origin + ladder_cell):
				var icon_at := local_origin + (Vector2(ladder_cell) + Vector2(.5, .5)) * cell
				var up := String(ladder.get("direction", "")) == "up"
				# ramps, switchback stairwells and spiral stairs: the stair icon (up or down)
				if String(ladder.get("kind", "ladder")) in ["ramp", "stairs", "spiral"]:
					_draw_stair_icon(icon_at, cell, up)
					if perf_probe:
						_tally("stair_icon")
				# ladders are not marked on the maps: only stairs, ramps and spirals
		# the full map's dots (props and pickups) are in the chunk's dot mesh, so these loops run for the minimap only
		for prop_value in (chunk.get("props", []) if not mesh_path else []):
			var prop: Dictionary = prop_value
			var local: Vector2i = prop.get("cell", Vector2i.ZERO)
			if not world_bounds.has_point(chunk_world_origin + local):
				continue
			if String(prop.get("kind", "prop")) == "prop":
				# solid props: their real collision boxes (decor has none and is not drawn); the full map's chunk mesh has them
				for box in (prop.get("boxes", []) if not mesh_path else []):
					_draw_collider_box(local_origin, cell, box, PROP_BOX_TINT)
					if perf_probe:
						_tally("collider_poly")
				continue
			var prop_at := local_origin + (Vector2(local) + Vector2(.5, .5)) * cell
			draw_circle(prop_at, maxf(1.0, cell * .16), PROP_BOX_TINT)
			if perf_probe:
				_tally("prop_circle")
		for pickup_value in (chunk.get("pickups", []) if not mesh_path else []):
			var pickup: Dictionary = pickup_value
			var kind := String(pickup.get("kind", ""))
			if kind not in ["relay", "battery"]:
				continue
			var local: Vector2i = pickup.get("cell", Vector2i.ZERO)
			if not world_bounds.has_point(chunk_world_origin + local):
				continue
			var tint := RELAY_TEAL_BLUE if kind == "relay" \
				else Color(0.95, 0.82, 0.25)
			draw_circle(local_origin + (Vector2(local) + Vector2(.5, .5)) * cell,
				maxf(1.0, cell * (.34 if kind == "relay" else .26)), tint)
			if perf_probe:
				_tally("pickup_circle")
		var spawn_cell: Vector2i = chunk.get("spawn", Vector2i(-1, -1))
		if spawn_cell.x >= 0 and world_bounds.has_point(chunk_world_origin + spawn_cell):
			if perf_probe:
				_tally("spawn", 3)
			var spawn_at := local_origin + (Vector2(spawn_cell) + Vector2(.5, .5)) * cell
			draw_circle(spawn_at, maxf(2.0, cell * .48), Color("65d394"))
			draw_line(spawn_at - Vector2(cell * .3, 0),
				spawn_at + Vector2(cell * .3, 0), Palette.BACKDROP, maxf(1.0, cell * .12))
			draw_line(spawn_at - Vector2(0, cell * .3),
				spawn_at + Vector2(0, cell * .3), Palette.BACKDROP, maxf(1.0, cell * .12))
		if streamed_show_stairs:
			for stair_value in chunk.get("stairs", []):
				var stair: Dictionary = stair_value
				var stair_cell: Vector2i = stair.get("cell", Vector2i.ZERO)
				if not world_bounds.has_point(chunk_world_origin + stair_cell):
					continue
				var stair_at := local_origin + (Vector2(stair_cell) + Vector2(.5, .5)) * cell
				var up := String(stair.get("direction", "")) == "up"
				_draw_stair_icon(stair_at, cell, up)
				if perf_probe:
					_tally("stair_icon")
	if streamed_show_regions:
		_draw_streamed_region_boundaries(visible_coords, origin, world_origin,
			world_bounds, cell)
		_draw_streamed_region_key(visible_coords)
		if perf_probe:
			_tally("region_key")
	_draw_waypoint_route(origin, world_origin, world_bounds, cell)
	if perf_probe:
		_tally("marker_helper")
	for mark in hunters:
		if not bool(mark.get("active", true)):
			continue
		var mark_world: Vector2 = mark["at"]
		var mark_at := origin + (mark_world - world_origin) * cell
		if bool(mark.get("ghost", false)) and ghost_ping:
			_draw_ghost_ping(mark_at, cell)   # clamps to the edge when she is out of range
			continue
		if not Rect2(world_bounds).has_point(mark_world):
			continue
		_draw_hunter_marker(mark_at, cell, mark)
		if perf_probe:
			_tally("marker_helper")
	for mark in players:
		var mark_world: Vector2 = mark.get("at", Vector2.ZERO)
		if mark.has("exit_direction") and not Rect2(world_bounds).has_point(mark_world):
			continue
		_draw_remote_player(origin + (mark_world - world_origin) * cell, cell, mark)
		if perf_probe:
			_tally("marker_helper")
	_draw_pings(origin, world_origin, cell)
	if perf_probe:
		_tally("marker_helper")
	_draw_pulses(origin, world_origin, cell)
	if perf_probe:
		_tally("marker_helper")
	for mark in dropped_tools:
		var mark_world: Vector2 = mark.get("at", Vector2.ZERO)
		if not Rect2(world_bounds).has_point(mark_world):
			continue
		_draw_dropped_tool(origin + (mark_world - world_origin) * cell, cell, mark)
		if perf_probe:
			_tally("marker_helper")
	for mark in safe_rooms:
		var mark_world: Vector2 = mark.get("at", Vector2.ZERO)
		if not Rect2(world_bounds).has_point(mark_world):
			continue
		_draw_safe_room_status(origin + (mark_world - world_origin) * cell, cell, mark)
		if perf_probe:
			_tally("marker_helper")
	for waypoint_value in waypoints:
		var waypoint: Dictionary = waypoint_value
		if int(waypoint.get("level", streamed_level)) != streamed_level:
			continue
		var waypoint_world: Vector2 = waypoint.get("at", Vector2.ZERO)
		if not Rect2(world_bounds).has_point(waypoint_world):
			continue
		var waypoint_at := origin + (waypoint_world - world_origin) * cell
		_draw_waypoint(waypoint_at, cell)
		if perf_probe:
			_tally("marker_helper")
	_draw_player(origin - world_origin * cell, cell)
	if perf_probe:
		_tally("marker_helper")


## One chunk's static layer on the full map: a mesh in absolute chunk-grid cells (the draw transform scales it), in the same paint
## order as the per-cell draw: backdrop, floor cells (horizontal runs merged), sewer water, then the solid-prop collision boxes.
func _draw_chunk_mesh(coord: Vector3i, chunk: Dictionary, xform: Transform2D) -> void:
	var key := int(_chunk_keys[coord]) if _chunk_keys.has(coord) else _chunk_static_key(chunk)
	if not _chunk_meshes.has(coord) or int(_chunk_meshes[coord]["key"]) != key:
		_chunk_meshes[coord] = {"key": key, "mesh": _build_chunk_mesh(coord, chunk)}
		if perf_probe:
			perf_mesh_builds += 1
	var mesh: ArrayMesh = _chunk_meshes[coord]["mesh"]
	if mesh == null:
		return
	draw_mesh(mesh, null, xform)
	if perf_probe:
		_tally("chunk_mesh")


func _build_chunk_mesh(coord: Vector3i, chunk: Dictionary) -> ArrayMesh:
	var side := streamed_chunk_size
	var corner := Vector2(coord.x * side, coord.z * side)
	_mesh_verts = PackedVector2Array()
	_mesh_colours = PackedColorArray()
	_mesh_indices = PackedInt32Array()
	var floor_tint := Palette.PANEL
	if streamed_show_regions:
		floor_tint = Palette.PANEL.lerp(region_color(String(chunk.get("region", "maze"))), .52)
	_mesh_rect(corner, Vector2(side, side), Palette.BACKDROP)
	var walls: PackedByteArray = chunk.get("walls", PackedByteArray())
	if walls.size() == side * side:
		for z in side:
			var x := 0
			while x < side:
				if walls[z * side + x] == WALL:
					x += 1
					continue
				var run_start := x
				while x < side and walls[z * side + x] != WALL:
					x += 1
				_mesh_rect(corner + Vector2(run_start, z), Vector2(x - run_start, 1), floor_tint)
	var water: PackedByteArray = chunk.get("water", PackedByteArray())
	if water.size() == side * side:
		for z in side:
			var x := 0
			while x < side:
				if water[z * side + x] == 0:
					x += 1
					continue
				var run_start := x
				while x < side and water[z * side + x] != 0:
					x += 1
				_mesh_rect(corner + Vector2(run_start, z), Vector2(x - run_start, 1), SEWER_WATER_TINT)
	for prop_value in chunk.get("props", []):
		var prop: Dictionary = prop_value
		if String(prop.get("kind", "prop")) != "prop":
			continue
		for box in prop.get("boxes", []):
			var points := collider_corners(box)
			_mesh_quad(corner + points[0], corner + points[1], corner + points[2],
				corner + points[3], PROP_BOX_TINT)
	return _take_mesh()


## One chunk's dots on the full map: the decor circles (PROP_BOX_TINT) and the relay and battery pickups, each radius held to its
## on-screen size at this cell (the 1 px minimum included), so the mesh is exact for the cell it was built at.
func _draw_chunk_dots(coord: Vector3i, chunk: Dictionary, xform: Transform2D, cell: float) -> void:
	var key := int(_dot_keys[coord]) if _dot_keys.has(coord) else _chunk_dot_key(chunk)
	if not _dot_meshes.has(coord) or int(_dot_meshes[coord]["key"]) != key \
			or float(_dot_meshes[coord]["cell"]) != cell:
		_dot_meshes[coord] = {"key": key, "cell": cell, "mesh": _build_chunk_dots(coord, chunk, cell)}
		if perf_probe:
			perf_dot_builds += 1
	var mesh: ArrayMesh = _dot_meshes[coord]["mesh"]
	if mesh == null:
		return
	draw_mesh(mesh, null, xform)
	if perf_probe:
		_tally("chunk_dots")


func _build_chunk_dots(coord: Vector3i, chunk: Dictionary, cell: float) -> ArrayMesh:
	var corner := Vector2(coord.x * streamed_chunk_size, coord.z * streamed_chunk_size)
	_mesh_verts = PackedVector2Array()
	_mesh_colours = PackedColorArray()
	_mesh_indices = PackedInt32Array()
	for prop_value in chunk.get("props", []):
		var prop: Dictionary = prop_value
		if String(prop.get("kind", "prop")) == "prop":
			continue
		var local: Vector2i = prop.get("cell", Vector2i.ZERO)
		_mesh_circle(corner + Vector2(local) + Vector2(.5, .5), maxf(1.0, cell * .16) / cell, PROP_BOX_TINT)
	for pickup_value in chunk.get("pickups", []):
		var pickup: Dictionary = pickup_value
		var kind := String(pickup.get("kind", ""))
		if kind not in ["relay", "battery"]:
			continue
		var local: Vector2i = pickup.get("cell", Vector2i.ZERO)
		var tint := RELAY_TEAL_BLUE if kind == "relay" else Color(0.95, 0.82, 0.25)
		_mesh_circle(corner + Vector2(local) + Vector2(.5, .5),
			maxf(1.0, cell * (.34 if kind == "relay" else .26)) / cell, tint)
	return _take_mesh()


func _mesh_circle(centre: Vector2, radius: float, colour: Color) -> void:
	var first := _mesh_verts.size()
	_mesh_verts.append(centre)
	_mesh_colours.append(colour)
	for k in CIRCLE_SEGMENTS:
		var angle := TAU * float(k) / float(CIRCLE_SEGMENTS)
		_mesh_verts.append(centre + Vector2(cos(angle), sin(angle)) * radius)
		_mesh_colours.append(colour)
	for k in CIRCLE_SEGMENTS:
		_mesh_indices.append(first)
		_mesh_indices.append(first + 1 + k)
		_mesh_indices.append(first + 1 + (k + 1) % CIRCLE_SEGMENTS)


## The mesh of the vertices collected so far (null when there are none); the collectors are emptied.
func _take_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = null
	if not _mesh_verts.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _mesh_verts
		arrays[Mesh.ARRAY_COLOR] = _mesh_colours
		arrays[Mesh.ARRAY_INDEX] = _mesh_indices
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_verts = PackedVector2Array()
	_mesh_colours = PackedColorArray()
	_mesh_indices = PackedInt32Array()
	return mesh


func _mesh_rect(at: Vector2, span: Vector2, colour: Color) -> void:
	_mesh_quad(at, at + Vector2(span.x, 0.0), at + span, at + Vector2(0.0, span.y), colour)


func _mesh_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, colour: Color) -> void:
	var first := _mesh_verts.size()
	_mesh_verts.append(a)
	_mesh_verts.append(b)
	_mesh_verts.append(c)
	_mesh_verts.append(d)
	for _corner in 4:
		_mesh_colours.append(colour)
	_mesh_indices.append(first)
	_mesh_indices.append(first + 1)
	_mesh_indices.append(first + 2)
	_mesh_indices.append(first)
	_mesh_indices.append(first + 2)
	_mesh_indices.append(first + 3)


static func region_color(region: String) -> Color:
	return REGION_COLORS.get(region, Color("87939b"))


func _draw_streamed_region_boundaries(visible_coords: Array[Vector3i],
		origin: Vector2, world_origin: Vector2, world_bounds: Rect2i,
		cell: float) -> void:
	var visible_lookup := {}
	for coord in visible_coords:
		visible_lookup[coord] = true
	var directions := [
		{"step": Vector3i(-1, 0, 0), "from": Vector2(0, 0),
			"to": Vector2(0, streamed_chunk_size)},
		{"step": Vector3i(1, 0, 0), "from": Vector2(streamed_chunk_size, 0),
			"to": Vector2(streamed_chunk_size, streamed_chunk_size)},
		{"step": Vector3i(0, 0, -1), "from": Vector2(0, 0),
			"to": Vector2(streamed_chunk_size, 0)},
		{"step": Vector3i(0, 0, 1), "from": Vector2(0, streamed_chunk_size),
			"to": Vector2(streamed_chunk_size, streamed_chunk_size)},
	]
	for coord in visible_coords:
		var chunk: Dictionary = streamed_chunks[coord]
		var region := String(chunk.get("region", "maze"))
		var chunk_origin := Vector2(coord.x * streamed_chunk_size,
			coord.z * streamed_chunk_size)
		for direction_value in directions:
			var direction: Dictionary = direction_value
			var neighbour: Vector3i = coord + (direction["step"] as Vector3i)
			if visible_lookup.has(neighbour) and String((streamed_chunks[neighbour] \
					as Dictionary).get("region", "maze")) == region:
				continue
			var from_world := chunk_origin + (direction["from"] as Vector2)
			var to_world := chunk_origin + (direction["to"] as Vector2)
			var edge_bounds := Rect2(Vector2(world_bounds.position),
				Vector2(world_bounds.size)).grow(1.0)
			if not edge_bounds.has_point(from_world) \
					and not edge_bounds.has_point(to_world):
				continue
			draw_line(origin + (from_world - world_origin) * cell,
				origin + (to_world - world_origin) * cell,
				region_color(region).lightened(.22), maxf(1.5, cell * .22), true)
			if perf_probe:
				_tally("region_line")


func _draw_streamed_region_key(visible_coords: Array[Vector3i]) -> void:
	var regions := []
	for coord in visible_coords:
		var region := String((streamed_chunks[coord] as Dictionary).get(
			"region", "maze"))
		if not regions.has(region):
			regions.append(region)
	regions.sort()
	if regions.is_empty() or not RegionNames.visible():
		return
	var current_coord := Vector3i(floori(player_at.x / streamed_chunk_size),
		streamed_level, floori(player_at.y / streamed_chunk_size))
	var current_region := ""
	if streamed_chunks.has(current_coord):
		current_region = String((streamed_chunks[current_coord] as Dictionary).get(
			"region", "maze"))
	var font := ThemeDB.fallback_font
	var font_size := 10 if interactive else 8
	var labels := regions if interactive else ([current_region] \
		if not current_region.is_empty() else [])
	var key_width := 0.0
	for region_value in labels:
		key_width += font.get_string_size(String(region_value).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 22.0
	if key_width <= 0.0:
		return
	var key_at := Vector2(7, size.y - font_size - 11)
	draw_rect(Rect2(key_at - Vector2(4, 4),
		Vector2(minf(key_width + 8.0, size.x - 6.0), font_size + 9.0)),
		Color(Palette.BACKDROP, .86))
	for region_value in labels:
		var region := String(region_value)
		draw_rect(Rect2(key_at, Vector2(9, 9)), region_color(region))
		var label := region.to_upper()
		draw_string(font, key_at + Vector2(13, 9), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.INK)
		key_at.x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x + 22.0


func add_ping(at: Vector2, colour: Color, label: String) -> void:
	pings.append({"at": at, "colour": colour, "label": label.to_upper().substr(0, 12),
		"until": Time.get_ticks_msec() + int(PING_SECONDS * 1000.0)})
	_mark_dirty(true)


func live_pings() -> Array:
	var now := Time.get_ticks_msec()
	pings = pings.filter(func(ping: Dictionary) -> bool: return int(ping["until"]) > now)
	return pings


func _draw_pings(origin: Vector2, world_origin: Vector2, cell: float) -> void:
	var font := ThemeDB.fallback_font
	var now := Time.get_ticks_msec()
	for ping_value in live_pings():
		var ping: Dictionary = ping_value
		var at: Vector2 = origin + ((ping["at"] as Vector2) - world_origin) * cell
		var left := float(int(ping["until"]) - now) / (PING_SECONDS * 1000.0)
		var colour: Color = ping["colour"]
		var radius := maxf(3.0, cell * .6)
		var pulse := 1.0 + .5 * fposmod(float(now) / 700.0, 1.0)
		draw_arc(at, radius * pulse, 0.0, TAU, 18, Color(colour, .9 * left), maxf(1.0, cell * .12), true)
		draw_circle(at, radius * .45, Color(colour, .95))
		if interactive:
			draw_string_outline(font, at + Vector2(radius + 2.0, 3.0), String(ping["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color(0, 0, 0, .9))
			draw_string(font, at + Vector2(radius + 2.0, 3.0), String(ping["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, colour.lightened(.2))


func _ping_clock() -> float:
	return radar_time if radar_time >= 0.0 else Time.get_ticks_msec() / 1000.0


## Porcelle's pulse: a dot with one expanding ring while a ping lasts, nothing in between; out of range it clamps to the
## edge as a small arrow so the direction still reads. Reduced motion draws the steady dim dot instead.
func _draw_ghost_ping(at: Vector2, cell: float) -> void:
	var info := RadarPing.marker(at, Rect2(Vector2.ZERO, size), _ping_clock(), Settings.reduced_motion)
	if not bool(info["visible"]):
		return
	var strength: float = info["strength"]
	var pos: Vector2 = info["pos"]
	var radius := maxf(RadarPing.MIN_RADIUS, cell * RadarPing.MARK_RADIUS_CELLS)
	var colour := Palette.ALERT
	if bool(info["clamped"]):
		var dir: Vector2 = info["direction"]
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([pos + dir * radius, pos - dir * radius * .6 + side * radius * .7,
			pos - dir * radius * .6 - side * radius * .7]), Color(colour, strength))
		return
	draw_circle(pos, radius, Color(colour, strength))
	if not Settings.reduced_motion:
		var grown := radius * lerpf(1.0, RadarPing.RING_GROWTH, float(info["progress"]))
		draw_arc(pos, grown, 0.0, TAU, 20, Color(colour, strength * (1.0 - float(info["progress"]))), maxf(1.0, cell * .10), true)


func _draw_hunter_marker(at: Vector2, cell: float, mark: Dictionary) -> void:
	if bool(mark.get("ghost", false)) and ghost_ping:
		_draw_ghost_ping(at, cell)
		return
	if bool(mark.get("ghost", false)):
		# Porcelle is readable but deliberately uncertain: a translucent head and
		# taper replace the solid danger dot used by visible hunters.
		var radius := maxf(2.0, cell * .52)
		var ghost_fill := Color(PORCELLE_GHOST, .30)
		var ghost_edge := Color(PORCELLE_GHOST, .62)
		draw_circle(at - Vector2(0, radius * .28), radius * .58, ghost_fill)
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(-radius * .62, -radius * .05),
			at + Vector2(radius * .62, -radius * .05),
			at + Vector2(radius * .42, radius * .70),
			at + Vector2(0, radius * .48),
			at + Vector2(-radius * .42, radius * .70),
		]), ghost_fill)
		draw_arc(at - Vector2(0, radius * .28), radius * .58, PI, TAU,
			12, ghost_edge, maxf(1.0, cell * .10), true)
		for eye_x in [-.20, .20]:
			draw_circle(at + Vector2(radius * eye_x, -radius * .30),
				maxf(.7, radius * .10), Color(PORCELLE_GHOST, .78))
		return
	# A solid dot with the hunter's initial centred in it. The dot has a floor
	# size (bigger on the full map) so the initial always fits inside it, and a
	# dark rim so it reads over floor, props and relays alike.
	var radius := maxf(cell * .55, HUNTER_BLIP_MIN_RADIUS_FULL if interactive
		else HUNTER_BLIP_MIN_RADIUS_MINI)
	draw_circle(at, radius + 1.0, Palette.BACKDROP)
	draw_circle(at, radius, Palette.ACCENT)
	var label := String(mark.get("name", "?")).substr(0, 1).to_upper()
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	var font_size := hunter_blip_font_size(radius)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# draw_string places the baseline, so centre the cap height on the dot
	# (the old code put the baseline at the centre, which pushed the letter
	# into the top half and cut a notch out of small blips).
	draw_string(font, hunter_blip_label_origin(at, width, font, font_size), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.BACKDROP)


const HUNTER_BLIP_MIN_RADIUS_MINI := 4.5
const HUNTER_BLIP_MIN_RADIUS_FULL := 7.0


## The initial's size for a hunter blip of `radius`: it fits inside the dot.
static func hunter_blip_font_size(radius: float) -> int:
	return clampi(roundi(radius * 1.3), 6, 12)


## Where draw_string must start so the initial is centred on `at` (baseline at
## the centre + half the glyph's visible height).
static func hunter_blip_label_origin(at: Vector2, width: float, font: Font, font_size: int) -> Vector2:
	var ascent := font.get_ascent(font_size)
	# capitals sit on the baseline and rise ~70% of the ascent
	var cap := ascent * .72
	return Vector2(at.x - width * .5, at.y + cap * .5)


## Co-op teammates. Same floor in view: a coloured arrow along their facing with an initial tag (the full map adds the callsign).
## Same floor off the view: the arrow becomes a pointer clamped to the map edge. Another floor: a dimmed dot with a triangle
## (up = a higher floor than yours) at their spot, or at the edge when out of view. Downed / spectating: a hollow grey ring with a cross.
const TEAMMATE_EDGE_MARGIN := 6.0


## Where and as what a teammate is drawn, given their screen position `at`: {kind: "arrow" | "downed" | "updown", shown (clamped to
## the map edge when off_view), off_view, outward (unit vector to them from the map centre), up (updown only)}.
func teammate_layout(at: Vector2, radius: float, mark: Dictionary) -> Dictionary:
	var inner := Rect2(Vector2.ZERO, size).grow(-maxf(TEAMMATE_EDGE_MARGIN, radius + 2.0))
	var off_view := not inner.has_point(at)
	var shown := at
	var outward := Vector2.ZERO
	if off_view and inner.size.x > 0.0 and inner.size.y > 0.0:
		var centre := inner.get_center()
		var delta := at - centre
		outward = delta.normalized()
		var half := inner.size * 0.5
		var t := minf(half.x / maxf(absf(delta.x), .0001), half.y / maxf(absf(delta.y), .0001))
		shown = centre + delta * minf(t, 1.0)
	var kind := "arrow"
	if bool(mark.get("other_floor", false)):
		kind = "updown"
	elif bool(mark.get("spectating", false)):
		kind = "downed"
	return {"kind": kind, "shown": shown, "off_view": off_view, "outward": outward,
		"up": int(mark.get("level", 0)) > streamed_level}


func _save_flash_live() -> bool:
	var now := Time.get_ticks_msec()
	for mark in safe_rooms:
		if int(mark.get("flash_until", 0)) > now:
			return true
	return false


func set_pulses(marks: Array) -> void:
	if pulses == marks:
		return
	pulses = marks.duplicate(true)
	_mark_dirty(true)


func _draw_pulses(origin: Vector2, world_origin: Vector2, cell: float) -> void:
	var now := Time.get_ticks_msec()
	for mark in pulses:
		if int(mark.get("until_msec", 0)) <= now:
			continue
		var world: Vector2 = mark.get("at", Vector2.ZERO)
		var at := origin + (world - world_origin) * cell
		var layout := teammate_layout(at, 4.0, {"other_floor": int(mark.get("level", streamed_level)) != streamed_level,
			"level": int(mark.get("level", streamed_level))})
		var shown: Vector2 = layout["shown"]
		var phase := fposmod(float(now) / 900.0, 1.0)
		var tint := Color("37e6d9")
		draw_circle(shown, 2.5, tint)
		draw_arc(shown, 4.0 + phase * 16.0, 0.0, TAU, 28, Color(tint, 1.0 - phase), 1.6, true)
		draw_arc(shown, 4.0 + fposmod(phase + .5, 1.0) * 16.0, 0.0, TAU, 28, Color(tint, 1.0 - fposmod(phase + .5, 1.0)), 1.2, true)
		var label := String(mark.get("name", "")).to_upper().substr(0, 12)
		if not label.is_empty():
			var font := ThemeDB.fallback_font
			var at_label := shown + Vector2(7.0, 3.0)
			if at_label.x + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x > size.x:
				at_label.x = shown.x - 8.0 - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
			draw_string_outline(font, at_label, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color(0.01, 0.04, 0.05, .95))
			draw_string(font, at_label, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, tint.lightened(.3))


## A revive window (ReviveDowns record via infinite_route_test.downed_map_marks()) as a map mark: where a teammate went down, the
## seconds left to revive them, and whether it is on another floor than the one shown (current_level).
static func down_map_mark(down: Dictionary, current_level: int) -> Dictionary:
	var world: Vector3 = down.get("at", Vector3.ZERO)
	var level := -int(down.get("depth", 0))
	return {"peer_id": int(down.get("peer", 0)), "at": Vector2(world.x, world.z), "level": level, "name": String(down.get("name", "")),
		"down_left": float(down.get("left", 0.0)), "other_floor": level != current_level, "colour": RouteInteractable3D.REVIVE_COLOR}


## Revive-green ring with a heartbeat line (never a red cross: that emblem is protected) and the name + seconds left: someone to revive. Another floor shows the up/down triangle; off the map it is
## clamped to the edge like a teammate.
func _draw_down_marker(at: Vector2, cell: float, mark: Dictionary) -> void:
	var radius := maxf(3.4 if interactive else 3.0, cell * .5)
	var layout := teammate_layout(at, radius, mark)
	var shown: Vector2 = layout["shown"]
	var pulse := 0.65 + 0.35 * sin(float(Time.get_ticks_msec()) / 180.0)
	var red := Color(RouteInteractable3D.REVIVE_COLOR, pulse)
	var ink := Color(0.01, 0.04, 0.05, .95)
	draw_circle(shown, radius + 1.2, Color(ink, .8))
	draw_arc(shown, radius, 0.0, TAU, 16, red, maxf(1.3, cell * .13), true)
	var beat := PackedVector2Array([shown + Vector2(-radius * .8, 0), shown + Vector2(-radius * .3, 0),
		shown + Vector2(-radius * .1, -radius * .7), shown + Vector2(radius * .15, radius * .6),
		shown + Vector2(radius * .35, 0), shown + Vector2(radius * .8, 0)])
	draw_polyline(beat, red, 1.2, true)
	if layout["kind"] == "updown":
		var dir := -1.0 if layout["up"] else 1.0
		var tri := PackedVector2Array([shown + Vector2(0, dir * radius * .9) + Vector2(radius + 3.5, 0),
			shown + Vector2(-radius * .5, -dir * radius * .4) + Vector2(radius + 3.5, 0),
			shown + Vector2(radius * .5, -dir * radius * .4) + Vector2(radius + 3.5, 0)])
		draw_colored_polygon(tri, red)
	var font := ThemeDB.fallback_font
	var label := "%s %dS" % [String(mark.get("name", "")).to_upper().substr(0, 10), ceili(float(mark.get("down_left", 0.0)))]
	var size_px := 7 if not interactive else 8
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var label_at := shown + Vector2(radius + 2.0, radius * .6)
	if label_at.x + width > size.x - 1.0:
		label_at.x = shown.x - radius - 2.0 - width
	draw_string_outline(font, label_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 3, ink)
	draw_string(font, label_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(RouteInteractable3D.REVIVE_COLOR.lightened(.25), pulse))


func _draw_remote_player(at: Vector2, cell: float, mark: Dictionary) -> void:
	if mark.has("exit_direction"):
		_draw_floor_exit_marker(at, cell, String(mark.get("exit_direction", "up")),
			String(mark.get("name", "")))
		return
	if mark.has("down_left"):
		_draw_down_marker(at, cell, mark)
		return
	var radius := maxf(3.4 if interactive else 3.0, cell * .5)
	# outside the map's range: a smaller arrow on the border pointing toward them; another floor: a tiny up/down mark
	var border_view := not Rect2(Vector2.ZERO, size).grow(-maxf(TEAMMATE_EDGE_MARGIN, radius + 2.0)).has_point(at)
	if border_view:
		radius *= 0.65
	var colour: Color = mark.get("colour", COOP_PLAYER_BLUE)
	if bool(mark.get("stale", false)):
		colour = Color(colour, .45)   # no news for a while: last known spot, dimmed
	var layout := teammate_layout(at, radius, mark)
	var off_view: bool = layout["off_view"]
	var shown: Vector2 = layout["shown"]
	var outward: Vector2 = layout["outward"]
	var ink := Color(0.01, 0.04, 0.05, .95)
	# Every player is an arrow in their own colour, no dots, initials or names (names live on the HUD waypoints).
	if layout["kind"] == "updown":
		# another floor: a bold up / down arrow in their colour
		var dir := -1.0 if layout["up"] else 1.0
		var reach := radius * (1.0 if not interactive else 1.6)   # the minimap keeps it tiny
		var tri := PackedVector2Array([shown + Vector2(0, dir * reach), shown + Vector2(-reach * .8, -dir * reach * .6),
			shown + Vector2(reach * .8, -dir * reach * .6)])
		var tri_outline := PackedVector2Array()
		for point in tri:
			tri_outline.append(shown + (point - shown) * 1.35)
		draw_colored_polygon(tri_outline, ink)
		draw_colored_polygon(tri, colour)
		return
	var facing: Vector2 = outward if off_view else mark.get("facing", Vector2.UP)
	if facing.length_squared() < .01:
		facing = Vector2.UP
	facing = facing.normalized()
	var side := Vector2(-facing.y, facing.x)
	var length := radius * 1.55
	var arrow := PackedVector2Array([shown + facing * length,
		shown - facing * length * .7 + side * radius * 1.05,
		shown - facing * length * .25,
		shown - facing * length * .7 - side * radius * 1.05])
	var outline := PackedVector2Array()
	for point in arrow:
		outline.append(point + (point - shown).normalized() * 1.1)
	draw_colored_polygon(outline, ink)
	if layout["kind"] == "downed":
		# downed / spectating: the same arrow, hollow
		var hollow := arrow.duplicate()
		hollow.append(arrow[0])
		draw_polyline(hollow, colour, 1.5, true)
	else:
		draw_colored_polygon(arrow, colour)


func _draw_floor_exit_marker(at: Vector2, cell: float, direction: String,
		display_name: String) -> void:
	var up := direction != "down"
	var radius := maxf(3.5, cell * .60)
	var tint := Color("8fe7ff")
	draw_circle(at, radius + maxf(1.0, cell * .12), Color(0.01, 0.04, 0.05, .95))
	draw_circle(at, radius, Color(tint, .20))
	_draw_stair_icon(at, cell, up)
	var label := String(display_name).substr(0, 1).to_upper()
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	var font_size := clampi(roundi(cell * .56), 6, 10)
	var glyph := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, at + Vector2(-glyph.x * .5, radius + glyph.y + 1.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


func _draw_dropped_tool(at: Vector2, cell: float, mark: Dictionary) -> void:
	var radius := maxf(2.5, cell * .34)
	var tint := Color("f2bb62")
	draw_circle(at, radius + maxf(1.0, cell * .10), Color(0.01, 0.04, 0.05, .92))
	draw_circle(at, radius, tint)
	var label := String(mark.get("label", "T")).substr(0, 1).to_upper()
	var font := ThemeDB.fallback_font
	var font_size := clampi(roundi(cell * .56), 6, 10)
	var glyph := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, at - Vector2(glyph.x * .5, -glyph.y * .30), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.01, 0.04, 0.05))


## A save point (safe room / checkpoint): a green diamond, ringed when it is your active checkpoint; SABOTAGED is a red diamond with a
## slash; a fresh sabotage pulses for a few seconds. Another floor: the same icon dimmed with an up/down arrow beside it. No letters.
func _draw_safe_room_status(at: Vector2, cell: float, mark: Dictionary) -> void:
	var breached := bool(mark.get("breached", false))
	var active := bool(mark.get("active", false))
	var other_floor := bool(mark.get("other_floor", false))
	var alpha := 0.55 if other_floor else 1.0
	var tint := Color(Palette.ALERT if breached else Palette.STABLE, alpha)
	var ink := Color(0.01, 0.04, 0.05, .94 * alpha)
	var radius := maxf(3.4, cell * .48)
	var diamond := PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0)])
	var outline := PackedVector2Array()
	for point in diamond:
		outline.append(at + (point - at) * 1.3)
	draw_colored_polygon(outline, ink)
	draw_colored_polygon(diamond, tint)
	if breached:
		draw_line(at + Vector2(-radius * 1.1, radius * 1.1), at + Vector2(radius * 1.1, -radius * 1.1), ink, maxf(2.2, cell * .2), true)
		draw_line(at + Vector2(-radius * 1.1, radius * 1.1), at + Vector2(radius * 1.1, -radius * 1.1), Color(1.0, .85, .85, alpha), 1.0, true)
	else:
		draw_circle(at, radius * .32, ink)   # the "slot" of an intact save point
		if active:
			draw_arc(at, radius * 1.65, 0.0, TAU, 20, tint, maxf(1.2, cell * .12), true)
	if other_floor:
		var up := int(mark.get("level", streamed_level)) > streamed_level
		var dir := -1.0 if up else 1.0
		var beside := at + Vector2(radius * 2.0, 0)
		draw_colored_polygon(PackedVector2Array([beside + Vector2(0, dir * radius), beside + Vector2(-radius * .8, -dir * radius * .6),
			beside + Vector2(radius * .8, -dir * radius * .6)]), Color(tint, 1.0))
	var flash_left := int(mark.get("flash_until", 0)) - Time.get_ticks_msec()
	if flash_left > 0:
		var phase := fposmod(float(Time.get_ticks_msec()) / 600.0, 1.0)
		draw_arc(at, radius * (1.4 + phase * 2.4), 0.0, TAU, 24, Color(Palette.ALERT, 1.0 - phase), 1.6, true)


func _draw_waypoint_route(origin: Vector2, world_origin: Vector2,
		world_bounds: Rect2i, cell: float) -> void:
	if waypoint_path.size() < 2:
		return
	var screen_points := PackedVector2Array()
	var expanded_bounds := Rect2(world_bounds).grow(1.0)
	for value in waypoint_path:
		var world_point: Vector2 = value
		if expanded_bounds.has_point(world_point):
			screen_points.append(origin + (world_point - world_origin) * cell)
		elif not screen_points.is_empty():
			# Retain one off-screen endpoint so the route visibly exits the map
			# instead of stopping one cell before the edge.
			screen_points.append(origin + (world_point - world_origin) * cell)
			break
	if screen_points.size() < 2:
		return
	var width := maxf(1.6, cell * .24)
	draw_polyline(screen_points, Color(0.01, 0.04, 0.05, .92),
		width + maxf(1.5, cell * .18), true)
	draw_polyline(screen_points, Color("55e5d5"), width, true)
	# A dotted centre reads as a directional GPS trail without adding text.
	for index in range(2, screen_points.size(), 4):
		draw_circle(screen_points[index], maxf(1.25, cell * .16), Color("d9fff9"))


func _draw_waypoint(at: Vector2, cell: float) -> void:
	var radius := maxf(3.0, cell * .55)
	var tint := Color("55e5d5")
	var points := PackedVector2Array([
		at + Vector2(0, -radius), at + Vector2(radius, 0),
		at + Vector2(0, radius), at + Vector2(-radius, 0),
	])
	draw_colored_polygon(points, Color(tint, .28))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2],
		points[3], points[0]]), tint, maxf(1.25, cell * .12), true)


## Fullscreen/admin maps show a direction-aware white stair symbol. The regular
## minimap never reaches this helper because it deliberately hides stair data.
## The collision boxes of a generated chunk's solid props, by prop id: [PackedFloat32Array(centre x, centre z, half x,
## half z, yaw)] in chunk-local metres, straight from CollisionWorld (the boxes the 3D view builds), so the map shows
## exactly what blocks the player. Props the placement clean-up removed are not in the chunk and get nothing.
static func collider_boxes(data: Dictionary) -> Dictionary:
	var out := {}
	for rect_value in CollisionWorld.from_chunk(data).rects:
		var rect: Dictionary = rect_value
		var centre: Vector2 = rect["center"]
		var half: Vector2 = rect["half"]
		var list: Array = out.get(String(rect["id"]), [])
		list.append(PackedFloat32Array([centre.x, centre.y, half.x, half.y, float(rect["yaw"])]))
		out[String(rect["id"])] = list
	return out


## One collision box [centre x, centre z, half x, half z, yaw] in chunk-local metres, as the rotated rectangle the player meets.
static func collider_corners(box: PackedFloat32Array) -> PackedVector2Array:
	var centre := Vector2(box[0], box[1])
	var c := cos(box[4])
	var s := sin(box[4])
	var out := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var local := Vector2(box[2] * corner.x, box[3] * corner.y)
		out.append(centre + Vector2(local.x * c + local.y * s, -local.x * s + local.y * c))
	return out


func _draw_collider_box(local_origin: Vector2, cell: float, box: PackedFloat32Array, tint: Color) -> void:
	var points := collider_corners(box)
	for i in points.size():
		points[i] = local_origin + points[i] * cell
	draw_colored_polygon(points, tint)


## A ladder between the maze and the sewer: two rails and three rungs inside a
## ring, with a small arrow for the way it leads from this layer.
func _draw_ladder_icon(at: Vector2, cell: float, up: bool) -> void:
	var r := maxf(3.0, cell * .9)
	draw_circle(at, r, Palette.BACKDROP)
	draw_arc(at, r, 0.0, TAU, 20, LADDER_ICON_TINT, maxf(1.0, cell * .14))
	var w := r * .38
	var h := r * .62
	var line := maxf(1.0, cell * .12)
	draw_line(at + Vector2(-w, -h), at + Vector2(-w, h), LADDER_ICON_TINT, line)
	draw_line(at + Vector2(w, -h), at + Vector2(w, h), LADDER_ICON_TINT, line)
	for k in 3:
		var y := lerpf(-h * .6, h * .6, k / 2.0)
		draw_line(at + Vector2(-w, y), at + Vector2(w, y), LADDER_ICON_TINT, line)
	var tip := at + Vector2(r * 1.05, -r * .7 if up else r * .7)
	var back := -r * .35 if not up else r * .35
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-r * .3, back), tip + Vector2(r * .3, back)]),
		LADDER_ICON_TINT)


func _draw_stair_icon(at: Vector2, cell: float, up: bool) -> void:
	var tint := STAIR_ICON_WHITE
	var shadow := Color(0.02, 0.04, 0.05, 0.9)
	var radius := maxf(3.5, cell * .62)
	var thickness := maxf(1.25, cell * .13)
	var points := PackedVector2Array([
		at + Vector2(-radius, radius * .55),
		at + Vector2(-radius * .35, radius * .55),
		at + Vector2(-radius * .35, 0.0),
		at + Vector2(radius * .25, 0.0),
		at + Vector2(radius * .25, -radius * .55),
		at + Vector2(radius, -radius * .55),
	])
	draw_polyline(points, shadow, thickness + 2.0, true)
	draw_polyline(points, tint, thickness, true)
	var arrow_x := radius * .72
	var arrow_from := at + Vector2(arrow_x, radius * (.45 if up else -.45))
	var arrow_to := at + Vector2(arrow_x, radius * (-.45 if up else .45))
	draw_line(arrow_from, arrow_to, shadow, thickness + 2.0, true)
	draw_line(arrow_from, arrow_to, tint, thickness, true)
	var arrow_tip := arrow_to
	var arrow_sign := 1.0 if up else -1.0
	var arrow_left := arrow_tip + Vector2(-radius * .28, radius * .28 * arrow_sign)
	var arrow_right := arrow_tip + Vector2(radius * .28, radius * .28 * arrow_sign)
	draw_line(arrow_tip, arrow_left, shadow, thickness + 2.0, true)
	draw_line(arrow_tip, arrow_right, shadow, thickness + 2.0, true)
	draw_line(arrow_tip, arrow_left, tint, thickness, true)
	draw_line(arrow_tip, arrow_right, tint, thickness, true)


func _dots(origin: Vector2, cell: float, entries: Array, tint: Color, scale: float) -> void:
	for entry in entries:
		if entry.get("collected", false):
			continue
		draw_circle(origin + (Vector2(entry["x"], entry["y"]) + Vector2(0.5, 0.5)) * cell,
			cell * scale, tint)


## A wedge rather than a dot, because on a map of a maze "which way am I facing"
## is most of what you came here to find out.
func _draw_player(origin: Vector2, cell: float) -> void:
	var at := origin + player_at * cell
	var forward := player_facing.normalized() if player_facing.length() > 0.01 else Vector2(0, 1)
	var side := Vector2(-forward.y, forward.x)
	# full map: a fixed on-screen arrow (arrow_reach) with an outline; minimap: scales with its cells
	var reach := arrow_reach(cell, interactive)
	var arrow := PackedVector2Array([
		at + forward * reach,
		at - forward * reach * 0.5 + side * reach * 0.6,
		at - forward * reach * 0.5 - side * reach * 0.6,
	])
	if interactive:
		var outline := arrow.duplicate()
		outline.append(arrow[0])
		draw_polyline(outline, Color(0.01, 0.04, 0.05, .95), maxf(2.0, reach * .22), true)
	draw_colored_polygon(arrow, RemotePlayers.local_colour())
