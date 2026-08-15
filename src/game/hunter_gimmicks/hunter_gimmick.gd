class_name HunterGimmick
extends RefCounted

## Base class for a hunter's optional behavior-changing gimmick — as opposed
## to a pure tuning-number difference, which needs no gimmick at all (see
## HunterRoster; that's how Dovelle works). One instance lives on the
## HunterBrain of any hunter whose id resolves to one below; everyone else's
## `gimmick` field is null and every hook here is skipped entirely.
##
## Mirrors the original's per-hunter files (src/game/hunters/*.js in
## KyttuXD/LastRoute) one-for-one: one script per hunter under this folder,
## registered in for_id() below. Override only the hooks a given hunter
## actually needs — each has a harmless no-op default. Add hooks here (and
## their matching call site in hunter_brain.gd) only when a real hunter
## needs one; guessing at hooks before a second/third real example exists
## just to look "complete" tends to guess wrong.

## Called once per HunterBrain.update(), before _update_perception() —
## mirrors where the original's per-hunter ability hooks run, ahead of the
## shared sight/hearing block in hunter-ai.js's updateHunterInner(). Free to
## set brain.state/last_known/lost_sight_timer/etc. directly to override or
## pre-empt ordinary perception for this frame. `generator` is passed through
## because several gimmicks are spatial (line of sight, floor-cell searches,
## pathfinding) — see KathyGimmick and MavrineGimmick.
func before_perception(_brain: HunterBrain, _delta: float, _target: Dictionary, _generator: FacilityGenerator) -> void:
	pass


## Multiplies HunterBrain._current_speed()'s computed result. Default: 1.0
## (no change).
func speed_scale(_brain: HunterBrain) -> float:
	return 1.0


## True while the gimmick pins her in place — the equivalent of the original's
## `movementScale: 0 / holdPosition: true` modifier. Perception and timers
## keep running; only movement stops. Used by MavrineGimmick's survey phase.
func holds_position() -> bool:
	return false


## The one place a hunter id maps to her gimmick instance. Returns null for
## any id with no behavior-changing gimmick (tuning-only hunters like
## Dovelle, and every not-yet-ported id) — HunterBrain treats null as "skip
## every hook", so adding a hunter here is opt-in, never a stub to fill in.
static func for_id(hunter_id: String) -> HunterGimmick:
	match hunter_id:
		"quirith":
			return QuirithGimmick.new()
		"eirys":
			return EirysGimmick.new()
		"xivvy":
			return XivvyGimmick.new()
		"kathy":
			return KathyGimmick.new()
		"ravelle":
			return RavelleGimmick.new()
		"mavrine":
			return MavrineGimmick.new()
		"umbriel":
			return UmbrielGimmick.new()
		_:
			return null
