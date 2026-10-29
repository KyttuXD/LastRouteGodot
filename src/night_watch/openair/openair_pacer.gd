class_name NightWatchOpenAirPacer
extends RefCounted

## The 2D core/time.js createPacer: how often a hunter moves. After each move she waits a random time chosen from a three-second window
## that slides down with her level (level 1: 12.5 to 15.5 s, level 10: 8 to 11 s, level 20: 3 to 6 s). Level 0 never moves.
## `rng` is a Callable returning 0..1 (a seeded stream, or a fixed roll in tests).

var t := 0.0
var next := -1.0   # -1 until her first wait is drawn
var rng: Callable


func _init(rng_callable: Callable) -> void:
	rng = rng_callable


func next_move_ms(level: int) -> float:
	var w := NightWatchData.move_window(level)
	return w.x + float(rng.call()) * (w.y - w.x)


## Advance by dt_ms at this level; true when she is due to move.
func step(dt_ms: float, level: int) -> bool:
	if not (level > 0):
		t = 0.0
		next = -1.0
		return false
	if next < 0.0:
		next = next_move_ms(level)
	t += dt_ms
	if t < next:
		return false
	t = 0.0
	next = next_move_ms(level)
	return true


func reset() -> void:
	t = 0.0
	next = -1.0


## A nudge: she is that much nearer her move.
func skip(ms: float) -> void:
	t += ms


func waited() -> float:
	return t
