class_name VoidOrangeGimmick
extends VoidGimmick

## Orange Void, systemSaboteur (voids/orange.js): every 26 s she takes ONE of the runner's systems offline for 9 s: the flashlight (forced
## off and cannot be switched on), the climate control (the heater goes off) or the radar (the minimap and map go black). The system comes
## back by itself. The player side applies it (main_3d: system_outage event -> PlayerController3D.begin_outage, HUD radar overlay).

const INTERVAL := 26.0
const OUTAGE_SECONDS := 9.0
const SYSTEMS := ["flashlight", "climate", "radar"]

var active_system := ""
var _timer := 0.0
var _left := 0.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	_left = maxf(0.0, _left - delta)
	if _left <= 0.0:
		active_system = ""
	_timer += delta
	if _timer < INTERVAL or target.is_empty():
		return
	_timer = 0.0
	var system: String = SYSTEMS[brain.next_random_index(SYSTEMS.size())]
	active_system = system
	_left = OUTAGE_SECONDS
	brain.emit_world_event({"what": "system_outage", "system": system, "seconds": OUTAGE_SECONDS,
		"sound": "alert", "message": "%s OFFLINE // %ds" % [system.to_upper(), int(OUTAGE_SECONDS)]})


func network_state() -> Dictionary:
	return {"outage": active_system}


func apply_network_state(state: Dictionary) -> void:
	active_system = String(state.get("outage", ""))
