class_name ClawGame
extends CarnivalGame

## CLAW MACHINE: steer the claw over the prizes (move), drop it (fire). It goes down, closes, and brings up whatever it caught: a prize under it, held on a grip that is strong 3 times in 4 (stronger the more
## centred the claw is). Two drops. One prize wins. The aim plane is the cabinet floor seen from above: (x, z) in metres.

const DROPS := 2
const BOUNDS := 0.5
const SPEED := 0.45
const DROP_TIME := 1.1
const PRIZE_RADIUS := 0.13
const GRIP_BASE := 0.55

var pos := Vector2.ZERO
var drops_left := DROPS
## prize slots: [{"at": Vector2, "gone": bool}]
var prizes: Array = []
## "idle" | "down" | "up" (carrying)
var phase := "idle"
var phase_t := 0.0
var carried := -1
var _will_hold := false


func _init(seed_number := 0) -> void:
	super(seed_number)
	seconds = 30.0
	for i in 9:
		prizes.append({"at": Vector2(-0.38 + float(i % 3) * 0.38 + rng.randf_range(-0.05, 0.05), -0.36 + float(i / 3) * 0.36 + rng.randf_range(-0.05, 0.05)), "gone": false})


func max_score() -> int:
	return DROPS


func won() -> bool:
	return booth_score >= 1


func prize_under() -> int:
	var best := -1
	var best_d := PRIZE_RADIUS
	for i in prizes.size():
		if not prizes[i]["gone"] and (prizes[i]["at"] as Vector2).distance_to(pos) < best_d:
			best_d = (prizes[i]["at"] as Vector2).distance_to(pos)
			best = i
	return best


func _tick(dt: float) -> void:
	if phase == "idle":
		pos = (pos + move * SPEED * dt).clamp(Vector2(-BOUNDS, -BOUNDS), Vector2(BOUNDS, BOUNDS))
		if move.length() > 0.1 and int(elapsed * 6.0) != int((elapsed - dt) * 6.0):
			events.append({"type": "motor"})
		return
	phase_t += dt
	if phase == "down" and phase_t >= DROP_TIME:
		var under := prize_under()
		events.append({"type": "grip"})
		carried = -1
		_will_hold = false
		if under >= 0:
			var centred := 1.0 - (prizes[under]["at"] as Vector2).distance_to(pos) / PRIZE_RADIUS
			_will_hold = rng.randf() < GRIP_BASE + 0.3 * centred
			if _will_hold:
				carried = under
		phase = "up"
		phase_t = 0.0
	elif phase == "up" and phase_t >= DROP_TIME:
		phase = "idle"
		phase_t = 0.0
		if carried >= 0:
			prizes[carried]["gone"] = true
			booth_score += 1
			events.append({"type": "win", "booth_score": booth_score})
		else:
			events.append({"type": "miss"})
		carried = -1


func _on_fire() -> void:
	if phase != "idle" or drops_left <= 0:
		return
	drops_left -= 1
	phase = "down"
	phase_t = 0.0
	events.append({"type": "drop"})


func _done() -> bool:
	return drops_left <= 0 and phase == "idle"


func prompt() -> String:
	return "MOVE THE CLAW OVER A PRIZE, DROP IT.  %d DROP%s LEFT" % [drops_left, "" if drops_left == 1 else "S"]


func claw_height() -> float:
	if phase == "down":
		return 1.0 - minf(1.0, phase_t / DROP_TIME)
	if phase == "up":
		return minf(1.0, phase_t / DROP_TIME)
	return 1.0


func state() -> Dictionary:
	return {"pos": pos, "phase": phase, "height": claw_height(), "carried": carried, "prizes": prizes.duplicate(true), "drops_left": drops_left}
