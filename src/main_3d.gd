extends Node

const HUNTER_JUMPSCARE_SCENE := preload("res://scenes/hunter_jumpscare.tscn")

## 3D counterpart to src/main.gd — same GameState-driven floor lifecycle and
## HUD wiring, orchestrating the 3D presentation layer instead of the 2D one.
## Also owns the hunter lifecycle: spawn/activation/per-frame brain update
## and the capture -> escape struggle -> success/jumpscare/game-over flow
## (hunter_brain.gd is pure simulation; this is where its results turn into
## game state, matching how game.js's update() drives hunter-ai.js).

var pause_menu: PauseMenu
var admin_menu: AdminMenu

@onready var world: Node3D = %World
@onready var facility_view: FacilityView3D = %FacilityView
@onready var player: PlayerController3D = %Player
@onready var hud: HUD = %HUD
@onready var route_loading = %RouteLoadingOverlay
@onready var run_report = %RunReport

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
var jumpscare: HunterJumpscare
var _death_moment: DeathMoment
## How the local runner is dying, for the death line pick: contact (default), deal (Zellia), cold (Wynelle).
var _death_via := "contact"
var pixel_signal_effect: PixelSignalEffect
var _capture_resolving := false
## Admin-only: shows every hunter on both maps, active or not -- see
## _map_marks()'s own note on why that distinction exists at all.
var _admin_reveal_hunters := false
var _remotes: RemotePlayers
var _room_chat: RoomChat
var _custom_map_request: HTTPRequest
## True while a fetch is in flight, so a second admin submission cannot start
## one on top of it. Tracked here rather than read off HTTPRequest itself --
## simpler than trusting an internal client-status API to mean what it sounds
## like it means.
var _custom_map_fetching := false
## A custom floor cannot be regenerated from RoomState's procedural seed. The
## host retains a compact canonical PNG so a late joiner's first snapshot can
## rebuild the exact authored grid before applying collected/disabled state.
const CUSTOM_MAP_MAX_BYTES := 2 * 1024 * 1024
const SNAPSHOT_PROTOCOL := 2
var _custom_map_png := PackedByteArray()
var _custom_map_seed := ""
## Changes whenever the host replaces the base floor, even if depth/seed stay
## the same (for example REBUILD FLOOR). Guests compare the host revision from
## snapshots so cleared pickups cannot remain completed on an old local base.
var _floor_revision := 0
var _applied_host_floor_revision := -1
## Guests enter the live scene before their world snapshot can arrive. Keep
## their controller locked until that snapshot has been validated and applied.
var _awaiting_initial_snapshot := false
## Rebuilt each frame on the host and sent as-is; empty on a client, which
## never fills it because it never runs a brain.
var _hunter_report: Array = []
## Local-only audio state. Hunter simulation remains host-authoritative, but
## each peer hears danger relative to its own body and camera orientation.
var _audio_hunter_active := {}
var _was_locally_pursued := false
## Host-side rate gate for taser requests. Guests animate immediately, but a
## modified client cannot make the authoritative hunter accept rapid shots.
var _taser_ready_usec_by_peer := {}
var _hunter_step_elapsed := 0.0
const TEMPERATURE_HUNTER_EFFECT_RADIUS := 14.0
const REMOTE_METER_EFFECT_INTERVAL := 0.1
var _remote_meter_effects := {}
var _remote_meter_effect_elapsed := 0.0
## Backend verification request id -> sanitized guest intent. Release guest
## admin commands wait here until the primary service confirms the opaque,
## room-bound proof; no account token ever reaches this player host.
var _pending_admin_requests := {}
var _admin_ticket_refresh_elapsed := 0.0
const HUNTER_DISCOVERY_RANGE := 7.5


func _ready() -> void:
	RefLook.install(self, get_node_or_null("WorldEnvironment") as WorldEnvironment)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("gameplay_session")
	UpdateManager.update_ready.connect(_on_background_update_ready)
	_awaiting_initial_snapshot = RoomState.online and not RoomState.is_host
	# The room's seed, not a fresh random one. Every shared thing below is
	# addressed by grid cell, which only names the same object on two machines
	# if both machines generated the same facility -- so this line is what makes
	# the rest of the sync mean anything. Offline it is still a stable seed, so
	# a solo run behaves the same way.
	var restored_checkpoint := not RoomState.online \
		and GameState.restore_queued_route_checkpoint()
	if not restored_checkpoint:
		GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	observed_depth = GameState.depth
	player.interaction_message.connect(_on_interaction_message)
	player.taser_requested.connect(_on_taser_requested)
	player.interaction_veto = _guardian_blocking
	player.hiding_trap_resolver = _ceryth_trap_check
	player.music_box_resolver = _wind_music_box
	player.vent_resolver = _use_vent
	player.shop_resolver = _use_shop
	player.shop_prompt_provider = _shop_prompt
	hud.inventory_reorder_requested.connect(player.move_inventory_slot)
	hud.inventory_open_changed.connect(_on_inventory_open_changed)
	hud.map_open_changed.connect(_on_map_open_changed)
	_void_fx = VoidPlayerEffects.new(player, hud, _report_void_route)
	# Last Route taps ESC: it is a co-op mode, so pausing has to be quick.
	pause_menu = PauseMenu.new()
	pause_menu.abandon_label = "ABANDON ROUTE"
	pause_menu.pauses_tree = not RoomState.online
	pause_menu.dismiss_overlay = _dismiss_gameplay_overlay
	if RoomState.online and not RoomState.is_host:
		pause_menu.abandon_warning = "This leaves the room and returns you to staging. The host's route continues."
	pause_menu.opened.connect(_on_pause_opened)
	pause_menu.resumed.connect(_on_pause_resumed)
	pause_menu.abandoned.connect(_on_abandoned)
	add_child(pause_menu)
	run_report.restart_requested.connect(_restart_solo_route)
	run_report.leave_requested.connect(_leave_after_report)
	jumpscare = HUNTER_JUMPSCARE_SCENE.instantiate()
	world.add_child(jumpscare)
	_death_moment = DeathMoment.new()
	add_child(_death_moment)
	pixel_signal_effect = PixelSignalEffect.new()
	pixel_signal_effect.name = "PixelSignalEffect"
	add_child(pixel_signal_effect)
	# Other players' bodies. Present offline too, doing nothing, so there is no
	# second code path for a solo run.
	_remotes = RemotePlayers.new()
	_remotes.name = "RemotePlayers"
	_remotes.local_player = player
	_remotes.hunters_received.connect(_apply_hunters)
	_remotes.world_event.connect(_apply_world_event)
	_remotes.world_event_requested.connect(_apply_world_request)
	_remotes.world_snapshot.connect(_apply_world_snapshot)
	_remotes.player_event.connect(_apply_player_event)
	_remotes.hunter_event.connect(_apply_hunter_event)
	_remotes.interaction_requested.connect(_apply_interaction_request)
	_remotes.snapshot_source = _build_snapshot
	world.add_child(_remotes)
	_room_chat = RoomChat.attach(self, _remotes)
	_room_chat.ping_posted.connect(hud.add_map_ping)
	_room_chat.open_changed.connect(_on_chat_open_changed)
	if not Backend.admin_ticket_verified.is_connected(_on_admin_ticket_verified):
		Backend.admin_ticket_verified.connect(_on_admin_ticket_verified)
	if not Backend.admin_ticket_changed.is_connected(_on_admin_ticket_changed):
		Backend.admin_ticket_changed.connect(_on_admin_ticket_changed)
	if RoomState.online and not RoomState.is_host \
			and not Backend.admin_ticket_for_room(RoomState.code).is_empty():
		_remotes.request_interaction({"what": "admin_auth"})
	facility_view.world_changed.connect(_on_world_changed)
	_build_admin()
	_build_floor()
	_checkpoint_solo_route()
	if _awaiting_initial_snapshot or (admin_menu != null and admin_menu.is_open()):
		player.input_frozen = true
		hud.show_message("SYNCING CURRENT FLOOR...")
		route_loading.show_waiting_for_snapshot()
	else:
		route_loading.dismiss()
	_update_hud()


func _on_background_update_ready(_path: String) -> void:
	hud.show_message("UPDATE READY // WILL APPLY AFTER THIS RUN")


func _process(delta: float) -> void:
	if _void_fx != null:
		_void_fx.tick(delta)
	if RoomState.online and not RoomState.is_host and Backend.admin_authorized():
		_admin_ticket_refresh_elapsed += delta
		if _admin_ticket_refresh_elapsed >= 5.0:
			_admin_ticket_refresh_elapsed = 0.0
			if Backend.admin_ticket_for_room(RoomState.code).is_empty():
				Backend.request_admin_ticket(RoomState.code)
	# Menu/stun callbacks may also write input_frozen. Snapshot readiness wins
	# over all of them: a guest must never walk around the temporary floor.
	if _awaiting_initial_snapshot:
		player.input_frozen = true
	if GameState.game_over:
		player.input_frozen = true
		# A solo scene can stop here. In co-op the host must keep simulating
		# hunters and remote runners while her own run-report is open.
		if not RoomState.online:
			return

	# Being held by a hunter is the one moment pausing would be an exploit, so
	# the menu is locked out for the length of the struggle.
	pause_menu.tap_to_pause = not GameState.escape_active
	if Input.is_action_just_pressed("inventory") and not GameState.escape_active \
			and not GameState.game_over and not pause_menu.is_open() \
			and (admin_menu == null or not admin_menu.is_open()):
		hud.toggle_inventory()
	if Input.is_action_just_pressed("toggle_map") and not GameState.escape_active \
			and (admin_menu == null or not admin_menu.is_open()):
		hud.set_inventory_open(false)
		hud.toggle_map_overlay()

	if get_tree().paused:
		return

	GameState.tick_escape_cooldowns(delta)

	if GameState.escape_active:
		_update_escape_struggle(delta)
		# The host's own struggle is local state; the other runners and the
		# authoritative hunters keep moving while it is on screen.
		if RoomState.online and _remotes != null and _remotes.simulates():
			_update_gameplay(delta)
	else:
		_update_gameplay(delta)
	_flush_remote_meter_effects(delta)

	if _remotes != null:
		if _remotes.simulates():
			_collect_hunter_report()
		_remotes.broadcast_hunters(_hunter_report)
	if GameState.depth != observed_depth:
		observed_depth = GameState.depth
		_build_floor()
		_checkpoint_solo_route()

	var remote_map_players := _remotes.remote_player_marks(GameState.depth) \
		if _remotes != null else []
	hud.update_minimap(facility_view.generator, player.grid_position(),
		player.facing, _map_marks(true) if _admin_reveal_hunters else _radar_marks(),
		remote_map_players)
	if hud.map_is_open():
		hud.update_map(facility_view.generator, player.grid_position(),
			player.facing, _map_marks(_admin_reveal_hunters), remote_map_players)
	hud.set_interaction_prompt(player.get_interaction_prompt())
	_discover_visible_hunters()
	_update_local_audio(delta)
	_update_hud()


## Dossier facts unlock from an actual local encounter, not from a room roll or
## host snapshot. Ordinary hunters require nearby line of sight. Porcelle also
## exposes herself through the full map, while Umbriel reveals the face she is
## wearing rather than silently exposing her real identity.
func _discover_visible_hunters() -> void:
	if not Backend.signed_in() or _awaiting_initial_snapshot:
		return
	var local_position := player.grid_position()
	for view in hunter_views:
		if view.brain == null or not view.brain.active:
			continue
		var hunter_id := view.brain.hunter_id
		if hunter_id == "porcelle" and hud.map_is_open():
			Backend.account_discover_hunter(hunter_id)
		if local_position.distance_to(view.brain.position) > HUNTER_DISCOVERY_RANGE \
				or not facility_view.generator.has_line_of_sight(
					local_position, view.brain.position):
			continue
		if view.brain.gimmick is UmbrielGimmick \
				and not view.brain.gimmick.disguise_id.is_empty():
			hunter_id = view.brain.gimmick.disguise_id
		Backend.account_discover_hunter(hunter_id)


func _update_gameplay(delta: float) -> void:
	var generator := facility_view.generator
	var local_target := _local_hunter_target()

	# Only the host thinks for the hunters. A client that ran the same brains
	# would run them against ITS player, so each window would be chased by a
	# hunter the others cannot see.
	if _remotes == null or not _remotes.simulates():
		return

	# Only the drawn route hunter follows the relay schedule; the specials
	# below wake on their own rules instead.
	if hunter_view and not hunter_view.brain.active:
		var activation_relay: int = mini(GameConfig.hunter_activation_relay_count(
			RoomState.difficulty_id()), generator.relay_count)
		if GameState.relays_collected >= activation_relay:
			var activation_target := _remotes.best_target(
				hunter_view.brain.position, local_target, GameState.depth)
			if not activation_target.is_empty():
				hunter_view.brain.activate_at(activation_target["position"])
				# A seeded Void incursion is extra pressure in the same active
				# lineup, not an inert model. Wake it with the route hunter while
				# leaving rule-summoned A-Z specials on their own conditions.
				for view in hunter_views:
					if not view.brain.active and String(HunterRoster.get_identity(
							view.brain.hunter_id).get("category", "az")) == "void":
						view.brain.activate_at(activation_target["position"])

	# Ferryn's scream, collected during the loop below and applied to every
	# OTHER hunter only after every hunter has had her own update() this
	# frame -- applying it inline would let whoever raised it stomp a
	# not-yet-updated sibling, then have that sibling's own update() overwrite
	# it right back a moment later.
	var facility_alerts: Array = []
	_direct_hunters(delta, local_target, generator)
	for view in hunter_views:
		var selected := _remotes.best_target(view.brain.position,
			local_target, GameState.depth)
		if selected.is_empty():
			view.target_peer_id = 0
			view.set_look_target(null)
			view.brain.update_without_target(delta, generator, GameState.depth,
				GameState.relays_collected)
			view.sync_from_brain()
			continue
		var target := _target_with_runtime(selected)
		view.target_peer_id = int(target.get("peer_id", 0))
		var captured: bool = view.brain.update(delta, generator, target,
			GameState.depth, GameState.relays_collected)
		view.set_look_target(view.brain.presentation_look_target())
		_collect_remote_meter_effects(target)
		view.sync_from_brain()
		# Anything a gimmick did to the floor. Only the host reaches here, which
		# is what makes it safe to broadcast without a second authority check.
		for event in view.brain.world_events:
			var what := String(event.get("what", ""))
			if what == "facility_alert":
				Sound.alert()
				_remotes.broadcast_event({"what": "sound_alert"})
				facility_alerts.append(event)
				continue
			if what == "stun":
				_dispatch_player_event(target, {
					"what": "stun",
					"seconds": float(event.get("seconds", 0.0)),
					"message": String(event.get("message", "")),
				})
				continue
			if what in ["signal_route", "system_outage", "radar_corrupt"]:
				_dispatch_player_event(target, event)
				continue
			facility_view.apply_event(event)
			_play_world_audio(event)
			_remotes.broadcast_event(event)
			var note := String(event.get("message", ""))
			if not note.is_empty():
				hud.show_message(note)
		view.brain.world_events.clear()
		# Javelle reaching into a locker. Resolved here rather than in the gimmick
		# because it moves the PLAYER, which the brain has no handle on.
		if view.brain.gimmick is JavelleGimmick and view.brain.gimmick.ejecting:
			_dispatch_player_event(target, {
				"what": "eject",
				"at": view.brain.gimmick.ejected_to,
				"message": "JAVELLE PULLED YOU OUT OF HIDING",
			})
		if view.brain.gimmick is LoxelleGimmick:
			for toggle in view.brain.gimmick.toggles:
				var cell: Vector2i = toggle["cell"]
				if toggle.has("eject_to"):
					_dispatch_player_event(target, {
						"what": "eject",
						"cell": cell,
						"at": toggle["eject_to"],
						"message": "LOXELLE BROKE YOUR COVER",
					})
					_dispatch_player_event(target, {"what": "meter_effect",
						"temperature_add": float(toggle.get("temperature_add", 0.0)),
						"noise_add": float(toggle.get("noise_add", 0.0))})
				else:
					var spot := facility_view.hiding_spot_at(cell)
					if spot:
						spot.set_disabled(bool(toggle["disabled"]))
					if bool(toggle["disabled"]):
						Sound.alert()
					_remotes.broadcast_event({"what": "hiding_disabled",
						"cell": cell, "disabled": bool(toggle["disabled"])})
			view.brain.gimmick.toggles.clear()
		# Wynelle's freeze grace is a second way to lose that isn't a grab:
		# if it runs out you die where you stand, with no struggle.
		if view.brain.gimmick is WynelleGimmick and view.brain.gimmick.has_frozen_player():
			if int(target.get("peer_id", 1)) == (multiplayer.get_unique_id() if RoomState.online else 1):
				_death_via = "cold"
			_capture_target(view, target, true)
			view.brain.gimmick.consume_frozen_player(view.brain)
			view.sync_from_brain()
			return
		if captured:
			_capture_target(view, target)
			return

	for alert in facility_alerts:
		var at: Vector2 = alert["at"]
		var except_id := String(alert.get("except", ""))
		for view in hunter_views:
			if not view.brain.active or view.brain.hunter_id == except_id:
				continue
			view.brain.state = HunterBrain.State.INVESTIGATE
			view.brain.has_last_known = true
			view.brain.last_known = at
			view.sync_from_brain()
		var note := String(alert.get("message", ""))
		if not note.is_empty():
			hud.show_message(note)


func _local_hunter_target() -> Dictionary:
	return {
		"peer_id": multiplayer.get_unique_id() if RoomState.online else 1,
		"position": player.grid_position(),
		"hidden": player.hidden,
		"hiding_spot": player.hidden_spot,
		"in_safe_zone": player.is_in_safe_zone(),
		"noise": player.noise,
		"flashlight_on": player.flashlight_enabled,
		# Actually moving under sprint, not merely holding the key — the
		# original gates on `sprinting && travelSpeed > .1` (Elise).
		"sprinting": player.movement_mode == "sprint" and player.noise > 0.0,
		# For beam-aim checks (Nyxie's dispel).
		"facing": player.facing,
		"lamp_charge": player.lamp_charge,
		"meters": player.meters,
		# Wynelle reads the heater station's two distinct states: merely
		# thawed dematerialises her, powered holds her off entirely.
		"heater_unfrozen": _heater_state() != RouteInteractable3D.HeaterState.FROZEN,
		"heater_powered": _heater_state() == RouteInteractable3D.HeaterState.POWERED,
		# Verrine only chases while the player is actually inside the vent
		# network she lurks in -- see VerrineGimmick.after_perception.
		"in_vent": player.in_vent,
		"vent_time_in": player.vent_time_in,
		# Zellia's pesticide trade -- Loxelle/Ysolde read this to skip their
		# own passive ability for its duration.
		"pesticide_active": player.pesticide_timer > 0.0,
		"map_open": hud.map_is_open(),
		"no_target": player.admin_no_target,
		"god_mode": player.admin_god_mode,
		"escape_active": GameState.escape_active,
		"capture_immune": GameState.is_capture_immune(),
		"game_over": GameState.game_over,
	}


## RPC dictionaries cannot contain RefCounted objects. Remote meter values are
## reconstructed into the same shape hunter gimmicks expect; a baseline lets
## us turn host-side mutations of that copy into targeted owner events.
var _hunter_director: HunterDirector


## Hunters work together on every mode (HunterDirector): share sightings, split into small teams, spread out, cap per runner.
func _direct_hunters(delta: float, local_target: Dictionary, generator) -> void:
	if _hunter_director == null or _hunter_director.mode_id != RoomState.difficulty_id():
		_hunter_director = HunterDirector.new(RoomState.difficulty_id(), "%s-director" % str(RoomState.seed_text if "seed_text" in RoomState else "ROUTE"))
	var entries: Array = []
	for view in hunter_views:
		var selected := _remotes.best_target(view.brain.position, local_target, GameState.depth)
		entries.append({"id": str(view.get_instance_id()), "brain": view.brain, "target": selected})
	_hunter_director.tick(delta, entries, generator)


func _target_with_runtime(source: Dictionary) -> Dictionary:
	var target := source.duplicate(true)
	if not target.has("meters"):
		var meters := PlayerMeters.new()
		meters.exposure = float(target.get("exposure", 0.0))
		meters.noise_meter = float(target.get("noise_meter", 0.0))
		meters.temperature = float(target.get("temperature", GameConfig.TEMPERATURE_START))
		meters.ambient = float(target.get("ambient", GameConfig.TEMPERATURE_START))
		meters.heat_locked = bool(target.get("heat_locked", false))
		meters.overheating = meters.temperature >= GameConfig.TEMPERATURE_OVERHEAT
		meters.freezing = meters.temperature <= GameConfig.TEMPERATURE_FREEZE
		target["meters"] = meters
		target["_meter_baseline"] = {
			"exposure": meters.exposure,
			"noise_meter": meters.noise_meter,
			"temperature": meters.temperature,
			"heat_locked": meters.heat_locked,
		}
	target["heater_unfrozen"] = _heater_state() != RouteInteractable3D.HeaterState.FROZEN
	target["heater_powered"] = _heater_state() == RouteInteractable3D.HeaterState.POWERED
	return target


## Collect changes a host-owned gimmick made to a remote runner's temporary
## meter copy. Effects are accumulated and sent at 10 Hz so Glyra's continuous
## noise does not become sixty reliable RPCs per second.
func _collect_remote_meter_effects(target: Dictionary) -> void:
	if not RoomState.online or not RoomState.is_host or not target.has("_meter_baseline"):
		return
	var peer_id := int(target.get("peer_id", -1))
	if peer_id <= 1:
		return
	var meters := target.get("meters") as PlayerMeters
	if meters == null:
		return
	var baseline: Dictionary = target["_meter_baseline"]
	var exposure_add := meters.exposure - float(baseline.get("exposure", meters.exposure))
	var noise_add := meters.pending_noise_input()
	var noise_reclaim := maxf(0.0,
		float(baseline.get("noise_meter", meters.noise_meter)) - meters.noise_meter)
	var temperature_add := meters.temperature - float(
		baseline.get("temperature", meters.temperature))
	var heat_lock := meters.heat_locked and not bool(baseline.get("heat_locked", false))
	if is_zero_approx(exposure_add) and is_zero_approx(noise_add) \
			and is_zero_approx(noise_reclaim) and is_zero_approx(temperature_add) \
			and not heat_lock:
		return
	var effect: Dictionary = _remote_meter_effects.get(peer_id, {
		"exposure_add": 0.0,
		"noise_add": 0.0,
		"noise_reclaim": 0.0,
		"temperature_add": 0.0,
		"heat_lock": false,
	})
	effect["exposure_add"] += exposure_add
	effect["noise_add"] += noise_add
	effect["noise_reclaim"] += noise_reclaim
	effect["temperature_add"] += temperature_add
	effect["heat_lock"] = bool(effect["heat_lock"]) or heat_lock
	_remote_meter_effects[peer_id] = effect


func _flush_remote_meter_effects(delta: float, force: bool = false) -> void:
	if _remote_meter_effects.is_empty():
		_remote_meter_effect_elapsed = 0.0
		return
	_remote_meter_effect_elapsed += delta
	if not force and _remote_meter_effect_elapsed < REMOTE_METER_EFFECT_INTERVAL:
		return
	_remote_meter_effect_elapsed = 0.0
	for peer_id in _remote_meter_effects:
		var effect: Dictionary = _remote_meter_effects[peer_id]
		effect["what"] = "meter_effect"
		_remotes.send_player_event(int(peer_id), effect)
	_remote_meter_effects.clear()


func _collect_hunter_report() -> void:
	_hunter_report.clear()
	for view in hunter_views:
		var disguise := ""
		var wake := 0
		if view.brain.gimmick is UmbrielGimmick:
			disguise = view.brain.gimmick.disguise_id
		if view.brain.gimmick is NyxieGimmick:
			wake = int(view.brain.gimmick.wake_mode)
		_hunter_report.append({
			"id": view.brain.hunter_id,
			"position": view.brain.position,
			"facing": view.brain.facing,
			"active": view.brain.active,
			"state": int(view.brain.state),
			"stun": view.brain.stun_timer,
			"target_peer_id": view.target_peer_id,
			"look_target": view.look_target_position if view.has_look_target else null,
			"disguise": disguise,
			"wake": wake,
			"gimmick": view.brain.gimmick.network_state()
				if view.brain.gimmick != null else {},
			"hard": view.brain.hard.network_state() if view.brain.hard != null else {},
		})


## Mirrors hunter-ai.js's guardianBlocking(), called from the same place its
## performInteraction() calls it: a guardian denies EVERYTHING inside her
## radius, not only the relay she came for -- the lift, a battery, a safe zone.
## Touching what she guards pings the player's position to every active hunter,
## which is the cost of testing her.
func _guardian_blocking(target: RouteInteractable3D) -> String:
	var at := Vector2(target.source_cell) + Vector2(0.5, 0.5)
	for view in hunter_views:
		var gimmick := view.brain.gimmick
		if not view.brain.active or gimmick == null or not gimmick.has_method("blocks"):
			continue
		if not gimmick.call("blocks", at):
			continue
		var name := String(HunterRoster.get_identity(view.brain.hunter_id)["display_name"])
		if RoomState.online and not RoomState.is_host:
			_remotes.request_interaction({"what": "guardian_ping",
				"cell": target.source_cell})
		for ally in hunter_views:
			if not ally.brain.active:
				continue
			ally.brain.enter_search_from(player.grid_position(), 1.8)
			ally.sync_from_brain()
		return "%s IS GUARDING THIS // DRAW HER OFF" % name.to_upper()
	return ""


## What the map shows. Every ACTIVE hunter, including the ones the room cannot
## see. Porcelle's extra full-map marker remains part of her counterplay even
## though she is now visible in the room as well.
##
## `include_inactive`: the admin menu's "REVEAL HUNTERS" toggle -- a hunter
## still waiting on the relay schedule (or a special still waiting on her own
## wake condition) is otherwise invisible to this too, which is right for a
## normal run and useless for debugging one.
func _map_marks(include_inactive: bool = false) -> Array:
	var marks: Array = []
	for view in hunter_views:
		# Rule-summoned specials exist as inert brains at the route hunter's
		# initial spawn until their own mechanic actually summons them. Showing
		# those placeholders under admin reveal left a second, motionless radar
		# dot behind after the real route hunter started moving. Reveal may show
		# the inactive route hunter for debugging; specials only exist on radar
		# after they are genuinely active.
		if not view.brain.active and (not include_inactive or view != hunter_view):
			continue
		# "active" here means "draw this mark" -- inclusion was already
		# decided above, so every entry that made it into this array wants
		# to be shown, whether or not the hunter herself is active yet.
		marks.append({
			"at": view.brain.position,
			"name": String(HunterRoster.get_identity(view.brain.hunter_id)["display_name"]),
			"hunter_id": view.brain.hunter_id,
			"ghost": view.brain.hunter_id == "porcelle",
			"active": true,
		})
	return marks


## The only hunter the minimap may show without admin reveal: Porcelle, while she is active (her radar ping).
func _radar_marks() -> Array:
	return _map_marks(false).filter(func(mark: Dictionary) -> bool: return String(mark.get("hunter_id", "")) == "porcelle")


## Ceryth's riddle, asked at the moment the player tries to hide in the spot
## she has staked out. Not a veto -- unlike Opalie's, a wrong answer does not
## refuse the interaction, it changes what happens inside it.
func _ceryth_trap_check(cell: Vector2i, flashlight_active: bool) -> Dictionary:
	for view in hunter_views:
		if view.brain.gimmick is CerythGimmick:
			var result: Dictionary = view.brain.gimmick.resolve_entry(cell, flashlight_active)
			if RoomState.online and not RoomState.is_host and bool(result.get("cleared", false)):
				_remotes.request_interaction({"what": "ceryth_answer", "cell": cell})
			return result
	return {}


## Winding Glyra's music box. She is always on the floor once implemented
## (no wake condition, no activation schedule -- see her gimmick), but a
## hunter roll could still draw someone else as the route hunter while she
## sits inert as a special-like fixture; if there is no Glyra on this floor
## at all, there is nothing to wind.
func _wind_music_box() -> String:
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction({"what": "music_box",
			"cell": facility_view.music_box.source_cell if facility_view.music_box else Vector2i(-1, -1)})
		return "MUSIC BOX // SIGNAL SENT"
	for view in hunter_views:
		if view.brain.gimmick is GlyraGimmick:
			view.brain.gimmick.wind(player.meters)
			return "Music box wound. The room settles."
	return "The box is still. Nothing winds it."


## Verrine's vent network. Like _wind_music_box, resolved here because it
## moves the PLAYER (entry/transit/exit) and reaches into a gimmick's own
## network state, neither of which a plain interactable has any business
## knowing about.
func _use_vent(vent_id: String) -> String:
	for view in hunter_views:
		if view.brain.gimmick is VerrineGimmick:
			var was_inside := player.in_vent
			var message: String = String(view.brain.gimmick.use_vent(
				vent_id, view.brain, player, facility_view.generator))
			if RoomState.online and not RoomState.is_host:
				_remotes.request_interaction({"what": "vent_used", "vent_id": vent_id,
					"entered": not was_inside and player.in_vent})
			return message
	return "The grate won't budge."


## Zellia's shop. `action` is "open" ([E] near her) or "1".."4" (a digit
## key while her menu is open) -- see PlayerController3D.shop_resolver.
func _use_shop(action: String) -> String:
	for view in hunter_views:
		if not view.brain.gimmick is ZelliaGimmick:
			continue
		var gimmick: ZelliaGimmick = view.brain.gimmick
		if action == "open":
			return gimmick.open_shop(player.grid_position(), view.brain.position, player.facing)
		if not gimmick.shop_open:
			return ""
		gimmick.shop_open = false
		var offer_index := int(action)
		if RoomState.online and not RoomState.is_host:
			_remotes.request_interaction({"what": "zellia_trade", "offer": offer_index})
			return "ZELLIA'S STORE // VERIFYING TRADE..."
		return _perform_zellia_trade(
			multiplayer.get_unique_id() if RoomState.online else 1,
			offer_index, _local_hunter_target(), gimmick)
	return ""


## What the interaction prompt shows near Zellia -- checked after the
## ordinary nearest-interactable prompt, since she is not one.
func _shop_prompt() -> String:
	for view in hunter_views:
		if not view.brain.active or not view.brain.gimmick is ZelliaGimmick:
			continue
		var gimmick: ZelliaGimmick = view.brain.gimmick
		if gimmick.shop_open:
			return gimmick.offer_menu_text()
		if gimmick.in_range(player.grid_position(), view.brain.position, player.facing):
			return "OPEN ZELLIA'S STORE"
	return ""


## Resolve guest-owned input against host-owned hunter state. Movement itself
## remains owner-authoritative; every lasting hunter/economy consequence is
## validated and committed here by the host.
func _apply_interaction_request(peer_id: int, event: Dictionary) -> void:
	if not _remotes.simulates():
		return
	var what := String(event.get("what", ""))
	# A debug-tools build treats access to its admin overlay as the admin role.
	# Shared commands are still executed by peer 1, so a guest never mutates a
	# private copy and assumes the host saw it.
	if what in ["admin_auth", "admin_custom_map", "admin_world"]:
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
	var source := _remotes.state_for_peer(peer_id, _local_hunter_target(), GameState.depth)
	if source.is_empty():
		return
	match what:
		"music_box":
			if facility_view.music_box == null \
					or not _target_can_interact(source, facility_view.music_box.source_cell):
				return
			for view in hunter_views:
				if not view.brain.gimmick is GlyraGimmick:
					continue
				var target := _target_with_runtime(source)
				view.brain.gimmick.wind(target.get("meters"))
				_collect_remote_meter_effects(target)
				_flush_remote_meter_effects(0.0, true)
				_remotes.send_player_event(peer_id, {"what": "message",
					"message": "Music box wound. The room settles."})
				return
		"ceryth_answer":
			var cell = event.get("cell")
			if not cell is Vector2i or not _target_can_interact(source, cell):
				return
			for view in hunter_views:
				if not view.brain.gimmick is CerythGimmick:
					continue
				var lit := bool(source.get("flashlight_on", false)) \
					and float(source.get("lamp_charge", 0.0)) > 0.0
				var result: Dictionary = view.brain.gimmick.resolve_entry(cell, lit)
				if not result.is_empty():
					_remotes.send_player_event(peer_id, {"what": "message",
						"message": String(result.get("message", ""))})
				return
		"guardian_ping":
			var cell = event.get("cell")
			if not cell is Vector2i or not _target_can_interact(source, cell):
				return
			var at := Vector2(cell) + Vector2(0.5, 0.5)
			for view in hunter_views:
				if not view.brain.active or not view.brain.gimmick is OpalieGimmick \
						or not view.brain.gimmick.blocks(at):
					continue
				for ally in hunter_views:
					if ally.brain.active:
						ally.brain.enter_search_from(source["position"], 1.8)
				return
		"vent_used":
			if not bool(event.get("entered", false)):
				return
			var vent_id := String(event.get("vent_id", ""))
			for view in hunter_views:
				if view.brain.gimmick is VerrineGimmick:
					view.brain.gimmick.remote_vent_entered(
						vent_id, view.brain, facility_view.generator)
					view.sync_from_brain()
					return
		"signal_route_result":
			VoidPlayerEffects.host_route_result(hunter_views, peer_id, bool(event.get("ok", false)))
		"zellia_trade":
			for view in hunter_views:
				if view.brain.active and view.brain.gimmick is ZelliaGimmick:
					_perform_zellia_trade(peer_id, int(event.get("offer", 0)),
						source, view.brain.gimmick, view.brain.position)
					return


func _target_can_interact(target: Dictionary, cell: Vector2i) -> bool:
	var position: Vector2 = target.get("position", Vector2(-9999, -9999))
	var offset := Vector2(cell) + Vector2(0.5, 0.5) - position
	if offset.length() > GameConfig.INTERACTION_RANGE / GameConfig.TILE_SIZE:
		return false
	if offset.length() <= 0.001:
		return true
	var facing: Vector2 = target.get("facing", Vector2.ZERO)
	return offset.normalized().dot(facing) >= cos(GameConfig.INTERACTION_FACING_HALF_ANGLE)


func _perform_zellia_trade(peer_id: int, offer_index: int, target: Dictionary,
		gimmick: ZelliaGimmick, merchant_position: Vector2 = Vector2.INF) -> String:
	if merchant_position != Vector2.INF and not gimmick.in_range(
			target.get("position", Vector2.ZERO), merchant_position,
			target.get("facing", Vector2.ZERO)):
		var rejected := "ZELLIA'S STORE // TRADE REJECTED // MOVE CLOSER"
		if peer_id != (multiplayer.get_unique_id() if RoomState.online else 1):
			_remotes.send_player_event(peer_id, {"what": "message", "message": rejected})
		return rejected
	var offer_id := gimmick.offer_key(offer_index)
	var label := gimmick.offer_label(offer_index)
	var cost := gimmick.offer_cost(offer_index)
	if offer_id.is_empty():
		return ""
	if GameState.coins < cost:
		var refused := "ZELLIA'S STORE // NOT ENOUGH COINS FOR %s (%d)" % [label, cost]
		if peer_id != (multiplayer.get_unique_id() if RoomState.online else 1):
			_remotes.send_player_event(peer_id, {"what": "message", "message": refused})
		return refused

	GameState.coins -= cost
	var personal_offer := offer_id
	if offer_id == "repair":
		var relay := facility_view.find_sabotaged_relay()
		if relay:
			relay.set_sabotaged(false)
			personal_offer = ""
	var message := "ZELLIA'S STORE // TRADE COMPLETE // %s // -%d COINS" % [label, cost]
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	if peer_id == local_id:
		if not personal_offer.is_empty():
			gimmick.apply_personal_offer(personal_offer, player)
	else:
		_remotes.send_player_event(peer_id, {"what": "zellia_trade",
			"offer": personal_offer, "coins": GameState.coins, "message": message})
	if RoomState.online:
		_remotes.broadcast_event({"what": "coins", "coins": GameState.coins})
	# 2D: any deal can be fatal. She grabs through the normal capture path, the death line is drawn from the "deal" pool.
	var zellia_view: HunterView3D = null
	for view in hunter_views:
		if view.brain.gimmick == gimmick:
			zellia_view = view
	if zellia_view != null and zellia_view.brain.next_random_float() < float(
			GameConfig.ZELLIA_DEATH_CHANCE.get(RoomState.difficulty_id(), 0.05)):
		if peer_id == local_id:
			_death_via = "deal"
			_trigger_capture(zellia_view, true)
		else:
			_remotes.send_player_event(peer_id, {"what": "capture", "hunter_id": "zellia",
				"inescapable": true, "via": "deal"})
		return "ZELLIA'S STORE // THE DEAL COST MORE THAN COINS"
	return message


func _on_admin_ticket_changed(ready: bool, room_code: String,
		message: String) -> void:
	if not ready or room_code != RoomState.code or not RoomState.online \
			or RoomState.is_host or _remotes == null:
		return
	# Verify as soon as the ticket arrives so personal no-target/god state is
	# authoritative before the first hunter capture, even if the admin never
	# presses a shared floor-edit button.
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
	var what := String(event.get("what", ""))
	var permission := _admin_event_permission(event)
	if not permission.is_empty() \
			and not _remotes.remote_admin_peer_allowed(peer_id, permission):
		_remotes.send_player_event(peer_id, {"what": "message",
			"message": "ADMIN REQUEST REJECTED // PERMISSION REQUIRED"})
		return
	match what:
		"admin_auth":
			_remotes.send_player_event(peer_id, {"what": "message",
				"message": "ADMIN ROOM PROOF VERIFIED"})
		"admin_custom_map":
			_load_custom_map(String(event.get("url", "")), true)
		"admin_world":
			_apply_admin_world_action(String(event.get("action", "")), true)


func _admin_event_permission(event: Dictionary) -> String:
	var what := String(event.get("what", ""))
	if what == "admin_custom_map":
		return "world"
	if what != "admin_world":
		return ""
	var action := String(event.get("action", ""))
	return "hunters" if action in ["stun_hunters", "wake_hunters"] else "world"


func _heater_state() -> RouteInteractable3D.HeaterState:
	var station := facility_view.heater_station
	return station.heater_state if station else RouteInteractable3D.HeaterState.FROZEN


func _capture_target(view: HunterView3D, target: Dictionary,
		force_inescapable: bool = false) -> void:
	# Re-check at the authoritative capture boundary as well as inside the
	# brain. This covers gimmick-driven captures and a toggle changed between
	# target selection and the end of the simulation step.
	if _target_tools_authorized(target) and (bool(target.get("no_target", false)) \
			or bool(target.get("god_mode", false))):
		return
	var peer_id := int(target.get("peer_id", 1))
	_remotes.send_player_event(peer_id, {
		"what": "capture",
		"hunter_id": view.brain.hunter_id,
		"inescapable": force_inescapable or (view.brain.gimmick != null
			and view.brain.gimmick.capture_is_inescapable()),
	})


func _target_tools_authorized(target: Dictionary) -> bool:
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	return Build.admin_permission("player") \
		if int(target.get("peer_id", local_id)) == local_id \
		else _remotes.remote_admin_peer_allowed(int(target.get("peer_id", 0)), "player")


func _trigger_capture(view: HunterView3D, force_inescapable: bool = false) -> void:
	# A reliable capture packet may already be in flight when a guest toggles a
	# protection. Resolve it locally and release the host's pending-capture gate.
	if Build.admin_permission("player") \
			and (player.admin_no_target or player.admin_god_mode):
		if RoomState.online and not RoomState.is_host:
			_remotes.submit_hunter_event({"what": "capture_blocked"})
		return
	if GameState.is_capture_immune():
		if RoomState.online and not RoomState.is_host:
			_remotes.submit_hunter_event({
				"what": "caught",
				"hunter_id": view.brain.hunter_id,
			})
		return
	capturing_view = view
	Sound.capture()
	# Some captures skip the struggle entirely — a cooldown-gated grab, a
	# hunter whose gimmick declares the grab inescapable (Nyxie's dead-lamp
	# wake), or any VOID hunter (original: void is instant game over). All go
	# straight to the outcome, matching triggerGameOver().
	var identity := HunterRoster.get_identity(view.brain.hunter_id)
	# Prefer explicit roster membership for void ids, fall back to the
	# identity.category field when available. Use the void-set rather than a
	# loose string check so mis-typed categories do not accidentally trigger
	# instant game over for ordinary A-Z hunters.
	var is_void := HunterRoster.VOID_IDS.has(view.brain.hunter_id) \
		or String(identity.get("category", "az")) == "void"
	# Immediate resolution conditions: void hunters, gimmick-declared
	# inescapable grabs (Nyxie's dead-lamp etc.), an explicit forced
	# inescapable trigger, or a re-grab still inside the post-escape cooldown
	# (hunter-ai.js's triggerGameOver cooldown-skip branch).
	if force_inescapable or (view.brain.gimmick and view.brain.gimmick.capture_is_inescapable()) \
			or is_void or GameState.escape_on_cooldown():
		# Diagnostic: record why the capture skipped the escape struggle so
		# inspection in editor/runtime can show whether it was void/cooldown/
		# gimmick-forced. This helps when a session immediately ends without
		# presenting the struggle/jumpscare.
		var reason := []
		if is_void:
			reason.append("void")
		if force_inescapable:
			reason.append("forced")
		if view.brain.gimmick and view.brain.gimmick.capture_is_inescapable():
			reason.append("gimmick")
		if GameState.escape_on_cooldown():
			reason.append("cooldown")
		print("[capture] immediate-inescape: hunter=%s reasons=%s" % [view.brain.hunter_id, reason])
		# Show the jumpscare presentation first (if available) so the player
		# always sees an impact before the run ends. Await the director so the
		# visual completes prior to resolving game-over.
		if jumpscare != null:
			await jumpscare.play(player.active_camera(), view.brain.hunter_id)
		_resolve_capture_outcome()
		return
	player.input_frozen = true
	GameState.begin_escape(view.brain.hunter_id)
	# Publish the grab overlay in the same call that starts the struggle. The
	# regular frame HUD refresh is intentionally later, but capture must not
	# look like an instant death during a slow or blocked frame.
	hud.set_escape_active(true)
	hud.update_escape(GameState.escape_progress, GameState.escape_required,
		GameState.escape_remaining, GameState.escape_duration)
	print("[capture] grab-start: hunter=%s duration=%.2f required=%d" % [
		view.brain.hunter_id, GameState.escape_duration, GameState.escape_required])


func _update_escape_struggle(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		GameState.register_escape_press()
		Sound.struggle(GameState.escape_progress / maxf(1.0, GameState.escape_required))
	GameState.escape_remaining = maxf(0.0, GameState.escape_remaining - delta)

	if GameState.escape_progress >= GameState.escape_required:
		_resolve_escape_success()
	elif GameState.escape_remaining <= 0.0:
		_resolve_capture_outcome()


func _resolve_escape_success() -> void:
	GameState.resolve_escape_success()
	Sound.escape()

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

	if capturing_view and RoomState.online and not RoomState.is_host:
		_remotes.submit_hunter_event({
			"what": "escaped",
			"hunter_id": capturing_view.brain.hunter_id,
			"at": new_pos,
		})
	elif capturing_view:
		capturing_view.brain.enter_search_from(new_pos, 1.8)
		capturing_view.brain.apply_stun(GameConfig.profile_value(RoomState.difficulty_id(), "escape_stun"))
		capturing_view.sync_from_brain()

	hud.show_message("You broke free!")


## Shared by both a failed struggle and the no-struggle-at-all cooldown skip
## (hunter-ai.js's triggerGameOver: Nyxie/cooldown captures go straight
## here, everyone else only arrives via a timed-out struggle).
func _resolve_capture_outcome() -> void:
	if _capture_resolving:
		return
	_capture_resolving = true
	print("[capture] outcome-start: hunter=%s escape_active=%s" % [
		capturing_view.brain.hunter_id if capturing_view else "unknown",
		GameState.escape_active])
	player.input_frozen = true
	player.look_frozen = true
	var hunter_id := capturing_view.brain.hunter_id if capturing_view else \
		HunterRoster.DEFAULT_ID
	if RoomState.online and not RoomState.is_host:
		_remotes.submit_hunter_event({
			"what": "caught",
			"hunter_id": hunter_id,
		})
	if HunterJumpscare.ENABLED:
		Sound.office_jumpscare(hunter_id)
	await jumpscare.play(player.active_camera(), hunter_id)
	print("[capture] presentation-complete: hunter=%s" % hunter_id)
	await _play_death_moment(hunter_id)
	# Keep the run non-terminal while the capture presentation owns the camera.
	# Setting game_over before this await lets the main loop and co-op snapshot
	# path observe the death before the player sees the hunter.
	GameState.resolve_escape_failure()
	_enter_game_over()
	_capture_resolving = false
	_force_disable_admin_cheats()


## The short death cutscene (a line from the catcher, no jumpscare). Online it is an overlay only, solo the end card waits.
func _play_death_moment(hunter_id: String) -> void:
	if _death_moment == null:
		return
	var cause := {"hunter_id": hunter_id, "via": _death_via, "detail": ""}
	_death_via = "contact"
	if hunter_id == "nyxie" and capturing_view != null and capturing_view.brain.gimmick != null:
		cause["detail"] = "lamp" if capturing_view.brain.gimmick.capture_is_inescapable() else "darkness"
	var name := String(HunterRoster.get_identity(hunter_id).get("display_name", hunter_id))
	var picked := DeathLines.pick(cause, RoomState.seed_text, GameState.depth, name)
	if not DeathMoment.plays(picked):
		return
	var is_void := HunterRoster.VOID_IDS.has(hunter_id)
	if RoomState.online:
		_death_moment.play(name, picked, is_void)
	else:
		await _death_moment.play(name, picked, is_void)


func _enter_game_over() -> void:
	_force_disable_admin_cheats()
	player.input_frozen = true
	if pause_menu.is_open():
		pause_menu.close()
	pause_menu.tap_to_pause = false
	pause_menu.set_process(false)
	pause_menu.set_process_unhandled_input(false)
	var hunter_name := "UNKNOWN HUNTER"
	if capturing_view != null and capturing_view.brain != null:
		hunter_name = String(HunterRoster.get_identity(
			capturing_view.brain.hunter_id).get("display_name", hunter_name)).to_upper()
	# A completed solo run must not remain available as a Continue checkpoint.
	if not RoomState.online and Backend.signed_in():
		Backend.account_clear_progress()
	run_report.open({
		"online": RoomState.online,
		"host": RoomState.is_host,
		"title": "YOU DIED",
		"reason": "CAPTURED BY %s" % hunter_name,
		"depth": GameState.depth,
		"score": GameState.score,
		"relays": GameState.relays_collected,
		"relay_target": GameState.relay_target,
		"coins": GameState.coins,
		"difficulty": String(RoomState.DIFFICULTY_LABELS.get(
			RoomState.difficulty, "STANDARD")),
		"seed": RoomState.seed_text,
	})


func _restore_gameplay_after_report() -> void:
	run_report.close()
	player.look_frozen = false
	pause_menu.tap_to_pause = true
	pause_menu.set_process(true)
	pause_menu.set_process_unhandled_input(true)


func _restart_solo_route() -> void:
	if RoomState.online:
		return
	_force_disable_admin_cheats()
	_restore_gameplay_after_report()
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	observed_depth = GameState.depth
	_build_floor()
	_checkpoint_solo_route()
	player.input_frozen = false
	hud.show_message("NEW ROUTE SIGNAL // DEPTH 1")
	_update_hud()


func _leave_after_report() -> void:
	_force_disable_admin_cheats()
	_restore_gameplay_after_report()
	if RoomState.online and RoomState.is_host:
		RoomState.end_session("HOST ENDED THE ROUTE // BACK IN STAGING")
	elif RoomState.online:
		RoomState.status_message = "LEFT THE ROUTE"
		RoomState.leave_network()
		get_tree().change_scene_to_file(RoomState.menu_scene_path())
	else:
		RoomState.session_active = false
		get_tree().change_scene_to_file(RoomState.menu_scene_path())


func _update_hud() -> void:
	hud.update_objective(GameState.depth, GameState.relays_collected,
		GameState.relay_target)
	hud.update_battery(player.lamp_charge, player.flashlight_enabled, player.is_in_safe_zone(), player.movement_mode)
	hud.update_stamina(player.stamina, player.exhausted)
	hud.update_inventory(player.selected_inventory_item(), player.taser_cooldown,
		player.inventory_durability_snapshot(), player.inventory_owned_snapshot(),
		player.inventory_order_snapshot(), player.inventory_max_durability_snapshot(),
		player.selected_inventory_slot, player.inventory_slot_durability_snapshot())
	var thermal := _temperature_hunter_proximity()
	hud.update_meters(player.meters, thermal.x, thermal.y)
	hud.set_escape_active(GameState.escape_active)
	if GameState.escape_active:
		hud.update_escape(GameState.escape_progress, GameState.escape_required, GameState.escape_remaining, GameState.escape_duration)


func _temperature_hunter_proximity() -> Vector2:
	var strengths := Vector2.ZERO # x = heat, y = cold
	var player_position := player.grid_position()
	for view in hunter_views:
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


## Returns null outside a debug build, so nothing here exists in a release.
func _build_admin() -> void:
	admin_menu = AdminMenu.attach(self,
		func() -> String:
			return "ROOM %s  %s\nDEPTH %d  RELAYS %d/%d\nSEED %s" % [
				RoomState.code, RoomState.SCALE_LABELS[RoomState.map_scale],
				GameState.depth, GameState.relays_collected,
				GameState.relay_target, RoomState.seed_text],
		[
			{"heading": "CREATIVE INVENTORY", "label": "CREATIVE INVENTORY",
				"permission": "inventory",
				"items": PlayerController3D.COLLECTIBLE_ITEMS,
				"labels": PlayerController3D.INVENTORY_LABELS,
				"action": _admin_give_item},
			{"heading": "PLAYER TOOLS", "permission": "player"},
			{"label": "GRANT RELAY", "permission": "world", "action": func() -> void:
				_admin_world_action("grant_relay")},
			{"label": "ALL RELAYS", "permission": "world", "action": func() -> void:
				_admin_world_action("all_relays")},
			{"label": "FULL LAMP", "permission": "player", "action": func() -> void:
				player.restore_lamp(GameConfig.MAX_LAMP_CHARGE)},
			{"label": "RESTORE PLAYER", "action": _admin_restore_player,
				"permission": "player"},
			{"label": "CLEAR STUN + COOLDOWNS", "permission": "player",
				"action": func() -> void:
				player.stun_timer = 0.0
				player.taser_cooldown = 0.0},
			{"label": "TELEPORT TO START", "permission": "player", "action": func() -> void:
				player.global_position = facility_view.cell_to_world(
					facility_view.generator.start)},
			{"label": "TELEPORT TO EXIT", "permission": "player", "action": func() -> void:
				player.global_position = facility_view.cell_to_world(
					facility_view.generator.exit_cell)},
			{"heading": "ROOM TOOLS", "permission": "world"},
			{"label": "REBUILD FLOOR", "permission": "world", "action": func() -> void:
				_admin_world_action("rebuild")},
			{"label": "DESCEND", "permission": "world", "action": func() -> void:
				_admin_world_action("descend")},
			{"label": "STUN ALL HUNTERS", "permission": "hunters", "action": func() -> void:
				_admin_world_action("stun_hunters")},
			{"label": "WAKE ALL HUNTERS", "permission": "hunters", "action": func() -> void:
				_admin_world_action("wake_hunters")},
			{"label": "ALL ROOM LIGHTS ON", "permission": "world", "action": func() -> void:
				_admin_world_action("lights_on")},
			{"label": "ALL ROOM LIGHTS OFF", "permission": "world", "action": func() -> void:
				_admin_world_action("lights_off")},
			{"heading": "VISUAL TOOLS", "permission": "visual"},
			{"label": "TOGGLE PIXEL EFFECT", "action": _toggle_admin_pixel_effect,
				"permission": "visual",
				"state": func() -> bool: return pixel_signal_effect.admin_enabled()},
			{"label": "PIXEL EFFECT +", "permission": "visual", "action": func() -> void:
				Settings.set_pixel_effect_percent(Settings.pixel_effect_percent + 10.0)},
			{"label": "PIXEL EFFECT -", "permission": "visual", "action": func() -> void:
				Settings.set_pixel_effect_percent(Settings.pixel_effect_percent - 10.0)},
			# Both maps read _admin_reveal_hunters fresh every frame in
			# _process(), so flipping this needs nothing else to take effect.
			{"label": "TOGGLE HUNTER REVEAL", "action": _toggle_admin_hunter_reveal,
				"permission": "visual",
				"state": func() -> bool: return _admin_reveal_hunters},
			{"label": "TOGGLE NO TARGET", "action": _toggle_admin_no_target,
				"permission": "player",
				"state": func() -> bool: return player.admin_no_target},
			{"label": "TOGGLE GOD MODE", "action": _toggle_admin_god_mode,
				"permission": "player",
				"state": func() -> bool: return player.admin_god_mode},
			{"label": "TOGGLE NOCLIP", "action": _toggle_admin_noclip,
				"permission": "player",
				"state": func() -> bool: return player.admin_noclip},
		],
		[
			{"label": "CUSTOM MAP URL", "placeholder": "https://.../map.png",
				"on_submit": _load_custom_map, "permission": "world"},
			{"label": "ADD / UPDATE LIMITED ADMIN",
				"placeholder": "USERNAME:player,world,hunters,visual,inventory",
				"on_submit": Backend.admin_roster_set_spec, "owner_only": true},
			{"label": "REMOVE LIMITED ADMIN", "placeholder": "USERNAME",
				"on_submit": Backend.admin_roster_remove, "owner_only": true},
		])
	if admin_menu != null:
		_apply_persisted_admin_preferences()
		admin_menu.open_changed.connect(_on_admin_menu_open_changed)
		if not Backend.admin_roster_changed.is_connected(_on_admin_roster_changed):
			Backend.admin_roster_changed.connect(_on_admin_roster_changed)


func _on_admin_roster_changed(ok: bool, message: String, _roster: Array) -> void:
	hud.show_message(("ADMIN ROSTER // " if ok else "ADMIN ROSTER FAILED // ") + message)


func _on_admin_menu_open_changed(shown: bool) -> void:
	if shown:
		hud.set_inventory_open(false)
		if _room_chat != null:
			_room_chat.close()
	player.velocity = Vector3.ZERO
	player.input_frozen = shown or _player_controls_blocked()


func _dismiss_gameplay_overlay() -> bool:
	if admin_menu != null and admin_menu.is_open():
		admin_menu.close()
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
	player.input_frozen = _player_controls_blocked()


func _player_controls_blocked() -> bool:
	return _awaiting_initial_snapshot or GameState.game_over \
		or GameState.escape_active or player.hidden or player.is_stunned() \
		or (pause_menu != null and pause_menu.is_open()) \
		or (hud != null and hud.inventory_is_open()) \
		or (hud != null and hud.map_is_open()) \
		or (_room_chat != null and _room_chat.is_open()) \
		or (admin_menu != null and admin_menu.is_open())


var _void_fx: VoidPlayerEffects


## A signal route (Gray) ended on this player's machine: the host decides what it means.
func _report_void_route(ok: bool) -> void:
	if RoomState.online and not RoomState.is_host:
		_remotes.request_interaction({"what": "signal_route_result", "ok": ok})
	else:
		VoidPlayerEffects.host_route_result(hunter_views,
			multiplayer.get_unique_id() if RoomState.online else 1, ok)


func _on_map_open_changed(_shown: bool) -> void:
	player.velocity = Vector3.ZERO
	player.input_frozen = _player_controls_blocked()


func _on_chat_open_changed(_shown: bool) -> void:
	if _shown:
		hud.set_inventory_open(false)
	player.velocity = Vector3.ZERO
	player.input_frozen = _player_controls_blocked()


func _admin_give_item(item_id: String) -> void:
	if player.grant_inventory_item(item_id):
		hud.show_message("ADMIN GIVE // %s" % String(
			PlayerController3D.INVENTORY_LABELS.get(item_id, item_id)).to_upper())
	else:
		hud.show_message("ADMIN GIVE FAILED // INVENTORY FULL")


func _admin_restore_player() -> void:
	player.restore_at_safe_zone()
	player.stun_timer = 0.0
	player.taser_cooldown = 0.0
	player.meters.exposure = 0.0
	player.meters.noise_meter = 0.0
	player.meters.temperature = player.meters.ambient


## Route-wide debug commands use the same guest -> host intent path as hunter
## interactions. Personal commands (lamp/no-target/god/reveal) deliberately
## stay on the admin who pressed them.
func _admin_world_action(action: String) -> void:
	var permission := "hunters" if action in ["stun_hunters", "wake_hunters"] \
		else "world"
	if not Build.admin_permission(permission):
		return
	if RoomState.online and not RoomState.is_host:
		if not _guest_admin_proof_ready():
			return
		_remotes.request_interaction({"what": "admin_world", "action": action})
		hud.show_message("ADMIN // %s SENT TO HOST" % action.replace("_", " ").to_upper())
		return
	_apply_admin_world_action(action)


func _apply_admin_world_action(action: String, authorized_remote: bool = false) -> void:
	var permission := "hunters" if action in ["stun_hunters", "wake_hunters"] \
		else "world"
	if (not authorized_remote and not Build.admin_permission(permission)) \
		or not ["grant_relay", "all_relays", "rebuild",
			"descend", "stun_hunters", "wake_hunters", "lights_on",
			"lights_off"].has(action):
		return
	match action:
		"grant_relay":
			_admin_collect_relays(1)
		"all_relays":
			_admin_collect_relays(-1)
		"rebuild":
			# A rebuilt floor is a fresh copy of this depth. Reset its durable
			# pickup state before spawning new interactables so the HUD cannot
			# report a completed objective beside newly collectible relays.
			GameState.start_floor()
			_build_floor()
		"descend":
			GameState.descend()
			observed_depth = GameState.depth
			_build_floor()
			_checkpoint_solo_route()
		"stun_hunters":
			for view in hunter_views:
				view.brain.apply_stun(10.0)
				view.sync_from_brain()
		"wake_hunters":
			for view in hunter_views:
				view.brain.active = true
				view.brain.state = HunterBrain.State.SEARCH
				view.sync_from_brain()
		"lights_on":
			facility_view.set_all_room_lights(true)
		"lights_off":
			facility_view.set_all_room_lights(false)
	if _remotes != null:
		_remotes.broadcast_snapshot()


## Admin relay grants are real shared-world pickups, not HUD counter edits.
## Reusing the same event path as a player pickup completes/hides the relay,
## disables its collision, marks generator state for hunter gimmicks, awards
## score, and sends the exact cell to every connected guest.
## `maximum < 0` means every relay still present on the floor.
func _admin_collect_relays(maximum: int) -> void:
	var remaining: Array[RouteInteractable3D] = []
	var already_collected := 0
	for entry in facility_view.generator.relays:
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		var relay := facility_view._at(cell, RouteInteractable3D.Kind.RELAY)
		if relay == null:
			continue
		if relay.completed:
			already_collected += 1
		else:
			remaining.append(relay)
	# Repair counter-only state left by older debug builds before applying any
	# new pickups. Relay objects are the durable source of truth on this floor.
	GameState.relays_collected = already_collected
	var collected_now := 0
	for relay in remaining:
		if maximum >= 0 and collected_now >= maximum:
			break
		var event := {
			"what": "pickup",
			"cell": relay.source_cell,
			"kind": int(RouteInteractable3D.Kind.RELAY),
		}
		_apply_world_event(event)
		if _remotes != null:
			_remotes.relay_world_event(event)
		collected_now += 1
	if collected_now > 0:
		Sound.collect()


func _toggle_admin_god_mode() -> void:
	player.admin_god_mode = not player.admin_god_mode
	Settings.set_admin_preference("god_mode", player.admin_god_mode)
	if not player.admin_god_mode:
		return
	if GameState.escape_active:
		GameState.cancel_escape()
		capturing_view = null
		player.input_frozen = _player_controls_blocked()
		if RoomState.online and not RoomState.is_host:
			_remotes.submit_hunter_event({"what": "capture_blocked"})


func _apply_persisted_admin_preferences() -> void:
	var player_tools := Build.admin_permission("player")
	var visual_tools := Build.admin_permission("visual")
	player.admin_no_target = player_tools and Settings.admin_preference("no_target")
	player.admin_god_mode = player_tools and Settings.admin_preference("god_mode")
	player.set_admin_noclip(player_tools and Settings.admin_preference("noclip"))
	_admin_reveal_hunters = visual_tools and Settings.admin_preference("hunter_reveal")
	pixel_signal_effect.set_admin_enabled(
		visual_tools and Settings.admin_preference("pixel_effect_enabled"))


func _toggle_admin_no_target() -> void:
	player.admin_no_target = not player.admin_no_target
	Settings.set_admin_preference("no_target", player.admin_no_target)


func _toggle_admin_noclip() -> void:
	player.set_admin_noclip(not player.admin_noclip)
	Settings.set_admin_preference("noclip", player.admin_noclip)


func _toggle_admin_hunter_reveal() -> void:
	_admin_reveal_hunters = not _admin_reveal_hunters
	Settings.set_admin_preference("hunter_reveal", _admin_reveal_hunters)


func _toggle_admin_pixel_effect() -> void:
	pixel_signal_effect.set_admin_enabled(not pixel_signal_effect.admin_enabled())
	Settings.set_admin_preference("pixel_effect_enabled",
		pixel_signal_effect.admin_enabled())


## Force runtime admin cheat flags off on the current player/scene.
## Called on run termination paths (death, abandon, leave, restart) so noclip/god
## etc. do not remain active for the finished state or an immediate in-place restart.
## Persisted preferences are left unchanged; a fresh scene load will re-apply them
## via _apply_persisted_admin_preferences for authorized admins.
func _force_disable_admin_cheats() -> void:
	if player != null:
		player.admin_no_target = false
		player.admin_god_mode = false
		player.set_admin_noclip(false)
		if player.has_method("leave_spectator"):
			player.leave_spectator()
		player.spectator_mode = false
	_admin_reveal_hunters = false
	if pixel_signal_effect != null:
		pixel_signal_effect.set_admin_enabled(false)
	# Do not touch persisted prefs here; termination only clears the active session state.


## Put the host's visual hunter copies into their authoritative state. Clients
## do not update these brains; sync_from_brain only turns this packet into the
## same position, visibility, model/disguise and animation the host sees.
func _apply_hunters(data: Array) -> void:
	for entry in data:
		var view := _find_hunter(String(entry.get("id", "")))
		if view == null:
			continue
		var position_value = entry.get("position")
		var facing_value = entry.get("facing")
		if position_value is Vector2:
			view.brain.position = position_value
		if facing_value is Vector2:
			view.brain.facing = facing_value
		view.brain.active = bool(entry.get("active", false))
		view.brain.state = clampi(int(entry.get("state", HunterBrain.State.IDLE)),
			HunterBrain.State.IDLE, HunterBrain.State.SEARCH)
		view.brain.stun_timer = maxf(0.0, float(entry.get("stun", 0.0)))
		view.target_peer_id = maxi(0, int(entry.get("target_peer_id", 0)))
		view.set_look_target(entry.get("look_target"))
		if view.brain.gimmick is UmbrielGimmick:
			view.brain.gimmick.disguise_id = String(entry.get("disguise", ""))
		if view.brain.gimmick is NyxieGimmick:
			view.brain.gimmick.wake_mode = clampi(int(entry.get("wake", 0)),
				NyxieGimmick.Wake.NONE, NyxieGimmick.Wake.EMPTY)
		if view.brain.gimmick != null:
			var gimmick_state = entry.get("gimmick", {})
			if gimmick_state is Dictionary:
				view.brain.gimmick.apply_network_state(gimmick_state)
		if view.brain.hard != null and entry.get("hard") is Dictionary:
			view.brain.hard.apply_network_state(entry["hard"])
		view.sync_from_brain()


func _update_local_audio(delta: float) -> void:
	if player == null:
		return
	var nearest := INF
	var stepping_hunter: HunterView3D
	var stepping_distance := INF
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	var locally_pursued := false
	for view in hunter_views:
		var id := view.brain.hunter_id
		var was_active := bool(_audio_hunter_active.get(id, false))
		if view.brain.active:
			var view_distance := view.brain.position.distance_to(player.grid_position())
			nearest = minf(nearest, view_distance)
			if view.brain.state != HunterBrain.State.IDLE and view_distance < stepping_distance:
				stepping_hunter = view
				stepping_distance = view_distance
			if view.brain.state == HunterBrain.State.CHASE \
					and view.brain.stun_timer <= 0.0 \
					and view.target_peer_id == local_id:
				locally_pursued = true
			if id == "nyxie" and not was_active and view.brain.gimmick is NyxieGimmick:
				if view.brain.gimmick.wake_mode == NyxieGimmick.Wake.EMPTY:
					Sound.nyxie_empty_wake()
				else:
					Sound.nyxie_timer_wake()
		_audio_hunter_active[id] = view.brain.active
		if id == "nyxie" and was_active and not view.brain.active:
			Sound.alert()
	if locally_pursued and not _was_locally_pursued:
		Sound.chase_start()
	_was_locally_pursued = locally_pursued
	var danger := 0.0 if nearest == INF else clampf(1.0 - (nearest - .5) / 9.0, 0.0, 1.0)
	if locally_pursued:
		danger = maxf(danger, .48)
	if player.is_in_safe_zone():
		danger = 0.0
	Sound.heartbeat(danger)
	if stepping_hunter == null or player.hidden:
		_hunter_step_elapsed = 0.0
		return
	_hunter_step_elapsed += delta
	var step_gap := .30 if stepping_hunter.brain.state == HunterBrain.State.CHASE else .43
	if _hunter_step_elapsed < step_gap:
		return
	_hunter_step_elapsed = 0.0
	var offset := stepping_hunter.brain.position - player.grid_position()
	var distance := offset.length()
	if distance > 9.0:
		return
	var right := Vector2(-player.facing.y, player.facing.x)
	var pan := clampf(offset.dot(right) / 4.5, -1.0, 1.0)
	Sound.hunter_footstep(pan, .09 * (1.0 - distance / 9.0))


func _find_hunter(hunter_id: String) -> HunterView3D:
	for view in hunter_views:
		if view.brain.hunter_id == hunter_id:
			return view
	return null


func _dispatch_player_event(target: Dictionary, event: Dictionary) -> void:
	_remotes.send_player_event(int(target.get("peer_id", 1)), event)


func _apply_player_event(event: Dictionary) -> void:
	if _void_fx != null and _void_fx.apply(event):
		return
	match String(event.get("what", "")):
		"capture":
			if String(event.get("via", "")) != "":
				_death_via = String(event.get("via", "contact"))
			var view := _find_hunter(String(event.get("hunter_id", "")))
			if view:
				_trigger_capture(view, bool(event.get("inescapable", false)))
		"stun":
			player.stun_timer = maxf(player.stun_timer,
				float(event.get("seconds", 0.0)))
			var stun_note := String(event.get("message", ""))
			if not stun_note.is_empty():
				hud.show_message(stun_note)
		"eject":
			if not player.hidden:
				return
			var expected = event.get("cell")
			if expected is Vector2i and player.hidden_spot != expected:
				return
			var at = event.get("at", Vector2.ZERO)
			player.leave_hiding(at if at is Vector2 else Vector2.ZERO, true)
			var eject_note := String(event.get("message", ""))
			if not eject_note.is_empty():
				hud.show_message(eject_note)
		"meter_effect":
			player.meters.add_exposure(float(event.get("exposure_add", 0.0)))
			player.meters.reclaim_noise(float(event.get("noise_reclaim", 0.0)))
			player.meters.add_noise(float(event.get("noise_add", 0.0)))
			player.meters.temperature = clampf(player.meters.temperature
				+ float(event.get("temperature_add", 0.0)), 0.0, 100.0)
			if bool(event.get("heat_lock", false)):
				player.meters.heat_locked = true
				player.meters.temperature = maxf(player.meters.temperature,
					GameConfig.TEMPERATURE_OVERHEAT)
		"zellia_trade":
			GameState.coins = int(event.get("coins", GameState.coins))
			var offer_id := String(event.get("offer", ""))
			if not offer_id.is_empty():
				for view in hunter_views:
					if view.brain.gimmick is ZelliaGimmick:
						view.brain.gimmick.apply_personal_offer(offer_id, player)
						break
			var trade_note := String(event.get("message", ""))
			if not trade_note.is_empty():
				hud.show_message(trade_note)
		"message":
			var note := String(event.get("message", ""))
			if not note.is_empty():
				hud.show_message(note)


## Guest escape/respawn outcomes return to the host so its simulation can
## release or reset the hunter which owns the grab.
func _apply_hunter_event(event: Dictionary) -> void:
	if RoomState.online and not RoomState.is_host:
		return
	match String(event.get("what", "")):
		"taser":
			var local_id := multiplayer.get_unique_id() if RoomState.online else 1
			_resolve_taser_request(int(event.get("peer_id", local_id)))
		"escaped":
			var view := _find_hunter(String(event.get("hunter_id", "")))
			var at = event.get("at")
			if view and at is Vector2:
				view.brain.enter_search_from(at, 1.8)
				view.brain.apply_stun(GameConfig.profile_value(RoomState.difficulty_id(), "escape_stun"))
				view.sync_from_brain()
		"caught":
			# The remote state packet marks this runner game-over; no hunter reset
			# is needed, but accepting the event releases the pending-capture gate.
			pass


func _on_taser_requested() -> void:
	if RoomState.online and not RoomState.is_host:
		_remotes.submit_hunter_event({"what": "taser"})
		return
	var peer_id := multiplayer.get_unique_id() if RoomState.online else 1
	_resolve_taser_request(peer_id)


## Host-authoritative cone hit. The request names no hunter and carries no
## transform, so a co-op guest cannot forge either; the host uses its most
## recent validated runner state and the same maze line-of-sight as hunter AI.
func _resolve_taser_request(peer_id: int) -> void:
	if not _remotes.simulates():
		return
	var now := Time.get_ticks_usec()
	if now < int(_taser_ready_usec_by_peer.get(peer_id, 0)):
		return
	_taser_ready_usec_by_peer[peer_id] = now + int(GameConfig.profile_value(RoomState.difficulty_id(), "taser_cooldown") * 1_000_000.0)
	var target := _remotes.state_for_peer(peer_id, _local_hunter_target(), GameState.depth)
	if target.is_empty() or bool(target.get("hidden", false)) \
			or bool(target.get("game_over", false)):
		return
	var from = target.get("position")
	var aim = target.get("facing")
	if not from is Vector2 or not aim is Vector2:
		return
	var hit: HunterView3D
	var nearest := INF
	for view in hunter_views:
		if view.brain == null or not view.brain.active:
			continue
		var distance: float = from.distance_to(view.brain.position)
		if distance >= nearest:
			continue
		if view.brain.beam_reaches(from, aim, view.brain.position,
				GameConfig.TASER_RANGE, GameConfig.TASER_HALF_ANGLE,
				facility_view.generator):
			hit = view
			nearest = distance
	if hit == null:
		_remotes.send_player_event(peer_id, {"what": "message",
			"message": "TASER // NO TARGET"})
		return
	hit.brain.apply_stun(GameConfig.profile_value(RoomState.difficulty_id(), "taser_stun"))
	hit.sync_from_brain()
	var identity := HunterRoster.get_identity(hit.brain.hunter_id)
	_remotes.send_player_event(peer_id, {"what": "message",
		"message": "TASER HIT // %s STUNNED %.1fs" % [
			String(identity.get("display_name", hit.brain.hunter_id)).to_upper(),
			GameConfig.profile_value(RoomState.difficulty_id(), "taser_stun")]})


## Something the local player did that the room shares. Sent as-is; the effect
## already happened here.
func _on_world_changed(event: Dictionary) -> void:
	if _remotes != null:
		_remotes.broadcast_event(event)


## Account checkpoints are floor-start recovery points, not live world dumps.
## That keeps them small and deterministic: partial pickups/hunter positions
## never need replay, co-op never forks host state, and authored PNG payloads
## are left to their own map workflow.
func _checkpoint_solo_route() -> void:
	if RoomState.online or not Backend.signed_in() or not _custom_map_png.is_empty():
		return
	Backend.account_save_progress(GameState.route_checkpoint(
		RoomState.seed_text, RoomState.map_scale, RoomState.difficulty,
		RoomState.difficulty_id()))


## Validate a guest's predicted world interaction before it becomes durable.
## The sender id and last known position come from ENet/host state, never from
## the request dictionary. Accepted events are applied once on the host and
## then relayed with canonical counters to every guest.
func _apply_world_request(peer_id: int, event: Dictionary) -> void:
	if not _remotes.simulates():
		return
	var target := _remotes.state_for_peer(peer_id, _local_hunter_target(), GameState.depth)
	if target.is_empty():
		return
	var accepted := false
	match String(event.get("what", "")):
		"pickup":
			var cell = event.get("cell")
			var kind := int(event.get("kind", -1))
			if cell is Vector2i and kind in [RouteInteractable3D.Kind.RELAY,
					RouteInteractable3D.Kind.BATTERY, RouteInteractable3D.Kind.COIN] \
					and _target_can_interact(target, cell):
				var item := facility_view._at(cell, kind)
				accepted = item != null and not item.completed
				if accepted and kind == RouteInteractable3D.Kind.BATTERY \
						and int(target.get("inventory_free_slots", 0)) <= 0:
					accepted = false
				if accepted and item.kind == RouteInteractable3D.Kind.RELAY \
						and item.locked_cache:
					var tool := String(event.get("tool", ""))
					accepted = bool(event.get("locked_cache", false)) \
						and PlayerController3D.LOCK_TOOLS.has(tool) \
						and String(target.get("selected_item", "")) == tool \
						and bool((target.get("owned_items", {}) as Dictionary).get(tool, false)) \
						and int((target.get("item_durability", {}) as Dictionary).get(tool, 0)) > 0
				elif accepted and bool(event.get("locked_cache", false)):
					accepted = false
		"boarded_path":
			var cell = event.get("cell")
			var tool := String(event.get("tool", ""))
			if cell is Vector2i \
					and PlayerController3D.BREACH_TOOLS.has(tool) \
					and String(target.get("selected_item", "")) == tool \
					and bool((target.get("owned_items", {}) as Dictionary).get(tool, false)) \
					and int((target.get("item_durability", {}) as Dictionary).get(tool, 0)) > 0 \
					and _target_can_interact(target, cell):
				var barrier := facility_view._at(cell,
					RouteInteractable3D.Kind.BOARDED_PATH)
				var next_pieces := int(event.get("pieces_remaining", -1))
				accepted = barrier != null and not barrier.opened \
					and next_pieces == maxi(0, barrier.board_pieces_remaining - 1) \
					and bool(event.get("opened", false)) == (next_pieces <= 0)
		"room_light":
			var cell = event.get("cell")
			if cell is Vector2i and _target_can_interact(target, cell):
				var switch := facility_view._at(cell,
					RouteInteractable3D.Kind.LIGHT_SWITCH)
				accepted = switch != null \
					and String(event.get("light_id", "")) == switch.light_id \
					and bool(event.get("enabled", switch.light_enabled)) != switch.light_enabled
		"heater":
			if facility_view.heater_station != null and _target_can_interact(
					target, facility_view.heater_station.source_cell):
				var current := int(facility_view.heater_station.heater_state)
				var expected := RouteInteractable3D.HeaterState.UNFROZEN \
					if current == RouteInteractable3D.HeaterState.POWERED else current + 1
				accepted = int(event.get("state", -1)) == expected
		"sabotage":
			var cell = event.get("cell")
			if cell is Vector2i and not bool(event.get("sabotaged", true)) \
					and _target_can_interact(target, cell):
				var relay := facility_view._at(cell, RouteInteractable3D.Kind.RELAY)
				accepted = relay != null and relay.sabotaged
		"descend":
			accepted = _target_can_interact(target, facility_view.generator.exit_cell) \
				and GameState.relays_collected >= GameState.relay_target \
				and GameState.relays_sabotaged == 0 \
				and int(event.get("depth", -1)) == GameState.depth + 1
	if not accepted:
		# The next canonical snapshot/event corrects durable counters. Personal
		# battery prediction is intentionally not rolled back; only one runner can
		# win the shared cell, and the losing edge is a sub-frame race.
		_remotes.send_player_event(peer_id, {"what": "message",
			"message": "INTERACTION REJECTED // WORLD STATE CHANGED"})
		return
	_apply_world_event(event)
	_remotes.relay_world_event(event)


## The same thing, arriving from someone else.
##
## Not gated on simulates(): a pickup is not a hunter-simulation step. Guests
## apply their interaction immediately, then the host relays the idempotent fact
## to every peer (including the sender).
func _apply_world_event(event: Dictionary) -> void:
	_play_world_audio(event)
	match String(event.get("what", "")):
		"descend":
			# Let the depth change do the work -- _process already rebuilds the
			# floor whenever it moves, which is the same path the local lift
			# takes.
			var depth := int(event.get("depth", GameState.depth))
			if depth != GameState.depth:
				GameState.depth = depth
				GameState.start_floor()
		"heater":
			facility_view.apply_event(event)
			# One station, one building: the cold it holds off is held off for
			# whoever is standing in it, not just whoever threw the switch.
			player.heater_on = _heater_state() == RouteInteractable3D.HeaterState.POWERED
		"coins":
			pass
		_:
			facility_view.apply_event(event)
	# Host-attached canonical counters correct optimistic guest interactions
	# and make every durable total converge even when two peers race one cell.
	if event.has("relays"):
		GameState.relays_collected = int(event["relays"])
	if event.has("relays_sabotaged"):
		GameState.relays_sabotaged = int(event["relays_sabotaged"])
	if event.has("coins"):
		GameState.coins = int(event["coins"])
	if event.has("score"):
		GameState.score = int(event["score"])


func _play_world_audio(event: Dictionary) -> void:
	var what := String(event.get("what", ""))
	var note := String(event.get("message", ""))
	if what == "thessine_mimic":
		_play_thessine_mimic(event)
		return
	if what in ["sabotage", "hiding_disabled", "sound_alert"] or String(event.get("sound", "")) == "alert" \
			or (what == "pickup" and note.begins_with("YSOLDE")):
		Sound.alert()


func _play_thessine_mimic(event: Dictionary) -> void:
	var rare := bool(event.get("rare", false))
	var cueable: Array[String] = []
	for view in hunter_views:
		if not view.brain.active or view.brain.hunter_id == "thessine":
			continue
		if view.brain.hunter_id in ["nyxie", "glyra", "ferryn", "briselle",
				"loxelle", "ravelle", "haelith"]:
			cueable.append(view.brain.hunter_id)
	cueable.sort()
	if rare or cueable.is_empty():
		Sound.mimic(rare)
		return
	var choice := clampf(float(event.get("choice", 0.0)), 0.0, 0.999999)
	var source := cueable[int(choice * cueable.size())]
	match source:
		"nyxie":
			Sound.nyxie_timer_wake()
		"glyra":
			Sound.music_box()
		"haelith":
			Sound.hunter_footstep(0.0, 0.09)
		_:
			Sound.alert()


## What the host tells a peer that joined after the floor started.
func _build_snapshot() -> Dictionary:
	_collect_hunter_report()
	var state := facility_view.shared_state()
	state["snapshot_protocol"] = SNAPSHOT_PROTOCOL
	state["floor_revision"] = _floor_revision
	state["floor_source"] = "custom" if not _custom_map_png.is_empty() else "procedural"
	if not _custom_map_png.is_empty():
		state["custom_map_png"] = _custom_map_png.duplicate()
		state["custom_map_seed"] = _custom_map_seed
	state["depth"] = GameState.depth
	state["relays"] = GameState.relays_collected
	state["relays_sabotaged"] = GameState.relays_sabotaged
	state["coins"] = GameState.coins
	state["score"] = GameState.score
	state["hunters"] = _hunter_report.duplicate(true)
	return state


func _apply_world_snapshot(state: Dictionary) -> void:
	if int(state.get("snapshot_protocol", 0)) != SNAPSHOT_PROTOCOL:
		var protocol_message := "SYNC FAILED // SNAPSHOT VERSION MISMATCH // RETRYING"
		hud.show_message(protocol_message)
		route_loading.show_snapshot_retry(protocol_message)
		return
	var depth := int(state.get("depth", GameState.depth))
	var depth_changed := depth != GameState.depth
	if depth != GameState.depth:
		GameState.depth = depth
		GameState.start_floor()
		observed_depth = depth

	# Build the authoritative base floor before applying cell-addressed state.
	# A late joiner initially has a procedural placeholder, which is not useful
	# when the host loaded a hand-painted map during this depth.
	var floor_source := String(state.get("floor_source", "procedural"))
	var host_floor_revision := int(state.get("floor_revision", 0))
	if floor_source == "custom":
		# Ordinary state broadcasts for the same authored floor must not rebuild
		# its GridMap: that respawns/teleports the guest and briefly replaces all
		# interactables whenever an admin changes one relay. Install only when the
		# authoritative base floor actually changed or is missing locally.
		var needs_custom_base := depth_changed or _custom_map_png.is_empty() \
			or host_floor_revision != _applied_host_floor_revision
		if needs_custom_base:
			var payload = state.get("custom_map_png", PackedByteArray())
			if not payload is PackedByteArray:
				var message := "SYNC FAILED // CUSTOM MAP PAYLOAD INVALID // RETRYING"
				hud.show_message(message)
				route_loading.show_snapshot_retry(message)
				return
			var custom_seed := String(state.get("custom_map_seed",
				"%s:CUSTOM" % GameState.level_seed_text()))
			var custom_error := _install_custom_map_png(payload, custom_seed)
			if not custom_error.is_empty():
				var message := "SYNC FAILED // %s // RETRYING" % custom_error.to_upper()
				hud.show_message(message)
				route_loading.show_snapshot_retry(message)
				return
	elif depth_changed or not _custom_map_png.is_empty() \
			or host_floor_revision != _applied_host_floor_revision:
		_build_floor()
	# Built here rather than left to _process, because the state below has to
	# land on the floor it describes and not on the one being replaced.
	facility_view.adopt_state(state)
	# Snapshots are authoritative. Exact assignment also rolls back the count
	# from an optimistic guest pickup which the host rejected.
	GameState.relays_collected = int(state.get("relays", GameState.relays_collected))
	GameState.relays_sabotaged = int(state.get("relays_sabotaged",
		GameState.relays_sabotaged))
	GameState.coins = int(state.get("coins", GameState.coins))
	GameState.score = int(state.get("score", GameState.score))
	var hunters = state.get("hunters", [])
	if hunters is Array:
		_apply_hunters(hunters)
	player.heater_on = _heater_state() == RouteInteractable3D.HeaterState.POWERED
	_awaiting_initial_snapshot = false
	_applied_host_floor_revision = host_floor_revision
	player.input_frozen = _player_controls_blocked()
	if _remotes != null:
		_remotes.confirm_snapshot_applied()
	route_loading.dismiss()
	_update_hud()


func _on_abandoned() -> void:
	_force_disable_admin_cheats()
	get_tree().paused = false
	if RoomState.online and RoomState.is_host:
		RoomState.end_session("HOST ENDED THE ROUTE // BACK IN STAGING")
	elif RoomState.online:
		RoomState.status_message = "LEFT THE ROUTE // BACK IN STAGING"
		RoomState.leave_network()
		get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")
	else:
		get_tree().change_scene_to_file(RoomState.menu_scene_path())


func _on_pause_opened() -> void:
	hud.set_inventory_open(false)
	if RoomState.online:
		player.input_frozen = true


func _on_pause_resumed() -> void:
	if RoomState.online:
		player.input_frozen = _player_controls_blocked()


func _on_interaction_message(message: String) -> void:
	hud.show_message(message)


func _build_floor() -> void:
	_floor_revision += 1
	_custom_map_png = PackedByteArray()
	_custom_map_seed = ""
	facility_view.generate_floor(GameState.level_seed_text())
	_after_floor_built()


## The end of a floor build every path shares: sync the relay target to
## whatever actually got placed, put the player on the real start (not
## wherever they stood on the last floor), and give the hunters a fresh spawn.
func _after_floor_built() -> void:
	GameState.relay_target = facility_view.generator.relay_count
	player.position = _player_spawn_world_position()
	player.velocity = Vector3.ZERO
	player.input_frozen = _player_controls_blocked()
	_spawn_hunter()


## Use authored green spawn cells first, then nearby open cells if the room has
## more players than authored spawns. Every peer builds the same ordered list
## and uses its roster index, so no extra spawn RPC is needed.
func _player_spawn_world_position(peer_id: int = -1) -> Vector3:
	var ordinary := facility_view.start_world_position()
	if not RoomState.online and peer_id < 0:
		return ordinary
	var id := peer_id if peer_id >= 0 else multiplayer.get_unique_id()
	var ids: Array = RoomState.peers.keys()
	ids.sort()
	var roster_index := ids.find(id)
	if roster_index < 0:
		roster_index = maxi(0, id - 1)
	var start := facility_view.generator.start
	var nearby_cells: Array = facility_view.generator.floor_cells()
	nearby_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance := a.distance_squared_to(start)
		var b_distance := b.distance_squared_to(start)
		if a_distance != b_distance:
			return a_distance < b_distance
		return a.y < b.y if a.y != b.y else a.x < b.x)
	var cells: Array = facility_view.generator.spawn_points.duplicate()
	for nearby_cell in nearby_cells:
		if not cells.has(nearby_cell):
			cells.append(nearby_cell)
	if cells.is_empty():
		return ordinary
	var cell: Vector2i = cells[roster_index % mini(cells.size(), RoomState.MAX_PLAYERS)]
	return Vector3(cell.x + 0.5, ordinary.y, cell.y + 0.5)


## Admin-only: fetches a raw PNG by URL and rebuilds the current floor from it
## via CustomMapParser, instead of the next depth's procedural one. Async --
## HTTPRequest is signal-driven, so this kicks the fetch off and the actual
## rebuild happens in _on_custom_map_response() once it lands.
func _load_custom_map(url: String, authorized_remote: bool = false) -> void:
	if not authorized_remote and not Build.admin_permission("world"):
		return
	var trimmed := url.strip_edges()
	if trimmed.is_empty():
		return
	if trimmed.length() > 2048 or not (trimmed.begins_with("https://") \
			or trimmed.begins_with("http://")):
		hud.show_message("CUSTOM MAP // ENTER A VALID HTTP(S) PNG URL")
		return
	if RoomState.online and not RoomState.is_host:
		if not _guest_admin_proof_ready():
			return
		_remotes.request_interaction({"what": "admin_custom_map", "url": trimmed})
		hud.show_message("CUSTOM MAP // SENT TO HOST FOR INSTALL")
		return
	if _custom_map_fetching:
		hud.show_message("CUSTOM MAP // ALREADY FETCHING ONE")
		return
	if _custom_map_request == null:
		_custom_map_request = HTTPRequest.new()
		_custom_map_request.body_size_limit = CUSTOM_MAP_MAX_BYTES
		add_child(_custom_map_request)
		_custom_map_request.request_completed.connect(_on_custom_map_response)
	var error := _custom_map_request.request(trimmed)
	if error != OK:
		hud.show_message("CUSTOM MAP // COULD NOT START REQUEST (%d)" % error)
		return
	_custom_map_fetching = true
	hud.show_message("CUSTOM MAP // FETCHING...")


func _guest_admin_proof_ready() -> bool:
	if not RoomState.online or RoomState.is_host \
			or Build.remote_guest_tools_allowed():
		return true
	if not Backend.admin_ticket_for_room(RoomState.code).is_empty():
		return true
	Backend.request_admin_ticket(RoomState.code)
	hud.show_message("ADMIN // REQUESTING ROOM PROOF // TRY AGAIN IN A MOMENT")
	return false


func _on_custom_map_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_custom_map_fetching = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		hud.show_message("CUSTOM MAP // FETCH FAILED (result %d, HTTP %d)" % [result, code])
		return
	var seed_text := "%s:CUSTOM" % GameState.level_seed_text()
	var parse_error := _install_custom_map_png(body, seed_text)
	if not parse_error.is_empty():
		hud.show_message("CUSTOM MAP // %s" % parse_error.to_upper())
		return
	if _remotes != null:
		_remotes.broadcast_snapshot()
	hud.show_message("CUSTOM MAP LOADED // %dx%d" % [facility_view.generator.cols, facility_view.generator.rows])


## Decode, validate and install the transferable representation of a custom
## floor. Used by both the admin HTTP response and a late-join snapshot so
## those paths cannot disagree about size limits or parsing.
func _install_custom_map_png(body: PackedByteArray, seed_text: String) -> String:
	if body.is_empty():
		return "CUSTOM MAP PAYLOAD IS EMPTY"
	if body.size() > CUSTOM_MAP_MAX_BYTES:
		return "CUSTOM MAP EXCEEDS %d KB" % (CUSTOM_MAP_MAX_BYTES / 1024)
	var dimensions := _png_dimensions(body)
	if dimensions == Vector2i.ZERO:
		return "NOT A READABLE PNG"
	var dimension_error := CustomMapParser.dimension_error(dimensions.x, dimensions.y)
	if not dimension_error.is_empty():
		return dimension_error
	var image := Image.new()
	var decode_error := image.load_png_from_buffer(body)
	if decode_error != OK:
		return "NOT A READABLE PNG"
	var parse_error := facility_view.generate_floor_from_custom_map(image, seed_text)
	if not parse_error.is_empty():
		return parse_error
	# Keep the already size-limited, successfully decoded source bytes. Re-
	# encoding could grow beyond the transport limit after the floor had already
	# been replaced, leaving the host with a map it could no longer publish.
	_custom_map_png = body.duplicate()
	_custom_map_seed = seed_text
	_floor_revision += 1
	# A new base floor owns a fresh objective set. Preserve run score/coins but
	# never carry relay progress or sabotage from the floor it replaced.
	GameState.start_floor()
	_after_floor_built()
	return ""


## Read PNG's fixed IHDR dimensions before asking Image to inflate its pixel
## buffer. This turns a compressed-image allocation bomb into a cheap reject.
static func _png_dimensions(body: PackedByteArray) -> Vector2i:
	if body.size() < 24:
		return Vector2i.ZERO
	var signature := [137, 80, 78, 71, 13, 10, 26, 10]
	for index in signature.size():
		if body[index] != signature[index]:
			return Vector2i.ZERO
	if body[12] != 73 or body[13] != 72 or body[14] != 68 or body[15] != 82:
		return Vector2i.ZERO
	var width := (body[16] << 24) | (body[17] << 16) | (body[18] << 8) | body[19]
	var height := (body[20] << 24) | (body[21] << 16) | (body[22] << 8) | body[23]
	return Vector2i(width, height) if width > 0 and height > 0 else Vector2i.ZERO


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
	var blocked_spawn_cells := {spawn_cell: true}
	var seed_text := GameState.level_seed_text()

	# The drawn route hunter, on the relay activation schedule.
	hunter_view = _add_hunter(HunterRoster.pick_for_floor(seed_text,
		GameState.depth, RoomState.difficulty_id()), spawn_pos,
		"%s:HUNTER" % seed_text)

	# Rule-summoned specials are always PRESENT but inert, exactly as in the
	# original — they wake on their own condition (darkness, heat) rather than
	# the relay count, and hunt alongside the route hunter rather than
	# replacing her.
	var extra_index := 0
	for special_id in HunterRoster.SPECIAL_IDS:
		var special_pos := _extra_hunter_spawn(generator, spawn_pos,
			blocked_spawn_cells, extra_index)
		extra_index += 1
		_add_hunter(special_id, special_pos,
			"%s:%s" % [seed_text, special_id.to_upper()])

	# Void hunters are occasional EXTRA pressure, never replacements for the
	# A-Z route identity. Their seeded decision is identical for host and guests.
	if HunterRoster.has_void_incursion(seed_text, GameState.depth):
		var void_id := HunterRoster.void_for_floor(seed_text, GameState.depth)
		var void_pos := _extra_hunter_spawn(generator, spawn_pos,
			blocked_spawn_cells, extra_index)
		_add_hunter(void_id, void_pos, "%s:%s" % [seed_text, void_id.to_upper()])


func _extra_hunter_spawn(generator: FacilityGenerator, origin: Vector2,
		blocked: Dictionary, index: int) -> Vector2:
	var angle := float(index) * 2.399963 + 0.8
	var distance := 2.0 + float(index) * 0.75
	var probe := origin + Vector2(cos(angle), sin(angle)) * distance
	var found := generator.nearest_open_position(probe.x, probe.y,
		GameConfig.HUNTER_RADIUS, blocked)
	var position := Vector2(float(found.get("x", origin.x)),
		float(found.get("y", origin.y)))
	blocked[Vector2i(floori(position.x), floori(position.y))] = true
	return position


func _add_hunter(hunter_id: String, spawn_pos: Vector2, seed_text: String) -> HunterView3D:
	var view := HunterView3D.new()
	view.name = "Hunter_%s" % hunter_id
	view.brain = HunterBrain.new(spawn_pos, seed_text, hunter_id,
		RoomState.difficulty_id())
	view.surface_height_provider = facility_view.surface_height_at
	world.add_child(view)
	view.sync_from_brain()
	hunter_views.append(view)
	return view
