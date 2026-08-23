class_name JyvraGimmick
extends HunterGimmick

## Jyvra's hiding timeout (hunterAbilities.jyvra.hidingTimeout). Ported from
## jyvra.js's updateHiddenHunterPressure: a locker is not safety from her. Stand
## still inside one while she is over it and after eight seconds she reaches in
## and pulls you out — alive, but standing in the open with her right there.
##
## The subtle rule the original spells out and this preserves: the timer keys on
## her PROXIMITY to the spot, not on her being in "chase". The shared brain drops
## a hunter out of chase the instant the player hides and gives up on the trail
## within a couple of seconds, so gating on chase reset the timer roughly every
## 0.45s and the ejection was unreachable. She is also pinned to the spot while
## it counts down, so ordinary search-and-wander cannot pull her off it.
##
## The ejection leaves her briefly stalled on purpose — it is non-lethal, and
## without the stall the player slides straight from being pulled out into a
## capture on the very next frame.

## Set by the scene when the ejection fires: where the player ends up.
var ejected_to := Vector2.ZERO
var ejecting := false

var _held := 0.0


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	ejecting = false
	if not bool(target.get("hidden", false)):
		_held = 0.0
		return
	var cell: Vector2i = target.get("hiding_spot", Vector2i(-1, -1))
	if cell.x < 0:
		_held = 0.0
		return

	var spot := Vector2(cell) + Vector2(0.5, 0.5)
	if brain.position.distance_to(spot) >= GameConfig.JYVRA_REACH:
		_held = 0.0
		return

	# Hold her over it. Search give-up would otherwise walk her away mid-count.
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = spot
	brain.search_visits = 0

	_held += delta
	if _held < GameConfig.JYVRA_HIDING_SECONDS:
		return
	_held = 0.0
	ejecting = true
	ejected_to = generator.hiding_exit_position({"x": cell.x, "y": cell.y})
	brain.apply_stun(GameConfig.JYVRA_EJECT_STALL)
