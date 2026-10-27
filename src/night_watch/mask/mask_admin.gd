class_name MaskAdmin
extends RefCounted

## Masked Hours' admin section (NightWatchAdmin PROVIDERS): the mask on / off and Thessine's mask timer, the music box, the vent lights and the hall light, the flashlight, the desk lamp, and the hall hunters
## and vent hunters on demand. The generic controls (jump, time, battery as "power", god, hunters, calls ...) come from the hooks MaskGame offers. Every entry carries a permission scope.

static func status(game: Node) -> String:
	return "\n".join(PackedStringArray(game.call("admin_hunter_rows")))


static func entries(game: Node) -> Array:
	var out := []
	out.append({"heading": "MASK", "permission": "player", "items": ["on", "off"], "labels": {"on": "PUT THE MASK ON", "off": "TAKE THE MASK OFF"},
		"action": func(id: String) -> void: game.call("admin_set_mask", id == "on")})
	out.append({"heading": "THESSINE'S MASK TIMER (MS FOOLED, LEAVES AT 2500)", "permission": "hunters", "items": ["0", "1000", "2000", "2400"],
		"labels": {"0": "0 (JUST ARRIVED)", "1000": "1000", "2000": "2000", "2400": "2400 (ABOUT TO LEAVE)"},
		"action": func(id: String) -> void: game.call("admin_set_mask_timer", float(id))})
	out.append({"heading": "MUSIC BOX", "permission": "world", "items": ["100", "50", "10", "0"], "labels": {"100": "WOUND (100%)", "50": "50%", "10": "10%", "0": "EMPTY (GLYRA COMES IN 6 S)"},
		"action": func(id: String) -> void: game.call("admin_set_box", float(id))})
	out.append({"heading": "VENT LIGHTS (HELD)", "permission": "player", "items": ["L_on", "L_off", "R_on", "R_off"],
		"labels": {"L_on": "LEFT VENT LIGHT ON", "L_off": "LEFT VENT LIGHT OFF", "R_on": "RIGHT VENT LIGHT ON", "R_off": "RIGHT VENT LIGHT OFF"},
		"action": func(id: String) -> void: game.call("press", "lightL" if id.begins_with("L") else "lightR", id.ends_with("_on"))})
	out.append({"heading": "HALL LIGHT (HELD)", "permission": "player", "items": ["on", "off"], "labels": {"on": "HALL LIGHT ON", "off": "HALL LIGHT OFF"},
		"action": func(id: String) -> void: game.call("press", "lightH", id == "on")})
	out.append({"label": "FLASH THE HALL LIGHT ONCE", "permission": "player", "action": func() -> void: game.call("admin_flash_hall")})
	out.append({"label": "TOGGLE THE DESK LAMP", "permission": "player", "action": func() -> void: game.call("press", "lamp")})
	out.append({"label": "THESSINE INTO THE OFFICE", "permission": "hunters", "action": func() -> void: game.call("admin_place_hunter", "thessine", "office")})
	out.append({"label": "UMBRIEL RUNS THE MAIN HALL", "permission": "hunters", "action": func() -> void: game.call("admin_place_hunter", "umbriel", "hall")})
	out.append({"label": "VERRINE TO THE LEFT VENT", "permission": "hunters", "action": func() -> void: game.call("admin_place_hunter", "verrine", "ventL")})
	out.append({"label": "ALL HUNTERS HOME", "permission": "hunters", "action": func() -> void: game.call("admin_all_home")})
	return out
