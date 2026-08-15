class_name UmbrielGimmick
extends HunterGimmick

## Umbriel's shapeshifter (hunterAbilities.umbriel.shapeshifter). Ported from
## the Standard-difficulty half of the original: every
## UMBRIEL_DISGUISE_INTERVAL seconds she takes on another roster hunter's
## appearance. On Standard that is **purely cosmetic** — she keeps her own
## sight, hearing, radius, speed and abilities the whole time. Copying the
## disguised hunter's actual attributes is a Nightmare-only behaviour
## (`nightmareCopiesAbilities`), and no difficulty selection exists in this
## port, so it is genuinely absent rather than stubbed.
##
## Kathy is excluded from the pool, as in the original. The pool is drawn from
## HunterRoster.IMPLEMENTED_IDS, so it widens on its own as more hunters are
## ported — with a small roster she simply has fewer faces to wear.
##
## The disguise is presentation-only, so the brain never reads it:
## HunterView3D polls `disguise_id` and swaps its model when it changes.

var disguise_id := ""

var _timer := GameConfig.UMBRIEL_DISGUISE_INTERVAL


func before_perception(brain: HunterBrain, delta: float, _target: Dictionary, _generator: FacilityGenerator) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = GameConfig.UMBRIEL_DISGUISE_INTERVAL

	var pool: Array = []
	for id in HunterRoster.IMPLEMENTED_IDS:
		if id == brain.hunter_id or id == disguise_id:
			continue
		if id in GameConfig.UMBRIEL_DISGUISE_EXCLUDED:
			continue
		pool.append(id)
	if pool.is_empty():
		return
	disguise_id = pool[brain.next_random_index(pool.size())]
