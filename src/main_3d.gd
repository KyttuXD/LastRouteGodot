extends Node

## 3D counterpart to src/main.gd — same GameState-driven floor lifecycle and
## HUD wiring, orchestrating the 3D presentation layer instead of the 2D one.
## Also owns the hunter lifecycle: spawn/activation/per-frame brain update
## and the capture -> escape struggle -> success/respawn/game-over flow
## (hunter_brain.gd is pure simulation; this is where its results turn into
## game state, matching how game.js's update() drives hunter-ai.js).

var pause_menu: PauseMenu

@onready var world: Node3D = %World
@onready var facility_view: FacilityView3D = %FacilityView
@onready var player: PlayerController3D = %Player
@onready var hud: HUD = %HUD

var observed_depth := 1
## Every hunter on the floor. Usually one drawn route hunter, plus any
## rule-summoned special that has woken (Nyxie on darkness, Solyth on heat) —
## the original runs those *alongside* the ordinary hunter, not instead of it.
var hunter_views: Array[HunterView3D] = []
## The route hunter specifically, kept separate because only she follows the
## relay activation schedule.
var hunter_view: HunterView3D
## Whoever actually grabbed the player, so the escape struggle resolves
## against the right hunter rather than always the route one.
var capturing_view: HunterView3D
var _game_over_timer := 0.0
var _remotes: RemotePlayers
## Rebuilt each frame on the host and sent as-is; empty on a client, which
## never fills it because it never runs a brain.
var _hunter_report: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.start_new_run()
	observed_depth = GameState.depth
	player.interaction_message.connect(_on_interaction_message)
	# Last Route taps ESC: it is a co-op mode, so pausing has to be quick.
	pause_menu = PauseMenu.new()
	pause_menu.abandon_label = "ABANDON ROUTE"
	pause_menu.abandoned.connect(_on_abandoned)
	add_child(pause_menu)
	# Other players' bodies. Present offline too, doing nothing, so there is no
	# second code path for a solo run.
	_remotes = RemotePlayers.new()
	_remotes.name = "RemotePlayers"
	_remotes.local_player = player
	_remotes.hunters_received.connect(_apply_hunters)
	world.add_child(_remotes)
	_build_admin()
	_build_floor()
	_update_hud()


func _process(delta: float) -> void:
	if GameState.game_over:
		_handle_game_over_tick(delta)
		return

	# Being held by a hunter is the one moment pausing would be an exploit, so
	# the menu is locked out for the length of the struggle.
	pause_menu.tap_to_pause = not GameState.escape_active
	if Input.is_action_just_pressed("toggle_map") and not GameState.escape_active:
		hud.toggle_map_overlay()

	if get_tree().paused:
		return

	GameState.tick_escape_cooldowns(delta)

	if GameState.escape_active:
		_update_escape_struggle(delta)
	else:
		_update_gameplay(delta)

	if _remotes != null:
		_remotes.broadcast_hunters(_hunter_report)
	if GameState.depth != observed_depth:
		observed_depth = GameState.depth
		_build_floor()

	hud.set_interaction_prompt(player.get_interaction_prompt())
	_update_hud()


func _update_gameplay(delta: float) -> void:
	var generator := facility_view.generator

	# Only the drawn route hunter follows the relay schedule; the specials
	# below wake on their own rules instead.
	if hunter_view and not hunter_view.brain.active:
		var activation_relay: int = mini(GameConfig.HUNTER_ACTIVATION_SPACING, generator.relay_count)
		if GameState.relays_collected >= activation_relay:
			hunter_view.brain.activate_at(player.grid_position())

	var target := {
		"position": player.grid_position(),
		"hidden": false,
		"in_safe_zone": player.is_in_safe_zone(),
		"noise": player.noise,
		"flashlight_on": player.flashlight_enabled,
		# Actually moving under sprint, not merely holding the key — the
		# original gates on `sprinting && travelSpeed > .1` (Eirys).
		"sprinting": player.movement_mode == "sprint" and player.noise > 0.0,
		# For beam-aim checks (Nyxie's dispel).
		"facing": player.facing,
		"lamp_charge": player.lamp_charge,
		"meters": player.meters,
		# Wynelle reads the heater station's two distinct states: merely
		# thawed dematerialises her, powered holds her off entirely.
		"heater_unfrozen": _heater_state() != RouteInteractable3D.HeaterState.FROZEN,
		"heater_powered": _heater_state() == RouteInteractable3D.HeaterState.POWERED,
	}

	# Only the host thinks for the hunters. A client that ran the same brains
	# would run them against ITS player, so each window would be chased by a
	# hunter the others cannot see.
	if not _remotes.simulates():
		return

	_hunter_report.clear()
	for view in hunter_views:
		var captured: bool = view.brain.update(delta, generator, target, GameState.depth, GameState.relays_collected)
		view.sync_from_brain()
		_hunter_report.append({"id": view.name, "at": view.global_position,
			"facing": view.rotation.y, "active": view.brain.active})
		# Wynelle's freeze grace is a second way to lose that isn't a grab:
		# if it runs out you die where you stand, with no struggle.
		if view.brain.gimmick is WynelleGimmick and view.brain.gimmick.has_frozen_player():
			capturing_view = view
			_resolve_capture_outcome()
			return
		if captured:
			_trigger_capture(view)
			return


func _heater_state() -> RouteInteractable3D.HeaterState:
	var station := facility_view.heater_station
	return station.heater_state if station else RouteInteractable3D.HeaterState.FROZEN


func _trigger_capture(view: HunterView3D) -> void:
	if GameState.is_capture_immune():
		return
	capturing_view = view
	# Some captures skip the struggle entirely — a cooldown-gated grab, or a
	# hunter whose gimmick declares the grab inescapable (Nyxie's dead-lamp
	# wake). Both go straight to the outcome, matching triggerGameOver().
	if GameState.escape_on_cooldown() or (view.brain.gimmick and view.brain.gimmick.capture_is_inescapable()):
		_resolve_capture_outcome()
		return
	player.input_frozen = true
	GameState.begin_escape(view.brain.hunter_id)


func _update_escape_struggle(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		GameState.register_escape_press()
	GameState.escape_remaining = maxf(0.0, GameState.escape_remaining - delta)

	if GameState.escape_progress >= GameState.escape_required:
		_resolve_escape_success()
	elif GameState.escape_remaining <= 0.0:
		_resolve_capture_outcome()


func _resolve_escape_success() -> void:
	GameState.resolve_escape_success()

	var hunter_pos: Vector2 = capturing_view.brain.position if capturing_view else player.grid_position()
	var player_pos := player.grid_position()
	var away := player_pos - hunter_pos
	if away.length() < 0.01:
		away = Vector2(1, 0)
	var knockback_target := player_pos + away.normalized() * 1.45
	var generator := facility_view.generator
	var open := generator.nearest_open_position(knockback_target.x, knockback_target.y, GameConfig.PLAYER_RADIUS)
	var new_pos: Vector2 = Vector2(open["x"], open["y"]) if not open.is_empty() else player_pos

	player.global_position = Vector3(new_pos.x, player.global_position.y, new_pos.y)
	player.input_frozen = false

	if capturing_view:
		capturing_view.brain.enter_search_from(new_pos, 1.8)
		capturing_view.brain.apply_stun(GameConfig.ESCAPE_STUN_DURATION)
		capturing_view.sync_from_brain()

	hud.show_message("You broke free!")


## Shared by both a failed struggle and the no-struggle-at-all cooldown skip
## (hunter-ai.js's triggerGameOver: Nyxie/cooldown captures go straight
## here, everyone else only arrives via a timed-out struggle).
func _resolve_capture_outcome() -> void:
	var continues := GameState.resolve_escape_failure()
	if continues:
		_respawn_after_capture()
	else:
		_enter_game_over()


func _respawn_after_capture() -> void:
	player.position = facility_view.start_world_position()
	player.velocity = Vector3.ZERO
	player.input_frozen = false
	for view in hunter_views:
		view.brain.calm_reset(GameConfig.RESPAWN_STUN_DURATION)
		view.sync_from_brain()
	hud.show_message("Caught! Respawned at the start.")


func _enter_game_over() -> void:
	player.input_frozen = true
	hud.show_message("GAME OVER")
	_game_over_timer = 0.0


## No game-over screen yet (out of scope for this milestone) — auto-restarts
## a fresh run after a short beat so the game doesn't just dead-end.
func _handle_game_over_tick(delta: float) -> void:
	_game_over_timer += delta
	if _game_over_timer < 3.0:
		return
	GameState.start_new_run()
	observed_depth = GameState.depth
	_build_floor()
	_update_hud()


func _update_hud() -> void:
	hud.update_objective(GameState.depth, GameState.relays_collected, GameState.relay_target, GameState.lives_remaining)
	hud.update_battery(player.lamp_charge, player.flashlight_enabled, player.is_in_safe_zone(), player.movement_mode)
	hud.update_stamina(player.stamina, player.exhausted)
	hud.update_meters(player.meters)
	hud.set_escape_active(GameState.escape_active)
	if GameState.escape_active:
		hud.update_escape(GameState.escape_progress, GameState.escape_required, GameState.escape_remaining, GameState.escape_duration)


## Returns null outside a debug build, so nothing here exists in a release.
func _build_admin() -> void:
	AdminMenu.attach(self,
		func() -> String:
			return "ROOM %s  %s\nDEPTH %d  RELAYS %d/%d  LIVES %d\nSEED %s" % [
				RoomState.code, RoomState.SCALE_LABELS[RoomState.map_scale],
				GameState.depth, GameState.relays_collected,
				GameState.relay_target, GameState.lives_remaining,
				RoomState.seed_text],
		[
			{"label": "GRANT RELAY", "action": func() -> void:
				GameState.relays_collected = mini(GameState.relay_target,
					GameState.relays_collected + 1)},
			{"label": "ALL RELAYS", "action": func() -> void:
				GameState.relays_collected = GameState.relay_target},
			{"label": "FULL LAMP", "action": func() -> void:
				player.restore_lamp(GameConfig.MAX_LAMP_CHARGE)},
			{"label": "REBUILD FLOOR", "action": _build_floor},
			{"label": "DESCEND", "action": func() -> void: GameState.descend()},
		])


## Put the host's hunters where the host says they are.
##
## Position only. The brains, the capture and the gimmicks all stay on the
## host -- this is the smallest thing that makes every window agree about where
## a hunter is standing, which is what has to be true before anything about a
## shared chase is worth writing.
func _apply_hunters(data: Array) -> void:
	for entry in data:
		for view in hunter_views:
			if String(view.name) != String(entry["id"]):
				continue
			view.global_position = entry["at"]
			view.rotation.y = entry["facing"]
			break


func _on_abandoned() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_interaction_message(message: String) -> void:
	hud.show_message(message)


func _build_floor() -> void:
	facility_view.generate_floor(GameState.level_seed_text())
	GameState.relay_target = facility_view.generator.relay_count
	player.position = facility_view.start_world_position()
	player.velocity = Vector3.ZERO
	player.input_frozen = false
	_spawn_hunter()


func _spawn_hunter() -> void:
	for view in hunter_views:
		view.queue_free()
	hunter_views.clear()
	hunter_view = null
	capturing_view = null

	var generator := facility_view.generator
	var from_start := generator.distance_map(generator.start.x, generator.start.y)
	var spawn_cell := generator.place_hunter_spawn(from_start)
	var spawn_pos := Vector2(spawn_cell) + Vector2(0.5, 0.5)
	var seed_text := GameState.level_seed_text()

	# The drawn route hunter, on the relay activation schedule.
	hunter_view = _add_hunter(HunterRoster.pick_for_floor(seed_text, GameState.depth), spawn_pos, "%s:HUNTER" % seed_text)

	# Rule-summoned specials are always PRESENT but inert, exactly as in the
	# original — they wake on their own condition (darkness, heat) rather than
	# the relay count, and hunt alongside the route hunter rather than
	# replacing her.
	for special_id in HunterRoster.SPECIAL_IDS:
		_add_hunter(special_id, spawn_pos, "%s:%s" % [seed_text, special_id.to_upper()])


func _add_hunter(hunter_id: String, spawn_pos: Vector2, seed_text: String) -> HunterView3D:
	var view := HunterView3D.new()
	view.brain = HunterBrain.new(spawn_pos, seed_text, hunter_id)
	world.add_child(view)
	view.sync_from_brain()
	hunter_views.append(view)
	return view
