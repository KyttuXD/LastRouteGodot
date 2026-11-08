class_name NightWatchPacer
extends RefCounted

## The pacer (createPacer): how often a hunter moves. There is no fixed tick: after each move she waits a random time from a three-second
## window that slides down with her level (NightWatchData.move_window). Level 0 never moves. Draws only from the stream it is given.

var rng: NightWatchStream
var t := 0.0
var next := -1.0   # -1 = none drawn yet (the 2D pacer's null)


func _init(stream: NightWatchStream) -> void:
	rng = stream


func _draw(level: int) -> float:
	var w := NightWatchData.move_window(level)
	return w.x + rng.next() * (w.y - w.x)


## Advance by dt_ms at this level; true when she is due to move.
func step(dt_ms: float, level: int) -> bool:
	if level <= 0:
		t = 0.0
		next = -1.0
		return false
	if next < 0.0:
		next = _draw(level)
	t += dt_ms
	if t < next:
		return false
	t = 0.0
	next = _draw(level)
	return true


func reset() -> void:
	t = 0.0
	next = -1.0


## A nudge: she is that much nearer her move.
func skip(ms: float) -> void:
	t += ms
