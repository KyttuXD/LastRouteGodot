class_name DayshiftAdmin
extends RefCounted

## Salvage Run's admin section (NightWatchAdmin PROVIDERS): the money and the quota, the rack's pieces, the upgrades, the noise, the doors and their lights, the window (Ysolde's knock) and the door visitors on demand.
## (The 2D mode has no hull or oxygen: its limits are the budget, the quota, the power and the noise.) The generic controls come from the hooks DayshiftGame offers. Every entry carries a permission scope.

static func status(game: Node) -> String:
	return "\n".join(PackedStringArray(game.call("admin_hunter_rows")))


static func entries(game: Node) -> Array:
	var out := []
	out.append({"heading": "MONEY (SCRAP TAKEN)", "permission": "world", "items": ["0", "100", "250", "quota"], "labels": {"0": "$0", "100": "$100", "250": "$250", "quota": "THE QUOTA"},
		"action": func(id: String) -> void: game.call("admin_set_money", int(game.get("sim").need) if id == "quota" else int(id))})
	out.append({"heading": "QUOTA", "permission": "world", "items": ["100", "210", "340", "9999"], "labels": {"100": "$100", "210": "$210 (WEEK 2)", "340": "$340 (WEEK 4)", "9999": "$9999 (UNREACHABLE)"},
		"action": func(id: String) -> void: game.call("admin_set_quota", int(id))})
	out.append({"heading": "RACK", "permission": "world", "items": ["scrap", "parts", "prize", "clear"], "labels": {"scrap": "ADD SCRAP ($10)", "parts": "ADD PARTS ($25)", "prize": "ADD A PRIZE ($60)", "clear": "CLEAR THE RACK"},
		"action": func(id: String) -> void:
			if id == "clear":
				game.call("admin_clear_rack")
			else:
				game.call("admin_add_piece", id)})
	out.append({"heading": "UPGRADES", "permission": "player", "items": ["all", "none"], "labels": {"all": "GRANT ALL FIVE", "none": "TAKE THEM ALL BACK"},
		"action": func(id: String) -> void: game.call("admin_grant_upgrades", id == "all")})
	out.append({"heading": "NOISE", "permission": "world", "items": ["0", "30", "50", "100"], "labels": {"0": "SILENT", "30": "UNEASY (30)", "50": "LOUD (50)", "100": "100"},
		"action": func(id: String) -> void: game.call("admin_set_noise", float(id))})
	out.append({"heading": "DOORS", "permission": "world", "items": ["doorL_shut", "doorL_open", "doorR_shut", "doorR_open"],
		"labels": {"doorL_shut": "SHUT LEFT DOOR", "doorL_open": "OPEN LEFT DOOR", "doorR_shut": "SHUT RIGHT DOOR", "doorR_open": "OPEN RIGHT DOOR"},
		"action": func(id: String) -> void: game.call("admin_set_door", id.split("_")[0], id.ends_with("_shut"))})
	out.append({"heading": "DOOR LIGHTS", "permission": "world", "items": ["doorL_on", "doorL_off", "doorR_on", "doorR_off"],
		"labels": {"doorL_on": "LEFT LIGHT ON", "doorL_off": "LEFT LIGHT OFF", "doorR_on": "RIGHT LIGHT ON", "doorR_off": "RIGHT LIGHT OFF"},
		"action": func(id: String) -> void: game.call("set_light", id.split("_")[0], id.ends_with("_on"))})
	out.append({"label": "YSOLDE KNOCKS AT THE WINDOW NOW", "permission": "hunters", "action": func() -> void: game.call("admin_place_hunter", "ysolde", "near")})
	out.append({"label": "YSOLDE AT THE GLASS (BE QUIET)", "permission": "hunters", "action": func() -> void: game.call("admin_place_hunter", "ysolde", "window")})
	out.append({"label": "SEND YSOLDE AWAY", "permission": "hunters", "action": func() -> void: game.call("admin_place_hunter", "ysolde", "far")})
	out.append({"label": "BOTH VISITORS ONE STEP FROM THEIR DOORS", "permission": "hunters", "action": func() -> void: game.call("admin_all_to_doors")})
	return out
