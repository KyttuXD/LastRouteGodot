class_name BlackWolfSpiderGimmick
extends WhiteWolfSpiderGimmick

## The rarer, more dangerous variant of the same species: it notices a runner from further away, hisses instead of barking (a
## longer, lower tell), runs faster and longer, waits longer between hunts, and IGNORES the flashlight: the only ways to end its
## hunt are a shelter, a hiding place, or outlasting it. Same telegraph first (the hiss, then 1.1 s of standing still).

const BLACK_ALERT_RADIUS := 19.0
const BLACK_BARK_SECONDS := 1.1
const BLACK_HUNT_SECONDS := 9.0
const BLACK_COOLDOWN_SECONDS := 60.0
const BLACK_HUNT_SPEED_SCALE := 1.05


func _init() -> void:
	alert_radius = BLACK_ALERT_RADIUS
	bark_seconds = BLACK_BARK_SECONDS
	hunt_seconds = BLACK_HUNT_SECONDS
	cooldown_seconds = BLACK_COOLDOWN_SECONDS
	hunt_speed_scale = BLACK_HUNT_SPEED_SCALE
	flash_hold = INF
	tell = "hiss"
