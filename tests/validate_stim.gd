extends RefCounted

## Stim Pack (GameConfig.STIM_*, docs/REVIVE.md): a 0.6 s injection uses one from the stack, fills stamina and boosts
## sprinting (x1.2 speed, half drain) for 6 s; then a 10 s crash halves regen and beats a heartbeat hunters can hear,
## in a locker too. No second stim until the crash is over; a grab cuts the injection without using one. GuestGuard
## lets the boost's speed through only after a stim was really used up.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- stim

const STEP := 1.0 / 60.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _advance(player: PlayerController3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		player._update_stim(STEP)
		t += STEP


## Horizontal speed after a second of holding sprint + forward.
func _sprint_speed(host: Node, player: PlayerController3D) -> float:
	Input.action_press("move_up")
	Input.action_press("sprint")
	var best := 0.0
	for _i in 40:
		await host.get_tree().physics_frame
		best = maxf(best, Vector2(player.velocity.x, player.velocity.z).length())
	Input.action_release("move_up")
	Input.action_release("sprint")
	for _i in 10:
		await host.get_tree().physics_frame
	return best


func _guard_state(at: Vector3, stims: int, boost: float) -> Dictionary:
	var order := ["flashlight", "stim_pack" if stims > 0 else ""]
	return {"at": at, "position": Vector2(at.x, at.z), "depth": 0, "lamp_charge": 80.0, "sprinting": true,
		"inventory_order": order, "inventory_slot_durability": [80, stims], "stim_boost": boost}


func _guard_run(guard: GuestGuard, peer: int, speed: float, seconds: float, stims_before: int, stims_after: int,
		boost: float) -> Dictionary:
	guard.check(peer, _guard_state(Vector3.ZERO, stims_before, 0.0), 0.0)
	var t := 0.05
	var x := 0.0
	while t < seconds:
		x += speed * .05
		var verdict := guard.check(peer, _guard_state(Vector3(x, 0, 0), stims_after, maxf(0.0, boost - t)), t)
		if not verdict.is_empty():
			return verdict
		t += .05
	return {}


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 8:
		await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
	player.admin_god_mode = false
	player.grant_inventory_item("stim_pack", 3)
	var slot := player.inventory_order.find("stim_pack")
	player.select_inventory_slot(slot)
	_expect(player.stack_count_at(slot) == 3, "three stims are not one stack of 3")
	var walk_speed := await _sprint_speed(host, player)

	# injection, then the boost
	player.stamina = 12.0
	player._use_stim()
	_expect(player.stim_injecting() > 0.0 and player.stack_count_at(slot) == 3, "the stim was used up before the injection landed")
	_advance(player, GameConfig.STIM_INJECT_SECONDS + .05)
	_expect(player.stack_count_at(slot) == 2, "the injection did not use exactly one stim")
	_expect(is_equal_approx(player.stamina, GameConfig.MAX_STAMINA) and not player.exhausted, "the stim did not fill stamina")
	_expect(player.stim_boost > GameConfig.STIM_BOOST_SECONDS - .2, "no boost after the stim")
	player._use_stim()
	_expect(player.stim_injecting() == 0.0, "a second stim started during the boost")
	var boosted_speed := await _sprint_speed(host, player)
	_expect(walk_speed > 0.0 and absf(boosted_speed / walk_speed - GameConfig.STIM_SPEED_SCALE) < .04,
		"the boost sprint is x%.2f, not x%.2f (%.2f vs %.2f)" % [boosted_speed / maxf(walk_speed, .001), GameConfig.STIM_SPEED_SCALE, boosted_speed, walk_speed])
	player.stamina = GameConfig.MAX_STAMINA
	player._update_stamina(1.0, true)
	_expect(is_equal_approx(player.stamina, GameConfig.MAX_STAMINA - GameConfig.STAMINA_SPRINT_DRAIN * GameConfig.STIM_DRAIN_SCALE),
		"boosted sprint drain is not halved (%.1f left after 1 s)" % player.stamina)

	# the crash: half regen and a heartbeat, in a locker too
	_advance(player, player.stim_boost + .02)
	_expect(player.stim_boost == 0.0 and player.stim_crash > GameConfig.STIM_CRASH_SECONDS - .2, "the crash did not follow the boost")
	player.stamina = 40.0
	player._update_stamina(STEP, false)
	_expect(is_equal_approx(player.stamina, 40.0 + GameConfig.STAMINA_RECOVERY * GameConfig.STIM_CRASH_REGEN_SCALE * STEP),
		"crash regen is not halved")
	var beats := 0
	for _i in 60:
		player._update_stim(STEP)
		if player._noise_burst_timer > 0.0 and player._noise_burst >= GameConfig.STIM_HEARTBEAT_NOISE:
			beats += 1
	_expect(beats > 0, "no heartbeat noise during the crash")
	player.hidden = true
	player.input_frozen = true
	player.emit_noise_burst(GameConfig.STIM_HEARTBEAT_NOISE, .25)
	await host.get_tree().physics_frame
	_expect(player.noise >= GameConfig.STIM_HEARTBEAT_NOISE - .01, "the heartbeat goes silent in a locker (%.2f)" % player.noise)
	player.hidden = false
	player.input_frozen = false
	player._use_stim()
	_expect(player.stim_injecting() == 0.0, "a stim was used during the crash")
	_advance(player, player.stim_crash + .05)
	_expect(player.stim_crash == 0.0, "the crash never ended")

	# a grab cuts the injection: nothing used
	player._use_stim()
	player._update_stim(.2)
	player.grab_active = true
	player._update_stim(STEP)
	player.grab_active = false
	_advance(player, 1.0)
	_expect(player.stack_count_at(slot) == 2 and player.stim_boost == 0.0, "a grab mid-injection still used a stim")
	# spectating clears it
	player.stim_boost = 3.0
	player.enter_spectator()
	_expect(player.stim_boost == 0.0 and player.stim_crash == 0.0, "spectating kept the stim running")
	player.leave_spectator()

	# GuestGuard: boosted speed passes only with a stim used up; more than the boost still fails
	var boosted := GuestGuard.max_speed * GameConfig.STIM_SPEED_SCALE
	_expect(_guard_run(GuestGuard.new(), 2, boosted, 5.0, 1, 0, GameConfig.STIM_BOOST_SECONDS).is_empty(),
		"a stim boost was flagged")
	_expect(not _guard_run(GuestGuard.new(), 3, boosted * GuestGuard.TOLERANCE * 1.12, 5.0, 1, 0, GameConfig.STIM_BOOST_SECONDS).is_empty(),
		"a speed past the boost passed")
	_expect(not _guard_run(GuestGuard.new(), 4, boosted * GuestGuard.TOLERANCE * .97, 5.0, 1, 1, GameConfig.STIM_BOOST_SECONDS).is_empty(),
		"a claimed boost with no stim used passed")
	_expect(_guard_run(GuestGuard.new(), 5, GuestGuard.max_speed * .9, 9.0, 1, 0, GameConfig.STIM_BOOST_SECONDS).is_empty(),
		"a long sprint right after a stim refill was flagged as stamina")
	scene.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  stim  ok")
	return _failures
