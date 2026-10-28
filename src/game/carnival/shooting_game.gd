class_name ShootingGame
extends CarnivalGame

## SHOOTING GALLERY: two rails of four tin targets that flip up for a moment. Aim and fire; a shot hits a target that is up under the crosshair. Eight shots; four hits win. LOUD.

const SHOTS := 8
const ROWS := 2
const COLS := 4
const UP_TIME := 1.5
const HIT_RADIUS := 0.15

var shots_left := SHOTS
## [{"at": Vector2, "up": bool, "t": float (time to the next flip), "hit": bool}]
var targets: Array = []


func _init(seed_number := 0) -> void:
	super(seed_number)
	seconds = 22.0
	for r in ROWS:
		for c in COLS:
			targets.append({"at": Vector2(-0.6 + float(c) * 0.4, 0.15 + float(r) * 0.42), "up": false, "t": rng.randf_range(0.3, 2.2), "hit": false})


func max_score() -> int:
	return SHOTS


func won() -> bool:
	return booth_score >= 4


func _tick(dt: float) -> void:
	for t in targets:
		t["t"] = float(t["t"]) - dt
		if float(t["t"]) <= 0.0:
			if bool(t["up"]):
				t["up"] = false
				t["hit"] = false
				t["t"] = rng.randf_range(0.8, 2.2)
			else:
				t["up"] = true
				t["t"] = UP_TIME
				events.append({"type": "pop"})


func _on_fire() -> void:
	if shots_left <= 0:
		return
	shots_left -= 1
	events.append({"type": "shot"})
	for t in targets:
		if bool(t["up"]) and not bool(t["hit"]) and (t["at"] as Vector2).distance_to(aim) <= HIT_RADIUS:
			t["hit"] = true
			t["up"] = false
			t["t"] = rng.randf_range(1.0, 2.2)
			booth_score += 1
			events.append({"type": "clang", "booth_score": booth_score})
			return


func _done() -> bool:
	return shots_left <= 0


func prompt() -> String:
	return "SHOOT THE TARGETS THAT FLIP UP.  %d SHOT%s LEFT  ·  %d HIT" % [shots_left, "" if shots_left == 1 else "S", booth_score]


func state() -> Dictionary:
	return {"targets": targets.duplicate(true), "shots_left": shots_left}
