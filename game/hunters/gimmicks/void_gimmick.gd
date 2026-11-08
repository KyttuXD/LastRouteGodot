class_name VoidGimmick
extends HunterGimmick

## Shared helpers for the 2D game's Void powers. Each colour is its own small
## subclass; this base only holds the geometry the powers have in common.


## True when the player is looking at `from` within `half_angle` radians, in range and with a clear line.
static func player_watching(target: Dictionary, from: Vector2, range_limit: float, half_angle: float, generator) -> bool:
	if target.is_empty() or bool(target.get("hidden", false)) or bool(target.get("in_safe_zone", false)):
		return false
	var at: Vector2 = target.get("position", Vector2(1.0e6, 1.0e6))
	var facing: Vector2 = target.get("facing", Vector2.ZERO)
	var offset := from - at
	var distance := offset.length()
	if distance <= 0.001 or distance > range_limit or facing.length() <= 0.001:
		return false
	if offset.normalized().dot(facing.normalized()) < cos(half_angle):
		return false
	return generator.has_line_of_sight(at, from)


## The player's own lit torch pointing at `from` (2D lit beam: flashlight on and lamp charged).
static func beam_on(target: Dictionary, from: Vector2, range_limit: float, half_angle: float, generator) -> bool:
	# a torch burning inside a hiding spot does not pin a hunter to it forever
	if bool(target.get("hidden", false)):
		return false
	if not bool(target.get("flashlight_on", false)) or float(target.get("lamp_charge", 1.0)) <= 0.0:
		return false
	return player_watching(target, from, range_limit, half_angle, generator)
