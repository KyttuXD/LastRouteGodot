class_name RemotePlayers
extends Node3D

## ENet replication for the route scene.
##
## Each peer owns its player transform and moment-to-moment player state. The
## host owns hunters and the durable floor state. Remote bodies interpolate
## toward the 20 Hz samples; the host also uses those samples when choosing
## which runner a hunter should pursue.

const MODEL := PlayerModels.SCENE
const REMOTE_HELD_MODELS := {
	"flashlight": "res://art/props-3d/interactables/flashlight_item.glb",
	"taser": "res://art/props-3d/interactables/taser_item.glb",
	"lockpick": "res://art/props-3d/interactables/lockpick_set.glb",
	"crowbar": "res://art/props-3d/interactables/crowbar.glb",
	"rescue_axe": "res://art/props-3d/interactables/rescue_axe.glb",
	"battery": "res://art/props-3d/interactables/battery.glb",
}
const REMOTE_HELD_SCALES := {
	"flashlight": .34, "taser": .32, "lockpick": .29,
	"crowbar": .30, "rescue_axe": .29, "battery": .40,
}
const REMOTE_BEAM_HAND_OFFSET := .38
const SEND_HZ := 20.0
const INTERPOLATION_SPEED := 14.0
const REMOTE_STATE_TIMEOUT_USEC := 2_000_000
const SNAPSHOT_RETRY_SECONDS := 0.5
const CAPTURE_PENDING_TIMEOUT_USEC := 15_000_000
const MAX_CHAT_LENGTH := 80   # spoken aloud (text to speech): short lines
const FLOOR_EXIT_MARK_TIMEOUT_USEC := 20_000_000

var local_player: Node3D
## Scene-specific fields merged into the ordinary controller packet. The fixed
## route needs no overrides; Infinite supplies its durable safe-room status and
## streamed level without forking this transport.
var state_overrides: Callable

var _bodies := {}
## id -> the skin hash that body shows (or is waiting for); peers' skins live in PlayerSkin's memory cache only.
var _peer_skin := {}
var _peer_slim := {}   # id -> whether that body has the slim (Alex) arms
var _players := {}
var _positions := {}
var _facings := {}
var _step_distances := {}
var _remote_flashlights := {}
var _remote_hand_anchors := {}
var _remote_held_items := {}
var _remote_held_item_ids := {}
var _remote_swing_seq := {}
var _remote_swing_tweens := {}
## VR peers (VRPoseSync): the latest received head/hand pose and the smoothed one drawn on their body.
var _vr_targets := {}
var _vr_current := {}
## The local VR runner's standing head height (running maximum, slowly relaxing), for real-life crouch.
var _vr_standing_height := 0.0
## Peer id -> the most recent simulation-facing state plus received_usec.
var _states := {}
var _floor_exit_marks := {}
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

signal chat_received(peer_id: int, display_name: String, message: String)
## Every chat line with its context: {text, channel ("team" | "nearby"), preset, ping, at (map position), world (Vector3),
## depth, system}. chat_received still fires for plain-text listeners.
signal chat_message(peer_id: int, display_name: String, payload: Dictionary)

const CHAT_CHANNELS := ["team", "nearby"]
## Moderation, enforced by the host for every sender (and locally): at most CHAT_RATE_MAX lines (quick-chat pings
## included) per CHAT_RATE_WINDOW_MS, then a CHAT_COOLDOWN_MS cooldown; one map ping per PING_MIN_INTERVAL_MS; an exact or
## near-duplicate of a line sent in the last DUPLICATE_WINDOW_MS is dropped; owner/admin room mutes drop everything.
const CHAT_RATE_WINDOW_MS := 10000
const CHAT_RATE_MAX := 3
const CHAT_COOLDOWN_MS := 5000
const PING_MIN_INTERVAL_MS := 2000
const DUPLICATE_WINDOW_MS := 20000
var _chat_times := {}
var _ping_times := {}
var _cooldown_until := {}
var _recent_lines := {}
## Host: peers muted for the whole room by the owner/admin tools (their lines are dropped before relay).
var room_muted := {}

## Host anti-cheat (docs/ANTI_CHEAT.md): sanity-checks every guest sample and rate-limits interaction requests.
var guard := GuestGuard.new()
## Emitted on the host when a guest's sample was corrected (and when it was kicked).
signal guest_violation(peer_id: int, reason: String, strikes: int, kicked: bool)
## Host events that move the guest a long way; the guard lets the next jump through (GuestGuard.allow_jump).
const HOST_MOVES := ["revive", "axe_rescue", "hide_found"]
const INTERACTION_RATE_WINDOW_MS := 1000
const INTERACTION_RATE_MAX := 8
var _interaction_times := {}
## Troll mode (docs/ANTI_CHEAT.md): guests the host has caught cheating this room, or the server says are flagged /
## owner-trolled. Hunters take only them while they are on the floor; the guest's own client adds the scares.
var troll_peers := {}
const PEER_LOOKUP_SECONDS := 30.0
var _lookup_elapsed := PEER_LOOKUP_SECONDS - 2.0
var _flag_noticed := {}
var _send_seq := 0


func _ready() -> void:
	# After the peers' animation players, so VR head and arm poses are drawn over the walk/idle clips.
	process_priority = 50
	if not RoomState.online:
		return
	if not multiplayer.peer_disconnected.is_connected(_drop):
		multiplayer.peer_disconnected.connect(_drop)
	if not multiplayer.peer_connected.is_connected(_greet):
		multiplayer.peer_connected.connect(_greet)
	if RoomState.is_host:
		Backend.moderation.peers_looked_up.connect(_on_peers_looked_up)
	else:
		Backend.moderation.report_integrity("join")


func send_chat(text: String, channel: String = "team") -> void:
	send_chat_payload({"text": text, "channel": channel})


func _send_chat_legacy(text: String) -> void:
	var message := _sanitize_chat(text)
	if message.is_empty():
		return
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	if not RoomState.online:
		chat_received.emit(local_id, RoomState.local_display_name(), message)
	elif RoomState.is_host:
		_deliver_chat(local_id, RoomState.local_display_name(), message)
	else:
		_submit_chat.rpc_id(1, message)


@rpc("any_peer", "call_remote", "reliable")
func _submit_chat(text: String) -> void:
	if not RoomState.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var message := _sanitize_chat(text)
	if sender <= 1 or message.is_empty():
		return
	_deliver_chat(sender, RoomState.peer_display_name(sender), message)


func _deliver_chat(peer_id: int, display_name: String, message: String) -> void:
	chat_received.emit(peer_id, display_name, message)
	if RoomState.online and RoomState.is_host:
		_chat.rpc(peer_id, display_name, message)


@rpc("authority", "call_remote", "reliable")
func _chat(peer_id: int, display_name: String, message: String) -> void:
	var clean := _sanitize_chat(message)
	if clean.is_empty():
		return
	chat_received.emit(peer_id, display_name.strip_edges().substr(0, 32), clean)


## Sends a chat line or quick-chat preset with the sender's position (for NEARBY filtering and map pings).
func send_chat_payload(payload: Dictionary) -> bool:
	var local_id := multiplayer.get_unique_id() if RoomState.online else 1
	var clean := sanitize_payload(payload, local_id == 1 and bool(payload.get("system", false)))
	var state := _local_state() if local_player != null else {}
	clean["at"] = state.get("position", Vector2.ZERO)
	clean["world"] = local_player.global_position if local_player != null else Vector3.ZERO
	clean["depth"] = GameState.depth
	if String(clean["text"]).is_empty() or not accept_line(local_id, clean):
		return false
	if not RoomState.online:
		_emit_payload(local_id, RoomState.local_display_name(), clean)
	elif RoomState.is_host:
		_deliver_payload(local_id, RoomState.local_display_name(), clean)
	else:
		_submit_chat_payload.rpc_id(1, clean)
	return true


## Host only: a system line (owner/admin notices) to everyone.
func send_system(text: String) -> void:
	if RoomState.online and not RoomState.is_host:
		return
	send_chat_payload({"text": text, "system": true})


@rpc("any_peer", "call_remote", "reliable")
func _submit_chat_payload(payload: Dictionary) -> void:
	if not RoomState.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var clean := sanitize_payload(payload, false)   # guests never send system lines
	if sender <= 1 or String(clean["text"]).is_empty() or not accept_line(sender, clean):
		return
	_deliver_payload(sender, RoomState.peer_display_name(sender), clean)


func _deliver_payload(peer_id: int, display_name: String, payload: Dictionary) -> void:
	_emit_payload(peer_id, display_name, payload)
	if RoomState.online and RoomState.is_host:
		_chat_payload.rpc(peer_id, display_name, payload)


@rpc("authority", "call_remote", "reliable")
func _chat_payload(peer_id: int, display_name: String, payload: Dictionary) -> void:
	var clean := sanitize_payload(payload, bool(payload.get("system", false)))
	if String(clean["text"]).is_empty():
		return
	_emit_payload(peer_id, display_name.strip_edges().substr(0, 32), clean)


func _emit_payload(peer_id: int, display_name: String, payload: Dictionary) -> void:
	chat_message.emit(peer_id, display_name, payload)
	if not bool(payload.get("system", false)):
		chat_received.emit(peer_id, display_name, String(payload["text"]))


## Only known fields with bounded values survive; a peer can never mark its own line as a system message.
static func sanitize_payload(payload: Dictionary, allow_system: bool) -> Dictionary:
	var channel := String(payload.get("channel", "team"))
	var at = payload.get("at", Vector2.ZERO)
	var world = payload.get("world", Vector3.ZERO)
	return {
		"text": _sanitize_chat(String(payload.get("text", ""))),
		"channel": channel if CHAT_CHANNELS.has(channel) else "team",
		"preset": String(payload.get("preset", "")).substr(0, 24),
		"ping": bool(payload.get("ping", false)),
		"at": at if at is Vector2 else Vector2.ZERO,
		"world": world if world is Vector3 else Vector3.ZERO,
		"depth": int(payload.get("depth", 0)),
		"system": allow_system and bool(payload.get("system", false)),
		# a quick-chat ping aimed at something else than the sender (HUNTER! at the aimed hunter)
		"target": payload.get("target") if payload.get("target") is Vector2 else null,
	}


## At most CHAT_RATE_MAX lines per CHAT_RATE_WINDOW_MS per peer, and one map ping per PING_MIN_INTERVAL_MS.
func rate_ok(peer_id: int, ping: bool, now_ms: int = -1) -> bool:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if now < int(_cooldown_until.get(peer_id, 0)):
		return false
	var times: Array = (_chat_times.get(peer_id, []) as Array).filter(func(t: int) -> bool: return now - t < CHAT_RATE_WINDOW_MS)
	if times.size() >= CHAT_RATE_MAX:
		_chat_times[peer_id] = times
		_cooldown_until[peer_id] = now + CHAT_COOLDOWN_MS
		return false
	if ping and now - int(_ping_times.get(peer_id, -PING_MIN_INTERVAL_MS)) < PING_MIN_INTERVAL_MS:
		return false
	times.append(now)
	_chat_times[peer_id] = times
	if ping:
		_ping_times[peer_id] = now
	return true


static func _sanitize_chat(text: String) -> String:
	return collapse_repeats(text.replace("\r", " ").replace("\n", " ").strip_edges()).substr(0, MAX_CHAT_LENGTH)


## "aaaaaaa" -> "aaa", "!!!!!!" -> "!!!": any character repeated more than 3 times in a row is cut to 3.
static func collapse_repeats(text: String) -> String:
	var out := ""
	var run := 0
	for index in text.length():
		run = run + 1 if index > 0 and text[index] == text[index - 1] else 1
		if run <= 3:
			out += text[index]
	return out


## Lines that are the same once case, spacing, punctuation and repeats are ignored count as duplicates.
static func line_key(text: String) -> String:
	var key := ""
	for character in collapse_repeats(text.to_lower()):
		if character.is_valid_identifier() or "0123456789".contains(character):
			key += character
	return key


## True (and remembered) when `text` repeats a line this peer sent in the last DUPLICATE_WINDOW_MS.
func is_duplicate(peer_id: int, text: String, now_ms: int = -1) -> bool:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var key := line_key(text)
	var recent: Array = (_recent_lines.get(peer_id, []) as Array).filter(func(entry: Array) -> bool: return now - int(entry[1]) < DUPLICATE_WINDOW_MS)
	for entry in recent:
		var other := String(entry[0])
		if other == key or (key.length() >= 6 and (other.begins_with(key) or key.begins_with(other))
				and absi(other.length() - key.length()) <= 3):
			_recent_lines[peer_id] = recent
			return true
	recent.append([key, now])
	_recent_lines[peer_id] = recent
	return false


## Host-side moderation in one place: room mute, rate limit (pings included), duplicates.
func accept_line(peer_id: int, payload: Dictionary, now_ms: int = -1) -> bool:
	if room_muted.has(peer_id):
		return false
	if bool(payload.get("system", false)):
		return true   # host/owner notices are not rate limited
	if is_duplicate(peer_id, String(payload.get("text", "")), now_ms):
		return false
	return rate_ok(peer_id, bool(payload.get("ping", false)), now_ms)


## Owner/admin tools (host): mute a guest for the whole room, or remove them.
func set_room_muted(peer_id: int, muted: bool) -> void:
	if muted:
		room_muted[peer_id] = true
	else:
		room_muted.erase(peer_id)


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

	if RoomState.is_host:
		_lookup_elapsed += delta
		if _lookup_elapsed >= PEER_LOOKUP_SECONDS and not _states.is_empty():
			_lookup_elapsed = 0.0
			_lookup_peers()
	_since_send += delta
	if _since_send < 1.0 / SEND_HZ:
		return
	_since_send = 0.0
	var state := _local_state()
	_send_seq += 1
	state["seq"] = _send_seq   # lets the host drop duplicated / reordered samples (GuestGuard)
	_send_to_live(_place, [state])


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
		"hiding_style": controller.hiding_style(),
		"asleep": controller.asleep,
		"in_safe_zone": controller.is_in_safe_zone(),
		"noise": controller.noise,
		# Publish the actual rendered beam, including held-slot, charge and
		# hunter-induced flicker state. A raw toggle made peers glow even when the
		# local flashlight had been put away or temporarily cut out.
		"flashlight_on": controller.flashlight != null and controller.flashlight.visible,
		"aim_direction": controller.equipment_aim_direction(),
		"sprinting": controller.movement_mode == "sprint" and controller.noise > 0.0,
		"facing": controller.facing,
		"lamp_charge": controller.lamp_charge,
		"selected_item": controller.selected_inventory_item(),
		"tool_swing_seq": controller.tool_swing_seq,
		"tool_swing_item": controller.tool_swing_item,
		"tool_swing_hit": controller.tool_swing_hit,
		"selected_inventory_slot": controller.selected_inventory_slot,
		"owned_items": controller.inventory_owned_snapshot(),
		"item_durability": controller.inventory_durability_snapshot(),
		"inventory_order": controller.inventory_order_snapshot(),
		"inventory_slot_durability": controller.inventory_slot_durability_snapshot(),
		"inventory_free_slots": controller.inventory_order_snapshot().count(""),
		"inventory_capacity": controller.inventory_capacity(),
		"equipped_backpack": controller.equipped_backpack,
		"display_name": RoomState.local_display_name(),
		"account": Backend.account_username if Backend.signed_in() else "",
		"device": Backend.moderation.device_id(),
		"player_hue": Settings.player_hue_degrees,
		"player_skin": "mannequin",
		"skin": _own_skin_hash(),
		"skin_copy": Settings.skin_copyable,
		"skin_slim": Settings.effective_slim(),
		"in_vent": controller.in_vent,
		"vent_time_in": controller.vent_time_in,
		"pesticide_active": controller.pesticide_timer > 0.0,
		"no_target": controller.admin_no_target,
		"god_mode": controller.admin_god_mode,
		"noclip": controller.admin_noclip,
		"escape_active": GameState.escape_active,
		"capture_immune": GameState.is_capture_immune(),
		"game_over": GameState.game_over or controller.spectator_mode,
		"spectating": controller.spectator_mode,
		"visible": not controller.hidden and not controller.spectator_mode,
		# Read-only meter values let host-side targeting rules use the same inputs.
		# The host diffs any hunter mutation against these values and returns the
		# delta through a targeted reliable player event.
		"exposure": controller.meters.exposure,
		"noise_meter": controller.meters.noise_meter,
		"temperature": controller.meters.temperature,
		"ambient": controller.meters.ambient,
		"heat_locked": controller.meters.heat_locked,
	}
	if controller.xr_active:
		var head_height := controller.xr_camera.global_position.y - controller.global_position.y
		_vr_standing_height = maxf(head_height, _vr_standing_height - 0.002)
		var packet := VRPoseSync.local_pose(controller, controller.xr_camera, controller.xr_left, controller.xr_right,
			_vr_standing_height)
		state["vr"] = packet
		if packet.decode_u8(0) & VRPoseSync.FLAG_CROUCH and String(state["clip"]) in ["idle", "walk"]:
			state["clip"] = "crouch"   # crouching in real life lowers the body for everyone else
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
func _visible_from_state(state: Dictionary, fallback: bool = true) -> bool:
	# `hidden` is the authoritative gameplay signal for the route. A stale/blank
	# `visible: false` flag can silently hide admin and co-op peers forever, so
	# treat a false visibility hint as stale unless the packet explicitly says the
	# runner is hidden. This keeps remote bodies visible during sync races and
	# backend propagation while still honoring real hide-state transitions.
	var hidden = state.get("hidden")
	if hidden is bool:
		return not hidden
	var raw = state.get("visible", fallback)
	if raw is bool:
		return raw if raw else fallback
	if raw is int:
		return raw > 0 if raw > 0 else fallback
	if raw is float:
		return raw > 0.0 if raw > 0.0 else fallback
	return fallback


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
	if RoomState.is_host and not _guard_sample(id, received):
		return
	at = received["at"]
	received["peer_id"] = id
	received["received_usec"] = Time.get_ticks_usec()
	var previous: Dictionary = _states.get(id, {})
	var previous_depth := int(previous.get("depth", 0))
	var next_depth := int(received.get("depth", previous_depth))
	var previous_position = previous.get("position")
	if not previous.is_empty() and previous_position is Vector2 \
			and previous_depth != next_depth:
		_floor_exit_marks[id] = {
			"at": previous_position,
			"depth": previous_depth,
			"direction": "up" if next_depth > previous_depth else "down",
			"name": String(received.get("display_name",
				RoomState.peer_display_name(id))),
			"received_usec": int(received["received_usec"]),
		}
	elif next_depth == previous_depth:
		_floor_exit_marks.erase(id)
	_states[id] = received

	var body: Node3D = _bodies.get(id)
	if body == null:
		body = ModelSlot.instantiate(MODEL)
		if body == null:
			return
		body.name = "Peer%d" % id
		body.scale = Vector3.ONE * PlayerModels.SCALE   # the name tag above her scales down with her
		add_child(body)
		body.global_position = at
		body.rotation.y = float(state.get("facing_y", 0.0))
		_bodies[id] = body
		_players[id] = ModelSlot.find_animation_player(body)
		ModelSlot.apply_character_hue(body, float(state.get("player_hue", 0.0)))
		_apply_peer_skin(id, body, String(state.get("skin", "")), bool(state.get("skin_slim", false)))
		_add_name_tag(body, String(state.get("display_name",
			RoomState.peer_display_name(id))))
		body.set_meta("fade_current", 0.0)
		_step_distances[id] = 0.0
		_attach_remote_flashlight(id, body)
	_positions[id] = at
	if String(state.get("skin", "")) != String(_peer_skin.get(id, "")) or bool(state.get("skin_slim", false)) != bool(_peer_slim.get(id, false)):
		_apply_peer_skin(id, body, String(state.get("skin", "")), bool(state.get("skin_slim", false)))
	_facings[id] = float(state.get("facing_y", body.rotation.y))
	var vr_pose := VRPoseSync.decode(state.get("vr"))
	if vr_pose.is_empty():
		_vr_targets.erase(id)
		_vr_current.erase(id)
	else:
		_vr_targets[id] = vr_pose
		_facings[id] = float(_facings[id]) + VRPoseSync.body_follow(vr_pose)
	var clip := String(state.get("clip", "idle"))
	# A runner going into hiding stays visible while their body slides into the spot (the local camera move,
	# PlayerController3D.HIDE_MOVE_SECONDS), crouched for a bed, then disappears.
	var shown := _visible_from_state(state, true)
	if not shown:
		var now := Time.get_ticks_usec()
		if not body.has_meta("hide_started_usec"):
			body.set_meta("hide_started_usec", now if body.visible else 0)
		if now - int(body.get_meta("hide_started_usec")) < int(PlayerController3D.HIDE_MOVE_SECONDS * 1_000_000.0):
			shown = true
			if String(state.get("hiding_style", "")) == "bed":
				clip = "crouch"
	elif body.has_meta("hide_started_usec"):
		body.remove_meta("hide_started_usec")
	body.visible = shown
	_sync_remote_equipment(id, body, state)
	_sync_sleep_tag(body, bool(state.get("asleep", false)))
	body.set_meta("movement_clip", clip)
	body.set_meta("fade_target", 0.55 if clip == "crouch" else 0.0)
	ModelSlot.play_if_available(_players.get(id), "idle" if clip == "crouch" else clip)


## A sleeping teammate shows "z Z" over their head (docs/REST_AND_SLEEP.md).
func _sync_sleep_tag(body: Node3D, asleep: bool) -> void:
	var tag := body.get_node_or_null("SleepTag") as Label3D
	if tag == null:
		if not asleep:
			return
		tag = Label3D.new()
		tag.name = "SleepTag"
		tag.text = "z Z"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 48
		tag.modulate = Color(.75, .85, 1.0)
		tag.position = Vector3(0, 2.25, 0)
		body.add_child(tag)
	tag.visible = asleep


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
		if _vr_targets.has(id):
			_vr_current[id] = VRPoseSync.blend(_vr_current.get(id, {}), _vr_targets[id], weight)
			VRPoseSync.apply(body, _vr_current[id])
		_update_remote_equipment_pose(id, body)
		_update_remote_footstep(id, body, previous)


const NAME_TAG_HEIGHT := 1.92
## One colour per teammate, stable for a peer id, shared by the 3D nametag and the minimap / full-map markers.
const PEER_COLOURS := [Color("4fd1ff"), Color("ff8a3d"), Color("7ee26b"), Color("ff5fb4"), Color("ffd84a"), Color("a98bff"),
	Color("3fe0c0"), Color("ff6b6b")]


static func peer_colour(peer_id: int) -> Color:
	return PEER_COLOURS[posmod(peer_id * 7 + 3, PEER_COLOURS.size())]


func _add_name_tag(body: Node3D, display_name: String) -> void:
	var label := Label3D.new()
	label.name = "PlayerNameTag"
	label.text = display_name.strip_edges().to_upper().substr(0, 32)
	# just over a 1.60 m runner's head (it floated half a metre above after the scale change)
	label.position = Vector3(0.0, NAME_TAG_HEIGHT, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 24
	label.outline_size = 5
	label.modulate = Color(peer_colour(int(String(body.name).to_int())).lightened(.35), .96)
	body.add_child(label)


func _attach_remote_flashlight(id: int, body: Node3D) -> SpotLight3D:
	# All authored equipment shares the animated right-hand anchor. The selected
	# model is swapped only when the replicated slot changes, never every packet.
	var hand := body.find_child("R-Attachment", true, false) as Node3D
	if hand == null:
		var prop := body.find_child("R-HandProp", true, false) as Node3D
		if prop != null:
			# the blocky rig's hand prop has no tilt (Y up, -Z forward): turn it into the R-Attachment convention
			# (local +Y forward) that the anchor below expects
			hand = Node3D.new()
			hand.name = "HandPropFrame"
			hand.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
			prop.add_child(hand)
	if hand == null:
		hand = body
	var anchor := Node3D.new()
	anchor.name = "PeerHeldItemAnchor"
	# R-Attachment is already authored at -90 degrees around X: its local +Y
	# points along the avatar's forward axis. Applying that conversion twice
	# made long tools point at the floor and disappear inside the player.
	anchor.rotation = Vector3(0.0, 0.0, deg_to_rad(-8.0))
	anchor.position = Vector3(0.0, -.02, -.08)
	hand.add_child(anchor)
	_remote_hand_anchors[id] = anchor

	var light := SpotLight3D.new()
	light.name = "PeerFlashlight"
	# Top-level keeps interpolation/animation from rotating the light a second
	# time after its world-space aim pose is resolved below. It remains a child
	# so deleting the peer body still deletes the light.
	light.top_level = true
	light.light_color = Color.WHITE
	light.light_energy = 7.5
	light.spot_range = PlayerController3D.FLASHLIGHT_MAX_RANGE
	light.spot_angle = 30.0
	light.spot_angle_attenuation = 1.4
	light.shadow_enabled = true
	light.shadow_bias = .3
	light.shadow_normal_bias = 1.0
	light.shadow_reverse_cull_face = true
	light.visible = false
	body.add_child(light)
	_remote_flashlights[id] = light
	return light


func _sync_remote_equipment(id: int, body: Node3D, state: Dictionary) -> void:
	var light := _remote_flashlights.get(id) as SpotLight3D
	if light == null:
		light = _attach_remote_flashlight(id, body)
	var selected := String(state.get("selected_item", ""))
	if not REMOTE_HELD_MODELS.has(selected):
		selected = ""
	_sync_remote_held_item(id, body, selected)
	_sync_remote_swing(id, body, state)
	var flashlight_held := selected == "flashlight" \
		and float(state.get("lamp_charge", 0.0)) > 0.0
	light.visible = body.visible and flashlight_held \
		and bool(state.get("flashlight_on", false))
	_update_remote_equipment_pose(id, body, state)


## Plays one swing on the remote hand anchor per increment of the replicated counter (the first packet only adopts it, so joining mid-game
## never replays an old swing), and the thud when the swing connected, quieter with distance.
func _sync_remote_swing(id: int, body: Node3D, state: Dictionary) -> void:
	var seq := int(state.get("tool_swing_seq", 0))
	if not _remote_swing_seq.has(id):
		_remote_swing_seq[id] = seq
		return
	if seq == int(_remote_swing_seq[id]):
		return
	_remote_swing_seq[id] = seq
	var item_id := String(state.get("tool_swing_item", ""))
	var swing: Dictionary = HeldItemPoses.SWINGS.get(item_id, {})
	var anchor := _remote_hand_anchors.get(id) as Node3D
	if swing.is_empty() or anchor == null or not body.visible:
		return
	play_remote_swing(id, anchor, item_id, bool(state.get("tool_swing_hit", false)))


func play_remote_swing(id: int, anchor: Node3D, item_id: String, hit: bool) -> void:
	var swing: Dictionary = HeldItemPoses.SWINGS.get(item_id, {})
	if swing.is_empty() or anchor == null:
		return
	var running := _remote_swing_tweens.get(id) as Tween
	if running != null and running.is_valid():
		running.kill()
	var arc := deg_to_rad(float(swing["arc"]))
	var tween := create_tween().set_trans(Tween.TRANS_QUAD)
	_remote_swing_tweens[id] = tween
	anchor.rotation.x = 0.0
	# positive x tips the head toward the avatar's back; the strike goes forward and down through the target
	tween.tween_property(anchor, "rotation:x", arc * .70, float(swing["windup"])).set_ease(Tween.EASE_OUT)
	tween.tween_property(anchor, "rotation:x", -arc * 1.15, float(swing["strike"])).set_ease(Tween.EASE_IN)
	tween.tween_property(anchor, "rotation:x", 0.0, float(swing["recover"])).set_ease(Tween.EASE_OUT)
	var local := local_player as Node3D
	var distance := 0.0 if local == null else local.global_position.distance_to(anchor.global_position)
	var gain := clampf(1.0 - distance / 22.0, 0.0, 1.0)
	if gain <= 0.0:
		return
	if item_id == "rescue_axe":
		Sound.axe_swing(0.0, gain)
		if hit:
			get_tree().create_timer(float(swing["windup"]) + float(swing["strike"])).timeout.connect(
				func() -> void: Sound.axe_chop(0.0, gain))


## Backwards-compatible name retained for focused validators and any finite
## scene helpers written before the generic held-item slot was introduced.
func _sync_remote_flashlight(id: int, body: Node3D, state: Dictionary) -> void:
	_sync_remote_equipment(id, body, state)


func _sync_remote_held_item(id: int, body: Node3D, selected: String) -> void:
	var current := String(_remote_held_item_ids.get(id, ""))
	var item := _remote_held_items.get(id) as Node3D
	if current == selected and item != null:
		item.visible = body.visible and not selected.is_empty()
		return
	if item != null:
		item.visible = false
		item.queue_free()
	_remote_held_items.erase(id)
	_remote_held_item_ids[id] = selected
	if selected.is_empty():
		return
	var anchor := _remote_hand_anchors.get(id) as Node3D
	if anchor == null:
		return
	item = ModelSlot.instantiate_prop(String(REMOTE_HELD_MODELS[selected]))
	if item == null:
		return
	item.name = "PeerHeld%s" % selected.to_pascal_case()
	# held by the grip (the anchor is the hand), long tools upright and leaning forward
	item.transform = HeldItemPoses.third_person_transform(selected,
		float(REMOTE_HELD_SCALES.get(selected, .32)))
	item.visible = body.visible
	anchor.add_child(item)
	_remote_held_items[id] = item


func _update_remote_equipment_pose(id: int, body: Node3D,
		state: Dictionary = {}) -> void:
	var light := _remote_flashlights.get(id) as SpotLight3D
	if light == null:
		return
	var source := state if not state.is_empty() else (_states.get(id, {}) as Dictionary)
	var raw_direction = source.get("aim_direction", -body.global_basis.z)
	var aim := raw_direction as Vector3 if raw_direction is Vector3 \
		else -body.global_basis.z
	if aim.length_squared() < .01 or absf(aim.x) > 1.01 \
			or absf(aim.y) > 1.01 or absf(aim.z) > 1.01:
		aim = -body.global_basis.z
	aim = aim.normalized()
	var anchor := _remote_hand_anchors.get(id) as Node3D
	var origin := anchor.global_position if anchor != null \
		else body.global_position + Vector3.UP * 1.1
	var vr_left = VRPoseSync.left_hand_world(body, _vr_current.get(id, {}))
	if vr_left is Vector3:
		origin = vr_left   # a VR runner holds the flashlight in the left hand
	# Start beyond the hand/mannequin silhouette so the remote body cannot cast
	# a shadow across its own beam. The same aim still strikes nearby walls.
	light.global_position = origin + aim * REMOTE_BEAM_HAND_OFFSET
	var up := Vector3.FORWARD if absf(aim.dot(Vector3.UP)) > .98 else Vector3.UP
	light.look_at(light.global_position + aim, up)


func _update_remote_footstep(id: int, body: Node3D, previous: Vector3) -> void:
	if local_player == null or not body.visible:
		return
	var clip := String(body.get_meta("movement_clip", "idle"))
	if not clip in ["walk", "sprint", "chase", "crouch"]:
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


## The skin hash to publish in the room state ("" when you wear the default or the server does not hold yours: guests and
## offline players wear theirs locally only).
func _own_skin_hash() -> String:
	Backend.skin_sync.sync_own()
	return Backend.skin_sync.shared_hash()


func _apply_peer_skin(id: int, body: Node3D, hash: String, slim: bool = false) -> void:
	if not PlayerSkin.valid_hash(hash):
		hash = ""
	var previous := String(_peer_skin.get(id, ""))
	_peer_skin[id] = hash
	_peer_slim[id] = slim
	PlayerSkin.set_arms(body, slim and not hash.is_empty())
	PlayerSkin.note_peer(id, String(_states.get(id, {}).get("display_name", RoomState.peer_display_name(id))), hash, bool(_states.get(id, {}).get("skin_copy", true)), slim)
	if hash.is_empty():
		if not previous.is_empty():
			PlayerSkin.apply(body, PlayerSkin.default_texture())
			PlayerSkin.release_peer(previous, _peer_skin.values())
		return
	var texture := PlayerSkin.peer_texture(hash)
	if texture != null:
		PlayerSkin.apply(body, texture)
		return
	if not Backend.skin_sync.fetched.is_connected(_on_skin_fetched):
		Backend.skin_sync.fetched.connect(_on_skin_fetched)
	Backend.skin_sync.fetch(hash)


func _on_skin_fetched(hash: String) -> void:
	for id in _peer_skin:
		if String(_peer_skin[id]) == hash and _bodies.has(id):
			PlayerSkin.apply(_bodies[id], PlayerSkin.peer_texture(hash))


func _exit_tree() -> void:
	# the room or run is ending: free every downloaded skin
	PlayerSkin.clear_peer_cache()


func _drop(id: int) -> void:
	var body: Node3D = _bodies.get(id)
	if body != null:
		body.queue_free()
	var gone := String(_peer_skin.get(id, ""))
	_peer_skin.erase(id)
	_peer_slim.erase(id)
	PlayerSkin.forget_peer(id)
	if not gone.is_empty():
		PlayerSkin.release_peer(gone, _peer_skin.values())
	_bodies.erase(id)
	_vr_targets.erase(id)
	_vr_current.erase(id)
	_players.erase(id)
	_positions.erase(id)
	_facings.erase(id)
	_step_distances.erase(id)
	_remote_flashlights.erase(id)
	_remote_hand_anchors.erase(id)
	_remote_held_items.erase(id)
	_remote_held_item_ids.erase(id)
	_remote_swing_seq.erase(id)
	_remote_swing_tweens.erase(id)
	_states.erase(id)
	troll_peers.erase(id)
	guard.forget(id)
	_interaction_times.erase(id)
	_pending_captures.erase(id)
	_authorized_admin_peers.erase(id)
	_floor_exit_marks.erase(id)


func authorize_admin_peer(peer_id: int, expires_in: int,
		permissions: PackedStringArray = PackedStringArray()) -> void:
	if peer_id <= 1 or expires_in <= 0:
		return
	_authorized_admin_peers[peer_id] = {
		"expires_at": Time.get_ticks_msec() + expires_in * 1000,
		"permissions": permissions.duplicate(),
	}


func remote_admin_peer_allowed(peer_id: int, permission: String = "") -> bool:
	if Build.remote_guest_tools_allowed():
		return true
	var proof: Dictionary = _authorized_admin_peers.get(peer_id, {})
	var expires_at := int(proof.get("expires_at", 0))
	if expires_at <= Time.get_ticks_msec():
		_authorized_admin_peers.erase(peer_id)
		return false
	return permission.is_empty() or permission in PackedStringArray(
		proof.get("permissions", PackedStringArray()))


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
		var candidate_tools := Build.admin_permission("player") \
			if candidate_id == local_id \
			else remote_admin_peer_allowed(candidate_id, "player")
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
	var trolled: Array[Dictionary] = []
	for candidate in fallback:
		if troll_peers.has(int(candidate.get("peer_id", local_id))):
			var marked := candidate.duplicate()
			marked["hidden"] = false   # no locker, bed or safe room hides a trolled guest
			marked["in_safe_zone"] = false
			marked["troll"] = true
			trolled.append(marked)
	if not trolled.is_empty():
		pool = trolled   # and teammates are left alone while one is on this floor
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
		var copy := state.duplicate(true)
		if not copy.has("peer_id"):
			copy["peer_id"] = int(id)
		result.append(copy)
	return result


## Map-safe view of fresh remote transforms. The caller supplies the same
## depth value that is replicated in movement packets, preventing teammates on
## upper/lower floors from leaking onto the current floor's map.
func remote_player_marks(depth: int) -> Array:
	var result := []
	var now := Time.get_ticks_usec()
	for id_value in _states:
		var id := int(id_value)
		var state: Dictionary = _states[id]
		if now - int(state.get("received_usec", 0)) > REMOTE_STATE_TIMEOUT_USEC \
				or int(state.get("depth", -999999)) != depth:
			continue
		var marker_position = state.get("position")
		if not marker_position is Vector2:
			continue
		result.append({
			"peer_id": id,
			"at": marker_position,
			"facing": state.get("facing", Vector2.UP),
			"name": String(state.get("display_name", RoomState.peer_display_name(id))),
			"level": -depth,
			"colour": peer_colour(id),
		})
	for id_value in _floor_exit_marks.keys().duplicate():
		var id := int(id_value)
		var exit_mark: Dictionary = _floor_exit_marks[id]
		if now - int(exit_mark.get("received_usec", 0)) > FLOOR_EXIT_MARK_TIMEOUT_USEC:
			_floor_exit_marks.erase(id)
			continue
		var state: Dictionary = _states.get(id, {})
		if not state.is_empty() and int(state.get("depth", -999999)) == depth:
			_floor_exit_marks.erase(id)
			continue
		if int(exit_mark.get("depth", -999999)) != depth:
			continue
		var exit_at = exit_mark.get("at")
		if not exit_at is Vector2:
			continue
		result.append({
			"peer_id": id,
			"at": exit_at,
			"name": String(exit_mark.get("name", RoomState.peer_display_name(id))),
			"level": -depth,
			"exit_direction": String(exit_mark.get("direction", "up")),
		})
	return result


func stream_centers() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var now := Time.get_ticks_usec()
	for id in _states:
		var state: Dictionary = _states[id]
		if now - int(state.get("received_usec", 0)) > REMOTE_STATE_TIMEOUT_USEC:
			continue
		var center_position = state.get("position")
		if not center_position is Vector2:
			continue
		var level := -int(state.get("depth", 0))
		result.append(Vector3i(
			floori(center_position.x / StreamedRouteGenerator.CHUNK_SIZE), level,
			floori(center_position.y / StreamedRouteGenerator.CHUNK_SIZE)))
	return result


## A peer we may still send to: its ENet connection is up. Between a guest dropping and the host noticing (the ENet
## timeout), the peer is still listed but every send fails with "Unable to send packet ... max channels: 0" (the playtest
## party logged ~1,200 of them); skip it instead.
func peer_is_live(peer_id: int) -> bool:
	if not multiplayer.has_multiplayer_peer() or peer_id == multiplayer.get_unique_id():
		return false
	if not peer_id in multiplayer.get_peers():
		return false
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return true
	# A guest's ENet link is to the host only; other guests are reached through the host's relay, so their ids have no
	# ENet peer here (asking for one logged `!peers.has(p_id)` ~20 times a second on every guest).
	if not RoomState.is_host and peer_id != 1:
		return true
	var packet_peer := enet.get_peer(peer_id)
	return packet_peer == null or packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED


## Sends an RPC to every live peer (instead of .rpc(), which also targets peers that are already gone).
func _send_to_live(method: Callable, args: Array) -> void:
	for peer_id in multiplayer.get_peers():
		if peer_is_live(peer_id):
			method.rpc_id.callv([peer_id] + args)


## Hunters, from the host only.
signal hunters_received(data: Array)


func broadcast_hunters(data: Array) -> void:
	if RoomState.online and RoomState.is_host:
		# Unreliable packets above the ~1,392 byte MTU fragment and fill the send buffer ("Buffer full, dropping packets"):
		# a large hunter frame goes on the reliable channel instead.
		if var_to_bytes(data).size() > HUNTERS_UNRELIABLE_MAX_BYTES:
			_send_to_live(_hunters_large, [data])
		else:
			_send_to_live(_hunters, [data])


const HUNTERS_UNRELIABLE_MAX_BYTES := 1100


@rpc("authority", "call_remote", "reliable")
func _hunters_large(data: Array) -> void:
	_hunters(data)


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
		_send_to_live(_event, [_canonical_world_event(event)])


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
			"vent_used", "zellia_trade", "admin_auth", "admin_custom_map",
			"admin_world", "stream_pickup", "stream_safe_repair",
			"stream_checkpoint", "stream_drop", "stream_sabotage",
			"stream_waypoint", "stream_axe_rescue", "ravelle_disarm", "stream_room_light", "stream_booth", "stream_carousel"].has(what):
		return
	if not _interaction_allowed(sender):
		return
	if what == "vent_used":
		guard.allow_jump(sender, Time.get_ticks_msec() / 1000.0)
	if what == "stream_pickup" and troll_peers.has(sender):
		# It slips away from a trolled guest only: the pickup stays for everyone else.
		_player_event.rpc_id(sender, {"what": "troll_pickup", "entity_id": String(event.get("entity_id", ""))})
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
		if not ["grant_relay", "all_relays", "rebuild", "descend",
				"stun_hunters", "wake_hunters", "calm_hunters",
				"damage_checkpoint", "repair_checkpoint", "lights_on",
				"lights_off", "summon_hunter", "remove_hunter",
				"story_start", "story_stop", "story_reset"].has(action):
			return
		accepted = {"what": what, "action": action,
			"admin_ticket": _clean_admin_ticket(event.get("admin_ticket", ""))}
		if action in ["summon_hunter", "remove_hunter"]:
			var hunter_id := String(event.get("hunter_id", ""))
			if not HunterRoster.A_Z_IDS.has(hunter_id) \
					and not HunterRoster.VOID_IDS.has(hunter_id):
				return
			accepted["hunter_id"] = hunter_id
		elif action == "story_start":
			var scene_id := String(event.get("scene_id", ""))
			if scene_id.is_empty() or scene_id.length() > 80:
				return
			for character in scene_id:
				if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
					return
			accepted["scene_id"] = scene_id
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
		_send_to_live(_snapshot, [snapshot_source.call()])


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
			if troll_peers.has(peer_id):
				event = event.duplicate()
				event["troll"] = true
		if String(event.get("what", "")) in HOST_MOVES:
			guard.allow_jump(peer_id, Time.get_ticks_msec() / 1000.0)
		if peer_is_live(peer_id):
			_player_event.rpc_id(peer_id, event)


@rpc("authority", "call_remote", "reliable")
func _player_event(event: Dictionary) -> void:
	if String(event.get("what", "")) == "anticheat_snap" and local_player != null and event.get("at") is Vector3:
		local_player.global_position = event["at"]
		if local_player is CharacterBody3D:
			(local_player as CharacterBody3D).velocity = Vector3.ZERO
	player_event.emit(event)


## Host only. Runs the guard over one guest sample: a bad one is rewritten to the last good spot (so targeting,
## pickups and relays use it) and the guest is snapped back; STRIKE_KICK strikes kick it. False drops the sample.
func _guard_sample(id: int, received: Dictionary) -> bool:
	if not guard.exempt.is_valid():
		guard.exempt = func(peer_id: int) -> bool: return remote_admin_peer_allowed(peer_id)
		guard.rtt_ms = _peer_rtt_ms
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	var verdict := guard.check(id, received, Time.get_ticks_msec() / 1000.0, space)
	if verdict.is_empty():
		return true
	if bool(verdict.get("drop", false)):
		return false   # a duplicate or out-of-order sample: the newer one already landed
	var snap: Vector3 = verdict["snap_to"]
	received["at"] = snap
	received["position"] = Vector2(snap.x, snap.z)
	var kicked := bool(verdict["kick"])
	var lag := bool(verdict.get("lag", false))
	if not lag:
		set_troll(id, true)   # a lag-only snap never trolls
	guest_violation.emit(id, String(verdict["reason"]), int(verdict["strikes"]), kicked)
	if peer_is_live(id):
		_player_event.rpc_id(id, {"what": "anticheat_snap", "at": snap, "reason": String(verdict["reason"]), "lag": lag})
	if kicked:
		kick_guest(id, String(verdict["reason"]))
		return false
	return true


## The transport's round trip to a guest in ms (ENet direct connections; 0 when unknown, e.g. behind the relay).
func _peer_rtt_ms(peer_id: int) -> float:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer if is_inside_tree() else null
	if enet == null:
		return 0.0
	var packet_peer := enet.get_peer(peer_id)
	return packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if packet_peer != null else 0.0


## Host only: tells everyone, then drops the guest's connection.
func kick_guest(id: int, reason: String) -> void:
	if not RoomState.is_host or id <= 1:
		return
	send_system("%s WAS REMOVED // ANTI-CHEAT (%s)" % [RoomState.peer_display_name(id), reason.to_upper()])
	var state: Dictionary = _states.get(id, {})
	Backend.moderation.report_kick(String(state.get("account", "")), String(state.get("device", "")), reason,
		guard.strikes(id))
	if peer_is_live(id):
		_player_event.rpc_id(id, {"what": "message", "message": "REMOVED FROM ROOM // ANTI-CHEAT"})
	var peer := multiplayer.multiplayer_peer
	if peer != null and RoomState.online:
		get_tree().create_timer(.25).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer == peer:
				peer.disconnect_peer(id))
	_drop(id)


## Host only: true while the guest is under INTERACTION_RATE_MAX requests per window.
func _interaction_allowed(id: int) -> bool:
	var now := Time.get_ticks_msec()
	var times: Array = _interaction_times.get(id, [])
	while not times.is_empty() and now - int(times[0]) > INTERACTION_RATE_WINDOW_MS:
		times.pop_front()
	if times.size() >= INTERACTION_RATE_MAX:
		return false
	times.append(now)
	_interaction_times[id] = times
	return true


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


## Host only. Turns troll mode on or off for a guest and tells that guest's client.
## `ads`: whether its troll-mode "ads" show (TrollAds); owners can turn them off per player.
func set_troll(peer_id: int, on: bool, ads := true) -> void:
	if not RoomState.is_host or peer_id <= 1:
		return
	if troll_peers.has(peer_id) == on and (not on or bool(troll_peers[peer_id]) == ads):
		return
	if on:
		troll_peers[peer_id] = ads
	else:
		troll_peers.erase(peer_id)
	if peer_is_live(peer_id):
		_player_event.rpc_id(peer_id, {"what": "troll", "on": on, "ads": on and ads})


func _lookup_peers() -> void:
	var names := []
	var devices := []
	for id in _states:
		var state: Dictionary = _states[id]
		if not String(state.get("account", "")).is_empty():
			names.append(String(state["account"]))
		if not String(state.get("device", "")).is_empty():
			devices.append(String(state["device"]))
	Backend.moderation.lookup_peers(names, devices)


## Server verdicts: flagged or owner-trolled accounts (and devices kicked lately) get troll mode; a guest the host
## itself caught this room keeps it either way.
func _on_peers_looked_up(players: Dictionary, devices: Dictionary) -> void:
	for id in _states:
		var state: Dictionary = _states[id]
		var player = players.get(String(state.get("account", "")), {})
		var device = devices.get(String(state.get("device", "")), {})
		var server_troll := (player is Dictionary and (bool(player.get("troll", false)) \
				or bool(player.get("flagged", false)))) or (device is Dictionary and bool(device.get("troll", false)))
		var ads: bool = not (player is Dictionary and player.has("ads")) or bool(player.get("ads", true))
		set_troll(int(id), server_troll or guard.strikes(int(id)) > 0, ads)
		if player is Dictionary and bool(player.get("flagged", false)) and not _flag_noticed.has(id):
			_flag_noticed[id] = true
			send_system("NOTICE // %s IS FLAGGED BY ANTI-CHEAT" % RoomState.peer_display_name(int(id)))


func count() -> int:
	return _bodies.size()
