class_name EliseGimmick
extends HunterGimmick

## Elise' running-data ratchet (hunterAbilities.elise.runningData). Ported
## from elise.js's updateRunningData(): every second the target spends
## actually sprinting outside a safe zone accumulates, and — the whole point —
## NEVER decays. At 100% she locks into a permanent chase on the target's live
## position, with no sight or hearing check involved at all. Once locked she
## re-affirms chase every frame, so HunterBrain's lost-sight grace can never
## accumulate past a single frame and drop her out.
##
## The original also gates on `travelSpeed > .1` (sprinting but stationary
## doesn't count); main_3d.gd folds that into the `sprinting` flag it passes,
## which is only true while genuinely moving.

var progress := 0.0
var locked := false


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	if not locked:
		var sprinting: bool = target.get("sprinting", false)
		var in_safe_zone: bool = target.get("in_safe_zone", false)
		if sprinting and not in_safe_zone:
			progress = minf(1.0, progress + delta / GameConfig.ELISE_SECONDS_TO_FULL)
		if progress >= 1.0:
			locked = true

	if not locked:
		return
	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = target["position"]
	brain.lost_sight_timer = 0.0


## 2D breachesHiding / breaksHiding: hiding does not hide the player from her.
func breaches_hiding() -> bool:
	return true
