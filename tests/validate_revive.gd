extends RefCounted

## Co-op revives (ReviveDowns, docs/REVIVE.md): the host opens a 90 s window where a runner went down; a teammate with
## a Revive Kit holds [E] there for 3 s (moving off, sprinting or a grab breaks it) and the downed runner is back at that
## spot with 25 stamina and 3.5 s of grace, the kit used up once. The host refuses no kit, too far, another floor, a
## short hold, a closed window and a runner who is not actually down; windows ride the world snapshot; a run restart
## clears them. Solo, a kit is a one-time second wind on a struggle catch.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- revive

const STEP := 1.0 / 60.0
const GUEST := 7

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _reviver(at: Vector3, kit := true, depth := 0) -> Dictionary:
	return {"at": at, "depth": depth, "owned_items": {"revive_kit": kit},
		"inventory_order": ["flashlight", "revive_kit" if kit else ""], "spectating": false}


func _unit() -> void:
	var downs := ReviveDowns.new()
	downs.down(GUEST, Vector3(10, 0, 10), 0, "GUEST")
	var near := _reviver(Vector3(10.8, 0, 10))
	_expect(downs.refusal(1, GUEST, near, true, 0.0, false).is_empty(), "a legit start was refused")
	_expect(downs.refusal(1, GUEST, _reviver(Vector3(10.8, 0, 10), false), true, 0.0, false) == "no_kit", "no kit passed")
	_expect(downs.refusal(1, GUEST, _reviver(Vector3(14, 0, 10)), true, 0.0, false) == "range", "4 m away passed")
	_expect(downs.refusal(1, GUEST, _reviver(Vector3(10.8, 0, 10), true, 1), true, 0.0, false) == "range", "another floor passed")
	_expect(downs.refusal(1, GUEST, near, false, 0.0, false) == "not_down", "a runner who is not spectating could be revived")
	_expect(downs.refusal(GUEST, GUEST, near, true, 0.0, false) == "self", "a self-revive passed")
	downs.start_hold(1, GUEST, 100.0)
	_expect(int(downs.downs[GUEST]["by"]) == 1, "the hold does not name the reviver")
	_expect(downs.refusal(1, GUEST, near, true, 101.0, true) == "hold", "a 1 s hold finished")
	_expect(downs.refusal(1, GUEST, near, true, 100.0 + GameConfig.REVIVE_HOLD_SECONDS, true).is_empty(), "a full hold was refused")
	_expect(downs.stop_hold(1) == GUEST and int(downs.downs[GUEST]["by"]) == 0, "stopping the hold did not clear the reviver")
	_expect(downs.refusal(1, GUEST, near, true, 200.0, true) == "hold", "a finish with no hold started passed")
	# the window
	var world := StreamedWorldState.new()
	world.downs.down(GUEST, Vector3(3, 0, 4), 2, "GUEST", 40.0)
	var copy := StreamedWorldState.new()
	copy.adopt(world.snapshot())
	_expect(copy.downs.is_down(GUEST) and int(copy.downs.downs[GUEST]["depth"]) == 2
		and is_equal_approx(float(copy.downs.downs[GUEST]["left"]), 40.0), "the revive window did not ride the snapshot")
	var legacy := world.snapshot()
	legacy.erase("downs")
	_expect(copy.adopt(legacy) and copy.downs.downs.is_empty(), "a snapshot with no windows did not load clean")
	_expect(downs.tick(GameConfig.REVIVE_WINDOW_SECONDS - 1.0).is_empty() and downs.is_down(GUEST), "the window closed early")
	_expect(downs.tick(1.5) == [GUEST] and not downs.is_down(GUEST), "the window did not close at %.0f s" % GameConfig.REVIVE_WINDOW_SECONDS)
	_expect(downs.refusal(1, GUEST, near, true, 0.0, false) == "window", "a closed window still revived")


func run(host: Node) -> int:
	_unit()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 8:
		await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
	var remotes: RemotePlayers = scene._remotes

	# solo: no windows, and the kit is a second wind on a struggle catch
	scene._host_record_down(GUEST, player.global_position, 0)
	_expect(scene.world_state.downs.downs.is_empty(), "a solo run opened a revive window")
	player.grant_inventory_item("revive_kit", 2)
	scene._begin_escape_struggle("NO-HUNTER", "dovelle")
	_expect(player.item_count("revive_kit") == 1 and not GameState.escape_active and not player.input_frozen,
		"the solo second wind did not use one kit and break the hold")
	_expect(scene._capture_cooldown >= GameConfig.REVIVE_GRACE_SECONDS - .1, "the second wind gave no grace")

	# co-op, this peer the host and the reviver; a fake guest who went down
	host.get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()   # unique id 1, no peers
	RoomState.online = true
	RoomState.is_host = true
	var local: int = int(scene._local_peer_id())
	var down_at := player.global_position + Vector3(1.0, 0, 0)
	remotes._states[GUEST] = {"peer_id": GUEST, "at": down_at, "depth": -int(scene.facility.current_level()),
		"spectating": true, "received_usec": Time.get_ticks_usec(), "display_name": "GUEST"}
	scene._host_record_down(GUEST, down_at, -int(scene.facility.current_level()))
	await host.get_tree().process_frame
	_expect(scene.world_state.downs.is_down(GUEST), "the host did not open a window for a downed guest")
	var marker = scene._revive_markers.get(GUEST)
	_expect(marker is RouteInteractable3D and (marker as RouteInteractable3D).kind == RouteInteractable3D.Kind.REVIVE_SPOT,
		"no revive marker at the spot")
	_expect(player._hold_seconds(marker) == GameConfig.REVIVE_HOLD_SECONDS, "a kit carrier gets no revive hold")
	player.inventory_order[player.inventory_order.find("revive_kit")] = ""
	player._sync_owned_inventory_items()
	_expect(player._hold_seconds(marker) == 0.0 and (marker as RouteInteractable3D).get_prompt().contains("NEEDS A REVIVE KIT"),
		"no kit: still a hold, or no hint")
	# without a kit the host refuses even a direct request
	scene._request_revive(GUEST, "start")
	_expect(scene.world_state.downs.holds.is_empty(), "the host started a hold with no kit")
	player.grant_inventory_item("revive_kit", 2)
	# a finish without the hold time is refused
	scene._request_revive(GUEST, "start")
	scene._request_revive(GUEST, "finish")
	_expect(scene.world_state.downs.is_down(GUEST) and player.item_count("revive_kit") == 2, "a revive finished without the 3 s hold")
	# the real hold, through the player's own hold logic
	scene._request_revive(GUEST, "stop")
	player.global_position = down_at - Vector3(1.0, 0, 0)
	player._resecure_target = marker
	player._resecure_progress = 0.0
	scene.world_state.downs.start_hold(local, GUEST, Time.get_ticks_msec() / 1000.0 - GameConfig.REVIVE_HOLD_SECONDS)
	scene._request_revive(GUEST, "finish")
	_expect(not scene.world_state.downs.is_down(GUEST), "a full hold did not revive the guest")
	_expect(player.item_count("revive_kit") == 1, "the revive did not use exactly one kit (%d left)" % player.item_count("revive_kit"))
	await host.get_tree().process_frame
	_expect(not scene._revive_markers.has(GUEST), "the marker stayed after the revive")
	# the hold breaks when the reviver walks off or sprints
	scene._host_record_down(GUEST, down_at, -int(scene.facility.current_level()))
	await host.get_tree().process_frame
	marker = scene._revive_markers.get(GUEST)
	var changes := []
	var note := func(_peer: int, holding: bool) -> void: changes.append(holding)
	player.revive_hold_changed.connect(note)
	player._resecure_target = marker
	player._resecure_progress = .5
	player._revive_hold_from = player.global_position
	player.movement_mode = "walk"
	_expect(not player._revive_hold_broken(), "standing still broke the hold")
	player.movement_mode = "sprint"
	_expect(player._revive_hold_broken(), "sprinting did not break the hold")
	player.movement_mode = "walk"
	player.global_position += Vector3(GameConfig.REVIVE_BREAK_DISTANCE + .1, 0, 0)
	_expect(player._revive_hold_broken(), "walking %.1f m off did not break the hold" % (GameConfig.REVIVE_BREAK_DISTANCE + .1))
	player._reset_hold()
	player.revive_hold_changed.disconnect(note)
	_expect(changes == [false] and player._resecure_progress == 0.0, "breaking the hold did not tell the host (%s)" % [changes])
	# a skipped frame (grabbed, stunned) breaks it too
	player._resecure_target = marker
	player._resecure_progress = .5
	player._resecure_frame = Engine.get_physics_frames() - 5
	player._update_resecure(STEP)
	_expect(player._resecure_progress == 0.0, "a grab or stun gap kept the hold going")
	# the downed side: back at the spot, out of spectating, low stamina, grace
	scene._clear_revives()
	player.enter_spectator()
	scene._host_record_down(local, down_at, -int(scene.facility.current_level()))
	_expect(scene.world_state.downs.is_down(local) and not scene._revive_markers.has(local), "own window missing, or a marker for ourselves")
	_expect(scene._revive_note().contains("WAITING FOR A REVIVE KIT") or scene._revive_note().contains("HAS A REVIVE KIT"),
		"the spectator line is missing (%s)" % scene._revive_note())
	scene.world_state.downs.set_reviver(local, GUEST)
	_expect(scene._revive_note().contains("IS REVIVING YOU"), "no IS REVIVING YOU line")
	scene._apply_revive_event({"what": "stream_revived", "peer": local, "by": GUEST, "at": down_at})
	_expect(not player.spectator_mode and player.global_position.distance_to(down_at) < .05, "the revived runner is not back at the spot")
	_expect(is_equal_approx(player.stamina, GameConfig.REVIVE_STAMINA) and scene._capture_cooldown >= GameConfig.REVIVE_GRACE_SECONDS - .1,
		"revived without low stamina and grace")
	# a restart clears every window
	scene._host_record_down(GUEST, down_at, 0)
	scene._clear_revives()
	_expect(scene.world_state.downs.downs.is_empty() and scene._revive_markers.is_empty(), "a restart left revive windows")
	_expect(RemotePlayers.HOST_MOVES.has("revive_at"), "a revive is not a host move for GuestGuard")
	remotes._states.erase(GUEST)
	RoomState.online = false
	host.get_tree().get_multiplayer().multiplayer_peer = null
	scene.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  revive  ok")
	return _failures
