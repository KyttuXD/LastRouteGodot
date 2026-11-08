class_name MixedAdmin
extends RefCounted

## Mixed Shift's admin section (NightWatchAdmin PROVIDERS): the ROTATION (play any of the nine maps, or the next one of the rotation; the next shift is the common JUMP TO SHIFT), ENDLESS's hour and roster re-draw, the director (force a spike),
## CHAOS events on demand, the doors and vents (shut, seal), the vent crawler's run, and threats on demand. The generic controls come from the hooks MixedGame offers. Every entry carries a permission scope.

static func status(game: Node) -> String:
	return "\n".join(PackedStringArray(game.call("admin_hunter_rows")))


static func entries(game: Node) -> Array:
	var out := []
	var skin_ids := []
	var skin_labels := {}
	for sk in MixedSkin.SKINS:
		skin_ids.append(String(sk["id"]))
		skin_labels[String(sk["id"])] = "%s (%s)" % [String(sk["name"]), String(sk["mode"]).to_upper()]
	out.append({"heading": "ROTATION: PLAY THIS MAP", "permission": "visual", "items": skin_ids, "labels": skin_labels,
		"action": func(id: String) -> void: game.call("admin_set_dressing", MixedSkin.index_of(id))})
	out.append({"label": "ROTATION: NEXT MAP IN THE ROTATION", "permission": "visual", "action": func() -> void: game.call("admin_set_dressing", MixedSkin.pick(int(game.get("seed_value")) + Time.get_ticks_msec()))})
	out.append({"heading": "ENDLESS: SET THE HOUR (NO DAWN)", "permission": "world", "items": ["3", "6", "9", "12"], "labels": {"3": "HOUR 3", "6": "HOUR 6", "9": "HOUR 9", "12": "HOUR 12"},
		"action": func(id: String) -> void: game.call("admin_set_hour", int(id))})
	out.append({"label": "ENDLESS: RE-DRAW THE ROSTER NOW", "permission": "world", "action": func() -> void: game.get("sim").admin_redraw_roster()})
	out.append({"label": "DIRECTOR: START THE NEXT SPIKE NOW", "permission": "world", "action": func() -> void: game.get("sim").admin_force_spike()})
	out.append({"heading": "CHAOS EVENT NOW", "permission": "world", "items": ["mood", "wake", "strain", "flicker", "decoy", "boxfast"],
		"labels": {"mood": "A MOOD SWAPS", "wake": "THE VENT CRAWLER STIRS", "strain": "THE SEALS STRAIN", "flicker": "A CAMERA FLICKERS", "decoy": "A DECOY TELL", "boxfast": "THE BOX RUNS DOWN FAST"},
		"action": func(id: String) -> void: game.get("sim").admin_force_chaos(id)})
	out.append({"heading": "DOORS", "permission": "world", "items": ["L_shut", "L_open", "R_shut", "R_open"], "labels": {"L_shut": "SHUT LEFT DOOR", "L_open": "OPEN LEFT DOOR", "R_shut": "SHUT RIGHT DOOR", "R_open": "OPEN RIGHT DOOR"},
		"action": func(id: String) -> void: game.call("admin_set_door", id.split("_")[0], id.ends_with("_shut"))})
	out.append({"heading": "VENT SEALS (HELD)", "permission": "world", "items": ["L_on", "L_off", "T_on", "T_off", "R_on", "R_off"],
		"labels": {"L_on": "SEAL LEFT VENT", "L_off": "RELEASE LEFT", "T_on": "SEAL TOP VENT", "T_off": "RELEASE TOP", "R_on": "SEAL RIGHT VENT", "R_off": "RELEASE RIGHT"},
		"action": func(id: String) -> void: game.call("set_seal", id.split("_")[0], id.ends_with("_on"))})
	out.append({"label": "VENT CRAWLER INTO THE RUN (CAM 9)", "permission": "hunters", "action": func() -> void:
		game.get("sim").admin_add_threat("verrine")
		game.call("admin_place_hunter", "verrine", "vent")})
	out.append({"label": "VENT CRAWLER AT THE LEFT VENT", "permission": "hunters", "action": func() -> void:
		game.get("sim").admin_add_threat("verrine")
		game.call("admin_place_hunter", "verrine", "ventL")})
	out.append({"label": "WINDER: STOP THE MUSIC BOX", "permission": "hunters", "action": func() -> void:
		game.get("sim").admin_add_threat("glyra")
		game.get("sim").threat("glyra")["tune"] = 0.0006})
	out.append({"label": "ALL THREATS HOME", "permission": "hunters", "action": func() -> void:
		for th in game.get("sim").list():
			game.get("sim").admin_send_home(String(th["id"]))})
	return out
