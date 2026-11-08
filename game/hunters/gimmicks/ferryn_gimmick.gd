class_name FerrynGimmick
extends HunterGimmick

## Ferryn's persistent stalk (hunterAbilities.ferryn.roundStalker). Ported
## from the original's updateRoundStalker.
##
## She has no sight, no hearing, no lost-sight grace -- she simply always
## knows where the player is and chases, permanently. The only counters are
## the ones the original gives her: successfully hiding, standing in a safe
## zone, or a held player torch. Any of the three teleports her back to a
## fixed origin room (rolled once per floor, never the start room) and resets
## her to an ordinary wander. A flash specifically is not a quiet retreat --
## it is a facility-wide noise spike (addNoise) that puts every OTHER active
## hunter onto the player's position, the same as any other shared alert
## (Kathy's summon uses the identical pattern in the original).
##
## Her second ability, emberVeil, is a presentation-only visibility toggle
## (near-transparent unless directly lit, per its own tuning: exposureDuration
## 999, revealedDuration .01 -- it almost never actually reveals her) with no
## rendering pipeline in this port to hook it into. Deliberately not ported,
## the same category as "real 3D art" -- documented, not silently dropped.

var stalker_origin := Vector2.ZERO
var _has_origin := false


func after_perception(brain: HunterBrain, _delta: float, target: Dictionary, generator) -> void:
	if not _has_origin:
		stalker_origin = _pick_origin(brain, generator)
		_has_origin = true
		brain.position = stalker_origin

	var flashed := brain.flash_triggered
	var hidden := bool(target.get("hidden", false))
	var in_safe_zone := bool(target.get("in_safe_zone", false))

	if flashed or hidden or in_safe_zone:
		brain.position = stalker_origin
		brain.state = HunterBrain.State.WANDER
		brain.has_last_known = false
		if flashed:
			var meters = target.get("meters")
			if meters != null and meters.has_method("add_noise"):
				meters.add_noise(GameConfig.FERRYN_FLASH_NOISE)
			# Applied to every OTHER active hunter by main_3d's drain loop --
			# a gimmick only ever sees its own brain, not the roster.
			brain.emit_world_event({"what": "facility_alert",
				"at": target["position"], "except": brain.hunter_id,
				"message": "FERRYN SCREAM // FACILITY NOISE SPIKE"})
		return

	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = target["position"]
	# Her tracking is never based on genuine sight in the first place, so
	# without this the shared brain's ordinary "no real sighting for 0.45s"
	# decay stomps this CHASE back down to INVESTIGATE every single frame.
	brain.lost_sight_timer = 0.0


static func _pick_origin(brain: HunterBrain, generator) -> Vector2:
	var start_room: Dictionary = generator.room_at(
		generator.start.x + 0.5, generator.start.y + 0.5)
	var start_id := String(start_room.get("id", ""))
	var candidates: Array = []
	for room in generator.rooms:
		if String(room.get("id", "")) != start_id:
			candidates.append(room)
	if candidates.is_empty():
		return brain.position
	var room: Dictionary = candidates[brain.next_random_index(candidates.size())]
	var room_center: Vector2i = room.get("center", Vector2i(
		int(room.get("x", 0)) + int(room.get("width", 1)) / 2,
		int(room.get("y", 0)) + int(room.get("height", 1)) / 2))
	var open: Dictionary = generator.nearest_open_position(
		room_center.x + 0.5, room_center.y + 0.5, brain.radius)
	return Vector2(open["x"], open["y"]) if not open.is_empty() else brain.position
