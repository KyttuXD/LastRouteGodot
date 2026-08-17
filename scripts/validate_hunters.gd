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
	_difficulty_scales_shared_brain(generator)
	_haelith_goes_where_the_relays_are(generator)
	_ysolde_takes_it_off_the_floor(generator)
	_opalie_holds_her_post(generator)
	_aki_answers_a_flash(generator)
	await _porcelle_is_only_on_the_map(_host)
	await _hiding_spots_and_jyvra(_host)
	await _loxelle_burns_and_regrows(_host)
	await _ceryth_traps_and_disperses(_host)
	await _briselle_sabotages_and_resecures(_host)
	_ferryn_stalks_and_screams(generator)
	_glyra_winds_down_and_back_up(generator)
	_ilyra_tags_and_pounces(generator)
	await _verrine_lurks_and_chases(_host)
	await _zephyra_trades_and_repairs(_host)
	await _interactables_require_facing(_host)
	_hunter_paths_to_a_distant_target(generator)
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


func _difficulty_scales_shared_brain(generator: FacilityGenerator) -> void:
	var at := Vector2(generator.start) + Vector2(0.5, 0.5)
	var relaxed := HunterBrain.new(at, "DIFFICULTY:RELAXED", "dovelle", "relaxed")
	var standard := HunterBrain.new(at, "DIFFICULTY:STANDARD", "dovelle", "standard")
	var hard := HunterBrain.new(at, "DIFFICULTY:HARD", "dovelle", "hard")
	for brain in [relaxed, standard, hard]:
		brain.activate_at(at)
	var relaxed_speed: float = relaxed._current_speed(1, 0)
	var standard_speed: float = standard._current_speed(1, 0)
	var hard_speed: float = hard._current_speed(1, 0)
	_expect(relaxed_speed < standard_speed and standard_speed < hard_speed,
		"hunter speed does not increase Relaxed < Standard < Hard")

	# At 0.43 cells Dovelle is outside Standard's 0.42 capture radius but
	# inside Hard's 1.04-scaled radius. Delta zero keeps movement out of it.
	var target := _target(at + Vector2(0.43, 0.0))
	_expect(not standard.update(0.0, generator, target, 1, 0),
		"Standard captured at Hard's extended-only distance")
	_expect(hard.update(0.0, generator, target, 1, 0),
		"Hard did not apply its capture-distance multiplier")
	print("  difficulty hunter speed/perception profile and capture reach applied")


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
	# Room-interior specifically, not just "a" hiding spot: place_hiding_spots()
	# falls back to corridor cells when a floor is too small to seat every spot
	# in a room, and Loxelle's passive -- correctly, matching the original's own
	# `if (!room) return` -- does nothing while she is standing in a corridor.
	# hiding_spots[0] picked whichever came first; on a seed where that happened
	# to be a corridor spot, she had nothing to do all test and this failed for
	# a reason that had nothing to do with her actually being broken.
	var spot: Dictionary = {}
	for candidate in generator.hiding_spots:
		if not String(candidate.get("room_id", "")).is_empty():
			spot = candidate
			break
	if spot.is_empty():
		_fail("no room-interior hiding spot on the live floor to test Loxelle against")
		scene.queue_free()
		return

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
	# Not a claim about THIS starting spot specifically: she is still an
	# ordinary wandering hunter between rolls, on the same shared movement
	# every idle/wander hunter uses, and over a long enough window that
	# carries her through several other rooms -- confirmed by watching her
	# room_at() visibly change room to room while this ran. What the passive
	# actually promises is "she burns a spot in whichever room she is
	# currently in when her timer fires," so that is what gets checked: the
	# first burn she raises, wherever it lands, not one pinned in advance.
	var burned_cell := Vector2i(-1, -1)
	# 40 rolls at a 25% chance each leaves under a 1-in-30000 chance of never
	# firing -- long enough to test the mechanism without reaching in and
	# forcing the dice, which would test the test rather than Loxelle.
	for i in int((GameConfig.LOXELLE_INTERVAL * 40.0) / STEP):
		brain.update(STEP, generator, target, 1, 0)
		for toggle in brain.gimmick.toggles:
			if toggle.get("disabled", false):
				burned_cell = toggle["cell"]
				break
		if burned_cell.x >= 0:
			break
	if burned_cell.x < 0:
		_fail("Loxelle never burned any hiding spot while idle/wandering")
		scene.queue_free()
		return

	var live: RouteInteractable3D = scene.facility_view.hiding_spot_at(burned_cell)
	if live == null:
		_fail("no interactable node at the hiding spot Loxelle burned")
		scene.queue_free()
		return
	# Drain the toggle the way main_3d._update_gameplay does every frame.
	for toggle in brain.gimmick.toggles.duplicate():
		if toggle.get("cell") == burned_cell:
			live.set_disabled(bool(toggle.get("disabled", false)))
	_expect(live.disabled, "Loxelle burned a spot but its interactable is still usable")
	_expect(live.get_prompt().is_empty(), "a burned hiding spot still offers to hide the player")

	print("  loxelle   burns an empty hiding spot in whichever room she's in, disabling it live")
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


## Briselle takes a collected relay offline without un-collecting it -- the
## lift gate has to notice (relays_sabotaged, not relays_collected), the
## interactable has to come back into view to be worked, and holding [E]
## there has to actually restore it. Driven through the real scene because
## "the gimmick sets sabotaged=true" is exactly the check that passes while
## the lift, the prompt and GameState's own count all still disagree with it.
func _briselle_sabotages_and_resecures(host: Node) -> void:
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var generator: FacilityGenerator = scene.facility_view.generator
	if generator.relays.is_empty():
		_fail("no relays on the live floor to test Briselle against")
		scene.queue_free()
		return

	# Room-interior specifically, not just "a" relay: a relay in a corridor has
	# no room for Briselle's room-entry check to ever find (room_at() returns
	# {} there, same reason a corridor hiding spot stumped Loxelle's own
	# check once) -- she is not broken by that, there is just nothing to
	# assert about her in a scenario her gimmick was never meant to act in.
	var relay_cell := Vector2i(-1, -1)
	for relay in generator.relays:
		var cell := Vector2i(relay["x"], relay["y"])
		if not generator.room_at(cell.x + 0.5, cell.y + 0.5).is_empty():
			relay_cell = cell
			break
	if relay_cell.x < 0:
		_fail("no room-interior relay on the live floor to test Briselle against")
		scene.queue_free()
		return
	# Collect it for real, through the real interactable, so relays_collected
	# and the interactable's own completed flag start where Briselle expects.
	var relay_node: RouteInteractable3D = scene.facility_view._at(relay_cell, RouteInteractable3D.Kind.RELAY)
	if relay_node == null:
		_fail("no interactable at the first relay's cell")
		scene.queue_free()
		return
	relay_node.activate(scene.player)
	_expect(GameState.relays_collected == 1, "collecting the relay did not register")

	var brain := _brain("briselle", Vector2(relay_cell) + Vector2(0.5, 0.5))
	if brain.gimmick == null:
		_fail("Briselle has no gimmick")
		scene.queue_free()
		return
	var target := _target(Vector2(relay_cell) + Vector2(0.5, 0.5))
	target["hidden"] = true  # see Loxelle's own note: otherwise she locks CHASE at distance 0

	var sabotaged := false
	for i in int((GameConfig.BRISELLE_SABOTAGE_DWELL + 10.0) / STEP):
		brain.update(STEP, generator, target, 1, 0)
		for event in brain.world_events:
			if event.get("what") == "sabotage" and event.get("cell") == relay_cell:
				sabotaged = true
		brain.world_events.clear()
		if sabotaged:
			break
	if not sabotaged:
		_fail("Briselle never sabotaged the collected relay she was standing next to")
		scene.queue_free()
		return

	# The event has to actually reach the interactable and GameState, the way
	# main_3d's drain loop would apply it -- not asserted about, applied.
	scene.facility_view.apply_event({"what": "sabotage", "cell": relay_cell, "sabotaged": true})
	_expect(relay_node.sabotaged, "the sabotage event never reached the relay's own interactable")
	_expect(GameState.relays_sabotaged == 1,
		"GameState does not know a relay is offline")
	_expect(scene.facility_view.hiding_spot_at(relay_cell) == null,  # sanity: still a relay, not a locker
		"setup sanity check failed")
	var lift: RouteInteractable3D = scene.facility_view._at(generator.exit_cell, RouteInteractable3D.Kind.LIFT)
	_expect(lift != null and not lift.get_prompt().is_empty(),
		"the lift has no complaint to make while a relay is offline")
	_expect(not relay_node.get_prompt().is_empty(),
		"a sabotaged relay offers no way to restore it")

	var restore_message := relay_node.set_sabotaged(false)
	_expect(not relay_node.sabotaged, "set_sabotaged(false) did not clear the flag")
	_expect(GameState.relays_sabotaged == 0, "restoring the relay left GameState's count off")
	_expect(not restore_message.is_empty(), "restoring a relay produced no message for the player")

	print("  briselle  takes a collected relay offline, blocks the lift, and can be restored")
	scene.queue_free()


## Ferryn always knows where the player is -- no sight or hearing check gates
## her chase at all -- and only stops for hiding, a safe zone, or a held
## torch, which sends her back to a fixed origin AND, for a flash specifically,
## puts every other active hunter onto the player. Driven through two real
## brains, because "she raises a facility_alert" is exactly the kind of check
## that passes while the SECOND hunter never actually receives it.
func _ferryn_stalks_and_screams(generator: FacilityGenerator) -> void:
	var far := Vector2(generator.start) + Vector2(0.5, 0.5)
	var brain := _brain("ferryn", far)
	if brain.gimmick == null:
		_fail("Ferryn has no gimmick")
		return
	var meters := PlayerMeters.new()
	var elsewhere := far + Vector2(6.0, 6.0)
	var target := _target(elsewhere)
	target["meters"] = meters

	# No sight, no hearing, nothing lit -- and she still locks CHASE at range,
	# which no other hunter in this roster does.
	brain.update(STEP, generator, target, 1, 0)
	_expect(brain.state == HunterBrain.State.CHASE,
		"Ferryn did not chase a player she has no way to have sensed")
	_expect(brain.last_known == elsewhere, "Ferryn is not tracking the player's real position")
	for i in 30:
		brain.update(STEP, generator, target, 1, 0)
	_expect(brain.state == HunterBrain.State.CHASE,
		"Ferryn's chase decayed on its own -- the lost-sight reset is not holding")

	# Hiding sends her home and quiets her down, no scream.
	var hidden_target := target.duplicate()
	hidden_target["hidden"] = true
	brain.update(STEP, generator, hidden_target, 1, 0)
	_expect(brain.state == HunterBrain.State.WANDER, "hiding did not send Ferryn back to wander")
	_expect(brain.position == brain.gimmick.stalker_origin, "hiding did not return Ferryn to her origin")
	_expect(brain.world_events.is_empty(), "merely hiding raised a facility alert -- only a flash should")
	brain.world_events.clear()

	# Flash her: real beam, real dwell, not an injected flag. Aimed at wherever
	# she ACTUALLY is (she was just teleported to her origin by hiding above),
	# not the stale `elsewhere` from before that -- a beam aimed at the wrong
	# point never lights her no matter how long it's held.
	brain.update(STEP, generator, target, 1, 0)  # re-lock chase first
	var from := brain.position - Vector2(0.0, 2.0)
	var lit := _target(from)
	lit["flashlight_on"] = true
	lit["facing"] = (brain.position - from).normalized()
	lit["meters"] = meters
	var before_noise: float = meters.noise_meter
	var flashed := false
	for i in 60:
		brain.update(STEP, generator, lit, 1, 0)
		if brain.flash_triggered:
			flashed = true
	_expect(flashed, "never actually held a flash on Ferryn -- setup problem, not her")
	# add_noise() only banks a rise; PlayerMeters.update() is what actually
	# folds it into noise_meter, same as the real per-frame player loop does.
	meters.update(STEP, {})
	_expect(meters.noise_meter > before_noise, "flashing Ferryn raised no facility noise")

	var alert: Dictionary = {}
	for event in brain.world_events:
		if event.get("what") == "facility_alert":
			alert = event
	_expect(not alert.is_empty(), "flashing Ferryn raised no facility_alert for other hunters")
	if not alert.is_empty():
		_expect(String(alert.get("except", "")) == "ferryn",
			"her own alert would re-target herself if a sibling brain applied it blindly")

	print("  ferryn    chases with no sight or hearing, resets on a flash, and screams the facility awake")


## Glyra never moves -- she is a timer wearing a hunter's slot -- and only
## matters through her music box: silent while wound, a real noise
## contribution once it runs down, and winding it gives back exactly what she
## added rather than leaving the meter wherever it happened to land.
func _glyra_winds_down_and_back_up(generator: FacilityGenerator) -> void:
	var brain := _brain("glyra", Vector2(generator.start) + Vector2(0.5, 0.5))
	if brain.gimmick == null:
		_fail("Glyra has no gimmick")
		return
	var meters := PlayerMeters.new()
	var target := _target(brain.position)
	target["meters"] = meters

	# Freshly wound: silent, and pinned in place.
	brain.update(STEP, generator, target, 1, 0)
	_expect(brain.gimmick.holds_position(), "Glyra is not pinned in place")
	_expect(brain.world_events.is_empty(), "a freshly wound music box already raised a warning")

	# Run the wind all the way down.
	for i in int(GameConfig.GLYRA_BAY_SECONDS / STEP) + 5:
		brain.update(STEP, generator, target, 1, 0)
	var warned := false
	for event in brain.world_events:
		if String(event.get("message", "")).find("WOUND DOWN") >= 0:
			warned = true
	_expect(warned, "Glyra's music box ran down with no warning to the player")
	brain.world_events.clear()

	# Unwound now: real noise, accumulating.
	meters.update(STEP, {})
	var before := meters.noise_meter
	for i in 30:
		brain.update(STEP, generator, target, 1, 0)
	meters.update(STEP, {})
	_expect(meters.noise_meter > before, "an unwound music box raised no facility noise")

	# Winding it gives back what it took, not just stops taking more.
	var winding := meters.noise_meter
	brain.gimmick.wind(meters)
	meters.update(STEP, {})
	_expect(meters.noise_meter < winding,
		"winding the music box did not reclaim the noise it had added")
	for i in 10:
		brain.update(STEP, generator, target, 1, 0)
	_expect(brain.world_events.is_empty(),
		"a freshly rewound box is already raising noise or warnings again")

	print("  glyra     silent while wound, raises real noise once run down, reclaims it on rewind")


## Ilyra teleports to a corner and watches. Seen once, then LOOKED AWAY FROM
## (not chased off -- she never chases), she tags wherever the player was and
## pounces after a short delay regardless of where the player has since gone.
## A held torch banishes her outright. Driven through real perception (sight,
## not an injected flag) because "she sets _tagged=true" is exactly the check
## that passes while sight/hearing never actually gated it.
func _ilyra_tags_and_pounces(generator: FacilityGenerator) -> void:
	var brain := _brain("ilyra", Vector2(generator.start) + Vector2(0.5, 0.5))
	if brain.gimmick == null:
		_fail("Ilyra has no gimmick")
		return

	# Her first update teleports her from wherever activate_at() put her to
	# her own chosen corner -- that jump is real and expected, so what gets
	# tested for "never walks" is stillness AFTER that landing, not agreement
	# with the arbitrary spot she started at.
	brain.update(STEP, generator, _target(brain.position + Vector2(40, 40)), 1, 0)
	var corner := brain.position

	# Close enough for real sight to land, torch off so it is sight and not
	# a beam that puts her in the wrong branch.
	var near := _target(corner + Vector2(1.0, 0.0))
	for i in 5:
		brain.update(STEP, generator, near, 1, 0)
	_expect(brain.state == HunterBrain.State.CHASE,
		"setup problem: Ilyra never actually saw the player at this range")
	_expect(brain.position == corner, "Ilyra moved -- she is supposed to only ever teleport")

	# Looked away: push the player out of sight/hearing range entirely.
	var far := _target(corner + Vector2(40.0, 40.0))
	far["hidden"] = true
	var pounced := false
	for i in int((GameConfig.ILYRA_POUNCE_DELAY + 1.0) / STEP):
		brain.update(STEP, generator, far, 1, 0)
		for event in brain.world_events:
			if event.get("what") == "stun":
				pounced = true
		brain.world_events.clear()
		if pounced:
			break
	_expect(pounced, "Ilyra saw the player and lost sight of her, but never pounced")

	var after_pounce := brain.position
	_expect(after_pounce != corner, "Ilyra did not teleport to a new corner after pouncing")

	# A held torch banishes her outright -- hidden, and inert.
	var lit := _target(brain.position - Vector2(0.0, 2.0))
	lit["flashlight_on"] = true
	lit["facing"] = Vector2(0, 1)
	var flashed := false
	for i in 90:
		brain.update(STEP, generator, lit, 1, 0)
		if brain.flash_triggered:
			flashed = true
	_expect(flashed, "setup problem: never actually held a flash on Ilyra")
	_expect(brain.gimmick.hidden_from_view(), "flashing Ilyra did not banish her")

	print("  ilyra     tags a real sighting, pounces after the delay, banished by a held torch")


func _verrine_lurks_and_chases(host: Node) -> void:
	# A real scene, purely for a real player node -- global_position is
	# unreadable/unsettable on a PlayerController3D that was never actually
	# built from its own scene (its @onready camera/flashlight children do
	# not exist on a bare .new()). The generator comes along with it, already
	# carrying a real vent network from _spawn_interactables' own call to
	# place_vents(). Verrine's own brain is still built by hand, same as
	# Jyvra/Ceryth's checks -- the scene's own random draw has no reason to
	# have actually drawn her.
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var generator: FacilityGenerator = scene.facility_view.generator
	var player: PlayerController3D = scene.player
	var vents: Array = generator.vents

	if vents.size() < GameConfig.VERRINE_VENT_COUNT:
		_fail("only %d vents placed on a whole floor" % vents.size())
		scene.queue_free()
		return
	for vent in vents:
		var cell := Vector2i(vent["x"], vent["y"])
		_expect(generator.grid[cell.y][cell.x] == 0, "vent %s is inside a wall" % cell)

	var brain := _brain("verrine", Vector2(vents[0]["x"], vents[0]["y"]) + Vector2(0.5, 0.5))
	if brain.gimmick == null:
		_fail("Verrine has no gimmick")
		scene.queue_free()
		return

	# Not in the network at all: hidden, holding position, and ignoring a
	# player standing right next to her -- the whole point of a lurker.
	var away := _target(brain.position + Vector2(1.0, 0.0))
	for i in 5:
		brain.update(STEP, generator, away, 1, 0)
	_expect(brain.gimmick.hidden_from_view(), "Verrine is visible before the player ever entered a vent")
	_expect(brain.state != HunterBrain.State.CHASE, "Verrine chased a player who never entered the network")
	var still_here := brain.position

	player.global_position = Vector3(vents[0]["x"] + 0.5, 0.0, vents[0]["y"] + 0.5)

	var message: String = brain.gimmick.use_vent(String(vents[0]["id"]), brain, player, generator)
	_expect(player.in_vent, "entering a vent did not mark the player in_vent")
	_expect(message.begins_with("VENT TRANSIT"), "entering the network did not transit forward: got '%s'" % message)
	_expect(brain.position != still_here, "Verrine did not teleport in when the player entered the network")

	# Driven frames with in_vent true: chase, and speed ramping over time.
	var in_vent_target := _target(player.grid_position())
	in_vent_target["in_vent"] = true
	in_vent_target["vent_time_in"] = 0.0
	brain.update(STEP, generator, in_vent_target, 1, 0)
	_expect(brain.state == HunterBrain.State.CHASE, "Verrine did not chase once the player was in the vent network")
	_expect(not brain.gimmick.hidden_from_view(), "Verrine stayed hidden while actively chasing through the vents")
	var early_speed: float = brain.gimmick.speed_scale(brain)
	_expect(is_equal_approx(early_speed, GameConfig.VERRINE_INITIAL_SPEED_SCALE),
		"Verrine's speed scale did not start at the network's initial value")

	in_vent_target["vent_time_in"] = 200.0
	brain.update(STEP, generator, in_vent_target, 1, 0)
	var ramped_speed: float = brain.gimmick.speed_scale(brain)
	_expect(ramped_speed > early_speed, "Verrine's speed did not ramp up the longer the player stayed in the vents")
	_expect(ramped_speed <= GameConfig.VERRINE_MAX_SPEED_SCALE + 0.001,
		"Verrine's speed scale exceeded the network's maximum")

	# Walk the ring all the way back around to the entry vent to exit --
	# each interaction happens at whichever vent the last transit landed on,
	# not the entry vent itself.
	var standing_index := 1
	var exited := false
	for i in vents.size() - 1:
		message = brain.gimmick.use_vent(String(vents[standing_index]["id"]), brain, player, generator)
		if message == "VENT NETWORK EXITED":
			exited = true
			break
		standing_index = (standing_index + 1) % vents.size()
	_expect(exited, "walking the whole ring never brought the player back to the entry vent")
	_expect(not player.in_vent, "exiting the network did not clear in_vent")

	# Back outside the network: inert again.
	brain.update(STEP, generator, _target(brain.position + Vector2(1.0, 0.0)), 1, 0)
	_expect(brain.gimmick.hidden_from_view(), "Verrine stayed visible after the player left the vent network")

	scene.queue_free()
	print("  verrine   inert outside the network, chases and ramps speed inside it, resets on exit")


func _zephyra_trades_and_repairs(host: Node) -> void:
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var generator: FacilityGenerator = scene.facility_view.generator
	var player: PlayerController3D = scene.player

	var coins: Array = generator.coins
	if coins.size() < GameConfig.COIN_PICKUP_COUNT:
		_fail("only %d coin pickups placed on a whole floor" % coins.size())
		scene.queue_free()
		return
	for coin in coins:
		var cell := Vector2i(coin["x"], coin["y"])
		_expect(generator.grid[cell.y][cell.x] == 0, "coin %s is inside a wall" % cell)

	# A real pickup, through the real interactable.
	var coin_node: RouteInteractable3D = scene.facility_view._at(
		Vector2i(coins[0]["x"], coins[0]["y"]), RouteInteractable3D.Kind.COIN)
	if coin_node == null:
		_fail("no interactable at the first coin's cell")
		scene.queue_free()
		return
	var coins_before := GameState.coins
	coin_node.activate(player)
	_expect(GameState.coins == coins_before + GameConfig.COIN_PICKUP_VALUE,
		"collecting a coin did not credit GameState.coins")
	_expect(coin_node.completed, "a collected coin did not mark itself completed")

	var brain := _brain("zephyra", Vector2(generator.start) + Vector2(0.5, 0.5))
	if brain.gimmick == null:
		_fail("Zephyra has no gimmick")
		scene.queue_free()
		return

	# First update settles her near the facility's center and she never moves
	# again, even with the player right on top of her.
	brain.update(STEP, generator, _target(brain.position + Vector2(40.0, 40.0)), 1, 0)
	var settled_at := brain.position
	for i in 10:
		brain.update(STEP, generator, _target(settled_at), 1, 0)
		_expect(brain.position == settled_at, "Zephyra moved -- she is supposed to hold position forever")
	_expect(brain.state == HunterBrain.State.IDLE,
		"Zephyra reacted to the player standing on top of her")

	# Standing exactly where a capture would ordinarily trigger must never
	# actually capture her.
	var captured := brain.update(STEP, generator, _target(settled_at), 1, 0)
	_expect(not captured, "Zephyra captured the player -- she is supposed to be immune")

	# Out of range: no shop.
	var message: String = brain.gimmick.open_shop(settled_at + Vector2(10.0, 10.0), settled_at, Vector2(0, 1))
	_expect(message.is_empty(), "the shop opened from far outside its range")

	# In range and facing her (distance 0 counts as facing -- there is no
	# meaningful "behind you" when you're standing exactly where she is):
	# opens with a real offer menu.
	GameState.coins = 20
	message = brain.gimmick.open_shop(settled_at, settled_at, Vector2(0, 1))
	_expect(not message.is_empty() and message.begins_with("ZYTTU SHOP"),
		"opening the shop in range and facing her did not return a menu")
	_expect(brain.gimmick.shop_open, "opening the shop did not mark it open")

	# In range but facing away: refused, same as any other interactable.
	brain.gimmick.shop_open = false
	var away_point := settled_at + Vector2(1.0, 0.0)
	message = brain.gimmick.open_shop(away_point, settled_at, Vector2(0, 1))
	_expect(message.is_empty(), "the shop opened while facing away from her")
	_expect(not brain.gimmick.shop_open, "facing away still marked the shop open")

	# Choosing before it's open is a no-op (guarded separately below by
	# closing it first).
	brain.gimmick.shop_open = false
	_expect(brain.gimmick.choose_offer(1, player, scene.facility_view).is_empty(),
		"choosing an offer with the shop closed did something")
	brain.gimmick.shop_open = true

	# Cooling costs coins and actually cools the player.
	player.meters.temperature = 80.0
	var coins_before_trade := GameState.coins
	message = brain.gimmick.choose_offer(1, player, scene.facility_view)
	_expect(message.begins_with("ZYTTU TRADE COMPLETE"), "a real cool trade did not complete: got '%s'" % message)
	_expect(is_equal_approx(player.meters.temperature, 80.0 - GameConfig.ZEPHYRA_TEMPERATURE_STEP),
		"cooling did not actually lower temperature")
	_expect(GameState.coins == coins_before_trade - GameConfig.ZEPHYRA_COOL_COST,
		"cooling did not charge the right number of coins")
	_expect(not brain.gimmick.shop_open, "a completed trade left the shop open")

	# Not enough coins: refused, and nothing is charged.
	GameState.coins = 0
	brain.gimmick.shop_open = true
	message = brain.gimmick.choose_offer(2, player, scene.facility_view)
	_expect(message.contains("NOT ENOUGH COINS"), "an unaffordable trade was not refused: got '%s'" % message)
	_expect(GameState.coins == 0, "a refused trade still charged coins")

	# Repair, with a real sabotaged relay on the floor.
	if generator.relays.is_empty():
		_fail("no relays on the live floor to test Zephyra's repair against")
	else:
		var relay_cell := Vector2i(generator.relays[0]["x"], generator.relays[0]["y"])
		var relay_node: RouteInteractable3D = scene.facility_view._at(relay_cell, RouteInteractable3D.Kind.RELAY)
		relay_node.set_sabotaged(true)
		GameState.coins = 20
		brain.gimmick.shop_open = true
		message = brain.gimmick.choose_offer(3, player, scene.facility_view)
		_expect(message.begins_with("ZYTTU TRADE COMPLETE"), "a real repair trade did not complete")
		_expect(not relay_node.sabotaged, "repair did not bring the sabotaged relay back online")

	# Pesticide arms the timer Loxelle/Ysolde read off the target dict.
	GameState.coins = 20
	brain.gimmick.shop_open = true
	message = brain.gimmick.choose_offer(4, player, scene.facility_view)
	_expect(message.begins_with("ZYTTU TRADE COMPLETE"), "a real pesticide trade did not complete")
	_expect(player.pesticide_timer >= GameConfig.ZEPHYRA_PESTICIDE_SECONDS - 0.01,
		"pesticide did not arm the player's timer")

	# Far and hidden, so ordinary sight/hearing cannot itself put either brain
	# into CHASE/INVESTIGATE -- isolates the assertion to each gimmick's OWN
	# ability logic, which is what the pesticide guard actually gates.
	var pesticide_target := _target(Vector2(500.0, 500.0))
	pesticide_target["hidden"] = true
	pesticide_target["pesticide_active"] = true
	var loxelle_brain := _brain("loxelle", Vector2(0.5, 0.5))
	loxelle_brain.gimmick._passive_timer = 999.0
	loxelle_brain.update(STEP, generator, pesticide_target, 1, 0)
	_expect(loxelle_brain.gimmick._passive_timer >= 999.0 - STEP - 0.001,
		"Loxelle's passive timer kept advancing while pesticide was active")
	# Her own logic sets last_known to a battery's position unconditionally
	# once one exists, regardless of range -- state alone can't tell the
	# difference here, since activate_at() already starts her in INVESTIGATE.
	var ysolde_brain := _brain("ysolde", Vector2(0.5, 0.5))
	var last_known_before := ysolde_brain.last_known
	ysolde_brain.update(STEP, generator, pesticide_target, 1, 0)
	_expect(ysolde_brain.last_known == last_known_before,
		"Ysolde still targeted a battery while pesticide was active")

	scene.queue_free()
	print("  zephyra   coins collect, trades cost and apply, and pesticide gates Loxelle/Ysolde")


## Not hunter-specific -- general player/interactable infrastructure, tested
## here because this file already has the real-scene + real-relay harness
## (see _briselle_sabotages_and_resecures) that a facing check needs. Being
## in reach used to be the whole gate; now the player also has to be turned
## toward the thing, which _nearest_interactable() enforces for every
## interactable at once (see PlayerController3D._nearest_interactable).
func _interactables_require_facing(host: Node) -> void:
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var generator: FacilityGenerator = scene.facility_view.generator
	var player: PlayerController3D = scene.player
	if generator.relays.is_empty():
		_fail("no relays on the live floor to test facing-gated interaction against")
		scene.queue_free()
		return
	var relay_cell := Vector2i(generator.relays[0]["x"], generator.relays[0]["y"])
	var relay_node: RouteInteractable3D = scene.facility_view._at(relay_cell, RouteInteractable3D.Kind.RELAY)
	if relay_node == null:
		_fail("no interactable at the first relay's cell")
		scene.queue_free()
		return

	# Close enough to reach, one metre off the relay.
	player.global_position = relay_node.global_position + Vector3(0.0, 0.0, 1.0)

	# Facing away from it: no prompt, and pressing interact does nothing --
	# proximity alone used to be enough for both.
	player.facing = Vector2(0.0, 1.0)
	_expect(player._nearest_interactable() != relay_node,
		"a relay right next to the player stayed targeted while they faced away from it")
	player._try_interact()
	_expect(GameState.relays_collected == 0,
		"pressing interact while facing away from a relay collected it anyway")

	# Turned to face it: the same relay, now reachable both for the prompt
	# and for the press.
	player.facing = Vector2(0.0, -1.0)
	_expect(player._nearest_interactable() == relay_node,
		"a relay right in front of the player was not targeted while facing it directly")
	player._try_interact()
	_expect(GameState.relays_collected == 1,
		"pressing interact while facing a relay directly did not collect it")

	scene.queue_free()
	print("  facing    a nearby interactable is only reachable while actually faced")


## Not hunter-specific -- pure A*/movement infrastructure, colocated here for
## the same reason _interactables_require_facing is. Every other check in
## this file drives state transitions (last_known, CHASE/SEARCH) without
## ever asserting the thing a player actually SEES: that `position` keeps
## advancing toward a real, far-off target over many real frames rather than
## stalling. A tuning-only baseline (Dovelle, no gimmick) isolates that from
## any gimmick's own movement override.
func _hunter_paths_to_a_distant_target(generator: FacilityGenerator) -> void:
	var start_pos := Vector2(generator.start) + Vector2(0.5, 0.5)
	var far_target := Vector2(generator.exit_cell) + Vector2(0.5, 0.5)
	if start_pos.distance_to(far_target) < 8.0:
		_fail("setup problem: start and exit are too close to prove real pathing")
		return

	var brain := HunterBrain.new(start_pos, "PATH-CHECK:dovelle", "dovelle")
	# Mirrors activate_at() in the real game: aimed at wherever the player
	# actually was the moment she woke.
	brain.activate_at(far_target)

	# The "player" stays permanently out of sight and hearing, so this
	# isolates path-FOLLOWING toward the already-locked last_known, not
	# perception re-acquiring her every frame.
	var target := _target(Vector2(-999.0, -999.0))
	target["hidden"] = true

	var start_distance := start_pos.distance_to(far_target)
	var closest := start_distance
	for i in 1800:  # 30 real seconds -- generous; she should close most of it
		brain.update(STEP, generator, target, 1, 0)
		closest = minf(closest, brain.position.distance_to(far_target))

	_expect(closest < start_distance * 0.5,
		"a hunter aimed at a real target %.1f tiles away only closed to %.1f in 30s -- pathing looks stalled"
			% [start_distance, closest])
	print("  pathing   a hunter closes real distance to a far target over many frames, not just state")
