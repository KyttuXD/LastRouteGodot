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
## Floor chevrons (PATH guidance) cover only the next stretch of the route.
const WAYPOINT_TRAIL_METRES := 28.0
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
## Decides when hunters emote (host only); see docs/HUNTER_EMOTES.md.
var _hunter_emoter := HunterEmoter.new()
var _city_secrets := CitySecrets.new()   # City-only secret trigger (docs/SECRET_WOLF_SPIDER.md)
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
var _waypoint_change_msec := {}
var _arrival_chime_pending := false
var _waypoint_overlay: WaypointOverlay
var _waypoint_route: Array = []
var _waypoint_route_key := ""
var _waypoint_grid_signature := ""
var _waypoint_grid := AStarGrid2D.new()
var _waypoint_trail: MeshInstance3D
var _admin_reveal_map := false
## Region/biome overlay on the maps (admin only, default off): toggle in the admin menu or with REGION_MAP_KEY.
var _admin_region_map := false
var _admin_show_collision := false
var _collision_overlay: CollisionOverlay
const REGION_MAP_KEY := KEY_F8
var _admin_reveal_hunters := false
var _drop_nodes := {}
var pixel_signal_effect: PixelSignalEffect
var jumpscare: HunterJumpscare
var _story
var _death_screen_open := false
var _city_escaped := false
var _city_autosave_elapsed := 0.0
var _city_autosave_msec := -100000
var _death_moment: DeathMoment
var _last_death_cause := {}
## Spectator state: peer id of the followed runner (0 = free camera).
## How long a caught PUBLIC-route runner spectates before rejoining (scripts/public_test.gd stretches it).
static var public_spectate_seconds := 8.0
var _spectate_peer := 0
var _spectator_banner: SpectatorBanner
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
	_waypoint_overlay = WaypointOverlay.new()
	hud.add_child(_waypoint_overlay)
	Settings.visual_changed.connect(func() -> void: _waypoint_route_key = "")
	if RoomState.online and multiplayer.multiplayer_peer != null \
			and not multiplayer.peer_disconnected.is_connected(_on_waypoint_peer_left):
		multiplayer.peer_disconnected.connect(_on_waypoint_peer_left)
	_death_moment = DeathMoment.new()
	add_child(_death_moment)
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
	player.tool_context_probe = _tool_context_available
	player.item_drop_requested.connect(_on_item_drop_requested)
	player.interaction_veto = _stream_guardian_blocking
	player.vent_resolver = _use_streamed_vent
	hud.inventory_reorder_requested.connect(player.move_inventory_slot)
	hud.inventory_open_changed.connect(_on_inventory_open_changed)
	hud.map_open_changed.connect(_on_map_open_changed)
	hud.map_waypoint_requested.connect(_on_map_waypoint_requested)
	run_report.restart_requested.connect(_respawn_after_death)
	_spectator_banner = SpectatorBanner.attach(hud)
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
	var city_save: Dictionary = RoomState.pending_city_save if RoomState.is_city() and not RoomState.online else {}
	RoomState.pending_city_save = {}
	if not city_save.is_empty() and CityRunSave.valid(city_save):
		_adopt_city_save_before_stream(city_save)
		_loaded_from_save = true
	facility.begin(str(RoomState.run_seed()), player, world_state)
	if _loaded_from_save and not city_save.is_empty():
		player.global_position = Vector3(float(city_save["x"]), .05, float(city_save["z"]))
		player.rotation.y = float(city_save.get("yaw", PI))
		player._yaw = player.rotation.y
	elif not _loaded_from_save:
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
	pause_menu.abandon_label = "LEAVE THE CITY" if RoomState.is_city() else "LEAVE ROUTE"
	pause_menu.pauses_tree = not RoomState.online
	pause_menu.dismiss_overlay = _dismiss_gameplay_overlay
	if RoomState.online and RoomState.is_host:
		pause_menu.abandon_warning = \
			"This ends the route for everyone and returns the room to staging."
	elif RoomState.online:
		pause_menu.abandon_warning = \
			"This disconnects you and returns to staging. The host's route continues."
	elif RoomState.is_city():
		pause_menu.abandon_warning = "This ends the run and returns to the City menu. Signed-in runs save to your account as you go."
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
	if RoomState.public_route:
		_public_start()
	if _awaiting_snapshot:
		player.input_frozen = true
		hud.show_message("SYNCING ROUTE WITH HOST...")
	else:
		if _loaded_from_save:
			_sync_stream_progress()
			_sync_drop_nodes()
			hud.show_message("SAVED CITY RUN RESTORED" if RoomState.is_city() else "LOCAL SAVE RESTORED")
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
	_update_spectating()
	if RoomState.is_city():
		_city_autosave_elapsed += delta
		if _city_autosave_elapsed >= 45.0:
			_city_autosave_elapsed = 0.0
			_city_autosave()
	if _admin_show_collision and _collision_overlay != null:
		_collision_overlay.refresh(facility.loaded_chunk_data(), StreamedFacilityView3D.LEVEL_HEIGHT)
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
	_handle_waypoint_input(level)
	_update_waypoint_hud(level)
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
	hud.depth_label.text = _city_zone_line() if RoomState.is_city() else "LEVEL %+d // %s" % [coord.y, region]
	hud.update_infinite_status(GameState.relays_collected,
		facility.loaded_chunk_count(), _live_danger_percent(data))
	hud.set_public_line(PublicRoute.line() if RoomState.public_route else "")


## The City HUD names the zone the runner stands in (Avenue, Grand Plaza, Garden, Shelter ...), not a maze level/district.
func _city_zone_line() -> String:
	if facility != null and facility.has_method("zone_name") and player != null:
		return "THE CITY // %s" % String(facility.call("zone_name", player.global_position))
	return "THE CITY"


func _on_pickup_claimed(entity_id: String) -> void:
	# Collection-specific feedback is shown when the authoritative event is applied.
	pass


func _update_hud() -> void:
	var data := facility.current_chunk_data()
	var safe := _player_in_intact_safe_room(data)
	hud.update_infinite_status(GameState.relays_collected,
		facility.loaded_chunk_count(), _live_danger_percent(data))
	if RoomState.is_city():
		hud.depth_label.text = _city_zone_line()
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
	# hunters nearest first: name, state, distance
	var rows := []
	for view_value in _hunter_views.values():
		var hv := view_value as HunterView3D
		if hv == null or hv.brain == null:
			continue
		var d := hv.brain.position.distance_to(player.grid_position())
		rows.append([d, "%s %s %dm%s%s" % [String(HunterRoster.get_identity(hv.brain.hunter_id).get("display_name", hv.brain.hunter_id)).to_upper(),
			HunterBrain.State.keys()[hv.brain.state], int(d), " FROZEN" if hv.brain.stun_timer > 999.0 else ("" if hv.brain.active else " ASLEEP"),
			" STUCK %.1fs" % hv.brain.stuck_seconds if hv.brain.active and hv.brain.stuck_seconds >= 1.0 else ""]])
	rows.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	result += "\nHUNTERS (nearest)"
	for i in mini(rows.size(), 6):
		result += "\n  " + String(rows[i][1])
	if RoomState.public_route:
		result += "\nPUBLIC ROUTE: %s" % ("HOST" if RoomState.is_host else "GUEST")
	if GameState.debug_run:
		result += "\nDEBUG RUN // NOT RECORDED"
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
	var hunter_ids: Array = []
	hunter_ids.append_array(HunterRoster.A_Z_IDS)
	hunter_ids.append_array(HunterRoster.VOID_IDS)
	hunter_ids.append_array(SecretCreatures.admin_ids())   # admin picker only
	return [
		{"label": "REFRESH ADMIN ROSTER", "action": Backend.admin_roster_refresh,
			"owner_only": true, "no_debug": true},
		{"heading": "ITEMS", "label": "CREATIVE INVENTORY",
			"permission": "inventory",
			"items": PlayerController3D.COLLECTIBLE_ITEMS,
			"labels": PlayerController3D.INVENTORY_LABELS,
			"action": _admin_give_item},
		{"heading": "PLAYER", "permission": "player"},
		{"heading": "TELEPORT", "permission": "player",
			"items": ["north", "south", "east", "west", "safe_room", "relay", "start", "checkpoint"],
			"labels": {"north": "Chunk N", "south": "Chunk S", "east": "Chunk E", "west": "Chunk W",
				"safe_room": "Safe room", "relay": "Nearest relay", "start": "Start", "checkpoint": "Checkpoint"},
			"action": _admin_teleport_chunk},
		{"heading": "RUN SPEED", "permission": "player",
			"items": ["1", "1.5", "2", "3"],
			"labels": {"1": "1x", "1.5": "1.5x", "2": "2x", "3": "3x"},
			"action": func(id: String) -> void: player.admin_speed_scale = float(id)},
		{"label": "FULL LAMP", "permission": "player", "action": func() -> void:
			player.restore_lamp(GameConfig.MAX_LAMP_CHARGE)},
		{"label": "RESTORE PLAYER", "action": _admin_restore_player,
			"permission": "player"},
		{"label": "CLEAR STUN + COOLDOWNS", "permission": "player",
			"action": func() -> void:
			player.stun_timer = 0.0
			player.taser_cooldown = 0.0},
		{"label": "TOGGLE NO TARGET", "action": _admin_toggle_no_target,
			"permission": "player",
			"state": func() -> bool: return player.admin_no_target},
		{"label": "TOGGLE GOD MODE", "action": _admin_toggle_god_mode,
			"permission": "player",
			"state": func() -> bool: return player.admin_god_mode},
		{"label": "TOGGLE NOCLIP", "action": _admin_toggle_noclip,
			"permission": "player",
			"state": func() -> bool: return player.admin_noclip},
		{"heading": "HUNTERS", "permission": "hunters"},
		{"heading": "HUNTER", "permission": "hunters", "hunter_tool": [
			{"label": "Summon", "call": func(id: String, _extra: String) -> void: _admin_summon_hunter(id)},
			{"label": "Remove (all matches)", "call": func(id: String, _extra: String) -> void: _admin_remove_hunter(id)},
			{"label": "Play emote (nearby)", "emote": true, "call": func(_id: String, emote: String) -> void:
				_admin_world_action("hunter_emote", {"emote": emote})},
		], "hunters": hunter_ids, "hunter_labels": _hunter_admin_labels(hunter_ids),
			"emotes": _hunter_emote_ids(), "emote_labels": _hunter_emote_labels()},
		{"label": "STUN ALL HUNTERS", "permission": "hunters",
			"action": func() -> void: _admin_world_action("stun_hunters")},
		{"label": "WAKE ALL HUNTERS", "permission": "hunters",
			"action": func() -> void: _admin_world_action("wake_hunters")},
		{"label": "CALM ALL HUNTERS", "permission": "hunters",
			"action": func() -> void: _admin_world_action("calm_hunters")},
		{"label": "FREEZE ALL HUNTERS", "permission": "hunters",
			"action": func() -> void: _admin_world_action("freeze_hunters")},
		{"label": "RELEASE ALL HUNTERS", "permission": "hunters",
			"action": func() -> void: _admin_world_action("release_hunters")},
		{"heading": "WORLD", "permission": "world"},
		{"heading": "GAME SPEED // SOLO RUNS ONLY", "permission": "world",
			"items": ["0", "0.25", "1", "2", "4", "step"],
			"labels": {"0": "Pause", "0.25": "0.25x", "1": "1x", "2": "2x", "4": "4x", "step": "Step 1 frame"},
			"action": _admin_game_speed},
		{"label": "GRANT RELAY", "permission": "world", "action": func() -> void:
			_admin_world_action("grant_relay")},
		{"label": "ALL LOADED RELAYS", "permission": "world",
			"action": func() -> void: _admin_world_action("all_relays")},
		{"label": "DAMAGE CHECKPOINT", "permission": "world",
			"action": func() -> void: _admin_world_action("damage_checkpoint")},
		{"label": "REPAIR CHECKPOINT", "permission": "world",
			"action": func() -> void: _admin_world_action("repair_checkpoint")},
		{"label": "COPY SEED", "permission": "world", "no_debug": true,
			"action": func() -> void:
				DisplayServer.clipboard_set(str(facility.generator.world_seed))
				hud.show_message("SEED COPIED")},
		{"label": "COPY ROOM CODE", "permission": "world", "no_debug": true,
			"action": func() -> void:
				DisplayServer.clipboard_set(RoomState.code)
				hud.show_message("ROOM CODE COPIED")},
		{"label": "TOGGLE ALL REGION LIGHTS", "permission": "world",
			"action": func() -> void:
				facility.set_all_lights(not facility.all_lights_enabled()),
			"state": func() -> bool: return facility.all_lights_enabled()},
		{"heading": "STORY", "permission": "world"},
		{"heading": "PLAY STORY / CUTSCENE", "permission": "world",
			"items": _story.admin_scene_ids() if _story != null else [],
			"labels": _story.admin_scene_labels() if _story != null else {},
			"action": _admin_start_story},
		{"label": "STOP STORY / CUTSCENE", "permission": "world",
			"action": _admin_stop_story},
		{"label": "RESET STORY STATE", "permission": "world",
			"action": _admin_reset_story},
		{"heading": "VISUAL", "permission": "visual"},
		{"label": "TELEPORT TO WAYPOINT", "action": _admin_teleport_to_waypoint, "permission": "player"},
		{"label": "CLEAR WAYPOINT", "action": _clear_local_waypoint, "permission": "player"},
		{"label": "TOGGLE MAP REVEAL", "action": _admin_toggle_map_reveal,
			"permission": "visual",
			"state": func() -> bool: return _admin_reveal_map},
		{"label": "TOGGLE REGION MAP (F8)", "action": _admin_toggle_region_map,
			"permission": "visual",
			"state": func() -> bool: return _admin_region_map},
		{"label": "SHOW COLLISION", "action": _admin_toggle_show_collision,
			"permission": "visual",
			"state": func() -> bool: return _admin_show_collision},
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


## Teleport to world cell "X,Z" (the position readout's cell coordinates).
func _admin_teleport_coordinates(text: String) -> void:
	var parts := text.replace(";", ",").replace(" ", ",").split(",", false)
	if parts.size() < 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
		hud.show_message("ADMIN // TELEPORT NEEDS X,Z")
		return
	var at := Vector2(float(parts[0]), float(parts[1]))
	var spot := _nearest_valid_position(at)
	_admin_teleport_to(spot)


func _admin_roster_fields() -> Array:
	return [
		{"label": "TELEPORT TO CELL X,Z", "placeholder": "X,Z  (e.g. 120,-45)", "permission": "player",
			"on_submit": _admin_teleport_coordinates},
		{"label": "ADD / UPDATE LIMITED ADMIN",
			"placeholder": "USERNAME:player,world,hunters,visual,inventory",
			"on_submit": Backend.admin_roster_set_spec, "owner_only": true, "no_debug": true},
		{"label": "REMOVE LIMITED ADMIN", "placeholder": "USERNAME",
			"on_submit": Backend.admin_roster_remove, "owner_only": true, "no_debug": true},
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
	if RoomState.mode == RoomState.Mode.CITY:
		return "THE CITY SAVES ITSELF TO YOUR ACCOUNT"
	if RoomState.online and not RoomState.is_host:
		return "ONLY THE ROOM HOST CAN SAVE THE SHARED ROUTE"
	return ""


func _save_load_denial() -> String:
	if RoomState.mode == RoomState.Mode.CITY:
		return "CONTINUE A CITY RUN FROM THE CITY MENU"
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
			"waypoints": _active_waypoints(),   # legacy shape (array); the single waypoint also rides in world_state
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
		# older saves kept several waypoints: the most recent one survives, owned by the local player
		if waypoints is Array and not RoomState.online and not world_state.waypoints.has_for(1):
			world_state.waypoints.adopt_legacy(waypoints, 1)
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
	_admin_region_map = visual_tools and Settings.admin_preference("region_map")
	_set_show_collision(visual_tools and Settings.admin_preference("show_collision"))
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


func _admin_toggle_region_map() -> void:
	_admin_region_map = not _admin_region_map and Build.admin_permission("visual")
	Settings.set_admin_preference("region_map", _admin_region_map)
	if _admin_menu != null:
		_admin_menu._refresh()


func _admin_toggle_show_collision() -> void:
	_set_show_collision(not _admin_show_collision and Build.admin_permission("visual"))
	Settings.set_admin_preference("show_collision", _admin_show_collision)
	if _admin_menu != null:
		_admin_menu._refresh()


func _set_show_collision(enabled: bool) -> void:
	_admin_show_collision = enabled
	if _collision_overlay == null:
		_collision_overlay = CollisionOverlay.new()
		_collision_overlay.name = "CollisionOverlay"
		world.add_child(_collision_overlay)
	_collision_overlay.set_enabled(enabled)
	if enabled:
		_collision_overlay.refresh(facility.loaded_chunk_data(), StreamedFacilityView3D.LEVEL_HEIGHT)


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
	if player != null:
		player.admin_speed_scale = 1.0
	Engine.time_scale = 1.0
	_admin_reveal_hunters = false
	_admin_region_map = false
	_admin_reveal_map = false
	if _collision_overlay != null:
		_set_show_collision(false)
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
	_request_waypoint({"what": "stream_waypoint", "at": world_position, "level": level})


func _local_peer_id() -> int:
	return multiplayer.get_unique_id() if RoomState.online else 1


## The local player's one waypoint ({} when none).
func _local_waypoint() -> Dictionary:
	return world_state.waypoints.get_for(_local_peer_id())


## Every waypoint on the level (one per player), tagged "mine" for ours.
func _floor_waypoints(level: int) -> Array:
	return world_state.waypoints.on_level(level, _local_peer_id())


func _active_waypoints() -> Array:
	var mine := _local_waypoint()
	return [] if mine.is_empty() else [mine]


## Single entry for every way of changing a waypoint (crosshair, map click, arrival, admin): a guest asks the host, the host
## and offline runs decide here. {"at", "level"} places/replaces (the same cell again clears), {"clear": true} clears.
func _request_waypoint(event: Dictionary) -> void:
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction(event)
		return
	_accept_stream_waypoint(_local_peer_id(), event)


func _place_waypoint_at(at: Vector2, level: int) -> void:
	_request_waypoint({"what": "stream_waypoint", "at": at, "level": level})


func _clear_local_waypoint() -> void:
	if _local_waypoint().is_empty():
		return
	_request_waypoint({"what": "stream_waypoint", "clear": true})


func _clear_reached_waypoints(level: int) -> void:
	var player_at := Vector2(player.global_position.x, player.global_position.z)
	if world_state.waypoints.reached(_local_peer_id(), player_at, level):
		_arrival_chime_pending = true
		_clear_local_waypoint()


## A player who leaves takes their pin with them.
func _on_waypoint_peer_left(peer_id: int) -> void:
	if RoomState.is_host and world_state.waypoints.has_for(peer_id):
		_publish_stream_event({"what": "stream_waypoint", "peer_id": peer_id,
			"waypoint": {}, "message_peer_id": peer_id})


func _waypoint_feedback(placed: bool) -> void:
	if placed:
		Sound.menu_blip()
		hud.show_message("WAYPOINT SET")
	elif _arrival_chime_pending:
		_arrival_chime_pending = false
		if Settings.waypoint_arrival_chime:
			Sound.collect()
		hud.show_message("WAYPOINT REACHED")
	else:
		Sound.menu_blip()
		hud.show_message("WAYPOINT CLEARED")


## Where the crosshair lands on the floor (or on the open floor in front of the wall / prop it hits), as world XZ; {} when
## there is nothing within range. Marches the view ray over the same floor grid the hunters walk.
func _crosshair_waypoint_target() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var level := facility.current_level()
	var navigation := _navigations.get(level) as StreamedHunterNavigation
	if navigation == null:
		navigation = _navigation
	if navigation == null:
		return {}
	var floor_y := facility.streamed_surface_height(Vector2.ZERO, level)
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var last_open := Vector2.INF
	var distance := 0.0
	while distance <= WaypointState.MAX_PLACE_RANGE:
		var point := origin + direction * distance
		var open := navigation.is_floor(point.x, point.z)
		if point.y <= floor_y + .05:
			if open:
				return {"at": Vector2(point.x, point.z), "level": level}
			break
		if not open:
			break
		last_open = Vector2(point.x, point.z)
		distance += .25
	return {} if last_open == Vector2.INF else {"at": last_open, "level": level}


## The waypoint key: place where you look, or remove the waypoint when you look at it / stand on it. B2 clears outright.
func _handle_waypoint_input(level: int) -> void:
	if Input.is_action_just_pressed("waypoint_clear"):
		_clear_local_waypoint()
		return
	if not Input.is_action_just_pressed("waypoint"):
		return
	var target := _crosshair_waypoint_target()
	if target.is_empty():
		hud.show_message("NOWHERE TO PLACE A WAYPOINT")
		return
	_place_waypoint_at(target["at"], level)


func _update_waypoint_hud(level: int) -> void:
	if _waypoint_overlay == null:
		return
	var camera := get_viewport().get_camera_3d()
	var pins := []
	if camera != null:
		for waypoint_value in _floor_waypoints(level):
			var waypoint: Dictionary = waypoint_value
			var at: Vector2 = waypoint["at"]
			var owner_id := int(waypoint.get("peer_id", 0))
			pins.append({"world": Vector3(at.x, facility.streamed_surface_height(at, level) + 1.1, at.y),
				"mine": bool(waypoint.get("mine", false)),
				"name": "" if bool(waypoint.get("mine", false)) else RoomState.peer_display_name(owner_id),
				"peer_id": owner_id})
	_waypoint_overlay.visible = not hud.map_is_open()
	_waypoint_overlay.set_pins(pins, camera, player.global_position)


func _admin_teleport_to_waypoint() -> void:
	var mine := _local_waypoint()
	if mine.is_empty():
		hud.show_message("ADMIN // NO WAYPOINT SET")
		return
	var at: Vector2 = mine["at"]
	_admin_teleport_to(Vector3(at.x, float(int(mine.get("level", 0))) * StreamedFacilityView3D.LEVEL_HEIGHT, at.y))


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
	var show_admin_regions := Build.admin_permission("visual") and _admin_region_map
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
	var mine := _local_waypoint()
	var player_cell := Vector2i(floori(player.global_position.x),
		floori(player.global_position.z))
	var destination := Vector2i(-2147483648, 0)
	if not mine.is_empty() and int(mine.get("level", level)) == level:
		var at: Vector2 = mine["at"]
		destination = Vector2i(floori(at.x), floori(at.y))
	var route_key := "%d:%s:%s:%d:%s" % [level, player_cell, destination,
		_discovered_chunks.size(), Settings.waypoint_guidance]
	if route_key == _waypoint_route_key:
		return
	_waypoint_route_key = route_key
	_waypoint_route.clear()
	if destination.x != -2147483648:
		var segment := _waypoint_path(player_cell, destination, level)
		for index in segment.size():
			_waypoint_route.append(Vector2(segment[index]) + Vector2(.5, .5))
	_update_waypoint_ground_trail(level)


## The route to a waypoint: the live floor grid first (it covers everything streamed in, so the City, whose chunks are all
## resident, and undiscovered maze floor both work), then the map-discovered floor as a fallback.
func _waypoint_path(from_cell: Vector2i, to_cell: Vector2i, level: int) -> Array:
	var navigation := _navigations.get(level) as StreamedHunterNavigation
	if navigation == null:
		navigation = _navigation
	if navigation != null:
		var live: Array = navigation.find_path(from_cell, to_cell)
		if not live.is_empty():
			return live
	return _discovered_waypoint_path(from_cell, to_cell, level)


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


## PATH guidance: small chevrons on the floor along the next WAYPOINT_TRAIL_METRES of the route (nothing in off/arrow mode).
func _update_waypoint_ground_trail(level: int) -> void:
	if _waypoint_trail == null:
		return
	if Settings.waypoint_guidance != "path" or _waypoint_route.size() < 2:
		_waypoint_trail.mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := facility.streamed_surface_height(Vector2.ZERO, level) + .035
	var travelled := 0.0
	var next_chevron := 1.0
	for index in _waypoint_route.size() - 1:
		var from_2d: Vector2 = _waypoint_route[index]
		var to_2d: Vector2 = _waypoint_route[index + 1]
		var length := from_2d.distance_to(to_2d)
		if length <= .0001:
			continue
		var direction := (to_2d - from_2d) / length
		while next_chevron <= travelled + length:
			if next_chevron > WAYPOINT_TRAIL_METRES:
				break
			var centre := from_2d + direction * (next_chevron - travelled)
			var side := direction.orthogonal() * .28
			var tip := centre + direction * .3
			var back := centre - direction * .18
			for vertex in [tip, back + side, back - side]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(Vector3(vertex.x, height, vertex.y))
			next_chevron += 1.6
		travelled += length
		if travelled > WAYPOINT_TRAIL_METRES:
			break
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
	if RoomState.is_day() and population_limit > 1:
		population_limit = maxi(1, int(floor(float(population_limit) * GameConfig.DAY_POPULATION_SCALE)))
	if RoomState.public_route:
		# Players online, not relays, size the PUBLIC population.
		population_limit = maxi(PublicRoute.hunter_target_count(),
			PublicRoster.target_count(RoomState.peers.size()))
	for spawn in candidates:
		# Admin removals consume the corresponding pressure slot until future
		# relay progress raises the desired population again. Otherwise the same
		# deterministic window immediately replaces a hunter the admin removed.
		if desired.size() + world_state.removed_hunters.size() >= population_limit:
			break
		var entity_id := String(spawn.get("id", ""))
		var admitted_spawn := spawn.duplicate(true)
		var proposed_id := String(admitted_spawn.get("hunter_id", ""))
		if RoomState.public_route:
			proposed_id = _public_next_identity(proposed_id)
			admitted_spawn["hunter_id"] = proposed_id
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
		if entity_id.begins_with("ADMIN:") or entity_id.begins_with("SECRET:"):
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
	_configure_day_vision(view.brain)
	world_state.restore_hunter(view.brain, state)
	view.surface_height_provider = facility.streamed_surface_height.bind(level)
	view.set_meta("streamed_entity_id", entity_id)
	view.add_to_group("streamed_hunter")
	world.add_child(view)
	view.sync_from_brain()
	_hunter_views[entity_id] = view
	_hunter_origins[entity_id] = state.get("origin_chunk", Vector3i.ZERO)
	_hunter_levels[entity_id] = level


## City daytime: the brain sees by the sun outdoors and by the night rules indoors (see HunterBrain.sight_limit_for).
func _configure_day_vision(brain: HunterBrain) -> void:
	brain.day_mode = RoomState.is_day()
	if brain.day_mode and facility.generator is CityRouteGenerator:
		var city_generator := facility.generator as CityRouteGenerator
		brain.indoor_check = city_generator.is_indoor_route_position


func _unload_hunter(entity_id: String, persist_state: bool = true) -> void:
	var view := _hunter_views.get(entity_id) as HunterView3D
	if view != null and is_instance_valid(view):
		if persist_state and (_remotes == null or _remotes.simulates()):
			_store_hunter(entity_id, view)
		view.queue_free()
	_hunter_views.erase(entity_id)
	_hunter_origins.erase(entity_id)
	_hunter_levels.erase(entity_id)
	_hunter_emoter.forget(entity_id)


func _store_hunter(entity_id: String, view: HunterView3D) -> void:
	world_state.store_hunter(entity_id, view.brain,
		int(_hunter_levels.get(entity_id, facility.current_level())),
		_hunter_origins.get(entity_id, Vector3i.ZERO))


func _update_hunters(delta: float, _data: Dictionary) -> void:
	if _remotes == null or not _remotes.simulates():
		return
	_city_secrets.update(self, delta)
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
		if RoomState.public_route:
			activation_relays = 0   # the shared route is always hunted
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
			if RoomState.public_route:
				_assign_public_patrol(entity_id, view)
			view.brain.update_without_target(delta, navigation,
				maxi(1, -level + 1), GameState.relays_collected)
		_hunter_emoter.tick(entity_id, view.brain, delta, {"target_distance": view.brain.position.distance_to(
			target["position"]) if not target.is_empty() else INF})
		view.sync_from_brain()
		for hunter_event_value in view.brain.world_events:
			_apply_gimmick_signal(hunter_event_value, view, target)
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


## Gimmick events that are not shared-world mutations: a toast, a player stun, a facility-wide alarm. The finite route
## handles these in main_3d.gd; the streamed route used to drop them silently.
func _apply_gimmick_signal(event: Dictionary, source: HunterView3D, target: Dictionary) -> void:
	match String(event.get("what", "")):
		"message":
			var note := String(event.get("message", ""))
			if String(event.get("sound", "")) == "alert":
				Sound.alert()
			if not note.is_empty():
				hud.show_message(note)
		"hiding_disabled":
			var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			for spot_value in get_tree().get_nodes_in_group("streamed_hiding_spot"):
				var spot := spot_value as RouteInteractable3D
				if spot != null and spot.source_cell == cell:
					spot.set_disabled(bool(event.get("disabled", false)))
		"stun":
			if not target.is_empty():
				_remotes.send_player_event(int(target.get("peer_id", 1)), {"what": "stun",
					"seconds": float(event.get("seconds", 0.0)), "message": String(event.get("message", ""))})
		"facility_alert":
			Sound.alert()
			var at: Vector2 = event.get("at", Vector2.ZERO)
			var except_id := String(event.get("except", ""))
			for other_value in _hunter_views.values():
				var other := other_value as HunterView3D
				if other == null or other == source or other.brain == null or not other.brain.active \
						or other.brain.hunter_id == except_id:
					continue
				other.brain.state = HunterBrain.State.INVESTIGATE
				other.brain.has_last_known = true
				other.brain.last_known = at
			var alert_note := String(event.get("message", ""))
			if not alert_note.is_empty():
				hud.show_message(alert_note)


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
		"map_open": hud.map_is_open(),
		"no_target": player.admin_no_target,
		"god_mode": player.admin_god_mode,
		"escape_active": GameState.escape_active,
		"capture_immune": _capture_cooldown > 0.0 or GameState.is_capture_immune(),
		"game_over": _death_screen_open or player.spectator_mode,
		"spectating": player.spectator_mode,
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


## Runners other than `except_peer` who are still playing (not dead, not spectating).
func _runners_alive_except(except_peer: int) -> int:
	var count := 0
	var local_target := _hunter_target(false)
	for target_value in _remotes.target_states(local_target):
		var target: Dictionary = target_value
		if int(target.get("peer_id", 0)) == except_peer or bool(target.get("game_over", false)) \
				or bool(target.get("spectating", false)):
			continue
		count += 1
	return count


## Host: a runner died. The hunter that got them gloats while others live (smug/dance/laugh), and everyone nearby
## poses at a party wipe. `hunter_id` may be empty (a guest's report): the nearest hunter is used.
func _hunters_gloat(peer_id: int, hunter_id: String) -> void:
	if _remotes == null or not _remotes.simulates():
		return
	var victim := _target_state_for_peer(peer_id)
	var at: Vector2 = victim.get("position", player.grid_position())
	var others := _runners_alive_except(peer_id) > 0
	var nearest: HunterView3D
	var nearest_distance := INF
	for entity_value in _hunter_views:
		var view := _hunter_views[entity_value] as HunterView3D
		if view == null or view.brain == null or not view.brain.active:
			continue
		var distance := view.brain.position.distance_to(at)
		if not others and distance < 30.0:
			_hunter_emoter.on_party_wipe(String(entity_value), view.brain)
		if (hunter_id.is_empty() or view.brain.hunter_id == hunter_id) and distance < nearest_distance:
			nearest = view
			nearest_distance = distance
	if others and nearest != null and nearest_distance < 12.0:
		_hunter_emoter.on_catch(String(nearest.get_meta("streamed_entity_id", "")), nearest.brain, true)


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


## True when the scene has a use for the tool in hand right here: a safe room to repair, or (axe) a grabbed teammate to cut free. Without one a
## swing is a free whoosh: no durability, no noise and no deny blip.
func _tool_context_available(item_id: String) -> bool:
	if item_id not in ["crowbar", "rescue_axe"]:
		return false
	if item_id == "rescue_axe" and not _grabbed_teammate_in_reach().is_empty():
		return true
	return _safe_room_repair_in_reach()


func _safe_room_repair_in_reach() -> bool:
	var data := facility.current_chunk_data()
	if not bool(data.get("safe_room", false)):
		return false
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	var center := Vector2((coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
		(coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
	return player.grid_position().distance_to(center) <= 4.25


const AXE_RESCUE_REACH := 3.4


## The teammate (if any) caught in a hunter's hold within reach of the axe: {"peer_id": ...} or empty.
func _grabbed_teammate_in_reach() -> Dictionary:
	if not RoomState.online:
		return {}
	var local_id := multiplayer.get_unique_id()
	for state in _remotes.target_states({}):
		var peer := int(state.get("peer_id", 0))
		var at = state.get("at")
		if peer == local_id or peer <= 0 or not bool(state.get("escape_active", false)) \
				or not at is Vector3 or bool(state.get("spectating", false)):
			continue
		if (at as Vector3).distance_to(player.global_position) <= AXE_RESCUE_REACH:
			return {"peer_id": peer}
	return {}


func _on_tool_used(item_id: String) -> void:
	if item_id not in ["crowbar", "rescue_axe"]:
		return
	if item_id == "rescue_axe":
		var grabbed := _grabbed_teammate_in_reach()
		if not grabbed.is_empty():
			var request := {"what": "stream_axe_rescue", "target_peer": int(grabbed["peer_id"])}
			if RoomState.is_host:
				_accept_axe_rescue(multiplayer.get_unique_id(), request)
			else:
				_remotes.request_interaction(request)
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
		"stream_axe_rescue":
			_accept_axe_rescue(peer_id, event)
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
	var now := Time.get_ticks_msec()
	if peer_id != _local_peer_id():
		if now - int(_waypoint_change_msec.get(peer_id, -100000)) < WaypointState.MIN_CHANGE_INTERVAL_MSEC:
			return
		_waypoint_change_msec[peer_id] = now
	var current := world_state.waypoints.get_for(peer_id)
	var waypoint := {}
	if not bool(event.get("clear", false)):
		var at = event.get("at")
		if not at is Vector2:
			return
		var level := int(event.get("level", 999999))
		if RoomState.online:
			var target := _target_state_for_peer(peer_id)
			if target.is_empty() or level != -int(target.get("depth", 0)):
				return
		var snapped := Vector2(floori(at.x) + .5, floori(at.y) + .5)
		var same_spot: bool = not current.is_empty() and int(current.get("level", level)) == level \
			and (current["at"] as Vector2).distance_to(snapped) <= .1
		if not same_spot:
			waypoint = {"at": snapped, "level": level, "peer_id": peer_id}
	elif current.is_empty():
		return
	_publish_stream_event({"what": "stream_waypoint", "peer_id": peer_id,
		"waypoint": waypoint, "message_peer_id": peer_id})


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
	if kind == "gate" and GameState.relays_collected < CityLayout.gate_relays_required(RoomState.difficulty_id()):
		var needed := CityLayout.gate_relays_required(RoomState.difficulty_id())
		var denied := "THE GATE STAYS SHUT // %d / %d RELAYS" % [GameState.relays_collected, needed]
		if not RoomState.online or peer_id == multiplayer.get_unique_id():
			hud.show_message(denied)
			Sound.interaction_fail()
		else:
			_remotes.send_player_event(peer_id, {"what": "message", "message": denied})
		return
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


## Host-authoritative: a teammate swinging the rescue axe frees a grabbed player in reach. The host checks that the swinger really holds the axe,
## that the target is mid-struggle and within reach of the swinger, then tells the victim, whose own client resolves the struggle (and stuns the
## hunter through the normal "escaped" report).
func _accept_axe_rescue(peer_id: int, event: Dictionary) -> void:
	var target_peer := int(event.get("target_peer", 0))
	if target_peer <= 0 or target_peer == peer_id:
		return
	var swinger := _target_state_for_peer(peer_id)
	var owned = swinger.get("owned_items", {})
	if swinger.is_empty() or not owned is Dictionary or not bool(owned.get("rescue_axe", false)):
		return
	var victim := _target_state_for_peer(target_peer)
	var victim_at = victim.get("at")
	var swinger_at = swinger.get("at")
	var victim_grabbed := bool(victim.get("escape_active", false))
	if target_peer == _local_peer_id():
		victim_grabbed = GameState.escape_active
		victim_at = player.global_position
	if not victim_grabbed or not victim_at is Vector3 or not swinger_at is Vector3 \
			or (victim_at as Vector3).distance_to(swinger_at as Vector3) > AXE_RESCUE_REACH + .8:
		return
	_remotes.send_player_event(target_peer, {"what": "axe_rescue", "rescuer_peer_id": peer_id,
		"message": "RESCUE AXE // A TEAMMATE CUT YOU FREE"})
	if peer_id != _local_peer_id():
		_remotes.send_player_event(peer_id, {"what": "message",
			"message": "RESCUE AXE // TEAMMATE FREED"})


func _accept_safe_repair(peer_id: int, event: Dictionary) -> void:
	var room := _safe_room_for_peer(peer_id, String(event.get("room_id", "")), 4.25)
	var item_id := String(event.get("item", ""))
	var target := _target_state_for_peer(peer_id)
	var owned = target.get("owned_items", {})
	if room.is_empty() or item_id not in ["crowbar", "rescue_axe"] \
			or not owned is Dictionary or not bool(owned.get(item_id, false)):
		return
	var info: Dictionary = room.get("safe_room_data", {})
	var status := world_state.repair_safe_room(info, 18 if item_id == "rescue_axe" else 12)
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
		"stream_respawn":
			for id_value in event.get("ids", []):
				world_state.claimed_pickups.erase(String(id_value))
			_sync_stream_progress()
			facility.refresh_mutations()
		"stream_pickup":
			var entity_id := String(event.get("entity_id", ""))
			if not facility.apply_pickup_claim(entity_id):
				return
			_sync_stream_progress()
			if String(event.get("kind", "")) == "gate":
				_city_escape(int(event.get("winner_peer_id", 0)))
				return
			_city_autosave()
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
			var owner_id := int(event.get("peer_id", 0))
			if waypoint is Dictionary and owner_id > 0 \
					and world_state.waypoints.apply(owner_id, waypoint):
				_waypoint_route_key = ""
				if owner_id == _local_peer_id():
					_waypoint_feedback(not (waypoint as Dictionary).is_empty())
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


# -- PUBLIC route -----------------------------------------------------------------------

func _public_start() -> void:
	PublicRoute.attach_scene(self)
	if RoomState.is_host:
		_public_restore_authority()
		_apply_public_resume()


## A new authority restores the route from the backend's copy: claimed relays and
## items, then the last hunter snapshot (applied after the remotes exist).
func _public_restore_authority() -> void:
	for id_value in PublicRoute.claimed_ids:
		world_state.claimed_pickups[String(id_value)] = true
	var snapshot := PublicRoute.decode_snapshot()
	if not snapshot.is_empty() and int(snapshot.get("seed", 0)) == RoomState.run_seed() \
			and snapshot.get("world_state") is Dictionary and snapshot.get("hunters") is Array:
		if world_state.adopt(snapshot["world_state"]):
			for id_value in PublicRoute.claimed_ids:
				world_state.claimed_pickups[String(id_value)] = true
			_apply_hunter_report.call_deferred(snapshot["hunters"])
	_sync_stream_progress()
	facility.refresh_mutations()
	hud.show_message("PUBLIC ROUTE RESTORED // %d RELAYS" % GameState.relays_collected)


## Back to where the runner was, never the hub unless that spot is not valid.
func _apply_public_resume() -> void:
	var saved := PublicRoute.resume
	if saved.is_empty():
		return
	PublicRoute.resume = {}
	var position: Dictionary = saved.get("position", {}) if saved.get("position") is Dictionary else {}
	if not position.is_empty():
		var spot := _nearest_valid_position(Vector2(float(position.get("x", 0.0)),
			float(position.get("z", 0.0))))
		player.global_position = spot
		player.velocity = Vector3.ZERO
		facility.refresh_at_tracked_player()
	var order: Array = player.inventory_order.duplicate()
	var durability: Array = player.inventory_slot_durability.duplicate()
	var restored := false
	for entry_value in saved.get("inventory", []):
		var entry: Dictionary = entry_value
		var slot := int(entry.get("slot", -1))
		var item_id := String(entry.get("id", ""))
		if slot < 0 or slot >= order.size() or not PlayerController3D.INVENTORY_ITEMS.has(item_id):
			continue
		order[slot] = item_id
		var maximum := int(PlayerController3D.INVENTORY_MAX_DURABILITY.get(item_id, 0))
		durability[slot] = mini(int(entry.get("durability", 0)), maximum) if maximum > 0 \
			else int(entry.get("durability", 0))
		restored = true
	if restored:
		player.inventory_order = order
		player.inventory_slot_durability = durability
	hud.show_message("RESUMED YOUR PLACE ON THE PUBLIC ROUTE")


## Nearest walkable cell to a saved world position, searched outward; the hub
## (spawn) only if nothing within 12 cells is open.
func _nearest_valid_position(world_xz: Vector2) -> Vector3:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	for radius in 13:
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var cell_x := floori(world_xz.x) + dx
				var cell_z := floori(world_xz.y) + dz
				var coord := Vector3i(floori(float(cell_x) / size), 0, floori(float(cell_z) / size))
				var data := facility.generator.chunk(coord)
				var local_x := posmod(cell_x, size)
				var local_z := posmod(cell_z, size)
				if int((data["grid"] as Array)[local_z][local_x]) == 0 \
						and facility.generator.is_chunk_allowed(coord):
					return Vector3(cell_x + .5, .05, cell_z + .5)
	return facility.spawn_position()


func apply_public_respawns(ids: Array) -> void:
	for id_value in ids:
		world_state.claimed_pickups.erase(String(id_value))
	_sync_stream_progress()
	facility.refresh_mutations()
	_remotes.relay_world_event({"what": "stream_respawn", "ids": ids})


## Today's lineup: the featured pair first, then the day-mixed weighted draw. The
## first identity of that lineup not already hunting takes the next slot.
func _public_next_identity(fallback: String) -> String:
	var day := String(PublicRoute.server.get("day", ""))
	var used := {}
	for state_value in world_state.hunters.values():
		used[String((state_value as Dictionary).get("hunter_id", ""))] = true
	for id in PublicRoster.lineup(RoomState.seed_text, day):
		if not used.has(String(id)):
			return String(id)
	return fallback


const PUBLIC_PATROL_DWELL_MSEC := 20_000
var _public_patrol := {}


## Idle hunters patrol around a real runner (the one fewest other hunters are on),
## re-rolled every few seconds, so nobody is safe just by being far from the hub.
func _assign_public_patrol(entity_id: String, view: HunterView3D) -> void:
	var now := Time.get_ticks_msec()
	var entry: Dictionary = _public_patrol.get(entity_id, {})
	if entry.is_empty() or now >= int(entry.get("until", 0)):
		var runners := _public_runner_positions()
		if runners.is_empty():
			view.brain.has_patrol_anchor = false
			return
		var load_by_peer := {}
		for other_id in _public_patrol:
			if other_id != entity_id:
				var peer := int((_public_patrol[other_id] as Dictionary).get("peer", 0))
				load_by_peer[peer] = int(load_by_peer.get(peer, 0)) + 1
		var best_peer := -1
		var best_load := 1 << 30
		var keys: Array = runners.keys()
		keys.sort()
		for peer_value in keys:
			var load := int(load_by_peer.get(peer_value, 0))
			if load < best_load:
				best_load = load
				best_peer = int(peer_value)
		entry = {"peer": best_peer, "until": now + PUBLIC_PATROL_DWELL_MSEC}
		_public_patrol[entity_id] = entry
	var runner_positions := _public_runner_positions()
	var anchor = runner_positions.get(int(entry.get("peer", -1)))
	if anchor is Vector2:
		view.brain.has_patrol_anchor = true
		view.brain.patrol_anchor = anchor
	else:
		view.brain.has_patrol_anchor = false


## Hunt-able runners (not in a safe room): peer id -> grid position.
func _public_runner_positions() -> Dictionary:
	var result := {}
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	if not _player_in_intact_safe_room(facility.current_chunk_data()):
		result[local_id] = player.grid_position()
	if _remotes != null:
		for target_value in _remotes.target_states({}):
			var target: Dictionary = target_value
			if bool(target.get("in_safe_zone", false)) or not target.get("position") is Vector2:
				continue
			result[int(target.get("peer_id", 0))] = target["position"]
	return result


## Captured on the PUBLIC route: watch from a free camera, then come back on your
## own after a few seconds (no run report, nobody has to press anything).
func _public_spectate_then_rejoin(hunter_name: String) -> void:
	_begin_spectating()
	if RoomState.online and not RoomState.is_host:
		_remotes.submit_hunter_event({"what": "caught"})
	hud.show_message("CAUGHT BY %s // SPECTATING // REJOINING SHORTLY" % hunter_name)
	_capture_resolving = false
	await get_tree().create_timer(public_spectate_seconds).timeout
	if not is_inside_tree() or not RoomState.public_route:
		return
	_end_spectating()
	_respawn_after_death()
	PublicRoute.join_grace_until_msec = Time.get_ticks_msec() + 10_000
	hud.show_message("BACK ON THE ROUTE // GRACE PERIOD")


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
	if RoomState.public_route:
		_apply_public_resume()


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
			if player.spectator_mode:
				if RoomState.online and not RoomState.is_host:
					_remotes.submit_hunter_event({"what": "caught"})
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
		"axe_rescue":
			if GameState.escape_active:
				_resolve_escape_success(true, String(event.get("message", "")))
		"stun":
			player.stun_timer = maxf(player.stun_timer, float(event.get("seconds", 0.0)))
			var stun_note := String(event.get("message", ""))
			if not stun_note.is_empty():
				hud.show_message(stun_note)
		"revive":
			if player.spectator_mode and not RoomState.is_host:
				_end_spectating()
				_death_screen_open = true
				_respawn_after_death()
				hud.show_message("RUN RESTARTED // BACK ON THE ROUTE")


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
	if player.owns_inventory_item("rescue_axe"):
		hud.show_message("RESCUE AXE // CLICK TO CUT FREE")
	if jumpscare != null:
		jumpscare.start_hold(player.active_camera(), hunter_id)


func _update_escape_struggle(delta: float) -> void:
	# The rescue axe cuts the hold: one click, then the grab is gone and the hunter is staggered for twice as long. It costs a third of the axe.
	if Input.is_action_just_pressed("tool_use") and MouseLock.is_captured() \
			and player.owns_inventory_item("rescue_axe") \
			and player.consume_item_durability("rescue_axe", PlayerController3D.AXE_BREAK_FREE_COST):
		player.swing_axe_for_escape()
		_resolve_escape_success(true, "RESCUE AXE // CUT FREE")
		return
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


func _resolve_escape_success(with_axe: bool = false, note: String = "") -> void:
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
			view.brain.apply_stun(GameConfig.ESCAPE_STUN_DURATION * (2.0 if with_axe else 1.0))
			view.sync_from_brain()
			_store_hunter(_escaping_entity_id, view)
	else:
		_remotes.submit_hunter_event({"what": "escaped",
			"entity_id": _escaping_entity_id, "hunter_id": _escaping_hunter_id,
			"axe": with_axe})
	hud.show_message(note if not note.is_empty() else "You broke free!")
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
	_hunters_gloat(multiplayer.get_unique_id() if RoomState.online else 1, hunter_id)
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
	if HunterJumpscare.ENABLED:
		Sound.office_jumpscare(hunter_id)
	if jumpscare != null:
		await jumpscare.play(player.active_camera(), hunter_id)
	# The death moment is only an overlay: online the spectator hand-off below happens at once, solo the run card
	# waits for it so the line is read before the end card.
	_last_death_cause = _death_cause(hunter_id)
	var moment := _death_moment_for(hunter_id, _last_death_cause)
	if RoomState.public_route or RoomState.online:
		_play_death_moment(hunter_name, moment, hunter_id)
	else:
		await _play_death_moment(hunter_name, moment, hunter_id)
	if RoomState.public_route:
		await _public_spectate_then_rejoin(hunter_name)
		return
	if RoomState.online and not RoomState.is_host:
		_begin_spectating()
		_remotes.submit_hunter_event({"what": "caught"})
		hud.show_message("YOU DIED // SPECTATOR MODE")
		_capture_resolving = false
		return
	# Host caught while a guest still lives: keep the host-authoritative hunter
	# simulation running and watch instead of ending the session.
	if RoomState.online and RoomState.is_host and not _living_runners().is_empty():
		_begin_spectating()
		_death_screen_open = false
		_capture_cooldown = 0.0
		pause_menu.set_process(true)
		pause_menu.set_process_unhandled_input(true)
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


## The cause the death line is drawn for: Nyxie's dead lamp or her darkness timer, otherwise an ordinary catch.
func _death_cause(hunter_id: String) -> Dictionary:
	var cause := {"hunter_id": hunter_id, "via": "contact", "detail": ""}
	if hunter_id == "nyxie":
		cause["detail"] = "darkness"
		for view_value in _hunter_views.values():
			var view := view_value as HunterView3D
			if view != null and view.brain != null and view.brain.hunter_id == "nyxie" \
					and view.brain.gimmick != null and view.brain.gimmick.capture_is_inescapable():
				cause["detail"] = "lamp"
	return cause


func _death_moment_for(hunter_id: String, cause_override: Dictionary = {}) -> Dictionary:
	var cause := cause_override if not cause_override.is_empty() else _death_cause(hunter_id)
	var name := String(HunterRoster.get_identity(String(cause["hunter_id"])).get("display_name", hunter_id))
	return DeathLines.pick(cause, RoomState.seed_text, -facility.current_level(), name)


func _play_death_moment(hunter_name: String, picked: Dictionary, hunter_id: String) -> void:
	if _death_moment == null or not DeathMoment.plays(picked):
		return
	await _death_moment.play(hunter_name, picked, HunterRoster.VOID_IDS.has(hunter_id))


func _apply_hunter_event(event: Dictionary) -> void:
	if RoomState.online and not RoomState.is_host:
		return
	match String(event.get("what", "")):
		"taser":
			_resolve_taser(int(event.get("peer_id",
				multiplayer.get_unique_id() if RoomState.online else 1)))
		"caught":
			_hunters_gloat(int(event.get("peer_id", 0)), "")
		"escaped":
			var view := _hunter_views.get(String(event.get("entity_id", ""))) \
				as HunterView3D
			if view != null:
				view.brain.apply_stun(GameConfig.ESCAPE_STUN_DURATION \
					* (2.0 if bool(event.get("axe", false)) else 1.0))
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


## Runners (excluding the local player) who are neither dead nor spectating.
func _living_runners() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _remotes == null:
		return result
	for target_value in _remotes.target_states({}):
		var target: Dictionary = target_value
		if not bool(target.get("game_over", false)) \
				and not bool(target.get("spectating", false)):
			result.append(target)
	return result


func _begin_spectating() -> void:
	player.enter_spectator()
	player.input_frozen = false
	player.look_frozen = false
	_spectate_peer = 0
	_cycle_spectate_target(1)


func _end_spectating() -> void:
	if player.spectator_mode:
		player.leave_spectator()
	_spectate_peer = 0
	if _spectator_banner != null:
		_spectator_banner.clear()


## dir: +1 / -1 steps through living runners; 0 selects the free camera.
func _cycle_spectate_target(dir: int) -> void:
	var living := _living_runners()
	if dir == 0 or living.is_empty():
		_spectate_peer = 0
		return
	var index := -1
	for i in living.size():
		if int(living[i].get("peer_id", 0)) == _spectate_peer:
			index = i
	index = 0 if index < 0 and dir > 0 else (living.size() - 1 if index < 0 \
		else posmod(index + dir, living.size()))
	_spectate_peer = int(living[index].get("peer_id", 0))


func _update_spectating() -> void:
	if not player.spectator_mode:
		return
	var watching := {}
	if _spectate_peer != 0:
		for target in _living_runners():
			if int(target.get("peer_id", 0)) == _spectate_peer:
				watching = target
		if watching.is_empty():
			_cycle_spectate_target(1)
			for target in _living_runners():
				if int(target.get("peer_id", 0)) == _spectate_peer:
					watching = target
	player.spectator_follow_valid = not watching.is_empty() \
		and watching.get("at") is Vector3
	if player.spectator_follow_valid:
		player.spectator_follow_at = watching["at"]
	var note := "REJOINING SHORTLY" if RoomState.public_route else ""
	if _spectator_banner != null:
		_spectator_banner.show_for(
			RoomState.peer_display_name(int(watching.get("peer_id", 0))) \
			if not watching.is_empty() else "", note)
	# Party wipe: the host was already spectating and the last guest just fell.
	if RoomState.online and RoomState.is_host and not RoomState.public_route \
			and not _death_screen_open and not _capture_resolving \
			and _living_runners().is_empty():
		_end_spectating()
		_death_screen_open = true
		# Party wipe: the last catcher gets the final word, as a line on the card rather than another cutscene.
		var wipe_line := {}
		if not _last_death_cause.is_empty():
			wipe_line = _death_moment_for(String(_last_death_cause["hunter_id"]), _last_death_cause)
		run_report.open({
			"online": true, "host": true, "respawn": true,
			"title": "RUN OVER", "kicker": "ALL RUNNERS // LOST",
			"reason": "THE WHOLE PARTY WAS CAUGHT",
			"line": String(wipe_line.get("text", "")) if DeathMoment.plays(wipe_line) else "",
			"line_style": String(wipe_line.get("style", "")),
			"depth": -facility.current_level(), "score": GameState.score,
			"relays": GameState.relays_collected,
			"relay_target": GameState.relay_target, "coins": GameState.coins,
			"difficulty": RoomState.difficulty_id().to_upper(),
			"seed": RoomState.seed_text,
		})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == REGION_MAP_KEY \
			and _admin_menu != null and Build.admin_permission("visual"):
		_admin_toggle_region_map()
		get_viewport().set_input_as_handled()
		return
	if not player.spectator_mode or not (event is InputEventKey) \
			or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_E:
			_cycle_spectate_target(1)
		KEY_Q:
			_cycle_spectate_target(-1)
		KEY_F:
			_cycle_spectate_target(0)


## The party opened the dome gate: everyone escapes together. A short gate sequence, then the escape card.
func _city_escape(opener_peer_id: int) -> void:
	if _city_escaped:
		return
	_city_escaped = true
	Backend.account_clear_game_progress(RoomState.GAME_CITY)
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	hud.show_message("THE DOME GATE OPENS" if opener_peer_id != local_id else "YOU OPENED THE DOME GATE")
	Sound.escape()
	player.input_frozen = true
	await get_tree().create_timer(2.4).timeout
	_end_spectating()
	_death_screen_open = true
	GameState.game_over = true
	run_report.open({
		"online": RoomState.online, "host": RoomState.is_host,
		"respawn": false, "title": "ESCAPED",
		"kicker": "DOME GATE // OPEN",
		"reason": "THE GATE OPENS. THE CITY LETS YOU GO.",
		"depth": 1, "score": GameState.score,
		"relays": GameState.relays_collected,
		"relay_target": CityLayout.gate_relays_required(RoomState.difficulty_id()),
		"coins": GameState.coins,
		"difficulty": RoomState.difficulty_id().to_upper(),
		"seed": RoomState.seed_text,
	})


func _new_city_run() -> void:
	run_report.close()
	GameState.game_over = false
	_death_screen_open = false
	_city_escaped = false
	if RoomState.online:
		_leave_test()
		return
	RoomState.reroll_seed()
	RoomState.session_active = false
	RoomState.enter(get_tree())


func _adopt_city_save_before_stream(save: Dictionary) -> void:
	GameState.score = maxi(0, int(save.get("score", 0)))
	GameState.coins = maxi(0, int(save.get("coins", 0)))
	GameState.relays_collected = maxi(0, int(save.get("relays", 0)))
	GameState.relays_sabotaged = maxi(0, int(save.get("sabotaged", 0)))
	for id_value in save.get("claimed", []):
		world_state.claimed_pickups[String(id_value)] = true


## Writes the City run checkpoint to the signed-in account (solo or a host with no guests; never a debug run, never after
## the dome gate opened). Throttled so a burst of pickups is one write.
func _city_autosave(force: bool = false) -> void:
	if not RoomState.is_city() or _city_escaped or GameState.debug_run or not Backend.signed_in():
		return
	if RoomState.online and (not RoomState.is_host or RoomState.peers.size() > 1):
		return
	var now := Time.get_ticks_msec()
	if not force and now - _city_autosave_msec < 8000:
		return
	_city_autosave_msec = now
	Backend.account_save_game_progress(RoomState.GAME_CITY, CityRunSave.make(RoomState.seed_text,
		RoomState.difficulty_id(), GameState.score, GameState.coins, GameState.relays_collected,
		GameState.relays_sabotaged, world_state.claimed_pickups.keys(), player.global_position, player._yaw, RoomState.is_day()))


func _respawn_after_death() -> void:
	if _city_escaped:
		_new_city_run()
		return
	if not _death_screen_open:
		return
	_force_disable_admin_cheats()
	_clear_local_waypoint()   # a waypoint never survives death
	run_report.close()
	GameState.game_over = false
	_end_spectating()
	if RoomState.online and RoomState.is_host and _remotes != null:
		for target_value in _remotes.target_states({}):
			var peer := int((target_value as Dictionary).get("peer_id", 0))
			if peer != 0 and bool((target_value as Dictionary).get("spectating", false)):
				_remotes.send_player_event(peer, {"what": "revive"})
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


## Chunk teleports land on the chunk's centre cell, where the main halls cross (always open floor).
func _admin_teleport_chunk(id: String) -> void:
	var here := facility.current_chunk_coord()
	var target := here
	match id:
		"north": target = Vector3i(here.x, here.y, here.z - 1)
		"south": target = Vector3i(here.x, here.y, here.z + 1)
		"east": target = Vector3i(here.x + 1, here.y, here.z)
		"west": target = Vector3i(here.x - 1, here.y, here.z)
		"safe_room":
			var best := 99999.0
			for dz in range(-5, 6):
				for dx in range(-5, 6):
					var coord := Vector3i(here.x + dx, here.y, here.z + dz)
					if not facility.generator.is_chunk_allowed(coord):
						continue
					if bool(facility.generator.chunk(coord).get("safe_room", false)):
						var d := float(dx * dx + dz * dz)
						if d < best and d > 0.0:
							best = d
							target = coord
			if target == here:
				hud.show_message("ADMIN // NO SAFE ROOM WITHIN 5 CHUNKS")
				return
		"start":
			_admin_teleport_to(facility.spawn_position())
			return
		"checkpoint":
			_admin_teleport_to(_checkpoint_world_position())
			return
		"relay":
			var relay := _admin_nearest_relay_position()
			if relay == Vector3.INF:
				hud.show_message("ADMIN // NO LOADED RELAY")
				return
			_admin_teleport_to(relay)
			return
	if not facility.generator.is_chunk_allowed(target):
		hud.show_message("ADMIN // THAT CHUNK DOES NOT EXIST")
		return
	var cs := StreamedRouteGenerator.CHUNK_SIZE
	_admin_teleport_to(Vector3(target.x * cs + cs / 2 + .5, player.global_position.y,
		target.z * cs + cs / 2 + .5))


func _admin_nearest_relay_position() -> Vector3:
	var best := INF
	var found := Vector3.INF
	for node in get_tree().get_nodes_in_group("interactable"):
		var item := node as RouteInteractable3D
		if item == null or item.kind != RouteInteractable3D.Kind.RELAY or item.completed:
			continue
		var d := item.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			found = item.global_position + Vector3(0, 0, 1.2)
	return found


## Solo only: speeding up or pausing the simulation would desync everyone else in the room.
func _admin_game_speed(id: String) -> void:
	if RoomState.online and (RoomState.public_route or RoomState.peers.size() > 1):
		hud.show_message("ADMIN // OTHER PLAYERS ARE IN THIS ROOM")
		return
	if id == "step":
		Engine.time_scale = 1.0
		await get_tree().physics_frame
		Engine.time_scale = 0.0
		return
	Engine.time_scale = float(id)


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
		"freeze_hunters":
			for view_value in _hunter_views.values():
				var view := view_value as HunterView3D
				if view != null and view.brain != null:
					view.brain.apply_stun(1.0e6)
					view.sync_from_brain()
		"release_hunters":
			for view_value in _hunter_views.values():
				var view := view_value as HunterView3D
				if view != null and view.brain != null:
					view.brain.stun_timer = 0.0
					view.sync_from_brain()
		"calm_hunters":
			for view_value in _hunter_views.values():
				var view := view_value as HunterView3D
				if view != null and view.brain != null:
					view.brain.calm_reset(2.0)
					view.sync_from_brain()
		"hunter_emote":
			_admin_hunter_emote_authoritative(peer_id, String(event.get("emote", "")))
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
			"freeze_hunters", "release_hunters",
			"summon_hunter", "remove_hunter", "hunter_emote"]:
		return "hunters"
	return ""


func _admin_hunter_id_allowed(hunter_id: String) -> bool:
	return HunterRoster.A_Z_IDS.has(hunter_id) \
		or HunterRoster.VOID_IDS.has(hunter_id) or SecretCreatures.has(hunter_id)


func _admin_feedback(peer_id: int, message: String) -> void:
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	if peer_id == local_id:
		hud.show_message(message)
	else:
		_remotes.send_player_event(peer_id, {"what": "message", "message": message})


## Test row: every active hunter within 40 m of the requesting runner plays the emote now (ignores rules and cooldowns).
func _hunter_emote_ids() -> Array:
	var ids := []
	for entry in HunterEmoteCatalog.ENTRIES:
		ids.append(String(entry["id"]))
	return ids


func _hunter_emote_labels() -> Dictionary:
	var labels := {}
	for entry in HunterEmoteCatalog.ENTRIES:
		labels[String(entry["id"])] = String(entry["label"])
	return labels


func _admin_hunter_emote_authoritative(peer_id: int, emote_id: String) -> void:
	var index := HunterEmoteCatalog.index_of(emote_id)
	var target := _target_state_for_peer(peer_id)
	var at = target.get("position")
	if index == HunterEmoteCatalog.NONE or not at is Vector2:
		_admin_feedback(peer_id, "ADMIN HUNTER EMOTE FAILED")
		return
	var played := 0
	for view_value in _hunter_views.values():
		var view := view_value as HunterView3D
		if view == null or view.brain == null or not view.brain.active \
				or view.brain.position.distance_to(at) > 40.0:
			continue
		view.brain.start_emote(index, HunterEmoteCatalog.seconds(index))
		view.sync_from_brain()
		played += 1
	_admin_feedback(peer_id, "HUNTER EMOTE // %s // %d HUNTERS" % [HunterEmoteCatalog.label(index).to_upper(), played])


func _admin_summon_hunter_authoritative(peer_id: int, hunter_id: String) -> void:
	if not _admin_hunter_id_allowed(hunter_id):
		return
	if SecretCreatures.is_pair(hunter_id):            # admin picker "pair" entry: both, linked, with the route difficulty's knobs
		for member in SecretCreatures.pair_members():
			_admin_summon_hunter_authoritative(peer_id, member)
		CitySecrets.link_admin_pair(self, RoomState.difficulty_id())
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
	if SecretCreatures.is_pair(hunter_id):
		for member in SecretCreatures.pair_members():
			_admin_remove_hunter_authoritative(peer_id, member)
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
	_city_autosave(true)
	_force_disable_admin_cheats()
	get_tree().paused = false
	if RoomState.public_route:
		PublicRoute.leave()
		RoomState.leave_network()
		get_tree().change_scene_to_file(RoomState.menu_scene_path())
		return
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
	elif RoomState.is_city():
		# A solo City run has no staging worth visiting: straight back to the City menu.
		RoomState.session_active = false
		RoomState.status_message = ""
		get_tree().change_scene_to_file(RoomState.menu_scene_path())
	else:
		RoomState.session_active = false
		RoomState.status_message = "ROUTE SUSPENDED // BACK IN STAGING"
		get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")
