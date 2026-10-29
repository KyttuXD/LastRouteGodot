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
	var npc_rpcs := names.filter(func(n: String) -> bool: return n.begins_with("_xnpc_"))
	_expect(npc_rpcs.size() >= 2 and names.slice(names.size() - npc_rpcs.size()) == npc_rpcs,
		"the NPC RPCs do not sort after every other RPC: %s" % [names])


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
		var facing := float(npcs.npcs[0]["facing"])
		var fastest := 0.0
		for _i in 240:
			await tree.physics_frame
			var now := float(npcs.npcs[0]["facing"])
			fastest = maxf(fastest, absf(wrapf(now - facing, -PI, PI)) * 60.0)
			facing = now
		_expect(fastest <= NpcTeammates.TURN_RATE + .05, "an NPC snapped round at %.1f rad/s (cap %.1f)" % [fastest, NpcTeammates.TURN_RATE])
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
	await _admin_tools(scene, npcs, remotes)
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


## The admin NPCS page's commands, on the host: spawn more, act on one (freeze, hunters ignore, follow, teleport, kill,
## remove); a guest admin's request is applied, a normal guest's refused, and the panel lists the NPCs.
func _admin_tools(scene: Node, npcs: NpcTeammates, remotes: RemotePlayers) -> void:
	var tree := scene.get_tree()
	var before := npcs.npcs.size()
	scene._admin_world_action("npc", {"op": "spawn", "count": 3, "smart": 90})
	_expect(npcs.npcs.size() == before + 3, "admin spawn of 3 gave %d" % (npcs.npcs.size() - before))
	var id := int(npcs.npcs[-1]["id"])
	_expect(int(npcs.npcs[-1]["smart"]) == 90, "the spawn smartness was not kept")
	for _i in 8:
		await tree.physics_frame
	var panel := AdminNpcPanel.new(scene)
	scene.add_child(panel)
	await tree.process_frame
	_expect(panel.rows().size() == npcs.npcs.size(), "the admin list shows %d NPCs, there are %d" % [panel.rows().size(), npcs.npcs.size()])
	scene._admin_world_action("npc", {"op": "freeze", "id": id})
	scene._admin_world_action("npc", {"op": "ignore", "id": id})
	for _i in 8:
		await tree.physics_frame
	var state := remotes.peer_state(id)
	_expect(int((state.get("npc_admin", [0]) as Array)[0]) & 1 and bool(state.get("no_target", false)), "freeze / ignore did not reach the NPC's state")
	var picked := remotes.best_target(state.get("position", Vector2.ZERO), {}, int(state.get("depth", 0)))
	_expect(int(picked.get("peer_id", 0)) != id, "a hunter still picks an NPC the admin made them ignore")
	var far: Vector3 = scene.player.global_position + Vector3(0, 0, 0)
	scene._admin_world_action("npc", {"op": "teleport", "id": id})
	_expect((npcs.find(id)["at"] as Vector3).distance_to(far) < 3.0, "teleport to me left the NPC %.1f m away" % (npcs.find(id)["at"] as Vector3).distance_to(far))
	scene._admin_world_action("npc", {"op": "follow", "id": id})
	_expect(int(npcs.find(id)["follow_peer"]) == 1, "follow me did not bind the NPC to the admin")
	scene._admin_world_action("npc", {"op": "kill", "id": id})
	_expect(bool(npcs.find(id)["out"]), "kill did not take the NPC out")
	scene._admin_world_action("npc", {"op": "remove", "id": id})
	await tree.physics_frame
	_expect(npcs.find(id).is_empty() and remotes.peer_state(id).is_empty(), "remove left the NPC in the run")
	# a guest admin (checked by the host) vs a normal guest: only the admin's spawn lands, the other is refused
	Build.deny_admin_for_test = true
	var admin := 7
	var plain := 8
	RoomState.peers[admin] = "ADMIN-GUEST"
	RoomState.peers[plain] = "PLAIN-GUEST"
	for peer in [admin, plain]:
		remotes._states[peer] = {"peer_id": peer, "at": scene.player.global_position, "position": scene.player.grid_position(),
			"depth": -int(scene.facility.current_level()), "received_usec": Time.get_ticks_usec(), "display_name": "G%d" % peer}
	remotes.authorize_admin_peer(admin, 600, PackedStringArray(["world"]))
	var count := npcs.npcs.size()
	scene._on_remote_interaction_request(plain, {"what": "admin_world", "action": "npc", "op": "spawn", "count": 1, "admin_ticket": ""})
	_expect(npcs.npcs.size() == count, "a normal guest spawned an NPC")
	scene._on_remote_interaction_request(admin, {"what": "admin_world", "action": "npc", "op": "spawn", "count": 1, "admin_ticket": ""})
	_expect(npcs.npcs.size() == count + 1, "a guest admin's spawn was not applied")
	scene._on_remote_interaction_request(admin, {"what": "admin_world", "action": "npc", "op": "remove_all", "admin_ticket": ""})
	_expect(npcs.npcs.is_empty(), "a guest admin's remove all left %d" % npcs.npcs.size())
	Build.deny_admin_for_test = false
	for peer in [admin, plain]:
		RoomState.peers.erase(peer)
		remotes._states.erase(peer)
	panel.queue_free()


func _finish(scene: Node) -> int:
	scene.get_tree().get_multiplayer().multiplayer_peer = null
	RoomState.online = false
	scene.queue_free()
	return _failures
