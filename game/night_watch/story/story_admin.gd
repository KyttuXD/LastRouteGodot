class_name StoryAdmin
extends RefCounted

## The Facility's admin section (NightWatchAdmin on the shared AdminMenu): the noise meter, the task list (jump to any task, force the current one done), go to any room, and the
## lift (ring the bell, open it, send it away). The generic controls (jump, the beacon as power, god, speed, hunters and their steps ...) come from the admin_* hooks StoryGame offers.

static func status(game: Node) -> String:
	return ""


static func entries(game: Node) -> Array:
	var out := []
	out.append({"heading": "NOISE", "permission": "world", "items": ["0", "25", "50", "80", "100"],
		"labels": {"0": "SILENT", "25": "25 (A DIAL CLICK)", "50": "50", "80": "80 (LOUD)", "100": "100 (EVERYONE HEARS)"},
		"action": func(id: String) -> void: game.call("admin_set_noise", float(id))})
	out.append({"label": "FORCE THE CURRENT TASK DONE", "permission": "world", "action": func() -> void: game.call("admin_complete_task")})
	var task_items := []
	var task_labels := {}
	var sim = game.get("sim")
	if sim != null:
		for i in (sim.tasks as Array).size():
			task_items.append(str(i))
			task_labels[str(i)] = "TASK %d: %s" % [i + 1, String(sim.tasks[i]["label"]).to_upper()]
	out.append({"heading": "JUMP TO TASK", "permission": "world", "items": task_items, "labels": task_labels,
		"action": func(id: String) -> void: game.call("admin_jump_to_task", int(id))})
	var room_items := []
	var room_labels := {}
	for room in StoryData.ROOMS:
		room_items.append(room)
		room_labels[room] = "GO TO %s" % String(StoryData.ROOMS[room]["label"])
	out.append({"heading": "GO TO A ROOM", "permission": "player", "items": room_items, "labels": room_labels,
		"action": func(id: String) -> void: game.call("admin_goto_room", id)})
	out.append({"heading": "THE LIFT", "permission": "hunters", "items": ["lift_away", "lift_bell", "lift_open"],
		"labels": {"lift_away": "SEND THE LIFT AWAY", "lift_bell": "RING THE BELL", "lift_open": "OPEN THE LIFT (QUENELLE)"},
		"action": func(id: String) -> void: game.call("admin_place_hunter", "quenelle", id)})
	return out
