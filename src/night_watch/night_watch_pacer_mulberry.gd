class_name NightWatchMulberryPacer
extends RefCounted

## core/time.js createPacer: how often a hunter moves. After each move she waits a random time from a three-second window that slides down
## with her level (level 1: 12.5 to 15.5 s, level 10: 8 to 11 s, level 20: 3 to 6 s); level 0 never moves. Draws from the shift's stream.

var _rng: NightWatchMulberry
var t := 0.0
var next_ms := -1.0   # -1 = none drawn yet


func _init(rng: NightWatchMulberry) -> void:
	_rng = rng


func _draw(level: int) -> float:
	var w := NightWatchData.move_window(level)
	return w.x + _rng.next() * (w.y - w.x)


## Advance by dt_ms at this level; true when she is due to move.
func step(dt_ms: float, level: int) -> bool:
	if level <= 0:
		t = 0.0
		next_ms = -1.0
		return false
	if next_ms < 0.0:
		next_ms = _draw(level)
	t += dt_ms
	if t < next_ms:
		return false
	t = 0.0
	next_ms = _draw(level)
	return true


func reset() -> void:
	t = 0.0
	next_ms = -1.0


## A nudge: she is that much nearer her move.
func skip(ms: float) -> void:
	t += ms
