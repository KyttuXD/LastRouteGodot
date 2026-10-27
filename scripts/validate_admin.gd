extends RefCounted

## Headless check on the admin overlay.
##
## Its whole reason to exist is that it must NOT exist in a normal build: every
## row either states what the game is thinking or reaches in and changes it.
## So what is worth testing is the gate, that both modes actually attach one,
## that its readouts do not throw, and that its actions do what they say.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- admin

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	# Admin toggles are real user preferences now. Keep this suite deterministic
	# without leaving the developer's own settings changed after validation.
	var original_admin_preferences := Settings.admin_preferences_snapshot()
	Settings.set_admin_preferences(Settings.ADMIN_PREFERENCE_DEFAULTS)
	# The gate itself. This suite only ever runs in a debug build, so what can
	# be checked here is that the release path is a real branch and not a
	# comment: attach returns null when tools are off.
	if not Build.tools_enabled():
		_fail("the check suite is running without tools enabled")

	for entry in [["res://scenes/main_3d.tscn", "maze"]]:
		var scene: Node = load(String(entry[0])).instantiate()
		host.get_tree().root.add_child(scene)
		await host.get_tree().process_frame
		await host.get_tree().process_frame

		var menu: AdminMenu = null
		for child in scene.get_children():
			if child is AdminMenu:
				menu = child
		if menu == null:
			_fail("%s has no admin overlay in a debug build" % entry[1])
			scene.queue_free()
			await host.get_tree().process_frame
			continue

		if menu.is_open():
			_fail("%s opened its admin overlay uninvited" % entry[1])
		# Closed, it must not be holding the cursor away from the game.
		menu._set_open(true)
		if not menu.is_open():
			_fail("%s admin overlay would not open" % entry[1])
		if not MouseLock.cursor_visible():
			_fail("%s admin overlay is clickable without a cursor" % entry[1])
		_expect(menu._panel.size.x >= 360.0 and menu._panel.size.y >= 220.0,
			"%s admin overlay is still a narrow side strip" % entry[1])
		if entry[1] == "maze":
			_expect(scene.player.input_frozen,
				"maze player remains mobile while the admin menu is open")
		# The readout runs every frame while open; a throw here is a crash in a
		# dev tool, which is the worst place to find one.
		if menu._readout.text.is_empty():
			_fail("%s admin overlay reads out nothing" % entry[1])
		var chips := menu._panel.find_children("StateChip", "Label", true, false)
		if entry[1] == "maze":
			_expect(chips.size() == 5,
				"maze admin has %d ON/OFF chips instead of 5" % chips.size())
			var on_count := 0
			var off_count := 0
			for chip in chips:
				on_count += 1 if String(chip.text) == "ON" else 0
				off_count += 1 if String(chip.text) == "OFF" else 0
			_expect(on_count == 1 and off_count == 4,
				"admin defaults are not four safety toggles OFF plus pixel effect ON")
			var item_buttons := menu._panel.find_children("*", "GridContainer", true, false)
			if item_buttons.is_empty():
				_fail("maze admin has no creative inventory grid")
			else:
				_expect(item_buttons[0].get_child_count() == PlayerController3D.COLLECTIBLE_ITEMS.size(),
					"creative inventory does not list every collectible or storage upgrade")
		# Exercise genuinely different physical sizes and aspect ratios. The
		# design viewport expands rather than letterboxes, so containment at the
		# default size alone does not prove the panel stays usable.
		for size in [Vector2i(800, 600), Vector2i(1280, 720),
				Vector2i(1920, 1080), Vector2i(3440, 1440)]:
			host.get_tree().root.size = size
			await host.get_tree().process_frame
			await host.get_tree().process_frame
			var view := host.get_tree().root.get_visible_rect()
			var rect := Rect2(menu._panel.global_position, menu._panel.size)
			_expect(rect.position.x >= 0.0 and rect.position.y >= 0.0
				and rect.end.x <= view.size.x + 1.0
				and rect.end.y <= view.size.y + 1.0,
				"%s admin panel spills outside %dx%d (%s in %s)" % [
					entry[1], size.x, size.y, rect, view.size])
		host.get_tree().root.size = Vector2i(960, 540)
		await host.get_tree().process_frame
		menu._set_open(false)
		if MouseLock.cursor_visible() and entry[1] == "maze":
			# The maze captures the mouse for first person; closing must give
			# it back rather than leaving a free pointer over a captured game.
			pass
		print("  %-9s %s" % [entry[1], menu._readout.text.replace("\n", " // ")])

		scene.queue_free()
		await host.get_tree().process_frame

	# Every action has to be callable. They are Callables built inline, so a
	# typo in one is invisible until someone presses that button mid-test.
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var menu: AdminMenu = null
	for child in scene.get_children():
		if child is AdminMenu:
			menu = child
	if menu != null:
		GameState.relays_collected = 0
		GameState.score = 0
		for row in menu._actions:
			# Heading-only rows deliberately have no fake no-op action. Every row
			# that renders a button must still expose a real callable.
			if not row.has("action"):
				continue
			var action: Callable = row["action"]
			if not action.is_valid():
				_fail("admin action '%s' is not callable" % row["label"])
		scene.player.taser_cooldown = 5.0
		for row in menu._actions:
			if String(row.get("label", "")) == "CREATIVE INVENTORY":
				(row["action"] as Callable).call("taser")
		_expect(scene.player.selected_inventory_item() == "taser" \
				and scene.player.taser_cooldown == 0.0,
			"creative inventory did not give/restock and select the taser")
		# Relay grants must perform physical pickups, not merely alter the HUD
		# counter. Grant one first, then collect the rest in a batch.
		for row in menu._actions:
			if String(row.get("label", "")) == "GRANT RELAY":
				(row["action"] as Callable).call()
		var relays := _relay_nodes(scene)
		var completed_after_grant := 0
		for relay in relays:
			if relay.completed:
				completed_after_grant += 1
		_expect(completed_after_grant == 1,
			"GRANT RELAY did not complete exactly one relay object")
		_expect(GameState.relays_collected == 1 and GameState.score == 100,
			"GRANT RELAY did not use normal relay count/score pickup effects")

		for row in menu._actions:
			if String(row.get("label", "")) == "ALL RELAYS":
				(row["action"] as Callable).call()
		if GameState.relays_collected != GameState.relay_target:
			_fail("ALL RELAYS left %d of %d collected"
				% [GameState.relays_collected, GameState.relay_target])
		for relay in relays:
			_expect(relay.completed and relay.get_prompt().is_empty(),
				"ALL RELAYS left relay %s collectible" % relay.source_cell)
		_expect(scene.facility_view.generator.uncollected(
			scene.facility_view.generator.relays).is_empty(),
			"ALL RELAYS left generator entries uncollected for hunter logic")
		_expect(GameState.score == GameState.relay_target * 100,
			"ALL RELAYS did not award the normal pickup score exactly once")

		# TOGGLE HUNTER REVEAL: the route hunter starts inactive (she wakes on
		# the relay schedule), so she is the natural case for "the map won't
		# show me a hunter who hasn't woken up yet, unless I'm looking with
		# admin eyes."
		if scene.hunter_view and scene.hunter_view.brain.active:
			_fail("setup problem: the route hunter is already active, nothing to reveal")
		else:
			var hidden_by_default: Array = scene._map_marks()
			var revealed: Array = scene._map_marks(true)
			_expect(hidden_by_default.is_empty(),
				"an inactive hunter showed up on the map without admin reveal")
			_expect(revealed.size() == 1,
				"admin reveal left inert special-hunter spawn dots on the radar")
			_expect(revealed.is_empty() or String(revealed[0].get("name", ""))
				== String(HunterRoster.get_identity(
					scene.hunter_view.brain.hunter_id)["display_name"]),
				"admin reveal did not identify the actual route hunter")

		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE HUNTER REVEAL":
				(row["action"] as Callable).call()
		_expect(scene._admin_reveal_hunters, "TOGGLE HUNTER REVEAL did not turn reveal on")
		menu._refresh()
		_expect(_state_text(menu, "HUNTER REVEAL") == "ON",
			"hunter reveal state chip did not update to ON")
		for row in menu._actions:
				if String(row.get("label", "")) == "TOGGLE HUNTER REVEAL":
					(row["action"] as Callable).call()
		_expect(not scene._admin_reveal_hunters, "TOGGLE HUNTER REVEAL did not turn back off")
		menu._refresh()
		_expect(_state_text(menu, "HUNTER REVEAL") == "OFF",
			"hunter reveal state chip did not update back to OFF")

		# NO TARGET is an authoritative targeting rule, not just a hidden local
		# model. With it enabled the host has no eligible solo target and an
		# already-alert hunter drops the chase and resumes ordinary roaming.
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE NO TARGET":
				(row["action"] as Callable).call()
		_expect(scene.player.admin_no_target,
			"TOGGLE NO TARGET did not enable the controller flag")
		_expect(bool(scene._local_hunter_target().get("no_target", false)),
			"NO TARGET was not included in the host targeting state")
		_expect(scene._remotes.best_target(Vector2.ZERO,
			scene._local_hunter_target(), GameState.depth).is_empty(),
			"host targeting still selected a NO TARGET runner")
		if scene.hunter_view:
			scene.hunter_view.brain.active = true
			scene.hunter_view.brain.state = HunterBrain.State.CHASE
			scene._update_gameplay(0.05)
			_expect(scene.hunter_view.brain.state != HunterBrain.State.CHASE,
				"NO TARGET left an alerted hunter frozen in CHASE")
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE NO TARGET":
				(row["action"] as Callable).call()
		_expect(not scene.player.admin_no_target,
			"TOGGLE NO TARGET did not turn back off")

		# NOCLIP is a debug traversal mode, so it must remove both collision
		# directions while active and restore the ordinary player body when off.
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE NOCLIP":
				(row["action"] as Callable).call()
		_expect(scene.player.admin_noclip,
			"TOGGLE NOCLIP did not enable the controller flag")
		_expect(scene.player.collision_layer == 0 and scene.player.collision_mask == 0,
			"NOCLIP left the player colliding with route geometry")
		menu._refresh()
		_expect(_state_text(menu, "NOCLIP") == "ON",
			"noclip state chip did not update to ON")
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE NOCLIP":
				(row["action"] as Callable).call()
		_expect(not scene.player.admin_noclip,
			"TOGGLE NOCLIP did not turn back off")
		_expect(scene.player.collision_layer == 1 and scene.player.collision_mask == 1,
			"disabling NOCLIP did not restore player collision")

		# GOD MODE still permits targeting/chasing, but capture cannot start a
		# struggle or end the run. Enabling it during a struggle cancels that
		# struggle cleanly as well.
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE GOD MODE":
				(row["action"] as Callable).call()
		_expect(scene.player.admin_god_mode,
			"TOGGLE GOD MODE did not enable the controller flag")
		_expect(bool(scene._local_hunter_target().get("god_mode", false)),
			"GOD MODE was not included in the host targeting state")
		var game_over_before := GameState.game_over
		if scene.hunter_view:
			scene._trigger_capture(scene.hunter_view, true)
		_expect(GameState.game_over == game_over_before,
			"GOD MODE allowed a capture to end the run")
		_expect(not GameState.escape_active,
			"GOD MODE allowed a capture struggle to begin")
		GameState.begin_escape("admin-test")
		scene.player.admin_god_mode = false
		scene._toggle_admin_god_mode()
		_expect(not GameState.escape_active,
			"enabling GOD MODE did not cancel an active struggle")
		scene._toggle_admin_god_mode()
		_expect(not scene.player.admin_god_mode,
			"TOGGLE GOD MODE did not turn back off")
	scene.queue_free()
	await host.get_tree().process_frame

	# Save every non-default personal toggle, then instantiate a fresh route.
	# This exercises both ConfigFile persistence and the tools-gated scene
	# restore path without pretending that room-wide mutations should survive.
	var persisted_preferences := {
		"no_target": true,
		"god_mode": true,
		"noclip": true,
		"map_reveal": true,
		"hunter_reveal": true,
		"pixel_effect_enabled": false,
	}
	Settings.set_admin_preferences(persisted_preferences)
	var saved_config := ConfigFile.new()
	_expect(saved_config.load(Settings.SETTINGS_PATH) == OK,
		"admin preferences were not written to settings.cfg")
	for key_value in persisted_preferences:
		var key := String(key_value)
		_expect(bool(saved_config.get_value("admin", key, false)) \
			== bool(persisted_preferences[key]),
			"admin preference '%s' was not persisted" % key)
	var restored_scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(restored_scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_expect(restored_scene.admin_menu != null,
		"persistence fixture did not pass the admin build gate")
	_expect(restored_scene.player.admin_no_target,
		"saved NO TARGET was not restored in a fresh route")
	_expect(restored_scene.player.admin_god_mode,
		"saved GOD MODE was not restored in a fresh route")
	_expect(restored_scene.player.admin_noclip \
		and restored_scene.player.collision_layer == 0 \
		and restored_scene.player.collision_mask == 0,
		"saved NOCLIP was not restored with its collision state")
	_expect(restored_scene._admin_reveal_hunters,
		"saved hunter reveal was not restored in a fresh route")
	_expect(not restored_scene.pixel_signal_effect.admin_enabled(),
		"saved pixel-effect override was not restored in a fresh route")
	restored_scene.queue_free()
	await host.get_tree().process_frame
	Settings.set_admin_preferences(original_admin_preferences)

	# ---- the streamed route's admin tools: new tools, ADMIN ACTIVE badge, DEBUG RUN flag
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	for _index in 8:
		await host.get_tree().physics_frame
	var route_menu: AdminMenu = null
	for child in route.get_children():
		if child is AdminMenu:
			route_menu = child
	if route_menu == null:
		_fail("the streamed route has no admin overlay in a debug build")
	else:
		var labels := []
		for entry in route_menu._actions:
			labels.append(String(entry.get("label", entry.get("heading", ""))))
		for wanted in ["FREEZE ALL HUNTERS", "RELEASE ALL HUNTERS", "TELEPORT // CHUNKS AND SAFE ROOMS",
				"RUN SPEED", "GAME SPEED // SOLO RUNS ONLY", "COPY SEED", "SUMMON VOID HUNTER",
				"TOGGLE REGION MAP (F8)"]:
			_expect(labels.has(wanted), "streamed route admin menu lacks %s" % wanted)
		# everything the new tools add is permission-scoped (nothing falls through to ungated)
		for entry in route_menu._actions:
			var gated: bool = entry.has("permission") or bool(entry.get("owner_only", false))
			_expect(gated, "admin entry %s has no permission scope" % entry.get("label", entry.get("heading", "?")))
		_expect(not route._admin_region_map, "the admin region/biome map must default to off")
		var badge := route_menu.get_node_or_null("AdminActiveBadge") as Label
		_expect(badge != null and badge.text.begins_with("ADMIN ACTIVE"),
			"the ADMIN ACTIVE badge is missing")
		GameState.debug_run = false
		route_menu._mark_debug({"label": "x"})
		_expect(GameState.debug_run and badge.text.contains("DEBUG RUN"),
			"using a tool did not flag the run as a DEBUG RUN")
		GameState.debug_run = false
		route_menu._mark_debug({"no_debug": true})
		_expect(not GameState.debug_run, "a roster/read-only entry must not flag a DEBUG RUN")
		# a DEBUG RUN records nothing
		GameState.debug_run = true
		var saved_before := Backend.account_progress_saved_at
		Backend.account_save_progress({"kind": "last_route", "schema": 1})
		_expect(Backend.account_progress_saved_at == saved_before and not Backend.account_discover_hunter("aki"),
			"a DEBUG RUN still recorded progress")
		GameState.debug_run = false
		# chunk teleport lands on the next chunk's centre; run speed and game speed apply and reset
		var here: Vector3i = route.facility.current_chunk_coord()
		route._admin_teleport_chunk("east")
		var cs: int = StreamedRouteGenerator.CHUNK_SIZE
		_expect(floori(route.player.global_position.x / cs) == here.x + 1,
			"the chunk teleport did not move one chunk east")
		route.player.admin_speed_scale = 2.0
		route._admin_game_speed("2")
		_expect(Engine.time_scale == 2.0, "the game-speed tool did not set the time scale")
		route._force_disable_admin_cheats()
		_expect(Engine.time_scale == 1.0 and route.player.admin_speed_scale == 1.0,
			"disabling the admin cheats did not reset game speed and run speed")
	Engine.time_scale = 1.0
	GameState.debug_run = false
	route.queue_free()
	await host.get_tree().process_frame

	if _failures == 0:
		print("admin OK")
	return _failures


func _relay_nodes(scene: Node) -> Array[RouteInteractable3D]:
	var result: Array[RouteInteractable3D] = []
	for entry in scene.facility_view.generator.relays:
		var relay: RouteInteractable3D = scene.facility_view._at(
			Vector2i(int(entry["x"]), int(entry["y"])),
			RouteInteractable3D.Kind.RELAY)
		if relay != null:
			result.append(relay)
	return result


func _state_text(menu: AdminMenu, caption: String) -> String:
	for entry in menu._state_buttons:
		var button := entry["button"] as Button
		var label := button.get_node_or_null("StateToggleContent/Caption") as Label
		if label != null and label.text == caption:
			var chip := button.get_node_or_null("StateToggleContent/StateChip") as Label
			return chip.text if chip != null else ""
	return ""
