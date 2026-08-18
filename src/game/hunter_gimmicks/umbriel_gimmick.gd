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
## Kathy is excluded from the pool, as in the original.
##
## The pool is the whole ROSTER, not the implemented pool. A disguise is a model
## and a name — the brain never reads it, HunterView3D polls `disguise_id` and
## swaps its model — so she can wear the face of a hunter whose AI is not
## ported. Drawing from the implemented pool instead would have made her a
## walking progress bar for the port, showing the player only the faces of
## hunters that happen to be finished.

var disguise_id := ""

var _timer := GameConfig.UMBRIEL_DISGUISE_INTERVAL


func before_perception(brain: HunterBrain, delta: float, _target: Dictionary, _generator) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = GameConfig.UMBRIEL_DISGUISE_INTERVAL

	var excluded: Array = GameConfig.UMBRIEL_DISGUISE_EXCLUDED.duplicate()
	excluded.append(brain.hunter_id)
	if not disguise_id.is_empty():
		excluded.append(disguise_id)
	var pool := HunterRoster.disguise_ids(excluded)
	if pool.is_empty():
		return
	disguise_id = pool[brain.next_random_index(pool.size())]
