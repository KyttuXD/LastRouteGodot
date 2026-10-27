class_name LureAdmin
extends RefCounted

## Dead Air's admin section (NightWatchAdmin on the shared AdminMenu): lure Xivvy now, force her to a room or a vent opening, break or fix a system, seal or open a vent,
## set the temperature and the appliances, refill the air. The generic controls (jump, time, air as power, god, speed, hunters and where they are ...) come from the admin_*
## hooks LureGame offers. Each entry carries a permission scope and calls a public hook, never a test-only path.

static func status(game: Node) -> String:
	return ""


static func entries(game: Node) -> Array:
	var out := []
	var lure_items := []
	var lure_labels := {}
	for room in LureData.ROOMS:
		if not String(room).begins_with("vent"):
			lure_items.append(room)
			lure_labels[room] = "LURE TO %s" % String(LureData.INFO[room]["label"])
	out.append({"heading": "LURE XIVVY NOW (NO COOLDOWN, NO AUDIO)", "permission": "hunters", "items": lure_items, "labels": lure_labels,
		"action": func(id: String) -> void: game.call("admin_force_lure", id)})
	out.append({"label": "RESET THE LURE COOLDOWN", "permission": "hunters", "action": func() -> void: game.call("admin_reset_lure_cooldown")})
	var vent_labels := {"ventl": "XIVVY TO THE LEFT CRAWLSPACE", "ventr": "XIVVY TO THE RIGHT CRAWLSPACE", "officeL": "XIVVY AT THE LEFT VENT OPENING", "officeR": "XIVVY AT THE RIGHT VENT OPENING"}
	out.append({"heading": "FORCE XIVVY TO A VENT", "permission": "hunters", "items": ["ventl", "ventr", "officeL", "officeR"], "labels": vent_labels,
		"action": func(id: String) -> void: game.call("admin_place_hunter", "xivvy", id)})
	var sys_items := []
	var sys_labels := {}
	for name in LureData.SYSTEMS:
		sys_items.append("%s_break" % name)
		sys_items.append("%s_fix" % name)
		sys_labels["%s_break" % name] = "BREAK %s" % String(LureData.SYSTEMS[name]["label"])
		sys_labels["%s_fix" % name] = "FIX %s" % String(LureData.SYSTEMS[name]["label"])
	out.append({"heading": "SYSTEMS", "permission": "world", "items": sys_items, "labels": sys_labels,
		"action": func(id: String) -> void:
			var parts := id.split("_")
			game.call("admin_set_system", parts[0], parts[1] == "break")})
	out.append({"heading": "VENT SEALS", "permission": "world", "items": ["L_on", "L_off", "R_on", "R_off"],
		"labels": {"L_on": "SEAL LEFT VENT", "L_off": "OPEN LEFT VENT", "R_on": "SEAL RIGHT VENT", "R_off": "OPEN RIGHT VENT"},
		"action": func(id: String) -> void:
			var parts := id.split("_")
			game.call("admin_set_seal", parts[0], parts[1] == "on")})
	out.append({"heading": "TEMPERATURE", "permission": "world", "items": ["40", "58", "70", "96", "115"],
		"labels": {"40": "40 F (FREEZING)", "58": "58 F (COLD LINE)", "70": "70 F", "96": "96 F (HEAT LINE)", "115": "115 F (ROASTING)"},
		"action": func(id: String) -> void: game.call("admin_set_temperature", float(id))})
	out.append({"heading": "APPLIANCES", "permission": "world", "items": ["heater_on", "heater_off", "fan_on", "fan_off"],
		"labels": {"heater_on": "HEATER ON", "heater_off": "HEATER OFF", "fan_on": "FAN ON", "fan_off": "FAN OFF"},
		"action": func(id: String) -> void:
			var parts := id.split("_")
			game.call("admin_set_appliance", parts[0], parts[1] == "on")})
	out.append({"label": "CLEAR THE COLD AND THE HEAT (70 F)", "permission": "world", "action": func() -> void: game.call("admin_clear_climate")})
	return out
