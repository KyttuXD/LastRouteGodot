class_name WynelleGimmick
extends HunterGimmick

## Wynelle's cold materializer (hunterAbilities.wynelle.coldMaterializer).
## Ported from wynelle.js's prepareColdMaterializer / updateColdMaterializers.
##
## Unlike Nyxie and Solyth she is drawn into the ordinary rotation — she just
## starts **dormant** and wakes on cold rather than on the relay count. Cold
## below the warm threshold builds a hidden meter (faster the deeper the cold);
## at 100 she materialises directly on the player and opens a freeze-grace
## window that kills if it runs out.
##
## The facility heater station is the counterplay, and the two states differ:
##   - POWERED zeroes her progress, holding her off entirely.
##   - UNFROZEN (merely thawed) dematerialises her if she has already
##     manifested, resetting her partway rather than to zero.
##
## Once materialised the shared brain drives her like any other chaser — the
## original's prepareColdMaterializer returns false at that point specifically
## so the ordinary sight/chase/pathfinding logic takes over. The bug comment
## in the original notes it used to return true unconditionally, which left
## her materialised but frozen in place; this port hands her over properly.

var materialized := false
var progress := 0.0

var _death_timer := 0.0
var _froze_player := false


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator: FacilityGenerator) -> void:
	var meters: PlayerMeters = target.get("meters")
	var heater_powered: bool = target.get("heater_powered", false)
	var heater_unfrozen: bool = target.get("heater_unfrozen", false)

	if materialized:
		if heater_unfrozen:
			# Not a full reset — powering the station is the only thing that
			# stops her building toward this again.
			materialized = false
			progress = GameConfig.WYNELLE_DEMATERIALIZE_RESET_PROGRESS
			brain.active = false
			brain.state = HunterBrain.State.IDLE
			return
		_death_timer -= delta
		if _death_timer <= 0.0:
			_froze_player = true
		return

	# Dormant until the cold actually builds.
	brain.active = false
	brain.state = HunterBrain.State.IDLE

	if heater_powered or meters == null:
		progress = 0.0
		return
	var temperature := meters.temperature
	if temperature >= GameConfig.WYNELLE_WARM_THRESHOLD:
		progress = 0.0
		return

	var rate := GameConfig.WYNELLE_DEEP_COLD_RATE if temperature < GameConfig.WYNELLE_DEEP_COLD_THRESHOLD \
		else (GameConfig.WYNELLE_WARM_THRESHOLD - temperature) * GameConfig.WYNELLE_PER_DEGREE_RATE
	progress = minf(100.0, progress + rate * delta)
	if progress < 100.0:
		return

	# She manifests where the cold caught up with you, not off in some
	# unrelated room, and gives chase immediately.
	materialized = true
	brain.active = true
	brain.position = target["position"]
	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = target["position"]
	brain.lost_sight_timer = 0.0
	_death_timer = GameConfig.WYNELLE_DEATH_GRACE_SECONDS


## True once the freeze grace ran out — main_3d.gd turns this into the run
## ending, the same way a failed escape does.
func has_frozen_player() -> bool:
	return _froze_player


## She wakes herself, so she must keep evaluating while inert.
func runs_while_inactive() -> bool:
	return true
