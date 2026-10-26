extends Node

## Endless survival route. Every peer renders deterministic chunks around its
## own runner; the host alone owns contested pickups, safe-room integrity,
## checkpoints, hunter simulation and late-join snapshots.

const SNAPSHOT_PROTOCOL := 2
const AUTHORITY_REFRESH_SECONDS := .20
const STREAM_INTERACT_DISTANCE := 3.25
const CHECKPOINT_REQUEST_RETRY_USEC := 500_000
## Hunters transfer one floor at a time, so only the current and immediately
## adjacent floors need live navigation. Baking five 3x3 A* windows whenever a
## region changed wasted work on floors no hunter could enter next.
const HUNTER_VERTICAL_STREAM_RADIUS := 1
## AI/pathfinding does not need to run at the render rate. Thirty deterministic
## simulation samples keep movement responsive while preventing 120/144 Hz
## clients from paying 4-5x for the same hunter decisions. Replication matches
## the existing 20 Hz player transport.
const HUNTER_SIMULATION_STEP := 1.0 / 30.0
const HUNTER_MAX_CATCH_UP_STEPS := 2
const HUNTER_BROADCAST_SECONDS := 1.0 / RemotePlayers.SEND_HZ
const HUNTER_RESIDENCY_CHUNK_RADIUS := 3
const MAP_DISCOVERY_NEARBY_RADIUS := 4.5
const WAYPOINT_ARRIVAL_RADIUS := 5.0
const DROPPED_TOOL_MARK_RADIUS := 14.0
const LOCAL_SAVE_SCHEMA := 1
const TEMPERATURE_HUNTER_EFFECT_RADIUS := 14.0
const STORY_DIRECTOR_SCRIPT := preload("res://src/story/infinite_story_director.gd")
const HUNTER_JUMPSCARE_SCENE := preload("res://scenes/hunter_jumpscare.tscn")

@onready var world: Node3D = %World
@onready var facility: StreamedFacilityView3D = %StreamedFacility
@onready var player: PlayerController3D = %Player
@onready var hud: HUD = %HUD
@onready var run_report: RunReport = %RunReport

var world_state := StreamedWorldState.new()
var pause_menu: PauseMenu
var _admin_menu: AdminMenu
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
var _room_chat: RoomChat
var _awaiting_snapshot := false
var _authority_refresh_elapsed := AUTHORITY_REFRESH_SECONDS
var _hunter_report: Array = []
var _taser_ready_usec_by_peer := {}
var _last_checkpoint_request := ""
var _last_checkpoint_request_usec := 0
var _hunter_activation_announced := false
var _hunter_simulation_accumulator := 0.0
var _hunter_broadcast_elapsed := HUNTER_BROADCAST_SECONDS
var _hunter_stream_signature := ""
## Compact copies of only the chunks the local runner has discovered. Keeping
## this separate from the renderer means unloaded history remains map-visible
## without retaining any 3D scene nodes.
var _discovered_chunks: Dictionary = {}
var _discovered_rooms := {}
var _discovered_map_markers := {}
var _map_waypoints: Array = []
var _waypoint_route: Array = []
var _waypoint_route_key := ""
var _waypoint_grid_signature := ""
var _waypoint_grid := AStarGrid2D.new()
var _waypoint_trail: MeshInstance3D
var _admin_reveal_map := false
var _admin_reveal_hunters := false
var _drop_nodes := {}
var pixel_signal_effect: PixelSignalEffect
var jumpscare: HunterJumpscare
var _story
var _death_screen_open := false
var _capture_resolving := false
## Streamed entity id / hunter id of whichever grab the local escape struggle
## is currently against, so success/failure can act on the right hunter.
var _escaping_entity_id := ""
var _escaping_hunter_id := ""
var _pending_admin_requests := {}
var _admin_ticket_refresh_elapsed := 0.0
var _relay_inactivity_seconds := 0.0
var _party_afk_seconds := 0.0
var _party_activity_anchors := {}
var _afk_void_warning_shown := false
var _anti_idle_last_relay_count := 0
var _anti_idle_spawn_sequence := 0
var _reconnect_notice_shown := false
var _run_statistics := {
	"elapsed_seconds": 0.0,
	"distance_m": 0.0,
	"relays_collected": 0,
	"items_collected": 0,
	"rooms_discovered": 0,
	"hunters_encountered": 0,
	"chases_started": 0,
	"checkpoints_activated": 0,
	"visited_levels": {"0": true},
	"encountered_hunters": {},
}
var _statistics_last_position := Vector3.ZERO
var _loaded_from_save := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RefLook.install(self, get_node_or_null("WorldEnvironment") as WorldEnvironment)
	add_to_group("gameplay_session")
	UpdateManager.update_ready.connect(_on_background_update_ready)
	pixel_signal_effect = PixelSignalEffect.new()
	pixel_signal_effect.name = "PixelSignalEffect"
	add_child(pixel_signal_effect)
	jumpscare = HUNTER_JUMPSCARE_SCENE.instantiate()
	world.add_child(jumpscare)
	_story = STORY_DIRECTOR_SCRIPT.new()
	_story.name = "InfiniteStoryDirector"
	add_child(_story)
	var story_error: String = _story.configure(not RoomState.online or RoomState.is_host)
	if not story_error.is_empty():
		push_error("Infinite story content: %s" % story_error)
	_story.state_published.connect(_on_story_state_published)
	_story.active_changed.connect(_on_story_active_changed)
	_build_waypoint_ground_trail()
	_awaiting_snapshot = RoomState.online and not RoomState.is_host
	# An online host with no guests may resume a local archive without tearing
	# down the room allocation. Guests never consume the host machine's pending
	# slot; a populated co-op room only permits snapshots, not live replacement.
	var pending_save := RunSaves.consume_pending() \
		if not RoomState.online or RoomState.is_host else {}
	var pending_payload: Dictionary = pending_save.get("payload", {}) \
		if bool(pending_save.get("ok", false)) else {}
	if not pending_payload.is_empty():
		RoomState.seed_text = String(pending_payload.get("seed_text",
			RoomState.seed_text))
		RoomState.difficulty = clampi(int(pending_payload.get("difficulty",
			RoomState.Difficulty.STANDARD)), RoomState.Difficulty.RELAXED,
			RoomState.Difficulty.HARD)
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	player.interaction_message.connect(hud.show_message)
	player.taser_requested.connect(_on_taser_requested)
	player.tool_used.connect(_on_tool_used)
	player.item_drop_requested.connect(_on_item_drop_requested)
	player.interaction_veto = _stream_guardian_blocking
	player.vent_resolver = _use_streamed_vent
	hud.inventory_reorder_requested.connect(player.move_inventory_slot)
	hud.inventory_open_changed.connect(_on_inventory_open_changed)
	hud.map_open_changed.connect(_on_map_open_changed)
	hud.map_waypoint_requested.connect(_on_map_waypoint_requested)
	run_report.restart_requested.connect(_respawn_after_death)
	run_report.leave_requested.connect(_leave_test)
	hud.map_overlay.visible = false
	# Strongly type the parent to avoid Godot's typed local inference error in
	# strict parse mode on some editor builds.
	var minimap_panel: Control = hud.minimap.get_parent() as Control
	if minimap_panel != null:
		minimap_panel.visible = true
	facility.chunk_changed.connect(_on_chunk_changed)
	facility.pickup_claimed.connect(_on_pickup_claimed)
	facility.pickup_requester = _request_streamed_pickup
	facility.door_requester = _request_streamed_door
	if not pending_payload.is_empty():
		_loaded_from_save = _adopt_route_save_before_stream(pending_payload)
	facility.begin(str(RoomState.run_seed()), player, world_state)
	if not _loaded_from_save:
		player.global_position = facility.spawn_position()
	_statistics_last_position = player.global_position
	_navigation = StreamedHunterNavigation.new(facility.generator,
		facility.current_level(), world_state)
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
	_room_chat = RoomChat.attach(self, _remotes)
	_room_chat.open_changed.connect(_on_chat_open_changed)
	if not Backend.admin_ticket_verified.is_connected(_on_admin_ticket_verified):
		Backend.admin_ticket_verified.connect(_on_admin_ticket_verified)
	if not Backend.admin_ticket_changed.is_connected(_on_admin_ticket_changed):
		Backend.admin_ticket_changed.connect(_on_admin_ticket_changed)
	if RoomState.online and not RoomState.is_host \
			and not Backend.admin_ticket_for_room(RoomState.code).is_empty():
		_remotes.request_interaction({"what": "admin_auth"})
	_refresh_hunter_stream()

	pause_menu = PauseMenu.new()
	pause_menu.abandon_label = "LEAVE ROUTE"
	pause_menu.pauses_tree = not RoomState.online
	pause_menu.dismiss_overlay = _dismiss_gameplay_overlay
	if RoomState.online and RoomState.is_host:
		pause_menu.abandon_warning = \
			"This ends the route for everyone and returns the room to staging."
	elif RoomState.online:
		pause_menu.abandon_warning = \
			"This disconnects you and returns to staging. The host's route continues."
	else:
		pause_menu.abandon_warning = \
			"This returns to room staging. Save first if you want to resume later."
	pause_menu.save_slots_source = RunSaves.list_slots
	pause_menu.save_new_request = _pause_save_new
	pause_menu.save_overwrite_request = _pause_save_overwrite
	pause_menu.save_load_request = _pause_save_load
	pause_menu.save_rename_request = RunSaves.rename_slot
	pause_menu.save_delete_request = RunSaves.delete_slot
	pause_menu.statistics_source = _pause_statistics
	pause_menu.abandoned.connect(_leave_test)
	pause_menu.opened.connect(_on_pause_opened)
	pause_menu.resumed.connect(_on_pause_resumed)
	add_child(pause_menu)
	_admin_menu = AdminMenu.attach(self, _admin_status, _infinite_admin_actions(),
		_admin_roster_fields())
	if _admin_menu != null:
		_apply_persisted_admin_preferences()
		_admin_menu.open_changed.connect(_on_admin_menu_open_changed)
		if not Backend.admin_roster_changed.is_connected(_on_admin_roster_changed):
			Backend.admin_roster_changed.connect(_on_admin_roster_changed)
	if _awaiting_snapshot:
		player.input_frozen = true
		hud.show_message("SYNCING ROUTE WITH HOST...")
	else:
		if _loaded_from_save:
			_sync_stream_progress()
			_sync_drop_nodes()
			hud.show_message("LOCAL SAVE RESTORED")
	_update_hud()


func _on_background_update_ready(_path: String) -> void:
	hud.show_message("UPDATE READY // WILL APPLY AFTER THIS RUN")


func _on_admin_ticket_changed(ready: bool, room_code: String,
		message: String) -> void:
	if not ready or room_code != RoomState.code or not RoomState.online \
			or RoomState.is_host or _remotes == null:
		return
	_remotes.request_interaction({"what": "admin_auth"})
	hud.show_message(message)


func _on_admin_ticket_verified(request_id: int, authorized: bool,
		expires_in: int, permissions: PackedStringArray, message: String) -> void:
	if not _pending_admin_requests.has(request_id):
		return
	var pending: Dictionary = _pending_admin_requests[request_id]
	_pending_admin_requests.erase(request_id)
	var peer_id := int(pending.get("peer_id", 0))
	if not RoomState.is_host or peer_id <= 1 or not RoomState.peers.has(peer_id):
		return
	if not authorized:
		_remotes.send_player_event(peer_id, {"what": "message",
			"message": "ADMIN REQUEST REJECTED // %s" % message})
		return
	_remotes.authorize_admin_peer(peer_id, expires_in, permissions)
	_apply_verified_admin_request(peer_id, pending.get("event", {}))


func _apply_verified_admin_request(peer_id: int, event: Dictionary) -> void:
	match String(event.get("what", "")):
		"admin_auth":
			_remotes.send_player_event(peer_id, {"what": "message",
				"message": "ADMIN ROOM PROOF VERIFIED"})
		"admin_world":
			_accept_stream_admin(peer_id, event)


func _process(delta: float) -> void:
	if RoomState.online and not RoomState.is_host and Backend.admin_authorized():
		_admin_ticket_refresh_elapsed += delta
		if _admin_ticket_refresh_elapsed >= 5.0:
			_admin_ticket_refresh_elapsed = 0.0
			if Backend.admin_ticket_for_room(RoomState.code).is_empty():
				Backend.request_admin_ticket(RoomState.code)
	var admin_open := _admin_menu != null and _admin_menu.is_open()
	var story_open: bool = _story != null and _story.is_active()
	if RoomState.reconnect_active:
		_awaiting_snapshot = true
		if not _reconnect_notice_shown:
			_reconnect_notice_shown = true
			hud.show_message("HOST SIGNAL LOST // RECONNECTING...")
	elif _reconnect_notice_shown:
		_reconnect_notice_shown = false
		hud.show_message("HOST SIGNAL RESTORED // SYNCING ROUTE...")
	# Being held by a hunter is the one moment pausing would be an exploit, so
	# the menu is locked out for the length of the struggle.
	pause_menu.tap_to_pause = not GameState.escape_active
	if _awaiting_snapshot or RoomState.reconnect_active or _death_screen_open \
			or GameState.escape_active or admin_open \
			or hud.inventory_is_open() or hud.map_is_open() \
			or (_room_chat != null and _room_chat.is_open()) or story_open:
		player.input_frozen = true
	if Input.is_action_just_pressed("inventory") and not admin_open and not story_open \
			and not GameState.escape_active and not _awaiting_snapshot \
			and not pause_menu.is_open():
		hud.toggle_inventory()
	if Input.is_action_just_pressed("toggle_map") and not admin_open and not story_open \
			and not GameState.escape_active and not _awaiting_snapshot:
		hud.set_inventory_open(false)
		hud.toggle_map_overlay()
	GameState.tick_escape_cooldowns(delta)
	if GameState.escape_active:
		_update_escape_struggle(delta)
	if get_tree().paused:
		return
	_update_run_statistics(delta)
	_update_anti_idle_pressure(delta)
	_capture_cooldown = maxf(0.0, _capture_cooldown - delta)
	var level := facility.current_level()
	GameState.depth = -level
	var data := facility.current_chunk_data()
	_update_map_discovery(data)
	# Story presentation freezes both input and host AI. This preserves the
	# original dialog/cutscene contract instead of letting a hunter capture a
	# player while every client's choices are on screen.
	if _story != null and _story.is_active():
		player.velocity = Vector3.ZERO
		_update_hud()
		return
	_clear_reached_waypoints(level)
	if not _awaiting_snapshot:
		_update_checkpoint(data)
	_authority_refresh_elapsed += delta
	if _remotes.simulates() and _authority_refresh_elapsed >= AUTHORITY_REFRESH_SECONDS:
		_authority_refresh_elapsed = 0.0
		_refresh_hunter_stream()
	if _remotes.simulates():
		_hunter_simulation_accumulator = minf(
			_hunter_simulation_accumulator + delta,
			HUNTER_SIMULATION_STEP * HUNTER_MAX_CATCH_UP_STEPS)
		while _hunter_simulation_accumulator >= HUNTER_SIMULATION_STEP:
			_update_hunters(HUNTER_SIMULATION_STEP, data)
			_hunter_simulation_accumulator -= HUNTER_SIMULATION_STEP
		_hunter_broadcast_elapsed += delta
		if _hunter_broadcast_elapsed >= HUNTER_BROADCAST_SECONDS:
			_hunter_broadcast_elapsed = fmod(_hunter_broadcast_elapsed,
				HUNTER_BROADCAST_SECONDS)
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
	_discover_loaded_chunks()
	if not (_remotes != null and _remotes.simulates()):
		_navigation = StreamedHunterNavigation.new(facility.generator, coord.y,
			world_state)
		_navigation.refresh(coord.y, facility.loaded_horizontal_coords())
	if _navigation != null and _remotes != null and _remotes.simulates():
		_refresh_hunter_stream()
	var region := String(data.get("region", "maze")).to_upper()
	hud.depth_label.text = "LEVEL %+d // %s" % [coord.y, region]
	hud.update_infinite_status(GameState.relays_collected,
		facility.loaded_chunk_count(), _live_danger_percent(data))


func _on_pickup_claimed(entity_id: String) -> void:
	# Collection-specific feedback is shown when the authoritative event is applied.
	pass


func _update_hud() -> void:
	var data := facility.current_chunk_data()
	var safe := _player_in_intact_safe_room(data)
	hud.update_infinite_status(GameState.relays_collected,
		facility.loaded_chunk_count(), _live_danger_percent(data))
	hud.update_battery(player.lamp_charge, player.flashlight_enabled, safe,
		player.movement_mode)
	hud.update_stamina(player.stamina, player.exhausted)
	var thermal := _temperature_hunter_proximity()
	hud.update_meters(player.meters, thermal.x, thermal.y)
	hud.update_inventory(player.selected_inventory_item(), player.taser_cooldown,
		player.inventory_durability_snapshot(), player.inventory_owned_snapshot(),
		player.inventory_order_snapshot(), player.inventory_max_durability_snapshot(),
		player.selected_inventory_slot, player.inventory_slot_durability_snapshot())
	_update_streamed_maps()
	_present_afk_void_warning()


func _temperature_hunter_proximity() -> Vector2:
	var strengths := Vector2.ZERO # x = heat, y = cold
	var local_level := facility.current_level()
	var player_position := player.grid_position()
	for entity_id_value in _hunter_views:
		var entity_id := String(entity_id_value)
		if int(_hunter_levels.get(entity_id, 999999)) != local_level:
			continue
		var view := _hunter_views.get(entity_id) as HunterView3D
		if view == null or view.brain == null or not view.brain.active:
			continue
		var hunter_id := String(view.brain.hunter_id)
		if hunter_id not in ["solyth", "wynelle"]:
			continue
		var distance := view.brain.position.distance_to(player_position)
		var strength := clampf(1.0 - maxf(0.0, distance - 2.0) \
			/ (TEMPERATURE_HUNTER_EFFECT_RADIUS - 2.0), 0.0, 1.0)
		if hunter_id == "solyth":
			strengths.x = maxf(strengths.x, strength)
		else:
			strengths.y = maxf(strengths.y, strength)
	return strengths


func _admin_status() -> String:
	var coord := facility.current_chunk_coord()
	var data := facility.current_chunk_data()
	var safe_text := "NONE"
	if bool(data.get("safe_room", false)):
		var status := world_state.safe_room_status(data.get("safe_room_data", {}))
		safe_text = "%d%%%s" % [int(status.get("integrity", 0)),
			" BREACHED" if bool(status.get("breached", false)) else ""]
	var pressure_remaining := maxi(0, ceili(
		GameConfig.anti_idle_hunter_seconds(RoomState.difficulty_id()) \
		- _relay_inactivity_seconds))
	var afk_remaining := maxi(0, ceili(
		GameConfig.anti_afk_hunter_seconds(RoomState.difficulty_id()) \
		- _party_afk_seconds))
	var result := "ROUTE DEBUG\nCHUNK %d:%d:%d  %s\nLOADED %d  DISCOVERED %d  HUNTERS %d\nSAFE %s  CHECKPOINT %s\nPRESSURE %ds  SURGES %d\nMAP REVEAL %s" % [
		coord.x, coord.y, coord.z, String(data.get("region", "maze")).to_upper(),
		facility.loaded_chunk_count(), _discovered_chunks.size(), _hunter_views.size(), safe_text,
		world_state.active_checkpoint if not world_state.active_checkpoint.is_empty()
		else "NONE", mini(pressure_remaining, afk_remaining),
		_anti_idle_spawn_sequence,
		"ON" if _admin_reveal_map else "OFF"]
	if Backend.admin_owner_authorized():
		result += "\nADMIN ROSTER %s" % Backend.admin_roster_summary()
	return result


func _hunter_admin_labels(ids: Array) -> Dictionary:
	var labels := {}
	for hunter_id_value in ids:
		var hunter_id := String(hunter_id_value)
		labels[hunter_id] = String(HunterRoster.get_identity(hunter_id).get(
			"display_name", hunter_id))
	return labels


func _infinite_admin_actions() -> Array:
	return [
		{"label": "REFRESH ADMIN ROSTER", "action": Backend.admin_roster_refresh,
			"owner_only": true},
		{"heading": "CREATIVE INVENTORY", "label": "CREATIVE INVENTORY",
			"permission": "inventory",
			"items": PlayerController3D.COLLECTIBLE_ITEMS,
			"labels": PlayerController3D.INVENTORY_LABELS,
			"action": _admin_give_item},
		{"heading": "PLAYER TOOLS", "permission": "player"},
		{"label": "FULL LAMP", "permission": "player", "action": func() -> void:
			player.restore_lamp(GameConfig.MAX_LAMP_CHARGE)},
		{"label": "RESTORE PLAYER", "action": _admin_restore_player,
			"permission": "player"},
		{"label": "CLEAR STUN + COOLDOWNS", "permission": "player",
			"action": func() -> void:
			player.stun_timer = 0.0
			player.taser_cooldown = 0.0},
		{"label": "TELEPORT TO START", "permission": "player",
			"action": func() -> void:
			_admin_teleport_to(facility.spawn_position())},
		{"label": "TELEPORT TO CHECKPOINT", "permission": "player",
			"action": func() -> void:
			_admin_teleport_to(_checkpoint_world_position())},
		{"label": "TOGGLE NO TARGET", "action": _admin_toggle_no_target,
			"permission": "player",
			"state": func() -> bool: return player.admin_no_target},
		{"label": "TOGGLE GOD MODE", "action": _admin_toggle_god_mode,
			"permission": "player",
			"state": func() -> bool: return player.admin_god_mode},
		{"label": "TOGGLE NOCLIP", "action": _admin_toggle_noclip,
			"permission": "player",
			"state": func() -> bool: return player.admin_noclip},
		{"heading": "WORLD + HUNTERS", "permission": "world"},
		{"label": "GRANT RELAY", "permission": "world", "action": func() -> void:
			_admin_world_action("grant_relay")},
		{"label": "ALL LOADED RELAYS", "permission": "world",
			"action": func() -> void: _admin_world_action("all_relays")},
		{"label": "STUN ALL HUNTERS", "permission": "hunters",
			"action": func() -> void: _admin_world_action("stun_hunters")},
		{"label": "WAKE ALL HUNTERS", "permission": "hunters",
			"action": func() -> void: _admin_world_action("wake_hunters")},
		{"label": "CALM ALL HUNTERS", "permission": "hunters",
			"action": func() -> void: _admin_world_action("calm_hunters")},
		{"heading": "SUMMON A-Z HUNTER", "items": HunterRoster.A_Z_IDS,
			"permission": "hunters",
			"labels": _hunter_admin_labels(HunterRoster.A_Z_IDS),
			"action": _admin_summon_hunter},
		{"heading": "REMOVE A-Z HUNTER // ALL MATCHES",
			"permission": "hunters",
			"items": HunterRoster.A_Z_IDS,
			"labels": _hunter_admin_labels(HunterRoster.A_Z_IDS),
			"action": _admin_remove_hunter},
		{"heading": "SUMMON VOID HUNTER", "items": HunterRoster.VOID_IDS,
			"permission": "hunters",
			"labels": _hunter_admin_labels(HunterRoster.VOID_IDS),
			"action": _admin_summon_hunter},
		{"heading": "REMOVE VOID HUNTER // ALL MATCHES",
			"permission": "hunters",
			"items": HunterRoster.VOID_IDS,
			"labels": _hunter_admin_labels(HunterRoster.VOID_IDS),
			"action": _admin_remove_hunter},
		{"label": "DAMAGE CHECKPOINT", "permission": "world",
			"action": func() -> void: _admin_world_action("damage_checkpoint")},
		{"label": "REPAIR CHECKPOINT", "permission": "world",
			"action": func() -> void: _admin_world_action("repair_checkpoint")},
		{"label": "TOGGLE ALL REGION LIGHTS", "permission": "world",
			"action": func() -> void:
				facility.set_all_lights(not facility.all_lights_enabled()),
			"state": func() -> bool: return facility.all_lights_enabled()},
		{"heading": "STORY / CUTSCENES", "permission": "world"},
		{"heading": "PLAY STORY / CUTSCENE", "permission": "world",
			"items": _story.admin_scene_ids() if _story != null else [],
			"labels": _story.admin_scene_labels() if _story != null else {},
			"action": _admin_start_story},
		{"label": "STOP STORY / CUTSCENE", "permission": "world",
			"action": _admin_stop_story},
		{"label": "RESET STORY STATE", "permission": "world",
			"action": _admin_reset_story},
		{"heading": "VISUAL TOOLS", "permission": "visual"},
		{"label": "TOGGLE MAP REVEAL", "action": _admin_toggle_map_reveal,
			"permission": "visual",
			"state": func() -> bool: return _admin_reveal_map},
		{"label": "TOGGLE HUNTER REVEAL", "action": _admin_toggle_hunter_reveal,
			"permission": "visual",
			"state": func() -> bool: return _admin_reveal_hunters},
		{"label": "TOGGLE PIXEL EFFECT", "action": _admin_toggle_pixel_effect,
			"permission": "visual",
			"state": func() -> bool: return pixel_signal_effect.admin_enabled()},
		{"label": "PIXEL EFFECT +", "permission": "visual", "action": func() -> void:
			Settings.set_pixel_effect_percent(Settings.pixel_effect_percent + 10.0)},
		{"label": "PIXEL EFFECT -", "permission": "visual", "action": func() -> void:
			Settings.set_pixel_effect_percent(Settings.pixel_effect_percent - 10.0)},
	]


func _admin_roster_fields() -> Array:
	return [
		{"label": "ADD / UPDATE LIMITED ADMIN",
			"placeholder": "USERNAME:player,world,hunters,visual,inventory",
			"on_submit": Backend.admin_roster_set_spec, "owner_only": true},
		{"label": "REMOVE LIMITED ADMIN", "placeholder": "USERNAME",
			"on_submit": Backend.admin_roster_remove, "owner_only": true},
	]


func _on_admin_roster_changed(ok: bool, message: String, _roster: Array) -> void:
	hud.show_message(("ADMIN ROSTER // " if ok else "ADMIN ROSTER FAILED // ") + message)


func _on_admin_menu_open_changed(shown: bool) -> void:
	if shown:
		hud.set_inventory_open(false)
		if _room_chat != null:
			_room_chat.close()
	player.velocity = Vector3.ZERO
	player.input_frozen = shown or _awaiting_snapshot \
		or _death_screen_open \
		or (pause_menu != null and pause_menu.is_open()) \
		or hud.inventory_is_open() \
		or (_room_chat != null and _room_chat.is_open()) \
		or (_story != null and _story.is_active()) \
		or player.hidden or player.is_stunned()


func _admin_teleport_to(destination: Vector3) -> void:
	# A teleport is also an exit from any modal/navigation state which was tied
	# to the old floor. Leaving the admin layer open used to keep input frozen,
	# while the fullscreen map still held the now-evicted floor and drew blank.
	hud.set_inventory_open(false)
	hud.set_map_open(false)
	if _room_chat != null:
		_room_chat.close()
	if _admin_menu != null:
		_admin_menu.close()
	player.velocity = Vector3.ZERO
	player.global_position = destination
	facility.refresh_at_tracked_player()
	_discover_loaded_chunks()
	var data := facility.current_chunk_data()
	_update_map_discovery(data)
	if _admin_reveal_map:
		_set_admin_map_reveal(true)
	hud.plan.reset_view()
	_waypoint_route_key = ""
	_waypoint_grid_signature = ""
	_update_streamed_maps()
	player.input_frozen = _awaiting_snapshot or _death_screen_open \
		or (pause_menu != null and pause_menu.is_open()) \
		or (_story != null and _story.is_active()) \
		or player.hidden or player.is_stunned()


func _dismiss_gameplay_overlay() -> bool:
	if _admin_menu != null and _admin_menu.is_open():
		_admin_menu.close()
		return true
	if hud.map_is_open():
		hud.map_overlay.visible = false
		return true
	if hud.inventory_is_open():
		hud.set_inventory_open(false)
		return true
	if _room_chat != null and _room_chat.is_open():
		_room_chat.close()
		return true
	return false


func _on_inventory_open_changed(_shown: bool) -> void:
	if _shown and hud.map_is_open():
		hud.map_overlay.visible = false
	if _shown and _room_chat != null:
		_room_chat.close()
	player.velocity = Vector3.ZERO
	player.input_frozen = _awaiting_snapshot or hud.inventory_is_open() \
		or _death_screen_open \
		or hud.map_is_open() \
		or (_admin_menu != null and _admin_menu.is_open()) \
		or (pause_menu != null and pause_menu.is_open()) \
		or (_room_chat != null and _room_chat.is_open()) \
		or (_story != null and _story.is_active()) \
		or player.hidden or player.is_stunned()


func _on_map_open_changed(_shown: bool) -> void:
	player.velocity = Vector3.ZERO
	player.input_frozen = _awaiting_snapshot or hud.map_is_open() \
		or _death_screen_open \
		or hud.inventory_is_open() \
		or (_admin_menu != null and _admin_menu.is_open()) \
		or (pause_menu != null and pause_menu.is_open()) \
		or (_room_chat != null and _room_chat.is_open()) \
		or (_story != null and _story.is_active()) \
		or player.hidden or player.is_stunned()


func _on_chat_open_changed(_shown: bool) -> void:
	if _shown:
		hud.set_inventory_open(false)
	player.velocity = Vector3.ZERO
	player.input_frozen = _awaiting_snapshot \
		or _death_screen_open \
		or (_room_chat != null and _room_chat.is_open()) \
		or hud.inventory_is_open() \
		or (_admin_menu != null and _admin_menu.is_open()) \
		or (pause_menu != null and pause_menu.is_open()) \
		or (_story != null and _story.is_active()) \
		or player.hidden or player.is_stunned()


func _on_pause_opened() -> void:
	hud.set_inventory_open(false)
	player.input_frozen = true


func _on_pause_resumed() -> void:
	player.input_frozen = _awaiting_snapshot or hud.inventory_is_open() \
		or _death_screen_open or hud.map_is_open() \
		or (_admin_menu != null and _admin_menu.is_open()) \
		or (_story != null and _story.is_active()) \
		or player.hidden or player.is_stunned()


func _on_story_state_published(state: Dictionary) -> void:
	if RoomState.online and not RoomState.is_host:
		return
	_publish_stream_event({"what": "stream_story", "state": state})


func _on_story_active_changed(active: bool) -> void:
	if active:
		hud.set_inventory_open(false)
		hud.set_map_open(false)
		if _room_chat != null:
			_room_chat.close()
		if _admin_menu != null:
			_admin_menu.close()
	player.velocity = Vector3.ZERO
	player.input_frozen = active or _awaiting_snapshot or _death_screen_open \
		or hud.inventory_is_open() or hud.map_is_open() \
		or (_admin_menu != null and _admin_menu.is_open()) \
		or (pause_menu != null and pause_menu.is_open()) \
		or (_room_chat != null and _room_chat.is_open()) \
		or player.hidden or player.is_stunned()


func _pause_save_new(display_name: String) -> Dictionary:
	var denial := _save_write_denial()
	if not denial.is_empty():
		return {"ok": false, "message": denial}
	return RunSaves.save_new(display_name, _build_route_save_payload())


func _pause_save_overwrite(slot_id: String) -> Dictionary:
	var denial := _save_write_denial()
	if not denial.is_empty():
		return {"ok": false, "message": denial}
	return RunSaves.overwrite(slot_id, _build_route_save_payload())


func _pause_save_load(slot_id: String) -> Dictionary:
	var denial := _save_load_denial()
	if not denial.is_empty():
		return {"ok": false, "message": denial}
	var result := RunSaves.queue_load(slot_id)
	if not bool(result.get("ok", false)):
		return result
	var payload: Dictionary = result.get("payload", {})
	RoomState.seed_text = String(payload.get("seed_text", RoomState.seed_text))
	RoomState.mode = RoomState.Mode.DEFAULT
	RoomState.map_scale = RoomState.Scale.INFINITE
	RoomState.difficulty = clampi(int(payload.get("difficulty",
		RoomState.Difficulty.STANDARD)), RoomState.Difficulty.RELAXED,
		RoomState.Difficulty.HARD)
	RoomState.session_active = true
	RoomState.broadcast()
	RoomState.status_message = "LOADING LOCAL SAVE // %s" % String(
		result.get("name", "ROUTE"))
	get_tree().paused = false
	call_deferred("_open_queued_route_save")
	return {"ok": true, "message": "LOADING SAVED ROUTE",
		"slot_id": slot_id}


func _save_write_denial() -> String:
	if RoomState.online and not RoomState.is_host:
		return "ONLY THE ROOM HOST CAN SAVE THE SHARED ROUTE"
	return ""


func _save_load_denial() -> String:
	if RoomState.online and not RoomState.is_host:
		return "ONLY THE ROOM HOST CAN LOAD A ROUTE"
	if RoomState.online and RoomState.peers.size() > 1:
		return "CO-OP WORLD CANNOT BE REPLACED WHILE GUESTS ARE CONNECTED"
	return ""


func _open_queued_route_save() -> void:
	get_tree().change_scene_to_file(RoomState.ROUTE_LOADING_SCENE)


func _build_route_save_payload() -> Dictionary:
	_collect_hunter_report()
	_run_statistics["rooms_discovered"] = _discovered_rooms.size()
	_run_statistics["relays_collected"] = GameState.relays_collected
	return {
		"schema": LOCAL_SAVE_SCHEMA,
		"kind": "infinite_route",
		"authority": {
			"source": "online_host" if RoomState.online else "offline",
			"party_size": maxi(1, RoomState.peers.size()) if RoomState.online else 1,
		},
		"seed_text": RoomState.seed_text,
		"run_seed": RoomState.run_seed(),
		"difficulty": RoomState.difficulty,
		"difficulty_id": RoomState.difficulty_id(),
		"game_state": {
			"score": GameState.score,
			"coins": GameState.coins,
			"relays_collected": GameState.relays_collected,
			"relays_sabotaged": GameState.relays_sabotaged,
			"depth": GameState.depth,
		},
		"world_state": world_state.snapshot(),
		"player": player.run_save_snapshot(),
		"discovery": {
			"chunks": _discovered_chunks.duplicate(true),
			"rooms": _discovered_rooms.duplicate(true),
			"markers": _discovered_map_markers.duplicate(true),
			"waypoints": _active_waypoints(),
		},
		"story": _story.snapshot() if _story != null else {"active": false},
		"anti_idle": {
			"relay_seconds": _relay_inactivity_seconds,
			"afk_seconds": _party_afk_seconds,
			"relay_count": _anti_idle_last_relay_count,
			"spawn_sequence": _anti_idle_spawn_sequence,
		},
		"statistics": _run_statistics.duplicate(true),
	}


func _adopt_route_save_before_stream(payload: Dictionary) -> bool:
	if int(payload.get("schema", 0)) != LOCAL_SAVE_SCHEMA \
			or String(payload.get("kind", "")) != "infinite_route" \
			or int(payload.get("run_seed", 0)) != RoomState.run_seed():
		return false
	var saved_world = payload.get("world_state")
	var saved_player = payload.get("player")
	if not saved_world is Dictionary or not saved_player is Dictionary \
			or not world_state.adopt(saved_world) \
			or not player.restore_run_save(saved_player):
		return false
	var progress = payload.get("game_state", {})
	if progress is Dictionary:
		GameState.score = maxi(0, int(progress.get("score", 0)))
		GameState.coins = maxi(0, int(progress.get("coins", 0)))
		GameState.relays_collected = maxi(0,
			int(progress.get("relays_collected", 0)))
		GameState.relays_sabotaged = maxi(0,
			int(progress.get("relays_sabotaged", 0)))
		GameState.depth = int(progress.get("depth", 1))
	var discovery = payload.get("discovery", {})
	if discovery is Dictionary:
		var chunks = discovery.get("chunks", {})
		var rooms = discovery.get("rooms", {})
		var markers = discovery.get("markers", {})
		var waypoints = discovery.get("waypoints", [])
		if chunks is Dictionary:
			_discovered_chunks = chunks.duplicate(true)
		if rooms is Dictionary:
			_discovered_rooms = rooms.duplicate(true)
		if markers is Dictionary:
			_discovered_map_markers = markers.duplicate(true)
		if waypoints is Array and not RoomState.online:
			_map_waypoints = waypoints.duplicate(true)
	var anti_idle = payload.get("anti_idle", {})
	if anti_idle is Dictionary:
		_relay_inactivity_seconds = maxf(0.0,
			float(anti_idle.get("relay_seconds", 0.0)))
		_party_afk_seconds = maxf(0.0,
			float(anti_idle.get("afk_seconds", 0.0)))
		_anti_idle_last_relay_count = maxi(0,
			int(anti_idle.get("relay_count", GameState.relays_collected)))
		_anti_idle_spawn_sequence = maxi(0,
			int(anti_idle.get("spawn_sequence", 0)))
	var story = payload.get("story", {})
	if story is Dictionary and _story != null:
		_story.adopt_snapshot(story)
	var statistics = payload.get("statistics", {})
	if statistics is Dictionary and not statistics.is_empty():
		_run_statistics = statistics.duplicate(true)
	_waypoint_route_key = ""
	_waypoint_grid_signature = ""
	return true


func _update_run_statistics(delta: float) -> void:
	_run_statistics["elapsed_seconds"] = maxf(0.0,
		float(_run_statistics.get("elapsed_seconds", 0.0)) + delta)
	var travel := Vector2(player.global_position.x - _statistics_last_position.x,
		player.global_position.z - _statistics_last_position.z).length()
	# Stair transfers are valid travel; teleports/load corrections are not.
	if travel <= 4.0:
		_run_statistics["distance_m"] = maxf(0.0,
			float(_run_statistics.get("distance_m", 0.0)) + travel)
	_statistics_last_position = player.global_position
	_run_statistics["rooms_discovered"] = _discovered_rooms.size()
	_run_statistics["relays_collected"] = GameState.relays_collected
	var levels: Dictionary = _run_statistics.get("visited_levels", {})
	levels[str(facility.current_level())] = true
	_run_statistics["visited_levels"] = levels
	var encountered: Dictionary = _run_statistics.get("encountered_hunters", {})
	for entity_id_value in _hunter_views:
		var entity_id := String(entity_id_value)
		var view := _hunter_views[entity_id] as HunterView3D
		if view != null and view.brain != null and view.brain.active \
				and int(_hunter_levels.get(entity_id, 999999)) == facility.current_level() \
				and view.brain.position.distance_to(player.grid_position()) <= 14.0:
			encountered[entity_id] = String(view.brain.hunter_id)
	_run_statistics["encountered_hunters"] = encountered
	_run_statistics["hunters_encountered"] = encountered.size()


func _pause_statistics() -> Dictionary:
	var levels: Dictionary = _run_statistics.get("visited_levels", {})
	return {
		"TIME SURVIVED": _format_run_duration(float(
			_run_statistics.get("elapsed_seconds", 0.0))),
		"DISTANCE TRAVELLED": "%d m" % roundi(float(
			_run_statistics.get("distance_m", 0.0))),
		"CURRENT FLOOR": "%+d" % facility.current_level(),
		"FLOORS VISITED": str(levels.size()),
		"ROOMS DISCOVERED": str(_discovered_rooms.size()),
		"RELAYS COLLECTED": str(GameState.relays_collected),
		"ITEMS COLLECTED": str(int(_run_statistics.get("items_collected", 0))),
		"HUNTERS ENCOUNTERED": str(int(
			_run_statistics.get("hunters_encountered", 0))),
		"CHASES STARTED": str(int(_run_statistics.get("chases_started", 0))),
		"CHECKPOINTS ACTIVATED": str(int(
			_run_statistics.get("checkpoints_activated", 0))),
		"ROOM CODE": RoomState.code,
		"ROUTE SEED": RoomState.seed_text,
		"DIFFICULTY": RoomState.difficulty_id().to_upper(),
	}


func _format_run_duration(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func _admin_toggle_map_reveal() -> void:
	_set_admin_map_reveal(not _admin_reveal_map)
	Settings.set_admin_preference("map_reveal", _admin_reveal_map)


func _set_admin_map_reveal(enabled: bool) -> void:
	_admin_reveal_map = enabled
	if not _admin_reveal_map or facility.generator == null:
		return
	var center := facility.current_chunk_coord()
	# Infinity has no complete map to reveal. Admin reveal exposes a generous,
	# deterministic local survey and keeps extending that survey as the runner
	# moves, without pretending the unbounded world has an edge.
	for z in range(center.z - 4, center.z + 5):
		for x in range(center.x - 4, center.x + 5):
			var coord := Vector3i(x, center.y, z)
			if not facility.generator.is_chunk_allowed(coord):
				continue
			_remember_discovered_chunk(coord, facility.generator.chunk(coord))


func _apply_persisted_admin_preferences() -> void:
	var player_tools := Build.admin_permission("player")
	var visual_tools := Build.admin_permission("visual")
	player.admin_no_target = player_tools and Settings.admin_preference("no_target")
	player.admin_god_mode = player_tools and Settings.admin_preference("god_mode")
	player.set_admin_noclip(player_tools and Settings.admin_preference("noclip"))
	_set_admin_map_reveal(visual_tools and Settings.admin_preference("map_reveal"))
	_admin_reveal_hunters = visual_tools and Settings.admin_preference("hunter_reveal")
	pixel_signal_effect.set_admin_enabled(
		visual_tools and Settings.admin_preference("pixel_effect_enabled"))


func _admin_toggle_no_target() -> void:
	player.admin_no_target = not player.admin_no_target
	Settings.set_admin_preference("no_target", player.admin_no_target)


func _admin_toggle_god_mode() -> void:
	player.admin_god_mode = not player.admin_god_mode
	Settings.set_admin_preference("god_mode", player.admin_god_mode)


func _admin_toggle_noclip() -> void:
	player.set_admin_noclip(not player.admin_noclip)
	Settings.set_admin_preference("noclip", player.admin_noclip)


func _admin_toggle_hunter_reveal() -> void:
	_admin_reveal_hunters = not _admin_reveal_hunters
	Settings.set_admin_preference("hunter_reveal", _admin_reveal_hunters)


func _admin_toggle_pixel_effect() -> void:
	pixel_signal_effect.set_admin_enabled(not pixel_signal_effect.admin_enabled())
	Settings.set_admin_preference("pixel_effect_enabled",
		pixel_signal_effect.admin_enabled())


## Mirrors main_3d.gd's _force_disable_admin_cheats so the test harness also
## guarantees noclip/god/no-target/etc are reset on every termination path.
func _force_disable_admin_cheats() -> void:
	if player != null:
		player.admin_no_target = false
		player.admin_god_mode = false
		player.set_admin_noclip(false)
	_admin_reveal_hunters = false
	_admin_reveal_map = false
	_set_admin_map_reveal(false)
	if pixel_signal_effect != null:
		pixel_signal_effect.set_admin_enabled(false)
	# Runtime only; do not mutate persisted prefs (tests rely on re-apply on load).


func _discover_loaded_chunks() -> void:
	if facility.generator == null:
		return
	for coord in facility.loaded_horizontal_coords():
		_remember_discovered_chunk(coord, facility.generator.chunk(coord))
	if _admin_reveal_map:
		var center := facility.current_chunk_coord()
		for z in range(center.z - 4, center.z + 5):
			for x in range(center.x - 4, center.x + 5):
				var coord := Vector3i(x, center.y, z)
				if not facility.generator.is_chunk_allowed(coord):
					continue
				_remember_discovered_chunk(coord, facility.generator.chunk(coord))


func _remember_discovered_chunk(coord: Vector3i, data: Dictionary) -> void:
	var side := StreamedRouteGenerator.CHUNK_SIZE
	var walls := PackedByteArray()
	walls.resize(side * side)
	var grid: Array = data.get("grid", [])
	if grid.size() != side:
		return
	for z in side:
		var row: Array = grid[z]
		if row.size() != side:
			return
		for x in side:
			walls[z * side + x] = 1 if int(row[x]) != 0 else 0
	var visible_pickups := []
	for value in data.get("pickups", []):
		var pickup: Dictionary = value
		if world_state.pickup_available(String(pickup.get("id", ""))):
			var pickup_id := String(pickup.get("id", ""))
			visible_pickups.append({"id": pickup_id,
				"discovery_id": pickup_id,
				"cell": pickup.get("cell", Vector2i.ZERO),
				"kind": String(pickup.get("kind", ""))})
	var visible_props := []
	for value in data.get("region_props", []):
		var prop: Dictionary = value
		if bool(prop.get("room_door", false)):
			continue
		var prop_id := String(prop.get("id", ""))
		if prop_id.is_empty():
			continue
		visible_props.append({"id": prop_id, "discovery_id": prop_id,
			"cell": prop.get("cell", Vector2i.ZERO),
			"kind": "prop", "type": String(prop.get("type", ""))})
	for value in data.get("fixtures", []):
		var fixture: Dictionary = value
		var fixture_id := String(fixture.get("id", ""))
		if fixture_id.is_empty():
			continue
		visible_props.append({"id": fixture_id, "discovery_id": fixture_id,
			"cell": fixture.get("cell", Vector2i.ZERO),
			"kind": String(fixture.get("kind", "fixture")),
			"type": String(fixture.get("kind", "fixture"))})
	var visible_stairs := []
	for value in data.get("stairs", []):
		var stair: Dictionary = value
		visible_stairs.append({"cell": stair.get("cell", Vector2i.ZERO),
			"direction": String(stair.get("direction", ""))})
	_discovered_chunks[coord] = {"walls": walls, "pickups": visible_pickups,
		"props": visible_props,
		"stairs": visible_stairs,
		"spawn": facility.generator.spawn_cell() if coord == Vector3i.ZERO \
			else Vector2i(-1, -1),
		"region": String(data.get("region", "maze"))}


func _local_map_chunks() -> Dictionary:
	var result := {}
	var center := facility.current_chunk_coord()
	for coord_value in _discovered_chunks:
		var coord: Vector3i = coord_value
		if coord.y == center.y and absi(coord.x - center.x) <= 1 \
				and absi(coord.z - center.z) <= 1:
			result[coord] = _map_chunk_with_available_pickups(
				_discovered_chunks[coord] as Dictionary)
	return result


func _map_chunk_with_available_pickups(chunk: Dictionary) -> Dictionary:
	# Discovery persists geometry, not already-consumed objectives. Consult the
	# authoritative mutation ledger whenever a map snapshot is prepared so a
	# local claim, remote claim, admin grant, or late-join snapshot all remove the
	# same marker without rediscovering/reloading the chunk.
	var result := chunk.duplicate(false)
	var available := []
	for pickup_value in chunk.get("pickups", []):
		var pickup: Dictionary = pickup_value
		var entity_id := String(pickup.get("id", ""))
		var discovery_id := String(pickup.get("discovery_id", ""))
		if not entity_id.is_empty() and world_state.pickup_available(entity_id) \
				and (discovery_id.is_empty() or _admin_reveal_map \
				or _discovered_map_markers.has(discovery_id)):
			available.append(pickup)
	result["pickups"] = available
	var visible_props := []
	for prop_value in chunk.get("props", []):
		var prop: Dictionary = prop_value
		var discovery_id := String(prop.get("discovery_id", ""))
		if discovery_id.is_empty() or _admin_reveal_map \
				or _discovered_map_markers.has(discovery_id):
			visible_props.append(prop)
	result["props"] = visible_props
	return result


func _update_map_discovery(data: Dictionary) -> void:
	if data.is_empty() or facility.generator == null:
		return
	var coord: Vector3i = data.get("coord", facility.current_chunk_coord())
	var local := StreamedHunterNavigation.local_cell(Vector2i(
		floori(player.global_position.x), floori(player.global_position.z)))
	var newly_discovered := false
	for room_value in data.get("rooms", []):
		var room: Dictionary = room_value
		var rect: Rect2i = room.get("rect", Rect2i())
		if not rect.has_point(local):
			continue
		var room_id := String(room.get("id", ""))
		if not room_id.is_empty() and not _discovered_rooms.has(room_id):
			_discovered_rooms[room_id] = true
			newly_discovered = true
		for collection_name in ["pickups", "region_props", "fixtures"]:
			for marker_value in data.get(collection_name, []):
				var marker: Dictionary = marker_value
				var marker_cell: Vector2i = marker.get("cell", Vector2i.ZERO)
				if rect.has_point(marker_cell):
					var marker_id := String(marker.get("id", ""))
					if not marker_id.is_empty():
						_discovered_map_markers[marker_id] = true
	# Corridor objects reveal only at ordinary sight/interact distance.
	for collection_name in ["pickups", "region_props", "fixtures"]:
		for marker_value in data.get(collection_name, []):
			var marker: Dictionary = marker_value
			var marker_cell: Vector2i = marker.get("cell", Vector2i.ZERO)
			if Vector2(marker_cell).distance_to(Vector2(local)) \
					<= MAP_DISCOVERY_NEARBY_RADIUS:
				var marker_id := String(marker.get("id", ""))
				if not marker_id.is_empty():
					_discovered_map_markers[marker_id] = true
	if newly_discovered or not _discovered_chunks.has(coord):
		_remember_discovered_chunk(coord, data)


func _on_map_waypoint_requested(world_position: Vector2, level: int) -> void:
	var waypoint_at := Vector2(floori(world_position.x) + .5,
		floori(world_position.y) + .5)
	if RoomState.online:
		var event := {"what": "stream_waypoint", "at": waypoint_at, "level": level}
		if RoomState.is_host:
			_accept_stream_waypoint(multiplayer.get_unique_id(), event)
		else:
			_remotes.request_interaction(event)
			hud.show_message("WAYPOINT PROPOSED")
		return
	_toggle_local_waypoint(waypoint_at, level)


func _toggle_local_waypoint(snapped: Vector2, level: int) -> void:
	for index in range(_map_waypoints.size() - 1, -1, -1):
		var waypoint: Dictionary = _map_waypoints[index]
		if int(waypoint.get("level", level)) == level \
				and (waypoint.get("at", Vector2.ZERO) as Vector2).distance_to(snapped) <= 1.25:
			_map_waypoints.remove_at(index)
			Sound.menu_blip()
			_update_streamed_maps()
			return
	_map_waypoints.append({"at": snapped, "level": level})
	Sound.menu_blip()
	_update_streamed_maps()


func _active_waypoints() -> Array:
	return world_state.shared_waypoints.duplicate(true) if RoomState.online \
		else _map_waypoints.duplicate(true)


func _floor_waypoints(level: int) -> Array:
	var source := _active_waypoints()
	return source.filter(func(waypoint: Dictionary) -> bool:
		return int(waypoint.get("level", level)) == level)


func _clear_reached_waypoints(level: int) -> void:
	var player_at := Vector2(player.global_position.x, player.global_position.z)
	if RoomState.online:
		for waypoint_value in _floor_waypoints(level):
			var waypoint: Dictionary = waypoint_value
			var waypoint_at: Vector2 = waypoint.get("at", Vector2.ZERO)
			if player_at.distance_to(waypoint_at) > WAYPOINT_ARRIVAL_RADIUS:
				continue
			var event := {"what": "stream_waypoint", "at": waypoint_at, "level": level}
			if RoomState.is_host:
				_accept_stream_waypoint(multiplayer.get_unique_id(), event)
			else:
				_remotes.request_interaction(event)
			return
		return
	var removed := false
	for index in range(_map_waypoints.size() - 1, -1, -1):
		var waypoint: Dictionary = _map_waypoints[index]
		if int(waypoint.get("level", level)) != level:
			continue
		var waypoint_at: Vector2 = waypoint.get("at", Vector2.ZERO)
		if player_at.distance_to(waypoint_at) > WAYPOINT_ARRIVAL_RADIUS:
			continue
		_map_waypoints.remove_at(index)
		removed = true
	if removed:
		_waypoint_route_key = ""


func _map_chunks_with_available_pickups(chunks: Dictionary) -> Dictionary:
	var result := {}
	for coord_value in chunks:
		result[coord_value] = _map_chunk_with_available_pickups(
			chunks[coord_value] as Dictionary)
	return result


func _streamed_map_marks(level: int, include_porcelle_counterplay: bool = true) -> Array:
	var result := []
	for entity_id_value in _hunter_views:
		var entity_id := String(entity_id_value)
		if int(_hunter_levels.get(entity_id, 999999)) != level:
			continue
		var view := _hunter_views[entity_id] as HunterView3D
		if view != null and view.brain != null:
			var hunter_id := view.brain.hunter_id
			var porcelle_ghost := hunter_id == "porcelle" \
				and include_porcelle_counterplay and view.brain.active
			if not _admin_reveal_hunters and not porcelle_ghost:
				continue
			var identity := HunterRoster.get_identity(view.brain.hunter_id)
			result.append({"at": view.brain.position, "active": view.brain.active,
				"name": String(identity.get("display_name", "?")), "level": level,
				"hunter_id": hunter_id, "ghost": hunter_id == "porcelle"})
	return result


func _update_streamed_maps() -> void:
	var at := Vector2(player.global_position.x, player.global_position.z)
	var level := facility.current_level()
	# Region boundaries expose generation information, so they follow the same
	# authenticated visual-admin permission as hunter/map reveal controls.
	var show_admin_regions := Build.admin_permission("visual")
	var remote_map_players := _remotes.remote_player_marks(-level) \
		if _remotes != null else []
	var dropped_tool_marks := _dropped_tool_marks(level)
	var discovered_map_chunks := _map_chunks_with_available_pickups(_discovered_chunks)
	var safe_room_marks := _safe_room_map_marks(level, discovered_map_chunks)
	_refresh_waypoint_route(level)
	hud.update_streamed_minimap(_local_map_chunks(), level,
		StreamedRouteGenerator.CHUNK_SIZE, at, player.facing,
		_streamed_map_marks(level, false), remote_map_players,
		show_admin_regions, dropped_tool_marks, safe_room_marks)
	var floor_waypoints := _floor_waypoints(level)
	hud.minimap.set_waypoints(floor_waypoints)
	hud.plan.set_waypoints(floor_waypoints)
	hud.minimap.set_waypoint_path(_waypoint_route)
	hud.plan.set_waypoint_path(_waypoint_route)
	if hud.map_is_open():
		hud.update_streamed_map(discovered_map_chunks, level,
			StreamedRouteGenerator.CHUNK_SIZE, at, player.facing,
			_streamed_map_marks(level, true), remote_map_players,
			show_admin_regions, dropped_tool_marks, safe_room_marks)


func _refresh_waypoint_route(level: int) -> void:
	var floor_waypoints := _floor_waypoints(level)
	var player_cell := Vector2i(floori(player.global_position.x),
		floori(player.global_position.z))
	var destinations := []
	for waypoint_value in floor_waypoints:
		var at: Vector2 = (waypoint_value as Dictionary).get("at", Vector2.ZERO)
		destinations.append(Vector2i(floori(at.x), floori(at.y)))
	var route_key := "%d:%s:%s:%d" % [level, player_cell, destinations,
		_discovered_chunks.size()]
	if route_key == _waypoint_route_key:
		return
	_waypoint_route_key = route_key
	_waypoint_route.clear()
	var cursor := player_cell
	for destination_value in destinations:
		var destination: Vector2i = destination_value
		var segment := _discovered_waypoint_path(cursor, destination, level)
		if segment.is_empty():
			break
		for index in segment.size():
			if not _waypoint_route.is_empty() and index == 0:
				continue
			_waypoint_route.append(Vector2(segment[index]) + Vector2(.5, .5))
		cursor = destination
	_update_waypoint_ground_trail(level)


func _dropped_tool_marks(level: int) -> Array:
	var result := []
	var player_at := Vector2(player.global_position.x, player.global_position.z)
	for record_value in world_state.dropped_items.values():
		var record: Dictionary = record_value
		if int(record.get("level", 999999)) != level:
			continue
		var position = record.get("position")
		if not position is Vector3:
			continue
		var at := Vector2(position.x, position.z)
		if player_at.distance_to(at) > DROPPED_TOOL_MARK_RADIUS:
			continue
		var item_id := String(record.get("item", ""))
		result.append({
			"at": at,
			"level": level,
			"label": String(PlayerController3D.INVENTORY_LABELS.get(item_id, item_id)).substr(0, 1),
			"item_id": item_id,
		})
	return result


func _safe_room_map_marks(level: int, chunks: Dictionary) -> Array:
	var result := []
	for coord_value in chunks.keys():
		var coord: Vector3i = coord_value
		if coord.y != level:
			continue
		var chunk: Dictionary = chunks[coord]
		if not bool(chunk.get("safe_room", false)):
			continue
		var info: Dictionary = chunk.get("safe_room_data", {})
		var room_id := String(info.get("id", ""))
		if room_id.is_empty():
			continue
		var status := world_state.safe_room_status(info)
		result.append({
			"at": Vector2((coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
				(coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE),
			"level": level,
			"breached": bool(status.get("breached", false)),
			"active": String(info.get("checkpoint_id", "")) == world_state.active_checkpoint,
		})
	return result


func _discovered_waypoint_path(from_cell: Vector2i, to_cell: Vector2i,
		level: int) -> Array:
	_ensure_waypoint_grid(level)
	if _waypoint_grid.region.size == Vector2i.ZERO \
			or not _waypoint_grid.is_in_boundsv(from_cell) \
			or not _waypoint_grid.is_in_boundsv(to_cell) \
			or _waypoint_grid.is_point_solid(from_cell) \
			or _waypoint_grid.is_point_solid(to_cell):
		return []
	var result := []
	for cell in _waypoint_grid.get_id_path(from_cell, to_cell):
		result.append(cell)
	return result


func _ensure_waypoint_grid(level: int) -> void:
	var coords: Array[Vector3i] = []
	for coord_value in _discovered_chunks:
		var coord: Vector3i = coord_value
		if coord.y == level:
			coords.append(coord)
	coords.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.z < b.z or (a.z == b.z and a.x < b.x))
	var signature := "%d:%s" % [level, coords]
	if signature == _waypoint_grid_signature:
		return
	_waypoint_grid_signature = signature
	if coords.is_empty():
		_waypoint_grid.region = Rect2i()
		_waypoint_grid.update()
		return
	var min_chunk := Vector2i(coords[0].x, coords[0].z)
	var max_chunk := min_chunk
	for coord in coords:
		min_chunk.x = mini(min_chunk.x, coord.x)
		min_chunk.y = mini(min_chunk.y, coord.z)
		max_chunk.x = maxi(max_chunk.x, coord.x)
		max_chunk.y = maxi(max_chunk.y, coord.z)
	var side := StreamedRouteGenerator.CHUNK_SIZE
	var origin := min_chunk * side
	var size := (max_chunk - min_chunk + Vector2i.ONE) * side
	_waypoint_grid.region = Rect2i(origin, size)
	_waypoint_grid.cell_size = Vector2.ONE
	_waypoint_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_waypoint_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_waypoint_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_waypoint_grid.update()
	for z in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var cell := Vector2i(x, z)
			if not _discovered_waypoint_cell_open(cell, level):
				_waypoint_grid.set_point_solid(cell, true)


func _discovered_waypoint_cell_open(cell: Vector2i, level: int) -> bool:
	var side := StreamedRouteGenerator.CHUNK_SIZE
	var coord := Vector3i(floori(float(cell.x) / side), level,
		floori(float(cell.y) / side))
	if not _discovered_chunks.has(coord):
		return false
	var walls: PackedByteArray = (_discovered_chunks[coord] as Dictionary).get(
		"walls", PackedByteArray())
	var local := Vector2i(posmod(cell.x, side), posmod(cell.y, side))
	var index := local.y * side + local.x
	return index >= 0 and index < walls.size() and walls[index] == 0


func _build_waypoint_ground_trail() -> void:
	_waypoint_trail = MeshInstance3D.new()
	_waypoint_trail.name = "WaypointGroundTrail"
	_waypoint_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_waypoint_trail.extra_cull_margin = 4.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.18, 0.92, 0.84, .72)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_waypoint_trail.material_override = material
	world.add_child(_waypoint_trail)


func _update_waypoint_ground_trail(level: int) -> void:
	if _waypoint_trail == null:
		return
	if _waypoint_route.size() < 2:
		_waypoint_trail.mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := float(level) * StreamedFacilityView3D.LEVEL_HEIGHT + .035
	for index in _waypoint_route.size() - 1:
		var from_2d: Vector2 = _waypoint_route[index]
		var to_2d: Vector2 = _waypoint_route[index + 1]
		var from := Vector3(from_2d.x, height, from_2d.y)
		var to := Vector3(to_2d.x, height, to_2d.y)
		var direction := to - from
		if direction.length_squared() <= .0001:
			continue
		var side := Vector3(-direction.z, 0.0, direction.x).normalized() * .075
		for vertex in [from - side, to - side, to + side,
				from - side, to + side, from + side]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	_waypoint_trail.mesh = surface.commit()


func _live_danger_percent(data: Dictionary) -> int:
	if _player_in_intact_safe_room(data):
		var safe_warning := _afk_void_warning_progress()
		return clampi(roundi(lerpf(0.62, 1.0, safe_warning) * 100.0), 0, 100) \
			if safe_warning > 0.0 else 0
	var base := clampf(float((data.get("difficulty", {}) as Dictionary).get(
		"danger", 0.0)), 0.0, 1.0)
	var score := base * .34
	var population := GameConfig.streamed_hunter_population(
		RoomState.difficulty_id(), GameState.relays_collected)
	score += minf(.22, GameState.relays_collected * .018 \
		+ maxi(0, population - 1) * .035)
	var local_level := facility.current_level()
	var nearest := INF
	var active_nearby := 0
	var chased := false
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	for entity_id_value in _hunter_views:
		var entity_id := String(entity_id_value)
		var view := _hunter_views[entity_id] as HunterView3D
		if view == null or view.brain == null or not view.brain.active:
			continue
		var level_gap := absi(int(_hunter_levels.get(entity_id, 999999)) - local_level)
		if level_gap > 1:
			continue
		active_nearby += 1
		if level_gap != 0:
			continue
		nearest = minf(nearest, view.brain.position.distance_to(player.grid_position()))
		chased = chased or (view.brain.state == HunterBrain.State.CHASE \
			and view.brain.stun_timer <= 0.0 and view.target_peer_id == local_id)
	score += minf(.18, active_nearby * .04)
	if nearest != INF:
		score += clampf(1.0 - nearest / 16.0, 0.0, 1.0) * .36
	if chased:
		score = maxf(score, .88)
	var warning := _afk_void_warning_progress()
	if warning > 0.0:
		score = maxf(score, lerpf(0.62, 1.0, warning))
	return clampi(roundi(score * 100.0), 0, 100)


func _update_anti_idle_pressure(delta: float) -> void:
	if delta <= 0.0 or _awaiting_snapshot or _death_screen_open:
		return
	# Online rooms keep the SceneTree running during a local pause so guests
	# still simulate. The AFK/void clocks must not, or an alt-tabbed host
	# still gets CAUGHT BY GRAY while SIGNAL SUSPENDED is up.
	if pause_menu != null and pause_menu.is_open():
		return
	var relay_count := GameState.relays_collected
	if relay_count != _anti_idle_last_relay_count:
		_anti_idle_last_relay_count = relay_count
		_relay_inactivity_seconds = 0.0
		_party_afk_seconds = 0.0
		_afk_void_warning_shown = false
		return
	_relay_inactivity_seconds += delta
	var local_target := _hunter_target(
		_player_in_intact_safe_room(facility.current_chunk_data()))
	var targets := _remotes.target_states(local_target) if _remotes != null else []
	if _party_moved_since_pressure_sample(targets):
		_party_afk_seconds = 0.0
		_afk_void_warning_shown = false
	else:
		_party_afk_seconds += delta
	var relay_delay := GameConfig.anti_idle_hunter_seconds(
		RoomState.difficulty_id())
	var afk_delay := GameConfig.anti_afk_hunter_seconds(
		RoomState.difficulty_id())
	var relay_pressure := _relay_inactivity_seconds >= relay_delay
	var afk_pressure := _party_afk_seconds >= afk_delay
	if not relay_pressure and not afk_pressure:
		return
	if _remotes == null or not _remotes.simulates():
		return
	if _spawn_anti_idle_hunter():
		_relay_inactivity_seconds = 0.0
		_party_afk_seconds = 0.0
		_afk_void_warning_shown = false
	else:
		# Generation may briefly have no eligible candidate while a new floor is
		# streaming. Retry soon without firing once per frame.
		if relay_pressure:
			_relay_inactivity_seconds = maxf(0.0, relay_delay - 5.0)
		if afk_pressure:
			_party_afk_seconds = maxf(0.0, afk_delay - 5.0)


func _reset_gray_void_pressure(despawn_gray: bool) -> bool:
	_relay_inactivity_seconds = 0.0
	_party_afk_seconds = 0.0
	_afk_void_warning_shown = false
	if not despawn_gray:
		return false
	var removed := false
	for entity_id_value in world_state.hunters.keys().duplicate():
		var entity_id := String(entity_id_value)
		var state: Dictionary = world_state.hunters[entity_id]
		if String(state.get("hunter_id", "")) != "void_gray":
			continue
		_unload_hunter(entity_id, false)
		world_state.hunters.erase(entity_id)
		removed = true
	if removed and _remotes != null and _remotes.simulates():
		_hunter_stream_signature = ""
		_refresh_hunter_stream()
		_collect_hunter_report()
		_remotes.broadcast_hunters(_hunter_report)
		_remotes.broadcast_snapshot()
	return removed


func _party_moved_since_pressure_sample(targets: Array) -> bool:
	var moved := false
	var present := {}
	for target_value in targets:
		var target: Dictionary = target_value
		var position_value = target.get("position")
		if not position_value is Vector2 or bool(target.get("game_over", false)):
			continue
		var peer_id := int(target.get("peer_id", 1))
		var position: Vector2 = position_value
		var facing_value = target.get("facing")
		var facing := Vector2.ZERO
		if facing_value is Vector2:
			facing = facing_value
		present[peer_id] = true
		var previous = _party_activity_anchors.get(peer_id)
		var prev_position := position
		var prev_facing := Vector2.ZERO
		var had_anchor := false
		if previous is Dictionary:
			had_anchor = true
			var stored_position = previous.get("position")
			if stored_position is Vector2:
				prev_position = stored_position
			var stored_facing = previous.get("facing")
			if stored_facing is Vector2:
				prev_facing = stored_facing
		elif previous is Vector2:
			had_anchor = true
			prev_position = previous
		var walked := had_anchor and prev_position.distance_to(position) >= .35
		var looked := false
		if had_anchor and facing.length_squared() > .0001 \
				and prev_facing.length_squared() > .0001 \
				and prev_facing.distance_to(facing) >= .22:
			looked = true
		if not had_anchor or walked or looked:
			_party_activity_anchors[peer_id] = {
				"position": position, "facing": facing}
			moved = true
		elif facing.length_squared() > .0001 and prev_facing.length_squared() <= .0001:
			_party_activity_anchors[peer_id] = {
				"position": prev_position, "facing": facing}
	for peer_id_value in _party_activity_anchors.keys().duplicate():
		if not present.has(peer_id_value):
			_party_activity_anchors.erase(peer_id_value)
	return moved or present.is_empty()


func _afk_void_warning_remaining() -> float:
	var delay := GameConfig.anti_afk_hunter_seconds(RoomState.difficulty_id())
	var window := GameConfig.anti_afk_warning_seconds()
	if window <= 0.0 or _party_afk_seconds <= 0.0:
		return 0.0
	var remaining := delay - _party_afk_seconds
	if remaining <= 0.0 or remaining > window:
		return 0.0
	return remaining


func _afk_void_warning_progress() -> float:
	var window := GameConfig.anti_afk_warning_seconds()
	var remaining := _afk_void_warning_remaining()
	if window <= 0.0 or remaining <= 0.0:
		return 0.0
	return clampf(1.0 - remaining / window, 0.0, 1.0)


func _present_afk_void_warning() -> void:
	if hud == null:
		return
	if _death_screen_open or _awaiting_snapshot:
		_afk_void_warning_shown = false
		hud.set_hold_message("")
		return
	var remaining := _afk_void_warning_remaining()
	var active := remaining > 0.0
	var paused := pause_menu != null and pause_menu.is_open()
	if active:
		# Generic idle copy only. Gray Void still owns the kill internally.
		hud.set_hold_message("STATIONARY // THREAT %ds" % maxi(1, ceili(remaining)))
		if not _afk_void_warning_shown and not paused:
			_afk_void_warning_shown = true
			Sound.alert()
			hud.show_message("STATIONARY // THREAT APPROACHING")
	else:
		hud.set_hold_message("")
		_afk_void_warning_shown = false


func _spawn_anti_idle_hunter() -> bool:
	var local_target := _hunter_target(
		_player_in_intact_safe_room(facility.current_chunk_data()))
	var targets := _remotes.target_states(local_target)
	targets = targets.filter(func(candidate: Dictionary) -> bool:
		return candidate.get("position") is Vector2 \
			and not bool(candidate.get("game_over", false)))
	if targets.is_empty():
		return false
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("peer_id", 1)) < int(b.get("peer_id", 1)))
	var target: Dictionary = targets[_anti_idle_spawn_sequence % targets.size()]
	var target_position: Vector2 = target["position"]
	var level := -int(target.get("depth", 0))
	# Gray is one persistent anti-idle hunter, not a new clone every time the
	# pressure timer fires. Wake and redirect the existing identity when present.
	for existing_id_value in world_state.hunters:
		var existing_id := String(existing_id_value)
		var existing: Dictionary = world_state.hunters[existing_id]
		if String(existing.get("hunter_id", "")) != "void_gray":
			continue
		existing["active"] = true
		existing["state"] = HunterBrain.State.SEARCH
		existing["has_last_known"] = true
		existing["last_known"] = target_position
		world_state.hunters[existing_id] = existing
		_hunter_stream_signature = ""
		_refresh_hunter_stream()
		var existing_view := _hunter_views.get(existing_id) as HunterView3D
		if existing_view != null and existing_view.brain != null:
			existing_view.brain.activate_at(target_position)
			existing_view.target_peer_id = int(target.get("peer_id", 1))
			existing_view.sync_from_brain()
			_store_hunter(existing_id, existing_view)
		_collect_hunter_report()
		_remotes.broadcast_hunters(_hunter_report)
		_remotes.broadcast_snapshot()
		_publish_stream_event({"what": "stream_pressure"})
		return true
	var target_chunk := Vector3i(
		floori(target_position.x / StreamedRouteGenerator.CHUNK_SIZE), level,
		floori(target_position.y / StreamedRouteGenerator.CHUNK_SIZE))
	var candidates: Array[Dictionary] = []
	for z in range(target_chunk.z - 1, target_chunk.z + 2):
		for x in range(target_chunk.x - 1, target_chunk.x + 2):
			var coord := Vector3i(x, level, z)
			if not facility.generator.is_chunk_allowed(coord):
				continue
			for spawn_value in facility.generator.chunk(coord).get("hunter_spawns", []):
				var spawn: Dictionary = spawn_value
				var entity_id := String(spawn.get("id", ""))
				if entity_id.is_empty() or world_state.hunters.has(entity_id) \
						or world_state.removed_hunters.has(entity_id):
					continue
				var cell: Vector2i = spawn.get("cell", Vector2i.ZERO)
				var position := Vector2(
					coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5,
					coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)
				var distance := position.distance_to(target_position)
				if distance < GameConfig.HUNTER_SPAWN_DISTANCE_MIN:
					continue
				var candidate := spawn.duplicate(true)
				candidate["pressure_distance"] = distance
				candidates.append(candidate)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := absf(float(a.get("pressure_distance", 0.0)) - 18.0)
		var b_score := absf(float(b.get("pressure_distance", 0.0)) - 18.0)
		return a_score < b_score or (is_equal_approx(a_score, b_score) \
			and String(a.get("id", "")) < String(b.get("id", ""))))
	var selected := candidates[0].duplicate(true)
	selected.erase("pressure_distance")
	# Gray Void is the dedicated anti-AFK / stalled-relay pursuer. Reusing a
	# dormant generated spawn preserves safe placement and streamed navigation,
	# while overriding only the identity presented by that durable entity.
	selected["hunter_id"] = "void_gray"
	var entity_id := String(selected.get("id", ""))
	var state := world_state.ensure_hunter(selected)
	if state.is_empty():
		return false
	state["active"] = true
	state["state"] = HunterBrain.State.SEARCH
	state["has_last_known"] = true
	state["last_known"] = target_position
	world_state.hunters[entity_id] = state
	_anti_idle_spawn_sequence += 1
	_hunter_stream_signature = ""
	_refresh_hunter_stream()
	var view := _hunter_views.get(entity_id) as HunterView3D
	if view != null and view.brain != null:
		view.brain.activate_at(target_position)
		view.target_peer_id = int(target.get("peer_id", 1))
		view.sync_from_brain()
		_store_hunter(entity_id, view)
	_collect_hunter_report()
	_remotes.broadcast_hunters(_hunter_report)
	_remotes.broadcast_snapshot()
	_publish_stream_event({"what": "stream_pressure"})
	return true


func _refresh_hunter_stream() -> void:
	if _remotes == null or not _remotes.simulates() or facility.generator == null:
		return
	_repair_duplicate_hunter_identities()
	var centers: Array[Vector3i] = [facility.current_chunk_coord()]
	for value in _remotes.stream_centers():
		var center: Vector3i = value
		if not centers.has(center):
			centers.append(center)
	centers.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.y < b.y or (a.y == b.y and (a.x < b.x \
			or (a.x == b.x and a.z < b.z))))
	var stream_signature := _build_hunter_stream_signature(centers)
	if stream_signature == _hunter_stream_signature:
		return
	_hunter_stream_signature = stream_signature
	var active_coords := {}
	var coords_by_level := {}
	var navigation_centers: Array[Vector3i] = centers.duplicate()
	# A pursuing hunter owns a small authority window too. Otherwise a runner
	# crossing a chunk edge or taking a stair could unload the hunter and its
	# path surface before it reached the same vertical link.
	for entity_id_value in world_state.hunters:
		var state: Dictionary = world_state.hunters[entity_id_value]
		if not bool(state.get("active", false)):
			continue
		var hunter_center := _state_chunk(state)
		var near_runner := centers.any(func(runner_center: Vector3i) -> bool:
			return absi(hunter_center.x - runner_center.x) \
				<= HUNTER_RESIDENCY_CHUNK_RADIUS \
				and absi(hunter_center.z - runner_center.z) \
				<= HUNTER_RESIDENCY_CHUNK_RADIUS \
				and absi(hunter_center.y - runner_center.y) <= 1)
		if near_runner and not navigation_centers.has(hunter_center):
			navigation_centers.append(hunter_center)
	# Keep a one-chunk ring around each runner and a bounded vertical stack.
	# Besides covering split parties, the extra level on either side keeps a
	# hunter resident across successive stair transfers instead of unloading
	# immediately when the player climbs twice.
	for center in navigation_centers:
		for level_offset in range(-HUNTER_VERTICAL_STREAM_RADIUS,
				HUNTER_VERTICAL_STREAM_RADIUS + 1):
			var level := center.y + level_offset
			if not coords_by_level.has(level):
				coords_by_level[level] = []
			var level_coords: Array = coords_by_level[level]
			for z in range(center.z - 1, center.z + 2):
				for x in range(center.x - 1, center.x + 2):
					var coord := Vector3i(x, level, z)
					if not facility.generator.is_chunk_allowed(coord):
						continue
					active_coords[coord] = true
					if not level_coords.has(coord):
						level_coords.append(coord)
			coords_by_level[level] = level_coords
	for level_value in coords_by_level:
		var level := int(level_value)
		var navigation := _navigations.get(level) as StreamedHunterNavigation
		if navigation == null:
			navigation = StreamedHunterNavigation.new(facility.generator, level,
				world_state)
			_navigations[level] = navigation
		navigation.refresh(level, coords_by_level[level])
	for level_value in _navigations.keys().duplicate():
		if not coords_by_level.has(level_value):
			_navigations.erase(level_value)
	_navigation = _navigations.get(facility.current_level()) as StreamedHunterNavigation
	var desired := {}
	# Existing hunters keep their durable identity when a route returns to their
	# area. New deterministic candidates are admitted only until the current
	# relay-driven population budget is full, so collecting signals causes
	# additional hunters to appear instead of waking the entire generated pool.
	for entity_id_value in world_state.hunters:
		var entity_id := String(entity_id_value)
		var state := world_state.hunter_state(entity_id)
		if active_coords.has(_state_chunk(state)):
			desired[entity_id] = state
	var candidates: Array[Dictionary] = []
	for coord_value in active_coords:
		var coord: Vector3i = coord_value
		var data := facility.generator.chunk(coord)
		for spawn_value in data.get("hunter_spawns", []):
			var spawn: Dictionary = spawn_value
			var entity_id := String(spawn.get("id", ""))
			if not entity_id.is_empty() and not desired.has(entity_id):
				candidates.append(spawn)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := _hunter_spawn_score(a, centers)
		var b_score := _hunter_spawn_score(b, centers)
		return a_score < b_score or (is_equal_approx(a_score, b_score) \
			and String(a.get("id", "")) < String(b.get("id", ""))))
	var population_limit := GameConfig.streamed_hunter_population(
		RoomState.difficulty_id(), GameState.relays_collected)
	for spawn in candidates:
		# Admin removals consume the corresponding pressure slot until future
		# relay progress raises the desired population again. Otherwise the same
		# deterministic window immediately replaces a hunter the admin removed.
		if desired.size() + world_state.removed_hunters.size() >= population_limit:
			break
		var entity_id := String(spawn.get("id", ""))
		var admitted_spawn := spawn.duplicate(true)
		var proposed_id := String(admitted_spawn.get("hunter_id", ""))
		# Void incursions are a late-route escalation. Gray is the anti-idle
		# exception and may still be admitted on its own timer; every other Void
		# identity waits until the complete 26-member A-Z roster is present.
		if not _void_auto_spawn_allowed(proposed_id):
			continue
		var office_rng := SeededRandom.new("%s:OFFICE-ADMIT:%s" % [
			facility.generator.world_seed, entity_id])
		var az_milestone := _all_a_z_hunters_present()
		var office_chance := .25 if az_milestone else .015
		if office_rng.next_float() < office_chance:
			var office_id := HunterRoster.office_void_for(entity_id)
			if _void_auto_spawn_allowed(office_id):
				admitted_spawn["hunter_id"] = office_id
		admitted_spawn["hunter_id"] = _unique_hunter_identity(
			String(admitted_spawn.get("hunter_id", HunterRoster.DEFAULT_ID)), entity_id)
		var state := world_state.ensure_hunter(admitted_spawn)
		if not state.is_empty():
			desired[entity_id] = state
	for entity_id_value in _hunter_views.keys().duplicate():
		var entity_id := String(entity_id_value)
		if not desired.has(entity_id):
			_unload_hunter(entity_id)
	for entity_id_value in desired:
		var entity_id := String(entity_id_value)
		if not _hunter_views.has(entity_id):
			_load_hunter(entity_id, desired[entity_id])


func _all_a_z_hunters_present() -> bool:
	var present := {}
	for state_value in world_state.hunters.values():
		var hunter_id := String((state_value as Dictionary).get("hunter_id", ""))
		if HunterRoster.A_Z_IDS.has(hunter_id):
			present[hunter_id] = true
	return present.size() >= HunterRoster.A_Z_ROSTER_SIZE


func _void_auto_spawn_allowed(hunter_id: String) -> bool:
	if not hunter_id.begins_with("void_") or hunter_id == "void_gray":
		return true
	return _all_a_z_hunters_present()


func _repair_duplicate_hunter_identities() -> void:
	# Older saves and pre-uniqueness generator revisions may already contain two
	# durable entities with the same character. Preserve the first stable entity
	# and deterministically reassign later duplicates while unused roster entries
	# remain. Once all A-Z and Void identities exist, repetition is unavoidable.
	var used := {}
	var entity_ids := world_state.hunters.keys()
	entity_ids.sort()
	for entity_id_value in entity_ids:
		var entity_id := String(entity_id_value)
		var state: Dictionary = world_state.hunters[entity_id]
		var hunter_id := String(state.get("hunter_id", HunterRoster.DEFAULT_ID))
		# An admin explicitly asking for two of the same character is intentional.
		# Reserve that identity so ordinary route pressure will not quietly add a
		# third copy, but do not rewrite the requested admin summon itself.
		if entity_id.begins_with("ADMIN:"):
			used[hunter_id] = true
			continue
		if not used.has(hunter_id):
			used[hunter_id] = true
			continue
		var replacement := _unused_hunter_identity(entity_id, used)
		if replacement.is_empty():
			continue
		state["hunter_id"] = replacement
		world_state.hunters[entity_id] = state
		used[replacement] = true
		# A resident view is keyed by durable entity ID, so changing only the saved
		# hunter_id would leave its previous body on screen until it streamed out.
		# Rebuild it during this same refresh with the repaired roster identity.
		if _hunter_views.has(entity_id):
			_unload_hunter(entity_id, false)


func _unique_hunter_identity(proposed: String, entity_id: String) -> String:
	var used := {}
	for state_value in world_state.hunters.values():
		var state: Dictionary = state_value
		used[String(state.get("hunter_id", HunterRoster.DEFAULT_ID))] = true
	if not used.has(proposed):
		return proposed
	var replacement := _unused_hunter_identity(entity_id, used)
	return replacement if not replacement.is_empty() else proposed


func _unused_hunter_identity(entity_id: String, used: Dictionary) -> String:
	var available := []
	for hunter_id_value in HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS:
		var hunter_id := String(hunter_id_value)
		if not used.has(hunter_id):
			available.append(hunter_id)
	if available.is_empty():
		return ""
	var rng := SeededRandom.new("%s:UNIQUE-HUNTER:%s" % [
		facility.generator.world_seed, entity_id])
	return String(available[rng.next_index(available.size())])


func _build_hunter_stream_signature(centers: Array[Vector3i]) -> String:
	var parts := PackedStringArray([
		str(world_state.navigation_revision),
		str(GameConfig.streamed_hunter_population(
			RoomState.difficulty_id(), GameState.relays_collected)),
	])
	for center in centers:
		parts.append("C:%d:%d:%d" % [center.x, center.y, center.z])
	var hunter_ids := world_state.hunters.keys()
	hunter_ids.sort()
	for entity_id_value in hunter_ids:
		var entity_id := String(entity_id_value)
		var state: Dictionary = world_state.hunters[entity_id]
		var coord := _state_chunk(state)
		parts.append("H:%s:%d:%d:%d" % [entity_id, coord.x, coord.y, coord.z])
	return "|".join(parts)


func _hunter_spawn_score(spawn: Dictionary, centers: Array[Vector3i]) -> float:
	var coord: Vector3i = spawn.get("origin_chunk", Vector3i.ZERO)
	var cell: Vector2i = spawn.get("cell", Vector2i.ZERO)
	var position := Vector2(
		coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)
	var result := INF
	for center in centers:
		var center_position := Vector2(
			(center.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
			(center.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
		var vertical_cost := absf(float(coord.y - center.y)) * 12.0
		result = minf(result, position.distance_to(center_position) + vertical_cost)
	return result


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


func _unload_hunter(entity_id: String, persist_state: bool = true) -> void:
	var view := _hunter_views.get(entity_id) as HunterView3D
	if view != null and is_instance_valid(view):
		if persist_state and (_remotes == null or _remotes.simulates()):
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
		var activation_relays := GameConfig.hunter_activation_relay_count(
			RoomState.difficulty_id())
		if not view.brain.active and GameState.relays_collected >= activation_relays \
				and not target.is_empty():
			view.brain.activate_at(target["position"])
			if not _hunter_activation_announced:
				_hunter_activation_announced = true
				hud.show_message("HUNTER SIGNAL ACTIVE")
		var safe_context := _safe_context_for_target(target, level)
		if bool(safe_context.get("inside", false)):
			var center: Vector2 = safe_context["center"]
			if view.brain.position.distance_to(center) <= 18.0:
				view.brain.state = HunterBrain.State.INVESTIGATE
				view.brain.has_last_known = true
				view.brain.last_known = center
		_operate_hunter_room_door(view, level)
		var captured := false
		if not target.is_empty():
			view.target_peer_id = int(target.get("peer_id", 1))
			captured = view.brain.update(delta, navigation, target,
				maxi(1, -level + 1), GameState.relays_collected)
			view.set_look_target(view.brain.presentation_look_target())
		else:
			view.target_peer_id = 0
			view.set_look_target(null)
			view.brain.update_without_target(delta, navigation,
				maxi(1, -level + 1), GameState.relays_collected)
		view.sync_from_brain()
		for hunter_event_value in view.brain.world_events:
			_apply_streamed_hunter_world_event(hunter_event_value, level,
				navigation)
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


func _operate_hunter_room_door(view: HunterView3D, level: int) -> void:
	if view == null or view.brain == null or not view.brain.active:
		return
	var nearest: RouteInteractable3D
	var nearest_distance := INF
	for door in facility.room_doors_on_level(level):
		if door.room_door_open or door.room_door_broken:
			continue
		var door_position := Vector2(door.source_cell) + Vector2(.5, .5)
		var distance := view.brain.position.distance_to(door_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = door
	if nearest == null or nearest_distance > 1.15:
		return
	var at := Vector2(nearest.source_cell) + Vector2(.5, .5)
	if view.brain.hunter_id == "loxelle" \
			and view.brain.state == HunterBrain.State.CHASE \
			and view.brain.gimmick is LoxelleGimmick:
		var loxelle := view.brain.gimmick as LoxelleGimmick
		if not loxelle.door_charge_active():
			loxelle.start_door_breach(view.brain, nearest.room_door_id, at)
		return
	# Every other hunter uses the handle and keeps moving. Door state is still
	# host-authoritative and reliable, so guests see the same hinge animation.
	_publish_stream_event({"what": "stream_door",
		"door_id": nearest.room_door_id, "open": true, "broken": false})


func _apply_streamed_hunter_world_event(event: Dictionary, level: int,
		navigation: StreamedHunterNavigation) -> void:
	if String(event.get("what", "")) == "room_door":
		var door_id := String(event.get("door_id", ""))
		var door_data := _stream_room_door_data(door_id)
		var coord: Vector3i = door_data.get("coord", Vector3i(0, 999999, 0))
		if door_data.is_empty() or coord.y != level:
			return
		var status := world_state.room_door_status(door_id)
		if bool(status.get("broken", false)):
			return
		_publish_stream_event({"what": "stream_door", "door_id": door_id,
			"open": bool(event.get("open", true)),
			"broken": bool(event.get("broken", false))})
		return
	var cell = event.get("cell")
	if not cell is Vector2i:
		return
	match String(event.get("what", "")):
		"pickup":
			if int(event.get("kind", -1)) != RouteInteractable3D.Kind.BATTERY:
				return
			for entry_value in navigation.batteries:
				var entry: Dictionary = entry_value
				if Vector2i(int(entry["x"]), int(entry["y"])) == cell:
					_publish_stream_event({"what": "stream_pickup",
						"entity_id": String(entry.get("id", "")), "kind": "battery",
						"item": "", "winner_peer_id": 0,
						"message": String(event.get("message", ""))})
					return
		"sabotage":
			for entry_value in navigation.relays:
				var entry: Dictionary = entry_value
				if Vector2i(int(entry["x"]), int(entry["y"])) == cell \
						and bool(entry.get("collected", false)) \
						and not world_state.relay_sabotaged(String(entry.get("id", ""))):
					_publish_stream_event({"what": "stream_sabotage",
						"entity_id": String(entry.get("id", "")), "cell": cell,
						"sabotaged": true, "level": level,
						"message": String(event.get("message", ""))})
					return


func _stream_guardian_blocking(target: RouteInteractable3D) -> String:
	var point := Vector2(target.source_cell) + Vector2(.5, .5)
	for view_value in _hunter_views.values():
		var view := view_value as HunterView3D
		if view == null or view.brain == null or not view.brain.active \
				or view.brain.gimmick == null \
				or not view.brain.gimmick.has_method("blocks") \
				or not bool(view.brain.gimmick.call("blocks", point)):
			continue
		if RoomState.online and not RoomState.is_host:
			_remotes.request_interaction({"what": "guardian_ping",
				"cell": target.source_cell})
		var identity := HunterRoster.get_identity(view.brain.hunter_id)
		return "%s IS GUARDING THIS // DRAW HER OFF" % String(
			identity.get("display_name", view.brain.hunter_id)).to_upper()
	return ""


func _accept_stream_guardian_ping(peer_id: int, event: Dictionary) -> void:
	var cell = event.get("cell")
	var target := _target_state_for_peer(peer_id)
	var position = target.get("position")
	if not cell is Vector2i or not position is Vector2 \
			or (position as Vector2).distance_to(Vector2(cell) + Vector2(.5, .5)) \
				> STREAM_INTERACT_DISTANCE:
		return
	var blocked := false
	for view_value in _hunter_views.values():
		var view := view_value as HunterView3D
		if view != null and view.brain.active and view.brain.gimmick != null \
				and view.brain.gimmick.has_method("blocks") \
				and bool(view.brain.gimmick.call("blocks",
					Vector2(cell) + Vector2(.5, .5))):
			blocked = true
			break
	if not blocked:
		return
	for view_value in _hunter_views.values():
		var view := view_value as HunterView3D
		if view != null and view.brain.active:
			view.brain.enter_search_from(position, 1.8)


func _use_streamed_vent(vent_id: String) -> String:
	var level := facility.current_level()
	var navigation := _navigations.get(level) as StreamedHunterNavigation
	if navigation == null:
		navigation = _navigation
	if navigation == null:
		return "The grate won't budge."
	for entity_id_value in _hunter_views:
		if int(_hunter_levels.get(entity_id_value, 999999)) != level:
			continue
		var view := _hunter_views[entity_id_value] as HunterView3D
		if view != null and view.brain.gimmick is VerrineGimmick:
			var was_inside := player.in_vent
			var message := String((view.brain.gimmick as VerrineGimmick).use_vent(
				vent_id, view.brain, player, navigation))
			if RoomState.online and not RoomState.is_host:
				_remotes.request_interaction({"what": "vent_used", "vent_id": vent_id,
					"entered": not was_inside and player.in_vent})
			return message
	return "The grate won't budge."


func _accept_stream_vent(peer_id: int, event: Dictionary) -> void:
	if not bool(event.get("entered", false)):
		return
	var target := _target_state_for_peer(peer_id)
	var level := -int(target.get("depth", 0))
	var navigation := _navigations.get(level) as StreamedHunterNavigation
	var vent_id := String(event.get("vent_id", ""))
	if navigation == null or not navigation.vents.any(func(entry: Dictionary) -> bool:
		return String(entry.get("id", "")) == vent_id):
		return
	for entity_id_value in _hunter_views:
		if int(_hunter_levels.get(entity_id_value, 999999)) != level:
			continue
		var view := _hunter_views[entity_id_value] as HunterView3D
		if view != null and view.brain.gimmick is VerrineGimmick:
			(view.brain.gimmick as VerrineGimmick).remote_vent_entered(
				vent_id, view.brain, navigation)


func _target_protected(target: Dictionary) -> bool:
	if target.is_empty() or bool(target.get("game_over", false)) \
			or bool(target.get("escape_active", false)) \
			or bool(target.get("capture_immune", false)):
		return true
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	var peer_id := int(target.get("peer_id", local_id))
	var tools_allowed := Build.admin_permission("player") if peer_id == local_id \
		else _remotes.remote_admin_peer_allowed(peer_id, "player")
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
		"inventory_order": player.inventory_order_snapshot(),
		"inventory_slot_durability": player.inventory_slot_durability_snapshot(),
		"selected_inventory_slot": player.selected_inventory_slot,
		"selected_item": player.selected_inventory_item(),
		"inventory_free_slots": player.inventory_order_snapshot().count(""),
		"inventory_capacity": player.inventory_capacity(),
		"equipped_backpack": player.equipped_backpack,
		"meters": player.meters,
		"no_target": player.admin_no_target,
		"god_mode": player.admin_god_mode,
		"escape_active": GameState.escape_active,
		"capture_immune": _capture_cooldown > 0.0 or GameState.is_capture_immune(),
		"game_over": _death_screen_open,
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
	var hunter_id := view.brain.hunter_id
	var identity := HunterRoster.get_identity(hunter_id)
	var is_void := HunterRoster.VOID_IDS.has(hunter_id) \
		or String(identity.get("category", "az")) == "void"
	var inescapable := is_void or (view.brain.gimmick != null \
		and view.brain.gimmick.capture_is_inescapable())
	view.brain.calm_reset(GameConfig.ESCAPE_STUN_DURATION)
	view.sync_from_brain()
	_remotes.send_player_event(int(target.get("peer_id", 1)), {
		"what": "capture", "streamed": true,
		"entity_id": String(view.get_meta("streamed_entity_id", "")),
		"hunter_id": hunter_id, "inescapable": inescapable})


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
		entity_id: String, kind: String, item_id: String) -> String:
	if kind == "relay" and world_state.relay_sabotaged(entity_id):
		var repair_event := {"what": "stream_sabotage", "entity_id": entity_id,
			"sabotaged": false}
		if RoomState.online and not RoomState.is_host:
			_remotes.request_interaction(repair_event)
		else:
			_accept_stream_sabotage(multiplayer.get_unique_id() \
				if RoomState.online else 1, repair_event)
		return "RESECURING SIGNAL RELAY..."
	var event := {"what": "stream_pickup", "entity_id": entity_id,
		"kind": kind, "item": item_id}
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
		return ""
	_accept_streamed_pickup(multiplayer.get_unique_id() if RoomState.online else 1,
		event)
	return ""


func _request_streamed_door(_requesting_player: PlayerController3D,
		door_id: String) -> String:
	var status := world_state.room_door_status(door_id)
	if bool(status.get("broken", false)):
		Sound.interaction_fail()
		return ""
	var event := {"what": "stream_door", "door_id": door_id}
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
		return ""
	_accept_stream_door(multiplayer.get_unique_id() if RoomState.online else 1,
		event)
	return ""

func _on_remote_interaction_request(peer_id: int, event: Dictionary) -> void:
	if not _remotes.simulates():
		return
	var what := String(event.get("what", ""))
	if what in ["admin_auth", "admin_world"]:
		if Build.remote_guest_tools_allowed() \
				or _remotes.remote_admin_peer_allowed(peer_id):
			_apply_verified_admin_request(peer_id, event)
			return
		var ticket := String(event.get("admin_ticket", ""))
		if ticket.is_empty():
			_remotes.send_player_event(peer_id, {"what": "message",
				"message": "ADMIN REQUEST REJECTED // ROOM PROOF REQUIRED"})
			return
		var request_id := Backend.verify_room_admin_ticket(RoomState.code, ticket)
		_pending_admin_requests[request_id] = {
			"peer_id": peer_id,
			"event": event.duplicate(true),
		}
		_remotes.send_player_event(peer_id, {"what": "message",
			"message": "ADMIN // VERIFYING ROOM PROOF"})
		return
	match what:
		"stream_pickup":
			_accept_streamed_pickup(peer_id, event)
		"stream_safe_repair":
			_accept_safe_repair(peer_id, event)
		"stream_checkpoint":
			_accept_checkpoint(peer_id, event)
		"stream_drop":
			_accept_stream_drop(peer_id, event)
		"stream_sabotage":
			_accept_stream_sabotage(peer_id, event)
		"stream_door":
			_accept_stream_door(peer_id, event)
		"stream_waypoint":
			_accept_stream_waypoint(peer_id, event)
		"guardian_ping":
			_accept_stream_guardian_ping(peer_id, event)
		"vent_used":
			_accept_stream_vent(peer_id, event)


func _on_item_drop_requested(item_id: String, durability: int, slot: int) -> void:
	var event := {"what": "stream_drop", "action": "create",
		"item": item_id, "durability": durability, "slot": slot}
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
		hud.show_message("DROPPING %s..." % String(
			PlayerController3D.INVENTORY_LABELS.get(item_id, item_id)).to_upper())
	else:
		_accept_stream_drop(multiplayer.get_unique_id() if RoomState.online else 1,
			event)


func _request_dropped_pickup(_requesting_player: PlayerController3D,
		drop_id: String) -> String:
	var event := {"what": "stream_drop", "action": "claim", "drop_id": drop_id}
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
	else:
		_accept_stream_drop(multiplayer.get_unique_id() if RoomState.online else 1,
			event)
	return ""


func _accept_stream_drop(peer_id: int, event: Dictionary) -> void:
	var target := _target_state_for_peer(peer_id)
	if target.is_empty():
		return
	match String(event.get("action", "")):
		"create":
			var item_id := String(event.get("item", ""))
			var owned = target.get("owned_items", {})
			var slot := int(event.get("slot", -1))
			var order = target.get("inventory_order", [])
			var slot_durability = target.get("inventory_slot_durability", [])
			if item_id != String(target.get("selected_item", "")) \
					or slot != int(target.get("selected_inventory_slot", -2)) \
					or not order is Array or slot < 0 or slot >= order.size() \
					or String(order[slot]) != item_id \
					or not owned is Dictionary or not bool(owned.get(item_id, false)):
				return
			var durability := int(slot_durability[slot]) \
				if slot_durability is Array and slot < slot_durability.size() \
				else int(event.get("durability", 0))
			var at = target.get("at")
			var facing = target.get("facing")
			if not at is Vector3 or not facing is Vector2:
				return
			var drop_position: Vector3 = at
			drop_position += Vector3(facing.x, 0.0, facing.y) * .72
			drop_position.y = facility.streamed_surface_height(Vector2(
				drop_position.x, drop_position.z), -int(target.get("depth", 0))) + .12
			var record := world_state.create_drop(item_id, durability, drop_position,
				-int(target.get("depth", 0)), peer_id, slot)
			if record.is_empty():
				return
			_publish_stream_event({"what": "stream_drop_create", "drop": record})
		"claim":
			var drop_id := String(event.get("drop_id", ""))
			var record: Dictionary = world_state.dropped_items.get(drop_id, {})
			var at = target.get("at")
			var owned = target.get("owned_items", {})
			if record.is_empty() or not at is Vector3 \
					or int(record.get("level", 999999)) != -int(target.get("depth", 0)) \
					or (at as Vector3).distance_to(record.get("position", Vector3.ZERO)) \
						> STREAM_INTERACT_DISTANCE \
					or int(target.get("inventory_free_slots", 0)) <= 0:
				return
			world_state.claim_drop(drop_id)
			_publish_stream_event({"what": "stream_drop_claim", "drop": record,
				"winner_peer_id": peer_id})


func _accept_stream_waypoint(peer_id: int, event: Dictionary) -> void:
	var target := _target_state_for_peer(peer_id)
	var at = event.get("at")
	if target.is_empty() or not at is Vector2:
		return
	var level := int(event.get("level", 999999))
	if level != -int(target.get("depth", 0)):
		return
	var result := world_state.toggle_shared_waypoint(
		Vector2(floori(at.x) + .5, floori(at.y) + .5), level, peer_id)
	if not bool(result.get("changed", false)):
		return
	var waypoint: Dictionary = result.get("waypoint", {})
	_publish_stream_event({"what": "stream_waypoint",
		"added": bool(result.get("added", false)),
		"waypoint": waypoint,
		"message_peer_id": peer_id})


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
	var kind := String(pickup.get("kind", "tool"))
	if kind != String(event.get("kind", "")) \
			or (kind in ["tool", "backpack"] and (item_id.is_empty() \
				or item_id != String(event.get("item", "")))):
		return
	if kind in ["tool", "battery"]:
		if int(target.get("inventory_free_slots", 0)) <= 0:
			return
	elif kind == "backpack":
		var target_order = target.get("inventory_order", [])
		if not target_order is Array \
				or not PlayerController3D.can_accept_backpack(target_order, item_id):
			return
	_publish_stream_event({"what": "stream_pickup", "entity_id": entity_id,
		"kind": kind, "item": item_id, "winner_peer_id": peer_id})


func _accept_stream_sabotage(peer_id: int, event: Dictionary) -> void:
	var entity_id := String(event.get("entity_id", ""))
	var pickup := _stream_pickup_data(entity_id)
	if pickup.is_empty() or String(pickup.get("kind", "")) != "relay" \
			or not world_state.relay_sabotaged(entity_id) \
			or bool(event.get("sabotaged", true)):
		return
	var target := _target_state_for_peer(peer_id)
	var at = target.get("position")
	var coord: Vector3i = pickup.get("coord", Vector3i.ZERO)
	var cell: Vector2i = pickup.get("cell", Vector2i.ZERO)
	var relay_at := Vector2(coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)
	if not at is Vector2 or -int(target.get("depth", 999999)) != coord.y \
			or (at as Vector2).distance_to(relay_at) > STREAM_INTERACT_DISTANCE:
		return
	_publish_stream_event({"what": "stream_sabotage", "entity_id": entity_id,
		"cell": Vector2i(floori(relay_at.x), floori(relay_at.y)),
		"sabotaged": false, "message_peer_id": peer_id})


func _accept_stream_door(peer_id: int, event: Dictionary) -> void:
	var door_id := String(event.get("door_id", ""))
	var target := _target_state_for_peer(peer_id)
	var position = target.get("position")
	var door_data := _stream_room_door_data(door_id, target)
	if target.is_empty() or not position is Vector2 or door_data.is_empty():
		return
	var coord: Vector3i = door_data.get("coord", Vector3i.ZERO)
	var cell: Vector2i = door_data.get("cell", Vector2i.ZERO)
	var door_position := Vector2(
		coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)
	if coord.y != -int(target.get("depth", 999999)) \
			or (position as Vector2).distance_to(door_position) > STREAM_INTERACT_DISTANCE:
		return
	var status := world_state.room_door_status(door_id)
	if bool(status.get("broken", false)):
		return
	_publish_stream_event({"what": "stream_door", "door_id": door_id,
		"open": not bool(status.get("open", false)), "broken": false,
		"message_peer_id": peer_id})


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
	if entity_id.length() > 80 or parts.size() != 6 or parts[3] != "PICKUP" \
			or not parts[0].is_valid_int() or not parts[1].is_valid_int() \
			or not parts[2].is_valid_int() or not parts[5].is_valid_int() \
			or String(parts[4]).to_lower() not in ["relay", "battery", "tool", "backpack", "coin"]:
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


func _stream_room_door_data(door_id: String, _target: Dictionary = {}) -> Dictionary:
	var parts := door_id.split(":")
	if door_id.length() > 80 or parts.size() != 5 or parts[3] != "DOOR" \
			or not parts[0].is_valid_int() or not parts[1].is_valid_int() \
			or not parts[2].is_valid_int() or not parts[4].is_valid_int():
		return {}
	var coord := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	if absi(coord.x) > 1_000_000 or absi(coord.y) > 1_000_000 \
			or absi(coord.z) > 1_000_000:
		return {}
	for value in facility.generator.chunk(coord).get("region_props", []):
		var prop: Dictionary = value
		if String(prop.get("id", "")) == door_id \
				and bool(prop.get("room_door", false)):
			var result := prop.duplicate(true)
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
			if not facility.apply_pickup_claim(entity_id):
				return
			_sync_stream_progress()
			var local_id := multiplayer.get_unique_id() if RoomState.online else 1
			if int(event.get("winner_peer_id", 0)) == 0 \
					and not String(event.get("message", "")).is_empty():
				hud.show_message(String(event.get("message", "")))
			if int(event.get("winner_peer_id", 0)) == local_id:
				var kind := String(event.get("kind", "tool"))
				var item_id := String(event.get("item", ""))
				if kind != "relay":
					_run_statistics["items_collected"] = int(
						_run_statistics.get("items_collected", 0)) + 1
				match kind:
					"relay":
						Sound.collect()
					"battery":
						if player.grant_inventory_item("battery"):
							Sound.collect()
					"coin":
						Sound.collect()
					_:
						if player.grant_inventory_item(item_id):
							Sound.collect()
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
					hud.show_message("SAFE ROOM BREACHED")
		"stream_checkpoint":
			var checkpoint_id := String(event.get("checkpoint_id", ""))
			world_state.apply_checkpoint(checkpoint_id)
			var local_id := multiplayer.get_unique_id() if RoomState.online else 1
			if int(event.get("winner_peer_id", 0)) == local_id:
				_run_statistics["checkpoints_activated"] = int(
					_run_statistics.get("checkpoints_activated", 0)) + 1
				_last_checkpoint = checkpoint_id
				_last_checkpoint_request = ""
				_last_checkpoint_request_usec = 0
				player.restore_at_safe_zone()
				Sound.recharge(20.0)
				hud.show_message("SAFE CHECKPOINT ACTIVE")
		"stream_sabotage":
			var entity_id := String(event.get("entity_id", ""))
			if world_state.set_relay_sabotaged(entity_id,
					bool(event.get("sabotaged", false))):
				facility.refresh_mutations()
				_sync_stream_progress()
				var local_id := multiplayer.get_unique_id() if RoomState.online else 1
				if bool(event.get("sabotaged", false)):
					hud.show_message("SIGNAL LOST // RELAY OFFLINE")
				elif int(event.get("message_peer_id", 0)) == local_id:
					hud.show_message("SIGNAL RELAY RESECURED")
		"stream_waypoint":
			var waypoint = event.get("waypoint", {})
			if waypoint is Dictionary and world_state.apply_shared_waypoint(
					waypoint, bool(event.get("added", false))):
				_waypoint_route_key = ""
				Sound.menu_blip()
				_update_streamed_maps()
		"stream_door":
			var door_id := String(event.get("door_id", ""))
			if _stream_room_door_data(door_id).is_empty():
				return
			var open := bool(event.get("open", false))
			var broken := bool(event.get("broken", false))
			var changed := facility.apply_room_door_state(door_id, open, broken)
			if not changed:
				return
			if broken:
				Sound.door_breach()
			else:
				Sound.door(open)
		"stream_drop_create":
			var record = event.get("drop", {})
			if not record is Dictionary:
				return
			world_state.apply_drop(record)
			var local_id := multiplayer.get_unique_id() if RoomState.online else 1
			if int(record.get("source_peer_id", 0)) == local_id:
				player.remove_inventory_item(String(record.get("item", "")),
					int(record.get("source_inventory_slot", -1)))
			_spawn_drop(record)
		"stream_drop_claim":
			var record = event.get("drop", {})
			if not record is Dictionary:
				return
			var drop_id := String(record.get("id", ""))
			world_state.claim_drop(drop_id)
			_remove_drop_node(drop_id)
			var local_id := multiplayer.get_unique_id() if RoomState.online else 1
			if int(event.get("winner_peer_id", 0)) == local_id:
				var item_id := String(record.get("item", ""))
				if player.grant_inventory_item(item_id, int(record.get("durability", -1))):
					Sound.collect()
		"stream_pressure":
			# Audio replaces another explanatory HUD log: the sudden warning is the
			# player's only announcement that Gray Void entered the route.
			Sound.alert()
		"stream_story":
			var story_state = event.get("state", {})
			if story_state is Dictionary and _story != null:
				_story.adopt_snapshot(story_state)


func _spawn_drop(record: Dictionary) -> void:
	var drop_id := String(record.get("id", ""))
	if drop_id.is_empty() or _drop_nodes.has(drop_id):
		return
	var item_id := String(record.get("item", ""))
	var node := RouteInteractable3D.new()
	node.name = "Dropped_%s" % drop_id.replace(":", "_")
	node.kind = RouteInteractable3D.Kind.TOOL_PICKUP
	node.position = record.get("position", Vector3.ZERO)
	node.set_meta("dropped_item_id", drop_id)
	node.activation_override = _request_dropped_pickup.bind(drop_id)
	world.add_child(node)
	node.configure_tool_pickup(item_id)
	_drop_nodes[drop_id] = node


func _remove_drop_node(drop_id: String) -> void:
	var node := _drop_nodes.get(drop_id) as Node
	if node != null:
		node.queue_free()
	_drop_nodes.erase(drop_id)


func _sync_drop_nodes() -> void:
	for drop_id_value in _drop_nodes.keys().duplicate():
		if not world_state.dropped_items.has(drop_id_value):
			_remove_drop_node(String(drop_id_value))
	for record_value in world_state.dropped_items.values():
		_spawn_drop(record_value)


func _local_safe_room_id() -> String:
	var data := facility.current_chunk_data()
	if not bool(data.get("safe_room", false)):
		return ""
	return String((data.get("safe_room_data", {}) as Dictionary).get("id", ""))


func _build_stream_snapshot() -> Dictionary:
	_collect_hunter_report()
	return {"snapshot_protocol": SNAPSHOT_PROTOCOL,
		"seed": RoomState.run_seed(), "world_state": world_state.snapshot(),
		"hunters": _hunter_report.duplicate(true),
		"story": _story.snapshot() if _story != null else {"active": false},
		"anti_idle": {
			"relay_seconds": _relay_inactivity_seconds,
			"afk_seconds": _party_afk_seconds,
			"relay_count": _anti_idle_last_relay_count,
			"spawn_sequence": _anti_idle_spawn_sequence,
		}}


func _apply_stream_snapshot(state: Dictionary) -> void:
	if int(state.get("snapshot_protocol", -1)) != SNAPSHOT_PROTOCOL \
			or int(state.get("seed", 0)) != RoomState.run_seed():
		return
	var snapshot = state.get("world_state")
	var report = state.get("hunters")
	if not snapshot is Dictionary or not report is Array \
			or not world_state.adopt(snapshot):
		return
	_sync_stream_progress()
	var anti_idle = state.get("anti_idle", {})
	if anti_idle is Dictionary:
		_relay_inactivity_seconds = maxf(0.0,
			float(anti_idle.get("relay_seconds", 0.0)))
		_party_afk_seconds = maxf(0.0,
			float(anti_idle.get("afk_seconds", 0.0)))
		_anti_idle_last_relay_count = int(anti_idle.get("relay_count",
			GameState.relays_collected))
		_anti_idle_spawn_sequence = maxi(0,
			int(anti_idle.get("spawn_sequence", 0)))
	var story = state.get("story", {})
	if story is Dictionary and _story != null:
		_story.adopt_snapshot(story)
	facility.refresh_mutations()
	_sync_drop_nodes()
	_apply_hunter_report(report)
	_awaiting_snapshot = false
	player.input_frozen = (pause_menu != null and pause_menu.is_open()) \
		or hud.inventory_is_open() \
		or (_admin_menu != null and _admin_menu.is_open()) \
		or (_story != null and _story.is_active())
	_remotes.confirm_snapshot_applied()
	hud.show_message("ROUTE SYNCED")


func _sync_stream_progress() -> void:
	var previous_relays := GameState.relays_collected
	var relay_count := 0
	var coin_count := 0
	for entity_id_value in world_state.claimed_pickups:
		if String(entity_id_value).contains(":PICKUP:RELAY:"):
			relay_count += 1
		elif String(entity_id_value).contains(":PICKUP:COIN:"):
			coin_count += 1
	GameState.relays_collected = relay_count
	GameState.relays_sabotaged = world_state.sabotaged_relays.size()
	GameState.coins = coin_count * GameConfig.COIN_PICKUP_VALUE
	var gray_removed := false
	if relay_count != previous_relays:
		_anti_idle_last_relay_count = relay_count
		gray_removed = _reset_gray_void_pressure(
			_remotes != null and _remotes.simulates())
	if relay_count != previous_relays and _remotes != null and _remotes.simulates():
		# Population pressure changes on the authoritative pickup frame rather
		# than waiting for the next periodic stream refresh. Relay progress also
		# cancels any currently spawned Gray Void pressure body immediately.
		if gray_removed:
			return
		_refresh_hunter_stream()


func _collect_hunter_report() -> void:
	_hunter_report.clear()
	var ids := _hunter_views.keys()
	ids.sort()
	for entity_id_value in ids:
		var entity_id := String(entity_id_value)
		var view := _hunter_views.get(entity_id) as HunterView3D
		if view == null or view.brain == null:
			continue
		var state := world_state.hunter_state(entity_id)
		state["entity_id"] = entity_id
		state["target_peer_id"] = view.target_peer_id
		state["look_target"] = view.look_target_position if view.has_look_target else null
		state["on_stairs"] = false
		state["presentation_y"] = view.position.y
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
		# Guests receive the host's planar tread positions and walk their matching
		# streamed ramp locally. Applying presentation_y here made remote hunters
		# pop vertically on every network packet instead of obeying gravity.
		view.clear_streamed_height_override()
		view.target_peer_id = int(state.get("target_peer_id", 0))
		view.set_look_target(state.get("look_target"))
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
			if _death_screen_open or GameState.escape_active:
				return
			var hunter_id := String(event.get("hunter_id", HunterRoster.DEFAULT_ID))
			if GameState.is_capture_immune():
				# Purely a protocol acknowledgement: releases the host's pending-
				# capture gate without actually ending or restarting the struggle.
				if RoomState.online and not RoomState.is_host:
					_remotes.submit_hunter_event({"what": "caught"})
				return
			if bool(event.get("inescapable", false)) or GameState.escape_on_cooldown():
				await _resolve_capture_outcome(hunter_id)
				return
			_begin_escape_struggle(String(event.get("entity_id", "")), hunter_id)
		"message":
			var message := String(event.get("message", ""))
			if not message.is_empty():
				hud.show_message(message)


## Starts the local mash-to-escape struggle. Ordinary A-Z hunters give the
## player this chance; void/gimmick-forced grabs skip straight to
## _resolve_capture_outcome().
func _begin_escape_struggle(entity_id: String, hunter_id: String) -> void:
	_escaping_entity_id = entity_id
	_escaping_hunter_id = hunter_id
	Sound.capture()
	player.velocity = Vector3.ZERO
	player.input_frozen = true
	player.look_frozen = true
	hud.set_inventory_open(false)
	hud.set_map_open(false)
	if pause_menu.is_open():
		pause_menu.close()
	GameState.begin_escape(hunter_id)
	hud.set_escape_active(true)
	hud.update_escape(GameState.escape_progress, GameState.escape_required,
		GameState.escape_remaining, GameState.escape_duration)
	if jumpscare != null:
		jumpscare.start_hold(player.active_camera(), hunter_id)


func _update_escape_struggle(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		GameState.register_escape_press()
		Sound.struggle(GameState.escape_progress / maxf(1.0, GameState.escape_required))
	GameState.escape_remaining = maxf(0.0, GameState.escape_remaining - delta)
	hud.update_escape(GameState.escape_progress, GameState.escape_required,
		GameState.escape_remaining, GameState.escape_duration)
	if GameState.escape_progress >= GameState.escape_required:
		_resolve_escape_success()
	elif GameState.escape_remaining <= 0.0:
		await _resolve_capture_outcome(_escaping_hunter_id)


func _resolve_escape_success() -> void:
	GameState.resolve_escape_success()
	Sound.escape()
	hud.set_escape_active(false)
	if jumpscare != null:
		jumpscare.stop_hold()
	player.input_frozen = false
	player.look_frozen = false
	if _remotes.simulates():
		var view := _hunter_views.get(_escaping_entity_id) as HunterView3D
		if view != null:
			view.brain.apply_stun(GameConfig.ESCAPE_STUN_DURATION)
			view.sync_from_brain()
			_store_hunter(_escaping_entity_id, view)
	else:
		_remotes.submit_hunter_event({"what": "escaped",
			"entity_id": _escaping_entity_id, "hunter_id": _escaping_hunter_id})
	hud.show_message("You broke free!")
	_escaping_entity_id = ""
	_escaping_hunter_id = ""


## Shared by a failed struggle and an inescapable grab (void hunters, or a
## gimmick that declares the grab inescapable): the same local jumpscare and
## death report either way.
func _resolve_capture_outcome(hunter_id: String) -> void:
	if _capture_resolving:
		return
	_capture_resolving = true
	GameState.resolve_escape_failure()
	hud.set_escape_active(false)
	_escaping_entity_id = ""
	_escaping_hunter_id = ""
	_force_disable_admin_cheats()
	_death_screen_open = true
	_capture_cooldown = 60.0 * 60.0
	player.velocity = Vector3.ZERO
	player.input_frozen = true
	player.look_frozen = true
	hud.set_inventory_open(false)
	hud.set_map_open(false)
	if pause_menu.is_open():
		pause_menu.close()
	pause_menu.set_process(false)
	pause_menu.set_process_unhandled_input(false)
	var identity := HunterRoster.get_identity(hunter_id)
	var hunter_name := String(identity.get("display_name", hunter_id)).to_upper()
	# Same local capture presentation as main_3d.gd: play the lunge/camera
	# takeover before the death screen or spectator handoff so the player
	# actually sees the hunter that caught them.
	Sound.office_jumpscare(hunter_id)
	if jumpscare != null:
		await jumpscare.play(player.active_camera(), hunter_id)
	if RoomState.online and not RoomState.is_host:
		player.enter_spectator()
		player.input_frozen = false
		player.look_frozen = false
		_remotes.submit_hunter_event({"what": "caught"})
		hud.show_message("YOU DIED // SPECTATOR MODE")
		_capture_resolving = false
		return
	run_report.open({
		"online": RoomState.online, "host": RoomState.is_host,
		"respawn": true, "title": "YOU DIED",
		"kicker": "RUNNER SIGNAL // LOST",
		"reason": "CAUGHT BY %s" % hunter_name,
		"depth": -facility.current_level(), "score": GameState.score,
		"relays": GameState.relays_collected,
		"relay_target": GameState.relay_target,
		"coins": GameState.coins,
		"difficulty": RoomState.difficulty_id().to_upper(),
		"seed": RoomState.seed_text,
	})
	_capture_resolving = false


func _apply_hunter_event(event: Dictionary) -> void:
	if RoomState.online and not RoomState.is_host:
		return
	match String(event.get("what", "")):
		"taser":
			_resolve_taser(int(event.get("peer_id",
				multiplayer.get_unique_id() if RoomState.online else 1)))
		"escaped":
			var view := _hunter_views.get(String(event.get("entity_id", ""))) \
				as HunterView3D
			if view != null:
				view.brain.apply_stun(GameConfig.ESCAPE_STUN_DURATION)
				view.sync_from_brain()
				_store_hunter(String(event.get("entity_id", "")), view)


func _update_hunter_audio(delta: float, data: Dictionary) -> void:
	var nearest := INF
	var stepping: HunterView3D
	var stepping_distance := INF
	var chased := false
	var local_level := facility.current_level()
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	for entity_id in _hunter_views:
		if not _hunter_audio_on_floor(String(entity_id), local_level):
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
		_run_statistics["chases_started"] = int(
			_run_statistics.get("chases_started", 0)) + 1
	_was_chased = chased
	var danger := 0.0 if nearest == INF else clampf(
		1.0 - (nearest - .5) / 9.0, 0.0, 1.0)
	if chased:
		danger = maxf(danger, .48)
	if _player_in_intact_safe_room(data):
		danger = 0.0
	var warning := _afk_void_warning_progress()
	if warning > 0.0 and (pause_menu == null or not pause_menu.is_open()):
		danger = maxf(danger, lerpf(0.38, 0.92, warning))
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


func _hunter_audio_on_floor(entity_id: String, local_level: int) -> bool:
	# Audio never bleeds vertically. Cross-floor hunters remain fully simulated,
	# but only become audible after their authoritative level transfer completes.
	return int(_hunter_levels.get(entity_id, 999999)) == local_level


func _admin_give_item(item_id: String) -> void:
	var granted := player.grant_inventory_item(item_id)
	if granted:
		hud.show_message("ADMIN GIVE // %s" % String(
			PlayerController3D.INVENTORY_LABELS.get(item_id, item_id)).to_upper())
	else:
		hud.show_message("ADMIN GIVE FAILED // INVENTORY FULL")


func _admin_restore_player() -> void:
	if player.hidden:
		player.leave_hiding(Vector2.ZERO, true)
	player.restore_at_safe_zone()
	player.stun_timer = 0.0
	player.taser_cooldown = 0.0


func _respawn_after_death() -> void:
	if not _death_screen_open:
		return
	_force_disable_admin_cheats()
	run_report.close()
	_death_screen_open = false
	_capture_cooldown = 3.5
	player.global_position = _checkpoint_world_position()
	player.velocity = Vector3.ZERO
	player.stun_timer = 0.0
	player.look_frozen = false
	player.restore_at_safe_zone()
	pause_menu.set_process(true)
	pause_menu.set_process_unhandled_input(true)
	player.input_frozen = _awaiting_snapshot or hud.inventory_is_open() \
		or hud.map_is_open() \
		or (_admin_menu != null and _admin_menu.is_open()) \
		or (_room_chat != null and _room_chat.is_open()) \
		or (_story != null and _story.is_active())
	player.pesticide_timer = 0.0


func _admin_summon_hunter(hunter_id: String) -> void:
	_admin_world_action("summon_hunter", {"hunter_id": hunter_id})


func _admin_remove_hunter(hunter_id: String) -> void:
	_admin_world_action("remove_hunter", {"hunter_id": hunter_id})


func _admin_start_story(scene_id: String) -> void:
	_admin_world_action("story_start", {"scene_id": scene_id})


func _admin_stop_story() -> void:
	_admin_world_action("story_stop")


func _admin_reset_story() -> void:
	_admin_world_action("story_reset")


func _admin_world_action(action: String, payload: Dictionary = {}) -> void:
	var event := {"what": "admin_world", "action": action}
	for key in payload:
		event[key] = payload[key]
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
		hud.show_message("ADMIN // %s SENT TO HOST" % action.replace("_", " ").to_upper())
	else:
		_accept_stream_admin(multiplayer.get_unique_id() if RoomState.online else 1,
			event)


func _accept_stream_admin(peer_id: int, event: Dictionary) -> void:
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	var action := String(event.get("action", ""))
	var permission := _admin_action_permission(action)
	var allowed := Build.admin_permission(permission) if peer_id == local_id \
		else _remotes.remote_admin_peer_allowed(peer_id, permission)
	if permission.is_empty() or not allowed:
		_admin_feedback(peer_id, "ADMIN REQUEST REJECTED // PERMISSION REQUIRED")
		return
	match action:
		"grant_relay":
			_admin_collect_loaded_relays(false)
		"all_relays":
			_admin_collect_loaded_relays(true)
		"stun_hunters":
			for view_value in _hunter_views.values():
				var view := view_value as HunterView3D
				if view != null and view.brain != null:
					view.brain.apply_stun(GameConfig.TASER_STUN_SECONDS)
					view.sync_from_brain()
		"wake_hunters":
			var target := _target_state_for_peer(peer_id)
			var target_position: Vector2 = target.get("position", player.grid_position())
			for view_value in _hunter_views.values():
				var view := view_value as HunterView3D
				if view != null and view.brain != null:
					view.brain.activate_at(target_position)
					view.target_peer_id = peer_id
					view.sync_from_brain()
		"calm_hunters":
			for view_value in _hunter_views.values():
				var view := view_value as HunterView3D
				if view != null and view.brain != null:
					view.brain.calm_reset(2.0)
					view.sync_from_brain()
		"summon_hunter":
			_admin_summon_hunter_authoritative(peer_id,
				String(event.get("hunter_id", "")))
		"remove_hunter":
			_admin_remove_hunter_authoritative(peer_id,
				String(event.get("hunter_id", "")))
		"damage_checkpoint":
			_admin_edit_checkpoint(peer_id, -25)
		"repair_checkpoint":
			_admin_edit_checkpoint(peer_id, 25)
		"story_start":
			var scene_id := String(event.get("scene_id", ""))
			if _story == null or not _story.admin_scene_ids().has(scene_id) \
					or not _story.start_admin_scene(scene_id, true):
				_admin_feedback(peer_id, "ADMIN STORY FAILED // INVALID SCENE")
			else:
				_admin_feedback(peer_id, "ADMIN STORY STARTED // %s" % scene_id.to_upper())
		"story_stop":
			if _story == null or not _story.stop_admin_scene(true):
				_admin_feedback(peer_id, "ADMIN STORY // NOTHING ACTIVE")
		"story_reset":
			if _story != null and _story.reset_admin_story(true):
				_admin_feedback(peer_id, "ADMIN STORY STATE RESET")


func _admin_action_permission(action: String) -> String:
	if action in ["grant_relay", "all_relays", "damage_checkpoint",
			"repair_checkpoint", "story_start", "story_stop", "story_reset"]:
		return "world"
	if action in ["stun_hunters", "wake_hunters", "calm_hunters",
			"summon_hunter", "remove_hunter"]:
		return "hunters"
	return ""


func _admin_hunter_id_allowed(hunter_id: String) -> bool:
	return HunterRoster.A_Z_IDS.has(hunter_id) \
		or HunterRoster.VOID_IDS.has(hunter_id)


func _admin_feedback(peer_id: int, message: String) -> void:
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	if peer_id == local_id:
		hud.show_message(message)
	else:
		_remotes.send_player_event(peer_id, {"what": "message", "message": message})


func _admin_summon_hunter_authoritative(peer_id: int, hunter_id: String) -> void:
	if not _admin_hunter_id_allowed(hunter_id):
		return
	var target := _target_state_for_peer(peer_id)
	var target_position = target.get("position")
	if target.is_empty() or not target_position is Vector2:
		_admin_feedback(peer_id, "ADMIN SUMMON FAILED // RUNNER NOT AVAILABLE")
		return
	var level := -int(target.get("depth", 0))
	var navigation := _navigations.get(level) as StreamedHunterNavigation
	if navigation == null:
		var target_coord := Vector3i(
			floori(target_position.x / StreamedRouteGenerator.CHUNK_SIZE), level,
			floori(target_position.y / StreamedRouteGenerator.CHUNK_SIZE))
		navigation = StreamedHunterNavigation.new(facility.generator, level,
			world_state)
		navigation.refresh(level, [target_coord])
		_navigations[level] = navigation
	var blocked := {Vector2i(floori(target_position.x),
		floori(target_position.y)): true}
	for entity_id_value in world_state.hunters:
		var state: Dictionary = world_state.hunters[entity_id_value]
		if int(state.get("level", 999999)) != level:
			continue
		var occupied: Vector2 = state.get("position", Vector2.ZERO)
		blocked[Vector2i(floori(occupied.x), floori(occupied.y))] = true
	var facing: Vector2 = target.get("facing", Vector2.UP)
	if facing.length_squared() < .01:
		facing = Vector2.UP
	var side := Vector2(-facing.y, facing.x).normalized()
	var open := navigation.nearest_open_position(
		target_position.x + side.x * 2.5,
		target_position.y + side.y * 2.5, .28, blocked)
	if open.is_empty():
		_admin_feedback(peer_id, "ADMIN SUMMON FAILED // NO OPEN FLOOR")
		return
	var spawn_position := Vector2(float(open["x"]), float(open["y"]))
	var spawn_cell := Vector2i(floori(spawn_position.x), floori(spawn_position.y))
	var origin_chunk := navigation.cell_chunk(spawn_cell, level)
	var sequence := 1
	var entity_id := "ADMIN:%s:%d" % [hunter_id, sequence]
	while world_state.hunters.has(entity_id) \
			or world_state.removed_hunters.has(entity_id):
		sequence += 1
		entity_id = "ADMIN:%s:%d" % [hunter_id, sequence]
	var state := world_state.ensure_hunter({
		"id": entity_id,
		"hunter_id": hunter_id,
		"origin_chunk": origin_chunk,
		"cell": StreamedHunterNavigation.local_cell(spawn_cell),
		"level": level,
	})
	if state.is_empty():
		_admin_feedback(peer_id, "ADMIN SUMMON FAILED")
		return
	state["position"] = spawn_position
	state["active"] = true
	state["state"] = HunterBrain.State.SEARCH
	state["has_last_known"] = true
	state["last_known"] = target_position
	world_state.hunters[entity_id] = state
	_hunter_stream_signature = ""
	_refresh_hunter_stream()
	var view := _hunter_views.get(entity_id) as HunterView3D
	if view != null and view.brain != null:
		view.brain.activate_at(target_position)
		view.target_peer_id = peer_id
		view.sync_from_brain()
		_store_hunter(entity_id, view)
	_collect_hunter_report()
	_remotes.broadcast_hunters(_hunter_report)
	_remotes.broadcast_snapshot()
	_admin_feedback(peer_id, "ADMIN SUMMONED // %s" % String(
		HunterRoster.get_identity(hunter_id).get("display_name", hunter_id)).to_upper())


func _admin_remove_hunter_authoritative(peer_id: int, hunter_id: String) -> void:
	if not _admin_hunter_id_allowed(hunter_id):
		return
	var removed := 0
	for entity_id_value in world_state.hunters.keys().duplicate():
		var entity_id := String(entity_id_value)
		var state: Dictionary = world_state.hunters[entity_id]
		if String(state.get("hunter_id", "")) != hunter_id:
			continue
		_unload_hunter(entity_id, false)
		if world_state.remove_hunter(entity_id):
			removed += 1
	_hunter_stream_signature = ""
	_refresh_hunter_stream()
	_collect_hunter_report()
	_remotes.broadcast_hunters(_hunter_report)
	_remotes.broadcast_snapshot()
	var name := String(HunterRoster.get_identity(hunter_id).get(
		"display_name", hunter_id)).to_upper()
	_admin_feedback(peer_id, "ADMIN REMOVED // %s x%d" % [name, removed] \
		if removed > 0 else "ADMIN REMOVE // NO %s ACTIVE" % name)


func _admin_collect_loaded_relays(all_relays: bool) -> void:
	for coord in facility.loaded_horizontal_coords():
		for pickup_value in facility.generator.chunk(coord).get("pickups", []):
			var pickup: Dictionary = pickup_value
			var entity_id := String(pickup.get("id", ""))
			if String(pickup.get("kind", "")) != "relay" \
					or not world_state.pickup_available(entity_id):
				continue
			_publish_stream_event({"what": "stream_pickup", "entity_id": entity_id,
				"kind": "relay", "item": "", "winner_peer_id": 0,
				"message": "ADMIN // SIGNAL RELAY GRANTED"})
			if not all_relays:
				return


func _admin_edit_checkpoint(peer_id: int, amount: int) -> void:
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	var data := facility.current_chunk_data()
	if peer_id != local_id:
		var target := _target_state_for_peer(peer_id)
		var position = target.get("position")
		if not position is Vector2:
			return
		var level := -int(target.get("depth", 0))
		var coord := Vector3i(floori(position.x / StreamedRouteGenerator.CHUNK_SIZE),
			level, floori(position.y / StreamedRouteGenerator.CHUNK_SIZE))
		data = facility.generator.chunk(coord)
	if not bool(data.get("safe_room", false)):
		return
	var info: Dictionary = data.get("safe_room_data", {})
	var status := world_state.repair_safe_room(info, amount) if amount > 0 \
		else world_state.damage_safe_room(info, -amount)
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
	_force_disable_admin_cheats()
	get_tree().paused = false
	if RoomState.online and RoomState.is_host:
		# Keep the ENet room alive and return every connected runner to the same
		# staging screen. RoomState owns the authoritative reliable RPC.
		RoomState.end_session("HOST ENDED THE ROUTE // BACK IN STAGING")
	elif RoomState.online:
		# A guest cannot end the host's route. Disconnect only this peer and leave a
		# local staging room ready rather than dropping all the way to the title.
		RoomState.status_message = "LEFT THE ROUTE // BACK IN STAGING"
		RoomState.leave_network()
		get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")
	else:
		RoomState.session_active = false
		RoomState.status_message = "ROUTE SUSPENDED // BACK IN STAGING"
		get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")
