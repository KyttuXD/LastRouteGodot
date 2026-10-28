class_name DuckGame
extends CarnivalGame

## DUCK POND: ducks drift round the pond; one wears a marker. Aim at the marked duck and hook it (fire). Five hooks; two marked ducks caught wins. The marker moves to another duck after each catch.

const DUCKS := 8
const HOOKS := 5
const HIT_RADIUS := 0.15
const SPEED := 0.55

var ducks: Array = []   # angle per duck
var marked := 0
var hooks_left := HOOKS


func _init(seed_number := 0) -> void:
	super(seed_number)
	seconds = 24.0
	for i in DUCKS:
		ducks.append(float(i) * TAU / float(DUCKS) + rng.randf_range(-0.1, 0.1))
	marked = rng.randi() % DUCKS


func max_score() -> int:
	return HOOKS


func won() -> bool:
	return booth_score >= 2


func duck_position(index: int, angle: float = -999.0) -> Vector2:
	var a := float(ducks[index]) if angle < -900.0 else angle
	return Vector2(cos(a) * 0.62, sin(a) * 0.26)


func _tick(dt: float) -> void:
	for i in DUCKS:
		ducks[i] = float(ducks[i]) + SPEED * dt * (1.0 if i % 2 == 0 else 0.7)


func _on_fire() -> void:
	if hooks_left <= 0:
		return
	hooks_left -= 1
	events.append({"type": "hook"})
	if duck_position(marked).distance_to(aim) <= HIT_RADIUS:
		booth_score += 1
		events.append({"type": "win", "booth_score": booth_score})
		marked = (marked + 1 + rng.randi() % (DUCKS - 1)) % DUCKS
	else:
		events.append({"type": "splash"})


func _done() -> bool:
	return hooks_left <= 0


func prompt() -> String:
	return "HOOK THE MARKED DUCK.  %d HOOK%s LEFT  ·  %d CAUGHT" % [hooks_left, "" if hooks_left == 1 else "S", booth_score]


func state() -> Dictionary:
	return {"ducks": ducks.duplicate(), "marked": marked, "hooks_left": hooks_left}
