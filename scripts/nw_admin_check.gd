class_name NwAdminCheck
extends RefCounted

## The admin menu checks every mode suite shares (NightWatchAdmin, docs/NIGHT_WATCH_ADMIN.md): the sections, every entry carries a permission, the layout fits at
## 480x270 / 1280x720 / 1920x1080, and EVERY entry (every item of a dropdown, every action of the hunter tool) runs through the game's hook and changes game state.
## A suite hands in `make_game` (a coroutine returning a fresh game with a sim and admin_menu) and `fingerprint(game)` (a string of the state the controls can change).

static func sections(game: Node) -> Array:
	var out := []
	for e in NightWatchAdmin.entries(game):
		var d: Dictionary = e
		if d.has("heading") and not d.has("items") and not d.has("hunter_tool"):
			out.append(String(d["heading"]))
	return out


## Problems with the entries themselves (empty list when fine): a permission on every control.
static func entry_problems(game: Node) -> Array:
	var out := []
	for e in NightWatchAdmin.entries(game):
		var d: Dictionary = e
		var control: bool = d.has("items") or d.has("hunter_tool") or d.has("action")
		if control and String(d.get("permission", "")).is_empty():
			out.append("an admin entry has no permission scope: %s" % str(d.get("label", d.get("heading", "?"))))
	return out


## The menu fits the screen and lists these tab titles at three sizes.
static func layout_problems(host: Node, game: Node, want_titles: Array) -> Array:
	var out := []
	var entries := NightWatchAdmin.entries(game)
	for size in [Vector2i(480, 270), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = true
		host.add_child(vp)
		var holder := Node.new()
		vp.add_child(holder)
		var menu := AdminMenu.attach(holder, func() -> String: return NightWatchAdmin.status(game), entries)
		await host.get_tree().process_frame
		menu.call("_set_open", true)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var panel := menu.get("_panel") as Control
		if not Rect2(Vector2.ZERO, Vector2(size)).encloses(panel.get_global_rect()):
			out.append("[%s] the admin panel leaves the screen: %s" % [str(size), str(panel.get_global_rect())])
		var tabs := menu.get("_tabs") as TabBar
		var titles := []
		for i in tabs.tab_count:
			titles.append(tabs.get_tab_title(i))
		for want in want_titles:
			if not titles.has(want):
				out.append("[%s] the admin tabs lack %s: %s" % [str(size), want, str(titles)])
		vp.queue_free()
		await host.get_tree().process_frame
	return out


## Runs every variant of every entry on a fresh game and reports the entries that changed nothing. `skip` lists entry headings / labels handled elsewhere (a jump reloads the scene).
static func exercise(make_game: Callable, fingerprint: Callable, skip: Array = []) -> Array:
	var out := []
	var probe: Node = await make_game.call()
	var count := (NightWatchAdmin.entries(probe) as Array).size()
	probe.queue_free()
	for i in count:
		var g0: Node = await make_game.call()
		var entry: Dictionary = (NightWatchAdmin.entries(g0) as Array)[i]
		var title := String(entry.get("label", entry.get("heading", "?")))
		g0.queue_free()
		if skip.has(title) or not (entry.has("action") or entry.has("items") or entry.has("hunter_tool")):
			continue
		var variants := []
		if entry.has("hunter_tool"):
			for a in (entry["hunter_tool"] as Array).size():
				variants.append(a)
		elif entry.has("items"):
			for id in entry["items"]:
				variants.append(id)
		else:
			variants.append(-1)
		var changed := false
		for variant in variants:
			var g: Node = await make_game.call()
			var e: Dictionary = (NightWatchAdmin.entries(g) as Array)[i]
			var before: String = fingerprint.call(g)
			if e.has("hunter_tool"):
				var hid := String((e["hunters"] as Array)[0])
				((e["hunter_tool"] as Array)[int(variant)] as Dictionary)["call"].call(hid, "")
			elif e.has("items"):
				(e["action"] as Callable).call(String(variant))
			else:
				(e["action"] as Callable).call()
			if fingerprint.call(g) != before:
				changed = true
			g.queue_free()
		if not changed:
			out.append("the admin control '%s' changed nothing" % title)
	return out
