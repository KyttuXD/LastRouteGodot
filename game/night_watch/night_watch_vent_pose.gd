class_name NightWatchVentPose
extends RefCounted

## The hunters' vent crawl for the Night Watch modes that have vent shafts (Masked Hours' ducts, Mixed Shift's vent run): while a hunter is in a shaft she takes the "vent" pose (Verrine's
## own belly-low crawl, the generic all-fours crawl for the others), Verrine drops into it with the one-shot "vent_enter" and rises out of it with "vent_exit" (NightWatchPoses.play_state;
## the pose data has the drop and rise for Verrine only). The shafts are at least 0.8 m high and the crawl stays under 0.67 m. One instance per game scene; call `update()` for every hunter
## every frame; it returns true while a vent pose owns the model (the caller then skips its walk / idle clip).

const ENTER_S := 0.8
const EXIT_S := 0.8

var _phase := {}     # hunter id -> "" | "enter" | "crawl" | "exit"
var _left := {}      # hunter id -> seconds left in a one-shot
var _speed := {}     # hunter id -> the crawl speed last played


func state_of(id: String) -> String:
	match String(_phase.get(id, "")):
		"enter":
			return "vent_enter"
		"crawl":
			return "vent"
		"exit":
			return "vent_exit"
	return ""


func update(id: String, model: Node3D, in_shaft: bool, moving: bool, delta: float) -> bool:
	var phase := String(_phase.get(id, ""))
	var speed := 1.0 if moving else 0.35
	if in_shaft:
		if phase == "" or phase == "exit":
			if NightWatchPoses.play_state(model, "vent_enter", {"hunter_id": id}):
				_phase[id] = "enter"
				_left[id] = ENTER_S
			else:
				_start_crawl(id, model, speed)
			return true
		if phase == "enter":
			_left[id] = float(_left[id]) - delta
			if float(_left[id]) <= 0.0:
				_start_crawl(id, model, speed)
			return true
		if absf(float(_speed.get(id, speed)) - speed) > 0.01:
			_start_crawl(id, model, speed)
		return true
	if phase == "enter" or phase == "crawl":
		if NightWatchPoses.play_state(model, "vent_exit", {"hunter_id": id}):
			_phase[id] = "exit"
			_left[id] = EXIT_S
			return true
		NightWatchPoses.stop(model)
		_phase[id] = ""
		return false
	if phase == "exit":
		_left[id] = float(_left[id]) - delta
		if float(_left[id]) <= 0.0:
			NightWatchPoses.stop(model)
			_phase[id] = ""
			return false
		return true
	return false


func _start_crawl(id: String, model: Node3D, speed: float) -> void:
	_phase[id] = "crawl"
	_speed[id] = speed
	NightWatchPoses.play_state(model, "vent", {"hunter_id": id, "speed": speed})
