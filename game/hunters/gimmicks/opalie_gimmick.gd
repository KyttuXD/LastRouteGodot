class_name OpalieGimmick
extends HunterGimmick

## Opalie's guard station (hunterAbilities.opalie.relayGuardian). Ported from
## opalie.js's updateRelayGuardian: she picks one relay, walks to it, and then
## STOPS -- and while she is standing there, nothing within
## OPALIE_SUPPRESSION_RADIUS can be interacted with at all. Not the relay: the
## lift, a battery, a safe zone, anything. The counter is to draw her off or
## wait her out, and touching what she guards pings your position to every
## active hunter on the floor.
##
## Faithfully, she guards `relays[0]` -- the first relay the generator placed,
## collected or not -- rather than the nearest or the most valuable. The
## original only gets cleverer about which relay on Nightmare, when it pairs her
## onto whatever Briselle is sabotaging; there is no difficulty selection and no
## Briselle here, so that branch is inert rather than approximated.
##
## The denial itself is a simulation rule, not a renderer effect: main_3d asks
## `blocks()` before any interaction resolves, exactly where the original's
## performInteraction() calls guardianBlocking().

## Where she has settled, or ZERO while she is still walking there.
var station := Vector2.ZERO
var on_station := false


func after_perception(brain: HunterBrain, _delta: float, target: Dictionary, generator) -> void:
	if generator.relays.is_empty():
		return
	# She keeps guarding the first relay still out; once it is taken she moves on to the next one.
	var relay: Dictionary = generator.relays[0]
	for entry in generator.relays:
		if not entry.get("collected", false):
			relay = entry
			break
	var open: Dictionary = generator.nearest_open_position(
		relay["x"] + 0.5, relay["y"] + 0.5, brain.radius)
	if open.is_empty():
		return
	var post := Vector2(open["x"], open["y"])
	# "opalie saw me, i hid in a locker, and now shes walking away even if i go up close" / "chase further". Once
	# she has seen or heard a runner she chases like any hunter and only walks back to her post after losing them.
	if brain.state == HunterBrain.State.CHASE and not bool(target.get("hidden", false)):
		on_station = false
		station = Vector2.ZERO
		return

	if brain.position.distance_to(post) > GameConfig.OPALIE_GUARD_ARRIVAL:
		# Still on her way. Ordinary movement carries her; she is only
		# investigating a spot that happens never to move.
		on_station = false
		station = Vector2.ZERO
		brain.state = HunterBrain.State.INVESTIGATE
		brain.has_last_known = true
		brain.last_known = post
		return

	on_station = true
	station = Vector2(relay["x"] + 0.5, relay["y"] + 0.5)


## Standing watch is the whole behaviour, so she stops rather than drifting off
## the post the moment perception suggests somewhere else to be.
func holds_position() -> bool:
	return on_station


## Whether this hunter is denying an interaction at `point`. Mirrors
## guardianBlocking(): only while she actually holds station.
func blocks(point: Vector2) -> bool:
	return on_station and station.distance_to(point) <= GameConfig.OPALIE_SUPPRESSION_RADIUS


func network_state() -> Dictionary:
	return {"station": station, "on_station": on_station}


func apply_network_state(state: Dictionary) -> void:
	var value = state.get("station")
	if value is Vector2:
		station = value
	on_station = bool(state.get("on_station", on_station))


## 2D: a stationed guardian returns before the capture check; she never grabs anyone.
func immune_to_capture() -> bool:
	return on_station
