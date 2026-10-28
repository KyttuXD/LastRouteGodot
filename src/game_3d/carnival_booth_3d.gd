class_name CarnivalBooth3D
extends Node3D

## One playable carnival booth in the world (docs/CARNIVAL_BOOTHS.md). It sits at its prop (a ring-toss stall, a strength tester ...), dresses it with a chase of bulbs round the roof, and while a game runs shows a pop-up
## GAME BOARD between the booth and the player: turning neck disc and rings, the tower with the puck and the bell. The player's CarnivalGame is local; the host only sees the start and the result.
## States: READY (bulbs chase), PLAYING_LOCAL (this player at the counter: movement locked, aim and fire / hold are the normal look and tool_use actions, so touch and XR work), PLAYING_REMOTE (another
## player's turn: the same board, idling), RESTING (the booth's cooldown: bulbs dim and red).

enum Mode { READY, PLAYING_LOCAL, PLAYING_REMOTE, RESTING }

const BULBS := 14
const BOARD_HEIGHT := 1.45
const CANCEL_KEY_DELAY := 0.5
const COLORS := [Color(1.0, 0.82, 0.35), Color(1.0, 0.35, 0.3), Color(0.4, 0.85, 1.0), Color(0.6, 1.0, 0.5), Color(1.0, 0.5, 0.9)]

var booth_id := ""
var prop_type := ""
var booth_size := Vector3(2.0, 2.4, 1.5)
var mode := Mode.READY
var game: CarnivalGame
var player: PlayerController3D
## seconds of cooldown left (the view feeds it from the world state); 0 = ready
var rest_resolver: Callable
## booth_id-scoped event out to the host: {"action": "finish"|"cancel", "booth_id", "booth_score", "elapsed"}
var reporter: Callable
## true in validators, which step the game by hand
var manual := false

var board: Node3D
var _bulbs: Array[MeshInstance3D] = []
var _bulb_mats: Array[StandardMaterial3D] = []
var _t := 0.0
var _flash := 0.0
var _flash_color := COLORS[0]
var _started_msec := 0
var _local_elapsed := 0.0
var _overlay: CanvasLayer
var _title: Label
var _line: Label
var _foot: Label
var _flying_nodes: Array[Node3D] = []
var _board_parts := {}
var _front := Vector3.FORWARD
var _occupant := 0
var _holding_player := false


func setup(id: String, type: String, size: Vector3) -> void:
	booth_id = id
	prop_type = type
	booth_size = size
	name = "Booth_%s" % type
	_build_bulbs()


func is_busy() -> bool:
	return mode == Mode.PLAYING_LOCAL or mode == Mode.PLAYING_REMOTE


func occupant_peer() -> int:
	return _occupant


## The interact prompt: the game's name, how long a resting booth has left, or that it is in use.
func prompt_text() -> String:
	var title := CarnivalBooths.title_for(prop_type)
	if is_busy():
		return "%s // IN USE" % title
	var left := rest_left()
	if left > 0.5:
		return "%s // BACK IN %d:%02d" % [title, int(left) / 60, int(left) % 60]
	return "PLAY %s" % title


func rest_left() -> float:
	return float(rest_resolver.call()) if rest_resolver.is_valid() else 0.0


# --- starting and ending ----------------------------------------------------------------------------------------------------------

## This player's turn.
func begin_local(player_node: PlayerController3D, seed_value: int) -> void:
	if is_busy():
		return
	player = player_node
	game = CarnivalBooths.make_game(prop_type, seed_value)
	if game == null:
		return
	mode = Mode.PLAYING_LOCAL
	_occupant = -1
	_local_elapsed = 0.0
	_started_msec = Time.get_ticks_msec()
	_face(player.global_position if _player_in_world() else global_position + Vector3.BACK)
	_build_board()
	if is_instance_valid(player):
		player.movement_locked = true
		_holding_player = true
	_build_overlay()
	_pop_board(true)
	Sound.carnival("start")
	_flash_for(0.4, COLORS[2])


## Another player's turn (or a replay on a late-loaded chunk): the board shows and idles.
func begin_remote(peer_id: int, seed_value: int, toward: Vector3 = Vector3.INF) -> void:
	if is_busy():
		return
	mode = Mode.PLAYING_REMOTE
	_occupant = peer_id
	game = CarnivalBooths.make_game(prop_type, seed_value)
	_face(toward if toward != Vector3.INF else global_position + Vector3.BACK)
	_build_board()
	_pop_board(true)
	Sound.carnival("start", 0.0, 0.6)


## The host's verdict: win (flash gold and ring) or lose (dim), then the board folds away and the booth rests.
func end_game(won: bool, booth_score: int = 0) -> void:
	var was_local := _holding_player
	_release_player()
	_destroy_overlay()
	mode = Mode.RESTING if rest_left() > 0.5 else Mode.READY
	_occupant = 0
	if won:
		_flash_for(2.2, COLORS[0])
		Sound.carnival("win", 0.0, 0.8 if not was_local else 1.0)
		if prop_type == "strengthTester":
			_ring_bell()
	else:
		_flash_for(0.8, COLORS[1])
		if was_local:
			Sound.carnival("lose")
	_pop_board(false)
	game = null


func _release_player() -> void:
	if _holding_player and is_instance_valid(player):
		player.movement_locked = false
	_holding_player = false


func cancel_local() -> void:
	if mode != Mode.PLAYING_LOCAL:
		return
	if reporter.is_valid():
		reporter.call({"action": "cancel", "booth_id": booth_id})
	else:
		end_game(false)


# --- the loop ---------------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	if mode == Mode.PLAYING_LOCAL and game != null and not manual:
		_read_input(delta)
	elif mode == Mode.PLAYING_REMOTE and game != null:
		_idle_board(delta)
	_animate_bulbs()
	if mode != Mode.PLAYING_LOCAL and mode != Mode.PLAYING_REMOTE:
		var resting := rest_left() > 0.5
		if resting and mode == Mode.READY:
			mode = Mode.RESTING
		elif not resting and mode == Mode.RESTING:
			mode = Mode.READY


## Real input for the local game: the camera ray into the board plane for the aim, tool_use for fire and hold, the move actions for the claw, interact to leave.
func _read_input(delta: float) -> void:
	if not is_instance_valid(player):
		cancel_local()
		return
	_local_elapsed += delta
	var cam := player.active_camera()
	if cam != null and board != null:
		var origin := cam.global_position
		var dir := -cam.global_transform.basis.z
		game.set_aim(plane_hit(origin, dir))
	var captured := MouseLock.is_captured()
	var pressed := Input.is_action_pressed("tool_use") and captured
	if Input.is_action_just_pressed("tool_use") and captured:
		game.fire()
	game.set_hold(pressed)
	game.set_move(Input.get_vector("move_left", "move_right", "move_up", "move_down"))
	if _local_elapsed > CANCEL_KEY_DELAY and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("pause")):
		cancel_local()
		return
	if player.global_position.distance_to(global_position) > CarnivalBooths.INTERACT_DISTANCE + 1.0:
		cancel_local()
		return
	step_game(delta)


## One tick of the local game and its presentation; the validators call this directly with a fixed dt.
func step_game(delta: float) -> void:
	if game == null:
		return
	game.step(delta)
	_present(game.take_events())
	_update_board()
	_update_overlay()
	if game.finished and mode == Mode.PLAYING_LOCAL:
		_report_finish()


func _report_finish() -> void:
	var event := {"action": "finish", "booth_id": booth_id, "booth_score": game.booth_score, "elapsed": maxf(game.elapsed, _local_elapsed)}
	mode = Mode.RESTING   # the host's answer ends the game; until then nothing more is read
	if reporter.is_valid():
		reporter.call(event)
	else:
		end_game(game.won(), game.booth_score)


## What an event of the game looks, sounds and costs: each kind plays its cue and the noise the booth's table says (CarnivalBooths.noise_for) on the local player, where the hunters hear it.
func _present(events: Array) -> void:
	for e in events:
		var kind := String(e["type"])
		match kind:
			"throw":
				Sound.carnival("throw")
				_launch_ring(e["at"])
			"ring_on":
				Sound.carnival("ring_on")
				_flash_for(0.3, COLORS[0])
				_rings_on_necks()
			"ring_miss":
				Sound.carnival("ring_miss")
			"windup":
				Sound.carnival("windup")
			"swing":
				Sound.carnival("swing")
			"thud":
				Sound.carnival("thud")
			"bell":
				Sound.carnival("bell")
				_ring_bell()
			_:
				Sound.carnival(kind)
		_make_noise(kind if kind != "bell" else "bell")


func _make_noise(kind: String) -> void:
	var n := CarnivalBooths.noise_for(prop_type, kind)
	if n.size() == 2 and is_instance_valid(player):
		player.emit_noise_burst(float(n[0]), float(n[1]))


# --- geometry ---------------------------------------------------------------------------------------------------------------------------

func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.metallic = 0.0
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow := 0.0, node_name := "Part") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color, glow)
	mi.position = pos
	mi.name = node_name
	parent.add_child(mi)
	return mi


func _build_bulbs() -> void:
	var hx := booth_size.x * 0.5
	var hz := booth_size.z * 0.5
	var perimeter := (hx + hz) * 4.0
	for i in BULBS:
		var d := perimeter * float(i) / float(BULBS)
		var p: Vector3
		var side := 2.0 * hx
		var depth := 2.0 * hz
		var y := booth_size.y + 0.06
		if d < side:
			p = Vector3(-hx + d, y, hz)
		elif d < side + depth:
			p = Vector3(hx, y, hz - (d - side))
		elif d < 2.0 * side + depth:
			p = Vector3(hx - (d - side - depth), y, -hz)
		else:
			p = Vector3(-hx, y, -hz + (d - 2.0 * side - depth))
		var bulb := _box(self, Vector3(0.12, 0.12, 0.12), p, COLORS[i % COLORS.size()], 1.0, "Bulb")
		_bulbs.append(bulb)
		_bulb_mats.append(bulb.material_override as StandardMaterial3D)


func _animate_bulbs() -> void:
	for i in _bulbs.size():
		var m := _bulb_mats[i]
		var c: Color = COLORS[i % COLORS.size()]
		var level := 1.0
		match mode:
			Mode.READY:
				level = 0.35 + 0.65 * maxf(0.0, sin(_t * 3.0 - float(i) * 0.7))
			Mode.PLAYING_LOCAL, Mode.PLAYING_REMOTE:
				level = 0.5 + 0.5 * (1.0 if int(_t * 8.0 + i) % 2 == 0 else 0.0)
			Mode.RESTING:
				c = Color(0.6, 0.12, 0.1)
				level = 0.18
		if _flash > 0.0:
			c = _flash_color
			level = 0.4 + 0.6 * (1.0 if int(_t * 14.0 + i) % 2 == 0 else 0.0)
		m.emission = c
		m.albedo_color = c * (0.35 + 0.65 * level)
		m.emission_energy_multiplier = 0.2 + 1.6 * level


func _flash_for(seconds: float, color: Color) -> void:
	_flash = seconds
	_flash_color = color


## Turn the board to face `toward` (horizontally) and place it between the booth and that point.
func _face(toward: Vector3) -> void:
	var flat := Vector3(toward.x - global_position.x, 0.0, toward.z - global_position.z)
	if flat.length() < 0.2:
		flat = Vector3.BACK
	_front = flat.normalized()


func _build_board() -> void:
	if board != null:
		board.queue_free()
	board = Node3D.new()
	board.name = "GameBoard"
	_board_parts.clear()
	_flying_nodes.clear()
	add_child(board)
	var dist := clampf(_distance_to_front() * 0.55, 0.9, 1.8)
	board.global_position = global_position + _front * dist
	board.look_at(board.global_position - _front, Vector3.UP)   # -Z points away from the player, so +Z (the front) faces the player
	board.scale = Vector3.ZERO
	match CarnivalBooths.game_for(prop_type):
		"ring_toss":
			_build_ring_toss_board()
		"strength":
			_build_strength_board()
		"claw":
			_build_claw_board()
		"shooting":
			_build_shooting_board()
		"mole":
			_build_mole_board()
		"duck":
			_build_duck_board()


func _player_in_world() -> bool:
	return is_instance_valid(player) and player.is_inside_tree()


func _distance_to_front() -> float:
	if mode == Mode.PLAYING_LOCAL and _player_in_world():
		return Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	return 2.6


## The plane the aim lives on: the board's, through the game's centre. Returns metres (u right, v up) from that centre.
func plane_hit(origin: Vector3, dir: Vector3) -> Vector2:
	if board == null:
		return Vector2.ZERO
	var normal := board.global_transform.basis.z
	var denom := normal.dot(dir)
	if absf(denom) < 0.0001:
		return Vector2.ZERO
	var t := normal.dot(board.global_position - origin) / denom
	if t < 0.0:
		return Vector2.ZERO
	var hit := origin + dir * t
	var local := board.to_local(hit)
	return Vector2(local.x, local.y - _board_center_height()) / maxf(board.scale.x, 0.001)


func _board_center_height() -> float:
	match CarnivalBooths.game_for(prop_type):
		"ring_toss":
			return BOARD_HEIGHT
		"shooting", "mole", "duck":
			return PANEL_CENTER
	return 1.1


func _pop_board(show: bool) -> void:
	if board == null:
		return
	var tween := create_tween()
	if show:
		tween.tween_property(board, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		var b := board
		tween.tween_property(b, "scale", Vector3.ZERO, 0.4).set_delay(1.8 if mode != Mode.PLAYING_LOCAL else 0.0)
		tween.tween_callback(func():
			if is_instance_valid(b):
				b.queue_free()
			if board == b:
				board = null)


# --- ring toss board --------------------------------------------------------------------------------------------------------------------

func _build_ring_toss_board() -> void:
	var post := _box(board, Vector3(0.1, BOARD_HEIGHT, 0.1), Vector3(0, BOARD_HEIGHT * 0.5, -0.05), Color(0.35, 0.22, 0.14), 0.0, "Post")
	var disc := Node3D.new()
	disc.name = "Disc"
	disc.position = Vector3(0, BOARD_HEIGHT, 0)
	board.add_child(disc)
	_board_parts["disc"] = disc
	var plate := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RingTossGame.DISC_RADIUS
	cyl.bottom_radius = RingTossGame.DISC_RADIUS
	cyl.height = 0.06
	plate.mesh = cyl
	plate.material_override = _mat(Color(0.75, 0.2, 0.22))
	plate.rotation.x = PI * 0.5
	disc.add_child(plate)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = RingTossGame.DISC_RADIUS - 0.03
	rim_mesh.outer_radius = RingTossGame.DISC_RADIUS + 0.03
	rim.mesh = rim_mesh
	rim.material_override = _mat(Color(1.0, 0.85, 0.35), 0.8)
	rim.rotation.x = PI * 0.5
	disc.add_child(rim)
	var necks := []
	for i in RingTossGame.NECKS:
		var holder := Node3D.new()
		var p := Vector2(cos(float(i) * TAU / RingTossGame.NECKS), sin(float(i) * TAU / RingTossGame.NECKS)) * RingTossGame.DISC_RADIUS * 0.72
		holder.position = Vector3(p.x, p.y, 0.0)
		disc.add_child(holder)
		_box(holder, Vector3(0.09, 0.09, 0.22), Vector3(0, 0, 0.12), Color(0.55, 0.9, 0.95), 0.4, "Neck")
		necks.append(holder)
	_board_parts["necks"] = necks


func _torus(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.7
	tm.outer_radius = radius
	mi.mesh = tm
	mi.material_override = _mat(color, 0.5)
	return mi


func _launch_ring(plane_point: Vector2) -> void:
	if board == null:
		return
	var ring := _torus(0.1, Color(1.0, 0.85, 0.2))
	ring.rotation.x = PI * 0.5
	board.add_child(ring)
	var from := Vector3(plane_point.x * 0.3, BOARD_HEIGHT - 0.55, 1.1)
	var to := Vector3(plane_point.x, plane_point.y + BOARD_HEIGHT, 0.1)
	ring.position = from
	var tween := create_tween()
	tween.tween_method(func(k: float):
		if is_instance_valid(ring):
			ring.position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 0.3, 0), 0.0, 1.0, RingTossGame.FLIGHT)
	tween.tween_callback(func():
		if is_instance_valid(ring):
			ring.queue_free())


func _rings_on_necks() -> void:
	if board == null or game == null or not game is RingTossGame:
		return
	var disc := _board_parts.get("disc") as Node3D
	var necks: Array = _board_parts.get("necks", [])
	var on: Array = (game as RingTossGame).on_necks.keys()
	for i in on:
		var holder := necks[int(i)] as Node3D
		if holder != null and holder.get_node_or_null("Ring") == null:
			var ring := _torus(0.1, Color(1.0, 0.85, 0.2))
			ring.name = "Ring"
			ring.position = Vector3(0, 0, 0.06)
			holder.add_child(ring)


# --- strength board ---------------------------------------------------------------------------------------------------------------------

const TOWER_HEIGHT := 2.2


func _build_strength_board() -> void:
	_box(board, Vector3(0.7, 0.2, 0.5), Vector3(0, 0.1, 0), Color(0.45, 0.3, 0.2), 0.0, "Base")
	_box(board, Vector3(0.22, TOWER_HEIGHT, 0.12), Vector3(0, 0.2 + TOWER_HEIGHT * 0.5, 0), Color(0.15, 0.15, 0.2), 0.0, "Tower")
	for i in 11:
		var lit := _box(board, Vector3(0.3, 0.05, 0.14), Vector3(0, 0.3 + float(i) * (TOWER_HEIGHT - 0.2) / 10.0, 0.01), COLORS[i % 5], 0.8, "Mark")
		lit.set_meta("level", float(i) / 10.0)
	_board_parts["puck"] = _box(board, Vector3(0.18, 0.14, 0.2), Vector3(0, 0.3, 0.12), Color(1.0, 0.25, 0.2), 0.8, "Puck")
	var bell := Node3D.new()
	bell.name = "BellPivot"
	bell.position = Vector3(0, 0.2 + TOWER_HEIGHT + 0.1, 0)
	board.add_child(bell)
	_box(bell, Vector3(0.3, 0.24, 0.3), Vector3(0, 0, 0), Color(1.0, 0.85, 0.3), 0.6, "Bell")
	_box(bell, Vector3(0.08, 0.08, 0.08), Vector3(0, -0.15, 0), Color(0.9, 0.9, 0.9), 0.3, "Clapper")
	_board_parts["bell"] = bell
	_board_parts["meter"] = _box(board, Vector3(0.1, 0.05, 0.1), Vector3(0.45, 0.3, 0), Color(0.3, 1.0, 0.4), 1.0, "Meter")


func _ring_bell() -> void:
	var bell := _board_parts.get("bell") as Node3D
	if bell == null or not is_instance_valid(bell):
		return
	var tween := create_tween()
	for i in 6:
		tween.tween_property(bell, "rotation:z", (0.5 if i % 2 == 0 else -0.5) * (1.0 - float(i) / 7.0), 0.12)
	tween.tween_property(bell, "rotation:z", 0.0, 0.1)


# --- the wall games (shooting gallery, whack-a-mole, duck pond) and the claw machine ---------------------------------------------------

const PANEL_CENTER := 1.3


func _panel(size: Vector2, color: Color) -> void:
	_box(board, Vector3(size.x, size.y, 0.06), Vector3(0, PANEL_CENTER, -0.03), color, 0.0, "Panel")
	_box(board, Vector3(size.x + 0.12, 0.08, 0.12), Vector3(0, PANEL_CENTER + size.y * 0.5 + 0.04, 0), Color(1.0, 0.8, 0.3), 0.7, "Header")
	_box(board, Vector3(0.1, PANEL_CENTER - size.y * 0.5, 0.1), Vector3(-size.x * 0.5, (PANEL_CENTER - size.y * 0.5) * 0.5, -0.05), Color(0.3, 0.2, 0.15), 0.0, "Leg")
	_box(board, Vector3(0.1, PANEL_CENTER - size.y * 0.5, 0.1), Vector3(size.x * 0.5, (PANEL_CENTER - size.y * 0.5) * 0.5, -0.05), Color(0.3, 0.2, 0.15), 0.0, "Leg")


func _build_shooting_board() -> void:
	_panel(Vector2(1.9, 1.3), Color(0.12, 0.14, 0.3))
	var pivots := []
	var g := game as ShootingGame
	for t in g.targets:
		var pivot := Node3D.new()
		pivot.position = Vector3((t["at"] as Vector2).x, PANEL_CENTER + (t["at"] as Vector2).y - 0.15, 0.04)
		board.add_child(pivot)
		_box(pivot, Vector3(0.26, 0.26, 0.03), Vector3(0, 0.13, 0), Color(0.95, 0.9, 0.85), 0.2, "Target")
		_box(pivot, Vector3(0.14, 0.14, 0.035), Vector3(0, 0.13, 0.005), Color(0.9, 0.2, 0.2), 0.5, "Bull")
		pivot.rotation.x = -PI * 0.5
		pivots.append(pivot)
	_board_parts["pivots"] = pivots


func _build_mole_board() -> void:
	_panel(Vector2(1.7, 1.2), Color(0.3, 0.22, 0.12))
	var g := game as MoleGame
	var moles := []
	for h in g.holes:
		_box(board, Vector3(0.34, 0.34, 0.02), Vector3((h as Vector2).x, PANEL_CENTER + (h as Vector2).y, 0.005), Color(0.04, 0.03, 0.03), 0.0, "Hole")
		var mole := _box(board, Vector3(0.24, 0.26, 0.16), Vector3((h as Vector2).x, PANEL_CENTER + (h as Vector2).y, -0.12), Color(0.5, 0.33, 0.2), 0.3, "Mole")
		_box(mole, Vector3(0.06, 0.06, 0.03), Vector3(0, 0.04, 0.09), Color(0.95, 0.5, 0.5), 0.4, "Nose")
		moles.append(mole)
	_board_parts["moles"] = moles


func _build_duck_board() -> void:
	_panel(Vector2(1.8, 0.9), Color(0.1, 0.35, 0.5))
	var g := game as DuckGame
	var ducks := []
	for i in g.ducks.size():
		var duck := _box(board, Vector3(0.2, 0.14, 0.12), Vector3(0, PANEL_CENTER, 0.08), Color(1.0, 0.85, 0.2), 0.5, "Duck")
		_box(duck, Vector3(0.1, 0.1, 0.1), Vector3(0.09, 0.09, 0), Color(1.0, 0.85, 0.2), 0.5, "Head")
		_box(duck, Vector3(0.05, 0.03, 0.04), Vector3(0.16, 0.08, 0), Color(1.0, 0.5, 0.1), 0.4, "Beak")
		ducks.append(duck)
	_board_parts["ducks"] = ducks
	_board_parts["marker"] = _box(board, Vector3(0.1, 0.1, 0.1), Vector3(0, PANEL_CENTER + 0.3, 0.1), Color(1.0, 0.2, 0.25), 1.2, "Marker")


func _build_claw_board() -> void:
	# a glass-fronted cabinet seen from the front: x across, the claw running on a top rail, prizes on the floor
	for sx in [-0.62, 0.62]:
		for sz in [-0.4, 0.4]:
			_box(board, Vector3(0.05, 1.7, 0.05), Vector3(sx, 0.85, sz), Color(0.8, 0.2, 0.5), 0.5, "Post")
	_box(board, Vector3(1.34, 0.08, 0.9), Vector3(0, 1.74, 0), Color(0.9, 0.3, 0.6), 0.6, "Roof")
	_box(board, Vector3(1.34, 0.3, 0.9), Vector3(0, 0.15, 0), Color(0.25, 0.1, 0.2), 0.0, "Base")
	var gantry := Node3D.new()
	gantry.position = Vector3(0, 1.65, 0)
	board.add_child(gantry)
	_box(gantry, Vector3(1.2, 0.05, 0.05), Vector3(0, 0, 0), Color(0.7, 0.7, 0.75), 0.3, "Rail")
	var carriage := Node3D.new()
	gantry.add_child(carriage)
	_box(carriage, Vector3(0.14, 0.1, 0.14), Vector3(0, 0, 0), Color(0.9, 0.9, 0.9), 0.4, "Carriage")
	var cable := _box(carriage, Vector3(0.02, 1.0, 0.02), Vector3(0, -0.5, 0), Color(0.6, 0.6, 0.6), 0.2, "Cable")
	var claw := Node3D.new()
	carriage.add_child(claw)
	for sx in [-1.0, 1.0]:
		_box(claw, Vector3(0.03, 0.2, 0.03), Vector3(sx * 0.07, -0.1, 0), Color(0.85, 0.85, 0.9), 0.3, "Prong")
	_board_parts["gantry"] = gantry
	_board_parts["carriage"] = carriage
	_board_parts["claw"] = claw
	_board_parts["cable"] = cable
	var prizes := []
	for p in (game as ClawGame).prizes:
		var prize := _box(board, Vector3(0.16, 0.16, 0.16), Vector3((p["at"] as Vector2).x * 1.2, 0.38, (p["at"] as Vector2).y * 0.8), COLORS[prizes.size() % 5], 0.5, "Prize")
		prizes.append(prize)
	_board_parts["prizes"] = prizes


# --- drawing the game state -------------------------------------------------------------------------------------------------------------

func _update_board() -> void:
	if board == null or game == null:
		return
	var st := game.state()
	if game is RingTossGame:
		var disc := _board_parts.get("disc") as Node3D
		if disc != null:
			disc.rotation.z = float(st["angle"])
	elif game is ShootingGame:
		var pivots: Array = _board_parts.get("pivots", [])
		for i in mini(pivots.size(), (game as ShootingGame).targets.size()):
			var up := bool((game as ShootingGame).targets[i]["up"])
			var pv := pivots[i] as Node3D
			pv.rotation.x = lerpf(pv.rotation.x, 0.0 if up else -PI * 0.5, 0.35)
	elif game is MoleGame:
		var moles: Array = _board_parts.get("moles", [])
		var up_map: Dictionary = (game as MoleGame).up
		for i in moles.size():
			var m := moles[i] as Node3D
			var lift := 0.17 if up_map.has(i) else 0.0
			m.position.z = lerpf(m.position.z, -0.12 + lift, 0.4)
	elif game is DuckGame:
		var dg := game as DuckGame
		var ducks: Array = _board_parts.get("ducks", [])
		for i in ducks.size():
			var p := dg.duck_position(i)
			var d := ducks[i] as Node3D
			d.position = Vector3(p.x, PANEL_CENTER + p.y, 0.08)
			d.scale.x = 1.0 if int(dg.ducks[i] / TAU * 2.0) % 2 == 0 else -1.0
		var marker := _board_parts.get("marker") as Node3D
		if marker != null:
			var mp := dg.duck_position(dg.marked)
			marker.position = Vector3(mp.x, PANEL_CENTER + mp.y + 0.18 + sin(_t * 6.0) * 0.03, 0.1)
	elif game is ClawGame:
		var cg := game as ClawGame
		var carriage := _board_parts.get("carriage") as Node3D
		var gantry := _board_parts.get("gantry") as Node3D
		var claw := _board_parts.get("claw") as Node3D
		var cable := _board_parts.get("cable") as MeshInstance3D
		if gantry != null:
			gantry.position.z = cg.pos.y * 0.8
		if carriage != null:
			carriage.position.x = cg.pos.x * 1.2
		var drop := (1.0 - cg.claw_height()) * 1.0
		if claw != null:
			claw.position.y = -0.5 - drop
		if cable != null:
			cable.mesh.size.y = 1.0 + drop
			cable.position.y = -(1.0 + drop) * 0.5 + 0.0
			claw.position.y = -(1.0 + drop)
		var prizes: Array = _board_parts.get("prizes", [])
		for i in prizes.size():
			var pr := prizes[i] as Node3D
			pr.visible = not bool(cg.prizes[i]["gone"]) and not (cg.carried == i and cg.phase == "up")
			if cg.carried == i and cg.phase == "up":
				pr.visible = true
				pr.position = Vector3(cg.pos.x * 1.2, 1.65 - (1.0 + drop) - 0.2, cg.pos.y * 0.8)   # hangs from the prongs
	elif game is StrengthGame:
		var puck := _board_parts.get("puck") as Node3D
		var meter := _board_parts.get("meter") as MeshInstance3D
		if puck != null:
			puck.position.y = 0.3 + float(st["puck"]) * (TOWER_HEIGHT - 0.2)
		if meter != null:
			var m := float(st["meter"])
			meter.scale.y = 0.2 + m * 40.0
			meter.position.y = 0.3 + m * (TOWER_HEIGHT - 0.2) * 0.5


## A remote player's board idles: the disc keeps turning, the meter sweeps.
func _idle_board(delta: float) -> void:
	if game == null:
		return
	if game is RingTossGame:
		(game as RingTossGame).angle += RingTossGame.TURN_SPEED * delta
	elif game is StrengthGame:
		var g := game as StrengthGame
		g.meter = 0.5 + 0.5 * sin(_t * 3.0)
	elif not game.finished:
		game.step(delta)
		game.take_events()
	_update_board()


# --- overlay ----------------------------------------------------------------------------------------------------------------------------

func _build_overlay() -> void:
	_destroy_overlay()
	_overlay = CanvasLayer.new()
	_overlay.name = "BoothOverlay"
	_overlay.layer = 25
	add_child(_overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)
	_title = _label(root, 10, Color(1.0, 0.85, 0.35))
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.offset_top = 26
	_line = _label(root, 7, Color(0.95, 0.93, 0.88))
	_line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_line.offset_top = 42
	_foot = _label(root, 6, Color(0.7, 0.68, 0.62))
	_foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_foot.offset_bottom = -34
	_foot.text = "LEAVE: E / ESC"
	_title.text = CarnivalBooths.title_for(prop_type)


func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _update_overlay() -> void:
	if _overlay == null or game == null:
		return
	_title.text = "%s    %d:%02d" % [CarnivalBooths.title_for(prop_type), int(game.time_left()) / 60, int(game.time_left()) % 60]
	_line.text = game.prompt()


func _destroy_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func _exit_tree() -> void:
	_release_player()
