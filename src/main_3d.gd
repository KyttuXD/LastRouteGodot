extends Node

## 3D counterpart to src/main.gd — same GameState-driven floor lifecycle and
## HUD wiring, orchestrating the 3D presentation layer instead of the 2D one.

@onready var facility_view: FacilityView3D = %FacilityView
@onready var player: PlayerController3D = %Player
@onready var hud: HUD = %HUD

var observed_depth := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.start_new_run()
	observed_depth = GameState.depth
	player.interaction_message.connect(_on_interaction_message)
	_build_floor()
	_update_hud()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		get_tree().paused = not get_tree().paused
		hud.set_paused(get_tree().paused)
	if Input.is_action_just_pressed("toggle_map"):
		hud.toggle_map_overlay()

	if GameState.depth != observed_depth:
		observed_depth = GameState.depth
		_build_floor()

	hud.set_interaction_prompt(player.get_interaction_prompt())
	_update_hud()


func _update_hud() -> void:
	hud.update_objective(GameState.depth, GameState.relays_collected, GameState.relay_target)
	hud.update_battery(player.lamp_charge, player.flashlight_enabled, player.is_in_safe_zone(), player.movement_mode)
	hud.update_stamina(player.stamina, player.exhausted)


func _on_interaction_message(message: String) -> void:
	hud.show_message(message)


func _build_floor() -> void:
	facility_view.generate_floor(GameState.level_seed_text())
	GameState.relay_target = facility_view.generator.relay_count
	player.position = facility_view.start_world_position()
	player.velocity = Vector3.ZERO
