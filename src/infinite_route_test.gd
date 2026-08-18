extends Node

## Playable debug bridge between the deterministic streamed topology and the
## full route. It deliberately ships only in tools-enabled builds for now:
## walking, collision, vertical streaming, pickups, checkpoints and authored
## prison dressing can be tested without pretending hunter persistence and
## online pickup arbitration are complete.

@onready var world: Node3D = %World
@onready var facility: StreamedFacilityView3D = %StreamedFacility
@onready var player: PlayerController3D = %Player
@onready var hud: HUD = %HUD

var world_state := StreamedWorldState.new()
var pause_menu: PauseMenu
var _last_checkpoint := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	player.interaction_message.connect(hud.show_message)
	hud.inventory_reorder_requested.connect(player.move_inventory_slot)
	hud.map_overlay.visible = false
	var minimap_panel := hud.minimap.get_parent()
	if minimap_panel != null:
		minimap_panel.visible = false
	facility.chunk_changed.connect(_on_chunk_changed)
	facility.pickup_claimed.connect(_on_pickup_claimed)
	facility.begin(str(RoomState.run_seed()), player, world_state)
	player.global_position = facility.spawn_position()

	pause_menu = PauseMenu.new()
	pause_menu.abandon_label = "LEAVE INFINITE TEST"
	pause_menu.abandon_warning = "This leaves the streamed route test and returns to the menu."
	pause_menu.abandoned.connect(_leave_test)
	add_child(pause_menu)
	AdminMenu.attach(self, _admin_status, [
		{"label": "TOGGLE NOCLIP", "action": func() -> void:
			player.set_admin_noclip(not player.admin_noclip),
			"state": func() -> bool: return player.admin_noclip},
		{"label": "RESTORE PLAYER", "action": func() -> void:
			player.restore_at_safe_zone()},
		{"label": "GIVE FLASHLIGHT", "action": func() -> void:
			player.grant_inventory_item("flashlight")},
	])
	hud.show_message("INFINITE ROUTE TEST // STREAMING ACTIVE")
	_update_hud()


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	var level := facility.current_level()
	GameState.depth = -level
	var data := facility.current_chunk_data()
	_update_checkpoint(data)
	hud.set_interaction_prompt(player.get_interaction_prompt())
	_update_hud()


func _update_checkpoint(data: Dictionary) -> void:
	if not bool(data.get("safe_room", false)):
		return
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	var center := Vector3(
		(coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
		coord.y * StreamedFacilityView3D.LEVEL_HEIGHT,
		(coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
	if Vector2(player.global_position.x - center.x,
			player.global_position.z - center.z).length() > 3.25:
		return
	if world_state.activate_checkpoint(data) \
			and world_state.active_checkpoint != _last_checkpoint:
		_last_checkpoint = world_state.active_checkpoint
		player.restore_at_safe_zone()
		hud.show_message("CHECKPOINT SECURED // HUNTERS CAN BREACH THIS ROOM")


func _on_chunk_changed(coord: Vector3i, data: Dictionary) -> void:
	var region := String(data.get("region", "maze")).to_upper()
	var danger := roundi(float((data.get("difficulty", {}) as Dictionary).get(
		"danger", 0.0)) * 100.0)
	hud.depth_label.text = "LEVEL %+d // %s" % [coord.y, region]
	hud.relay_label.text = "STREAMED CHUNKS %d // DANGER %d%%" % [
		facility.loaded_chunk_count(), danger]


func _on_pickup_claimed(entity_id: String) -> void:
	# Solo-only while the Infinite selector is debug-gated. The durable entity
	# id is still recorded now, so unloading/reloading cannot duplicate it.
	hud.show_message("WORLD PICKUP CLAIMED // %s" % entity_id)


func _update_hud() -> void:
	var data := facility.current_chunk_data()
	var safe := bool(data.get("safe_room", false))
	hud.update_battery(player.lamp_charge, player.flashlight_enabled, safe,
		player.movement_mode)
	hud.update_stamina(player.stamina, player.exhausted)
	hud.update_meters(player.meters)
	hud.update_inventory(player.selected_inventory_item(), player.taser_cooldown,
		player.inventory_durability_snapshot(), player.inventory_owned_snapshot(),
		player.inventory_order_snapshot(), player.inventory_max_durability_snapshot())


func _admin_status() -> String:
	var coord := facility.current_chunk_coord()
	var data := facility.current_chunk_data()
	return "INFINITE TEST\nCHUNK %d:%d:%d  %s\nLOADED %d  CHECKPOINT %s" % [
		coord.x, coord.y, coord.z, String(data.get("region", "maze")).to_upper(),
		facility.loaded_chunk_count(),
		world_state.active_checkpoint if not world_state.active_checkpoint.is_empty()
		else "NONE"]


func _leave_test() -> void:
	get_tree().paused = false
	RoomState.session_active = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
