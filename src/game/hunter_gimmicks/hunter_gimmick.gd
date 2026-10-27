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
## pathfinding) — see KathyGimmick and MavrineGimmick. It is intentionally a
## duck-typed navigation surface: fixed routes pass FacilityGenerator, while
## the explicitly stream-safe roster passes StreamedHunterNavigation.
func before_perception(_brain: HunterBrain, _delta: float, _target: Dictionary, _generator) -> void:
	pass


## Called after _update_perception() and before movement — the original's
## line-909 block, where the objective-driven hunters live. The distinction from
## before_perception is not cosmetic: a hook here OVERRIDES what perception just
## decided, which is the whole point for a hunter who goes where the relays are
## rather than where the player is. Haelith, Ysolde and Opalie all need this;
## running them earlier made every one of them an ordinary chaser the moment she
## laid eyes on anybody, which is exactly the bug the hunters suite caught.
func after_perception(_brain: HunterBrain, _delta: float, _target: Dictionary, _generator) -> void:
	pass


## Multiplies HunterBrain._current_speed()'s computed result. Default: 1.0
## (no change).
func speed_scale(_brain: HunterBrain) -> float:
	return 1.0


## True when this hunter should be hidden by presentation logic alone. The brain
## never reads it; HunterView3D does.
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


## True for a gimmick whose hunter can never trigger a capture at all --
## Zephyra, who is a stationary shopkeeper the player stands right next to on
## every single trade. The original's merchant prep short-circuits her whole
## update before the shared capture-distance check ever runs; this is that
## same short-circuit, since HunterBrain.update()'s own check is otherwise
## unconditional.
func immune_to_capture() -> bool:
	return false


## Multiplies the brain's sight range (2D `gimmickModifiers.sightScale`: Ilyra 1.8, Mavrine's survey .7).
func sight_scale(_brain: HunterBrain) -> float:
	return 1.0


## True for a hunter who can sense and grab a player hidden in a hiding spot (2D `breachesHiding`/`breaksHiding`:
## Eirys, Loxelle). The brain then ignores the hidden flag while her last known point is within reach of it.
func breaches_hiding() -> bool:
	return false


## Small presentation/interaction state which a non-authoritative peer needs
## in addition to the shared HunterBrain fields. Timers and AI decisions stay
## host-only; subclasses expose only values a guest must render or consult
## while resolving its own input (Ceryth's riddle, Opalie's guard, etc.).
func network_state() -> Dictionary:
	return {}


func apply_network_state(_state: Dictionary) -> void:
	pass


## The one place a hunter id maps to her gimmick instance. Returns null for
## any id with no behavior-changing gimmick (tuning-only hunters like
## Dovelle, and every not-yet-ported id) — HunterBrain treats null as "skip
## every hook", so adding a hunter here is opt-in, never a stub to fill in.
static func for_id(hunter_id: String) -> HunterGimmick:
	match hunter_id:
		"white_wolf_spider":
			return WhiteWolfSpiderGimmick.new()
		"black_wolf_spider":
			return BlackWolfSpiderGimmick.new()
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
		"thessine":
			return ThessineGimmick.new()
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
		"jyvra":
			return JyvraGimmick.new()
		"loxelle":
			return LoxelleGimmick.new()
		"ceryth":
			return CerythGimmick.new()
		"briselle":
			return BriselleGimmick.new()
		"ferryn":
			return FerrynGimmick.new()
		"glyra":
			return GlyraGimmick.new()
		"ilyra":
			return IlyraGimmick.new()
		"verrine":
			return VerrineGimmick.new()
		"zephyra":
			return ZephyraGimmick.new()
		"void_black":
			return VoidBlackGimmick.new()
		"void_blue":
			return VoidBlueGimmick.new()
		"void_brown":
			return VoidBrownGimmick.new()
		"void_cyan":
			return VoidCyanGimmick.new()
		"void_green":
			return VoidGreenGimmick.new()
		"void_pink":
			return VoidPinkGimmick.new()
		"void_red":
			return VoidRedGimmick.new()
		"void_white":
			return VoidWhiteGimmick.new()
		"void_yellow":
			return VoidYellowGimmick.new()
		_:
			return null
