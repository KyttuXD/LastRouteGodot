class_name PlaytestObserver
extends RefCounted

## Game-independent part of an observation (frame, time, performance, menus/buttons). Game adapters add the rest.

const MAX_BUTTONS := 40


static func base(tree: SceneTree) -> Dictionary:
	var scene := tree.current_scene
	return {
		"frame": Engine.get_physics_frames(),
		"time": snappedf(float(Engine.get_physics_frames()) / maxf(1.0, float(Engine.physics_ticks_per_second)), .001),
		"scene": scene.scene_file_path.get_file() if scene != null else "",
		"paused": tree.paused,
		"fps": Engine.get_frames_per_second(),
		"frame_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, .01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, .01),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"ui": ui(tree),
	}


## Visible buttons of the current scene (what a menu tour can press) and the focused control.
static func ui(tree: SceneTree) -> Dictionary:
	var scene := tree.current_scene
	var buttons: Array = []
	if scene != null:
		for node in scene.find_children("*", "BaseButton", true, false):
			var button := node as BaseButton
			if button == null or not button.is_visible_in_tree():
				continue
			buttons.append({
				"name": String(button.name),
				"text": (button as Button).text if button is Button else "",
				"disabled": button.disabled,
				"pressed": button.button_pressed,
			})
			if buttons.size() >= MAX_BUTTONS:
				break
	var focus := tree.root.gui_get_focus_owner() if tree.root != null else null
	return {"buttons": buttons, "focus": String(focus.name) if focus != null else ""}


## Stable hash of the interesting parts of an observation (positions to 1 cm), for determinism checks.
static func state_hash(obs: Dictionary) -> int:
	var keep := {}
	for key in ["frame", "scene", "run", "player", "world", "hunters"]:
		if obs.has(key):
			keep[key] = obs[key]
	return JSON.stringify(_rounded(keep)).hash()


static func _rounded(value: Variant) -> Variant:
	if value is float:
		return snappedf(value, .01)
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_rounded(item))
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _rounded(value[key])
		return out
	return value
