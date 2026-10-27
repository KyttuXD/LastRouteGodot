class_name MaskControls
extends RefCounted

## Masked Hours' controls, ported from the 2D game's core/toggles.js and the control half of modes/mask/mask-logic.js: the mask and the camera monitor
## are one exclusive pair with short raise / lower times (they never share the screen; only a fully-on mask counts for the hunters; a press mid-
## transition is queued, the latest wins). Lights work only with both down and still; winding only with the monitor fully up on CAM 1; the vent
## lights also work on their own duct's camera. A held key is remembered (`held`), so a light or the wind comes back on its own once the panel is
## down / up. The desk lamp is a plain switch. Every input reaches the rules through press(); control_input() is what the rules see each frame.
## In 3D the physical stations (the mask on the desk, the monitor, the music box, the vent grates, the hall light) and the quick keys both call press().

const PANELS := {"mask": {"raise": 200.0, "lower": 150.0}, "monitor": {"raise": 250.0, "lower": 200.0}}
const HELD := ["lightL", "lightR", "lightH", "winKey", "winPtr"]

# the exclusive-panel machine (toggles.js)
var phase := "idle"        # idle, raising, up, lowering
var panel := ""
var t := 0.0
var gen := 0
var want := ""
# the controls around it
var cam := "music"
var held := {}
var lamp := false


func _init() -> void:
	for k in HELD:
		held[k] = false


func _dur() -> float:
	if phase == "raising":
		return float(PANELS[panel]["raise"])
	if phase == "lowering":
		return float(PANELS[panel]["lower"])
	return 0.0


func _begin(new_phase: String, p: String, ev: Array) -> void:
	phase = new_phase
	panel = p
	t = 0.0
	gen += 1
	ev.append({"type": "raise" if new_phase == "raising" else "lower", "panel": p, "gen": gen})


func _kick(ev: Array) -> void:
	if phase == "idle" and want != "":
		_begin("raising", want, ev)
	elif phase == "up" and want != panel:
		_begin("lowering", panel, ev)


func _finish(ev: Array) -> void:
	if phase == "raising":
		phase = "up"
		t = 0.0
		if want == panel:
			ev.append({"type": "up", "panel": panel, "gen": gen})
	elif phase == "lowering":
		ev.append({"type": "down", "panel": panel, "gen": gen})
		phase = "idle"
		panel = ""
		t = 0.0
	_kick(ev)


func is_up(p: String) -> bool:
	return phase == "up" and panel == p


func clear() -> bool:
	return phase == "idle"


func busy() -> bool:
	return phase == "raising" or phase == "lowering"


## How far panel `p` covers the screen, 0..1.
func cover(p: String) -> float:
	if panel != p:
		return 0.0
	if phase == "up":
		return 1.0
	var k := minf(1.0, t / _dur()) if _dur() > 0.0 else 1.0
	return k if phase == "raising" else 1.0 - k


## Everything down at once (night over, jump scare, quit).
func cancel() -> void:
	phase = "idle"
	panel = ""
	t = 0.0
	want = ""
	gen += 1


## One input, as a pure rule. Returns the toggle events it started. Actions: "mask" / "monitor" (a press on), "lightL" / "lightR" / "lightH" /
## "winKey" / "winPtr" (held down or let go; only one vent light at a time, the latest press wins), "lamp" (a press flips it), "cam:<room>".
func press(action: String, on := true) -> Array:
	var ev := []
	if action == "mask" or action == "monitor":
		if on:
			want = "" if want == action else action
			_kick(ev)
	elif action == "winKey" or action == "winPtr":
		held[action] = on
		if on and is_up("monitor"):
			cam = "music"
	elif action == "lightL" or action == "lightR":
		held[action] = on
		if on:
			held["lightR" if action == "lightL" else "lightL"] = false
	elif HELD.has(action):
		held[action] = on
	elif action == "lamp":
		if on:
			lamp = not lamp
			ev.append({"type": "lamp", "on": lamp})
	elif action.begins_with("cam:"):
		var room := action.substr(4)
		if is_up("monitor") and MaskData.ROOMS.has(room) and int(MaskData.ROOMS[room]["cam"]) > 0:
			cam = room
	else:
		push_error("MaskControls: unknown control %s" % action)
	return ev


## Advance by game time. A wind key already held when the monitor comes fully up jumps to CAM 1.
func step(dt_ms: float) -> Array:
	var ev := []
	var left := dt_ms
	var guard := 0
	while guard < 8 and (phase == "raising" or phase == "lowering"):
		guard += 1
		var need := _dur() - t
		if left < need:
			t += left
			break
		left -= need
		_finish(ev)
	if phase == "up":
		t += left
	if (bool(held["winKey"]) or bool(held["winPtr"])):
		for e in ev:
			if String(e["type"]) == "up" and String(e["panel"]) == "monitor":
				cam = "music"
	return ev


## What the rules see this frame (the lights need both panels down, or the duct camera for a vent light).
func control_input() -> Dictionary:
	var duct_up_l := is_up("monitor") and cam == MaskData.DUCT_CAM["L"]
	var duct_up_r := is_up("monitor") and cam == MaskData.DUCT_CAM["R"]
	return {
		"mask": is_up("mask"),
		"monitor": is_up("monitor"),
		"cam": cam,
		"lightL": bool(held["lightL"]) and (clear() or duct_up_l),
		"lightR": bool(held["lightR"]) and not bool(held["lightL"]) and (clear() or duct_up_r),
		"lightH": bool(held["lightH"]) and clear(),
		"winding": is_up("monitor") and cam == "music" and (bool(held["winKey"]) or bool(held["winPtr"])),
		"lamp": lamp,
	}
