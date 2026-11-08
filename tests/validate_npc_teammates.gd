extends RefCounted

## NPC teammates (NpcTeammates, docs/NPC_TEAMMATES.md): the host simulates them and publishes each as a runner state, so they are
## in the hunters' target list and the player list ("NPC · name"), keep up with a runner, go down on a capture (a revive
## window), come back on a revive and are out when the window closes. The room setting clamps to 0..COUNT_LIMIT (0 = unlimited), the new RPC
## keeps every older RPC id (its name sorts last), one NPC packet stays inside NpcPerfTable.PACKET_BUDGET, and the
## Budget table matches that helper (upload = npc_count * guest_count * SEND_HZ * packet_size). HUNTERS IGNORE leaves an NPC
## out of best_target; HUNTERS TARGET puts it in the preferred pool ahead of closer runners. The two clear each other.
## The host's own NO TARGET hides only that runner.
## An NPC whose runner is on another storey walks a stair, spiral, ladder or ramp onto that storey. The crossing is a
## run of positions along the link, not one teleport after a wait.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- npc_teammates

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _unit() -> void:
	_perf_table()
	_expect(RemotePlayers.is_npc(NpcTeammates.ID_BASE) and not RemotePlayers.is_npc(1) and not RemotePlayers.is_npc(123456789),
		"is_npc picks the wrong ids")
	RoomState.online = false
	# unlimited by default: a large setting is kept (no 16 cap), a negative one is 0
	RoomState.set_npc_teammates(40)
	_expect(RoomState.npc_teammates == 40, "the setting capped 40 NPCs at %d" % RoomState.npc_teammates)
	RoomState.set_npc_teammates(-2)
	_expect(RoomState.npc_teammates == 0, "the setting went below 0")
	_expect(NpcTeammates.clamp_count(999) == 999 and NpcTeammates.clamp_count(-3) == 0,
		"clamp_count is not 0 below and unlimited above (COUNT_LIMIT %d)" % NpcTeammates.COUNT_LIMIT)
	# Godot numbers a script's RPCs by sorted name: the NPC RPC must sort last so older builds keep the others' ids
	var names: Array = []
	var lines := FileAccess.get_file_as_string("res://game/network/remote_players.gd").split("\n")
	for i in lines.size() - 1:
		if lines[i].begins_with("@rpc("):
			names.append(lines[i + 1].get_slice("func ", 1).get_slice("(", 0))
	names.sort()
	var npc_rpcs := names.filter(func(n: String) -> bool: return n.begins_with("_xnpc_"))
	_expect(npc_rpcs.size() >= 2 and names.slice(names.size() - npc_rpcs.size()) == npc_rpcs,
		"the NPC RPCs do not sort after every other RPC: %s" % [names])
	_storey_route_math()
	_hunt_prefer()


## The staging screen: no NPC row for a player; an admin host gets the ◀ N ▶ scroller, which stops at 0 and has no upper limit.
func _lobby(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.online = true
	RoomState.is_host = true
	RoomState.npc_teammates = 0
	for admin in [false, true]:
		Build.deny_admin_for_test = not admin
		var lobby := Control.new()
		lobby.set_script(load("res://game/menus/room_lobby.gd"))
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
		lobby.queue_free()
		await host.get_tree().process_frame
	Build.deny_admin_for_test = false
	# no upper limit: on a fresh staging screen the ▶ steps past 64, and the count it sets is kept
	RoomState.npc_teammates = 64
	var top := Control.new()
	top.set_script(load("res://game/menus/room_lobby.gd"))
	host.add_child(top)
	await host.get_tree().process_frame
	var top_row := top.find_child("LobbyNpcTeammates", true, false)
	_expect(top_row != null, "the admin staging screen has no NPC TEAMMATES scroller at 64")
	if top_row != null:
		var more := top_row.find_child("NpcMore", true, false) as Button
		_expect(not more.disabled, "▶ is disabled at 64: the staging stepper still has a ceiling")
		more.pressed.emit()
		_expect(RoomState.npc_teammates == 65, "▶ did not step past 64 (now %d)" % RoomState.npc_teammates)
	top.queue_free()
	await host.get_tree().process_frame
	RoomState.npc_teammates = 0
	RoomState.online = false


## Captures the spawn request the admin NPCS panel sends, without a route.
class SpawnRecorder extends Node:
	var last := {}

	func _admin_world_action(_kind: String, payload: Dictionary) -> void:
		last = payload


## The admin NPCS spawn stepper has no upper limit: it steps past 64, and the request it sends carries that count.
func _spawn_count_uncapped(host: Node) -> void:
	var recorder := SpawnRecorder.new()
	host.add_child(recorder)
	var panel := AdminNpcPanel.new(recorder)
	host.add_child(panel)
	await host.get_tree().process_frame
	panel._set_count(64)
	(panel.find_child("NpcMore", true, false) as Button).pressed.emit()
	_expect(panel._count == 65, "the NPCS spawn stepper stopped at %d, not 65" % panel._count)
	(panel.find_child("NpcSpawn", true, false) as Button).pressed.emit()
	_expect(String(recorder.last.get("op", "")) == "spawn" and int(recorder.last.get("count", 0)) == 65,
		"the spawn request carried %s, not a count of 65" % [recorder.last])
	panel.queue_free()
	recorder.queue_free()
	await host.get_tree().process_frame


## HUNTERS TARGET / IGNORE, without a route: the flags publish on the NPC state, best_target prefers a marked NPC over a
## closer runner, ignore still excludes it, and the host's own NO TARGET does not hide the NPC. A trolled guest still wins.
func _hunt_prefer() -> void:
	var team := NpcTeammates.new()
	var npc_id := NpcTeammates.ID_BASE
	team.npcs.append({"id": npc_id, "name": "R-1", "at": Vector3.ZERO, "level": 0, "facing": 0.0, "clip": "idle",
		"down": false, "out": false, "grace": 0.0, "ignored": false, "targeted": false, "frozen": false, "chat": true,
		"smart": 70, "follow_peer": 0})
	_expect(team.command(npc_id, "target") and bool(team.npcs[0]["targeted"]) and not bool(team.npcs[0]["ignored"]),
		"HUNTERS TARGET did not mark the NPC")
	var published := team.state_of(team.npcs[0])
	_expect(bool(published.get("hunt_target", false)) and not bool(published.get("no_target", false)),
		"HUNTERS TARGET did not publish hunt_target (or left no_target set)")
	_expect(team.command(npc_id, "ignore") and bool(team.npcs[0]["ignored"]) and not bool(team.npcs[0]["targeted"]),
		"HUNTERS IGNORE did not clear the target mark")
	published = team.state_of(team.npcs[0])
	_expect(bool(published.get("no_target", false)) and not bool(published.get("hunt_target", false)),
		"HUNTERS IGNORE did not publish no_target (or left hunt_target set)")
	_expect(team.command(npc_id, "target") and not bool(team.npcs[0]["ignored"]) and bool(team.npcs[0]["targeted"]),
		"HUNTERS TARGET did not clear ignore")
	team.free()

	var remotes := RemotePlayers.new()
	var now := Time.get_ticks_usec()
	var guest := 71
	remotes._states[npc_id] = {"peer_id": npc_id, "position": Vector2(40, 0), "depth": 0, "received_usec": now,
		"npc": true, "hunt_target": true, "no_target": false}
	remotes._states[guest] = {"peer_id": guest, "position": Vector2(2, 0), "depth": 0, "received_usec": now}
	var local := {"peer_id": 1, "position": Vector2(1, 0), "depth": 0}
	var picked := remotes.best_target(Vector2.ZERO, local, 0)
	_expect(int(picked.get("peer_id", 0)) == npc_id,
		"hunters did not prefer the targeted NPC over a closer runner (%s)" % picked)
	remotes._states[npc_id]["hunt_target"] = true
	remotes._states[npc_id]["no_target"] = true
	picked = remotes.best_target(Vector2.ZERO, local, 0)
	_expect(int(picked.get("peer_id", 0)) != npc_id,
		"a hunter still picks an NPC that is both ignored and marked (%s)" % picked)
	remotes._states[npc_id]["hunt_target"] = false
	remotes._states[npc_id]["no_target"] = true
	picked = remotes.best_target(Vector2.ZERO, local, 0)
	_expect(int(picked.get("peer_id", 0)) == 1, "an ignored NPC was still hunted (%s)" % picked)
	# the host's NO TARGET hides only the host; the NPC (the only one left) is still the target
	remotes._states.erase(guest)
	remotes._states[npc_id]["no_target"] = false
	remotes._states[npc_id]["hunt_target"] = false
	local["no_target"] = true
	picked = remotes.best_target(Vector2.ZERO, local, 0)
	_expect(int(picked.get("peer_id", 0)) == npc_id,
		"host NO TARGET stopped hunters choosing the NPC (%s)" % picked)
	remotes._states[guest] = {"peer_id": guest, "position": Vector2(3, 0), "depth": 0, "received_usec": now}
	picked = remotes.best_target(Vector2.ZERO, local, 0)
	_expect(int(picked.get("peer_id", 0)) == guest,
		"an unmarked NPC was preferred over a closer runner (%s)" % picked)
	remotes._states[npc_id]["hunt_target"] = true
	remotes.troll_peers[guest] = true
	picked = remotes.best_target(Vector2.ZERO, local, 0)
	_expect(int(picked.get("peer_id", 0)) == guest and bool(picked.get("troll", false)),
		"troll mode lost to an NPC hunt target (%s)" % picked)
	remotes.free()


func run(host: Node) -> int:
	_unit()
	await _lobby(host)
	await _spawn_count_uncapped(host)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
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
	var packet_size := var_to_bytes(npcs.state_of(npcs.npcs[0])).size()
	_expect(packet_size <= NpcPerfTable.PACKET_BUDGET,
		"one NPC packet is %d bytes (budget %d)" % [packet_size, NpcPerfTable.PACKET_BUDGET])
	# the documented formula, on the packet that actually went out (the 4 NPC x 3 guest ceiling is the old 86 KB/s case)
	var measured := NpcPerfTable.host_upload_bytes_per_sec(4, 3, packet_size)
	_expect(measured == 4 * 3 * int(NpcTeammates.SEND_HZ) * packet_size,
		"upload helper %d != npc_count * guest_count * SEND_HZ * packet_size" % measured)
	_expect(measured <= NpcPerfTable.host_upload_bytes_per_sec(4, 3),
		"4 NPCs x 3 guests at %d B/packet is %d B/s, over the budget ceiling" % [packet_size, measured])
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
	await _storey_traversal(scene, npcs)
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
	_unlimited_spawn(scene, npcs)
	return _finish(scene)


## Stair and ladder crossings move along the link. A stair path is bottom-to-top in link-local space; going down reads it
## backwards, so the body leaves the upper floor, passes the middle of the flight, and arrives on the lower floor.
func _storey_route_math() -> void:
	var chunk := Vector3i.ZERO
	var stairs := LevelLink.make("stairs", chunk, 0, Vector2i(4, 4), -1, Vector2i(4, 4))
	stairs["path"] = [Vector3(4.5, 0.0, 4.5), Vector3(4.5, 2.0, 8.0), Vector3(4.5, 4.0, 4.5)]
	var top := NpcTeammates.crossing_point(stairs, 0, 0.0, 0.0)
	var mid := NpcTeammates.crossing_point(stairs, 0, 0.5, 0.0)
	var bottom := NpcTeammates.crossing_point(stairs, 0, 1.0, 0.0)
	_expect(is_equal_approx(top.y, 0.0) and is_equal_approx(bottom.y, -4.0),
		"a stair crossing does not run from the upper floor to the lower (%s -> %s)" % [top, bottom])
	_expect(mid.y < top.y - .5 and mid.y > bottom.y + .5, "a stair crossing skips the middle of the flight (%s)" % mid)
	_expect(mid.distance_to(Vector3(4.5, -2.0, 8.0)) < .2, "a stair crossing left its flight (%s)" % mid)
	var ladder := LevelLink.make("ladder", chunk, 0, Vector2i(10, 12), -1, Vector2i(10, 12))
	var high := NpcTeammates.crossing_point(ladder, 0, 0.0, 0.0)
	var low := NpcTeammates.crossing_point(ladder, 0, 1.0, 0.0)
	_expect(is_equal_approx(high.x, 10.5) and is_equal_approx(high.z, 12.5) and is_equal_approx(low.x, high.x) \
			and is_equal_approx(low.z, high.z), "a ladder crossing leaves the shaft (%s -> %s)" % [high, low])
	_expect(high.y > low.y + 3.0, "a ladder crossing does not change height (%s -> %s)" % [high, low])
	_expect(NpcTeammates.crossing_seconds(stairs) > .2, "a stair crossing takes no time")


## The runner is held on the storey below. The NPC has to get there along a stair or ladder: samples between the floors
## stay on that link, no frame covers the whole gap, and it steps off at the landing rather than beside the runner.
func _storey_traversal(scene: Node, npcs: NpcTeammates) -> void:
	var tree := scene.get_tree()
	var player: PlayerController3D = scene.player
	var facility: StreamedFacilityView3D = scene.facility
	var home := player.global_position
	var npc: Dictionary = npcs.npcs[0]
	var other: Dictionary = npcs.npcs[1]
	other["frozen"] = true
	npc["ignored"] = true
	npc["frozen"] = true
	var level := int(npc["level"])
	var nav: StreamedHunterNavigation = npcs._nav(level)
	_expect(nav != null, "no navigation on the NPC's storey to walk a stair")
	if nav == null:
		_restore_storey_fixture(scene, npcs, home)
		return
	var link := npcs._storey_link(level, Vector2(player.global_position.x, player.global_position.z), level - 1)
	if link.is_empty():
		link = npcs._storey_link(level, Vector2((npc["at"] as Vector3).x, (npc["at"] as Vector3).z), level - 1)
	_expect(not link.is_empty(), "no stair or ladder from the spawn storey toward the one below")
	if link.is_empty():
		_restore_storey_fixture(scene, npcs, home)
		return
	var floor_y := npcs._floor_y(level)
	var stand := _stand_near_link(nav, LadderTraffic.ladder_point(link, level), floor_y)
	if not stand.is_empty():
		npc["at"] = stand["at"]
		var chosen := npcs._storey_link(level, Vector2((stand["at"] as Vector3).x, (stand["at"] as Vector3).z), level - 1)
		if not chosen.is_empty():
			link = chosen
			var again := _stand_near_link(nav, LadderTraffic.ladder_point(link, level), floor_y)
			if not again.is_empty():
				stand = again
				npc["at"] = stand["at"]
	_expect(not stand.is_empty(), "no open floor beside the stair or ladder")
	if stand.is_empty():
		_restore_storey_fixture(scene, npcs, home)
		return
	var dest := int(LevelLink.other_end(link, level)["level"])
	var far := LadderTraffic.ladder_point(link, dest)
	var base_y := facility.global_position.y
	var leader_at := Vector3(far.x + 14.0, base_y + float(dest) * StreamedFacilityView3D.LEVEL_HEIGHT + .08, far.y)
	player.set_admin_noclip(true)
	player.velocity = Vector3.ZERO
	player.global_position = leader_at
	facility.refresh_at_tracked_player()
	for _i in 20:
		await tree.physics_frame
		player.global_position = leader_at
		player.velocity = Vector3.ZERO
	npcs._drop_crossing(npc)
	npc["at"] = stand["at"]
	npc["level"] = level
	npc["path"] = []
	npc["path_age"] = 99.0
	npc["ignored"] = true
	npc["frozen"] = false
	var started := Time.get_ticks_msec()
	var prev: Vector3 = npc["at"]
	var max_step := 0.0
	var between := 0
	var off_route := 0
	var used := {}
	var from_level := level
	var low_y := minf(npcs._floor_y(level), npcs._floor_y(dest))
	var high_y := maxf(npcs._floor_y(level), npcs._floor_y(dest))
	var speed := GameConfig.PLAYER_WALK_SPEED / GameConfig.TILE_SIZE
	var step_limit := speed / float(Engine.physics_ticks_per_second) * 2.5 + .08
	var arrived := false
	var arrive_at := Vector3.ZERO
	for _i in 60 * 12:
		await tree.physics_frame
		player.global_position = leader_at
		player.velocity = Vector3.ZERO
		var at: Vector3 = npc["at"]
		max_step = maxf(max_step, at.distance_to(prev))
		prev = at
		var climb: Dictionary = npc["climb"] if npc.get("climb") is Dictionary else {}
		if climb.get("link") is Dictionary:
			used = climb["link"]
			from_level = int(climb["from_level"])
		if at.y > low_y + .4 and at.y < high_y - .4:
			between += 1
			if not used.is_empty() and not _on_link_route(used, from_level, at, base_y):
				off_route += 1
		if int(npc["level"]) == dest:
			arrived = true
			arrive_at = at
			break
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	_expect(arrived, "the NPC did not reach storey %d (still on %d at %s after %.1fs, link %s)" % [
		dest, int(npc["level"]), npc["at"], seconds, link.get("id", "")])
	_expect(not used.is_empty(), "storey changed with no stair or ladder crossing")
	_expect(between >= 6, "the NPC changed storey without travelling between the floors (%d samples)" % between)
	_expect(off_route == 0, "%d between-floor samples left the stair or ladder route" % off_route)
	_expect(max_step <= step_limit, "the NPC jumped %.2f m in one frame (limit %.2f)" % [max_step, step_limit])
	if arrived and not used.is_empty():
		var landing := NpcTeammates.crossing_point(used, from_level, 1.0, base_y)
		_expect(arrive_at.distance_to(landing) < 1.5,
			"arriving on the storey left the link landing by %.1f m" % arrive_at.distance_to(landing))
		_expect(arrive_at.distance_to(leader_at) > 8.0,
			"the NPC appeared beside its runner (%.1f m) instead of at the link" % arrive_at.distance_to(leader_at))
		print("  storey  crossed %s in %.2fs (max step %.3f m, %d between-floor samples)" % [
			String(used.get("kind", "?")), seconds, max_step, between])
	_restore_storey_fixture(scene, npcs, home)
	for _i in 20:
		await tree.physics_frame
		player.global_position = home
		player.velocity = Vector3.ZERO
	player.set_admin_noclip(false)
	player.global_position = home
	player.velocity = Vector3.ZERO
	for _i in 8:
		await tree.physics_frame
		if player.global_position.distance_to(home) > .4:
			player.global_position = home
			player.velocity = Vector3.ZERO


func _restore_storey_fixture(scene: Node, npcs: NpcTeammates, home: Vector3) -> void:
	var player: PlayerController3D = scene.player
	var npc: Dictionary = npcs.npcs[0]
	var ladders = scene.get("_ladders")
	if ladders != null:
		ladders.clear()
	var home_level := npcs._level_of(home.y)
	for body in npcs.npcs:
		npcs._drop_crossing(body)
		body["level"] = home_level
		body["at"] = home
		body["path"] = []
		body["ignored"] = false
		body["frozen"] = false
	player.global_position = home
	player.velocity = Vector3.ZERO
	(scene.facility as StreamedFacilityView3D).refresh_at_tracked_player()


func _stand_near_link(nav: StreamedHunterNavigation, foot: Vector2, floor_y: float) -> Dictionary:
	var offsets: Array = [Vector2(2.2, 0.6), Vector2(-2.2, 0.6), Vector2(0.6, 2.2), Vector2(0.6, -2.2),
		Vector2(3.2, 0.0), Vector2(-3.2, 0.0), Vector2(0.0, 3.2), Vector2(0.0, -3.2), Vector2(1.6, 1.6)]
	for offset in offsets:
		var nudge: Vector2 = offset
		var open: Dictionary = nav.nearest_open_position(foot.x + nudge.x, foot.y + nudge.y, .23)
		if not open.has("cell"):
			continue
		var spot := Vector2(float(open["x"]), float(open["y"]))
		var d := spot.distance_to(foot)
		if d >= 1.2 and d <= 4.5:
			return {"at": Vector3(spot.x, floor_y, spot.y)}
	return {}


func _on_link_route(link: Dictionary, from_level: int, at: Vector3, base_y: float) -> bool:
	var best := INF
	for i in 25:
		var p := NpcTeammates.crossing_point(link, from_level, float(i) / 24.0, base_y)
		best = minf(best, at.distance_to(p))
	return best <= .75


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
	_expect(int((state.get("npc_admin", [0]) as Array)[0]) & 1 and bool(state.get("no_target", false)) \
			and not bool(state.get("hunt_target", false)), "freeze / ignore did not reach the NPC's state")
	var picked := remotes.best_target(state.get("position", Vector2.ZERO), {}, int(state.get("depth", 0)))
	_expect(int(picked.get("peer_id", 0)) != id, "a hunter still picks an NPC the admin made them ignore")
	var listed := panel.rows().filter(func(row: Dictionary) -> bool: return int(row["id"]) == id)
	_expect(not listed.is_empty() and String(listed[0]["state"]).contains("IGNORED"),
		"the admin list does not show the ignored NPC")
	scene._admin_world_action("npc", {"op": "target", "id": id})
	for _i in 20:
		await tree.physics_frame
	state = remotes.peer_state(id)
	_expect(bool(state.get("hunt_target", false)) and not bool(state.get("no_target", false)),
		"HUNTERS TARGET did not clear ignore on the published state")
	var npc_pos: Vector2 = state.get("position", Vector2.ZERO)
	var depth := int(state.get("depth", 0))
	var decoy := 42
	remotes._states[decoy] = {"peer_id": decoy, "position": npc_pos + Vector2(4, 0), "depth": depth,
		"received_usec": Time.get_ticks_usec()}
	var origin := npc_pos + Vector2(30, 0)
	var forced := remotes.best_target(origin, {"peer_id": 1, "position": npc_pos + Vector2(6, 0), "depth": depth}, depth)
	_expect(int(forced.get("peer_id", 0)) == id,
		"hunters did not prefer the targeted NPC over a closer runner (%s)" % forced)
	listed = panel.rows().filter(func(row: Dictionary) -> bool: return int(row["id"]) == id)
	_expect(not listed.is_empty() and String(listed[0]["state"]).contains("TARGET") \
			and not String(listed[0]["state"]).contains("IGNORED"),
		"the admin list does not show the targeted NPC")
	remotes._states.erase(decoy)
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
	# a guest admin's request for 500 is not capped per request and the run's total is unlimited: all 500 land
	scene._on_remote_interaction_request(admin, {"what": "admin_world", "action": "npc", "op": "spawn", "count": 500, "admin_ticket": ""})
	_expect(npcs.npcs.size() == 500,
		"a guest admin's request for 500 NPCs added %d, not all 500" % npcs.npcs.size())
	scene._on_remote_interaction_request(admin, {"what": "admin_world", "action": "npc", "op": "remove_all", "admin_ticket": ""})
	Build.deny_admin_for_test = false
	for peer in [admin, plain]:
		RoomState.peers.erase(peer)
		remotes._states.erase(peer)
	panel.queue_free()


## No cap by default: a 40-NPC spawn keeps all 40 with their own ids, the first grid searches are staggered over REPATH (not one
## frame), and the slots past SLOT_RING_SLOTS sit on a wider ring so the group does not stack on one 2.4 m ring.
func _unlimited_spawn(scene: Node, npcs: NpcTeammates) -> void:
	_expect(NpcTeammates.COUNT_LIMIT == 0, "COUNT_LIMIT is not unlimited (0): %d" % NpcTeammates.COUNT_LIMIT)
	var before := npcs.npcs.size()
	var at: Vector3 = (scene.get("player") as Node3D).global_position
	var ids: Array = npcs.spawn(40, at, 70)
	_expect(ids.size() == 40, "a spawn of 40 gave %d NPCs" % ids.size())
	_expect(npcs.npcs.size() == before + 40, "the run holds %d NPCs, wanted %d" % [npcs.npcs.size(), before + 40])
	var phases := {}
	var furthest := 0.0
	for id in ids:
		var npc := npcs.find(int(id))
		var age := float(npc["path_age"])
		phases["%.3f" % age] = true
		_expect(age > 0.0 and age <= NpcTeammates.REPATH, "NPC %d starts its first grid search at %.3f s" % [int(id), age])
		furthest = maxf(furthest, (npc["at"] as Vector3).distance_to(at))
	_expect(phases.size() >= 20, "the first grid searches land on %d distinct phases; they should spread over REPATH" % phases.size())
	_expect(furthest > NpcTeammates.SLOT_RADIUS * 1.5, "40 NPCs stack on one ring (furthest %.1f m)" % furthest)
	_expect(is_equal_approx(NpcTeammates.slot_radius(8), NpcTeammates.SLOT_RADIUS)
		and NpcTeammates.slot_radius(40) > NpcTeammates.slot_radius(8),
		"the slot ring does not stay at SLOT_RADIUS to slot 8 and widen past it")
	for id in ids:
		npcs.remove(int(id))
	_expect(npcs.npcs.size() == before, "removing the 40 left %d NPCs, wanted %d" % [npcs.npcs.size(), before])


## NpcPerfTable against NpcTeammates and against the Budget table committed in docs/NPC_TEAMMATES.md.
func _perf_table() -> void:
	var before := _failures
	_expect(NpcPerfTable.SEND_HZ == NpcTeammates.SEND_HZ,
		"NpcPerfTable.SEND_HZ %s drifted from NpcTeammates.SEND_HZ %s" % [NpcPerfTable.SEND_HZ, NpcTeammates.SEND_HZ])
	_expect(NpcPerfTable.COUNT_LIMIT == NpcTeammates.COUNT_LIMIT,
		"NpcPerfTable.COUNT_LIMIT %s drifted from NpcTeammates.COUNT_LIMIT %s" % [NpcPerfTable.COUNT_LIMIT, NpcTeammates.COUNT_LIMIT])
	_expect(is_equal_approx(NpcPerfTable.REPATH, NpcTeammates.REPATH),
		"NpcPerfTable.REPATH %s drifted from NpcTeammates.REPATH %s" % [NpcPerfTable.REPATH, NpcTeammates.REPATH])
	_expect(NpcPerfTable.SEND_HZ == float(int(NpcPerfTable.SEND_HZ)) and NpcPerfTable.SEND_HZ > 0.0,
		"SEND_HZ %s is not a whole number of packets per second" % NpcPerfTable.SEND_HZ)
	_expect(NpcPerfTable.PACKET_BUDGET > 0 and NpcPerfTable.REPATH > 0.0, "packet budget or REPATH is not positive")
	_expect(NpcPerfTable.NPC_COUNTS == [1, 4, 8, 16, 32, 64], "representative NPC counts drifted from 1, 4, 8, 16, 32, 64")
	_expect(NpcPerfTable.GUEST_COUNTS == [1, 3], "representative guest counts drifted from 1, 3")
	for row in NpcPerfTable.rows():
		var npcs := int(row["npcs"])
		var guests := int(row["guests"])
		var formula := npcs * guests * int(NpcPerfTable.SEND_HZ) * NpcPerfTable.PACKET_BUDGET
		_expect(NpcPerfTable.host_upload_bytes_per_sec(npcs, guests) == formula,
			"%d NPCs x %d guests: helper %s != npc_count * guest_count * SEND_HZ * packet_size (%s)" % [npcs, guests, row["bytes_per_sec"], formula])
		_expect(NpcPerfTable.host_upload_bytes_per_sec(npcs, guests, 100) == npcs * guests * int(NpcPerfTable.SEND_HZ) * 100,
			"%d NPCs x %d guests: helper ignored packet_size" % [npcs, guests])
		_expect(is_equal_approx(float(row["kb_per_sec"]), float(formula) / 1000.0),
			"%d NPCs x %d guests: KB/s %s is not bytes/s / 1000" % [npcs, guests, row["kb_per_sec"]])
		_expect(is_equal_approx(NpcPerfTable.pathfinds_per_sec(npcs), float(npcs) / NpcTeammates.REPATH),
			"%d NPCs: pathfinds/s %s != count / REPATH" % [npcs, NpcPerfTable.pathfinds_per_sec(npcs)])
	var doc := FileAccess.get_file_as_string("res://docs/NPC_TEAMMATES.md")
	var section := _budget_section(doc)
	_expect(not section.is_empty(), "docs/NPC_TEAMMATES.md has no ## Budget section")
	if section.is_empty():
		return
	_expect(section.contains("npc_count * guest_count * SEND_HZ * packet_size"),
		"Budget formula drifted from npc_count * guest_count * SEND_HZ * packet_size")
	_expect(section.contains("npc_count / REPATH"), "Budget lost pathfinds/s = npc_count / REPATH")
	_expect(section.contains("no physics body"), "Budget lost the no-physics-body note")
	var constants := _budget_constants(section)
	var keys := ["SEND_HZ", "PACKET_BUDGET", "COUNT_LIMIT", "REPATH"]
	for key in keys:
		_expect(constants.has(key), "Budget constants line missing %s (wanted SEND_HZ, PACKET_BUDGET, COUNT_LIMIT, REPATH)" % key)
	if constants.has_all(keys):
		_expect(constants.size() == keys.size(), "Budget constants line has extra fields: %s" % [constants.keys()])
		_expect(is_equal_approx(float(constants["SEND_HZ"]), NpcPerfTable.SEND_HZ),
			"doc SEND_HZ=%s drifted from NpcPerfTable %s" % [constants["SEND_HZ"], NpcPerfTable.SEND_HZ])
		_expect(int(constants["PACKET_BUDGET"]) == NpcPerfTable.PACKET_BUDGET,
			"doc PACKET_BUDGET=%s drifted from NpcPerfTable %s" % [constants["PACKET_BUDGET"], NpcPerfTable.PACKET_BUDGET])
		_expect(int(constants["COUNT_LIMIT"]) == NpcPerfTable.COUNT_LIMIT,
			"doc COUNT_LIMIT=%s drifted from NpcPerfTable %s" % [constants["COUNT_LIMIT"], NpcPerfTable.COUNT_LIMIT])
		_expect(is_equal_approx(float(constants["REPATH"]), NpcPerfTable.REPATH),
			"doc REPATH=%s drifted from NpcPerfTable %s" % [constants["REPATH"], NpcPerfTable.REPATH])
	var parsed := _budget_rows(section)
	if not String(parsed["error"]).is_empty():
		_expect(false, String(parsed["error"]))
		return
	var doc_rows: Array = parsed["rows"]
	var expected := {}
	for row in NpcPerfTable.rows():
		expected["%d:%d" % [row["npcs"], row["guests"]]] = row
	_expect(doc_rows.size() == expected.size(),
		"Budget table has %d rows, NpcPerfTable has %d" % [doc_rows.size(), expected.size()])
	var seen := {}
	for doc_row in doc_rows:
		var key := "%d:%d" % [doc_row["npcs"], doc_row["guests"]]
		_expect(expected.has(key), "Budget table row %s is not produced by NpcPerfTable" % key)
		if not expected.has(key):
			continue
		seen[key] = true
		var want: Dictionary = expected[key]
		_expect(int(doc_row["bytes"]) == int(want["bytes_per_sec"]),
			"Budget row %s bytes/s %s drifted from %s" % [key, doc_row["bytes"], want["bytes_per_sec"]])
		_expect(absf(float(doc_row["kb"]) - float(want["kb_per_sec"])) < 0.05,
			"Budget row %s KB/s %s drifted from %s" % [key, doc_row["kb"], want["kb_per_sec"]])
		_expect(is_equal_approx(float(doc_row["pathfinds"]), float(want["pathfinds_per_sec"])),
			"Budget row %s pathfinds/s %s drifted from %s" % [key, doc_row["pathfinds"], want["pathfinds_per_sec"]])
	for key in expected:
		_expect(seen.has(key), "Budget table is missing the %s row" % key)
	if _failures == before:
		var top: int = NpcPerfTable.NPC_COUNTS.back()
		var cap := NpcPerfTable.host_upload_bytes_per_sec(top, 3)
		print("  npc perf  %d NPCs x 3 guests = %.1f KB/s (%d B/s) at %d Hz, %.0f pathfinds/s, packet <= %d B" % [
			top, float(cap) / 1000.0, cap, int(NpcPerfTable.SEND_HZ),
			NpcPerfTable.pathfinds_per_sec(top), NpcPerfTable.PACKET_BUDGET])


func _budget_section(doc: String) -> String:
	var start := doc.find("## Budget")
	if start < 0:
		return ""
	var rest := doc.substr(start)
	var next := rest.find("\n## ")
	return rest.substr(0, next) if next >= 0 else rest


func _budget_constants(section: String) -> Dictionary:
	var line := ""
	for raw in section.split("\n"):
		var stripped := raw.strip_edges()
		if stripped.begins_with("Constants:"):
			line = stripped
			break
	if line.is_empty():
		return {}
	var body := line.trim_prefix("Constants:").trim_suffix(".").strip_edges()
	var out := {}
	for piece in body.split(","):
		var bits := piece.strip_edges().split("=")
		if bits.size() != 2:
			return {}
		out[bits[0].strip_edges()] = bits[1].strip_edges()
	return out


## Data rows of the Budget markdown table. `error` is set when the header or a row is not the committed shape.
func _budget_rows(section: String) -> Dictionary:
	var rows: Array = []
	var saw_header := false
	var heads := ["NPCs", "Guests", "Bytes/s", "KB/s", "Pathfinds/s"]
	for raw in section.split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("|"):
			continue
		var parts: PackedStringArray = line.trim_prefix("|").trim_suffix("|").split("|")
		if parts.size() != heads.size():
			return {"error": "Budget table row has %d cells, wanted %d: %s" % [parts.size(), heads.size(), line], "rows": rows}
		var key := parts[0].strip_edges()
		if key == "NPCs":
			saw_header = true
			for i in heads.size():
				if parts[i].strip_edges() != heads[i]:
					return {"error": "Budget table header drifted: %s" % line, "rows": rows}
			continue
		if key.begins_with(":") or key.begins_with("-"):
			continue
		if not key.is_valid_int() or not parts[1].strip_edges().is_valid_int() or not parts[2].strip_edges().is_valid_int():
			return {"error": "Budget table row is not npc, guest, bytes: %s" % line, "rows": rows}
		if not parts[3].strip_edges().is_valid_float() or not parts[4].strip_edges().is_valid_float():
			return {"error": "Budget table row is not KB/s and pathfinds/s: %s" % line, "rows": rows}
		rows.append({
			"npcs": key.to_int(),
			"guests": parts[1].strip_edges().to_int(),
			"bytes": parts[2].strip_edges().to_int(),
			"kb": parts[3].strip_edges().to_float(),
			"pathfinds": parts[4].strip_edges().to_float(),
		})
	if not saw_header:
		return {"error": "Budget table header missing (NPCs, Guests, Bytes/s, KB/s, Pathfinds/s)", "rows": rows}
	return {"error": "", "rows": rows}


func _finish(scene: Node) -> int:
	scene.get_tree().get_multiplayer().multiplayer_peer = null
	RoomState.online = false
	scene.queue_free()
	return _failures
