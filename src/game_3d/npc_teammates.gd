class_name NpcTeammates
extends Node

## Host-simulated AI teammates (room setting NPC TEAMMATES 0-4, docs/NPC_TEAMMATES.md, KT 2026-10-28). The host runs each NPC
## here and publishes it as a remote runner (RemotePlayers.npc_state), so every peer draws it, lists it as "NPC · name", and the
## host's hunters target it through the same target list as a real runner. Caught, it goes down where it stood (the co-op revive
## window, ReviveDowns); a teammate's Revive Kit hold brings it back, else it stays out like a caught player.
## An NPC keeps with the nearest human runner on its storey (its own slot round them), runs from a chasing hunter, and when its
## runner is on another storey for CATCH_UP_SECONDS it rejoins them there (out of their sight: it does not walk stairs yet).

const ID_BASE := 2_000_000_000   # above any id ENet hands out in practice; RemotePlayers.is_npc()
const MAX_COUNT := 4
## NPC names follow the guest style ("R-4821", GuestNames), seeded by the room so every peer agrees; the player list adds the NPC tag.
const SLOT_RADIUS := 2.4
const FOLLOW_RADIUS := 5.0       # m from the runner before the NPC walks to its slot again
const THREAT_RANGE := 14.0
const CATCH_RANGE := 1.3
const CATCH_UP_SECONDS := 6.0
const REPATH := .5
const SEND_HZ := 12.0            # below a player's 20: an NPC's packets are the room's budget (docs/NPC_TEAMMATES.md)
const GRACE := 4.0               # s after a revive before a hunter may take it again

var scene: Node
var npcs: Array = []             # {id, name, at: Vector3, level, facing, path: Array, path_age, clip, down, out, grace, away}
var _send_clock := 0.0
var _seq := 0


func setup(p_scene: Node, count: int) -> void:
	scene = p_scene
	npcs.clear()
	var spawn: Vector3 = (scene.get("player") as Node3D).global_position
	for i in clampi(count, 0, MAX_COUNT):
		var angle := float(i + 1) * 2.39996
		npcs.append({"id": ID_BASE + i, "name": GuestNames.from_seed(RoomState.run_seed() + i), "at": spawn + Vector3(cos(angle), 0.0, sin(angle)) * SLOT_RADIUS,
			"level": _level_of(spawn.y), "facing": 0.0, "path": [], "path_age": 99.0, "clip": "idle", "down": false,
			"out": false, "grace": 0.0, "away": 0.0, "slot": i + 1})


func _physics_process(delta: float) -> void:
	if scene == null or npcs.is_empty() or not RoomState.online or not RoomState.is_host:
		return
	for npc in npcs:
		_think(npc, delta)
	_send_clock += delta
	if _send_clock >= 1.0 / SEND_HZ:
		_send_clock = 0.0
		var remotes: Node = scene.get("_remotes")
		if remotes != null and remotes.has_method("npc_state"):
			for npc in npcs:
				remotes.call("npc_state", int(npc["id"]), state_of(npc))


## The NPC as a runner state packet: the fields RemotePlayers, the player list and the hunters read.
func state_of(npc: Dictionary) -> Dictionary:
	_seq += 1
	var at: Vector3 = npc["at"]
	var gone := bool(npc["down"]) or bool(npc["out"])
	return {"at": at, "position": Vector2(at.x, at.z), "facing_y": float(npc["facing"]), "clip": String(npc["clip"]),
		"depth": -int(npc["level"]), "display_name": String(npc["name"]), "npc": true, "seq": _seq,
		"sent_ms": Time.get_ticks_msec(), "hidden": false, "visible": not gone, "spectating": gone, "game_over": gone,
		"capture_immune": float(npc["grace"]) > 0.0, "noise": .3 if String(npc["clip"]) == "run" else .1,
		"player_skin": "mannequin", "skin": "", "flashlight_on": false, "in_safe_zone": false}


## A hunter's capture reached NPC `id` (RemotePlayers.npc_captured): down where it stands.
func down(id: int) -> void:
	for npc in npcs:
		if int(npc["id"]) == id and not bool(npc["down"]) and not bool(npc["out"]) and float(npc["grace"]) <= 0.0:
			npc["down"] = true
			npc["path"] = []
			scene.call("_host_record_down", id, npc["at"], -int(npc["level"]))


func is_down(id: int) -> bool:
	for npc in npcs:
		if int(npc["id"]) == id:
			return bool(npc["down"])
	return false


## The host published a revive of `id` (stream_revived): back on its feet with a short grace.
func revived(id: int) -> void:
	for npc in npcs:
		if int(npc["id"]) == id:
			npc["down"] = false
			npc["out"] = false
			npc["grace"] = GRACE


func _think(npc: Dictionary, delta: float) -> void:
	npc["grace"] = maxf(0.0, float(npc["grace"]) - delta)
	if bool(npc["out"]):
		return
	if bool(npc["down"]):
		npc["clip"] = "idle"
		var downs: ReviveDowns = scene.get("world_state").downs
		if not downs.downs.has(int(npc["id"])):
			npc["out"] = true   # the window ran out: out of the run, like a caught player
		return
	var at: Vector3 = npc["at"]
	var hunter := _nearest_hunter(npc)
	if not hunter.is_empty() and float(hunter["dist"]) < CATCH_RANGE and String(hunter["state"]) == "CHASE":
		down(int(npc["id"]))
		return
	var nav := _nav(int(npc["level"]))
	var leader := _leader(npc)
	if leader.is_empty() or nav == null:
		npc["clip"] = "idle"
		return
	var leader_at: Vector3 = leader["at"]
	if int(leader["level"]) != int(npc["level"]):
		npc["away"] = float(npc["away"]) + delta
		npc["clip"] = "idle"
		if float(npc["away"]) >= CATCH_UP_SECONDS:
			_rejoin(npc, leader_at, int(leader["level"]))
		return
	npc["away"] = 0.0
	var here := Vector2(at.x, at.z)
	var goal := Vector2.INF
	var running := false
	if not hunter.is_empty() and float(hunter["dist"]) < THREAT_RANGE and String(hunter["state"]) == "CHASE":
		var away: Vector2 = here - (hunter["pos"] as Vector2)
		goal = here + (away.normalized() if away.length() > .1 else Vector2.RIGHT) * 12.0
		running = true
	elif here.distance_to(Vector2(leader_at.x, leader_at.z)) > FOLLOW_RADIUS or not (npc["path"] as Array).is_empty():
		var angle := float(npc["slot"]) * 2.39996
		goal = Vector2(leader_at.x, leader_at.z) + Vector2(cos(angle), sin(angle)) * SLOT_RADIUS
	if goal == Vector2.INF:
		npc["clip"] = "idle"
		return
	npc["path_age"] = float(npc["path_age"]) + delta
	if float(npc["path_age"]) >= REPATH:
		npc["path_age"] = 0.0
		var open: Dictionary = nav.nearest_open_position(goal.x, goal.y, .23)
		var to: Vector2i = open.get("cell", Vector2i(floori(goal.x), floori(goal.y)))
		npc["path"] = nav.find_path(Vector2i(floori(at.x), floori(at.z)), to)
		if not (npc["path"] as Array).is_empty():
			(npc["path"] as Array).pop_front()   # the cell it stands in
	var path: Array = npc["path"]
	if path.is_empty():
		npc["clip"] = "idle"
		return
	var next_cell: Vector2i = path[0]
	var target := Vector2(next_cell.x + .5, next_cell.y + .5)
	var speed := (GameConfig.PLAYER_SPRINT_SPEED if running else GameConfig.PLAYER_WALK_SPEED) / GameConfig.TILE_SIZE
	var step := target - here
	if step.length() <= speed * delta:
		path.pop_front()
		here = target
	else:
		here += step.normalized() * speed * delta
		npc["facing"] = atan2(-step.x, -step.y)
	npc["at"] = Vector3(here.x, _floor_y(int(npc["level"])), here.y)
	npc["clip"] = "run" if running else "walk"


## Human runners (the host and every guest; never another NPC) with a fresh state: the nearest on the NPC's storey, else the
## nearest anywhere.
func _leader(npc: Dictionary) -> Dictionary:
	var at: Vector3 = npc["at"]
	var runners: Array = []
	var player: Node3D = scene.get("player")
	if player != null and not GameState.game_over:
		runners.append({"at": player.global_position, "level": _level_of(player.global_position.y)})
	var remotes: Node = scene.get("_remotes")
	if remotes != null:
		var states: Dictionary = remotes.get("_states")
		for id in states:
			var state: Dictionary = states[id]
			if bool(state.get("npc", false)) or bool(state.get("spectating", false)) or not state.get("at") is Vector3:
				continue
			runners.append({"at": state["at"], "level": -int(state.get("depth", 0))})
	var best := {}
	var best_d := INF
	for runner in runners:
		var d := (runner["at"] as Vector3).distance_to(at) + (0.0 if int(runner["level"]) == int(npc["level"]) else 10000.0)
		if d < best_d:
			best_d = d
			best = runner
	return best


func _nearest_hunter(npc: Dictionary) -> Dictionary:
	var at: Vector3 = npc["at"]
	var best := {}
	var views: Dictionary = scene.get("_hunter_views")
	var levels: Dictionary = scene.get("_hunter_levels")
	for key in views:
		var view: HunterView3D = views[key]
		if view == null or not is_instance_valid(view) or view.brain == null:
			continue
		if int(levels.get(key, 999999)) != int(npc["level"]):
			continue
		var brain: HunterBrain = view.brain
		var d := brain.position.distance_to(Vector2(at.x, at.z))
		if best.is_empty() or d < float(best["dist"]):
			best = {"dist": d, "pos": brain.position, "state": HunterBrain.State.keys()[brain.state]}
	return best


func _rejoin(npc: Dictionary, leader_at: Vector3, level: int) -> void:
	var nav := _nav(level)
	var spot := Vector2(leader_at.x, leader_at.z) + Vector2(cos(float(npc["slot"]) * 2.39996), sin(float(npc["slot"]) * 2.39996)) * SLOT_RADIUS
	if nav != null:
		var open: Dictionary = nav.nearest_open_position(spot.x, spot.y, .23)
		if open.has("cell"):
			spot = Vector2((open["cell"] as Vector2i).x + .5, (open["cell"] as Vector2i).y + .5)
	npc["level"] = level
	npc["at"] = Vector3(spot.x, _floor_y(level), spot.y)
	npc["path"] = []
	npc["away"] = 0.0


func _nav(level: int) -> StreamedHunterNavigation:
	var navs: Dictionary = scene.get("_navigations")
	return navs.get(level) as StreamedHunterNavigation if navs != null else null


func _floor_y(level: int) -> float:
	var facility: Node3D = scene.get("facility")
	return facility.global_position.y + float(level) * StreamedFacilityView3D.LEVEL_HEIGHT


func _level_of(y: float) -> int:
	var facility: Node3D = scene.get("facility")
	return roundi((y - facility.global_position.y) / StreamedFacilityView3D.LEVEL_HEIGHT)
