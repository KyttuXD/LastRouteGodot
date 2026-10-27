class_name NightWatchOpenAirAdmin
extends RefCounted

## Open Air's admin section (NightWatchAdmin provider): the controls of the watch that is up (rooftop: lantern, oil, the door she is at; bus stop: warmth, fuel, chill, a canister,
## the bus; campfire: fire, logs, the rain, Verrine's mood), plus the weather. The generic controls (jump to a watch, set the hour, freeze, god, no jumpscare, speed, each hunter's AI
## level and step, the call, reveal, noclip, win / lose) come from the hooks NightWatchOpenAirGame offers. Every entry carries a permission scope.

static func status(game: Node) -> String:
	var sim: NightWatchOpenAirLogic = game.get("sim")
	match sim.watch:
		0:
			return "LANTERN %s  OIL %d%%  TORCH %d%%  HER DOOR %s (%d steps out)" % ["ON" if sim.lantern else "OUT", int(sim.oil), int(sim.torch), sim.v.side, sim.v.dist]
		1:
			return "WARM %d%%  FUEL %d%%  CHILL %d%%  CANISTERS %d  BUS %d%%" % [int(sim.warm), int(sim.fuel), int(sim.chill), sim.cans.size(), int(sim.bus * 100.0)]
	return "FIRE %d%%  LOGS %d  MOOD %s  YSOLDE AT %d  VERRINE %d  QUENELLE %d" % [int(sim.fire), sim.logs, sim.mood_kind, sim.y.dist, sim.v.dist, sim.q.dist]


static func entries(game: Node) -> Array:
	var sim: NightWatchOpenAirLogic = game.get("sim")
	var out := []
	match sim.watch:
		0:
			out.append({"heading": "LANTERN", "permission": "world", "items": ["on", "out"], "labels": {"on": "LIGHT THE LANTERN", "out": "BLOW IT OUT"},
				"action": func(id: String) -> void: game.call("admin_set", "lantern", id == "on")})
			out.append({"heading": "OIL", "permission": "player", "items": ["100", "50", "10", "0"], "labels": {"100": "100%", "50": "50%", "10": "10%", "0": "0% (WINCHES STOP)"},
				"action": func(id: String) -> void: game.call("admin_set", "oil", float(id))})
			out.append({"heading": "HER DOOR", "permission": "hunters", "items": ["L", "R"], "labels": {"L": "THE STAIR DOOR (LEFT)", "R": "THE HATCH (RIGHT)"},
				"action": func(id: String) -> void: game.call("admin_set_side", id)})
		1:
			out.append({"heading": "WARMTH", "permission": "player", "items": ["100", "50", "10"], "labels": {"100": "100%", "50": "50%", "10": "10% (BITING)"},
				"action": func(id: String) -> void: game.call("admin_set", "warm", float(id))})
			out.append({"heading": "FUEL", "permission": "player", "items": ["100", "50", "0"], "labels": {"100": "100%", "50": "50%", "0": "0% (LAMP DRY)"},
				"action": func(id: String) -> void: game.call("admin_set", "fuel", float(id))})
			out.append({"heading": "CHILL", "permission": "hunters", "items": ["0", "50", "90"], "labels": {"0": "0%", "50": "50%", "90": "90% (ABOUT TO FREEZE)"},
				"action": func(id: String) -> void: game.call("admin_set", "chill", float(id))})
			out.append({"label": "DROP A CANISTER NOW", "permission": "world", "action": func() -> void: game.call("admin_set", "can", 1)})
			out.append({"label": "CALL THE BUS (LAST 18 SECONDS)", "permission": "world", "action": func() -> void: game.call("admin_set", "bus", 1)})
		_:
			out.append({"heading": "FIRE", "permission": "player", "items": ["100", "50", "10", "0"], "labels": {"100": "100%", "50": "50%", "10": "10% (LOW: THEY GET BOLDER)", "0": "0% (OUT)"},
				"action": func(id: String) -> void: game.call("admin_set", "fire", float(id))})
			out.append({"heading": "LOGS", "permission": "player", "items": ["0", "6", "12"], "labels": {"0": "NONE", "6": "6", "12": "12"},
				"action": func(id: String) -> void: game.call("admin_set", "logs", int(id))})
			out.append({"heading": "VERRINE'S MOOD", "permission": "hunters", "items": ["calm", "bold", "shy"], "labels": {"calm": "CALM", "bold": "BOLD (QUICKER)", "shy": "SHY (SLOWER)"},
				"action": func(id: String) -> void: game.call("admin_set", "mood", id)})
	if sim.watch > 0:
		out.append({"label": "WEATHER NOW", "permission": "world", "state": func() -> bool: return bool((game.get("sim") as NightWatchOpenAirLogic).weather.get("on", false)),
			"action": func() -> void: game.call("admin_set", "rain", not bool((game.get("sim") as NightWatchOpenAirLogic).weather.get("on", false)))})
	return out
