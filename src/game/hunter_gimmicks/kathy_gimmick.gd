class_name KathyGimmick
extends HunterGimmick

## Kathy's search beam (hunterAbilities.kathy.beamDetection). Ported from
## hunter-ai.js's hunterBeamSpotsPlayer(): a cone along her OWN facing that
## spots the target at 11.5 cells — well past the roster's ~8-cell ordinary
## sight — still requiring line of sight, and still blocked by a safe zone or
## hiding. In the original this feeds the shared `seesPlayer` disjunction;
## here it runs in before_perception and sets the same chase state that a
## sighting would, re-affirmed every frame so the lost-sight grace can't
## accumulate while the target stays in the cone.
##
## Her second ability, affectedSummon, is deliberately not ported: it spawns
## an extra hunter once OTHER active route hunters have alerted the player,
## and both codebases run exactly one ordinary route hunter per floor
## (ROUTE_HUNTER_COUNT = 1), so its precondition can never be met. It is
## permanently inert rather than skipped — see HUNTER_ROSTER.md.


func before_perception(brain: HunterBrain, _delta: float, target: Dictionary, generator: FacilityGenerator) -> void:
	if target.get("hidden", false) or target.get("in_safe_zone", false):
		return
	if not brain.beam_reaches(
		brain.position, brain.facing, target["position"],
		GameConfig.KATHY_BEAM_RANGE, GameConfig.KATHY_BEAM_HALF_ANGLE, generator
	):
		return

	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = target["position"]
	brain.lost_sight_timer = 0.0
