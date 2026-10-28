class_name StrengthGame
extends CarnivalGame

## STRENGTH TESTER: a meter sweeps up and down; HOLD (fire) to wind up the mallet and RELEASE to swing, and the puck climbs as far as the meter said. The bell rings from 92%. Three swings; ringing the bell
## once wins. Each swing is faster than the last. The bell is the loudest thing in the carnival.

const SWINGS := 3
const BELL_AT := 0.92
const BASE_PERIOD := 1.25   # seconds for one full sweep up and down

var swings_left := SWINGS
var meter := 0.0
var best_power := 0.0
var rang := false
## the puck's height 0..1 of the current / last swing and whether it is travelling
var puck := 0.0
var puck_target := 0.0
var puck_rising := false
var _phase := 0.0
var _rest := 0.0


func _init(seed_number := 0) -> void:
	super(seed_number)
	seconds = 20.0
	_phase = rng.randf()


func max_score() -> int:
	return 1


func won() -> bool:
	return booth_score >= 1


func _period() -> float:
	return BASE_PERIOD * pow(0.82, float(SWINGS - swings_left))


func _tick(dt: float) -> void:
	if _rest > 0.0:
		_rest -= dt
	if holding and swings_left > 0 and not puck_rising:
		_phase = fposmod(_phase + dt / _period(), 1.0)
		meter = 1.0 - absf(_phase * 2.0 - 1.0)
	if puck_rising:
		puck = minf(puck_target, puck + dt * 1.6)
		if puck >= puck_target:
			puck_rising = false
			_rest = 0.9
			if puck_target >= BELL_AT:
				rang = true
				booth_score = 1
				events.append({"type": "bell", "power": puck_target})
			else:
				events.append({"type": "thud", "power": puck_target})


func _on_fire() -> void:
	pass   # the swing happens on release


func _on_hold(on: bool) -> void:
	if on:
		if swings_left > 0 and not puck_rising and _rest <= 0.0:
			puck = 0.0
			events.append({"type": "windup"})
	elif swings_left > 0 and not puck_rising and _rest <= 0.0 and meter > 0.0:
		swings_left -= 1
		puck_target = meter
		best_power = maxf(best_power, meter)
		puck_rising = true
		events.append({"type": "swing", "power": meter})
		meter = 0.0


func _done() -> bool:
	return rang and not puck_rising or (swings_left <= 0 and not puck_rising and _rest <= 0.0)


func prompt() -> String:
	return "HOLD TO WIND UP, RELEASE ON A HIGH METER  ·  %d SWING%s LEFT" % [swings_left, "" if swings_left == 1 else "S"]


func state() -> Dictionary:
	return {"meter": meter, "puck": puck, "rising": puck_rising, "swings_left": swings_left, "rang": rang, "best": best_power}
