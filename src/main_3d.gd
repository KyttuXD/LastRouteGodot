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
var _custom_map_request: HTTPRequest
## True while a fetch is in flight, so a second admin submission cannot start
## one on top of it. Tracked here rather than read off HTTPRequest itself --
## simpler than trusting an internal client-status API to mean what it sounds
## like it means.
var _custom_map_fetching := false
## Rebuilt each frame on the host and sent as-is; empty on a client, which
## never fills it because it never runs a brain.
var _hunter_report: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The room's seed, not a fresh random one. Every shared thing below is
	# addressed by grid cell, which only names the same object on two machines
	# if both machines generated the same facility -- so this line is what makes
	# the rest of the sync mean anything. Offline it is still a stable seed, so
	# a solo run behaves the same way.
	GameState.start_new_run(RoomState.run_seed())
	observed_depth = GameState.depth
	player.interaction_message.connect(_on_interaction_message)
	player.interaction_veto = _guardian_blocking
	player.hiding_trap_resolver = _ceryth_trap_check
	player.music_box_resolver = _wind_music_box
	player.trigger_static_effect = hud.trigger_static
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
	_remotes.world_event.connect(_apply_world_event)
	_remotes.world_snapshot.connect(_apply_world_snapshot)
	_remotes.snapshot_source = _build_snapshot
	world.add_child(_remotes)
	facility_view.world_changed.connect(_on_world_changed)
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

	if hud.map_is_open():
		hud.update_map(facility_view.generator, player.grid_position(),
			player.facing, _map_marks())
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
		"hidden": player.hidden,
		"hiding_spot": player.hidden_spot,
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
	# Ferryn's scream, collected during the loop below and applied to every
	# OTHER hunter only after every hunter has had her own update() this
	# frame -- applying it inline would let whoever raised it stomp a
	# not-yet-updated sibling, then have that sibling's own update() overwrite
	# it right back a moment later.
	var facility_alerts: Array = []
	for view in hunter_views:
		var captured: bool = view.brain.update(delta, generator, target, GameState.depth, GameState.relays_collected)
		view.sync_from_brain()
		_hunter_report.append({"id": view.name, "at": view.global_position,
			"facing": view.rotation.y, "active": view.brain.active})
		# Anything a gimmick did to the floor. Only the host reaches here, which
		# is what makes it safe to broadcast without a second authority check.
		for event in view.brain.world_events:
			if String(event.get("what", "")) == "facility_alert":
				facility_alerts.append(event)
				continue
			facility_view.apply_event(event)
			_remotes.broadcast_event(event)
			var note := String(event.get("message", ""))
			if not note.is_empty():
				hud.show_message(note)
		view.brain.world_events.clear()
		# Jyvra reaching into a locker. Resolved here rather than in the gimmick
		# because it moves the PLAYER, which the brain has no handle on.
		if view.brain.gimmick is JyvraGimmick and view.brain.gimmick.ejecting:
			player.leave_hiding(view.brain.gimmick.ejected_to, true)
			hud.show_message("JYVRA PULLED YOU OUT OF HIDING")
		if view.brain.gimmick is LoxelleGimmick:
			for toggle in view.brain.gimmick.toggles:
				var cell: Vector2i = toggle["cell"]
				if toggle.has("eject_to"):
					if player.hidden and player.hidden_spot == cell:
						player.leave_hiding(toggle["eject_to"], true)
						hud.show_message("LOXELLE BROKE YOUR COVER")
				else:
					var spot := facility_view.hiding_spot_at(cell)
					if spot:
						spot.set_disabled(bool(toggle["disabled"]))
					_remotes.broadcast_event({"what": "hiding_disabled",
						"cell": cell, "disabled": bool(toggle["disabled"])})
			view.brain.gimmick.toggles.clear()
		# Wynelle's freeze grace is a second way to lose that isn't a grab:
		# if it runs out you die where you stand, with no struggle.
		if view.brain.gimmick is WynelleGimmick and view.brain.gimmick.has_frozen_player():
			capturing_view = view
			_resolve_capture_outcome()
			return
		if captured:
			_trigger_capture(view)
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
		for ally in hunter_views:
			if not ally.brain.active:
				continue
			ally.brain.enter_search_from(player.grid_position(), 1.8)
			ally.sync_from_brain()
		return "%s IS GUARDING THIS // DRAW HER OFF" % name.to_upper()
	return ""


## What the map shows. Every ACTIVE hunter, including the ones the room cannot
## see -- Porcelle is invisible in the world and appears only here, which is the
## whole reason this panel had to become a real map.
func _map_marks() -> Array:
	var marks: Array = []
	for view in hunter_views:
		if not view.brain.active:
			continue
		marks.append({
			"at": view.brain.position,
			"name": String(HunterRoster.get_identity(view.brain.hunter_id)["display_name"]),
			"active": true,
		})
	return marks


## Ceryth's riddle, asked at the moment the player tries to hide in the spot
## she has staked out. Not a veto -- unlike Opalie's, a wrong answer does not
## refuse the interaction, it changes what happens inside it.
func _ceryth_trap_check(cell: Vector2i, flashlight_active: bool) -> Dictionary:
	for view in hunter_views:
		if view.brain.gimmick is CerythGimmick:
			return view.brain.gimmick.resolve_entry(cell, flashlight_active)
	return {}


## Winding Glyra's music box. She is always on the floor once implemented
## (no wake condition, no activation schedule -- see her gimmick), but a
## hunter roll could still draw someone else as the route hunter while she
## sits inert as a special-like fixture; if there is no Glyra on this floor
## at all, there is nothing to wind.
func _wind_music_box() -> String:
	for view in hunter_views:
		if view.brain.gimmick is GlyraGimmick:
			view.brain.gimmick.wind(player.meters)
			return "Music box wound. The room settles."
	return "The box is still. Nothing winds it."


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
		],
		[
			{"label": "CUSTOM MAP URL", "placeholder": "https://.../map.png",
				"on_submit": _load_custom_map},
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


## Something the local player did that the room shares. Sent as-is; the effect
## already happened here.
func _on_world_changed(event: Dictionary) -> void:
	if _remotes != null:
		_remotes.broadcast_event(event)


## The same thing, arriving from someone else.
##
## Not gated on simulates(): a pickup is not a simulation, it is a fact, and the
## peer that reports it is the authority on it. Gating this on the host would
## mean a client's relay took a round trip to disappear.
func _apply_world_event(event: Dictionary) -> void:
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
		_:
			facility_view.apply_event(event)


## What the host tells a peer that joined after the floor started.
func _build_snapshot() -> Dictionary:
	var state := facility_view.shared_state()
	state["depth"] = GameState.depth
	state["relays"] = GameState.relays_collected
	return state


func _apply_world_snapshot(state: Dictionary) -> void:
	var depth := int(state.get("depth", GameState.depth))
	if depth != GameState.depth:
		GameState.depth = depth
		GameState.start_floor()
		_build_floor()
		# Built here rather than left to _process, because the state below has
		# to land on the floor it describes and not on the one being replaced.
		observed_depth = depth
	facility_view.adopt_state(state)
	# adopt_state re-counts the relays it applies, so this is a correction for
	# anything the count could still miss rather than the source of it.
	GameState.relays_collected = maxi(GameState.relays_collected, int(state.get("relays", 0)))
	player.heater_on = _heater_state() == RouteInteractable3D.HeaterState.POWERED
	_update_hud()


func _on_abandoned() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_interaction_message(message: String) -> void:
	hud.show_message(message)


func _build_floor() -> void:
	facility_view.generate_floor(GameState.level_seed_text())
	_after_floor_built()


## The end of a floor build every path shares: sync the relay target to
## whatever actually got placed, put the player on the real start (not
## wherever they stood on the last floor), and give the hunters a fresh spawn.
func _after_floor_built() -> void:
	GameState.relay_target = facility_view.generator.relay_count
	player.position = facility_view.start_world_position()
	player.velocity = Vector3.ZERO
	player.input_frozen = false
	_spawn_hunter()


## Admin-only: fetches a raw PNG by URL and rebuilds the current floor from it
## via CustomMapParser, instead of the next depth's procedural one. Async --
## HTTPRequest is signal-driven, so this kicks the fetch off and the actual
## rebuild happens in _on_custom_map_response() once it lands.
func _load_custom_map(url: String) -> void:
	var trimmed := url.strip_edges()
	if trimmed.is_empty():
		return
	if _custom_map_fetching:
		hud.show_message("CUSTOM MAP // ALREADY FETCHING ONE")
		return
	if _custom_map_request == null:
		_custom_map_request = HTTPRequest.new()
		add_child(_custom_map_request)
		_custom_map_request.request_completed.connect(_on_custom_map_response)
	var error := _custom_map_request.request(trimmed)
	if error != OK:
		hud.show_message("CUSTOM MAP // COULD NOT START REQUEST (%d)" % error)
		return
	_custom_map_fetching = true
	hud.show_message("CUSTOM MAP // FETCHING...")


func _on_custom_map_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_custom_map_fetching = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		hud.show_message("CUSTOM MAP // FETCH FAILED (result %d, HTTP %d)" % [result, code])
		return
	var image := Image.new()
	var decode_error := image.load_png_from_buffer(body)
	if decode_error != OK:
		hud.show_message("CUSTOM MAP // NOT A READABLE PNG")
		return
	var seed_text := "%s:CUSTOM" % GameState.level_seed_text()
	var parse_error := facility_view.generate_floor_from_custom_map(image, seed_text)
	if not parse_error.is_empty():
		hud.show_message("CUSTOM MAP // %s" % parse_error.to_upper())
		return
	_after_floor_built()
	hud.show_message("CUSTOM MAP LOADED // %dx%d" % [facility_view.generator.cols, facility_view.generator.rows])


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
