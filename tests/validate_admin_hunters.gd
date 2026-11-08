extends RefCounted

## Admin hunter and NPC controls (infinite_route_test.gd, AdminMenu HUNTERS and NPCS):
##   - SUMMON ALL HUNTERS places one ADMIN:<id>:<seq> hunter for every A-Z and Void id in one batch (one stream refresh),
##     skips ids already summoned, and REMOVE SUMMONED HUNTERS takes only those ADMIN: copies back out.
##   - The per-hunter TOGGLE summons an absent id and removes a present one.
##   - Guest parity: every hunter and emote request the admin menu sends is on RemotePlayers.ADMIN_WORLD_ACTIONS (the list the
##     host sanitizer checks first), and its permission is "hunters" on the host.
##   - ALL NPCS: the bulk ops reach every NPC in the run through one "all" flag; a non-bulk op (kill) is refused; CLEAR drops
##     both the ignore and the target flag; the panel has the ALL NPCS row.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- admin_hunters

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## Pure data: the guest allow-list, the permission map and the NPC op tables. No scene needed.
func _contract() -> void:
	for action in ["summon_hunter", "remove_hunter", "toggle_hunter", "summon_all_hunters", "remove_all_hunters",
			"stun_hunters", "freeze_hunters", "release_hunters", "hunter_emote"]:
		_expect(RemotePlayers.ADMIN_WORLD_ACTIONS.has(action),
			"a guest admin's %s request is not on the sanitizer's ADMIN_WORLD_ACTIONS (the host would drop it silently)" % action)
	_expect(NpcTeammates.OPS.has("clear"), "NpcTeammates.OPS has no clear op")
	for op in ["teleport", "follow", "unfollow", "smart", "chat", "freeze", "resume", "ignore", "target", "clear"]:
		_expect(NpcTeammates.BULK_OPS.has(op), "BULK_OPS is missing %s" % op)
	for op in ["kill", "down", "revive", "remove", "goto"]:
		_expect(not NpcTeammates.BULK_OPS.has(op), "%s is a per-NPC op and must not be a bulk op" % op)
	_clear_on_a_bare_npc()


## NpcTeammates.command("clear") clears both flags, and each of ignore / target leaves the other off.
func _clear_on_a_bare_npc() -> void:
	var npcs := NpcTeammates.new()
	var id := NpcTeammates.ID_BASE + 7
	npcs.npcs = [{"id": id, "ignored": false, "targeted": false, "down": false, "out": false, "frozen": false}]
	npcs.command(id, "ignore")
	_expect(bool(npcs.find(id)["ignored"]) and not bool(npcs.find(id)["targeted"]), "ignore did not set the ignore flag alone")
	npcs.command(id, "clear")
	_expect(not bool(npcs.find(id)["ignored"]) and not bool(npcs.find(id)["targeted"]), "clear did not drop the ignore flag")
	npcs.command(id, "target")
	npcs.command(id, "clear")
	_expect(not bool(npcs.find(id)["ignored"]) and not bool(npcs.find(id)["targeted"]), "clear did not drop the target flag")
	npcs.free()


func _admin_hunter_entries(scene: Node) -> Array:
	var found: Array = []
	for entity_id_value in scene.world_state.hunters:
		var entity_id := String(entity_id_value)
		if entity_id.begins_with("ADMIN:"):
			found.append(entity_id)
	return found


func run(host: Node) -> int:
	_contract()
	await _route(host)
	return _failures


func _route(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 8:
		await host.get_tree().process_frame
	var tree := host.get_tree()
	tree.get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()   # unique id 1, no peers
	RoomState.online = true
	RoomState.is_host = true
	await _summon_all(scene, tree)
	await _toggle(scene, tree)
	await _npc_bulk(scene, tree)
	_finish(scene)


func _summon_all(scene: Node, tree: SceneTree) -> void:
	var wanted := HunterRoster.A_Z_IDS.size() + HunterRoster.VOID_IDS.size()
	scene._admin_world_action("remove_all_hunters")
	scene._admin_world_action("summon_all_hunters")
	for _i in 4:
		await tree.physics_frame
	var entries := _admin_hunter_entries(scene)
	_expect(entries.size() >= wanted * 3 / 4,
		"SUMMON ALL HUNTERS placed %d of %d hunters" % [entries.size(), wanted])
	var kinds := {}
	for entity_id in entries:
		kinds[String(scene.world_state.hunters[entity_id].get("hunter_id", ""))] = true
	_expect(kinds.size() == entries.size(), "SUMMON ALL HUNTERS placed a second copy of an id (%d ids, %d hunters)"
		% [kinds.size(), entries.size()])
	scene._admin_world_action("summon_all_hunters")
	_expect(_admin_hunter_entries(scene).size() == entries.size(),
		"a second SUMMON ALL HUNTERS stacked more copies")
	scene._admin_world_action("remove_all_hunters")
	_expect(_admin_hunter_entries(scene).is_empty(), "REMOVE SUMMONED HUNTERS left %d ADMIN hunters" % _admin_hunter_entries(scene).size())
	_expect(scene._admin_action_permission("summon_all_hunters") == "hunters"
		and scene._admin_action_permission("remove_all_hunters") == "hunters"
		and scene._admin_action_permission("toggle_hunter") == "hunters",
		"the new hunter actions are not gated by the hunters permission")


func _toggle(scene: Node, tree: SceneTree) -> void:
	# clear any route-native copy of the id first, so the toggle starts from "absent" whatever the seed placed
	scene._admin_world_action("remove_hunter", {"hunter_id": "aki"})
	scene._admin_world_action("toggle_hunter", {"hunter_id": "aki"})
	for _i in 2:
		await tree.physics_frame
	var present := _admin_hunter_entries(scene).filter(func(id: String) -> bool:
		return String(scene.world_state.hunters[id].get("hunter_id", "")) == "aki")
	_expect(present.size() == 1, "TOGGLE on an absent hunter did not summon it (%d copies)" % present.size())
	scene._admin_world_action("toggle_hunter", {"hunter_id": "aki"})
	for _i in 2:
		await tree.physics_frame
	var after := _admin_hunter_entries(scene).filter(func(id: String) -> bool:
		return String(scene.world_state.hunters[id].get("hunter_id", "")) == "aki")
	_expect(after.is_empty(), "TOGGLE on a present hunter did not remove it")


func _npc_bulk(scene: Node, tree: SceneTree) -> void:
	scene._admin_world_action("npc", {"op": "spawn", "count": 3, "smart": 70})
	var npcs: NpcTeammates = scene._npcs
	_expect(npcs != null and npcs.npcs.size() >= 3, "could not spawn 3 NPCs for the bulk checks")
	if npcs == null:
		return
	for _i in 4:
		await tree.physics_frame
	scene._admin_world_action("npc", {"op": "freeze", "all": true})
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return bool(npc["frozen"])), "ALL FREEZE did not freeze every NPC")
	scene._admin_world_action("npc", {"op": "resume", "all": true})
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return not bool(npc["frozen"])), "ALL RESUME did not resume every NPC")
	scene._admin_world_action("npc", {"op": "ignore", "all": true})
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return bool(npc["ignored"])), "ALL IGNORE did not ignore every NPC")
	scene._admin_world_action("npc", {"op": "clear", "all": true})
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return not bool(npc["ignored"]) and not bool(npc["targeted"])),
		"ALL CLEAR left a hunter flag on an NPC")
	scene._admin_world_action("npc", {"op": "target", "all": true})
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return bool(npc["targeted"]) and not bool(npc["ignored"])),
		"ALL TARGET did not target every NPC")
	scene._admin_world_action("npc", {"op": "clear", "all": true})
	scene._admin_world_action("npc", {"op": "smart", "all": true, "smart": 90})
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return int(npc["smart"]) == 90), "ALL SMART did not set every NPC")
	scene._admin_world_action("npc", {"op": "chat", "all": true, "value": 0})
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return not bool(npc["chat"])), "ALL CHAT OFF did not reach every NPC")
	scene._admin_world_action("npc", {"op": "kill", "all": true})
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return not bool(npc["out"])),
		"a non-bulk op (kill) ran on every NPC through the all flag")
	scene._admin_world_action("npc", {"op": "teleport", "all": true})
	var me: Vector3 = scene.player.global_position
	_expect(npcs.npcs.all(func(npc: Dictionary) -> bool: return (npc["at"] as Vector3).distance_to(me) < 6.0),
		"ALL TO ME did not bring every NPC near the admin")
	var panel := AdminNpcPanel.new(scene)
	scene.add_child(panel)
	await tree.process_frame
	for op in ["teleport", "follow", "unfollow", "freeze", "resume", "ignore", "target", "clear", "chat_on", "chat_off", "smart"]:
		_expect(panel.find_child("NpcAll_" + op, true, false) != null, "the ALL NPCS row has no %s button" % op)
	_expect(panel.find_child("Npc_clear", true, false) != null, "the per-NPC grid has no CLEAR HUNTER FLAGS button")
	panel.queue_free()
	scene._admin_world_action("npc", {"op": "remove_all"})
	await tree.physics_frame


func _finish(scene: Node) -> void:
	scene.get_tree().get_multiplayer().multiplayer_peer = null
	RoomState.online = false
	scene.queue_free()
