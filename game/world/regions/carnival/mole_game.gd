class_name MoleGame
extends CarnivalGame

## WHACK-A-MOLE: six holes; a mole pops up in a random one every so often and stays a moment. Aim at the hole and hit (fire) while it is up. Twenty seconds; six whacks win.

const HOLES := 6
const UP_TIME := 0.95
const SPAWN_EVERY := 0.7
const HIT_RADIUS := 0.19

var holes: Array = []
var up: Dictionary = {}   # hole index -> time left up
var _next := 0.6
var misses := 0


func _init(seed_number := 0) -> void:
	super(seed_number)
	seconds = 20.0
	for i in HOLES:
		holes.append(Vector2(-0.45 + float(i % 3) * 0.45, 0.18 + float(i / 3) * -0.4))


func max_score() -> int:
	return 30


func won() -> bool:
	return booth_score >= 6


func _tick(dt: float) -> void:
	for i in up.keys():
		up[i] = float(up[i]) - dt
		if float(up[i]) <= 0.0:
			up.erase(i)
	_next -= dt
	if _next <= 0.0:
		_next = SPAWN_EVERY * rng.randf_range(0.8, 1.2)
		var free := range(HOLES).filter(func(i): return not up.has(i))
		if not free.is_empty():
			var h := int(free[rng.randi() % free.size()])
			up[h] = UP_TIME
			events.append({"type": "pop", "hole": h})


func _on_fire() -> void:
	for i in up.keys():
		if (holes[i] as Vector2).distance_to(aim) <= HIT_RADIUS:
			up.erase(i)
			booth_score += 1
			events.append({"type": "hit", "hole": i, "booth_score": booth_score})
			return
	misses += 1
	events.append({"type": "miss_swing"})


func prompt() -> String:
	return "WHACK THE MOLES AS THEY POP UP.  %d WHACKED" % booth_score


func state() -> Dictionary:
	return {"holes": holes, "up": up.duplicate(), "misses": misses}
