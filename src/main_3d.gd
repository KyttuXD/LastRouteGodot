extends Node

## 3D counterpart to src/main.gd — same GameState-driven floor lifecycle and
## HUD wiring, orchestrating the 3D presentation layer instead of the 2D one.
## Also owns the hunter lifecycle: spawn/activation/per-frame brain update
## and the capture -> escape struggle -> success/respawn/game-over flow
## (hunter_brain.gd is pure simulation; this is where its results turn into
## game state, matching how game.js's update() drives hunter-ai.js).

@onready var world: Node3D = %World
@onready var facility_view: FacilityView3D = %FacilityView
@onready var player: PlayerController3D = %Player
@onready var hud: HUD = %HUD

var observed_depth := 1
var hunter_view: HunterView3D
var _game_over_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.start_new_run()
	observed_depth = GameState.depth
	player.interaction_message.connect(_on_interaction_message)
	_build_floor()
	_update_hud()


func _process(delta: float) -> void:
	if GameState.game_over:
		_handle_game_over_tick(delta)
		return

	if Input.is_action_just_pressed("pause") and not GameState.escape_active:
		get_tree().paused = not get_tree().paused
		hud.set_paused(get_tree().paused)
	if Input.is_action_just_pressed("toggle_map") and not GameState.escape_active:
		hud.toggle_map_overlay()

	if get_tree().paused:
		return

	GameState.tick_escape_cooldowns(delta)

	if GameState.escape_active:
		_update_escape_struggle(delta)
	else:
		_update_gameplay(delta)

	if GameState.depth != observed_depth:
		observed_depth = GameState.depth
		_build_floor()

	hud.set_interaction_prompt(player.get_interaction_prompt())
	_update_hud()


func _update_gameplay(delta: float) -> void:
	if hunter_view == null:
		return
	var generator := facility_view.generator
	var activation_relay: int = mini(GameConfig.HUNTER_ACTIVATION_SPACING, generator.relay_count)
	if not hunter_view.brain.active and GameState.relays_collected >= activation_relay:
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
	}
	var captured: bool = hunter_view.brain.update(delta, generator, target, GameState.depth, GameState.relays_collected)
	hunter_view.sync_from_brain()

	if captured:
		_trigger_capture()


func _trigger_capture() -> void:
	if GameState.is_capture_immune():
		return
	if GameState.escape_on_cooldown():
		_resolve_capture_outcome()
		return
	player.input_frozen = true
	GameState.begin_escape(hunter_view.brain.hunter_id)


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

	var hunter_pos: Vector2 = hunter_view.brain.position
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

	hunter_view.brain.enter_search_from(new_pos, 1.8)
	hunter_view.brain.apply_stun(GameConfig.ESCAPE_STUN_DURATION)
	hunter_view.sync_from_brain()

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
	hunter_view.brain.calm_reset(GameConfig.RESPAWN_STUN_DURATION)
	hunter_view.sync_from_brain()
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
	hud.set_escape_active(GameState.escape_active)
	if GameState.escape_active:
		hud.update_escape(GameState.escape_progress, GameState.escape_required, GameState.escape_remaining, GameState.escape_duration)


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
	if hunter_view != null:
		hunter_view.queue_free()
		hunter_view = null

	var generator := facility_view.generator
	var from_start := generator.distance_map(generator.start.x, generator.start.y)
	var spawn_cell := generator.place_hunter_spawn(from_start)
	var spawn_pos := Vector2(spawn_cell) + Vector2(0.5, 0.5)

	var hunter_id := HunterRoster.pick_for_floor(GameState.level_seed_text(), GameState.depth)
	var brain := HunterBrain.new(spawn_pos, "%s:HUNTER" % GameState.level_seed_text(), hunter_id)
	hunter_view = HunterView3D.new()
	hunter_view.brain = brain
	world.add_child(hunter_view)
	hunter_view.sync_from_brain()
