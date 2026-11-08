extends RefCounted

## Co-op player-state wire shape (PlayerStateWire): the 20 Hz sample must stay under PlayerStateWire.HOT_MAX_BYTES
## (ENet fragments unreliable packets over ~1,392 B, and VIDEO's 2026-10-28 co-op runs lost 2.1 KB samples that way),
## every field RemotePlayers sends must be classified hot or profile, and a receiver must rebuild exactly the
## long-key state it used to get -- over a real ENet loopback, including a peer that has not shown it reads v2 yet.
##
##   godot4 --headless res://tests/scenes/validate.tscn -- player_state_packet

var PORT := 28461 + int(OS.get_environment("VALIDATE_PORT_OFFSET"))

var _failures := 0
var _host: Node


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_host = host
	_source_fields_classified()
	_codec()
	await _loopback()
	await _real_state()
	return _failures


## What the wire would hand back for `value` (Vector3 goes through float32, etc.).
static func _wired(value: Variant) -> Variant:
	return bytes_to_var(var_to_bytes(value))


static func _same(left: Variant, right: Variant) -> bool:
	return var_to_bytes(_wired(left)) == var_to_bytes(_wired(right))


## A sample with every hot field at its largest realistic value (VR pose, grab, seated, long strings).
static func _worst_state(base: Dictionary = {}) -> Dictionary:
	var state := base.duplicate(true)
	var defaults := {
		"at": Vector3(1234.5, -48.0, 4567.8), "facing_y": 3.0, "clip": "crouch_walk", "position": Vector2(1234.5, 4567.8),
		"depth": -12, "hidden": true, "hiding_spot": Vector2i(123, 456), "hiding_style": "locker", "asleep": false,
		"seat_at": Vector2(12.5, 45.5), "seat_top": 0.52, "in_safe_zone": false, "noise": 0.87, "flashlight_on": true,
		"aim_direction": Vector3(0.1, -0.2, 0.97), "sprinting": true, "facing": Vector2(0.6, 0.8), "lamp_charge": 0.81,
		"selected_item": "rescue_axe", "tool_swing_seq": 1_000_000, "tool_swing_item": "rescue_axe", "tool_swing_hit": true,
		"selected_inventory_slot": 7, "in_vent": false, "grab": ["neck_lift", 1.9, 0.442, 0.0, -13.268, 0.0, 0.0],
		"vent_time_in": 12.5, "pesticide_active": true, "escape_active": true, "capture_immune": false,
		"game_over": false, "spectating": false, "visible": true, "exposure": 0.21, "noise_meter": 0.33,
		"temperature": 0.51, "ambient": 0.42, "heat_locked": false,
		"display_name": "A LONG DISPLAY NAME 24CH", "account": "account_name_20chars", "device": "f".repeat(32),
		"player_hue": 200.0, "player_skin": "mannequin", "skin": "a".repeat(64), "skin_copy": true, "skin_slim": false,
		"owned_items": {"flashlight": 1, "crowbar": 1, "battery": 3, "medkit": 2, "rope": 1, "lockpick": 1},
		"item_durability": {"flashlight": 0.73, "crowbar": 0.5, "rescue_axe": 0.9},
		"inventory_order": ["flashlight", "crowbar", "battery", "medkit", "rope", "lockpick", "rescue_axe", "taser"],
		"inventory_slot_durability": [1.0, 0.73, 1.0, 0.5, 1.0, 1.0, 0.9, 0.4], "inventory_free_slots": 0,
		"inventory_capacity": 8, "equipped_backpack": "large_pack", "no_target": false, "god_mode": false, "noclip": false,
	}
	for key in defaults:
		if not state.has(key) or key in ["clip", "hiding_style", "grab", "seat_at", "selected_item", "tool_swing_item"]:
			state[key] = defaults[key]
	var vr := PackedByteArray()
	vr.resize(VRPoseSync.PACKET_BYTES)
	state["vr"] = vr
	state["seq"] = 2_000_000_000
	return state


## Every key RemotePlayers._local_state() can emit is listed hot or profile (an unlisted one still arrives, in
## extras, but costs bytes and is easy to miss). Read from the source so conditional keys (vr) count too.
func _source_fields_classified() -> void:
	var source := FileAccess.get_file_as_string("res://game/network/remote_players.gd")
	var start := source.find("func _local_state()")
	var end := source.find("\nfunc ", start + 1)
	_expect(start >= 0 and end > start, "RemotePlayers._local_state() not found")
	if start < 0 or end <= start:
		return
	var body := source.substr(start, end - start)
	var keys := {}
	var pattern := RegEx.new()
	pattern.compile("(?m)^\\s*\"([a-z_]+)\"\\s*:|state\\[\"([a-z_]+)\"\\]")
	for found in pattern.search_all(body):
		var key := found.get_string(1) if not found.get_string(1).is_empty() else found.get_string(2)
		keys[key] = true
	_expect(keys.size() >= 40, "only %d keys parsed from _local_state(); the classification check is not reading it" % keys.size())
	var missing := PlayerStateWire.unclassified(keys)
	_expect(missing.is_empty(), "RemotePlayers._local_state() sends %s, in neither PlayerStateWire.HOT_FIELDS nor PROFILE_FIELDS" % [missing])
	for key in PlayerStateWire.BOOL_FIELDS:
		_expect(key in PlayerStateWire.HOT_FIELDS, "bool field %s is not a hot field" % key)
	for key in PlayerStateWire.PROFILE_FIELDS:
		_expect(not key in PlayerStateWire.HOT_FIELDS, "%s is both hot and profile" % key)
	_expect(PlayerStateWire.HOT_FIELDS.size() <= 62, "more hot fields than present_bits can hold")


func _codec() -> void:
	var state := _worst_state()
	var hot := PlayerStateWire.encode_hot(state)
	var hot_bytes := PlayerStateWire.size_of(hot)
	var legacy_bytes := PlayerStateWire.size_of(state)
	var profile_bytes := PlayerStateWire.size_of(PlayerStateWire.profile_of(state))
	print("  wire      worst case: full dict %d B -> hot %d B (budget %d) + profile %d B sent on change" % [
		legacy_bytes, hot_bytes, PlayerStateWire.HOT_MAX_BYTES, profile_bytes])
	_expect(hot_bytes < PlayerStateWire.HOT_MAX_BYTES,
		"hot packet is %d B, over the %d B budget" % [hot_bytes, PlayerStateWire.HOT_MAX_BYTES])
	_expect(not hot[-1] is Dictionary, "a fully classified state still carried extras %s" % [hot[-1]])

	var decoded := PlayerStateWire.decode_hot(_wired(hot))
	decoded.merge(PlayerStateWire.profile_of(state), false)
	for key in state:
		_expect(decoded.has(key) and _same(decoded[key], state[key]),
			"%s did not survive the hot+profile round trip (%s -> %s)" % [key, state[key], decoded.get(key)])
	for key in decoded:
		_expect(state.has(key), "round trip invented %s" % key)

	# Absent fields stay absent (readers fall back on .get defaults), and a null value stays null.
	var sparse := {"at": Vector3.ONE, "position": Vector2.ONE, "seat_at": null, "seq": 3}
	var back := PlayerStateWire.decode_hot(PlayerStateWire.encode_hot(sparse))
	_expect(back.size() == 4 and back.has("seat_at") and back["seat_at"] == null and not back.has("hidden"),
		"a sparse sample decoded as %s" % [back])

	# Unclassified keys and off-type bools still arrive (extras), under their long names.
	var odd := {"at": Vector3.ONE, "position": Vector2.ONE, "visible": 1, "lane_new_field": "x", "seq": 4}
	back = PlayerStateWire.decode_hot(PlayerStateWire.encode_hot(odd))
	_expect(back.get("visible") is int and int(back["visible"]) == 1, "an int 'visible' was lost or turned into a bit")
	_expect(String(back.get("lane_new_field", "")) == "x", "an unclassified field was dropped instead of riding in extras")

	# Version tag: other versions, truncated or forged packets are refused, never half-read.
	var good := PlayerStateWire.encode_hot(state)
	for bad in [[], [1, 0, 0, 0], [PlayerStateWire.VERSION + 1, 1, 0, 0], good.slice(0, good.size() - 1),
			good + [{"x": 1}, {"y": 2}], [PlayerStateWire.VERSION, "1", 0, 0], good + [7]]:
		_expect(PlayerStateWire.decode_hot(bad).is_empty(), "decode_hot accepted a bad packet of %d items" % (bad as Array).size())
	var forged := [PlayerStateWire.VERSION, 5, 0, 0, {"display_name": "IMPOSTOR", "noclip": true}]
	back = PlayerStateWire.decode_hot(forged)
	_expect(not back.has("display_name") and not back.has("noclip"), "profile fields were accepted from hot extras")


## Two RemotePlayers on two SceneMultiplayers over a real ENet loopback.
func _loopback() -> void:
	var tree := _host.get_tree()
	var server := ENetMultiplayerPeer.new()
	if server.create_server(PORT, 4) != OK:
		_fail("could not open ENet loopback server on %d" % PORT)
		return
	var client := ENetMultiplayerPeer.new()
	if client.create_client("127.0.0.1", PORT) != OK:
		_fail("could not open ENet loopback client")
		server.close()
		return
	var mp_a := SceneMultiplayer.new()
	var mp_b := SceneMultiplayer.new()
	var side_a := Node.new()
	side_a.name = "WireA"
	var side_b := Node.new()
	side_b.name = "WireB"
	tree.root.add_child(side_a)
	tree.root.add_child(side_b)
	tree.set_multiplayer(mp_a, side_a.get_path())
	tree.set_multiplayer(mp_b, side_b.get_path())
	mp_a.multiplayer_peer = server
	mp_b.multiplayer_peer = client
	var a := RemotePlayers.new()
	a.name = "Remotes"
	side_a.add_child(a)
	var b := RemotePlayers.new()
	b.name = "Remotes"
	side_b.add_child(b)

	for frame in 300:
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and mp_a.get_peers().size() == 1:
			break
		await tree.process_frame
	_expect(mp_a.get_peers().size() == 1, "ENet loopback never connected")
	# Both fixtures play guests: a host would run GuestGuard, which (rightly) snaps the fixture's teleports.
	var was_host := RoomState.is_host
	RoomState.is_host = false
	if mp_a.get_peers().size() == 1:
		await _exchange(tree, a, b, mp_b.get_unique_id())
	RoomState.is_host = was_host

	a.queue_free()
	b.queue_free()
	await tree.process_frame
	client.close()
	server.close()
	tree.set_multiplayer(null, side_a.get_path())
	tree.set_multiplayer(null, side_b.get_path())
	side_a.queue_free()
	side_b.queue_free()
	await tree.process_frame


func _exchange(tree: SceneTree, a: RemotePlayers, b: RemotePlayers, b_id: int) -> void:
	var state_a := _worst_state({"skin": ""})   # no skin download from a fixture
	var state_b := _worst_state({"skin": ""})
	state_b["display_name"] = "PEER B"

	# 1. Nobody has shown v2 yet: A must send the full Dictionary (an older build reads it unchanged).
	await _send_until(tree, func() -> void: a._send_state(_stamped(state_a)),
		func() -> bool: return b._states.has(1))
	_expect(a._profile_sent.is_empty(), "A sent a v2 profile before B had shown it reads v2")
	_expect(int(b._wire_peers.get(1, 0)) == PlayerStateWire.VERSION, "B did not learn from A's tagged full state that A reads v2")
	_expect(String(b._states.get(1, {}).get("display_name", "")) == state_a["display_name"], "B lost A's identity from the full state")

	# An older build never tags its packets, so it keeps getting full Dictionaries.
	var old_build := state_b.duplicate(true)
	old_build.erase("wire")
	b._unpack_state(4242, old_build)
	_expect(not b._wire_peers.has(4242), "an untagged (older build) peer was treated as reading v2")
	b._drop(4242)

	# 2. B answers (tagged); A switches B to hot packets plus a reliable profile.
	await _send_until(tree, func() -> void: b._send_state(_stamped(state_b)),
		func() -> bool: return a._wire_peers.has(b_id))
	var moved := state_a.duplicate(true)
	moved["at"] = Vector3(-5.0, -48.0, 99.5)
	moved["display_name"] = "RENAMED A"
	moved["inventory_order"] = ["taser", "", "", "", "", "", "", ""]
	await _send_until(tree, func() -> void: a._send_state(_stamped(moved)),
		func() -> bool: return _same(b._states.get(1, {}).get("at"), moved["at"]) \
			and String(b._states.get(1, {}).get("display_name", "")) == "RENAMED A")
	_expect(a._profile_sent.has(b_id), "A never used the v2 path (hot packet + profile) for B")
	var seen: Dictionary = b._states.get(1, {})
	for key in moved:
		if key in PlayerStateWire.TRANSPORT_FIELDS:
			continue
		_expect(seen.has(key) and _same(seen[key], moved[key]),
			"over ENet, %s arrived as %s (sent %s)" % [key, seen.get(key), moved[key]])
	_expect(String(seen.get("display_name", "")) == "RENAMED A", "a profile change did not reach the peer")

	# 3. A profile that did not change is not resent every tick.
	var sent_hash = a._profile_sent.get(b_id)
	a._send_state(_stamped(moved))
	_expect(a._profile_sent.get(b_id) == sent_hash, "the profile hash changed for an unchanged profile")


var _seq := 0


## A copy with the next sequence number, as RemotePlayers._process stamps every sample (receivers drop old ones).
func _stamped(state: Dictionary) -> Dictionary:
	_seq += 1
	var copy := state.duplicate(true)
	copy["seq"] = _seq
	return copy


func _send_until(tree: SceneTree, send: Callable, done: Callable) -> void:
	for frame in 240:
		if done.call():
			return
		if frame % 6 == 0:
			send.call()
		await tree.process_frame
	_fail("loopback exchange timed out")


## The real controller's state (a booted route scene): classified, and under budget even at its worst.
func _real_state() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = load("res://game/main_3d.tscn").instantiate()
	_host.get_tree().root.add_child(scene)
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
	var remotes := scene.get("_remotes") as RemotePlayers
	_expect(remotes != null and remotes.local_player != null, "main_3d has no RemotePlayers with a local player")
	if remotes != null and remotes.local_player != null:
		var state := remotes._local_state()
		state["seq"] = 1
		_expect(PlayerStateWire.unclassified(state).is_empty(),
			"the live state carries unclassified keys %s" % [PlayerStateWire.unclassified(state)])
		var live := PlayerStateWire.size_of(PlayerStateWire.encode_hot(state))
		var worst := PlayerStateWire.size_of(PlayerStateWire.encode_hot(_worst_state(state)))
		print("  wire      live controller: full dict %d B -> hot %d B (worst %d B)" % [
			PlayerStateWire.size_of(state), live, worst])
		_expect(worst < PlayerStateWire.HOT_MAX_BYTES, "live hot packet at its worst is %d B" % worst)
	scene.queue_free()
	await _host.get_tree().process_frame
