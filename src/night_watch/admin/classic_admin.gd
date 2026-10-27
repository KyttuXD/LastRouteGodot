class_name NightWatchClassicAdmin
extends RefCounted

## Classic's admin section: the two doors and the door lights, a flat "all hunters to the doors" test, Kathy's meet-her-eyes forcing on Night 7. The generic controls (jump, time, power, god, hunters ...)
## come from the hooks NightWatchGame offers; see NightWatchAdmin. Entries need a "permission" (the shared scopes: world, player, hunters, visual, inventory).

static func status(game: Node) -> String:
	if not game.has_method("admin_hunter_rows"):
		return ""
	return "\n".join(PackedStringArray(game.call("admin_hunter_rows")))


static func entries(game: Node) -> Array:
	var out := []
	out.append({"heading": "DOORS", "permission": "world", "items": ["doorL_shut", "doorL_open", "doorR_shut", "doorR_open"],
		"labels": {"doorL_shut": "SHUT LEFT DOOR", "doorL_open": "OPEN LEFT DOOR", "doorR_shut": "SHUT RIGHT DOOR", "doorR_open": "OPEN RIGHT DOOR"},
		"action": func(id: String) -> void:
			game.call("admin_set_door", id.split("_")[0], id.ends_with("_shut"))})
	out.append({"heading": "DOOR LIGHTS", "permission": "world", "items": ["doorL_on", "doorL_off", "doorR_on", "doorR_off"],
		"labels": {"doorL_on": "LEFT LIGHT ON", "doorL_off": "LEFT LIGHT OFF", "doorR_on": "RIGHT LIGHT ON", "doorR_off": "RIGHT LIGHT OFF"},
		"action": func(id: String) -> void:
			game.call("set_light", id.split("_")[0], id.ends_with("_on"))})
	out.append({"label": "ALL HUNTERS TO THEIR DOORS", "permission": "hunters", "action": func() -> void: game.call("admin_all_to_doors")})
	if game.get("sim") != null and bool((game.get("sim") as NightWatchClassic).kathy_night):
		out.append({"label": "KATHY: FORCE MEET HER EYES", "permission": "hunters", "action": func() -> void: game.call("admin_force_meet")})
	return out
