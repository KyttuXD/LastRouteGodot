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
	var generator := FacilityGenerator.new("HUNTERS-CHECK", RoomState.generator_options())
	_haelith_goes_where_the_relays_are(generator)
	_ysolde_takes_it_off_the_floor(generator)
	_opalie_holds_her_post(generator)
	_aki_answers_a_flash(generator)
	await _porcelle_is_only_on_the_map(_host)
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
