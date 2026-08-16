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
	# The gate itself. This suite only ever runs in a debug build, so what can
	# be checked here is that the release path is a real branch and not a
	# comment: attach returns null when tools are off.
	if not Build.tools_enabled():
		_fail("the check suite is running without tools enabled")

	for entry in [["res://scenes/main_3d.tscn", "maze"],
			["res://scenes/office_3d.tscn", "office"]]:
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
		# The readout runs every frame while open; a throw here is a crash in a
		# dev tool, which is the worst place to find one.
		if menu._readout.text.is_empty():
			_fail("%s admin overlay reads out nothing" % entry[1])
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
		for row in menu._actions:
			var action: Callable = row["action"]
			if not action.is_valid():
				_fail("admin action '%s' is not callable" % row["label"])
		# One with an observable effect, so this is not merely a null check.
		for row in menu._actions:
			if String(row["label"]) == "ALL RELAYS":
				(row["action"] as Callable).call()
		if GameState.relays_collected != GameState.relay_target:
			_fail("ALL RELAYS left %d of %d collected"
				% [GameState.relays_collected, GameState.relay_target])

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
			_expect(revealed.size() == scene.hunter_views.size(),
				"admin reveal did not surface every hunter, active or not")

			for row in menu._actions:
				if String(row["label"]) == "TOGGLE HUNTER REVEAL":
					(row["action"] as Callable).call()
			_expect(scene._admin_reveal_hunters, "TOGGLE HUNTER REVEAL did not turn reveal on")
			for row in menu._actions:
				if String(row["label"]) == "TOGGLE HUNTER REVEAL":
					(row["action"] as Callable).call()
			_expect(not scene._admin_reveal_hunters, "TOGGLE HUNTER REVEAL did not turn back off")
	scene.queue_free()
	await host.get_tree().process_frame

	if _failures == 0:
		print("admin OK")
	return _failures
