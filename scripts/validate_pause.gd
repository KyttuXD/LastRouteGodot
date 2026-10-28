extends RefCounted

## Headless check on pausing and the mouse lock.
##
## Both are the kind of thing that breaks silently and is only noticed when a
## player is already stuck. Four specific failures are worth a test:
##
##   1. ESC leaving the run. It used to change scene on the spot, which in a
##      route after a capture is a way to lose it by reaching for the
##      wrong key.
##   2. The cursor being taken back. The camera sets its capture preference
##      every frame, so a menu that merely set Input.mouse_mode would be
##      unclickable one frame later. MouseLock arbitrates instead, and that
##      arbitration is what is checked here rather than the OS mouse mode --
##      headless has no real cursor to read.
##   3. Office Mode's hold-to-pause firing on a tap. The mode is built around
##      not being able to step away; a one-key exit would undercut it.
##   4. Losing window/application focus mid-route. The route kept simulating
##      and Gray Void still woke, because WASD never reached the game. Focus
##      loss has to call the same open() ESC uses, and focus returning must
##      not resume on its own.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- pause

## The suite runs inside scenes/validate.tscn, so the tree comes from the host
## node rather than from `self` -- see scripts/validate_runner.gd for why these
## are not `--script` SceneTree scripts any more.
var _host: Node


func _tree() -> SceneTree:
	return _host.get_tree()


func _root() -> Window:
	return _host.get_tree().root


func _frame() -> Signal:
	return _host.get_tree().process_frame


var _failures := 0
## Keep validation off the real gameplay port so this suite can run while a
## developer has an ordinary local room open in another window.
## VALIDATE_PORT_OFFSET lets parallel runs on one machine use distinct ports.
var TEST_PORT := 28422 + int(OS.get_environment("VALIDATE_PORT_OFFSET"))


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_host = host
	var was_pausing := Settings.pause_on_focus_loss
	Settings.pause_on_focus_loss = true   # the solo/online checks below run with the setting ON
	await _check_lock()
	await _check_maze()
	await _check_online_maze()
	await _check_share_copy()
	await _check_menus_ignore_unfocus()
	await _check_unfocus_afk()
	await _check_focus_rules()
	Settings.pause_on_focus_loss = was_pausing
	if _failures == 0:
		print("pause and mouse lock OK")
	return _failures


## Headless has no real OS focus change. Drive the same notifications the
## PauseMenu watches so the suite proves unfocus enters open(), not a second
## pause path.
func _simulate_lost_focus(node: Node) -> void:
	node.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	node.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)


func _simulate_regained_focus(node: Node) -> void:
	node.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	node.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)


func _broadcast_lost_focus(node: Node) -> void:
	_simulate_lost_focus(node)
	for child in node.get_children():
		_broadcast_lost_focus(child)


func _open_pause_count(root: Node) -> int:
	var count := 0
	if root is PauseMenu and (root as PauseMenu).is_open():
		count += 1
	for child in root.get_children():
		count += _open_pause_count(child)
	return count


## The arbitration itself, with no scene involved.
func _check_lock() -> void:
	MouseLock.set_gameplay_capture(false)
	for who in ["pause", "tablet", "seated"]:
		MouseLock.claim(who, false)
	_expect(MouseLock.cursor_visible(), "cursor hidden with nothing asking to capture it")

	MouseLock.set_gameplay_capture(true)
	_expect(MouseLock.is_captured(), "gameplay asked for capture and did not get it")

	MouseLock.claim("pause", true)
	_expect(MouseLock.cursor_visible(), "a menu claim did not free the cursor")
	# The camera restating its preference must not override a live claim --
	# this is the exact frame ordering that made the old menu unclickable.
	MouseLock.set_gameplay_capture(true)
	_expect(MouseLock.cursor_visible(), "gameplay took the cursor back from an open menu")

	MouseLock.claim("tablet", true)
	MouseLock.claim("pause", false)
	_expect(MouseLock.cursor_visible(), "cursor recaptured while the tablet still held it")
	MouseLock.claim("tablet", false)
	_expect(MouseLock.is_captured(), "cursor stayed free after the last claim was dropped")
	# Releasing twice must not leave a phantom holder.
	MouseLock.claim("tablet", false)
	_expect(MouseLock.is_captured(), "a double release left the cursor stuck")
	print("  lock      claims arbitrate; gameplay cannot outrank an open menu")


func _check_maze() -> void:
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	_root().add_child(scene)
	await _frame()
	await _frame()
	var menu: PauseMenu = scene.pause_menu
	if menu == null:
		_fail("main_3d has no pause menu")
		scene.queue_free()
		return

	_expect(not menu.is_open(), "maze started paused")
	menu.open()
	_expect(_tree().paused, "opening the menu did not pause the tree")
	_expect(MouseLock.cursor_visible(), "the pause menu did not free the cursor")

	var abandoned := [false]
	menu.abandoned.connect(func() -> void: abandoned[0] = true)
	menu.close()
	_expect(not _tree().paused, "closing the menu left the tree paused")
	_expect(not abandoned[0], "closing the menu counted as abandoning the run")

	# Losing OS focus must enter the same open() ESC uses. Getting it back
	# must leave SIGNAL SUSPENDED up until RETURN / ESC.
	var opened_from_focus := [0]
	var opened_watch := func() -> void: opened_from_focus[0] += 1
	menu.opened.connect(opened_watch)
	_simulate_lost_focus(menu)
	_expect(menu.is_open(), "losing application focus did not open pause")
	_expect(_tree().paused, "focus-loss pause did not use the existing open() path")
	_expect(opened_from_focus[0] == 1,
		"focus-loss did not emit the same opened signal as Esc")
	_simulate_regained_focus(menu)
	_expect(menu.is_open() and _tree().paused,
		"regaining focus closed pause without Resume/Esc")
	menu.close()
	_expect(not menu.is_open() and not _tree().paused,
		"focus-loss pause could not resume through the normal close path")
	_simulate_regained_focus(menu)
	menu.get_window().focus_exited.emit()
	_expect(menu.is_open(), "window focus_exited did not open pause")
	menu.close()
	menu.opened.disconnect(opened_watch)

	# Being held by a hunter is the one moment pausing would be an exploit.
	GameState.escape_active = true
	scene._process(0.016)
	_expect(not menu.tap_to_pause, "ESC still pauses mid-escape")
	_simulate_lost_focus(menu)
	_expect(not menu.is_open(), "losing focus paused during an escape struggle")
	GameState.escape_active = false
	scene._process(0.016)
	_expect(menu.tap_to_pause, "ESC stayed locked out after the escape ended")

	# ESC dismisses the top gameplay overlay and is consumed there. It must not
	# replace the map/inventory/admin screen with the pause screen in one press.
	var escape := InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	scene.hud.map_overlay.visible = true
	menu._unhandled_input(escape)
	_expect(not scene.hud.map_is_open() and not menu.is_open(),
		"ESC closed the full map but opened pause underneath it")
	scene.hud.set_inventory_open(true)
	menu._unhandled_input(escape)
	_expect(not scene.hud.inventory_is_open() and not menu.is_open(),
		"ESC closed inventory but opened pause underneath it")
	if scene.admin_menu != null:
		scene.admin_menu._set_open(true)
		menu._unhandled_input(escape)
		_expect(not scene.admin_menu.is_open() and not menu.is_open(),
			"ESC did not close the admin menu before pause")

	_tree().paused = false
	scene.queue_free()
	await _frame()
	print("  maze      taps to pause, locked out mid-escape, unfocus uses the same open()")


func _check_online_maze() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var error := RoomState.host_room(TEST_PORT)
	if not error.is_empty():
		_fail("could not open an online room for the pause check: %s" % error)
		return
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	_root().add_child(scene)
	await _frame()
	await _frame()
	var menu: PauseMenu = scene.pause_menu
	_expect(not menu.pauses_tree, "a co-op pause menu still owns the whole SceneTree")
	menu.open()
	_expect(not _tree().paused, "the host froze every peer by opening a local menu")
	_expect(scene.player.input_frozen, "the paused local runner can still move online")
	menu.close()
	_expect(not scene.player.input_frozen, "resuming left the online runner frozen")
	_simulate_lost_focus(menu)
	_expect(not menu.is_open(), "losing focus in a room opened the pause menu")
	_expect(not _tree().paused, "losing focus in a room froze the host simulation")
	_expect(not scene.player.input_frozen, "losing focus in a room froze the local runner")
	scene.queue_free()
	await _frame()
	RoomState.leave_network()
	print("  co-op     pause freezes one runner without freezing the host simulation")


func _check_share_copy() -> void:
	var old_code := RoomState.code
	var old_seed := RoomState.seed_text
	var old_online := RoomState.online
	var old_host := RoomState.is_host
	var old_peers := RoomState.peers.duplicate(true)
	RoomState.code = "ABCDE"
	RoomState.seed_text = "ROOM-ABCDE-VALIDATIONSEED01"
	RoomState.online = true
	RoomState.is_host = true
	RoomState.peers = {1: "HOST"}
	_expect(PauseMenu.route_share_text("ABCDE", "ROOM-ABCDE-VALIDATIONSEED01")
			== "ROOM ABCDE // SEED ROOM-ABCDE-VALIDATIONSEED01",
		"share text did not combine the live room code and route seed")
	_expect(PauseMenu.route_share_text("", "SOLO-SEED") == "SOLO-SEED",
		"a seed-only route did not copy the seed")
	_expect(PauseMenu.route_share_text("FGHIJ", "") == "ROOM FGHIJ",
		"a code-only room did not copy the room code")
	_expect(PauseMenu.route_share_text("  ", "") == "",
		"an empty room still produced a share string")

	var menu := PauseMenu.new()
	_root().add_child(menu)
	await _frame()
	menu.open()
	menu.call("_set_section", "statistics")
	var share := menu.find_child("PauseShare", true, false)
	var copy_button := menu.find_child("PauseCopyRoute", true, false) as Button
	var code_label := menu.find_child("PauseShareCode", true, false) as Label
	var seed_label := menu.find_child("PauseShareSeed", true, false) as Label
	var status := menu.find_child("PauseCopyStatus", true, false) as Label
	_expect(share != null and copy_button != null and status != null,
		"pause statistics is missing the route-share copy block")
	if code_label != null:
		_expect(code_label.text == "ROOM ABCDE",
			"pause share block did not show the live room code")
	if seed_label != null:
		_expect(seed_label.text == "ROOM-ABCDE-VALIDATIONSEED01",
			"pause share block did not show the live route seed")
	if copy_button != null:
		_expect(not copy_button.disabled, "copy route was disabled for the host")
		copy_button.pressed.emit()
	var copied := menu.copy_route_share()
	_expect(copied == "ROOM ABCDE // SEED ROOM-ABCDE-VALIDATIONSEED01",
		"copying the live route did not return the share string")
	if status != null:
		_expect(status.text == "COPIED TO CLIPBOARD",
			"pause UI did not confirm the clipboard copy")
	var clipboard := DisplayServer.clipboard_get()
	if not clipboard.is_empty():
		_expect(clipboard == copied,
			"OS clipboard did not receive the live route share string")

	RoomState.is_host = false
	RoomState.peers = {1: "HOST", 2: "GUEST"}
	menu.call("_set_section", "statistics")
	_expect(menu.copy_route_share() == copied,
		"a guest lost the read-only route-share copy")
	_expect(menu.save_new_request.is_valid() == false
			and menu.save_load_request.is_valid() == false,
		"the share-copy path wired guest save/load authority")
	var save_new := menu.find_child("SaveNew", true, false)
	_expect(save_new != null,
		"pause archives vanished after a guest opened the share block")
	menu.close()
	menu.queue_free()
	await _frame()
	RoomState.code = old_code
	RoomState.seed_text = old_seed
	RoomState.online = old_online
	RoomState.is_host = old_host
	RoomState.peers = old_peers
	print("  share     pause copies room code and seed; guests stay read-only")


func _check_menus_ignore_unfocus() -> void:
	_tree().paused = false
	var title: Node = load("res://scenes/main_menu.tscn").instantiate()
	_root().add_child(title)
	await _frame()
	_broadcast_lost_focus(title)
	_expect(not _tree().paused, "title paused the tree on lost focus")
	_expect(_open_pause_count(title) == 0, "title opened SIGNAL SUSPENDED on lost focus")
	title.queue_free()
	await _frame()

	RoomState.create_local(RoomState.Mode.DEFAULT)
	var staging: Node = load("res://scenes/room_lobby.tscn").instantiate()
	_root().add_child(staging)
	await _frame()
	_broadcast_lost_focus(staging)
	_expect(not _tree().paused, "staging paused the tree on lost focus")
	_expect(_open_pause_count(staging) == 0,
		"co-op staging opened SIGNAL SUSPENDED on lost focus")
	staging.queue_free()
	await _frame()
	print("  menus     title and staging stay off pause when the window blurs")


func _check_unfocus_afk() -> void:
	var route_script := load("res://src/infinite_route_test.gd") as GDScript
	if route_script == null or not route_script.can_instantiate():
		_fail("Infinite route script did not compile")
		return
	var route: Node = route_script.new()
	var menu := PauseMenu.new()
	# Online rooms do not pause the SceneTree. The AFK guard has to stand
	# on is_open() itself, so this fixture matches that contract.
	menu.pauses_tree = false
	_root().add_child(menu)
	await _frame()
	route.pause_menu = menu
	route.set("_party_afk_seconds", 4.0)
	route.set("_relay_inactivity_seconds", 4.0)
	_simulate_lost_focus(menu)
	_expect(menu.is_open(), "Infinite AFK fixture did not pause on lost focus")
	route.call("_update_anti_idle_pressure", 8.0)
	_expect(is_equal_approx(float(route.get("_party_afk_seconds")), 4.0),
		"AFK clock advanced while SIGNAL SUSPENDED was up")
	_expect(is_equal_approx(float(route.get("_relay_inactivity_seconds")), 4.0),
		"relay-inactivity clock advanced while SIGNAL SUSPENDED was up")
	_expect(is_equal_approx(float(route.call("_afk_void_warning_remaining")), 0.0),
		"AFK warning armed from a short idle while paused")
	menu.close()
	_expect(not menu.is_open(), "AFK fixture could not resume after a focus-loss pause")

	var delay := GameConfig.anti_afk_hunter_seconds(RoomState.difficulty_id())
	var warning := GameConfig.anti_afk_warning_seconds()
	_expect(warning > 0.0 and warning < delay \
			and warning < GameConfig.anti_afk_hunter_seconds("nightmare"),
		"AFK warning is not a short slice of the existing AFK window")
	route.set("_party_afk_seconds", delay - warning - 1.0)
	_expect(is_equal_approx(float(route.call("_afk_void_warning_remaining")), 0.0),
		"AFK warning started before the existing telegraph window")
	route.set("_party_afk_seconds", delay - warning + 1.0)
	var remaining := float(route.call("_afk_void_warning_remaining"))
	_expect(remaining > 0.0 and remaining <= warning,
		"AFK warning did not arm inside the existing kill window")
	_simulate_lost_focus(menu)
	var frozen_warning := float(route.get("_party_afk_seconds"))
	route.call("_update_anti_idle_pressure", warning)
	_expect(is_equal_approx(float(route.get("_party_afk_seconds")), frozen_warning),
		"AFK warning clock advanced while SIGNAL SUSPENDED was up")
	_expect(float(route.call("_afk_void_warning_remaining")) > 0.0,
		"paused AFK warning cleared itself without movement")
	menu.close()

	var still := {"peer_id": 1, "position": Vector2(4, 4),
		"facing": Vector2(0, 1), "game_over": false}
	route.set("_party_activity_anchors", {})
	_expect(bool(route.call("_party_moved_since_pressure_sample", [still])),
		"first AFK sample did not register the standing runner")
	route.set("_party_afk_seconds", delay - 2.0)
	_expect(not bool(route.call("_party_moved_since_pressure_sample", [still])),
		"standing still cancelled the AFK warning clock")
	var looking := still.duplicate()
	looking["facing"] = Vector2(1, 0)
	_expect(bool(route.call("_party_moved_since_pressure_sample", [looking])),
		"looking around did not cancel the AFK warning the way idle already does")
	var walking := still.duplicate()
	walking["position"] = Vector2(5, 4)
	walking["facing"] = Vector2(1, 0)
	_expect(bool(route.call("_party_moved_since_pressure_sample", [walking])),
		"moving did not cancel the AFK warning the way idle already does")

	route.free()
	menu.queue_free()
	await _frame()
	print("  unfocus   lost focus opens pause; AFK/void stays frozen until Resume")


## Focus loss rules: the setting, rooms, text focus, admin overlays, and held keys.
func _check_focus_rules() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	_root().add_child(scene)
	await _frame()
	await _frame()
	var menu: PauseMenu = scene.pause_menu
	var was := Settings.pause_on_focus_loss
	# solo, setting ON: pauses
	Settings.pause_on_focus_loss = true
	_simulate_lost_focus(menu)
	_expect(menu.is_open(), "solo with the setting on did not pause on focus loss")
	menu.close()
	_simulate_regained_focus(menu)
	# solo, setting OFF: no pause, held movement released
	Settings.pause_on_focus_loss = false
	Input.action_press("move_up")
	_simulate_lost_focus(menu)
	_expect(not menu.is_open(), "solo with the setting off paused on focus loss")
	_expect(not Input.is_action_pressed("move_up"), "a held movement key stayed pressed after focus loss")
	_simulate_regained_focus(menu)
	# setting ON but a text field has the keyboard: no pause
	Settings.pause_on_focus_loss = true
	var field := LineEdit.new()
	scene.add_child(field)
	field.grab_focus()
	await _frame()
	_simulate_lost_focus(menu)
	_expect(not menu.is_open(), "focus loss paused while a text field had the keyboard")
	field.queue_free()
	await _frame()
	_simulate_regained_focus(menu)
	# an admin overlay is open: no pause
	AdminMenu.overlay_open = true
	_simulate_lost_focus(menu)
	_expect(not menu.is_open(), "focus loss paused over an open admin overlay")
	AdminMenu.overlay_open = false
	_simulate_regained_focus(menu)
	# other players present (even with the setting on): no pause
	var old_online := RoomState.online
	var old_peers := RoomState.peers.duplicate(true)
	RoomState.online = true
	RoomState.peers = {1: "HOST", 2: "GUEST"}
	_simulate_lost_focus(menu)
	_expect(not menu.is_open(), "focus loss paused with other players connected")
	RoomState.online = old_online
	RoomState.peers = old_peers
	_simulate_regained_focus(menu)
	var old_public := RoomState.public_route
	RoomState.public_route = true
	_simulate_lost_focus(menu)
	_expect(not menu.is_open(), "focus loss paused on a public route")
	RoomState.public_route = old_public
	# the default: off outside release builds
	_expect(Settings.default_pause_on_focus_loss() == not (OS.is_debug_build() or Build.is_beta() or OS.has_feature("test_server")),
		"the focus-loss default does not follow the build type")
	Settings.pause_on_focus_loss = was
	scene.queue_free()
	await _frame()
	print("  focus     setting on/off, rooms, text focus, admin overlay: only solo + setting pauses; held keys released")
