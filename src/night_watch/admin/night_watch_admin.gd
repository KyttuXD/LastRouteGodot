class_name NightWatchAdmin
extends RefCounted

## The Night Watch ADMIN MENU: the shared AdminMenu (src/ui/admin_menu.gd, the 0 key, the same gate as Last Route and the City: Build.tools_enabled() = a signed-in admin; absent and
## inert for everyone else; a used control marks the run DEBUG and the badge reads "ADMIN ACTIVE ... (NOT RECORDED)") filled from a per-mode DATA table, so lanes extend it with a provider each.
##
## COMMON controls come from hooks a game offers (an entry exists only when the game has the hook, so every control really changes game state through a public method):
##   admin_jump_to(level)           admin_set_hour(h)               admin_set_frozen(on) / admin_is_frozen()
##   admin_set_power(percent)       admin_set_infinite_power(on) / admin_infinite_power()
##   admin_set_god(on) / admin_is_god()      admin_set_no_scare(on) / admin_no_scare()      admin_set_hunter_speed(mult)
##   admin_hunter_ids() + admin_set_hunter_level(id, level)      admin_places() + admin_place_hunter(id, place)
##   admin_play_call() / admin_skip_call()   admin_set_reveal(on) / admin_is_reveal()      admin_win() / admin_lose()
##   admin_set_noclip(on) / admin_is_noclip()
## and a MODE section from `PROVIDERS[mode_id]`, a script with `static func entries(game) -> Array` (entries in the AdminMenu format, each with "permission") and optional `static func status(game) -> String`.
## A game attaches it with `NightWatchAdmin.attach(self)` and lists "admin" in its hint-line actions while `menu != null`.

const PROVIDERS := {
	"classic": "res://src/night_watch/admin/classic_admin.gd",
	"mask": "res://src/night_watch/mask/mask_admin.gd",
	"dayshift": "res://src/night_watch/dayshift/dayshift_admin.gd",
	"mixed": "res://src/night_watch/mixed/mixed_admin.gd",
	"lure": "res://src/night_watch/lure/lure_admin.gd",
	"bedroom": "res://src/night_watch/bedroom/bedroom_admin.gd",
	"story": "res://src/night_watch/story/story_admin.gd",
	"descent": "res://src/night_watch/descent/descent_admin.gd",
	"extra": "res://src/night_watch/openair/openair_admin.gd",
}
const LEVEL_ITEMS := [0, 5, 10, 15, 20]


## Returns the AdminMenu, or null when the caller is not an admin (or in a build without tools). `allowed` is only overridden by tests.
static func attach(game: Node, allowed: bool = Build.tools_enabled()) -> AdminMenu:
	if not allowed:
		return null
	return AdminMenu.attach(game, func() -> String: return status(game), entries(game))


static func status(game: Node) -> String:
	var lines := PackedStringArray()
	if game.has_method("admin_status"):
		lines.append(String(game.call("admin_status")))
	var provider := _provider(game)
	if provider != null and provider.has_method("status"):
		lines.append(String(provider.call("status", game)))
	return "\n".join(lines)


static func _provider(game: Node) -> GDScript:
	var mode_id := String(game.get("mode_id")) if game.get("mode_id") != null else ""
	var path := String(PROVIDERS.get(mode_id, ""))
	return load(path) as GDScript if not path.is_empty() and ResourceLoader.exists(path) else null


static func _has(game: Node, hook: String) -> bool:
	return game.has_method(hook)


## The full entry list in AdminMenu's format: a COMMON section from the hooks the game has, then the mode's own section.
static func entries(game: Node) -> Array:
	var out := []
	var mode_title := String(game.get("mode_id")).to_upper() if game.get("mode_id") != null else "NIGHT WATCH"
	if _has(game, "mode_data") and not (game.call("mode_data") as Dictionary).is_empty():
		mode_title = String((game.call("mode_data") as Dictionary).get("title", mode_title))
	out.append({"heading": "SHIFT // " + mode_title})
	if _has(game, "admin_jump_to") and _has(game, "level_count"):
		var items := []
		var labels := {}
		var names: Array = (game.call("mode_data") as Dictionary).get("levels", [])
		for i in int(game.call("level_count")):
			items.append(str(i + 1))
			labels[str(i + 1)] = String(names[i]) if i < names.size() else "LEVEL %d" % (i + 1)
		out.append({"heading": "JUMP TO SHIFT", "permission": "world", "items": items, "labels": labels,
			"action": func(id: String) -> void: game.call("admin_jump_to", int(id))})
	if _has(game, "admin_set_hour"):
		var hours := ["0", "1", "2", "3", "4", "5"]
		var hour_labels := {"0": "12 AM", "1": "1 AM", "2": "2 AM", "3": "3 AM", "4": "4 AM", "5": "5 AM"}
		out.append({"heading": "SET TIME", "permission": "world", "items": hours, "labels": hour_labels,
			"action": func(id: String) -> void: game.call("admin_set_hour", int(id))})
	if _has(game, "admin_set_frozen"):
		out.append({"label": "TOGGLE CLOCK FREEZE", "permission": "world", "state": func() -> bool: return bool(game.call("admin_is_frozen")),
			"action": func() -> void: game.call("admin_set_frozen", not bool(game.call("admin_is_frozen")))})
	if _has(game, "admin_set_power"):
		out.append({"heading": "SET POWER", "permission": "player", "items": ["100", "50", "10", "0"], "labels": {"100": "100%", "50": "50%", "10": "10%", "0": "0% (POWER OUT)"},
			"action": func(id: String) -> void: game.call("admin_set_power", float(id))})
	if _has(game, "admin_set_infinite_power"):
		out.append({"label": "TOGGLE INFINITE POWER", "permission": "player", "state": func() -> bool: return bool(game.call("admin_infinite_power")),
			"action": func() -> void: game.call("admin_set_infinite_power", not bool(game.call("admin_infinite_power")))})
	if _has(game, "admin_set_god"):
		out.append({"label": "TOGGLE GOD MODE", "permission": "player", "state": func() -> bool: return bool(game.call("admin_is_god")),
			"action": func() -> void: game.call("admin_set_god", not bool(game.call("admin_is_god")))})
	if _has(game, "admin_set_no_scare"):
		out.append({"label": "TOGGLE NO JUMPSCARE", "permission": "visual", "state": func() -> bool: return bool(game.call("admin_no_scare")),
			"action": func() -> void: game.call("admin_set_no_scare", not bool(game.call("admin_no_scare")))})
	if _has(game, "admin_set_noclip"):
		out.append({"label": "TOGGLE NOCLIP", "permission": "player", "state": func() -> bool: return bool(game.call("admin_is_noclip")),
			"action": func() -> void: game.call("admin_set_noclip", not bool(game.call("admin_is_noclip")))})
	if _has(game, "admin_set_reveal"):
		out.append({"label": "TOGGLE REVEAL HUNTERS ON MAP", "permission": "visual", "state": func() -> bool: return bool(game.call("admin_is_reveal")),
			"action": func() -> void: game.call("admin_set_reveal", not bool(game.call("admin_is_reveal")))})
	if _has(game, "admin_set_hunter_speed"):
		out.append({"heading": "HUNTER SPEED", "permission": "hunters", "items": ["0.5", "1", "2", "4"], "labels": {"0.5": "0.5X (SLOW)", "1": "1X", "2": "2X", "4": "4X (FAST)"},
			"action": func(id: String) -> void: game.call("admin_set_hunter_speed", float(id))})
	# hunters: AI level and where she is
	if _has(game, "admin_hunter_ids"):
		var ids: Array = game.call("admin_hunter_ids")
		var hunter_labels := {}
		for id in ids:
			hunter_labels[id] = String(NightWatchData.NAMES.get(id, String(id).capitalize()))
		var acts := []
		if _has(game, "admin_set_hunter_level"):
			for lv in LEVEL_ITEMS:
				acts.append({"label": "AI LEVEL %d" % lv, "call": func(hid: String, _extra: String) -> void: game.call("admin_set_hunter_level", hid, lv)})
		if _has(game, "admin_place_hunter") and _has(game, "admin_places"):
			for place in game.call("admin_places"):
				acts.append({"label": "SEND TO %s" % String(place).to_upper(), "call": func(hid: String, _extra: String) -> void: game.call("admin_place_hunter", hid, place)})
		if not acts.is_empty():
			out.append({"heading": "HUNTERS", "permission": "hunters", "hunter_tool": acts, "hunters": ids, "hunter_labels": hunter_labels})
	if _has(game, "admin_play_call") or _has(game, "admin_win"):
		out.append({"heading": "ZELLIA AND THE NIGHT"})
		if _has(game, "admin_play_call"):
			out.append({"label": "PLAY ZELLIA'S CALL NOW", "permission": "world", "action": func() -> void: game.call("admin_play_call")})
			out.append({"label": "SKIP THE CALL", "permission": "world", "action": func() -> void: game.call("admin_skip_call")})
		if _has(game, "admin_win"):
			out.append({"label": "WIN THE SHIFT", "permission": "world", "action": func() -> void: game.call("admin_win")})
			out.append({"label": "LOSE THE SHIFT", "permission": "world", "action": func() -> void: game.call("admin_lose")})
	# the mode's own section
	var provider := _provider(game)
	if provider != null:
		out.append({"heading": "%s SPECIFIC" % mode_title})
		out.append_array(provider.call("entries", game))
	return out
