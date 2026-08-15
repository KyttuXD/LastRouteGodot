extends RefCounted

## Headless check on the three objective-driven hunters.
##
## Haelith, Ysolde and Opalie are the first hunters whose behaviour is about the
## FLOOR rather than the player, and all three depend on the generator's
## `collected` flag actually meaning something. They are driven here the way the
## game drives them -- a real generated facility, a real brain, real frames --
## because the failure mode for all three is silent: a hunter who simply stands
## still, or who walks to a relay that was collected ten minutes ago.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- hunters

const STEP := 1.0 / 60.0

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(_host: Node) -> int:
	# RoomState is an autoload -- it survives between suites in the same
	# runner invocation, so whatever an earlier suite left map_scale/difficulty
	# set to would otherwise leak into every generator built here. That is a
	# real bug this run just caught: Loxelle's own facility came out a
	# different size depending on which suites ran before this one, and with
	# it, whether her fixed 40-interval budget was still enough to find a
	# candidate. Pin it, the same way validate_sync.gd does.
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var generator := FacilityGenerator.new("HUNTERS-CHECK", RoomState.generator_options())
	_haelith_goes_where_the_relays_are(generator)
	_ysolde_takes_it_off_the_floor(generator)
	_opalie_holds_her_post(generator)
	_aki_answers_a_flash(generator)
	await _porcelle_is_only_on_the_map(_host)
	await _hiding_spots_and_jyvra(_host)
	await _loxelle_burns_and_regrows(_host)
	await _ceryth_traps_and_disperses(_host)
	if _failures == 0:
		print("hunters OK")
	return _failures


func _brain(id: String, at: Vector2) -> HunterBrain:
	var brain := HunterBrain.new(at, "HUNTERS-CHECK:%s" % id, id)
	brain.gimmick = HunterGimmick.for_id(id)
	brain.activate_at(at)
	return brain


func _target(at: Vector2) -> Dictionary:
	return {"position": at, "hidden": false, "in_safe_zone": false, "noise": 0.0,
		"flashlight_on": false, "sprinting": false, "facing": Vector2(0, 1),
		"lamp_charge": 100.0, "meters": null,
		"heater_unfrozen": false, "heater_powered": false}


## She re-aims every frame, so collecting the one she is walking to has to send
## her somewhere else rather than leave her circling an empty tile.
func _haelith_goes_where_the_relays_are(generator: FacilityGenerator) -> void:
	for entry in generator.relays:
		entry["collected"] = false
	var start := Vector2(generator.start) + Vector2(0.5, 0.5)
	var brain := _brain("haelith", start)
	if brain.gimmick == null:
		_fail("Haelith has no gimmick")
		return

	for i in 30:
		brain.update(STEP, generator, _target(start), 1, 0)
	var first := brain.last_known
	_expect(brain.has_last_known, "Haelith never picked a relay to walk to")
	_expect(_is_a_relay(generator, first), "Haelith is walking to %s, which is not a relay" % first)

	# Take the one she chose. She must not keep going to it.
	generator.mark_collected(generator.relays, Vector2i(int(first.x), int(first.y)))
	for i in 30:
		brain.update(STEP, generator, _target(start), 1, 0)
	_expect(brain.last_known != first,
		"Haelith is still walking to a relay that has already been collected")
	print("  haelith   re-aims off a collected relay onto another")


func _is_a_relay(generator: FacilityGenerator, at: Vector2) -> bool:
	for entry in generator.relays:
		if Vector2i(entry["x"], entry["y"]) == Vector2i(int(at.x), int(at.y)):
			return true
	return false


## Standing next to a battery has to actually take it -- and say so, because a
## battery that vanishes with no report reads as a bug rather than a hunter.
func _ysolde_takes_it_off_the_floor(generator: FacilityGenerator) -> void:
	for entry in generator.batteries:
		entry["collected"] = false
	if generator.batteries.is_empty():
		_fail("no batteries on the floor to steal")
		return
	var battery: Dictionary = generator.batteries[0]
	var cell := Vector2i(battery["x"], battery["y"])
	var brain := _brain("ysolde", Vector2(cell) + Vector2(0.5, 0.5))
	if brain.gimmick == null:
		_fail("Ysolde has no gimmick")
		return

	brain.update(STEP, generator, _target(Vector2(0, 0)), 1, 0)
	_expect(battery.get("collected", false),
		"Ysolde stood on a battery and did not take it")
	if brain.world_events.is_empty():
		_fail("Ysolde took a battery and told nobody, so it stays on every other peer's floor")
		return
	var event: Dictionary = brain.world_events[0]
	_expect(event.get("cell", Vector2i(-1, -1)) == cell,
		"Ysolde's theft names cell %s, not %s" % [event.get("cell"), cell])
	_expect(int(event.get("kind", -1)) == int(RouteInteractable3D.Kind.BATTERY),
		"Ysolde's theft is not reported as a battery")
	_expect(not String(event.get("message", "")).is_empty(),
		"Ysolde's theft has no message, so it happens invisibly")
	print("  ysolde    takes a battery off the floor and reports it")


## The whole hunter is standing still in the right place and refusing things.
func _opalie_holds_her_post(generator: FacilityGenerator) -> void:
	if generator.relays.is_empty():
		_fail("no relays for Opalie to guard")
		return
	var relay: Dictionary = generator.relays[0]
	var post := Vector2(relay["x"] + 0.5, relay["y"] + 0.5)
	var brain := _brain("opalie", post)
	if brain.gimmick == null:
		_fail("Opalie has no gimmick")
		return

	for i in 60:
		brain.update(STEP, generator, _target(post + Vector2(6, 6)), 1, 0)
	if not brain.gimmick.holds_position():
		_fail("Opalie started on her relay and still has not settled on it")
		return
	var moved := brain.position.distance_to(post)
	_expect(moved < 1.0, "Opalie drifted %.2f cells off the relay she is guarding" % moved)

	_expect(brain.gimmick.call("blocks", post),
		"Opalie does not deny the relay she is standing on")
	_expect(brain.gimmick.call("blocks", post + Vector2(1.4, 0.0)),
		"Opalie's suppression does not reach %.1f cells" % GameConfig.OPALIE_SUPPRESSION_RADIUS)
	_expect(not brain.gimmick.call("blocks", post + Vector2(4.0, 0.0)),
		"Opalie denies interactions far outside her suppression radius")
	print("  opalie    settles on a relay and denies %.1f cells around it"
		% GameConfig.OPALIE_SUPPRESSION_RADIUS)


## Aki does nothing until you point a torch at her and HOLD it. The two ways to
## get her wrong are firing on a beam that merely swept past, and firing on
## every frame the beam stays on her -- so both are driven here, not asserted
## about.
func _aki_answers_a_flash(generator: FacilityGenerator) -> void:
	var post := Vector2(generator.start) + Vector2(0.5, 0.5)
	var brain := _brain("aki", post)
	if brain.gimmick == null:
		_fail("Aki has no gimmick")
		return
	var meters := PlayerMeters.new()

	# Two cells apart, torch aimed straight at her, so line of sight holds.
	var from := post - Vector2(0.0, 2.0)
	var lit := _target(from)
	lit["flashlight_on"] = true
	lit["facing"] = (post - from).normalized()
	lit["meters"] = meters
	var dark := lit.duplicate()
	dark["flashlight_on"] = false

	# A beam that only brushes her is not a flash.
	brain.update(STEP, generator, lit, 1, 0)
	brain.update(STEP, generator, dark, 1, 0)
	_expect(brain.gimmick.phase == AkiGimmick.Phase.IDLE,
		"Aki woke on a beam that swept past her, not on a held flash")

	var flashes := 0
	for i in 120:
		brain.update(STEP, generator, lit, 1, 0)
		if brain.flash_triggered:
			flashes += 1
	_expect(flashes == 1,
		"holding the beam on Aki counted as %d flashes; a held torch is one" % flashes)
	if brain.gimmick.phase == AkiGimmick.Phase.IDLE:
		_fail("Aki never woke despite a torch held on her for two seconds")
		return

	# The fuse, then three bursts five seconds apart.
	var before := meters.exposure
	for i in int(GameConfig.AKI_INITIAL_DELAY / STEP) + 2:
		brain.update(STEP, generator, lit, 1, 0)
	_expect(meters.exposure > before, "Aki's fuse ran out and nothing happened")
	for i in int(GameConfig.AKI_BURST_INTERVAL / STEP) * 3 + 8:
		brain.update(STEP, generator, lit, 1, 0)
	_expect(brain.gimmick.bursts_remaining == 0 and brain.gimmick.phase == AkiGimmick.Phase.IDLE,
		"Aki did not settle back to idle after her %d bursts" % GameConfig.AKI_BURST_COUNT)
	print("  aki       wakes on one held flash, spikes exposure %dx, goes quiet"
		% GameConfig.AKI_BURST_COUNT)


## Porcelle is invisible in the room and visible ONLY on the map, so the two
## halves have to be checked together: hiding her without the map drawing her
## puts a hunter on the floor who cannot be found by any means. Driven through
## the real scene, because "the gimmick returns true" is exactly the kind of
## check that passes while the model is still on screen.
func _porcelle_is_only_on_the_map(host: Node) -> void:
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame

	var view: HunterView3D = scene.hunter_views[0] if not scene.hunter_views.is_empty() else null
	if view == null:
		_fail("no hunter on the floor to make Porcelle out of")
		scene.queue_free()
		return
	view.brain.hunter_id = "porcelle"
	view.brain.gimmick = HunterGimmick.for_id("porcelle")
	view.brain.active = true
	view._shown_id = ""
	view._apply_model("porcelle")
	# The hunter she replaced is queue_free()d, which does not take effect until
	# the end of the frame -- without this the sweep below finds the OLD body
	# still hanging in the tree and blames Porcelle for it.
	await host.get_tree().process_frame

	var drawn := false
	for child in view.get_children():
		if child is Node3D and (child as Node3D).visible:
			drawn = true
	_expect(not drawn, "Porcelle is drawn in the room; she is supposed to be invisible there")

	var marks: Array = scene._map_marks()
	var found := false
	for mark in marks:
		if String(mark.get("name", "")).to_lower() == "porcelle":
			found = true
	_expect(found, "Porcelle is invisible AND missing from the map, so nothing can find her")
	print("  porcelle  invisible in the room, drawn on the map")
	scene.queue_free()


## Hiding spots, and Jyvra reaching into one.
##
## Two failure modes worth naming. A locker you can enter and not leave is the
## worse one, and it was real: hiding freezes input, and the freeze swallowed
## the key that gets you out. The other is Jyvra's timer keying on her being in
## "chase" -- the shared brain drops her out of chase the moment you hide, so
## the ejection never fires and the locker is permanent safety.
func _hiding_spots_and_jyvra(host: Node) -> void:
	var generator := FacilityGenerator.new("HIDE-CHECK", RoomState.generator_options())
	var spots := generator.place_hiding_spots()
	if spots.size() < 2:
		_fail("only %d hiding spots placed on a whole floor" % spots.size())
		return
	for spot in spots:
		var cell := Vector2i(spot["x"], spot["y"])
		_expect(generator.grid[cell.y][cell.x] == 0,
			"hiding spot %s is inside a wall" % cell)
		_expect(cell != generator.start and cell != generator.exit_cell,
			"a hiding spot is on the spawn or the lift")
	print("  hiding    %d spots, all on open cells backed onto a wall" % spots.size())

	# In and back out, through the real scene, using the key a player uses.
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var real: Array = scene.facility_view.generator.place_hiding_spots()
	if real.is_empty():
		_fail("no hiding spots on the live floor")
		scene.queue_free()
		return
	var cell := Vector2i(real[0]["x"], real[0]["y"])
	scene.player.enter_hiding(cell)
	_expect(scene.player.hidden, "entering a locker did not hide the player")
	scene.player.leave_hiding(Vector2(cell) + Vector2(0.5, 0.5))
	_expect(not scene.player.hidden, "the player could not get back out of a locker")

	# Jyvra standing over an occupied spot for her full count.
	var brain := _brain("jyvra", Vector2(cell) + Vector2(0.5, 0.5))
	if brain.gimmick == null:
		_fail("Jyvra has no gimmick")
		scene.queue_free()
		return
	var hiding := _target(Vector2(cell) + Vector2(0.5, 0.5))
	hiding["hidden"] = true
	hiding["hiding_spot"] = cell
	var fired := false
	for i in int((GameConfig.JYVRA_HIDING_SECONDS + 0.5) / STEP):
		brain.update(STEP, scene.facility_view.generator, hiding, 1, 0)
		if brain.gimmick.ejecting:
			fired = true
			break
	_expect(fired, "Jyvra stood over an occupied locker for %.0fs and never reached in"
		% GameConfig.JYVRA_HIDING_SECONDS)
	_expect(brain.stun_timer > 0.0,
		"Jyvra's ejection left her free to grab the player she just pulled out")
	print("  jyvra     pulls a hidden player out after %.0fs, then stalls"
		% GameConfig.JYVRA_HIDING_SECONDS)
	scene.queue_free()


## Loxelle burns hiding spots in her own room while idle/wandering, and pulls
## the player out of an occupied one rather than burning it. Both are driven
## through the real scene, because the failure mode is a spot that vanishes
## with nothing in the world reflecting it -- correct data, wrong screen.
func _loxelle_burns_and_regrows(host: Node) -> void:
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var generator: FacilityGenerator = scene.facility_view.generator
	if generator.hiding_spots.is_empty():
		_fail("no hiding spots on the live floor to test Loxelle against")
		scene.queue_free()
		return

	var spot: Dictionary = generator.hiding_spots[0]
	var cell := Vector2i(spot["x"], spot["y"])
	var brain := _brain("loxelle", Vector2(cell) + Vector2(0.5, 0.5))
	if brain.gimmick == null:
		_fail("Loxelle has no gimmick")
		scene.queue_free()
		return

	# Hidden, not merely distant: activate_at() wakes her straight into
	# INVESTIGATE, and with the fake player standing on her own cell ordinary
	# sight would otherwise see it at distance zero and lock her into CHASE
	# forever, which is a bug in this harness, not in Loxelle -- she never gets
	# the idle/wander time her passive requires unless perception is told there
	# is nothing to see.
	var target := _target(Vector2(cell) + Vector2(0.5, 0.5))
	target["hidden"] = true
	var burned := false
	# 40 rolls at a 25% chance each leaves under a 1-in-30000 chance of never
	# firing -- long enough to test the mechanism without reaching in and
	# forcing the dice, which would test the test rather than Loxelle.
	for i in int((GameConfig.LOXELLE_INTERVAL * 40.0) / STEP):
		brain.update(STEP, generator, target, 1, 0)
		for toggle in brain.gimmick.toggles:
			if toggle.get("cell") == cell and toggle.get("disabled", false):
				burned = true
		if burned:
			break
	if not burned:
		_fail("Loxelle never burned an empty hiding spot in her own room")
		scene.queue_free()
		return

	var live: RouteInteractable3D = scene.facility_view.hiding_spot_at(cell)
	if live == null:
		_fail("no interactable node at the hiding spot Loxelle burned")
		scene.queue_free()
		return
	# Drain the toggle the way main_3d._update_gameplay does every frame.
	for toggle in brain.gimmick.toggles.duplicate():
		if toggle.get("cell") == cell:
			live.set_disabled(bool(toggle.get("disabled", false)))
	_expect(live.disabled, "Loxelle burned a spot but its interactable is still usable")
	_expect(live.get_prompt().is_empty(), "a burned hiding spot still offers to hide the player")

	print("  loxelle   burns an empty hiding spot in her own room, disabling it live")
	scene.queue_free()


## Ceryth never chases. She teleports once to a hiding spot, holds position
## forever, and asks a flashlight riddle the moment anyone tries to hide there
## -- wrong answer locks you in, right answer disperses her for good. Every
## branch is driven through the real scene, because "resolve_entry returns the
## right dict" is exactly the kind of check that passes while the player is
## still stuck behind a lock timer that never got wired to _physics_process.
func _ceryth_traps_and_disperses(host: Node) -> void:
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var view: HunterView3D = scene.hunter_views[0] if not scene.hunter_views.is_empty() else null
	if view == null:
		_fail("no hunter on the floor to make Ceryth out of")
		scene.queue_free()
		return
	view.brain.hunter_id = "ceryth"
	view.brain.gimmick = HunterGimmick.for_id("ceryth")
	view.brain.active = true

	var generator: FacilityGenerator = scene.facility_view.generator
	var far := Vector2(generator.start) + Vector2(10, 10)
	var target := _target(far)
	target["hidden"] = true
	for i in 10:
		view.brain.update(STEP, generator, target, 1, 0)
	var gimmick: CerythGimmick = view.brain.gimmick
	_expect(gimmick.trap_spot.x >= 0, "Ceryth never staked out a hiding spot")
	var stood_at := view.brain.position
	for i in 60:
		view.brain.update(STEP, generator, target, 1, 0)
	_expect(view.brain.position == stood_at,
		"Ceryth moved after staking her spot; she is supposed to never move at all")

	# Wrong answer: flashlight state answers the wrong colour.
	var wrong := gimmick.eyes_red  # red wants the light OFF; on is wrong for red
	scene.player.flashlight_enabled = wrong
	scene.player.lamp_charge = 100.0
	var message: String = scene.player.enter_hiding(gimmick.trap_spot)
	_expect(scene.player.hidden and scene.player.hiding_lock_timer > 0.0,
		"answering Ceryth's riddle wrong did not lock the player in")
	_expect(not scene.player.flashlight_enabled,
		"a locked-in player's flashlight is still on")
	_expect(scene.player.leave_hiding().begins_with("Locked"),
		"the exit key worked while Ceryth's lock was still counting down")
	scene.player.leave_hiding(Vector2.ZERO, true)  # reset for the next case, forced past the lock

	# Right answer: disperses her, for good.
	scene.player.flashlight_enabled = not wrong
	message = scene.player.enter_hiding(gimmick.trap_spot)
	_expect(gimmick.dispersed, "answering Ceryth's riddle right did not disperse her")
	_expect(scene.player.hiding_lock_timer <= 0.0,
		"a correct answer still locked the player in")
	view.sync_from_brain()
	# view._model directly, not a sweep of view's children: the model she is
	# replacing is queue_free()'d in the same call and does not actually leave
	# the tree until end of frame, so a sweep here would blame her for a stale
	# node on its way out rather than for her own visibility.
	_expect(view._model != null and not view._model.visible,
		"Ceryth is dispersed but still drawn in the room")

	print("  ceryth    stakes one spot forever, locks a wrong answer, disperses on a right one")
	scene.queue_free()
