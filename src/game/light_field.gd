class_name LightField
extends RefCounted

## How lit a spot is, 0..1, from the same lamp data that drives rendering (docs/LIGHT_SIGHT.md). Every lamp registered in
## the LampField (all visual lamps of the resident chunks, not only the few budgeted real lights) within LAMP_REACH counts,
## falling off over its range, unless a wall blocks the line (the nav floor grid). The base ambient adds a floor. Used for
## the mutual light rule: a lit hunter that the runner can see also sees the runner, flashlight or not.

## Rule switch (admin can turn it off).
static var enabled := true
const LAMP_REACH := 25.0
const AMBIENT := 0.04
## Exposure the player's eye needs to make out a hunter (calibrated against the lamp pools in captures).
const VISIBLE_EXPOSURE := 0.32
## Sight range scale by the runner's own exposure when her flashlight is off: pitch dark -> lit.
const DARK_SIGHT_SCALE := 0.35
const LIT_SIGHT_SCALE := 1.6


## `lamps_by_chunk`: LampField chunk lists ([pos, color, energy, flicker]); `line_clear`: Callable(Vector2, Vector2) -> bool or
## an invalid Callable to skip occlusion. `flicker_off`: lamps currently off (flicker != 0 and dark) are skipped by the caller.
static func exposure_at(point: Vector3, lamps_by_chunk: Dictionary, line_clear: Callable = Callable()) -> Dictionary:
	var total := AMBIENT
	var best := 0.0
	var source := Vector3.ZERO
	var range := LampField.LIGHT_RANGE
	var at2 := Vector2(point.x, point.z)
	for lamps in lamps_by_chunk.values():
		for lamp_value in lamps:
			var lamp: Array = lamp_value
			var pos: Vector3 = lamp[0]
			var d := pos.distance_to(point)
			if d > minf(range, LAMP_REACH):
				continue
			var falloff := pow(1.0 - d / range, 1.6)
			var contribution := float(lamp[2]) * falloff * .9
			if contribution < .02:
				continue
			if line_clear.is_valid() and not bool(line_clear.call(Vector2(pos.x, pos.z), at2)):
				continue
			total += contribution
			if contribution > best:
				best = contribution
				source = pos
	return {"value": clampf(total, 0.0, 1.0), "source": source}


## Sight limit for an unlit runner by her exposure.
static func unlit_scale(exposure: float) -> float:
	return lerpf(DARK_SIGHT_SCALE, LIT_SIGHT_SCALE, clampf(exposure, 0.0, 1.0))
