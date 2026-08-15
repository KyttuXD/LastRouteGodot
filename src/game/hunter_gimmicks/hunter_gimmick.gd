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


## Called after _update_perception() and before movement — the original's
## line-909 block, where the objective-driven hunters live. The distinction from
## before_perception is not cosmetic: a hook here OVERRIDES what perception just
## decided, which is the whole point for a hunter who goes where the relays are
## rather than where the player is. Haelith, Ysolde and Opalie all need this;
## running them earlier made every one of them an ordinary chaser the moment she
## laid eyes on anybody, which is exactly the bug the hunters suite caught.
func after_perception(_brain: HunterBrain, _delta: float, _target: Dictionary, _generator: FacilityGenerator) -> void:
	pass


## Multiplies HunterBrain._current_speed()'s computed result. Default: 1.0
## (no change).
func speed_scale(_brain: HunterBrain) -> float:
	return 1.0


## True when this hunter is not drawn in the world at all — Porcelle, who
## exists only on the map. Presentation-only, like Umbriel's disguise: the brain
## never reads it, HunterView3D does.
func hidden_from_view() -> bool:
	return false


## True while the gimmick pins her in place — the equivalent of the original's
## `movementScale: 0 / holdPosition: true` modifier. Perception and timers
## keep running; only movement stops. Used by MavrineGimmick's survey phase.
func holds_position() -> bool:
	return false


## True when a grab by this hunter skips the escape struggle entirely and goes
## straight to the outcome — Nyxie's dead-lamp wake is the original's one case
## (`triggerGameOver` is called directly, with no beginEscape).
func capture_is_inescapable() -> bool:
	return false


## True for a gimmick that decides its hunter's OWN activation, so it has to
## keep running while she is still inert. Rule-summoned hunters (Nyxie on
## darkness, Solyth on heat, Wynelle on cold) need this — without it the
## brain's `if not active: return` would stop the very code that wakes them.
## Ordinary gimmicks stay dormant until the relay schedule activates their
## hunter, which is why this defaults to false rather than always running.
func runs_while_inactive() -> bool:
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
		"nyxie":
			return NyxieGimmick.new()
		"solyth":
			return SolythGimmick.new()
		"wynelle":
			return WynelleGimmick.new()
		"haelith":
			return HaelithGimmick.new()
		"ysolde":
			return YsoldeGimmick.new()
		"opalie":
			return OpalieGimmick.new()
		"aki":
			return AkiGimmick.new()
		"porcelle":
			return PorcelleGimmick.new()
		_:
			return null
