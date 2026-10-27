class_name BedroomAdmin
extends RefCounted

## Bedtime's admin section (NightWatchAdmin on the shared AdminMenu): which hand is down (the closet door, the hall light, the bed light), Haelith's creep (the sleep meter),
## making the house restless. The generic controls (jump, time, the battery as power, god, speed, reveal, hunters and where they stand ...) come from the admin_* hooks BedroomGame
## offers; "who stands where" is in the status tab.

static func status(game: Node) -> String:
	return ""


static func entries(game: Node) -> Array:
	var out := []
	out.append({"heading": "HAND (ONE AT A TIME)", "permission": "player", "items": ["hold", "hall", "bed", "none"],
		"labels": {"hold": "HOLD THE CLOSET DOOR", "hall": "LIGHT ON THE HALL", "bed": "LIGHT ON THE BED", "none": "NO HAND DOWN (DARK)"},
		"action": func(id: String) -> void: game.call("admin_set_hand", id)})
	out.append({"heading": "SLEEP METER (HAELITH CREEPING IN)", "permission": "hunters", "items": ["0", "25", "50", "75", "99"],
		"labels": {"0": "0% (FAR OFF)", "25": "25%", "50": "50% (SHE STIRS)", "75": "75%", "99": "99% (AT THE BED)"},
		"action": func(id: String) -> void: game.call("admin_set_creep", float(id))})
	out.append({"label": "MAKE THE HOUSE RESTLESS NOW", "permission": "hunters", "action": func() -> void: game.call("admin_make_restless")})
	return out
