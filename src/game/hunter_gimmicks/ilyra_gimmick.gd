class_name IlyraGimmick
extends HunterGimmick

## Ilyra's corner observation and shadow pounce (hunterAbilities.ilyra.
## cornerObserver). Ported from ilyra.js's prepareCornerObserver/
## respawnCornerObserver/resolveCornerObserver.
##
## She never walks anywhere -- she TELEPORTS to a corner of a random room and
## watches. Seen once (real sight, not hearing), then lost sight of again --
## looked away from, not chased off -- she tags wherever the player was at
## that moment and, after a short delay, pounces: the player is stunned for
## ILYRA_STUN_SECONDS regardless of where they have since moved, and she
## teleports to a fresh corner to start over.
##
## A held player torch does not just interrupt her, it banishes her --
## invisible and completely inert for ILYRA_BANISH_SECONDS, reusing the same
## hidden_from_view() Porcelle already established.
##
## The pounce delay is the 2D config's 15 s (zero on Nightmare).

var _has_corner := false
var _hidden_remaining := 0.0
var _saw_player := false
var _tagged := false
var _pounce_remaining := 0.0


func after_perception(brain: HunterBrain, delta: float, _target: Dictionary, generator) -> void:
	if not _has_corner:
		_respawn_corner(brain, generator)
		_has_corner = true

	if _hidden_remaining > 0.0:
		_hidden_remaining -= delta
		return

	if brain.flash_triggered:
		_hidden_remaining = GameConfig.ILYRA_BANISH_SECONDS
		_saw_player = false
		_tagged = false
		_pounce_remaining = 0.0
		return

	# CHASE intentionally persists around corners now. Use the current visual
	# evidence rather than the retained state, otherwise looking away would no
	# longer tag the player and her delayed pounce could never begin.
	var sees := brain.direct_chase_visible or _shares_room(brain, _target, generator)
	if sees:
		_saw_player = true
	elif _saw_player and not _tagged:
		_tagged = true
		_pounce_remaining = 0.0 if brain.difficulty_id == "nightmare" else GameConfig.ILYRA_POUNCE_DELAY
		_saw_player = false

	if _tagged:
		_pounce_remaining -= delta
		if _pounce_remaining <= 0.0:
			brain.world_events.append({"what": "stun", "seconds": GameConfig.ILYRA_STUN_SECONDS,
				"message": "ILYRA SHADOW POUNCE // STUNNED %ds" % int(GameConfig.ILYRA_STUN_SECONDS)})
			_tagged = false
			_respawn_corner(brain, generator)


func holds_position() -> bool:
	return true


func sight_scale(_brain: HunterBrain) -> float:
	return GameConfig.ILYRA_SIGHT_SCALE


## 2D: standing in her room with a lit player counts as sight even without a clear ray.
func _shares_room(brain: HunterBrain, target: Dictionary, generator) -> bool:
	if target.is_empty() or bool(target.get("hidden", false)) or bool(target.get("in_safe_zone", false)):
		return false
	var at: Vector2 = target.get("position", Vector2(1.0e6, 1.0e6))
	var mine: Dictionary = generator.room_at(brain.position.x, brain.position.y)
	var theirs: Dictionary = generator.room_at(at.x, at.y)
	return not mine.is_empty() and str(mine.get("id", mine.get("center"))) == str(theirs.get("id", theirs.get("center")))


func hidden_from_view() -> bool:
	return _hidden_remaining > 0.0


func network_state() -> Dictionary:
	return {"hidden": _hidden_remaining > 0.0}


func apply_network_state(state: Dictionary) -> void:
	# Guests do not count the authoritative timer; they only need the current
	# visibility result, refreshed in every hunter packet.
	_hidden_remaining = 1.0 if bool(state.get("hidden", false)) else 0.0


func _respawn_corner(brain: HunterBrain, generator) -> void:
	if generator.rooms.is_empty():
		return
	var room: Dictionary = generator.rooms[brain.next_random_index(generator.rooms.size())]
	var room_x: float = float(room.get("x", 0.0))
	var room_y: float = float(room.get("y", 0.0))
	var room_width: float = float(room.get("width", 0.0))
	var room_height: float = float(room.get("height", 0.0))
	var corners := [
		Vector2(room_x + 1.5, room_y + 1.5),
		Vector2(room_x + room_width - 1.5, room_y + 1.5),
		Vector2(room_x + 1.5, room_y + room_height - 1.5),
		Vector2(room_x + room_width - 1.5, room_y + room_height - 1.5),
	]
	var chosen: Vector2 = corners[brain.next_random_index(corners.size())]
	var open: Dictionary = generator.nearest_open_position(
		chosen.x, chosen.y, brain.radius)
	brain.position = Vector2(open["x"], open["y"]) if not open.is_empty() else chosen


## Non-lethal in 2D (nonLethal / specialist early return): she can never trigger a capture.
func immune_to_capture() -> bool:
	return true
