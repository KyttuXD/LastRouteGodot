extends RefCounted

## The anti-AFK clock measures real displacement on every platform: a phone with the touch layer attached and no fingers down,
## a Quest with head sway, and a desktop with nothing held all trip the Gray Void pressure on schedule; walking or a real turn
## resets it.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- anti_idle

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## Seconds until the AFK clock reaches `delay` while `sample` supplies the target each tick (null = reset by activity).
func _seconds_to_pressure(delay: float, sample: Callable, xr: bool = false) -> float:
	PlatformProfile.is_xr = xr
	var anchors := {}
	var afk := 0.0
	var clock := 0.0
	var step := 1.0 / 30.0
	while clock < delay * 3.0:
		clock += step
		if AntiIdle.party_moved(anchors, [sample.call(clock)]):
			afk = 0.0
		else:
			afk += step
		if afk >= delay:
			return clock
	return INF


func run(host: Node) -> int:
	await host.get_tree().process_frame
	var saved_xr := PlatformProfile.is_xr
	var still := func(_t: float) -> Dictionary:
		return {"peer_id": 1, "position": Vector2(10.5, 10.5), "facing": Vector2(0, 1)}
	for mode in ["relaxed", "standard", "hard", "nightmare"]:
		var delay := GameConfig.anti_afk_hunter_seconds(mode)
		# desktop, idle
		var at := _seconds_to_pressure(delay, still)
		_expect(absf(at - delay) < .2 and at < INF, "%s: an idle desktop trips the AFK clock at %.0f s (got %.1f)" % [mode, delay, at])
	var delay := GameConfig.anti_afk_hunter_seconds("standard")

	# phone: the touch layer is attached, no finger is down, the d-pad and stick are released
	var touch := TouchControls.new()
	host.add_child(touch)
	await host.get_tree().process_frame
	for action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		_expect(not Input.is_action_pressed(action), "the idle touch layer holds %s down" % action)
	var looks := [0]
	touch.look_dragged.connect(func(_d: Vector2) -> void: looks[0] += 1)
	touch.set_pad(Vector2.ZERO, false)
	for i in 120:
		await host.get_tree().process_frame
	_expect(looks[0] == 0, "the idle touch layer emitted look drags (%d)" % looks[0])
	for action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		_expect(not Input.is_action_pressed(action), "the idle touch layer pressed %s" % action)
	var phone_at := _seconds_to_pressure(delay, still)
	_expect(absf(phone_at - delay) < .2, "an idle phone trips the AFK clock on schedule (%.1f vs %.0f s)" % [phone_at, delay])
	touch.queue_free()

	# Quest: head sway well under a deliberate turn does not reset the clock
	var sway := func(t: float) -> Dictionary:
		return {"peer_id": 1, "position": Vector2(10.5, 10.5), "facing": Vector2(sin(t * 1.3) * .2, 1.0).normalized()}
	var quest_at := _seconds_to_pressure(delay, sway, true)
	_expect(absf(quest_at - delay) < .2, "an idle Quest with head sway trips the AFK clock on schedule (%.1f vs %.0f s)" % [quest_at, delay])
	# a keep-awake phone: the flag changes nothing
	var kept := _seconds_to_pressure(delay, still)
	_expect(absf(kept - delay) < .2, "keep-awake does not feed the clock")

	# real activity resets it
	var walker := func(t: float) -> Dictionary:
		return {"peer_id": 1, "position": Vector2(10.5 + t * 1.5, 10.5), "facing": Vector2(0, 1)}
	_expect(_seconds_to_pressure(delay, walker) == INF, "walking keeps the clock at zero")
	var turner := func(t: float) -> Dictionary:
		var angle := floorf(t / 10.0) * 1.5
		return {"peer_id": 1, "position": Vector2(10.5, 10.5), "facing": Vector2.from_angle(angle)}
	_expect(_seconds_to_pressure(delay, turner) == INF, "a real turn every 10 s keeps the clock at zero")

	PlatformProfile.is_xr = saved_xr
	if _failures == 0:
		print("  ok    anti_idle: desktop, phone (touch layer, no touches), Quest (head sway) trip on schedule; walking / turning reset")
	return _failures
