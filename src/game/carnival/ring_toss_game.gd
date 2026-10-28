class_name RingTossGame
extends CarnivalGame

## RING TOSS: five bottle necks on a turning disc and three rings. Aim at the disc and throw (fire); a ring lands where the crosshair was, a little off, after a short flight, and goes round a neck only if a
## neck is under it at that moment. Two necks of three wins. The aim plane is the disc's plane, centred on its axis; the disc turns, so the aim has to lead it.

const NECKS := 5
const DISC_RADIUS := 0.62
const NECK_RADIUS := 0.13
const TURN_SPEED := 0.85   # rad/s
const FLIGHT := 0.45
const RINGS := 3
const SPREAD := 0.05

var rings_left := RINGS
var angle := 0.0
## [{"at": Vector2 (landing point), "t": float (time left in the air), "hit": int (neck index or -1)}]
var flying: Array = []
var on_necks := {}   # neck index -> true
var thrown := 0


func _init(seed_number := 0) -> void:
	super(seed_number)
	seconds = 24.0
	angle = rng.randf() * TAU


func max_score() -> int:
	return RINGS


func won() -> bool:
	return booth_score >= 2


func neck_position(index: int, at_angle := angle) -> Vector2:
	var a := at_angle + float(index) * TAU / float(NECKS)
	return Vector2(cos(a), sin(a)) * DISC_RADIUS * 0.72


func _tick(dt: float) -> void:
	angle += TURN_SPEED * dt
	for ring in flying:
		ring["t"] = float(ring["t"]) - dt
	var landed := flying.filter(func(r): return float(r["t"]) <= 0.0)
	flying = flying.filter(func(r): return float(r["t"]) > 0.0)
	for ring in landed:
		var hit := -1
		for i in NECKS:
			if not on_necks.has(i) and neck_position(i).distance_to(ring["at"]) <= NECK_RADIUS:
				hit = i
				break
		if hit >= 0:
			on_necks[hit] = true
			booth_score += 1
			events.append({"type": "ring_on", "neck": hit, "booth_score": booth_score})
		else:
			events.append({"type": "ring_miss", "at": ring["at"]})


func _on_fire() -> void:
	if rings_left <= 0:
		return
	rings_left -= 1
	thrown += 1
	var wobble := Vector2(rng.randf_range(-SPREAD, SPREAD), rng.randf_range(-SPREAD, SPREAD))
	flying.append({"at": aim + wobble, "t": FLIGHT, "from": aim})
	events.append({"type": "throw", "at": aim + wobble})


func _done() -> bool:
	return rings_left <= 0 and flying.is_empty()


func prompt() -> String:
	return "AIM AT THE TURNING NECKS, THROW. %d RING%s LEFT  ·  %d ON" % [rings_left, "" if rings_left == 1 else "S", booth_score]


func state() -> Dictionary:
	return {"angle": angle, "necks": NECKS, "on": on_necks.keys(), "rings_left": rings_left, "flying": flying.duplicate(true)}
