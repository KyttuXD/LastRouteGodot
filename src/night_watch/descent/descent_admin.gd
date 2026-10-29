class_name NightWatchDescentAdmin
extends RefCounted

## The Descent's admin section (NightWatchAdmin provider): the elevator's depth (which stage is up), solving or dealing the stage again, the wrong-attempt count,
## Elise's closeness and window, and the door hold. The generic controls (jump to a descent, freeze, god, no jumpscare, speed, her AI level and place, the call, win / lose,
## reveal) come from the hooks NightWatchDescentGame offers. Every entry carries a permission scope.

static func status(game: Node) -> String:
	var sim: NightWatchDescentLogic = game.get("sim")
	return "STAGES  %s\nPUZZLE  %s" % [" > ".join(PackedStringArray(sim.stages)), sim.kind() if sim.over == "" else sim.over.to_upper()]


static func entries(game: Node) -> Array:
	var sim: NightWatchDescentLogic = game.get("sim")
	var depth := []
	var depth_labels := {}
	for i in sim.stages.size():
		depth.append(str(i + 1))
		depth_labels[str(i + 1)] = "FLOOR %d: %s" % [i + 1, NightWatchDescentData.STAGE_NAMES[sim.stages[i]]]
	var out := []
	out.append({"heading": "ELEVATOR DEPTH", "permission": "world", "items": depth, "labels": depth_labels,
		"action": func(id: String) -> void: game.call("admin_goto_stage", int(id))})
	out.append({"label": "SOLVE THIS STAGE", "permission": "world", "action": func() -> void: game.call("admin_solve_stage")})
	out.append({"label": "DEAL THIS PUZZLE AGAIN", "permission": "world", "action": func() -> void: game.call("admin_redeal")})
	out.append({"heading": "WRONG ATTEMPTS", "permission": "player", "items": ["add", "clear"], "labels": {"add": "ADD ONE", "clear": "CLEAR THE COUNT"},
		"action": func(id: String) -> void: game.call("admin_add_wrong", 1 if id == "add" else -int(game.get("sim").wrong))})
	out.append({"heading": "ELISE'S CLOSENESS", "permission": "hunters", "items": ["0", "30", "60", "90"], "labels": {"0": "0% (OUT OF SIGHT)", "30": "30%", "60": "60% (RED BAR)", "90": "90% (AT THE GLASS)"},
		"action": func(id: String) -> void: game.call("admin_set_closeness", float(id))})
	out.append({"label": "HOLD THE DOOR (LATCH ON)", "permission": "player", "state": func() -> bool: return bool(game.get("hold_down")),
		"action": func() -> void: game.call("admin_set_hold", not bool(game.get("hold_down")))})
	return out
