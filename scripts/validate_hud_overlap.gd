extends RefCounted

## HUD panels never overlap each other, never touch the window edge and never carry dead space: at the smallest design
## window, a tall 4:3-ish window (the hotel screenshot), 1024x768, KT's 16:9 windows, ultrawide and phone landscape;
## in the states solo, a long BETA/TEST server tag with ADMIN ACTIVE and the public line, co-op chat with messages,
## open chat, spectating, a toast plus interaction prompt, and a map-less zone (the City). Run in the streamed route
## with the HUD up.
##
##   godot --headless --path . res://scenes/validate.tscn -- hud_overlap

const SIZES := [Vector2i(480, 270), Vector2i(926, 728), Vector2i(1024, 768), Vector2i(1280, 720), Vector2i(1440, 840),
	Vector2i(1920, 1080), Vector2i(3440, 1440), Vector2i(844, 390)]
const HUD_PANELS := ["HudStatusBar", "ObjectivePanel", "HotbarPanel", "MinimapPanel", "ZonePanel", "CompactStaminaBar",
	"MessageLabel", "InteractionLabel", "FpsLabel"]
const MIN_TEXT_PIXELS := 12.0
const SAFE := 8.0
const LONG_SERVER := "BETA  //  play.kyttulab-beta-server.example.org:8105"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _frames(host: Node, count: int = 4) -> void:
	for _i in count:
		await host.get_tree().process_frame


## Visible panels of the current state: name -> rect in HUD units.
func _collect(hud: Node, route: Node) -> Dictionary:
	var rects := {}
	for name in HUD_PANELS:
		var control := hud.get_node_or_null(name) as Control
		if control != null and control.is_visible_in_tree():
			rects[name] = control.get_global_rect()
	var banner := route.get("_spectator_banner") as Control
	if banner != null and banner.is_visible_in_tree():
		rects["SpectatorBanner"] = banner.get_global_rect()
	var chat := route.get("_room_chat") as RoomChat
	if chat != null and chat.panel_rect().size != Vector2.ZERO:
		rects["RoomChat"] = chat.panel_rect()
	return rects


func _check_state(host: Node, hud: HUD, route: Node, label: String, size: Vector2i, expected: Array = []) -> void:
	await _frames(host)
	var view := host.get_tree().root.get_visible_rect()
	var where := "%s at %s" % [label, size]
	var rects := _collect(hud, route)
	var safe := view.grow(-(SAFE - 1.0))
	for name in rects:
		var rect: Rect2 = rects[name]
		_expect(view.grow(1.0).encloses(rect), "%s: %s leaves the window: %s inside %s" % [where, name, rect, view])
		# the bottom row (hotbar, stamina) and the spectator strip may sit on the 8-unit margin line itself
		_expect(safe.grow(.5).encloses(rect) or name in ["SpectatorBanner"], "%s: %s breaks the safe margin: %s inside %s" % [where, name, rect, safe])
		_expect(rect.size.x > 0.5 and rect.size.y > 0.5, "%s: %s is visible but empty" % [where, name])
	var names := rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if (rects[names[i]] as Rect2).grow(-.01).intersects((rects[names[j]] as Rect2).grow(-.01)):
				_expect(false, "%s: %s overlaps %s: %s vs %s" % [where, names[i], names[j], rects[names[i]], rects[names[j]]])
	for name in expected:
		_expect(rects.has(name), "%s: %s should be showing" % [where, name])
	_check_text(hud, where, size, view)


## Text fits inside its panel, and is at least MIN_TEXT_PIXELS tall on screen.
func _check_text(hud: HUD, where: String, size: Vector2i, view: Rect2) -> void:
	var pixels_per_unit := float(size.x) / view.size.x
	# a 480x270 pixel window is 1 pixel per unit: the 12 px floor is for real windows
	var floor_applies := pixels_per_unit >= 1.3
	var bar := hud.status_bar
	if bar.visible:
		_expect(bar.size.x <= view.size.x - 2.0 * SAFE + .5, "%s: the status bar is wider than the window allows (%s)" % [where, bar.size.x])
		for child in bar.get_child(0).get_children():
			var label := child as Label
			if label == null or not label.visible:
				continue
			var font := label.get_theme_font("font")
			var units := label.get_theme_font_size("font_size")
			_expect(not floor_applies or float(units) * pixels_per_unit >= MIN_TEXT_PIXELS - .5, "%s: status text is %.1f px (< %d)" % [where, units * pixels_per_unit, int(MIN_TEXT_PIXELS)])
			var padding := label.get_theme_stylebox("normal").get_minimum_size().x if label.has_theme_stylebox_override("normal") else 0.0
			var needed := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, units).x + padding
			if bar.natural_width() <= bar.max_width:
				_expect(needed <= label.size.x + 1.0, "%s: '%s' is cut off (%.1f of %.1f)" % [where, label.text, needed, label.size.x])
	for pair in [[hud.depth_label, 7], [hud.relay_label, 6], [hud.danger_label, 6]]:
		var label := pair[0] as Label
		if not label.is_visible_in_tree():
			continue
		var units := label.get_theme_font_size("font_size")
		_expect(not floor_applies or float(units) * pixels_per_unit >= MIN_TEXT_PIXELS - .5, "%s: %s is %.1f px (< %d)" % [where, label.name, units * pixels_per_unit, int(MIN_TEXT_PIXELS)])
		var panel := hud.get_node("ObjectivePanel") as Control
		_expect(panel.get_global_rect().grow(.5).encloses(label.get_global_rect()), "%s: %s sticks out of the stats panel" % [where, label.name])
	# the stats panel is as small as its content: no dead space below the last row
	var objective := hud.get_node("ObjectivePanel") as Control
	_expect(objective.size.y <= objective.get_combined_minimum_size().y + 1.0, "%s: the stats panel has dead space (%s vs %s)" % [where, objective.size.y, objective.get_combined_minimum_size().y])


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await _frames(host, 10)
	var hud := route.hud as HUD
	var window := host.get_tree().root
	var original := window.size
	var chat := route.get("_room_chat") as RoomChat
	var banner := route.get("_spectator_banner") as SpectatorBanner
	hud.update_infinite_status(12, 40, 55)
	for size in SIZES:
		window.size = size
		await _frames(host)
		# 1. solo, the route as it opens
		hud.status_bar.set_segment("env", "", "env")
		hud.status_bar.set_segment("admin", "", "admin")
		hud.set_public_line("")
		await _check_state(host, hud, route, "solo", size, ["HotbarPanel", "ObjectivePanel"])
		# 2. everything the top bar can carry, with a server name too long for a phone
		hud.status_bar.set_segment("env", LONG_SERVER, "env")
		hud.status_bar.set_segment("admin", "ADMIN ACTIVE // PUBLIC ROUTE // DEBUG RUN (NOT RECORDED)", "admin")
		hud.set_public_line("PUBLIC ROUTE // 12 ONLINE // 120 RELAYS")
		await _check_state(host, hud, route, "status bar full", size, ["HudStatusBar"])
		# 3. co-op: chat with messages (collapsed panel is zero-size without them)
		if chat != null:
			_expect(chat.panel_rect().size == Vector2.ZERO, "chat shows an empty panel at %s: %s" % [size, chat.panel_rect()])
			for line in ["hello there", "the second relay is past the red door and down the stairs, bring a battery", "ok"]:
				chat._on_chat_received(1, "Kyttu", line)
			await _check_state(host, hud, route, "co-op chat", size, ["RoomChat"])
			var rect := chat.panel_rect()
			_expect(rect.size.y <= window.get_visible_rect().size.y * .25 + 8.0, "chat is taller than a quarter of the window at %s: %s" % [size, rect])
			chat.open()
			await _check_state(host, hud, route, "chat open", size, ["RoomChat"])
			chat.close()
			chat._fresh_left = 0.0
			chat._messages.clear()
			await _frames(host)
			_expect(chat.panel_rect().size == Vector2.ZERO, "chat did not collapse again at %s" % size)
		# 4. toast + prompt
		hud.show_message("RELAY ONLINE  //  FOLLOW THE COLD AIR TO THE NEXT ROOM")
		hud.set_interaction_prompt("[E] PICK UP BATTERY")
		await _check_state(host, hud, route, "toast and prompt", size, ["MessageLabel"])
		hud.set_interaction_prompt("")
		hud.show_message("")
		hud.message_label.visible = false
		# 5. spectating
		if banner != null:
			banner.show_for("Kyttu", "THE PARTY IS STILL RUNNING")
			await _check_state(host, hud, route, "spectator", size, ["SpectatorBanner"])
			banner.clear()
		# 6. no map data (City): the minimap panel goes, the zone name takes its slot
		hud.set_minimap_available(false)
		hud.set_zone_text("")
		await _check_state(host, hud, route, "no map, no zone", size)
		_expect(not (hud.get_node("MinimapPanel") as Control).visible, "an empty minimap is still drawn at %s" % size)
		_expect(not (hud.get_node("ZonePanel") as Control).visible, "an empty zone panel is drawn at %s" % size)
		hud.set_zone_text("OLD TOWN  //  NIGHT MARKET")
		await _check_state(host, hud, route, "zone name", size, ["ZonePanel"])
		hud.set_zone_text("")
		hud.set_minimap_available(true)
	window.size = original
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  hud       %d panels x 8 window sizes x 7 states: inside the safe margin, no overlaps, no empty boxes, text fits" % HUD_PANELS.size())
	return _failures
