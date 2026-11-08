class_name ThessineGimmick
extends HunterGimmick

## Thessine's sound mimic. The original evaluates one roll every ten seconds;
## on success it either borrows another active hunter's real cue or plays an
## uncanny fallback. The decision is made by the authoritative brain and sent
## as a world event, while main_3d resolves the procedural sound locally for
## every peer. Co-op hears one shared deception without simulation owning an
## AudioStreamPlayer.

var _timer := GameConfig.THESSINE_MIMIC_INTERVAL


func before_perception(brain: HunterBrain, delta: float, _target: Dictionary,
		_generator) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	# Preserve overrun instead of starting a fresh interval. A slow frame cannot
	# make the long-term ten-second cadence drift later and later.
	_timer += GameConfig.THESSINE_MIMIC_INTERVAL
	if brain.next_random_float() >= GameConfig.THESSINE_MIMIC_CHANCE:
		return
	brain.emit_world_event({
		"what": "thessine_mimic",
		"rare": brain.next_random_float() < GameConfig.THESSINE_MIMIC_RARE_CHANCE,
		"choice": brain.next_random_float(),
	})
