extends RefCounted

## Headless check on pausing and the mouse lock.
##
## Both are the kind of thing that breaks silently and is only noticed when a
## player is already stuck. Three specific failures are worth a test:
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
const TEST_PORT := 28422


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_host = host
	await _check_lock()
	await _check_maze()
	await _check_online_maze()
	await _check_share_copy()
	await _check_office()
	if _failures == 0:
		print("pause and mouse lock OK")
	return _failures


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

	# Being held by a hunter is the one moment pausing would be an exploit.
	GameState.escape_active = true
	scene._process(0.016)
	_expect(not menu.tap_to_pause, "ESC still pauses mid-escape")
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
	print("  maze      taps to pause, locked out mid-escape, ESC never exits on its own")


func _check_office() -> void:
	var scene: Node = load("res://scenes/office_3d.tscn").instantiate()
	_root().add_child(scene)
	await _frame()
	await _frame()
	var menu: PauseMenu = scene.pause_menu
	if menu == null:
		_fail("office has no pause menu")
		scene.queue_free()
		return

	_expect(not menu.tap_to_pause, "office pauses on a tap instead of a hold")

	# Standing up has to capture the mouse and show the reticle. Seated, the
	# free cursor IS the pointer and a second mark in the middle of the screen
	# would be clutter -- but the office is walkable now, and walking with a
	# loose cursor and no crosshair is the complaint this checks for.
	var view: OfficeView3D = scene.get_node("%OfficeView")
	var walker: OfficeWalker = view._walker
	var reticle: Crosshair = scene.find_child("Crosshair", true, false)
	if walker == null or reticle == null:
		_fail("the office has no walker or no crosshair")
	else:
		_expect(walker.seated, "the office did not start at the desk")
		_expect(MouseLock.cursor_visible(), "the desk took the cursor away from its own UI")
		# Standing must be reachable BY PLAYING, not only by calling stand().
		# Pointing at the console used to make interact press a button instead,
		# so the chair was effectively inescapable.
		view._hovered = "ctrl:LeftDoor"
		Input.action_press("interact")
		view._update_seating()
		Input.action_release("interact")
		_expect(not walker.seated,
			"interact worked a control instead of standing the player up")
		view._hovered = ""
		_expect(MouseLock.is_captured(), "standing up did not capture the mouse")
		reticle._process(0.016)
		_expect(reticle._shown, "standing up did not show the crosshair")
		walker.sit()
		_expect(MouseLock.cursor_visible(), "sitting back down did not free the cursor")
		reticle._process(0.016)
		_expect(not reticle._shown, "the crosshair stayed up at the desk")

	# A tap, then a hold, driven by hand rather than in real time.
	Input.action_press("pause")
	menu._process(0.2)
	_expect(not menu.is_open(), "a 0.2 s press paused a mode that asks for 3 s")
	Input.action_release("pause")
	menu._process(0.016)
	_expect(not menu.is_open(), "releasing early still paused")

	Input.action_press("pause")
	for i in 4:
		menu._process(PauseMenu.HOLD_SECONDS / 3.0)
	Input.action_release("pause")
	_expect(menu.is_open(), "holding ESC past %.0f s did not pause" % PauseMenu.HOLD_SECONDS)
	_expect(MouseLock.cursor_visible(), "the office pause menu did not free the cursor")

	menu.close()
	_expect(not _tree().paused, "closing the office menu left the tree paused")

	_tree().paused = false
	scene.queue_free()
	await _frame()
	print("  office    ignores a tap, pauses after a %.0f s hold" % PauseMenu.HOLD_SECONDS)


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
