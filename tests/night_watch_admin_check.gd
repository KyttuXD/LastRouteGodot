class_name NightWatchAdminCheck
extends RefCounted

## Shared checks for a mode's admin section (used by validate_night_watch_mask / _dayshift / _mixed): the gate, the sections, the layout of the tabs at three sizes, and that EVERY entry the
## mode's menu has is exercised through its action and changes the game's state (`snapshot` returns a string of everything an admin entry can touch). Each function returns the list of failures.

## The gate and the sections: null for a non-admin, a menu for an admin, a "SHIFT" section and the mode's own "<TITLE> SPECIFIC", a permission on every control.
static func sections(game: Node, specific_title: String) -> Array:
	var bad := []
	if NightWatchAdmin.attach(game, false) != null:
		bad.append("a non-admin got the admin menu")
	if game.get("admin_menu") == null or not (game.get("admin_menu") is AdminMenu):
		bad.append("an admin did not get the menu (headless validation counts as admin)")
		return bad
	var headings := []
	var entries := NightWatchAdmin.entries(game)
	for e in entries:
		if e.has("heading") and not e.has("items") and not e.has("hunter_tool") and not e.has("action"):
			headings.append(String(e["heading"]).split(" // ")[0])
		elif e.has("action") or e.has("hunter_tool"):
			if String(e.get("permission", "")) == "":
				bad.append("an admin entry has no permission scope: %s" % str(e.get("label", e.get("heading", "?"))))
	for want in ["SHIFT", specific_title]:
		if not headings.has(want):
			bad.append("the admin menu has no %s section: %s" % [want, str(headings)])
	return bad


## The menu opens and its panel and tabs fit at 480x270, 1280x720 and 1920x1080.
static func layout(host: Node, game: Node, specific_title: String) -> Array:
	var bad := []
	var entries := NightWatchAdmin.entries(game)
	(game.get("admin_menu") as AdminMenu).call("_set_open", true)
	if not (game.get("admin_menu") as AdminMenu).is_open():
		bad.append("the admin menu did not open")
	(game.get("admin_menu") as AdminMenu).close()
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
			bad.append("[%s] the admin panel leaves the screen: %s" % [str(size), str(panel.get_global_rect())])
		var tabs := menu.get("_tabs") as TabBar
		var titles := []
		for i in tabs.tab_count:
			titles.append(tabs.get_tab_title(i))
		if not (titles.has("SHIFT") and titles.has(specific_title)):
			bad.append("[%s] the admin tabs lack a section: %s" % [str(size), str(titles)])
		vp.queue_free()
		await host.get_tree().process_frame
	return bad


## Every entry of the live menu (except `skip` headings / labels) is used and changes `snapshot.call(game)`.
static func exercise(game: Node, snapshot: Callable, skip: Array = []) -> Array:
	var bad := []
	var used := 0
	for e in NightWatchAdmin.entries(game):
		var name := String(e.get("label", e.get("heading", "")))
		if skip.has(name):
			continue
		if e.has("items") and e.has("action"):
			var changed := false
			for item in e["items"]:
				var before := String(snapshot.call(game))
				(e["action"] as Callable).call(String(item))
				used += 1
				changed = changed or before != String(snapshot.call(game))
			if not changed:
				bad.append("no value of '%s' changed anything" % name)
		elif e.has("hunter_tool"):
			var ids: Array = e.get("hunters", [])
			var changed2 := false
			for act in e["hunter_tool"]:
				for hid in ids:
					var before2 := String(snapshot.call(game))
					((act as Dictionary)["call"] as Callable).call(String(hid), "")
					used += 1
					if before2 != String(snapshot.call(game)):
						changed2 = true
						break
			if not changed2:
				bad.append("the hunter tool '%s' changed nothing" % name)
		elif e.has("action"):
			var before3 := String(snapshot.call(game))
			(e["action"] as Callable).call()
			used += 1
			if before3 == String(snapshot.call(game)):
				bad.append("'%s' changed nothing" % name)
	if used < 5:
		bad.append("only %d admin controls were exercised" % used)
	return bad


## A stable string of any state value (dictionaries sorted by insertion, the seeded pacers as their two numbers), for the snapshots.
static func dump(value) -> String:
	if value is Dictionary:
		var parts := []
		for k in value:
			parts.append("%s:%s" % [str(k), dump(value[k])])
		return "{" + ",".join(PackedStringArray(parts)) + "}"
	if value is Array:
		var parts2 := []
		for v in value:
			parts2.append(dump(v))
		return "[" + ",".join(PackedStringArray(parts2)) + "]"
	if value is Object:
		if value.get("t") != null and value.get("next_ms") != null:
			return "pacer(%s,%s)" % [str(value.get("t")), str(value.get("next_ms"))]
		return "obj"
	return str(value)
