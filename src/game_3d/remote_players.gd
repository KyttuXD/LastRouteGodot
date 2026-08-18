class_name RemotePlayers
extends Node3D

## ENet replication for the route scene.
##
## Each peer owns its player transform and moment-to-moment player state. The
## host owns hunters and the durable floor state. Remote bodies interpolate
## toward the 20 Hz samples; the host also uses those samples when choosing
## which runner a hunter should pursue.

const MODEL := "res://art/props-3d/characters/player.tscn"
const SEND_HZ := 20.0
const INTERPOLATION_SPEED := 14.0
const REMOTE_STATE_TIMEOUT_USEC := 2_000_000
const SNAPSHOT_RETRY_SECONDS := 0.5
const CAPTURE_PENDING_TIMEOUT_USEC := 15_000_000

var local_player: Node3D
## Scene-specific fields merged into the ordinary controller packet. The fixed
## route needs no overrides; Infinite supplies its durable safe-room status and
## streamed level without forking this transport.
var state_overrides: Callable

var _bodies := {}
var _players := {}
var _positions := {}
var _facings := {}
var _step_distances := {}
## Peer id -> the most recent simulation-facing state plus received_usec.
var _states := {}
## A host-issued capture is kept here independently of the next movement
## packet. That prevents the same hunter from starting a second struggle while
## the reliable capture RPC and the guest's next unreliable state cross paths.
var _pending_captures := {}
## Host-side peer authority proven by the primary backend. Expiry uses the
## monotonic game clock, matching Backend's expiresIn response without trusting
## either player's wall clock.
var _authorized_admin_peers := {}
var _since_send := 0.0
var _snapshot_elapsed := SNAPSHOT_RETRY_SECONDS
var _snapshot_received := false


func _ready() -> void:
	if not RoomState.online:
		return
	if not multiplayer.peer_disconnected.is_connected(_drop):
		multiplayer.peer_disconnected.connect(_drop)
	if not multiplayer.peer_connected.is_connected(_greet):
		multiplayer.peer_connected.connect(_greet)


func _process(delta: float) -> void:
	_interpolate_bodies(delta)
	if not RoomState.online or local_player == null:
		return

	# A route normally starts with every peer already connected in staging, so
	# peer_connected does not fire again after this node exists. Guests request a
	# snapshot themselves and retry across the short scene-change race.
	if not RoomState.is_host and not _snapshot_received:
		_snapshot_elapsed += delta
		if _snapshot_elapsed >= SNAPSHOT_RETRY_SECONDS:
			_snapshot_elapsed = 0.0
			_request_snapshot.rpc_id(1)

	_since_send += delta
	if _since_send < 1.0 / SEND_HZ:
		return
	_since_send = 0.0
	_place.rpc(_local_state())


func _local_state() -> Dictionary:
	var controller := local_player as PlayerController3D
	if controller == null:
		var fallback := {
			"at": local_player.global_position,
			"facing_y": local_player.rotation.y,
			"clip": _local_clip(),
			"position": Vector2(local_player.global_position.x, local_player.global_position.z),
			"depth": GameState.depth,
		}
		return _merge_state_overrides(fallback)
	var state := {
		"at": controller.global_position,
		"facing_y": controller.rotation.y,
		"clip": controller.current_clip(),
		"position": controller.grid_position(),
		"depth": GameState.depth,
		"hidden": controller.hidden,
		"hiding_spot": controller.hidden_spot,
		"in_safe_zone": controller.is_in_safe_zone(),
		"noise": controller.noise,
		"flashlight_on": controller.flashlight_enabled,
		"sprinting": controller.movement_mode == "sprint" and controller.noise > 0.0,
		"facing": controller.facing,
		"lamp_charge": controller.lamp_charge,
		"selected_item": controller.selected_inventory_item(),
		"owned_items": controller.inventory_owned_snapshot(),
		"item_durability": controller.inventory_durability_snapshot(),
		"display_name": RoomState.local_display_name(),
		"player_hue": Settings.player_hue_degrees,
		"admin_skin": Backend.admin_authorized(),
		"in_vent": controller.in_vent,
		"vent_time_in": controller.vent_time_in,
		"pesticide_active": controller.pesticide_timer > 0.0,
		"no_target": controller.admin_no_target,
		"god_mode": controller.admin_god_mode,
		"noclip": controller.admin_noclip,
		"escape_active": GameState.escape_active,
		"capture_immune": GameState.is_capture_immune(),
		"game_over": GameState.game_over,
		"visible": not controller.hidden,
		# Read-only meter values let host-side targeting rules use the same inputs.
		# The host diffs any hunter mutation against these values and returns the
		# delta through a targeted reliable player event.
		"exposure": controller.meters.exposure,
		"noise_meter": controller.meters.noise_meter,
		"temperature": controller.meters.temperature,
		"ambient": controller.meters.ambient,
		"heat_locked": controller.meters.heat_locked,
	}
	return _merge_state_overrides(state)


func _merge_state_overrides(state: Dictionary) -> Dictionary:
	if not state_overrides.is_valid():
		return state
	var additions = state_overrides.call()
	if additions is Dictionary:
		for key in additions:
			state[key] = additions[key]
	return state


func _local_clip() -> String:
	if local_player == null or not local_player.has_method("current_clip"):
		return "idle"
	return String(local_player.call("current_clip"))


## Any peer may publish only its own state: sender id is taken from ENet, never
## from the packet. Invalid transform packets are ignored before they can move a
## body or become a hunter target.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _place(state: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id <= 0 or id == multiplayer.get_unique_id():
		return
	var at = state.get("at")
	var grid = state.get("position")
	if not at is Vector3 or not grid is Vector2:
		return
	var received := state.duplicate(true)
	received["peer_id"] = id
	received["received_usec"] = Time.get_ticks_usec()
	_states[id] = received

	var body: Node3D = _bodies.get(id)
	if body == null:
		var model_path := PlayerController3D.ADMIN_BODY_MODEL_SCENE \
			if bool(state.get("admin_skin", false)) else MODEL
		body = ModelSlot.instantiate(model_path)
		if body == null:
			return
		body.name = "Peer%d" % id
		add_child(body)
		body.global_position = at
		body.rotation.y = float(state.get("facing_y", 0.0))
		_bodies[id] = body
		_players[id] = ModelSlot.find_animation_player(body)
		if not bool(state.get("admin_skin", false)):
			ModelSlot.apply_character_hue(body, float(state.get("player_hue", 0.0)))
		_add_name_tag(body, String(state.get("display_name",
			RoomState.peer_display_name(id))))
		body.set_meta("fade_current", 0.0)
		_step_distances[id] = 0.0
	_positions[id] = at
	_facings[id] = float(state.get("facing_y", body.rotation.y))
	body.visible = bool(state.get("visible", true))
	var clip := String(state.get("clip", "idle"))
	body.set_meta("movement_clip", clip)
	body.set_meta("fade_target", 0.55 if clip == "crouch" else 0.0)
	ModelSlot.play_if_available(_players.get(id), "idle" if clip == "crouch" else clip)


func _interpolate_bodies(delta: float) -> void:
	var weight := clampf(delta * INTERPOLATION_SPEED, 0.0, 1.0)
	for id in _bodies:
		var body: Node3D = _bodies[id]
		if body == null or not _positions.has(id):
			continue
		var previous := body.global_position
		body.global_position = body.global_position.lerp(_positions[id], weight)
		body.rotation.y = lerp_angle(body.rotation.y, float(_facings.get(id, body.rotation.y)), weight)
		var fade := move_toward(float(body.get_meta("fade_current", 0.0)),
			float(body.get_meta("fade_target", 0.0)), delta * 2.8)
		body.set_meta("fade_current", fade)
		ModelSlot.set_character_fade(body, fade)
		_update_remote_footstep(id, body, previous)


func _add_name_tag(body: Node3D, display_name: String) -> void:
	var label := Label3D.new()
	label.name = "PlayerNameTag"
	label.text = display_name.strip_edges().to_upper().substr(0, 32)
	label.position = Vector3(0.0, 2.08, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 24
	label.outline_size = 5
	label.modulate = Color(0.78, 0.92, 0.94, .94)
	body.add_child(label)


func _update_remote_footstep(id: int, body: Node3D, previous: Vector3) -> void:
	if local_player == null or not body.visible:
		return
	var clip := String(body.get_meta("movement_clip", "idle"))
	if clip == "idle":
		_step_distances[id] = 0.0
		return
	_step_distances[id] = float(_step_distances.get(id, 0.0)) \
		+ previous.distance_to(body.global_position)
	var stride := .78 if clip == "sprint" else (1.0 if clip == "crouch" else .68)
	if float(_step_distances[id]) < stride:
		return
	_step_distances[id] = fmod(float(_step_distances[id]), stride)
	var offset := body.global_position - local_player.global_position
	var distance := offset.length()
	if distance > 12.0:
		return
	var local_facing := Vector2(0, 1)
	if local_player is PlayerController3D:
		local_facing = (local_player as PlayerController3D).facing
	var right := Vector2(-local_facing.y, local_facing.x)
	var pan := clampf(Vector2(offset.x, offset.z).dot(right) / 4.5, -1.0, 1.0)
	Sound.remote_player_footstep(clip, pan, .045 * (1.0 - distance / 12.0))


func _drop(id: int) -> void:
	var body: Node3D = _bodies.get(id)
	if body != null:
		body.queue_free()
	_bodies.erase(id)
	_players.erase(id)
	_positions.erase(id)
	_facings.erase(id)
	_step_distances.erase(id)
	_states.erase(id)
	_pending_captures.erase(id)
	_authorized_admin_peers.erase(id)


func authorize_admin_peer(peer_id: int, expires_in: int) -> void:
	if peer_id <= 1 or expires_in <= 0:
		return
	_authorized_admin_peers[peer_id] = Time.get_ticks_msec() + expires_in * 1000


func remote_admin_peer_allowed(peer_id: int) -> bool:
	if Build.remote_guest_tools_allowed():
		return true
	var expires_at := int(_authorized_admin_peers.get(peer_id, 0))
	if expires_at <= Time.get_ticks_msec():
		_authorized_admin_peers.erase(peer_id)
		return false
	return true


## Choose the closest available runner for one hunter. A visible/vulnerable
## runner wins over a hidden or safe runner; hidden/safe states remain as a
## fallback so a gimmick which explicitly reacts to them still receives a
## coherent target when everyone is concealed.
func best_target(origin: Vector2, local_target: Dictionary, depth: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	if int(local_target.get("depth", depth)) == depth:
		candidates.append(local_target)
	var now := Time.get_ticks_usec()
	for id in _states:
		var state: Dictionary = _states[id]
		var pending_since := int(_pending_captures.get(id, 0))
		if pending_since > 0:
			if now - pending_since <= CAPTURE_PENDING_TIMEOUT_USEC:
				continue
			_pending_captures.erase(id)
		if now - int(state.get("received_usec", 0)) > REMOTE_STATE_TIMEOUT_USEC:
			continue
		if int(state.get("depth", -1)) != depth:
			continue
		candidates.append(state)

	var preferred: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	for candidate in candidates:
		var candidate_id := int(candidate.get("peer_id", local_id))
		var candidate_tools := Build.tools_enabled() if candidate_id == local_id \
			else remote_admin_peer_allowed(candidate_id)
		if (candidate_tools and bool(candidate.get("no_target", false))) \
				or bool(candidate.get("game_over", false)) \
				or bool(candidate.get("escape_active", false)) \
				or bool(candidate.get("capture_immune", false)):
			continue
		fallback.append(candidate)
		if not bool(candidate.get("hidden", false)) \
				and not bool(candidate.get("in_safe_zone", false)):
			preferred.append(candidate)
	var pool := preferred if not preferred.is_empty() else fallback
	if pool.is_empty():
		return {}
	var chosen: Dictionary = pool[0]
	var best_distance := origin.distance_squared_to(chosen.get("position", origin))
	for candidate in pool.slice(1):
		var distance := origin.distance_squared_to(candidate.get("position", origin))
		if distance < best_distance:
			chosen = candidate
			best_distance = distance
	return chosen


## Fresh player states across every streamed level. Host-owned endless-route
## simulation uses this to keep authority windows around split-up runners and
## to guide hunters toward a stair when their nearest target changed floors.
func target_states(local_target: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not local_target.is_empty():
		result.append(local_target)
	var now := Time.get_ticks_usec()
	for id in _states:
		var state: Dictionary = _states[id]
		if now - int(state.get("received_usec", 0)) > REMOTE_STATE_TIMEOUT_USEC:
			continue
		result.append(state.duplicate(true))
	return result


func stream_centers() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var now := Time.get_ticks_usec()
	for id in _states:
		var state: Dictionary = _states[id]
		if now - int(state.get("received_usec", 0)) > REMOTE_STATE_TIMEOUT_USEC:
			continue
		var position = state.get("position")
		if not position is Vector2:
			continue
		var level := -int(state.get("depth", 0))
		result.append(Vector3i(
			floori(position.x / StreamedRouteGenerator.CHUNK_SIZE), level,
			floori(position.y / StreamedRouteGenerator.CHUNK_SIZE)))
	return result


## Hunters, from the host only.
signal hunters_received(data: Array)


func broadcast_hunters(data: Array) -> void:
	if RoomState.online and RoomState.is_host:
		_hunters.rpc(data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _hunters(data: Array) -> void:
	hunters_received.emit(data)


func simulates() -> bool:
	return not RoomState.online or RoomState.is_host


## Most recent targeting packet for one specific owner. Used only by the host
## to validate an interaction request and apply its result to the same runner.
func state_for_peer(peer_id: int, local_target: Dictionary, depth: int) -> Dictionary:
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	if peer_id == local_id:
		return local_target
	var state: Dictionary = _states.get(peer_id, {})
	if state.is_empty() or int(state.get("depth", -1)) != depth:
		return {}
	if Time.get_ticks_usec() - int(state.get("received_usec", 0)) > REMOTE_STATE_TIMEOUT_USEC:
		return {}
	return state.duplicate(true)


## Durable shared-world events are relayed by the host. A guest keeps the local
## interaction responsive, submits the fact to peer 1, and receives the same
## idempotent event back with every other guest.
signal world_event(event: Dictionary)
signal world_event_requested(peer_id: int, event: Dictionary)
signal world_snapshot(state: Dictionary)
signal interaction_requested(peer_id: int, event: Dictionary)
var snapshot_source: Callable


func broadcast_event(event: Dictionary) -> void:
	if not RoomState.online:
		return
	if RoomState.is_host:
		relay_world_event(event)
	else:
		_submit_event.rpc_id(1, event)


@rpc("any_peer", "call_remote", "reliable")
func _submit_event(event: Dictionary) -> void:
	if not RoomState.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender > 1:
		world_event_requested.emit(sender, event)


func relay_world_event(event: Dictionary) -> void:
	if RoomState.online and RoomState.is_host:
		_event.rpc(_canonical_world_event(event))


@rpc("authority", "call_remote", "reliable")
func _event(event: Dictionary) -> void:
	world_event.emit(event)


## Attach authoritative counters after the host has applied an event. This
## corrects simultaneous pickup prediction (especially shared coins) instead
## of letting two guests permanently disagree about who won the same cell.
func _canonical_world_event(event: Dictionary) -> Dictionary:
	var canonical := event.duplicate(true)
	canonical["relays"] = GameState.relays_collected
	canonical["relays_sabotaged"] = GameState.relays_sabotaged
	canonical["coins"] = GameState.coins
	canonical["score"] = GameState.score
	canonical["depth"] = GameState.depth
	return canonical


## Guest-owned input which needs host-owned hunter state. The request names an
## intent only; main_3d validates range/state and decides the actual result.
func request_interaction(event: Dictionary) -> void:
	var request := event.duplicate(true)
	var what := String(request.get("what", ""))
	if what in ["admin_auth", "admin_custom_map", "admin_world"]:
		request["admin_ticket"] = Backend.admin_ticket_for_room(RoomState.code)
	if not RoomState.online or RoomState.is_host:
		interaction_requested.emit(multiplayer.get_unique_id() if RoomState.online else 1,
			request)
	else:
		_request_interaction.rpc_id(1, request)


@rpc("any_peer", "call_remote", "reliable")
func _request_interaction(event: Dictionary) -> void:
	if not RoomState.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var what := String(event.get("what", ""))
	if sender <= 1 or not ["music_box", "ceryth_answer", "guardian_ping",
			"vent_used", "zephyra_trade", "admin_auth", "admin_custom_map",
			"admin_world", "stream_pickup", "stream_safe_repair",
			"stream_checkpoint"].has(what):
		return
	var accepted: Dictionary
	if what == "admin_auth":
		accepted = {"what": what,
			"admin_ticket": _clean_admin_ticket(event.get("admin_ticket", ""))}
	elif what == "admin_custom_map":
		var url := String(event.get("url", "")).strip_edges()
		if url.is_empty() or url.length() > 2048 or not (url.begins_with("https://") \
				or url.begins_with("http://")):
			return
		accepted = {"what": what, "url": url,
			"admin_ticket": _clean_admin_ticket(event.get("admin_ticket", ""))}
	elif what == "admin_world":
		var action := String(event.get("action", ""))
		if not ["grant_relay", "all_relays", "rebuild", "descend"].has(action):
			return
		accepted = {"what": what, "action": action,
			"admin_ticket": _clean_admin_ticket(event.get("admin_ticket", ""))}
	else:
		accepted = event.duplicate(true)
	accepted["peer_id"] = sender
	interaction_requested.emit(sender, accepted)


static func _clean_admin_ticket(value) -> String:
	var ticket := String(value)
	if ticket.length() != 43:
		return ""
	for character in ticket:
		if not "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return ""
	return ticket


func _greet(id: int) -> void:
	if not RoomState.is_host or not snapshot_source.is_valid():
		return
	_snapshot.rpc_id(id, snapshot_source.call())


## A host-side floor replacement (currently the debug custom-map loader) must
## rebuild already-connected guests too, not only peers which join afterward.
func broadcast_snapshot() -> void:
	if RoomState.online and RoomState.is_host and snapshot_source.is_valid():
		_snapshot.rpc(snapshot_source.call())


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if not RoomState.is_host or not snapshot_source.is_valid():
		return
	var id := multiplayer.get_remote_sender_id()
	if id > 1:
		_snapshot.rpc_id(id, snapshot_source.call())


@rpc("authority", "call_remote", "reliable")
func _snapshot(state: Dictionary) -> void:
	world_snapshot.emit(state)


## The route scene confirms only after it has rebuilt the authoritative floor
## and adopted every durable mutation. A malformed/incomplete custom-map
## snapshot therefore keeps retrying instead of unlocking the guest on the
## wrong building merely because an RPC packet arrived.
func confirm_snapshot_applied() -> void:
	_snapshot_received = true
	_snapshot_elapsed = 0.0


func awaiting_snapshot() -> bool:
	return RoomState.online and not RoomState.is_host and not _snapshot_received


## Targeted effects (capture, stun, forced hiding exit) are decided by the
## host's hunter simulation and resolved by the affected player's own scene.
signal player_event(event: Dictionary)
signal hunter_event(event: Dictionary)


func send_player_event(peer_id: int, event: Dictionary) -> void:
	if not simulates():
		return
	if not RoomState.online or peer_id == multiplayer.get_unique_id():
		player_event.emit(event)
	else:
		if String(event.get("what", "")) == "capture":
			_pending_captures[peer_id] = Time.get_ticks_usec()
		_player_event.rpc_id(peer_id, event)


@rpc("authority", "call_remote", "reliable")
func _player_event(event: Dictionary) -> void:
	player_event.emit(event)


## A guest reports the result of a local escape struggle so the host can stun
## the authoritative hunter or release the capture gate when that runner dies.
func submit_hunter_event(event: Dictionary) -> void:
	if not RoomState.online or RoomState.is_host:
		hunter_event.emit(event)
	else:
		_submit_hunter_event.rpc_id(1, event)


@rpc("any_peer", "call_remote", "reliable")
func _submit_hunter_event(event: Dictionary) -> void:
	if not RoomState.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var what := String(event.get("what", ""))
	if sender <= 1:
		return
	# A taser packet is only an intent. Position, facing, target, cooldown and
	# line of sight all come from host-owned state in main_3d.
	if what == "taser":
		hunter_event.emit({"what": "taser", "peer_id": sender})
		return
	if not ["escaped", "caught", "capture_blocked"].has(what):
		return
	# Only a peer which the host actually captured may resolve that capture.
	# This also turns the report into a one-shot message.
	if not _pending_captures.has(sender):
		return
	_pending_captures.erase(sender)
	var received := event.duplicate(true)
	received["peer_id"] = sender
	hunter_event.emit(received)


func count() -> int:
	return _bodies.size()
