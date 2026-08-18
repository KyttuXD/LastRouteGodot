extends Node

## Endless survival route. Every peer renders deterministic chunks around its
## own runner; the host alone owns contested pickups, safe-room integrity,
## checkpoints, hunter simulation and late-join snapshots.

const SNAPSHOT_PROTOCOL := 1
const AUTHORITY_REFRESH_SECONDS := .20
const STREAM_INTERACT_DISTANCE := 2.35
const CHECKPOINT_REQUEST_RETRY_USEC := 500_000

@onready var world: Node3D = %World
@onready var facility: StreamedFacilityView3D = %StreamedFacility
@onready var player: PlayerController3D = %Player
@onready var hud: HUD = %HUD

var world_state := StreamedWorldState.new()
var pause_menu: PauseMenu
var _last_checkpoint := ""
var _navigation: StreamedHunterNavigation
var _navigations := {}
var _hunter_views := {}
var _hunter_origins := {}
var _hunter_levels := {}
var _safe_damage_accumulators := {}
var _capture_cooldown := 0.0
var _was_chased := false
var _hunter_step_elapsed := 0.0
var _remotes: RemotePlayers
var _awaiting_snapshot := false
var _authority_refresh_elapsed := AUTHORITY_REFRESH_SECONDS
var _hunter_report: Array = []
var _taser_ready_usec_by_peer := {}
var _last_checkpoint_request := ""
var _last_checkpoint_request_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_awaiting_snapshot = RoomState.online and not RoomState.is_host
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
	facility.pickup_requester = _request_streamed_pickup
	facility.begin(str(RoomState.run_seed()), player, world_state)
	player.global_position = facility.spawn_position()
	_navigation = StreamedHunterNavigation.new(facility.generator,
		facility.current_level())
	_navigations[facility.current_level()] = _navigation

	_remotes = RemotePlayers.new()
	_remotes.name = "RemotePlayers"
	_remotes.local_player = player
	_remotes.state_overrides = _streamed_state_overrides
	_remotes.hunters_received.connect(_apply_hunter_report)
	_remotes.world_event.connect(_apply_stream_world_event)
	_remotes.interaction_requested.connect(_on_remote_interaction_request)
	_remotes.world_snapshot.connect(_apply_stream_snapshot)
	_remotes.player_event.connect(_apply_player_event)
	_remotes.hunter_event.connect(_apply_hunter_event)
	_remotes.snapshot_source = _build_stream_snapshot
	world.add_child(_remotes)
	_refresh_hunter_stream()

	pause_menu = PauseMenu.new()
	pause_menu.abandon_label = "LEAVE INFINITE ROUTE"
	pause_menu.pauses_tree = not RoomState.online
	pause_menu.abandon_warning = "This leaves the endless survival route."
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
	if _awaiting_snapshot:
		player.input_frozen = true
		hud.show_message("SYNCING INFINITE WORLD WITH HOST...")
	else:
		hud.show_message("INFINITE SURVIVAL // STREAMING + HUNTERS ACTIVE")
	_update_hud()


func _process(delta: float) -> void:
	if _awaiting_snapshot:
		player.input_frozen = true
	if get_tree().paused:
		return
	_capture_cooldown = maxf(0.0, _capture_cooldown - delta)
	var level := facility.current_level()
	GameState.depth = -level
	var data := facility.current_chunk_data()
	if not _awaiting_snapshot:
		_update_checkpoint(data)
	_authority_refresh_elapsed += delta
	if _remotes.simulates() and _authority_refresh_elapsed >= AUTHORITY_REFRESH_SECONDS:
		_authority_refresh_elapsed = 0.0
		_refresh_hunter_stream()
	if _remotes.simulates():
		_update_hunters(delta, data)
		_collect_hunter_report()
		_remotes.broadcast_hunters(_hunter_report)
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
	var checkpoint_id := String(info.get("checkpoint_id", ""))
	if checkpoint_id.is_empty() or checkpoint_id == _last_checkpoint:
		return
	var now := Time.get_ticks_usec()
	if checkpoint_id == _last_checkpoint_request \
			and now - _last_checkpoint_request_usec < CHECKPOINT_REQUEST_RETRY_USEC:
		return
	_last_checkpoint_request = checkpoint_id
	_last_checkpoint_request_usec = now
	var event := {"what": "stream_checkpoint", "checkpoint_id": checkpoint_id,
		"room_id": String(info.get("id", ""))}
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
	else:
		_accept_checkpoint(multiplayer.get_unique_id() if RoomState.online else 1,
			event)


func _on_chunk_changed(coord: Vector3i, data: Dictionary) -> void:
	if _navigation != null and _remotes != null and _remotes.simulates():
		_refresh_hunter_stream()
	var region := String(data.get("region", "maze")).to_upper()
	var danger := roundi(float((data.get("difficulty", {}) as Dictionary).get(
		"danger", 0.0)) * 100.0)
	hud.depth_label.text = "LEVEL %+d // %s" % [coord.y, region]
	hud.relay_label.text = "STREAMED CHUNKS %d // DANGER %d%%" % [
		facility.loaded_chunk_count(), danger]


func _on_pickup_claimed(entity_id: String) -> void:
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
	if _remotes == null or not _remotes.simulates() or facility.generator == null:
		return
	var centers: Array[Vector3i] = [facility.current_chunk_coord()]
	for value in _remotes.stream_centers():
		var center: Vector3i = value
		if not centers.has(center):
			centers.append(center)
	var active_coords := {}
	var coords_by_level := {}
	# Keep a one-chunk ring on the runner's floor and both adjacent floors.
	# Besides covering split parties, this keeps a hunter resident while she is
	# walking to and transferring across a deterministic stair link.
	for center in centers:
		for level_offset in range(-1, 2):
			var level := center.y + level_offset
			if not coords_by_level.has(level):
				coords_by_level[level] = []
			var level_coords: Array = coords_by_level[level]
			for z in range(center.z - 1, center.z + 2):
				for x in range(center.x - 1, center.x + 2):
					var coord := Vector3i(x, level, z)
					active_coords[coord] = true
					if not level_coords.has(coord):
						level_coords.append(coord)
			coords_by_level[level] = level_coords
	for level_value in coords_by_level:
		var level := int(level_value)
		var navigation := _navigations.get(level) as StreamedHunterNavigation
		if navigation == null:
			navigation = StreamedHunterNavigation.new(facility.generator, level)
			_navigations[level] = navigation
		navigation.refresh(level, coords_by_level[level])
	for level_value in _navigations.keys().duplicate():
		if not coords_by_level.has(level_value):
			_navigations.erase(level_value)
	_navigation = _navigations.get(facility.current_level()) as StreamedHunterNavigation
	var desired := {}
	# Deterministic chunk-owned spawns become durable the first time their chunk
	# enters the active window.
	for coord_value in active_coords:
		var coord: Vector3i = coord_value
		var data := facility.generator.chunk(coord)
		for spawn_value in data.get("hunter_spawns", []):
			var spawn: Dictionary = spawn_value
			var entity_id := String(spawn.get("id", ""))
			var state := world_state.ensure_hunter(spawn)
			if active_coords.has(_state_chunk(state)):
				desired[entity_id] = state
	# A hunter may have crossed out of her origin chunk. Current position, not
	# origin ownership, decides whether her view stays resident.
	for entity_id_value in world_state.hunters:
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
		if _remotes == null or _remotes.simulates():
			_store_hunter(entity_id, view)
		view.queue_free()
	_hunter_views.erase(entity_id)
	_hunter_origins.erase(entity_id)
	_hunter_levels.erase(entity_id)


func _store_hunter(entity_id: String, view: HunterView3D) -> void:
	world_state.store_hunter(entity_id, view.brain,
		int(_hunter_levels.get(entity_id, facility.current_level())),
		_hunter_origins.get(entity_id, Vector3i.ZERO))


func _update_hunters(delta: float, _data: Dictionary) -> void:
	if _remotes == null or not _remotes.simulates():
		return
	var local_safe := _player_in_intact_safe_room(facility.current_chunk_data())
	var local_target := _hunter_target(local_safe)
	var all_targets := _remotes.target_states(local_target)
	var breach_rooms := {}
	for entity_id_value in _hunter_views.keys().duplicate():
		var entity_id := String(entity_id_value)
		var view := _hunter_views.get(entity_id) as HunterView3D
		if view == null or not is_instance_valid(view) or view.brain == null:
			continue
		var level := int(_hunter_levels.get(entity_id, 0))
		var navigation := _navigations.get(level) as StreamedHunterNavigation
		if navigation == null:
			continue
		var target := _remotes.best_target(view.brain.position, local_target, -level)
		var safe_context := _safe_context_for_target(target, level)
		if bool(safe_context.get("inside", false)):
			var center: Vector2 = safe_context["center"]
			if view.brain.position.distance_to(center) <= 18.0:
				view.brain.state = HunterBrain.State.INVESTIGATE
				view.brain.has_last_known = true
				view.brain.last_known = center
		var captured := false
		if not target.is_empty():
			view.target_peer_id = int(target.get("peer_id", 1))
			captured = view.brain.update(delta, navigation, target,
				maxi(1, -level + 1), 0)
		else:
			var cross_target := _cross_floor_target(view.brain.position, level,
				all_targets)
			if cross_target.is_empty():
				view.target_peer_id = 0
				view.brain.update_without_target(delta, navigation,
					maxi(1, -level + 1), 0)
			else:
				view.target_peer_id = int(cross_target.get("peer_id", 1))
				_update_hunter_toward_stair(delta, entity_id, view, level,
					cross_target, navigation)
		view.sync_from_brain()
		# Stream-safe gimmicks may still emit local presentation events (for
		# example Thessine's decoy cues). The finite route has richer dispatch;
		# the endless pass consumes them so an unloaded hunter never accumulates
		# an unbounded event backlog.
		view.brain.world_events.clear()
		_store_hunter(entity_id, view)
		if bool(safe_context.get("inside", false)) \
				and view.brain.position.distance_to(safe_context["center"]) <= 4.25:
			var info: Dictionary = safe_context.get("info", {})
			var room_id := String(info.get("id", ""))
			var entry: Dictionary = breach_rooms.get(room_id,
				{"info": info, "breachers": 0})
			entry["breachers"] = int(entry.get("breachers", 0)) + 1
			breach_rooms[room_id] = entry
		if captured:
			_capture_target(view, target)
	_update_safe_room_breaches(delta, breach_rooms)


func _cross_floor_target(origin: Vector2, level: int,
		candidates: Array[Dictionary]) -> Dictionary:
	var chosen := {}
	var best_score := INF
	for candidate in candidates:
		if _target_protected(candidate):
			continue
		var target_level := -int(candidate.get("depth", -level))
		var position = candidate.get("position")
		if target_level == level or not position is Vector2:
			continue
		var score := origin.distance_to(position) + absf(target_level - level) * 12.0
		if score < best_score:
			best_score = score
			chosen = candidate
	return chosen


func _update_hunter_toward_stair(delta: float, entity_id: String,
		view: HunterView3D, level: int, target: Dictionary,
		navigation: StreamedHunterNavigation) -> void:
	var target_level := -int(target.get("depth", -level))
	var stair := _nearest_stair(view.brain.position, level,
		1 if target_level > level else -1, navigation)
	if stair.is_empty():
		view.brain.update_without_target(delta, navigation,
			maxi(1, -level + 1), 0)
		return
	var stair_position: Vector2 = stair["position"]
	var stair_target := target.duplicate(true)
	stair_target["position"] = stair_position
	stair_target["hidden"] = false
	stair_target["in_safe_zone"] = false
	stair_target["noise"] = 12.0
	stair_target["flashlight_on"] = true
	stair_target["capture_immune"] = true
	view.brain.update(delta, navigation, stair_target,
		maxi(1, -level + 1), 0)
	if view.brain.position.distance_to(stair_position) > .78:
		return
	var new_level := level + (1 if target_level > level else -1)
	_hunter_levels[entity_id] = new_level
	view.surface_height_provider = facility.streamed_surface_height.bind(new_level)
	view.brain.enter_search_from(target.get("position", stair_position), 2.25)
	_store_hunter(entity_id, view)
	# The authority window already includes adjacent floors; refreshing here
	# changes the navigation surface immediately instead of waiting for the next
	# periodic room-wide authority update.
	_refresh_hunter_stream()


func _nearest_stair(origin: Vector2, level: int, direction: int,
		navigation: StreamedHunterNavigation) -> Dictionary:
	var center := Vector3i(
		floori(origin.x / StreamedRouteGenerator.CHUNK_SIZE), level,
		floori(origin.y / StreamedRouteGenerator.CHUNK_SIZE))
	var wanted := "up" if direction > 0 else "down"
	var chosen := {}
	var best_distance := INF
	for z in range(center.z - 1, center.z + 2):
		for x in range(center.x - 1, center.x + 2):
			var coord := Vector3i(x, level, z)
			var data := facility.generator.chunk(coord)
			for stair_value in data.get("stairs", []):
				var stair: Dictionary = stair_value
				if String(stair.get("direction", "")) != wanted:
					continue
				var cell: Vector2i = stair.get("cell", Vector2i.ZERO)
				var position := Vector2(
					coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5,
					coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)
				var distance := origin.distance_to(position)
				if distance >= best_distance:
					continue
				var path := navigation.find_path(Vector2i(floori(origin.x),
					floori(origin.y)), Vector2i(floori(position.x),
					floori(position.y)))
				if path.is_empty():
					continue
				best_distance = distance
				chosen = {"position": position, "stair": stair, "coord": coord}
	return chosen


func _target_protected(target: Dictionary) -> bool:
	if target.is_empty() or bool(target.get("game_over", false)) \
			or bool(target.get("escape_active", false)) \
			or bool(target.get("capture_immune", false)):
		return true
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	var peer_id := int(target.get("peer_id", local_id))
	var tools_allowed := Build.tools_enabled() if peer_id == local_id \
		else _remotes.remote_admin_peer_allowed(peer_id)
	return tools_allowed and (bool(target.get("no_target", false)) \
		or bool(target.get("god_mode", false)))


func _hunter_target(in_safe_room: bool) -> Dictionary:
	return {
		"peer_id": multiplayer.get_unique_id() if RoomState.online else 1,
		"at": player.global_position,
		"position": player.grid_position(),
		"depth": -facility.current_level(),
		"hidden": player.hidden,
		"in_safe_zone": in_safe_room,
		"noise": player.noise,
		"flashlight_on": player.flashlight_enabled,
		"sprinting": player.movement_mode == "sprint" and player.noise > 0.0,
		"facing": player.facing,
		"lamp_charge": player.lamp_charge,
		"owned_items": player.inventory_owned_snapshot(),
		"item_durability": player.inventory_durability_snapshot(),
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


func _safe_context_for_target(target: Dictionary, level: int) -> Dictionary:
	if target.is_empty() or int(target.get("depth", -level)) != -level:
		return {"inside": false}
	var position = target.get("position")
	if not position is Vector2:
		return {"inside": false}
	var coord := Vector3i(
		floori(position.x / StreamedRouteGenerator.CHUNK_SIZE), level,
		floori(position.y / StreamedRouteGenerator.CHUNK_SIZE))
	var data := facility.generator.chunk(coord)
	if not bool(data.get("safe_room", false)):
		return {"inside": false}
	var info: Dictionary = data.get("safe_room_data", {})
	var status := world_state.safe_room_status(info)
	if bool(status.get("breached", false)):
		return {"inside": false, "info": info, "status": status}
	var center := Vector2(
		(coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
		(coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
	return {"inside": position.distance_to(center) <= 3.25,
		"center": center, "info": info, "status": status}


func _player_in_intact_safe_room(data: Dictionary) -> bool:
	return bool(_safe_context(data).get("inside", false))


func _update_safe_room_breaches(delta: float, breach_rooms: Dictionary) -> void:
	for room_id_value in _safe_damage_accumulators.keys().duplicate():
		if not breach_rooms.has(room_id_value):
			_safe_damage_accumulators.erase(room_id_value)
	for room_id_value in breach_rooms:
		var room_id := String(room_id_value)
		var entry: Dictionary = breach_rooms[room_id]
		var info: Dictionary = entry.get("info", {})
		var accumulated := float(_safe_damage_accumulators.get(room_id, 0.0)) \
			+ delta * float(info.get("breach_pressure", 1.0)) * 7.0 \
			* int(entry.get("breachers", 0))
		var damage := floori(accumulated)
		_safe_damage_accumulators[room_id] = accumulated - damage
		if damage <= 0:
			continue
		var status := world_state.damage_safe_room(info, damage)
		_publish_stream_event({"what": "stream_safe", "room_id": room_id,
			"integrity": int(status.get("integrity", 0)),
			"breached": bool(status.get("breached", false))}, false)


func _capture_target(view: HunterView3D, target: Dictionary) -> void:
	if view == null or target.is_empty() or _target_protected(target):
		return
	view.brain.calm_reset(GameConfig.ESCAPE_STUN_DURATION)
	view.sync_from_brain()
	_remotes.send_player_event(int(target.get("peer_id", 1)), {
		"what": "capture", "streamed": true,
		"entity_id": String(view.get_meta("streamed_entity_id", "")),
		"hunter_id": view.brain.hunter_id})


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
	if RoomState.online and not RoomState.is_host:
		_remotes.submit_hunter_event({"what": "taser"})
		return
	_resolve_taser(multiplayer.get_unique_id() if RoomState.online else 1)


func _resolve_taser(peer_id: int) -> void:
	if not _remotes.simulates():
		return
	var now := Time.get_ticks_usec()
	if now < int(_taser_ready_usec_by_peer.get(peer_id, 0)):
		return
	_taser_ready_usec_by_peer[peer_id] = now + int(
		GameConfig.TASER_COOLDOWN_SECONDS * 1_000_000.0)
	var target := _target_state_for_peer(peer_id)
	if target.is_empty() or bool(target.get("hidden", false)):
		return
	var owned = target.get("owned_items", {})
	if owned is Dictionary and not bool(owned.get("taser", false)):
		return
	var from = target.get("position")
	var aim = target.get("facing")
	var level := -int(target.get("depth", 0))
	var navigation := _navigations.get(level) as StreamedHunterNavigation
	if not from is Vector2 or not aim is Vector2 or navigation == null:
		return
	var hit: HunterView3D
	var nearest := INF
	for entity_id in _hunter_views:
		if int(_hunter_levels.get(entity_id, 999999)) != level:
			continue
		var view := _hunter_views[entity_id] as HunterView3D
		if view == null or view.brain == null or not view.brain.active:
			continue
		var distance: float = from.distance_to(view.brain.position)
		if distance >= nearest:
			continue
		if view.brain.beam_reaches(from, aim, view.brain.position,
				GameConfig.TASER_RANGE, GameConfig.TASER_HALF_ANGLE, navigation):
			hit = view
			nearest = distance
	if hit == null:
		_remotes.send_player_event(peer_id, {"what": "message",
			"message": "TASER // NO TARGET"})
		return
	hit.brain.apply_stun(GameConfig.TASER_STUN_SECONDS)
	hit.sync_from_brain()
	var identity := HunterRoster.get_identity(hit.brain.hunter_id)
	_remotes.send_player_event(peer_id, {"what": "message",
		"message": "TASER HIT // %s STUNNED" % String(identity.get(
			"display_name", hit.brain.hunter_id)).to_upper()})


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
	var info: Dictionary = data.get("safe_room_data", {})
	var event := {"what": "stream_safe_repair",
		"room_id": String(info.get("id", "")), "item": item_id}
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
	else:
		_accept_safe_repair(multiplayer.get_unique_id() if RoomState.online else 1,
			event)


func _streamed_state_overrides() -> Dictionary:
	return {"depth": -facility.current_level(),
		"in_safe_zone": _player_in_intact_safe_room(facility.current_chunk_data())}


func _request_streamed_pickup(_requesting_player: PlayerController3D,
		entity_id: String, item_id: String) -> String:
	var event := {"what": "stream_pickup", "entity_id": entity_id,
		"item": item_id}
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
		return "REQUESTING %s..." % String(PlayerController3D.INVENTORY_LABELS.get(
			item_id, item_id)).to_upper()
	_accept_streamed_pickup(multiplayer.get_unique_id() if RoomState.online else 1,
		event)
	return "COLLECTING %s..." % String(PlayerController3D.INVENTORY_LABELS.get(
		item_id, item_id)).to_upper()


func _on_remote_interaction_request(peer_id: int, event: Dictionary) -> void:
	if not _remotes.simulates():
		return
	match String(event.get("what", "")):
		"stream_pickup":
			_accept_streamed_pickup(peer_id, event)
		"stream_safe_repair":
			_accept_safe_repair(peer_id, event)
		"stream_checkpoint":
			_accept_checkpoint(peer_id, event)


func _accept_streamed_pickup(peer_id: int, event: Dictionary) -> void:
	var entity_id := String(event.get("entity_id", ""))
	var pickup := _stream_pickup_data(entity_id)
	if pickup.is_empty() or not world_state.pickup_available(entity_id):
		return
	var coord: Vector3i = pickup.get("coord", Vector3i(999999, 999999, 999999))
	var target := _target_state_for_peer(peer_id)
	var position = target.get("position")
	var cell: Vector2i = pickup.get("cell", Vector2i.ZERO)
	var pickup_position := Vector2(
		coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)
	if target.is_empty() or not position is Vector2 \
			or -int(target.get("depth", 999999)) != coord.y \
			or position.distance_to(pickup_position) > STREAM_INTERACT_DISTANCE:
		return
	var item_id := String(pickup.get("item", ""))
	if item_id.is_empty() or item_id != String(event.get("item", "")):
		return
	_publish_stream_event({"what": "stream_pickup", "entity_id": entity_id,
		"item": item_id, "winner_peer_id": peer_id})


func _accept_safe_repair(peer_id: int, event: Dictionary) -> void:
	var room := _safe_room_for_peer(peer_id, String(event.get("room_id", "")), 4.25)
	var item_id := String(event.get("item", ""))
	var target := _target_state_for_peer(peer_id)
	var owned = target.get("owned_items", {})
	if room.is_empty() or item_id not in ["crowbar", "rescue_axe"] \
			or not owned is Dictionary or not bool(owned.get(item_id, false)):
		return
	var info: Dictionary = room.get("safe_room_data", {})
	var status := world_state.repair_safe_room(info, 12)
	_publish_stream_event({"what": "stream_safe",
		"room_id": String(info.get("id", "")),
		"integrity": int(status.get("integrity", 0)),
		"breached": bool(status.get("breached", false)),
		"message_peer_id": peer_id}, false)


func _accept_checkpoint(peer_id: int, event: Dictionary) -> void:
	var room := _safe_room_for_peer(peer_id, String(event.get("room_id", "")), 3.25)
	if room.is_empty():
		return
	var info: Dictionary = room.get("safe_room_data", {})
	var checkpoint_id := String(info.get("checkpoint_id", ""))
	if checkpoint_id.is_empty() or checkpoint_id != String(event.get(
			"checkpoint_id", "")) \
			or bool(world_state.safe_room_status(info).get("breached", false)):
		return
	world_state.apply_checkpoint(checkpoint_id)
	_publish_stream_event({"what": "stream_checkpoint",
		"checkpoint_id": checkpoint_id, "room_id": String(info.get("id", "")),
		"winner_peer_id": peer_id}, false)


func _safe_room_for_peer(peer_id: int, room_id: String,
		maximum_distance: float) -> Dictionary:
	if room_id.is_empty():
		return {}
	var target := _target_state_for_peer(peer_id)
	var position = target.get("position")
	if target.is_empty() or not position is Vector2:
		return {}
	var level := -int(target.get("depth", 0))
	var coord := Vector3i(
		floori(position.x / StreamedRouteGenerator.CHUNK_SIZE), level,
		floori(position.y / StreamedRouteGenerator.CHUNK_SIZE))
	var data := facility.generator.chunk(coord)
	var info: Dictionary = data.get("safe_room_data", {})
	var center := Vector2((coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
		(coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
	if not bool(data.get("safe_room", false)) \
			or String(info.get("id", "")) != room_id \
			or position.distance_to(center) > maximum_distance:
		return {}
	return data


func _target_state_for_peer(peer_id: int) -> Dictionary:
	var local_target := _hunter_target(
		_player_in_intact_safe_room(facility.current_chunk_data()))
	for target in _remotes.target_states(local_target):
		if int(target.get("peer_id", 1)) == peer_id:
			return target
	return {}


func _stream_pickup_data(entity_id: String) -> Dictionary:
	var parts := entity_id.split(":")
	if entity_id.length() > 80 or parts.size() != 5 or parts[3] != "PICKUP" \
			or not parts[0].is_valid_int() or not parts[1].is_valid_int() \
			or not parts[2].is_valid_int() or not parts[4].is_valid_int():
		return {}
	var coord := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	if absi(coord.x) > 1_000_000 or absi(coord.y) > 1_000_000 \
			or absi(coord.z) > 1_000_000:
		return {}
	for value in facility.generator.chunk(coord).get("pickups", []):
		var pickup: Dictionary = value
		if String(pickup.get("id", "")) == entity_id:
			var result := pickup.duplicate(true)
			result["coord"] = coord
			return result
	return {}


func _publish_stream_event(event: Dictionary, _state_already_applied: bool = false) -> void:
	# Host RPCs do not loop back to the sender, so apply locally first. Durable
	# setters are idempotent, which also makes replayed reliable packets harmless.
	_apply_stream_world_event(event)
	if RoomState.online and RoomState.is_host:
		_remotes.relay_world_event(event)


func _apply_stream_world_event(event: Dictionary) -> void:
	match String(event.get("what", "")):
		"stream_pickup":
			var entity_id := String(event.get("entity_id", ""))
			facility.apply_pickup_claim(entity_id)
			var local_id := multiplayer.get_unique_id() if RoomState.online else 1
			if int(event.get("winner_peer_id", 0)) == local_id:
				var item_id := String(event.get("item", ""))
				if player.grant_inventory_item(item_id):
					Sound.collect()
					hud.show_message("%s COLLECTED" % String(
						PlayerController3D.INVENTORY_LABELS.get(item_id,
						item_id)).to_upper())
		"stream_safe":
			var room_id := String(event.get("room_id", ""))
			world_state.apply_safe_room_status(room_id,
				int(event.get("integrity", 0)), bool(event.get("breached", false)))
			var local_id := multiplayer.get_unique_id() if RoomState.online else 1
			if int(event.get("message_peer_id", 0)) == local_id:
				hud.show_message("SAFE ROOM REPAIRED // %d%%" % int(
					event.get("integrity", 0)))
			elif bool(event.get("breached", false)) \
					and _local_safe_room_id() == room_id:
				hud.show_message("SAFE ROOM BREACHED // MOVE OR FIGHT")
		"stream_checkpoint":
			var checkpoint_id := String(event.get("checkpoint_id", ""))
			world_state.apply_checkpoint(checkpoint_id)
			var local_id := multiplayer.get_unique_id() if RoomState.online else 1
			if int(event.get("winner_peer_id", 0)) == local_id:
				_last_checkpoint = checkpoint_id
				_last_checkpoint_request = ""
				_last_checkpoint_request_usec = 0
				player.restore_at_safe_zone()
				Sound.recharge(20.0)
				hud.show_message("SAFE CHECKPOINT ACTIVE")


func _local_safe_room_id() -> String:
	var data := facility.current_chunk_data()
	if not bool(data.get("safe_room", false)):
		return ""
	return String((data.get("safe_room_data", {}) as Dictionary).get("id", ""))


func _build_stream_snapshot() -> Dictionary:
	_collect_hunter_report()
	return {"snapshot_protocol": SNAPSHOT_PROTOCOL,
		"seed": RoomState.run_seed(), "world_state": world_state.snapshot(),
		"hunters": _hunter_report.duplicate(true)}


func _apply_stream_snapshot(state: Dictionary) -> void:
	if int(state.get("snapshot_protocol", -1)) != SNAPSHOT_PROTOCOL \
			or int(state.get("seed", 0)) != RoomState.run_seed():
		return
	var snapshot = state.get("world_state")
	var report = state.get("hunters")
	if not snapshot is Dictionary or not report is Array \
			or not world_state.adopt(snapshot):
		return
	facility.refresh_mutations()
	_apply_hunter_report(report)
	_awaiting_snapshot = false
	player.input_frozen = pause_menu != null and pause_menu.is_open()
	_remotes.confirm_snapshot_applied()
	hud.show_message("INFINITE WORLD SYNCED // SURVIVE")


func _collect_hunter_report() -> void:
	_hunter_report.clear()
	var ids := _hunter_views.keys()
	ids.sort()
	for entity_id_value in ids:
		var entity_id := String(entity_id_value)
		var view := _hunter_views.get(entity_id) as HunterView3D
		if view == null or view.brain == null:
			continue
		_store_hunter(entity_id, view)
		var state := world_state.hunter_state(entity_id)
		state["entity_id"] = entity_id
		state["target_peer_id"] = view.target_peer_id
		state["gimmick"] = view.brain.gimmick.network_state() \
			if view.brain.gimmick != null else {}
		_hunter_report.append(state)


func _apply_hunter_report(data: Array) -> void:
	if _remotes != null and _remotes.simulates():
		return
	var reported := {}
	for value in data:
		if not value is Dictionary:
			continue
		var state: Dictionary = value
		var entity_id := String(state.get("entity_id", ""))
		if entity_id.is_empty():
			continue
		reported[entity_id] = true
		world_state.hunters[entity_id] = state.duplicate(true)
		if not _hunter_views.has(entity_id):
			_load_hunter(entity_id, state)
		var view := _hunter_views.get(entity_id) as HunterView3D
		if view == null or view.brain == null:
			continue
		world_state.restore_hunter(view.brain, state)
		var level := int(state.get("level", 0))
		_hunter_levels[entity_id] = level
		view.surface_height_provider = facility.streamed_surface_height.bind(level)
		view.target_peer_id = int(state.get("target_peer_id", 0))
		var gimmick_state = state.get("gimmick", {})
		if view.brain.gimmick != null and gimmick_state is Dictionary:
			view.brain.gimmick.apply_network_state(gimmick_state)
		view.sync_from_brain()
	for entity_id_value in _hunter_views.keys().duplicate():
		var entity_id := String(entity_id_value)
		if not reported.has(entity_id):
			_unload_hunter(entity_id)


func _apply_player_event(event: Dictionary) -> void:
	match String(event.get("what", "")):
		"capture":
			if not bool(event.get("streamed", false)):
				return
			_capture_cooldown = 3.5
			Sound.capture()
			player.velocity = Vector3.ZERO
			player.global_position = _checkpoint_world_position()
			player.stun_timer = maxf(player.stun_timer, 1.5)
			var hunter_id := String(event.get("hunter_id", HunterRoster.DEFAULT_ID))
			var identity := HunterRoster.get_identity(hunter_id)
			hud.show_message("CAUGHT BY %s // RETURNED TO LAST SAFE CHECKPOINT" %
				String(identity.get("display_name", hunter_id)).to_upper())
			if RoomState.online and not RoomState.is_host:
				_remotes.submit_hunter_event({"what": "caught"})
		"message":
			var message := String(event.get("message", ""))
			if not message.is_empty():
				hud.show_message(message)


func _apply_hunter_event(event: Dictionary) -> void:
	if RoomState.online and not RoomState.is_host:
		return
	if String(event.get("what", "")) == "taser":
		_resolve_taser(int(event.get("peer_id",
			multiplayer.get_unique_id() if RoomState.online else 1)))


func _update_hunter_audio(delta: float, data: Dictionary) -> void:
	var nearest := INF
	var stepping: HunterView3D
	var stepping_distance := INF
	var chased := false
	var local_level := facility.current_level()
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	for entity_id in _hunter_views:
		if int(_hunter_levels.get(entity_id, 999999)) != local_level:
			continue
		var view := _hunter_views[entity_id] as HunterView3D
		if view == null or view.brain == null or not view.brain.active:
			continue
		var distance := view.brain.position.distance_to(player.grid_position())
		nearest = minf(nearest, distance)
		if view.brain.state == HunterBrain.State.CHASE \
				and view.brain.stun_timer <= 0.0 \
				and view.target_peer_id == local_id:
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
		var info: Dictionary = data.get("safe_room_data", {})
		var status := world_state.damage_safe_room(info, 25)
		_publish_stream_event({"what": "stream_safe",
			"room_id": String(info.get("id", "")),
			"integrity": int(status.get("integrity", 0)),
			"breached": bool(status.get("breached", false))}, false)


func _admin_repair_checkpoint() -> void:
	var data := facility.current_chunk_data()
	if bool(data.get("safe_room", false)):
		var info: Dictionary = data.get("safe_room_data", {})
		var status := world_state.repair_safe_room(info, 25)
		_publish_stream_event({"what": "stream_safe",
			"room_id": String(info.get("id", "")),
			"integrity": int(status.get("integrity", 0)),
			"breached": bool(status.get("breached", false))}, false)


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
