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
