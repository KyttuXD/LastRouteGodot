extends RefCounted

## Behavioral check for the replacement of the old three-second auto-reset and
## life pool. A failed capture plays the local hunter/camera sequence and stops
## the run until an explicit choice. Co-op capture has no hidden rejoin button.

var _host: Node
var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_host = host
	var account_before := {
		"username": Backend.account_username,
		"token": Backend.account_session_token,
		"admin": Backend.account_admin,
		"admin_owner": Backend.account_admin_owner,
		"admin_permissions": Backend.account_admin_permissions.duplicate(),
		"verified": Backend.account_session_verified,
	}
	# Never let a validation run contact the real account save slot when it
	# deliberately triggers solo game-over.
	Backend.account_username = ""
	Backend.account_session_token = ""
	Backend.account_admin = false
	Backend.account_admin_owner = false
	Backend.account_admin_permissions = PackedStringArray()
	Backend.account_session_verified = false

	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame

	GameState.depth = 6
	GameState.score = 3100
	GameState.coins = 7
	GameState.relays_collected = 2
	GameState.relay_target = 5
	scene.capturing_view = scene.hunter_view
	scene.jumpscare.duration = 0.05
	await scene._resolve_capture_outcome()
	await host.get_tree().process_frame
	_expect(GameState.game_over, "failed capture did not end the run")
	_expect(scene.jumpscare.last_hunter_id == scene.hunter_view.brain.hunter_id,
		"jumpscare used a different hunter from the capture")
	_expect(not scene.jumpscare.playing,
		"jumpscare camera did not return control after its animation")
	_expect(scene.run_report.is_open(),
		"solo game-over did not open the run report")
	_expect(scene.player.input_frozen,
		"solo player can move behind the run report")
	_expect(MouseLock.cursor_visible(),
		"run report did not release the pointer for its actions")
	var depth_label := scene.run_report.find_child("DepthReachedValue", true, false) as Label
	_expect(depth_label != null and depth_label.text == "6",
		"run report did not preserve the finished depth")

	scene._restart_solo_route()
	await host.get_tree().process_frame
	_expect(not scene.run_report.is_open() and not GameState.game_over,
		"explicit solo restart did not close/reset game-over")
	_expect(GameState.depth == 1 and GameState.score == 0 and GameState.coins == 0,
		"explicit solo restart retained the completed run totals")
	_expect(not scene.player.input_frozen,
		"explicit solo restart left the player frozen")

	# One captured runner cannot silently respawn. A guest can leave; a captured
	# host explicitly ends the shared route for everyone.
	scene._remotes.set_process(false)
	host.get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	RoomState.online = true
	RoomState.is_host = false
	RoomState.session_active = true
	GameState.depth = 9
	scene.observed_depth = 9
	GameState.score = 8800
	GameState.coins = 21
	GameState.game_over = true
	scene._enter_game_over()
	await host.get_tree().process_frame
	_expect((scene.run_report.find_child("ReportPrimaryButton", true, false) as Button).text
		== "LEAVE ROOM", "captured guest is offered a hidden rejoin")
	_expect(not (scene.run_report.find_child("ReportSecondaryButton", true, false) as Button).visible,
		"co-op report shows a second respawn/rejoin path")
	_expect(GameState.depth == 9 and GameState.score == 8800 and GameState.coins == 21,
		"opening the captured-runner report reset shared route progress")
	RoomState.is_host = true
	scene._enter_game_over()
	await host.get_tree().process_frame
	_expect((scene.run_report.find_child("ReportPrimaryButton", true, false) as Button).text
		== "END ROUTE", "captured host is not told that leaving ends the route")

	RoomState.online = false
	RoomState.is_host = true
	RoomState.session_active = false
	host.get_tree().get_multiplayer().multiplayer_peer = null
	scene.queue_free()
	await host.get_tree().process_frame
	MouseLock.claim("run_report", false)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	Backend.account_username = account_before["username"]
	Backend.account_session_token = account_before["token"]
	Backend.account_admin = account_before["admin"]
	Backend.account_admin_owner = account_before["admin_owner"]
	Backend.account_admin_permissions = account_before["admin_permissions"]
	Backend.account_session_verified = account_before["verified"]

	if _failures == 0:
		print("  capture   hunter model lunges through a temporary local camera")
		print("  solo      report waits for Restart/Main Menu and preserves final stats")
		print("  co-op     capture offers Leave/End Route with no life-pool rejoin")
		print("run report OK")
	return _failures
