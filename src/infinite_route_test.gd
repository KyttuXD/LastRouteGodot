extends Node

## Playable solo-debug endless survival route. Geometry and hunter entities are
## regenerated from stable chunk ids, while StreamedWorldState retains the
## mutations which must outlive meshes: pickups, safe-room integrity,
## checkpoints, and moving hunter state. Online authority remains gated.

@onready var world: Node3D = %World
@onready var facility: StreamedFacilityView3D = %StreamedFacility
@onready var player: PlayerController3D = %Player
@onready var hud: HUD = %HUD

var world_state := StreamedWorldState.new()
var pause_menu: PauseMenu
var _last_checkpoint := ""
var _navigation: StreamedHunterNavigation
var _hunter_views := {}
var _hunter_origins := {}
var _hunter_levels := {}
var _safe_damage_accumulator := 0.0
var _capture_cooldown := 0.0
var _last_hunter_level := 999999
var _was_chased := false
var _hunter_step_elapsed := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	player.interaction_message.connect(hud.show_message)
	player.taser_requested.connect(_on_taser_requested)
	player.tool_used.connect(_on_tool_used)
	hud.inventory_reorder_requested.connect(player.move_inventory_slot)
	hud.map_overlay.visible = false
	var minimap_panel := hud.minimap.get_parent()
	if minimap_panel != null:
		minimap_panel.visible = false
	facility.chunk_changed.connect(_on_chunk_changed)
	facility.pickup_claimed.connect(_on_pickup_claimed)
	facility.begin(str(RoomState.run_seed()), player, world_state)
	player.global_position = facility.spawn_position()
	_navigation = StreamedHunterNavigation.new(facility.generator,
		facility.current_level())
	_refresh_hunter_stream()

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
		{"label": "GIVE TASER", "action": func() -> void:
			player.grant_inventory_item("taser")},
		{"label": "DAMAGE CHECKPOINT", "action": _admin_damage_checkpoint},
		{"label": "REPAIR CHECKPOINT", "action": _admin_repair_checkpoint},
	])
	hud.show_message("INFINITE SURVIVAL // STREAMING + HUNTERS ACTIVE")
	_update_hud()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_capture_cooldown = maxf(0.0, _capture_cooldown - delta)
	var level := facility.current_level()
	GameState.depth = -level
	var data := facility.current_chunk_data()
	_update_checkpoint(data)
	_update_hunters(delta, data)
	_update_hunter_audio(delta, data)
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
	var info: Dictionary = data.get("safe_room_data", {})
	if bool(world_state.safe_room_status(info).get("breached", false)):
		return
	if world_state.activate_checkpoint(data) \
			and world_state.active_checkpoint != _last_checkpoint:
		_last_checkpoint = world_state.active_checkpoint
		player.restore_at_safe_zone()
		hud.show_message("CHECKPOINT SECURED // HUNTERS CAN BREACH THIS ROOM")


func _on_chunk_changed(coord: Vector3i, data: Dictionary) -> void:
	if _navigation != null:
		_refresh_hunter_stream()
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
	var safe := _player_in_intact_safe_room(data)
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
	var safe_text := "NONE"
	if bool(data.get("safe_room", false)):
		var status := world_state.safe_room_status(data.get("safe_room_data", {}))
		safe_text = "%d%%%s" % [int(status.get("integrity", 0)),
			" BREACHED" if bool(status.get("breached", false)) else ""]
	return "INFINITE TEST\nCHUNK %d:%d:%d  %s\nLOADED %d  HUNTERS %d\nSAFE %s  CHECKPOINT %s" % [
		coord.x, coord.y, coord.z, String(data.get("region", "maze")).to_upper(),
		facility.loaded_chunk_count(), _hunter_views.size(), safe_text,
		world_state.active_checkpoint if not world_state.active_checkpoint.is_empty()
		else "NONE"]


func _refresh_hunter_stream() -> void:
	if _navigation == null:
		return
	var level := facility.current_level()
	var coords := facility.loaded_horizontal_coords()
	_navigation.refresh(level, coords)
	var active_coords := {}
	for coord in coords:
		active_coords[coord] = true
	var desired := {}
	# Deterministic chunk-owned spawns become durable the first time their chunk
	# enters the active window.
	for coord in coords:
		var data := facility.generator.chunk(coord)
		for spawn_value in data.get("hunter_spawns", []):
			var spawn: Dictionary = spawn_value
			var entity_id := String(spawn.get("id", ""))
			var state := world_state.ensure_hunter(spawn)
			if active_coords.has(_state_chunk(state)):
				desired[entity_id] = state
	# A hunter may have crossed out of her origin chunk. Current position, not
	# origin ownership, decides whether her view stays resident.
	for entity_id_value in world_state.hunter_ids_on_level(level):
		var entity_id := String(entity_id_value)
		var state := world_state.hunter_state(entity_id)
		if active_coords.has(_state_chunk(state)):
			desired[entity_id] = state
	for entity_id_value in _hunter_views.keys().duplicate():
		var entity_id := String(entity_id_value)
		if not desired.has(entity_id):
			_unload_hunter(entity_id)
	for entity_id_value in desired:
		var entity_id := String(entity_id_value)
		if not _hunter_views.has(entity_id):
			_load_hunter(entity_id, desired[entity_id])
	_last_hunter_level = level


func _load_hunter(entity_id: String, state: Dictionary) -> void:
	var hunter_id := String(state.get("hunter_id", HunterRoster.DEFAULT_ID))
	var spawn_position: Vector2 = state.get("position", Vector2.ZERO)
	var level := int(state.get("level", facility.current_level()))
	var view := HunterView3D.new()
	view.name = "StreamedHunter_%s" % entity_id.replace(":", "_")
	view.brain = HunterBrain.new(spawn_position,
		"%s:%s" % [facility.generator.world_seed, entity_id], hunter_id,
		RoomState.difficulty_id())
	world_state.restore_hunter(view.brain, state)
	view.surface_height_provider = facility.streamed_surface_height.bind(level)
	view.set_meta("streamed_entity_id", entity_id)
	view.add_to_group("streamed_hunter")
	world.add_child(view)
	view.sync_from_brain()
	_hunter_views[entity_id] = view
	_hunter_origins[entity_id] = state.get("origin_chunk", Vector3i.ZERO)
	_hunter_levels[entity_id] = level


func _unload_hunter(entity_id: String) -> void:
	var view := _hunter_views.get(entity_id) as HunterView3D
	if view != null and is_instance_valid(view):
		_store_hunter(entity_id, view)
		view.queue_free()
	_hunter_views.erase(entity_id)
	_hunter_origins.erase(entity_id)
	_hunter_levels.erase(entity_id)


func _store_hunter(entity_id: String, view: HunterView3D) -> void:
	world_state.store_hunter(entity_id, view.brain,
		int(_hunter_levels.get(entity_id, facility.current_level())),
		_hunter_origins.get(entity_id, Vector3i.ZERO))


func _update_hunters(delta: float, data: Dictionary) -> void:
	if _navigation == null:
		return
	if facility.current_level() != _last_hunter_level:
		_refresh_hunter_stream()
	var safe_context := _safe_context(data)
	var target := _hunter_target(bool(safe_context.get("inside", false)))
	var breachers := 0
	for entity_id_value in _hunter_views.keys().duplicate():
		var entity_id := String(entity_id_value)
		var view := _hunter_views.get(entity_id) as HunterView3D
		if view == null or not is_instance_valid(view) or view.brain == null:
			continue
		if bool(safe_context.get("inside", false)) and not player.admin_no_target:
			var center: Vector2 = safe_context["center"]
			if view.brain.position.distance_to(center) <= 18.0:
				view.brain.state = HunterBrain.State.INVESTIGATE
				view.brain.has_last_known = true
				view.brain.last_known = center
		var captured := false
		if player.admin_no_target:
			view.brain.update_without_target(delta, _navigation,
				maxi(1, -facility.current_level() + 1), 0)
		else:
			captured = view.brain.update(delta, _navigation, target,
				maxi(1, -facility.current_level() + 1), 0)
		view.sync_from_brain()
		# Stream-safe gimmicks may still emit local presentation events (for
		# example Thessine's decoy cues). The finite route has richer dispatch;
		# the endless pass consumes them so an unloaded hunter never accumulates
		# an unbounded event backlog.
		view.brain.world_events.clear()
		_store_hunter(entity_id, view)
		if bool(safe_context.get("inside", false)) and not player.admin_no_target \
				and view.brain.position.distance_to(safe_context["center"]) <= 4.25:
			breachers += 1
		if captured and _capture_cooldown <= 0.0:
			_capture_player(view)
			return
	_update_safe_room_breach(delta, safe_context, breachers)


func _hunter_target(in_safe_room: bool) -> Dictionary:
	return {
		"position": player.grid_position(),
		"hidden": player.hidden,
		"in_safe_zone": in_safe_room,
		"noise": player.noise,
		"flashlight_on": player.flashlight_enabled,
		"sprinting": player.movement_mode == "sprint" and player.noise > 0.0,
		"facing": player.facing,
		"lamp_charge": player.lamp_charge,
		"meters": player.meters,
		"no_target": player.admin_no_target,
		"god_mode": player.admin_god_mode,
		"escape_active": false,
		"capture_immune": _capture_cooldown > 0.0,
		"game_over": false,
	}


func _safe_context(data: Dictionary) -> Dictionary:
	if not bool(data.get("safe_room", false)):
		return {"inside": false}
	var info: Dictionary = data.get("safe_room_data", {})
	var status := world_state.safe_room_status(info)
	if bool(status.get("breached", false)):
		return {"inside": false, "info": info, "status": status}
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	var center := Vector2(
		(coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
		(coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
	return {"inside": player.grid_position().distance_to(center) <= 3.25,
		"center": center, "info": info, "status": status}


func _player_in_intact_safe_room(data: Dictionary) -> bool:
	return bool(_safe_context(data).get("inside", false))


func _update_safe_room_breach(delta: float, context: Dictionary,
		breachers: int) -> void:
	if not bool(context.get("inside", false)) or breachers <= 0:
		_safe_damage_accumulator = 0.0
		return
	var info: Dictionary = context.get("info", {})
	_safe_damage_accumulator += delta * float(info.get("breach_pressure", 1.0)) \
		* 7.0 * breachers
	var damage := floori(_safe_damage_accumulator)
	if damage <= 0:
		return
	_safe_damage_accumulator -= damage
	var status := world_state.damage_safe_room(info, damage)
	if bool(status.get("breached", false)):
		hud.show_message("SAFE ROOM BREACHED // MOVE OR FIGHT")
	else:
		hud.show_message("SAFE ROOM UNDER ATTACK // %d%%" %
			int(status.get("integrity", 0)))


func _capture_player(view: HunterView3D) -> void:
	_capture_cooldown = 3.5
	Sound.capture()
	var identity := HunterRoster.get_identity(view.brain.hunter_id)
	player.velocity = Vector3.ZERO
	player.global_position = _checkpoint_world_position()
	player.stun_timer = maxf(player.stun_timer, 1.5)
	view.brain.calm_reset(GameConfig.ESCAPE_STUN_DURATION)
	view.sync_from_brain()
	hud.show_message("CAUGHT BY %s // RETURNED TO LAST SAFE CHECKPOINT" %
		String(identity.get("display_name", view.brain.hunter_id)).to_upper())


func _checkpoint_world_position() -> Vector3:
	var fallback := facility.spawn_position()
	if world_state.active_checkpoint.is_empty():
		return fallback
	var parts := world_state.active_checkpoint.split(":")
	if parts.size() < 4:
		return fallback
	var coord := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	var data := facility.generator.chunk(coord)
	var info: Dictionary = data.get("safe_room_data", {})
	if info.is_empty() or bool(world_state.safe_room_status(info).get(
			"breached", false)):
		return fallback
	return Vector3((coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE, .08 \
		+ coord.y * StreamedFacilityView3D.LEVEL_HEIGHT,
		(coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)


func _on_taser_requested() -> void:
	var hit: HunterView3D
	var nearest := INF
	for value in _hunter_views.values():
		var view := value as HunterView3D
		if view == null or view.brain == null or not view.brain.active:
			continue
		var distance := player.grid_position().distance_to(view.brain.position)
		if distance >= nearest:
			continue
		if view.brain.beam_reaches(player.grid_position(), player.facing,
				view.brain.position, GameConfig.TASER_RANGE,
				GameConfig.TASER_HALF_ANGLE, _navigation):
			hit = view
			nearest = distance
	if hit == null:
		hud.show_message("TASER // NO TARGET")
		return
	hit.brain.apply_stun(GameConfig.TASER_STUN_SECONDS)
	hit.sync_from_brain()
	var identity := HunterRoster.get_identity(hit.brain.hunter_id)
	hud.show_message("TASER HIT // %s STUNNED" %
		String(identity.get("display_name", hit.brain.hunter_id)).to_upper())


func _on_tool_used(item_id: String) -> void:
	if item_id not in ["crowbar", "rescue_axe"]:
		return
	var data := facility.current_chunk_data()
	if not bool(data.get("safe_room", false)):
		return
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	var center := Vector2((coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
		(coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
	if player.grid_position().distance_to(center) > 4.25:
		return
	var status := world_state.repair_safe_room(data.get("safe_room_data", {}), 12)
	hud.call_deferred("show_message", "SAFE ROOM REPAIRED // %d%%" %
		int(status.get("integrity", 0)))


func _update_hunter_audio(delta: float, data: Dictionary) -> void:
	var nearest := INF
	var stepping: HunterView3D
	var stepping_distance := INF
	var chased := false
	for value in _hunter_views.values():
		var view := value as HunterView3D
		if view == null or view.brain == null or not view.brain.active:
			continue
		var distance := view.brain.position.distance_to(player.grid_position())
		nearest = minf(nearest, distance)
		if view.brain.state == HunterBrain.State.CHASE \
				and view.brain.stun_timer <= 0.0:
			chased = true
		if view.brain.state != HunterBrain.State.IDLE and distance < stepping_distance:
			stepping = view
			stepping_distance = distance
	if chased and not _was_chased:
		Sound.chase_start()
	_was_chased = chased
	var danger := 0.0 if nearest == INF else clampf(
		1.0 - (nearest - .5) / 9.0, 0.0, 1.0)
	if chased:
		danger = maxf(danger, .48)
	if _player_in_intact_safe_room(data):
		danger = 0.0
	Sound.heartbeat(danger)
	if stepping == null or player.hidden:
		_hunter_step_elapsed = 0.0
		return
	_hunter_step_elapsed += delta
	var gap := .30 if stepping.brain.state == HunterBrain.State.CHASE else .43
	if _hunter_step_elapsed < gap:
		return
	_hunter_step_elapsed = 0.0
	var offset := stepping.brain.position - player.grid_position()
	var distance := offset.length()
	if distance > 9.0:
		return
	var right := Vector2(-player.facing.y, player.facing.x)
	var pan := clampf(offset.dot(right) / 4.5, -1.0, 1.0)
	Sound.hunter_footstep(pan, .09 * (1.0 - distance / 9.0))


func _admin_damage_checkpoint() -> void:
	var data := facility.current_chunk_data()
	if bool(data.get("safe_room", false)):
		world_state.damage_safe_room(data.get("safe_room_data", {}), 25)


func _admin_repair_checkpoint() -> void:
	var data := facility.current_chunk_data()
	if bool(data.get("safe_room", false)):
		world_state.repair_safe_room(data.get("safe_room_data", {}), 25)


func _state_chunk(state: Dictionary) -> Vector3i:
	var position: Vector2 = state.get("position", Vector2.ZERO)
	return Vector3i(
		floori(position.x / StreamedRouteGenerator.CHUNK_SIZE),
		int(state.get("level", 0)),
		floori(position.y / StreamedRouteGenerator.CHUNK_SIZE))


func _leave_test() -> void:
	get_tree().paused = false
	RoomState.session_active = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
