extends RefCounted

## Crowbar and rescue axe hits on a hunter: the profile values (longer than a taser or a grab break-free, falling with the
## mode), MeleeStrike's rules, the stun kind on HunterBrain (the longest stun wins and carries its kind, a shorter one never
## downgrades a heavy one), the world-state round trip that carries the kind to guests, the reach rule, the replicated intent
## whitelist, and the heavy reel on HunterView3D (only while it holds, never for other stuns, sleep or a grab).
## The host's acceptance and the press-time probe need a running route; they are covered by hunter_real and the co-op runs.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- melee_stun

var _failures := 0


class StubNav extends RefCounted:
	var clear := true

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return clear


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _brain(hunter_id: String = "dovelle") -> HunterBrain:
	var brain := HunterBrain.new(Vector2(5, 5), "MELEE-TEST", hunter_id, "standard")
	brain.activate_at(Vector2(5, 5))
	brain.state = HunterBrain.State.WANDER
	return brain


func run(host: Node) -> int:
	var tree := host.get_tree()
	var modes := ["relaxed", "standard", "hard", "nightmare"]

	# ---- profile values: a crowbar or axe hit outlasts a taser and a grab break-free, and both fall as the mode rises
	for id in modes:
		var taser := GameConfig.profile_value(id, "taser_stun")
		var grab := GameConfig.profile_value(id, "escape_stun")
		var crowbar := GameConfig.profile_value(id, "crowbar_stun")
		var axe := GameConfig.profile_value(id, "axe_stun")
		_expect(crowbar > taser and crowbar > grab,
			"%s: crowbar stun %.2f must outlast the taser %.2f and the grab %.2f" % [id, crowbar, taser, grab])
		_expect(axe > crowbar, "%s: axe stun %.2f must outlast the crowbar %.2f" % [id, axe, crowbar])
	for i in range(1, modes.size()):
		for key in ["crowbar_stun", "axe_stun"]:
			_expect(GameConfig.profile_value(modes[i], key) <= GameConfig.profile_value(modes[i - 1], key),
				"%s falls with the mode (%s)" % [key, modes[i]])

	# ---- MeleeStrike rules
	_expect(is_equal_approx(MeleeStrike.stun_seconds("crowbar", "standard"), GameConfig.profile_value("standard", "crowbar_stun")),
		"the crowbar stun comes from its profile key")
	_expect(is_equal_approx(MeleeStrike.stun_seconds("rescue_axe", "hard"), GameConfig.profile_value("hard", "axe_stun")),
		"the axe stun comes from its profile key")
	_expect(MeleeStrike.stun_seconds("taser", "standard") == 0.0, "a taser is not a melee hit")
	_expect(MeleeStrike.handles("crowbar") and MeleeStrike.handles("rescue_axe"), "the crowbar and axe hit hunters")
	_expect(not MeleeStrike.handles("taser") and not MeleeStrike.handles("flashlight") and not MeleeStrike.handles(""),
		"other items do not hit hunters")
	_expect(MeleeStrike.STUN_KIND_HEAVY == "heavy", "the heavy kind keeps its replicated name")

	# ---- stun kinds on the brain: the longest stun wins and carries its kind
	var brain := _brain()
	brain.apply_stun(4.0, MeleeStrike.STUN_KIND_HEAVY)
	_expect(brain.stun_kind == "heavy" and is_equal_approx(brain.stun_timer, 4.0), "a heavy hit sets the kind and the timer")
	brain.apply_stun(2.7)
	_expect(brain.stun_kind == "heavy" and is_equal_approx(brain.stun_timer, 4.0),
		"a shorter taser does not downgrade a running heavy stun")
	brain.stun_timer = 1.0
	brain.apply_stun(2.7)
	_expect(brain.stun_kind == "" and is_equal_approx(brain.stun_timer, 2.7),
		"a longer taser takes the kind of the stun that now wins")
	brain.stun_timer = 0.0
	brain.apply_stun(2.0)
	brain.apply_stun(5.0, MeleeStrike.STUN_KIND_HEAVY)
	_expect(brain.stun_kind == "heavy" and is_equal_approx(brain.stun_timer, 5.0),
		"a heavy hit switches the kind over a shorter generic stun")
	brain.apply_stun(1.0e6)
	_expect(brain.stun_kind == "" and brain.stun_timer > 1000.0, "the admin freeze is a plain stun")

	# ---- replication: the host's stored hunter carries the kind to a guest's copy
	var host_world := StreamedWorldState.new()
	var source := _brain()
	source.apply_stun(GameConfig.profile_value("standard", "crowbar_stun"), MeleeStrike.STUN_KIND_HEAVY)
	host_world.store_hunter("MELEE:HUNTER:1", source, 0, Vector3i.ZERO)
	var reported := host_world.hunter_state("MELEE:HUNTER:1")
	var guest := _brain()
	var guest_world := StreamedWorldState.new()
	guest_world.restore_hunter(guest, reported)
	_expect(guest.stun_kind == "heavy" and is_equal_approx(guest.stun_timer, source.stun_timer),
		"a guest restores the heavy stun with its length")
	var plain := _brain()
	plain.apply_stun(2.7)
	host_world.store_hunter("MELEE:HUNTER:2", plain, 0, Vector3i.ZERO)
	var plain_guest := _brain()
	guest_world.restore_hunter(plain_guest, host_world.hunter_state("MELEE:HUNTER:2"))
	_expect(plain_guest.stun_kind == "", "a taser stun reaches a guest with no kind")

	# ---- hit immunity (HunterBrain.melee_hit): a hunter who is not melee immune (Dovelle's file, the default) takes the swing
	# as a heavy stun; a melee-immune one does not (hunter_immunity covers the immune side and the pack path)
	var struck := _brain()
	_expect(struck.melee_hit(MeleeStrike.stun_seconds("rescue_axe", "standard")) and struck.stun_kind == MeleeStrike.STUN_KIND_HEAVY,
		"an axe swing does not stun a hunter who is not melee immune")
	_expect(_brain().melee_hit(MeleeStrike.stun_seconds("crowbar", "standard")), "a crowbar swing does not stun Dovelle")

	# ---- reach: in reach, in front, with a clear line
	var nav := StubNav.new()
	var hunter := _brain()
	var aim := Vector2(1, 0)
	var swinger := Vector2(5, 5) - Vector2(1.5, 0)
	_expect(MeleeStrike.can_strike(hunter, swinger, aim, nav), "a hunter 1.5 m in front is struck")
	_expect(not MeleeStrike.can_strike(hunter, swinger, -aim, nav), "a hunter behind the swing is not struck")
	_expect(not MeleeStrike.can_strike(hunter, Vector2(5, 5) - Vector2(4.0, 0), aim, nav), "a hunter beyond melee reach is not struck")
	nav.clear = false
	_expect(not MeleeStrike.can_strike(hunter, swinger, aim, nav), "a wall between swinger and hunter stops the swing")
	nav.clear = true
	_expect(not MeleeStrike.can_strike(hunter, swinger, aim, null), "no navigation, no strike")
	_expect(not MeleeStrike.can_strike(null, swinger, aim, nav), "no hunter, no strike")

	# ---- replicated intent: the guest request is on the whitelist
	_expect(RemotePlayers.GUEST_INTERACTIONS.has("stream_hunter_strike"), "stream_hunter_strike is a guest interaction")

	# ---- the view: a heavy stun reels her, other stuns do not, and she rights herself when it ends
	var view := HunterView3D.new()
	view.brain = _brain("dovelle")
	host.add_child(view)
	await tree.process_frame
	view.sync_from_brain()
	_expect(view._model != null, "the view has a model to reel")
	if view._model != null:
		view.brain.apply_stun(3.0)
		for _i in 30:
			view._update_heavy_stun_pose(1.0 / 30.0)
		_expect(absf(view._model.rotation.x) < .001, "a plain stun does not reel her")
		view.brain.stun_timer = 0.0
		view.brain.apply_stun(3.0, MeleeStrike.STUN_KIND_HEAVY)
		for _i in 30:
			view._update_heavy_stun_pose(1.0 / 30.0)
		_expect(view._model.rotation.x > HunterView3D.HEAVY_STUN_LEAN * .6,
			"a heavy stun reels her (lean %.3f)" % view._model.rotation.x)
		view._update_stars(.016)
		_expect(view._stars != null and view._stars.visible and view._stars_heavy,
			"the stars under a heavy stun use the heavy colour")
		view.brain.stun_timer = 0.0
		for _i in 90:
			view._update_heavy_stun_pose(1.0 / 30.0)
		_expect(absf(view._model.rotation.x) < .001, "she rights herself when the heavy stun ends")
		view.brain.apply_stun(3.0, MeleeStrike.STUN_KIND_HEAVY)
		view._asleep = true
		for _i in 30:
			view._update_heavy_stun_pose(1.0 / 30.0)
		_expect(absf(view._model.rotation.x) < .001, "a sleeping hunter is not reeled")
		view._asleep = false
		view.brain.stun_timer = 0.0
		for _i in 90:
			view._update_heavy_stun_pose(1.0 / 30.0)
	view.queue_free()
	await tree.process_frame

	if _failures == 0:
		print("  melee     crowbar/axe profile values, MeleeStrike rules, heavy stun kind on brain and guests, reach, whitelist, reel view")
	return _failures
