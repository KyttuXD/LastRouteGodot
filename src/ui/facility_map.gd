class_name FacilityMap
extends Control

signal waypoint_requested(world_position: Vector2, level: int)

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
	"carnival": Color("ce5d96"),
}

@export var interactive := false

var generator: FacilityGenerator
var player_at := Vector2.ZERO
var player_facing := Vector2(0, 1)
## [{ "at": Vector2, "name": String, "active": bool }]
var hunters: Array = []
## Other runners are deliberately separate from hunter intelligence: co-op
## teammates remain visible on both maps while hunter markers still require
## the admin reveal permission.
var players: Array = []
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
var map_zoom := 1.0
var _pan_world := Vector2.ZERO
var _dragging := false
var _last_cell_scale := 1.0
var _last_world_origin := Vector2.ZERO
var _last_world_center := Vector2.ZERO
var _base_cell_scale := 1.0
var _last_screen_origin := Vector2.ZERO


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE


func _process(delta: float) -> void:
	if not interactive or not visible or not has_focus() or streamed_chunk_size <= 0:
		return
	# Full-map controller controls: left stick pans, shoulders zoom, and X drops
	# a waypoint at the centre crosshair. Gameplay is already frozen while this
	# surface is open, so these actions never leak into tools or movement.
	var pan := Input.get_vector("move_left", "move_right", "move_up", "move_down")
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
	elif event is InputEventMouseMotion and _dragging:
		pan_screen((event as InputEventMouseMotion).relative)
		accept_event()


func zoom_at(factor: float, screen_position: Vector2 = Vector2(-1, -1)) -> void:
	if not interactive or factor <= 0.0:
		return
	var focus := screen_position
	if focus.x < 0.0 or focus.y < 0.0:
		focus = size * .5
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
	_pan_world = wanted_origin - _last_world_center + size / (2.0 * new_cell)
	queue_redraw()


func pan_screen(screen_delta: Vector2) -> void:
	if not interactive:
		return
	# Dragging right moves the paper right, so the viewed world origin moves left.
	_pan_world -= screen_delta / maxf(.0001, _last_cell_scale)
	queue_redraw()


func reset_view() -> void:
	map_zoom = 1.0
	_pan_world = Vector2.ZERO
	_dragging = false
	queue_redraw()


func set_waypoints(marks: Array) -> void:
	waypoints = marks.duplicate(true)
	queue_redraw()


func set_waypoint_path(points: Array) -> void:
	waypoint_path = points.duplicate()
	queue_redraw()


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
	queue_redraw()


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
		if not mark.has("level") or int(mark["level"]) == level:
			players.append(mark)
	dropped_tools = []
	for mark_value in drop_marks:
		var mark: Dictionary = mark_value
		if not mark.has("level") or int(mark["level"]) == level:
			dropped_tools.append(mark)
	safe_rooms = []
	for mark_value in safe_room_marks:
		var mark: Dictionary = mark_value
		if not mark.has("level") or int(mark["level"]) == level:
			safe_rooms.append(mark)
	queue_redraw()


func _draw() -> void:
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
	for mark in dropped_tools:
		_draw_dropped_tool(origin + (mark.get("at", Vector2.ZERO) as Vector2) * cell,
			cell, mark)
	for mark in safe_rooms:
		_draw_safe_room_status(origin + (mark.get("at", Vector2.ZERO) as Vector2) * cell,
			cell, mark)

	_draw_player(origin, cell)


func _draw_streamed() -> void:
	var visible_coords: Array[Vector3i] = []
	for value in streamed_chunks.keys():
		var coord: Vector3i = value
		if coord.y == streamed_level:
			visible_coords.append(coord)
	if visible_coords.is_empty():
		return
	var min_x := visible_coords[0].x
	var max_x := min_x
	var min_z := visible_coords[0].z
	var max_z := min_z
	for coord in visible_coords:
		min_x = mini(min_x, coord.x)
		max_x = maxi(max_x, coord.x)
		min_z = mini(min_z, coord.z)
		max_z = maxi(max_z, coord.z)
	var discovered_min := Vector2(min_x * streamed_chunk_size,
		min_z * streamed_chunk_size)
	var discovered_size := Vector2((max_x - min_x + 1) * streamed_chunk_size,
		(max_z - min_z + 1) * streamed_chunk_size)
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
		world_origin = _last_world_center + _pan_world - size / (2.0 * cell)
		world_min_x = floori(world_origin.x)
		world_min_z = floori(world_origin.y)
		cols = ceili(size.x / cell) + 1
		rows = ceili(size.y / cell) + 1
	_last_cell_scale = cell
	_last_world_origin = world_origin
	_last_screen_origin = origin
	var world_bounds := Rect2i(world_min_x, world_min_z, cols, rows)
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
		draw_rect(Rect2(origin + (Vector2(visible_bounds.position) - world_origin) * cell,
			Vector2(visible_bounds.size) * cell), Palette.BACKDROP)
		var walls: PackedByteArray = chunk.get("walls", PackedByteArray())
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
		for pickup_value in chunk.get("pickups", []):
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
		for prop_value in chunk.get("props", []):
			var prop: Dictionary = prop_value
			var local: Vector2i = prop.get("cell", Vector2i.ZERO)
			if not world_bounds.has_point(chunk_world_origin + local):
				continue
			var prop_at := local_origin + (Vector2(local) + Vector2(.5, .5)) * cell
			var radius := maxf(1.0, cell * .20)
			draw_rect(Rect2(prop_at - Vector2.ONE * radius,
				Vector2.ONE * radius * 2.0), Color("7899a1"))
		var spawn_cell: Vector2i = chunk.get("spawn", Vector2i(-1, -1))
		if spawn_cell.x >= 0 and world_bounds.has_point(chunk_world_origin + spawn_cell):
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
	if streamed_show_regions:
		_draw_streamed_region_boundaries(visible_coords, origin, world_origin,
			world_bounds, cell)
		_draw_streamed_region_key(visible_coords)
	_draw_waypoint_route(origin, world_origin, world_bounds, cell)
	for mark in hunters:
		if not bool(mark.get("active", true)):
			continue
		var mark_world: Vector2 = mark["at"]
		if not Rect2(world_bounds).has_point(mark_world):
			continue
		var mark_at := origin + (mark_world - world_origin) * cell
		_draw_hunter_marker(mark_at, cell, mark)
	for mark in players:
		var mark_world: Vector2 = mark.get("at", Vector2.ZERO)
		if not Rect2(world_bounds).has_point(mark_world):
			continue
		_draw_remote_player(origin + (mark_world - world_origin) * cell, cell, mark)
	for mark in dropped_tools:
		var mark_world: Vector2 = mark.get("at", Vector2.ZERO)
		if not Rect2(world_bounds).has_point(mark_world):
			continue
		_draw_dropped_tool(origin + (mark_world - world_origin) * cell, cell, mark)
	for mark in safe_rooms:
		var mark_world: Vector2 = mark.get("at", Vector2.ZERO)
		if not Rect2(world_bounds).has_point(mark_world):
			continue
		_draw_safe_room_status(origin + (mark_world - world_origin) * cell, cell, mark)
	for waypoint_value in waypoints:
		var waypoint: Dictionary = waypoint_value
		if int(waypoint.get("level", streamed_level)) != streamed_level:
			continue
		var waypoint_world: Vector2 = waypoint.get("at", Vector2.ZERO)
		if not Rect2(world_bounds).has_point(waypoint_world):
			continue
		var waypoint_at := origin + (waypoint_world - world_origin) * cell
		_draw_waypoint(waypoint_at, cell)
	_draw_player(origin - world_origin * cell, cell)


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


func _draw_streamed_region_key(visible_coords: Array[Vector3i]) -> void:
	var regions := []
	for coord in visible_coords:
		var region := String((streamed_chunks[coord] as Dictionary).get(
			"region", "maze"))
		if not regions.has(region):
			regions.append(region)
	regions.sort()
	if regions.is_empty():
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


func _draw_hunter_marker(at: Vector2, cell: float, mark: Dictionary) -> void:
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
	draw_circle(at, maxf(1.5, cell * .55), Palette.ACCENT)
	var label := String(mark.get("name", "?")).substr(0, 1).to_upper()
	var font := ThemeDB.fallback_font
	var font_size := clampi(roundi(cell * .66), 7, 10)
	var glyph := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, at - glyph * .5 + Vector2(0, glyph.y * .5), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.BACKDROP)


func _draw_remote_player(at: Vector2, cell: float, mark: Dictionary) -> void:
	if mark.has("exit_direction"):
		_draw_floor_exit_marker(at, cell, String(mark.get("exit_direction", "up")),
			String(mark.get("name", "")))
		return
	var radius := maxf(2.0, cell * .48)
	draw_circle(at, radius + maxf(1.0, cell * .12), Color(0.01, 0.04, 0.05, .95))
	draw_circle(at, radius, COOP_PLAYER_BLUE)
	var facing: Vector2 = mark.get("facing", Vector2.UP)
	if facing.length_squared() > .01:
		draw_line(at, at + facing.normalized() * radius * 1.55,
			Color("d9fff9"), maxf(1.0, cell * .11), true)
	var label := String(mark.get("name", "P")).substr(0, 1).to_upper()
	var font := ThemeDB.fallback_font
	var font_size := clampi(roundi(cell * .62), 6, 10)
	var glyph := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, at - Vector2(glyph.x * .5, -glyph.y * .32), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.01, 0.04, 0.05))


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


func _draw_safe_room_status(at: Vector2, cell: float, mark: Dictionary) -> void:
	var breached := bool(mark.get("breached", false))
	var active := bool(mark.get("active", false))
	var tint := Palette.ALERT if breached else Palette.STABLE
	var radius := maxf(3.0, cell * .42)
	draw_circle(at, radius + maxf(1.0, cell * .10), Color(0.01, 0.04, 0.05, .94))
	draw_circle(at, radius, Color(tint, .26 if breached else .22))
	draw_circle(at, radius * .58, tint)
	if active and not breached:
		draw_line(at - Vector2(radius * .42, 0.0), at + Vector2(radius * .42, 0.0),
			Color(0.01, 0.04, 0.05), maxf(1.0, cell * .12), true)
		draw_line(at - Vector2(0.0, radius * .42), at + Vector2(0.0, radius * .42),
			Color(0.01, 0.04, 0.05), maxf(1.0, cell * .12), true)
	else:
		var font := ThemeDB.fallback_font
		var label := "X" if breached else "S"
		var font_size := clampi(roundi(cell * .58), 6, 10)
		var glyph := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, at - Vector2(glyph.x * .5, -glyph.y * .30), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.01, 0.04, 0.05))


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
	var reach := cell * 0.95
	draw_colored_polygon(PackedVector2Array([
		at + forward * reach,
		at - forward * reach * 0.5 + side * reach * 0.6,
		at - forward * reach * 0.5 - side * reach * 0.6,
	]), Palette.INK)
