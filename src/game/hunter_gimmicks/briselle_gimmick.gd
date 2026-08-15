class_name BriselleGimmick
extends HunterGimmick

## Briselle's room-entry relay sabotage (hunterAbilities.briselle.saboteur).
## Ported from briselle.js's updateSabotage.
##
## While she is not actually chasing or investigating (ordinary sight/hearing
## takes priority and interrupts her), every room she enters gets one check:
## if it holds a collected, unsabotaged relay, a roll decides whether she goes
## after it. Reaching it, she dwells BRISELLE_SABOTAGE_DWELL seconds and takes
## it offline -- not un-collecting it (GameState.relays_collected never
## decreases, same split the original makes), just blocking the lift until a
## player holds [E] there long enough to restore it.
##
## A held player torch aimed at her (the same beam-attention rising edge Aki
## reads) breaks her off mid-sabotage and sends her back to ordinary wander,
## matching the original's own flash-triggered retreat.
##
## Not ported: the Nightmare-only pairing with Opalie (converging onto
## whichever relay Opalie is already guarding) — there is no difficulty
## selection yet for that branch to ever take.

var target_cell := Vector2i(-1, -1)
var _room_id := ""
var _dwell := 0.0


func after_perception(brain: HunterBrain, delta: float, _target: Dictionary, generator: FacilityGenerator) -> void:
	# CHASE/INVESTIGATE alone cannot tell "ordinary perception just spotted the
	# player" apart from "I set INVESTIGATE myself last frame to walk toward my
	# own target, and perception -- sensing nothing -- left it unchanged"; both
	# look identical on brain.state. What tells them apart is last_known: mine
	# always points exactly at target_cell's centre, because I am the one who
	# put it there. Anything else in that state -- the player's position, or no
	# target of mine at all yet -- is a real interruption. Missing this the
	# first time meant her own activate_at() startup state (every hunter wakes
	# into INVESTIGATE) looked identical to a real sighting and she abandoned
	# a sabotage attempt before ever making one.
	var mine := target_cell.x >= 0 and brain.has_last_known \
		and brain.last_known.distance_to(Vector2(target_cell) + Vector2(0.5, 0.5)) < 0.01
	if brain.state == HunterBrain.State.CHASE or (brain.state == HunterBrain.State.INVESTIGATE and not mine):
		if target_cell.x >= 0:
			_abandon(brain)
		return

	if brain.flash_triggered and target_cell.x >= 0:
		_abandon(brain)
		brain.state = HunterBrain.State.WANDER
		return

	if target_cell.x < 0:
		var room := generator.room_at(brain.position.x, brain.position.y)
		var room_id := String(room.get("id", ""))
		if room.is_empty() or room_id == _room_id:
			return
		_room_id = room_id
		var candidates := _eligible_relays(generator, room_id)
		if candidates.is_empty():
			return
		if brain.next_random_index(1000) >= int(GameConfig.BRISELLE_ROOM_CHANCE * 1000.0):
			return
		var chosen: Dictionary = candidates[brain.next_random_index(candidates.size())]
		target_cell = Vector2i(chosen["x"], chosen["y"])
		_dwell = 0.0

	var relay := _find_relay(generator, target_cell)
	if relay.is_empty() or relay.get("collected", false) != true or relay.get("sabotaged", false):
		_abandon(brain)
		return

	var post := Vector2(target_cell) + Vector2(0.5, 0.5)
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = post

	if brain.position.distance_to(post) >= 0.75:
		return
	_dwell += delta
	if _dwell < GameConfig.BRISELLE_SABOTAGE_DWELL:
		return
	# Same shared-world channel Ysolde's theft and Loxelle's burns use --
	# HunterBrain.world_events, drained by main_3d every frame and broadcast
	# to the room.
	brain.world_events.append({"what": "sabotage", "cell": target_cell, "sabotaged": true,
		"message": "SIGNAL LOST // RELAY OFFLINE"})
	_abandon(brain)


## Pinned to the dwell, like Opalie holding station -- the reach to sabotage a
## relay is standing still next to it, not walking through it.
func holds_position() -> bool:
	return target_cell.x >= 0 and _dwell > 0.0


func _abandon(_brain: HunterBrain) -> void:
	target_cell = Vector2i(-1, -1)
	_dwell = 0.0


static func _eligible_relays(generator: FacilityGenerator, room_id: String) -> Array:
	var out := []
	for relay in generator.relays:
		if not relay.get("collected", false) or relay.get("sabotaged", false):
			continue
		var room := generator.room_at(relay["x"] + 0.5, relay["y"] + 0.5)
		if String(room.get("id", "")) == room_id:
			out.append(relay)
	return out


static func _find_relay(generator: FacilityGenerator, cell: Vector2i) -> Dictionary:
	for relay in generator.relays:
		if relay["x"] == cell.x and relay["y"] == cell.y:
			return relay
	return {}
