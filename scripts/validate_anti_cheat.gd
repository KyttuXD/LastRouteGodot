extends RefCounted

## Host anti-cheat for co-op guests (docs/ANTI_CHEAT.md): synthetic cheating guests get snapped back and kicked after
## GuestGuard.STRIKE_KICK strikes; legit fast moves (sprint with lag, ladders, plunges, stairs between floors,
## respawns, admins) never trigger. Also the per-guest interaction rate limit.
##
##   godot --headless --path . res://scenes/validate.tscn -- anti_cheat

const HZ := 20.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _state(at: Vector3, extra := {}) -> Dictionary:
	var state := {"at": at, "position": Vector2(at.x, at.z), "depth": 0, "lamp_charge": 80.0, "sprinting": false,
		"inventory_order": ["flashlight", ""]}
	state.merge(extra, true)
	return state


## Feeds `steps` samples moving `velocity` m/s; returns the first verdict that is not empty.
func _run(guard: GuestGuard, peer: int, from: Vector3, velocity: Vector3, steps: int, t0: float, extra := {},
		space: PhysicsDirectSpaceState3D = null, gap := 1.0 / HZ) -> Dictionary:
	for i in steps + 1:
		var verdict := guard.check(peer, _state(from + velocity * gap * i, extra), t0 + gap * i, space)
		if not verdict.is_empty():
			return verdict
	return {}


func run(host: Node) -> int:
	var sprint := GuestGuard.max_speed
	# Legit.
	var guard := GuestGuard.new()
	_expect(_run(guard, 2, Vector3.ZERO, Vector3(sprint, 0, 0), 60, 0.0, {"sprinting": true}).is_empty(),
		"a 3 s sprint was flagged")
	_expect(_run(guard, 3, Vector3.ZERO, Vector3(sprint, 0, 0), 4, 0.0, {}, null, 1.0).is_empty(),
		"a sprint over 1 s lag gaps was flagged")
	_expect(_run(guard, 4, Vector3.ZERO, Vector3(0, GameConfig.LADDER_CLIMB_SPEED, 0), 80, 0.0).is_empty(),
		"climbing a ladder was flagged")
	_expect(_run(guard, 5, Vector3(0, 30, 0), Vector3(0, -25, 0), 20, 0.0).is_empty(), "a plunge was flagged")
	guard.check(6, _state(Vector3.ZERO), 0.0)
	_expect(guard.check(6, _state(Vector3(40, -4, 3), {"depth": 1}), .05).is_empty(), "taking stairs down was flagged")
	guard.legit_spot = func(at: Vector3, _depth: int) -> bool: return at.distance_to(Vector3(100, 0, 0)) < 4.0
	guard.check(7, _state(Vector3.ZERO), 0.0)
	_expect(guard.check(7, _state(Vector3(100, 0, 1)), .05).is_empty(), "a respawn at the checkpoint was flagged")
	guard.exempt = func(peer: int) -> bool: return peer == 8
	_expect(_run(guard, 8, Vector3.ZERO, Vector3(80, 0, 0), 20, 0.0).is_empty(), "an admin's fast flight was flagged")
	guard.check(9, _state(Vector3.ZERO, {"lamp_charge": 20.0, "inventory_order": ["flashlight", "battery"]}), 0.0)
	_expect(guard.check(9, _state(Vector3.ZERO, {"lamp_charge": 100.0, "inventory_order": ["flashlight", ""]}),
		.05).is_empty(), "using a battery was flagged")
	_expect(_run(guard, 10, Vector3.ZERO, Vector3(sprint, 0, 0), 20, 0.0, {"spectating": true}).is_empty() \
		and guard.check(10, _state(Vector3(300, 0, 0), {"spectating": true}), 2.0).is_empty(), "a spectator was flagged")

	# Cheats.
	var cheats := {
		"speed": _run(guard, 20, Vector3.ZERO, Vector3(sprint * 2.5, 0, 0), 60, 0.0),
		"teleport": _run(guard, 21, Vector3.ZERO, Vector3(40.0 * HZ, 0, 0), 1, 0.0),
		"fly": _run(guard, 22, Vector3.ZERO, Vector3(0, 12, 0), 60, 0.0),
		"stamina": _run(guard, 23, Vector3.ZERO, Vector3(sprint, 0, 0), 200, 0.0, {"sprinting": true}),
		"lamp": _run(guard, 24, Vector3.ZERO, Vector3.ZERO, 2, 0.0, {"lamp_charge": 150.0}),
		"position": _run(guard, 25, Vector3.ZERO, Vector3.ZERO, 2, 0.0, {"position": Vector2(30, 30)}),
	}
	guard.check(26, _state(Vector3.ZERO, {"lamp_charge": 10.0}), 0.0)
	cheats["lamp_refill"] = guard.check(26, _state(Vector3.ZERO, {"lamp_charge": 90.0}), .05)
	for reason in cheats:
		var verdict: Dictionary = cheats[reason]
		_expect(String(verdict.get("reason", "")) == String(reason).trim_suffix("_refill"),
			"%s cheat gave %s" % [reason, verdict])
	_expect((cheats["teleport"] as Dictionary).get("snap_to") == Vector3.ZERO, "the teleporter was not snapped back")

	# Strikes: repeated cheating kicks; a clean run decays strikes.
	var kicked := false
	var t := 10.0
	for i in GuestGuard.STRIKE_KICK:
		guard.check(30, _state(Vector3.ZERO), t)
		var verdict := guard.check(30, _state(Vector3(50, 0, 0)), t + .05)
		kicked = bool(verdict.get("kick", false))
		_expect(kicked == (i == GuestGuard.STRIKE_KICK - 1), "strike %d kick=%s" % [i + 1, kicked])
		t += .1
	guard.check(31, _state(Vector3.ZERO), 0.0)
	guard.check(31, _state(Vector3(50, 0, 0)), .05)
	_run(guard, 31, Vector3.ZERO, Vector3.ZERO, int(GuestGuard.STRIKE_DECAY_SECONDS * 2.0), .1, {}, null, 1.0)
	_expect(guard.strikes(31) == 0, "strikes did not decay (%d)" % guard.strikes(31))

	# No-clip: a wall between two samples, and a door that must not count.
	var root := Node3D.new()
	host.get_tree().root.add_child(root)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.2, 3, 6)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.global_position = Vector3(1, 1.5, 0)
	var door := RouteInteractable3D.new()
	var door_body := StaticBody3D.new()
	var door_shape := CollisionShape3D.new()
	door_shape.shape = box
	door_body.add_child(door_shape)
	door.add_child(door_body)
	root.add_child(door)
	door_body.global_position = Vector3(1, 1.5, 20)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var through := _run(guard, 40, Vector3(0, 0, 0), Vector3(4, 0, 0), 10, 0.0, {}, space)
	_expect(String(through.get("reason", "")) == "noclip", "walking through a wall gave %s" % through)
	_expect(_run(guard, 41, Vector3(0, 0, 20), Vector3(4, 0, 0), 10, 0.0, {}, space).is_empty(),
		"walking through a (lagging) door was flagged")
	_expect(_run(guard, 42, Vector3(0, 0, 5), Vector3(4, 0, 0), 10, 0.0, {}, space).is_empty(),
		"walking past the wall's end was flagged")
	root.queue_free()

	# Host-caused moves (vent transit, pulled out of hiding, axe rescue, revive) never strike.
	guard.check(60, _state(Vector3.ZERO), 0.0)
	guard.allow_jump(60, .02)
	_expect(guard.check(60, _state(Vector3(30, 0, 0)), .05).is_empty(), "a host-approved vent jump was flagged")
	_expect(not guard.check(60, _state(Vector3(70, 0, 0)), 5.0).is_empty(), "the jump allowance never ran out")

	# Troll mode: hunters take only the trolled guest, hiding or not, and leave the teammate alone.
	var troll_remotes := RemotePlayers.new()
	var now := Time.get_ticks_usec()
	troll_remotes._states = {
		70: {"peer_id": 70, "position": Vector2(40, 0), "depth": 0, "hidden": true, "received_usec": now},
		71: {"peer_id": 71, "position": Vector2(2, 0), "depth": 0, "received_usec": now}}
	var plain := troll_remotes.best_target(Vector2.ZERO, {"peer_id": 1, "position": Vector2(90, 0), "depth": 0}, 0)
	_expect(int(plain.get("peer_id", 0)) == 71, "without troll mode the nearest visible runner is not chosen (%s)" % plain)
	troll_remotes.troll_peers[70] = true
	var picked := troll_remotes.best_target(Vector2.ZERO, {"peer_id": 1, "position": Vector2(1, 0), "depth": 0}, 0)
	_expect(int(picked.get("peer_id", 0)) == 70 and not bool(picked.get("hidden", true)) \
		and bool(picked.get("troll", false)), "a hidden trolled guest was not the hunters' target (%s)" % picked)
	troll_remotes.free()
	var brain := HunterBrain.new(Vector2.ZERO, "TROLL", HunterRoster.DEFAULT_ID, "standard")
	var normal_speed := brain._current_speed(0, 0)
	brain.troll_target = true
	_expect(brain._current_speed(0, 0) > normal_speed * 1.1, "hunters are not faster toward a trolled guest")
	var controller := PlayerController3D.new()
	controller.admin_god_mode = false
	controller._update_stamina(1.0, true)
	var normal_drain := GameConfig.MAX_STAMINA - controller.stamina
	controller.stamina = GameConfig.MAX_STAMINA
	controller.troll_active = true
	controller._update_stamina(1.0, true)
	_expect(GameConfig.MAX_STAMINA - controller.stamina > normal_drain * 1.4, "stamina does not drain faster when trolled")
	controller._update_troll(10.0)
	_expect(controller._troll_step_in > 0.0, "no fake hunter footstep was scheduled")
	controller.free()
	var scare := HunterJumpscare.new()
	scare.duration_scale = GameConfig.TROLL_SCARE_SCALE
	_expect(scare.duration_scale >= 2.0, "the trolled scare is not longer")
	scare.free()

	# Client messages: a server status or a FLAGGED refusal reaches the player as an account message.
	var heard := [""]
	var listener := func(_signed: bool, _name: String, _admin: bool, message: String) -> void: heard[0] = message
	Backend.account_changed.connect(listener)
	Backend.moderation._on_status_reply({"status": {"flagged": true,
		"message": "PUBLIC ROUTE AND SKIN UPLOADS LOCKED UNTIL 12:00"}})
	_expect(String(heard[0]).begins_with("PUBLIC ROUTE"), "the restriction message did not reach the player")
	_expect(Backend.moderation.restriction_message() == String(heard[0]), "restriction_message() is stale")
	Backend.account_changed.disconnect(listener)
	Backend.moderation._on_status_reply({"status": {}})
	_expect(Backend.moderation.device_id().length() == 32, "the device id is not a 32-hex id")

	# Interaction rate limit.
	var remotes := RemotePlayers.new()
	var allowed := 0
	for i in 30:
		if remotes._interaction_allowed(50):
			allowed += 1
	_expect(allowed == RemotePlayers.INTERACTION_RATE_MAX, "%d of 30 instant interactions allowed" % allowed)
	remotes.free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  anti_cheat  ok")
	return _failures
