class_name VoidPurpleGimmick
extends VoidGimmick

## Purple Void, radarCorrupter (voids/purple.js): every 21 s she corrupts the radar into static for 8 s; each corruption has a 35 %
## chance to black it out completely for 11 s instead. The player side applies it (main_3d: radar_corrupt event -> HUD radar overlay on
## the minimap and the full map; the 3D game's radar is the minimap).

const INTERVAL := 21.0
const STATIC_SECONDS := 8.0
const BLACKOUT_CHANCE := .35
const BLACKOUT_SECONDS := 11.0

var mode := ""
var _timer := 0.0
var _left := 0.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	_left = maxf(0.0, _left - delta)
	if _left <= 0.0:
		mode = ""
	_timer += delta
	if _timer < INTERVAL or target.is_empty():
		return
	_timer = 0.0
	if brain.next_random_float() < BLACKOUT_CHANCE:
		mode = "blackout"
		_left = BLACKOUT_SECONDS
		brain.world_events.append({"what": "radar_corrupt", "mode": "blackout", "seconds": BLACKOUT_SECONDS,
			"sound": "alert", "message": "RADAR DEAD // REBOOTING"})
	else:
		mode = "static"
		_left = STATIC_SECONDS
		brain.world_events.append({"what": "radar_corrupt", "mode": "static", "seconds": STATIC_SECONDS,
			"sound": "alert", "message": "RADAR CORRUPTED"})


func network_state() -> Dictionary:
	return {"radar": mode}


func apply_network_state(state: Dictionary) -> void:
	mode = String(state.get("radar", ""))
