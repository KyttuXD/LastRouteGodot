extends RefCounted

## NPC teammates (NpcTeammates, docs/NPC_TEAMMATES.md): the host simulates them and publishes each as a runner state, so they are
## in the hunters' target list and the player list ("NPC · name"), keep up with a runner, go down on a capture (a revive
## window), come back on a revive and are out when the window closes. The room setting clamps to 0..MAX_COUNT, the new RPC
## keeps every older RPC id (its name sorts last), and one NPC packet stays inside its budget.
##
##   godot --headless --path . res://scenes/validate.tscn -- npc_teammates

const PACKET_BUDGET := 600   # bytes of one NPC state as sent (var_to_bytes)

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _unit() -> void:
	_expect(RemotePlayers.is_npc(NpcTeammates.ID_BASE) and not RemotePlayers.is_npc(1) and not RemotePlayers.is_npc(123456789),
		"is_npc picks the wrong ids")
	RoomState.online = false
	RoomState.set_npc_teammates(99)
	_expect(RoomState.npc_teammates == NpcTeammates.MAX_COUNT, "the setting did not clamp to %d" % NpcTeammates.MAX_COUNT)
	RoomState.set_npc_teammates(-2)
	_expect(RoomState.npc_teammates == 0, "the setting went below 0")
	# Godot numbers a script's RPCs by sorted name: the NPC RPC must sort last so older builds keep the others' ids
	var names: Array = []
	var lines := FileAccess.get_file_as_string("res://src/game_3d/remote_players.gd").split("\n")
	for i in lines.size() - 1:
		if lines[i].begins_with("@rpc("):
			names.append(lines[i + 1].get_slice("func ", 1).get_slice("(", 0))
	names.sort()
	_expect(not names.is_empty() and names[-1] == "_xnpc_place", "the NPC RPC does not sort last: %s" % [names])


## The staging screen: no NPC row for a player; an admin host gets the ◀ N ▶ scroller, which steps and stops at 0 and MAX_COUNT.
func _lobby(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.online = true
	RoomState.is_host = true
	RoomState.npc_teammates = 0
	for admin in [false, true]:
		Build.deny_admin_for_test = not admin
		var lobby := Control.new()
		lobby.set_script(load("res://src/ui/room_lobby.gd"))
		host.add_child(lobby)
		await host.get_tree().process_frame
		var row := lobby.find_child("LobbyNpcTeammates", true, false)
		if not admin:
			_expect(row == null, "a player sees the NPC TEAMMATES row")
		else:
			_expect(row != null, "an admin host has no NPC TEAMMATES scroller")
			if row != null:
				_expect((row.find_child("NpcLess", true, false) as Button).disabled, "◀ is enabled at 0")
				(row.find_child("NpcMore", true, false) as Button).pressed.emit()
				_expect(RoomState.npc_teammates == 1, "▶ did not step to 1")
				RoomState.npc_teammates = NpcTeammates.MAX_COUNT
		lobby.queue_free()
		await host.get_tree().process_frame
	Build.deny_admin_for_test = false
	RoomState.npc_teammates = 0
	RoomState.online = false


func run(host: Node) -> int:
	_unit()
	await _lobby(host)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 8:
		await host.get_tree().process_frame
	var tree := host.get_tree()
	var player: PlayerController3D = scene.player
	var remotes: RemotePlayers = scene._remotes
	tree.get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()   # unique id 1, no peers
	RoomState.online = true
	RoomState.is_host = true
	scene._start_npcs(2)
	var npcs: NpcTeammates = scene._npcs
	_expect(npcs != null and npcs.npcs.size() == 2, "the host did not start 2 NPC teammates")
	if npcs == null:
		return _finish(scene)
	for _i in 30:
		await tree.physics_frame
	var a := NpcTeammates.ID_BASE
	_expect(remotes._states.has(a) and remotes._states.has(a + 1) and bool((remotes._states[a] as Dictionary).get("npc", false)),
		"the NPCs are not runner states on the host")
	var names := remotes.player_list_rows(false).map(func(row: Dictionary) -> String: return String(row["name"]))
	var npc_names := names.filter(func(n: String) -> bool: return n.begins_with("NPC · ") and GuestNames.valid(n.trim_prefix("NPC · ")))
	_expect(npc_names.size() >= 2, "the player list does not show the NPCs with guest-style names and the NPC tag: %s" % [names])
	var targets := remotes.target_states({}).map(func(t: Dictionary) -> int: return int(t.get("peer_id", 0)))
	_expect(targets.has(a) and targets.has(a + 1), "the hunters' target list leaves the NPCs out: %s" % [targets])
	# hunters sense an NPC like a runner: a player's footstep noise and a torch on
	var walking: Dictionary = npcs.npcs[0].duplicate()
	walking["clip"] = "walk"
	var sensed := npcs.state_of(walking)
	_expect(float(sensed["noise"]) == GameConfig.NOISE_WALK and bool(sensed["flashlight_on"]) and sensed["facing"] is Vector2,
		"an NPC is quieter or darker to the hunters than a runner: %s" % [[sensed["noise"], sensed["flashlight_on"]]])
	_expect(var_to_bytes(npcs.state_of(npcs.npcs[0])).size() <= PACKET_BUDGET,
		"one NPC packet is %d bytes (budget %d)" % [var_to_bytes(npcs.state_of(npcs.npcs[0])).size(), PACKET_BUDGET])
	# it keeps up: its runner walks off 9 m, and within 4 s it is closer again
	var start: Vector3 = npcs.npcs[0]["at"]
	var nav: StreamedHunterNavigation = scene._navigation
	var open: Dictionary = nav.nearest_open_position(player.global_position.x + 9.0, player.global_position.z, .23)
	if open.has("cell"):
		player.global_position = Vector3((open["cell"] as Vector2i).x + .5, player.global_position.y, (open["cell"] as Vector2i).y + .5)
		var before := (start as Vector3).distance_to(player.global_position)
		for _i in 240:
			await tree.physics_frame
		var after := (npcs.npcs[0]["at"] as Vector3).distance_to(player.global_position)
		_expect(after < before - 2.0, "the NPC did not follow its runner (%.1f m -> %.1f m)" % [before, after])
	else:
		print("  note: no open floor 9 m off the spawn, follow check skipped")
	await _hunter_hunts_npc(scene, npcs, remotes)
	# a hunter's capture: down, a revive window, a ghost to everyone
	remotes.send_player_event(a, {"what": "capture"})
	await tree.physics_frame
	_expect(npcs.is_down(a) and scene.world_state.downs.is_down(a), "a capture did not put the NPC down with a revive window")
	for _i in 8:
		await tree.physics_frame
	_expect(bool((remotes._states[a] as Dictionary).get("spectating", false)), "a downed NPC is not shown as down")
	var rows := remotes.player_list_rows(false).filter(func(row: Dictionary) -> bool: return int(row["id"]) == a)
	_expect(not rows.is_empty() and String(rows[0]["status"]) != RoomPlayerList.STATUS_ALIVE, "the list still shows the downed NPC alive")
	# a teammate's revive brings it back with a grace
	scene._apply_revive_event({"what": "stream_revived", "peer": a, "by": 0, "at": npcs.npcs[0]["at"]})
	_expect(not npcs.is_down(a) and float(npcs.npcs[0]["grace"]) > 0.0, "the revive did not bring the NPC back with a grace")
	# down again, and the window closes: out of the run
	npcs.npcs[0]["grace"] = 0.0
	remotes.send_player_event(a, {"what": "capture"})
	scene.world_state.downs.clear(a)
	await tree.physics_frame
	_expect(bool(npcs.npcs[0]["out"]), "an NPC whose window closed is not out of the run")
	return _finish(scene)


## A hunter summoned onto an NPC (the host's own runner hidden from hunters) spots it, chases and catches it: the NPC goes down.
func _hunter_hunts_npc(scene: Node, npcs: NpcTeammates, remotes: RemotePlayers) -> void:
	var tree := scene.get_tree()
	var b := NpcTeammates.ID_BASE + 1
	var player: PlayerController3D = scene.player
	player.admin_no_target = true
	scene._admin_summon_hunter_authoritative(b, "dovelle")
	var chased := false
	var caught := false
	var states := {}
	for _i in 60 * 40:
		await tree.physics_frame
		for view_value in scene._hunter_views.values():
			var view := view_value as HunterView3D
			if view != null and view.brain != null:
				states[HunterBrain.State.keys()[view.brain.state]] = true
				if view.brain.state == HunterBrain.State.CHASE:
					chased = true
		if npcs.is_down(b) or bool(npcs.npcs[1]["out"]):
			caught = true
			break
	_expect(not scene._hunter_views.is_empty(), "no hunter was summoned onto the NPC")
	_expect(chased, "the hunter never chased the NPC (states seen: %s)" % [states.keys()])
	_expect(caught, "the hunter did not catch the NPC within 40 s")
	_expect(not caught or scene.world_state.downs.is_down(b), "the caught NPC has no revive window")
	# leave the rest of the suite a clean slate: the hunter gone, the NPC back on its feet, the host targetable again
	for entity_id in scene.world_state.hunters.keys().duplicate():
		scene._unload_hunter(String(entity_id), false)
		scene.world_state.hunters.erase(entity_id)
	scene.world_state.downs.clear(b)
	npcs.revived(b)
	player.admin_no_target = false


func _finish(scene: Node) -> int:
	scene.get_tree().get_multiplayer().multiplayer_peer = null
	RoomState.online = false
	scene.queue_free()
	return _failures
