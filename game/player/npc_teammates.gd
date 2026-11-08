class_name NpcTeammates
extends Node

## Host-simulated AI teammates (admin/dev room setting NPC TEAMMATES, unlimited by default, docs/NPC_TEAMMATES.md). The host runs each NPC
## here and publishes it as a remote runner (RemotePlayers.npc_state), so every peer draws it, lists it as "NPC · name", and the
## host's hunters target it through the same target list as a real runner. Caught, it goes down where it stood (the co-op revive
## window, ReviveDowns); a teammate's Revive Kit hold brings it back, else it stays out like a caught player.
## An NPC keeps with the nearest human runner on its storey (its own slot round them), runs from a chasing hunter, and when its
## runner is on another storey it walks to a stair, spiral, ladder or ramp and crosses it (it does not teleport).

const ID_BASE := 2_000_000_000   # above any id ENet hands out in practice; RemotePlayers.is_npc()
## Guest admin NPC ids are clamped to ID_BASE .. ID_BASE + ID_SPAN (far beyond any run's spawn count).
const ID_SPAN := 1_000_000_000
## How many NPCs the host runs at once. 0 = unlimited (the default); a positive value caps the run's total.
const COUNT_LIMIT := 0
## NPC names follow the guest style ("R-4821", GuestNames), seeded by the room so every peer agrees; the player list adds the NPC tag.
const SLOT_RADIUS := 2.4
## Slots past SLOT_RING_SLOTS sit on a wider ring (the radius grows with the square root of the slot), so a big group spreads
## out instead of stacking on one 2.4 m ring. Slots 1 to 8 keep the original ring.
const SLOT_RING_SLOTS := 8.0
## Each NPC's first grid search lands at its own phase inside REPATH (slot * PATH_STAGGER, mod REPATH), so a batch does not
## pathfind on one physics frame and then stay in lockstep.
const PATH_STAGGER := .137
const FOLLOW_RADIUS := 5.0       # m from the runner before the NPC walks to its slot again
const THREAT_RANGE := 14.0
const CATCH_RANGE := 1.3
const REPATH := .5
## Another storey: search this many chunks out for a stair, spiral, ladder or ramp that steps toward the runner, then walk
## onto it. The crossing itself follows the link (a stair/spiral path, a ramp slope, or a ladder shaft), the same records
## hunters use (LadderTraffic), at the NPC's walk speed, so the body moves every frame instead of appearing at the top.
const LINK_SEARCH_CHUNKS := 2
const LINK_MOUNT := 2.4
const STOREY_REPLAN := 1.5
const STOREY_KINDS := ["stairs", "spiral", "ladder", "ramp"]
const SEND_HZ := 12.0            # below a player's 20: an NPC's packets are the room's budget (docs/NPC_TEAMMATES.md)
const GRACE := 4.0
## Turning like a person (as the playtest bots): the heading eases toward the path over HEADING_SMOOTH s and the
## body yaw follows through a critically damped spring capped at TURN_RATE, so guests never see an NPC snap or dither.
const HEADING_SMOOTH := .3
const TURN_SPRING := 60.0
const TURN_RATE := 5.0          # rad/s
## Admin control (AdminMenu "NPCS"): spawn mid-run, remove, and per NPC: teleport to / go to / follow the admin,
## smartness, chat, freeze, hunters ignore it or lock onto it, down / revive / kill. The host applies every command (a guest
## admin's arrive as requests the host checks first, _accept_stream_admin) and the flags ride the NPC's state, so every peer
## lists the same. Ignore and target clear each other: ignore drops the NPC from the hunt, target makes hunters on its floor
## prefer it over every other runner.
const OPS := ["teleport", "goto", "follow", "unfollow", "smart", "chat", "freeze", "resume", "ignore", "target", "clear",
	"down", "revive", "kill", "remove"]
## ALL NPCS (AdminNpcPanel, admin_world "npc" with "all": true): the ops that make sense on every NPC at once. Down, revive,
## kill, goto and remove stay per NPC (each needs one NPC's own state or point).
const BULK_OPS := ["teleport", "follow", "unfollow", "smart", "chat", "freeze", "resume", "ignore", "target", "clear"]
const CHAT_COOLDOWN := 30.0     # s between one NPC's lines

var scene: Node
var npcs: Array = []             # {id, name, at: Vector3, level, facing, path: Array, path_age, clip, down, out, grace, away}
var _send_clock := 0.0
var _seq := 0
var _next := 0                   # the next NPC's index (ids and names are never reused within a run)


func setup(p_scene: Node, count: int) -> void:
	scene = p_scene
	npcs.clear()
	_next = 0
	spawn(count, (scene.get("player") as Node3D).global_position)


## `count` more NPCs round `at` (each in its own slot); their ids. COUNT_LIMIT caps the run's total when it is set (0 = unlimited).
func spawn(count: int, at: Vector3, smart: int = 70) -> Array:
	var ids := []
	var more := maxi(count, 0)
	if COUNT_LIMIT > 0:
		more = mini(more, maxi(COUNT_LIMIT - npcs.size(), 0))
	for _i in more:
		var slot := _next + 1
		var angle := float(slot) * 2.39996
		var ring := slot_radius(slot) * (0.0 if count == 1 else 1.0)
		var phase := fmod(float(slot) * PATH_STAGGER, REPATH)
		npcs.append({"id": ID_BASE + _next, "name": GuestNames.from_seed(RoomState.run_seed() + _next),
			"at": at + Vector3(cos(angle), 0.0, sin(angle)) * ring,
			"level": _level_of(at.y), "facing": 0.0, "path": [], "path_age": REPATH - phase, "clip": "idle", "down": false,
			"out": false, "grace": 0.0, "away": 0.0, "slot": slot, "smart": clampi(smart, 0, 100), "chat": true,
			"frozen": false, "ignored": false, "targeted": false, "follow_peer": 0, "goto": null, "said_at": -100.0})
		ids.append(ID_BASE + _next)
		_next += 1
	return ids


## A requested NPC count kept in range: never below 0, and never above COUNT_LIMIT when that is set.
static func clamp_count(value: int) -> int:
	var low := maxi(value, 0)
	return low if COUNT_LIMIT <= 0 else mini(low, COUNT_LIMIT)


## Ring radius of slot `slot` round its runner: SLOT_RADIUS up to SLOT_RING_SLOTS, wider past it.
static func slot_radius(slot: int) -> float:
	return SLOT_RADIUS * maxf(1.0, sqrt(float(slot) / SLOT_RING_SLOTS))


func find(id: int) -> Dictionary:
	for npc in npcs:
		if int(npc["id"]) == id:
			return npc
	return {}


## Gone from the run: no more state packets (peers drop the body when its state goes stale) and no revive window.
func remove(id: int) -> bool:
	var npc := find(id)
	if npc.is_empty():
		return false
	_drop_crossing(npc)
	npcs.erase(npc)
	var downs: ReviveDowns = scene.get("world_state").downs
	downs.clear(id)
	var remotes: Node = scene.get("_remotes")
	if remotes != null and remotes.has_method("forget_npc"):
		remotes.call("forget_npc", id)
	return true


## One admin command on NPC `id` (see OPS); `at` is the admin's position (teleport, go to), `peer` the admin (follow).
func command(id: int, op: String, at: Vector3 = Vector3.INF, peer: int = 0, value: int = 0) -> bool:
	var npc := find(id)
	if npc.is_empty() or not op in OPS:
		return false
	match op:
		"teleport":
			if at == Vector3.INF:
				return false
			_drop_crossing(npc)
			var spot := _open_near(at, int(npc["slot"]), _level_of(at.y))
			npc["level"] = _level_of(at.y)
			npc["at"] = spot
			npc["path"] = []
		"goto":
			if at == Vector3.INF:
				return false
			_drop_crossing(npc)
			npc["goto"] = Vector2(at.x, at.z)
			npc["follow_peer"] = 0
			npc["path"] = []
		"follow":
			npc["follow_peer"] = peer
			npc["goto"] = null
		"unfollow":
			npc["follow_peer"] = 0
		"smart":
			npc["smart"] = clampi(value, 0, 100)
		"chat":
			npc["chat"] = value != 0
		"freeze":
			npc["frozen"] = true
			npc["path"] = []
			_drop_crossing(npc)
		"resume":
			npc["frozen"] = false
		"ignore":
			npc["ignored"] = true
			npc["targeted"] = false
		"target":
			npc["ignored"] = false
			npc["targeted"] = true
		"clear":
			# back to the normal hunt: neither ignored nor preferred
			npc["ignored"] = false
			npc["targeted"] = false
		"down":
			npc["grace"] = 0.0
			down(id)
		"revive":
			var downs: ReviveDowns = scene.get("world_state").downs
			downs.clear(id)
			revived(id)
		"kill":
			npc["down"] = false
			npc["out"] = true
			_drop_crossing(npc)
			var downs: ReviveDowns = scene.get("world_state").downs
			downs.clear(id)
		"remove":
			return remove(id)
	return true


func _open_near(at: Vector3, slot: int, level: int) -> Vector3:
	var spot := Vector2(at.x, at.z) + Vector2(cos(float(slot) * 2.39996), sin(float(slot) * 2.39996)) * 1.5
	var nav := _nav(level)
	if nav != null:
		var open: Dictionary = nav.nearest_open_position(spot.x, spot.y, .23)
		if open.has("cell"):
			spot = Vector2((open["cell"] as Vector2i).x + .5, (open["cell"] as Vector2i).y + .5)
	return Vector3(spot.x, _floor_y(level), spot.y)


func _physics_process(delta: float) -> void:
	# co-op: the host simulates; solo (an admin's spawn) runs them locally
	if scene == null or npcs.is_empty() or (RoomState.online and not RoomState.is_host):
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
		"sent_ms": Time.get_ticks_msec(), "visible": not gone, "spectating": gone, "game_over": gone,
		# what a runner moving like this gives the hunters to sense: footstep noise as a player's (GameConfig.NOISE_*), and a
		# torch on, as players carry one (hunters see a lit runner further; a dark, near-silent NPC went unnoticed)
		"capture_immune": float(npc["grace"]) > 0.0, "noise": _noise(String(npc["clip"])) if not gone else 0.0,
		"facing": Vector2(-sin(float(npc["facing"])), -cos(float(npc["facing"]))),
		# hidden, in_safe_zone, skin are left out: their defaults (false, false, the mannequin) are what an NPC is
		"flashlight_on": not gone,
		# admin flags, for every peer's admin list. no_target keeps the hunters off it; hunt_target is the preferred
		# pool on its floor (RemotePlayers.best_target). The two flags are mutually exclusive (command ignore / target).
		# npc_admin: [frozen | chat << 1, smartness, followed peer] (one key: the packet stays in its budget)
		"no_target": bool(npc.get("ignored", false)),
		"hunt_target": bool(npc.get("targeted", false)),
		"npc_admin": [(1 if bool(npc.get("frozen", false)) else 0) | (2 if bool(npc.get("chat", true)) else 0),
			int(npc.get("smart", 70)), int(npc.get("follow_peer", 0))]}


## A hunter's capture reached NPC `id` (RemotePlayers.npc_captured): down where it stands.
func down(id: int) -> void:
	for npc in npcs:
		if int(npc["id"]) == id and not bool(npc["down"]) and not bool(npc["out"]) and float(npc["grace"]) <= 0.0:
			npc["down"] = true
			npc["path"] = []
			_drop_crossing(npc)
			scene.call("_host_record_down", id, npc["at"], -int(npc["level"]))


static func _noise(clip: String) -> float:
	match clip:
		"run":
			return GameConfig.NOISE_SPRINT
		"walk", "climb":
			return GameConfig.NOISE_WALK
	return 0.0


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
	if not hunter.is_empty() and float(hunter["dist"]) < CATCH_RANGE and String(hunter["state"]) == "CHASE" \
			and not bool(npc.get("ignored", false)):
		down(int(npc["id"]))
		return
	if bool(npc.get("frozen", false)):
		npc["clip"] = "idle"
		return
	_talk(npc, hunter)
	# a crossing already underway finishes even when this floor's nav drops out from under it
	if _tick_crossing(npc, delta):
		return
	var nav := _nav(int(npc["level"]))
	var leader := _leader(npc)
	if npc.get("goto") is Vector2:
		# go to a point once (an admin's "go to me"), then stand there
		var dest: Vector2 = npc["goto"]
		if Vector2(at.x, at.z).distance_to(dest) < 1.5:
			npc["goto"] = null
		else:
			leader = {"at": Vector3(dest.x, at.y, dest.y), "level": int(npc["level"])}
	if leader.is_empty() or nav == null:
		npc["clip"] = "idle"
		return
	var leader_at: Vector3 = leader["at"]
	var here := Vector2(at.x, at.z)
	# smarter NPCs notice a chasing hunter sooner (smartness 0: half the range, 100: one and a half)
	var threat_range := THREAT_RANGE * (.5 + float(npc.get("smart", 70)) / 100.0)
	var flee := Vector2.INF
	if not hunter.is_empty() and float(hunter["dist"]) < threat_range and String(hunter["state"]) == "CHASE" \
			and not bool(npc.get("ignored", false)):
		var away: Vector2 = here - (hunter["pos"] as Vector2)
		flee = here + (away.normalized() if away.length() > .1 else Vector2.RIGHT) * 12.0
	if int(leader["level"]) != int(npc["level"]):
		if flee != Vector2.INF:
			_walk_toward(npc, flee, delta, true)
		else:
			_approach_storey(npc, int(leader["level"]), delta)
		return
	npc["away"] = 0.0
	npc["storey"] = {}
	var goal := Vector2.INF
	var running := false
	var ring := slot_radius(int(npc["slot"]))
	if flee != Vector2.INF:
		goal = flee
		running = true
	elif here.distance_to(Vector2(leader_at.x, leader_at.z)) > FOLLOW_RADIUS + ring - SLOT_RADIUS \
			or not (npc["path"] as Array).is_empty():
		var angle := float(npc["slot"]) * 2.39996
		goal = Vector2(leader_at.x, leader_at.z) + Vector2(cos(angle), sin(angle)) * ring
	if goal == Vector2.INF:
		npc["clip"] = "idle"
		return
	_walk_toward(npc, goal, delta, running)


## One grid step toward `goal` on this storey (the same path the same-floor follow uses).
func _walk_toward(npc: Dictionary, goal: Vector2, delta: float, running: bool) -> void:
	var at: Vector3 = npc["at"]
	var here := Vector2(at.x, at.z)
	var nav := _nav(int(npc["level"]))
	if nav == null:
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
	var speed := _move_speed(running)
	var step := target - here
	var heading: Vector2 = npc.get("heading", step.normalized())
	heading = heading.lerp(step.normalized(), 1.0 - exp(-delta / HEADING_SMOOTH)).normalized() if step.length() > .01 else heading
	npc["heading"] = heading
	if step.length() <= speed * delta:
		path.pop_front()
		here = target
	else:
		here += step.normalized() * speed * delta
	_turn(npc, atan2(-heading.x, -heading.y), delta)
	npc["at"] = Vector3(here.x, _floor_y(int(npc["level"])), here.y)
	npc["clip"] = "run" if running else "walk"


static func _move_speed(running: bool) -> float:
	return (GameConfig.PLAYER_SPRINT_SPEED if running else GameConfig.PLAYER_WALK_SPEED) / GameConfig.TILE_SIZE


## Walk to the nearest stair, spiral, ladder or ramp that steps toward `target_level`, then cross it.
func _approach_storey(npc: Dictionary, target_level: int, delta: float) -> void:
	var link := _planned_link(npc, target_level, delta)
	if link.is_empty():
		npc["clip"] = "idle"
		return
	var foot := LadderTraffic.ladder_point(link, int(npc["level"]))
	var at: Vector3 = npc["at"]
	if Vector2(at.x, at.z).distance_to(foot) <= LINK_MOUNT:
		if _begin_crossing(npc, link):
			_tick_crossing(npc, delta)
		else:
			npc["clip"] = "idle"   # someone is already on this ladder
			npc["path"] = []
		return
	_walk_toward(npc, foot, delta, false)


func _planned_link(npc: Dictionary, target_level: int, delta: float) -> Dictionary:
	var level := int(npc["level"])
	var want := level + signi(target_level - level)
	var age := float(npc.get("storey_age", 99.0)) + delta
	npc["storey_age"] = age
	var plan: Dictionary = npc["storey"] if npc.get("storey") is Dictionary else {}
	var cached: Dictionary = plan["link"] if plan.get("link") is Dictionary else {}
	if not cached.is_empty() and int(plan.get("want", 999999)) == want and age < STOREY_REPLAN:
		return cached
	var link := _storey_link(level, Vector2((npc["at"] as Vector3).x, (npc["at"] as Vector3).z), target_level)
	if String(link.get("id", "")) != String(cached.get("id", "")):
		npc["path"] = []
		npc["path_age"] = 99.0
	npc["storey"] = {"link": link, "want": want}
	npc["storey_age"] = 0.0
	return link


## The nearest link on `level` whose other end is closer to `target_level` than staying put, and that the nav can
## reach (or that the NPC is already standing on). Searches the near chunks first.
func _storey_link(level: int, near: Vector2, target_level: int) -> Dictionary:
	if target_level == level:
		return {}
	var close := _first_reachable(level, near, _collect_links(level, near, target_level, 1))
	if not close.is_empty():
		return close
	return _first_reachable(level, near, _collect_links(level, near, target_level, LINK_SEARCH_CHUNKS))


func _collect_links(level: int, near: Vector2, target_level: int, reach: int) -> Array:
	var generator := _generator()
	if generator == null or not generator.has_method("vertical_links"):
		return []
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cx := floori(near.x / float(size))
	var cz := floori(near.y / float(size))
	var found: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var coord := Vector3i(cx + dx, level, cz + dz)
			if not generator.is_chunk_allowed(coord):
				continue
			for link_value in generator.vertical_links(coord):
				var link: Dictionary = link_value
				if not STOREY_KINDS.has(String(link.get("kind", ""))):
					continue
				if LevelLink.cell_on(link, level) == Vector2i(-1, -1):
					continue
				var other := int(LevelLink.other_end(link, level)["level"])
				if absi(other - target_level) >= absi(level - target_level):
					continue
				var at := LadderTraffic.ladder_point(link, level)
				found.append({"link": link, "at": at, "d": at.distance_squared_to(near)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	return found


func _first_reachable(level: int, near: Vector2, found: Array) -> Dictionary:
	var nav := _nav(level)
	var from_cell := Vector2i(floori(near.x), floori(near.y))
	var tries := 0
	for entry in found:
		tries += 1
		if tries > 6:
			break
		var link: Dictionary = entry["link"]
		var at: Vector2 = entry["at"]
		if near.distance_to(at) <= LINK_MOUNT:
			return link
		if nav == null:
			return link
		if not nav.find_path(from_cell, Vector2i(floori(at.x), floori(at.y))).is_empty():
			return link
	return {}


## Book the link (one climber at a time, the hunters' ladder lock) and start walking it from where the NPC stands.
func _begin_crossing(npc: Dictionary, link: Dictionary) -> bool:
	var from_level := int(npc["level"])
	var to_level := int(LevelLink.other_end(link, from_level)["level"])
	var ladders = scene.get("_ladders") if scene != null else null
	var seconds := crossing_seconds(link)
	if ladders != null and not ladders.begin("npc:%d" % int(npc["id"]), link, from_level, seconds):
		return false
	var route := crossing_point(link, from_level, 0.0, _base_y())
	var at: Vector3 = npc["at"]
	npc["climb"] = {"link": link, "from_level": from_level, "to_level": to_level, "seconds": seconds,
		"gap": Vector2(at.x, at.z).distance_to(Vector2(route.x, route.z)) / _move_speed(false),
		"elapsed": 0.0, "from_at": at}
	npc["path"] = []
	return true


## Advance a crossing one tick. Returns true while the link still owns the NPC (including the frame it steps off).
func _tick_crossing(npc: Dictionary, delta: float) -> bool:
	var climb: Dictionary = npc["climb"] if npc.get("climb") is Dictionary else {}
	if climb.is_empty():
		return false
	var link: Dictionary = climb["link"]
	var from_level := int(climb["from_level"])
	var base_y := _base_y()
	var gap := float(climb["gap"])
	var cross := float(climb["seconds"])
	climb["elapsed"] = float(climb["elapsed"]) + delta
	npc["climb"] = climb
	var elapsed := float(climb["elapsed"])
	var along := 0.0
	var pos: Vector3
	if gap > 0.0 and elapsed < gap:
		var start: Vector3 = climb["from_at"]
		pos = start.lerp(crossing_point(link, from_level, 0.0, base_y), elapsed / gap)
	else:
		along = 1.0 if cross <= 0.0 else clampf((elapsed - gap) / cross, 0.0, 1.0)
		pos = crossing_point(link, from_level, along, base_y)
	var ahead := crossing_point(link, from_level, minf(1.0, along + .04), base_y)
	var flat := Vector2(ahead.x - pos.x, ahead.z - pos.z)
	if flat.length() > .01:
		_turn(npc, atan2(-flat.x, -flat.y), delta)
	npc["at"] = pos
	npc["clip"] = "climb" if String(link.get("kind", "")) == "ladder" else "walk"
	npc["path"] = []
	if elapsed + .0001 >= gap + cross:
		var done := crossing_point(link, from_level, 1.0, base_y)
		var to_level := int(climb["to_level"])
		npc["level"] = to_level
		npc["at"] = Vector3(done.x, _floor_y(to_level), done.z)
		npc["away"] = 0.0
		_drop_crossing(npc)
	return true


## Point `progress` (0 at the near end, 1 at the far end) along a link, in world space. Stairs and spirals follow the
## authored path; a ramp follows its slope; a ladder stays on the shaft and changes height.
static func crossing_point(link: Dictionary, from_level: int, progress: float, base_y: float) -> Vector3:
	var to_level := int(LevelLink.other_end(link, from_level)["level"])
	var t := clampf(progress, 0.0, 1.0)
	var chunk: Vector3i = link["chunk"]
	var lower := mini(from_level, to_level)
	var lower_y := base_y + float(lower) * StreamedFacilityView3D.LEVEL_HEIGHT
	var path: Array = link.get("path", [])
	if not path.is_empty():
		var going_up := to_level > from_level
		var p := LadderTraffic.path_point(link, t, going_up)
		var origin := Vector2(chunk.x, chunk.z) * StreamedRouteGenerator.CHUNK_SIZE
		return Vector3(origin.x + p.x, lower_y + p.y, origin.y + p.z)
	if String(link.get("kind", "")) == "ramp":
		var start := LadderTraffic.ladder_point(link, from_level)
		var finish := LadderTraffic.ladder_point(link, to_level)
		var xz := start.lerp(finish, t)
		var local_x := xz.x - float(chunk.x * StreamedRouteGenerator.CHUNK_SIZE)
		var upper_y := base_y + float(link["from_level"]) * StreamedFacilityView3D.LEVEL_HEIGHT
		return Vector3(xz.x, upper_y + StreamedFacilityView3D._ramp_surface_y(link, local_x), xz.y)
	var at := LadderTraffic.ladder_point(link, from_level)
	var going_up := to_level > from_level
	var height := StreamedFacilityView3D.LEVEL_HEIGHT * (t if going_up else 1.0 - t)
	return Vector3(at.x, lower_y + height, at.y)


static func crossing_seconds(link: Dictionary) -> float:
	var length := StreamedFacilityView3D.LEVEL_HEIGHT
	var path: Array = link.get("path", [])
	if not path.is_empty():
		length = maxf(LadderTraffic.path_length(link), .5)
	elif String(link.get("kind", "")) == "ramp":
		var flat := LadderTraffic.ladder_point(link, int(link["from_level"])).distance_to(
			LadderTraffic.ladder_point(link, int(link["to_level"])))
		var rise := StreamedFacilityView3D.LEVEL_HEIGHT
		length = sqrt(flat * flat + rise * rise)
	return maxf(length / _move_speed(false), .2)


func _drop_crossing(npc: Dictionary) -> void:
	var ladders = scene.get("_ladders") if scene != null else null
	if ladders != null:
		ladders.release("npc:%d" % int(npc["id"]))
	npc["climb"] = {}
	npc["storey"] = {}
	npc["storey_age"] = 99.0


func _generator() -> StreamedRouteGenerator:
	var facility: Node = scene.get("facility") if scene != null else null
	if facility == null:
		return null
	return facility.get("generator") as StreamedRouteGenerator


func _base_y() -> float:
	var facility: Node3D = scene.get("facility")
	return facility.global_position.y if facility != null else 0.0


## The body yaw toward `want` through a critically damped spring, rate capped.
func _turn(npc: Dictionary, want: float, delta: float) -> void:
	var facing := float(npc["facing"])
	var v := float(npc.get("turn_v", 0.0))
	var error := wrapf(want - facing, -PI, PI)
	v = clampf(v + (TURN_SPRING * error - 2.0 * sqrt(TURN_SPRING) * v) * delta, -TURN_RATE, TURN_RATE)
	npc["turn_v"] = v
	npc["facing"] = wrapf(facing + v * delta, -PI, PI)


## Human runners (the host and every guest; never another NPC) with a fresh state: the nearest on the NPC's storey, else the
## nearest anywhere.
func _leader(npc: Dictionary) -> Dictionary:
	var at: Vector3 = npc["at"]
	var runners: Array = []
	var follow := int(npc.get("follow_peer", 0))
	if follow != 0:
		# an admin's "follow me": that runner only, while it is in the run
		var local_id := scene.multiplayer.get_unique_id() if RoomState.online else 1
		var player_node: Node3D = scene.get("player")
		if follow == local_id and player_node != null:
			return {"at": player_node.global_position, "level": _level_of(player_node.global_position.y)}
		var followed: Dictionary = (scene.get("_remotes").call("peer_state", follow) as Dictionary) if scene.get("_remotes") != null else {}
		if followed.get("at") is Vector3:
			return {"at": followed["at"], "level": -int(followed.get("depth", 0))}
		npc["follow_peer"] = 0
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


## A short line now and then (chat on): a chasing hunter close, as the playtest bots say it, spoken by the TTS with the NPC's
## own voice. The host delivers it as the NPC's line (RemotePlayers.npc_chat).
func _talk(npc: Dictionary, hunter: Dictionary) -> void:
	if not bool(npc.get("chat", true)) or hunter.is_empty() or String(hunter["state"]) != "CHASE" or float(hunter["dist"]) > 12.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(npc.get("said_at", -100.0)) < CHAT_COOLDOWN:
		return
	npc["said_at"] = now
	var remotes: Node = scene.get("_remotes")
	if remotes != null and remotes.has_method("npc_chat"):
		var lines: Array = ["Hunter! Run!", "It's on me, help!", "Something's chasing me!", "Hunter close, watch out!"]
		remotes.call("npc_chat", int(npc["id"]), String(npc["name"]), String(lines[randi() % lines.size()]), npc["at"])


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


func _nav(level: int) -> StreamedHunterNavigation:
	var navs: Dictionary = scene.get("_navigations")
	return navs.get(level) as StreamedHunterNavigation if navs != null else null


func _floor_y(level: int) -> float:
	var facility: Node3D = scene.get("facility")
	return facility.global_position.y + float(level) * StreamedFacilityView3D.LEVEL_HEIGHT


func _level_of(y: float) -> int:
	var facility: Node3D = scene.get("facility")
	return roundi((y - facility.global_position.y) / StreamedFacilityView3D.LEVEL_HEIGHT)
