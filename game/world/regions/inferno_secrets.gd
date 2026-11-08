class_name InfernoSecrets
extends RefCounted

## The wolf spiders' home: the Inferno, level -3 (docs/SECRET_WOLF_SPIDER.md). One instance lives on the streamed route node and is
## updated from its host-side hunter tick. Guests do not run it (the host spawns a durable "SECRET:" hunter state which the normal hunter
## replication carries). The dwell clock runs while the local runner OR a living co-op guest is on the home level.
##
## Hook for the route (the only changes outside this file's neighbours):
##   var _inferno_secrets := InfernoSecrets.new()                  # next to _hunter_emoter
##   _inferno_secrets.update(self, delta)                          # first line of _update_hunters after the simulates() guard
##   (SecretCreatures.stays_home(hunter_id) keeps _hunter_ladder_step from ever sending one up a ramp or ladder)
##
## Trigger (SecretCreatures.TRIGGER): "inferno" = a runner has spent DWELL_SECONDS on level -3 (the clock runs only while someone is there,
## once per tick, and keeps what it has when everyone leaves); "off" = nothing ever spawns by itself (only the admin picker can summon them).
## The local runner counts, and so does each living guest whose replicated depth is the home level (route._remotes.target_states). The spawn
## anchors on the local runner when they are home, otherwise on the guest with the lowest peer id. The host still simulates and spawns.
## SecretCreatures.RELATIONSHIP / DIFFICULTY decide who comes and whether it is a pair (solo or pair by game difficulty, with the shared
## SpiderPack rest). A creature appears out of reach, already telegraphing (bark or hiss): the warning comes first. It then roams and hunts
## on -3 only (SecretCreatures.HOME_LEVEL), preferring big open ground for its lair (its legs sprawl 3.5 m wide).

const DWELL_SECONDS := 30.0
const SPAWN_MIN_DISTANCE := 16.0
const SPAWN_MAX_DISTANCE := 23.0
const DISCOVER_RANGE := 14.0
const DISCOVER_EVERY := 0.5
## Open ground around a lair: cells counted in a square of CLEARANCE_RADIUS around it; a lair prefers at least WIDE_CLEARANCE of
## (2r+1)^2 cells open (a cavern or a lava hall), and never below ROOMY_CLEARANCE (a hall it can turn round in).
const CLEARANCE_RADIUS := 3
const WIDE_CLEARANCE := 0.9
const ROOMY_CLEARANCE := 0.6
const LAIR_SAMPLES := 220

## Test hooks: the validator arms a trigger / relationship / difficulty without touching the shipped constants.
static var trigger_override := ""
static var relationship_override := ""
static var difficulty_override := ""

var fired := false                  # at least one creature has been spawned this run
var dwell := 0.0                    # seconds any living runner (local or co-op guest) has spent on the home level
var spawned := {}                   # creature id -> true
var met := {}                       # creature id -> true once the local runner has seen it (account-independent)

var pack: SpiderPack = null
var pending_join := {}              # {"id", "left", "knobs", "stagger", "flank"}: the black one joining a "hard" pair after the white one's bark
var last_plan := {}

var _discover_left := 0.0


static func trigger() -> String:
	return trigger_override if not trigger_override.is_empty() else SecretCreatures.TRIGGER


static func relationship() -> String:
	return relationship_override if not relationship_override.is_empty() else SecretCreatures.RELATIONSHIP


static func difficulty() -> String:
	return difficulty_override if not difficulty_override.is_empty() else RoomState.difficulty_id()


static func entity_id(creature_id: String) -> String:
	return "SECRET:%s" % creature_id


func update(route, delta: float) -> void:
	_discover(route, delta)
	_update_join(route, delta)
	if trigger() == "off" or route.player == null:
		return
	var anchor = _home_anchor(route)
	if not anchor is Vector2:
		return
	if _finished(route):
		return
	dwell += delta
	if dwell >= DWELL_SECONDS:
		_fire(route, anchor)


## Position the trigger anchors on. The local runner wins when they are on the home level; otherwise the living guest
## with the lowest peer id. Empty when nobody the host is simulating is on that level (the clock pauses and keeps dwell).
## Guest depth is the replicated value (-level), the same one RemotePlayers.target_states already exposes. Dead and
## spectating guests do not count. One anchor per tick, so two runners on -3 do not run the clock twice.
func _home_anchor(route) -> Variant:
	if route.player != null and int(route.facility.current_level()) == SecretCreatures.HOME_LEVEL:
		return route.player.grid_position()
	var remotes = route.get("_remotes") if "_remotes" in route else null
	if remotes == null or not remotes.has_method("target_states"):
		return null
	var home_depth := -SecretCreatures.HOME_LEVEL
	var found := false
	var best_peer := 0
	var best_position := Vector2.ZERO
	for state in remotes.target_states({}):
		if typeof(state) != TYPE_DICTIONARY:
			continue
		if int(state.get("depth", 0)) != home_depth:
			continue
		if bool(state.get("game_over", false)) or bool(state.get("spectating", false)):
			continue
		var position = state.get("position")
		if not position is Vector2:
			continue
		var peer_id := int(state.get("peer_id", 0))
		if not found or peer_id < best_peer:
			found = true
			best_peer = peer_id
			best_position = position
	return best_position if found else null


## ---------------------------------------------------------------- spawn

## Creatures that already exist this run (spawned now, or earlier in a saved route, or removed by an admin) count as done.
func _finished(route) -> bool:
	for id in _planned_ids():
		var entity := entity_id(String(id))
		if route.world_state.has_hunter(entity) or route.world_state.removed_hunters.has(entity):
			spawned[id] = true
	fired = not spawned.is_empty()
	return _plan(route).is_empty() and fired


func _planned_ids() -> Array:
	return [SecretCreatures.WHITE_WOLF_SPIDER, SecretCreatures.BLACK_WOLF_SPIDER]


## Which creatures the NEXT trigger brings (empty = nothing more to bring right now).
func _plan(route) -> Array:
	return _plan_info(route)["ids"]


## {"ids", "knobs", "join": "now" | "after_bark", "join_delay", "stagger", "flank"}.
func _plan_info(route) -> Dictionary:
	var white := SecretCreatures.WHITE_WOLF_SPIDER
	var black := SecretCreatures.BLACK_WOLF_SPIDER
	var plain := {"ids": [], "knobs": {}, "join": "now", "join_delay": 0.0, "stagger": 0.0, "flank": false}
	match relationship():
		"pair":
			plain["ids"] = [] if spawned.has(white) or spawned.has(black) else [white, black]
			plain["stagger"] = 1.8
			return plain
		"black_rare":
			if spawned.has(white) or spawned.has(black):
				return plain
			var roll := SeededRandom.new("%s:SECRET-PICK" % route.facility.generator.world_seed).next_float()
			plain["ids"] = [black] if roll < SecretCreatures.BLACK_CHANCE else [white]
			return plain
		"black_follows_white":
			if not spawned.has(white):
				plain["ids"] = [white]
			elif not spawned.has(black) and met.has(white):
				plain["ids"] = [black]
			return plain
		_:
			if spawned.has(white) or spawned.has(black):
				return plain          # one plan per run: the difficulty decided solo or pair, and who, when the trigger first fired
			last_plan = SecretCreatures.plan_for(difficulty(), String(route.facility.generator.world_seed))
			return last_plan


func _fire(route, player_position: Vector2) -> void:
	var info := _plan_info(route)
	var ids: Array = info["ids"]
	if ids.is_empty():
		dwell = 0.0                      # armed, but nothing is due yet (e.g. the black one waits until the white one has been met)
		return
	var knobs: Dictionary = info["knobs"]
	var first_id := String(ids[0])
	var first_position = _pick_lair(route, player_position, first_id)
	if first_position == null or not _spawn(route, first_id, first_position, player_position, knobs, 0.0):
		dwell = DWELL_SECONDS * .9       # nowhere open yet (the floor around the runner is still streaming in): try again on a later tick
		return
	if ids.size() > 1:
		var second_id := String(ids[1])
		if String(info["join"]) == "after_bark":
			# the black one joins once the white one has noticed the runner (it barks the moment it appears): `join_delay` s later, from another side
			pending_join = {"id": second_id, "left": float(info["join_delay"]), "knobs": knobs, "stagger": float(info["stagger"]),
				"flank": bool(info["flank"]), "first_position": first_position}
		else:
			_spawn_second(route, second_id, player_position, first_position, knobs, float(info["stagger"]), bool(info["flank"]))
	dwell = 0.0


func _spawn_second(route, second_id: String, player_position: Vector2, first_position: Vector2, knobs: Dictionary, stagger: float, flank: bool) -> bool:
	var position = _pick_lair(route, player_position, second_id, first_position, flank)
	if position == null:
		return false
	return _spawn(route, second_id, position, player_position, knobs, stagger)


func _update_join(route, delta: float) -> void:
	if pending_join.is_empty():
		return
	pending_join["left"] = float(pending_join["left"]) - delta
	if float(pending_join["left"]) > 0.0 or route.player == null:
		return
	var join := pending_join
	pending_join = {}
	var anchor = _home_anchor(route)
	if anchor is Vector2:
		_spawn_second(route, String(join["id"]), anchor, join["first_position"], join["knobs"], 0.0, bool(join["flank"]))


## Share of the square of CLEARANCE_RADIUS around `cell` that a hunter can stand on (1.0 = open ground all round).
static func clearance(navigation, cell: Vector2i) -> float:
	var open := 0
	for dz in range(-CLEARANCE_RADIUS, CLEARANCE_RADIUS + 1):
		for dx in range(-CLEARANCE_RADIUS, CLEARANCE_RADIUS + 1):
			if navigation.is_floor(cell.x + dx + .5, cell.y + dz + .5):
				open += 1
	var side := CLEARANCE_RADIUS * 2 + 1
	return float(open) / float(side * side)


## A deterministic open cell SPAWN_MIN..MAX cells from the runner on the home level, reachable from the runner, on the widest ground
## around (seeded by the route seed and the creature). `avoid` (the first creature of a pair): keep at least PAIR_MIN_GAP cells from it,
## and when `flank` is set prefer the far side of the runner (at least PAIR_FLANK_DEGREES between the two as seen from the runner).
## Returns null while no such cell exists (yet).
func _pick_lair(route, player_position: Vector2, creature_id: String = SecretCreatures.WHITE_WOLF_SPIDER, avoid = null, flank := false):
	var navigation = route._navigations.get(SecretCreatures.HOME_LEVEL)
	if navigation == null:
		return null
	var rng := SeededRandom.new("%s:SECRET-LAIR:%s" % [route.facility.generator.world_seed, creature_id])
	var here := Vector2i(floori(player_position.x), floori(player_position.y))
	var wide: Array = []
	var roomy: Array = []
	var any: Array = []
	for _i in LAIR_SAMPLES:
		var angle := rng.next_float() * TAU
		var distance := lerpf(SPAWN_MIN_DISTANCE, SPAWN_MAX_DISTANCE, rng.next_float())
		var cell := here + Vector2i(roundi(cos(angle) * distance), roundi(sin(angle) * distance))
		if not navigation.can_occupy(cell.x + .5, cell.y + .5):
			continue
		var world := Vector2(cell) + Vector2(.5, .5)
		if avoid != null:
			if world.distance_to(avoid as Vector2) < SecretCreatures.PAIR_MIN_GAP:
				continue
			if flank:
				var first_dir := ((avoid as Vector2) - player_position).normalized()
				if absf(rad_to_deg(first_dir.angle_to((world - player_position).normalized()))) < SecretCreatures.PAIR_FLANK_DEGREES:
					continue
		var open := clearance(navigation, cell)
		if open >= WIDE_CLEARANCE:
			wide.append(world)
		elif open >= ROOMY_CLEARANCE:
			roomy.append(world)
		else:
			any.append(world)
	for pool in [wide, roomy, any]:
		var candidates: Array = pool
		while not candidates.is_empty():
			var index := rng.next_index(candidates.size())
			var candidate: Vector2 = candidates[index]
			candidates.remove_at(index)
			if not navigation.find_path(Vector2i(floori(candidate.x), floori(candidate.y)), here).is_empty():
				return candidate
	if avoid != null and flank:
		return _pick_lair(route, player_position, creature_id, avoid, false)   # no far side open: relax the flank
	return null


func _spawn(route, creature_id: String, spawn_position: Vector2, target_position: Vector2, knobs: Dictionary = {}, bark_delay: float = 0.0) -> bool:
	var level := SecretCreatures.HOME_LEVEL
	var navigation = route._navigations.get(level)
	if navigation == null:
		return false
	var cell := Vector2i(floori(spawn_position.x), floori(spawn_position.y))
	var entity := entity_id(creature_id)
	var state: Dictionary = route.world_state.ensure_hunter({
		"id": entity, "hunter_id": creature_id,
		"origin_chunk": navigation.cell_chunk(cell, level),
		"cell": StreamedHunterNavigation.local_cell(cell), "level": level,
	})
	if state.is_empty():
		return false
	state["position"] = spawn_position
	state["active"] = true
	state["state"] = int(HunterBrain.State.IDLE)
	state["facing"] = (target_position - spawn_position).normalized()
	route.world_state.hunters[entity] = state
	route._hunter_stream_signature = ""
	route._refresh_hunter_stream()
	var view = route._hunter_views.get(entity)
	if view != null and view.brain != null:
		view.brain.activate_at(target_position)
		var gimmick := view.brain.gimmick as WhiteWolfSpiderGimmick
		if gimmick != null:
			gimmick.start_with_bark(bark_delay)
			if not knobs.is_empty():
				gimmick.apply_knobs(view.brain, knobs)
			_link_pack(route, creature_id)         # links only once the other one of the pair exists
		view.sync_from_brain()
		route._store_hunter(entity, view)
	spawned[creature_id] = true
	fired = true
	return true


static func _other(creature_id: String) -> String:
	return SecretCreatures.BLACK_WOLF_SPIDER if creature_id == SecretCreatures.WHITE_WOLF_SPIDER else SecretCreatures.WHITE_WOLF_SPIDER


## Both of a pair on the route: one shared rest timer / recall (SpiderPack).
func _link_pack(route, creature_id: String) -> void:
	var mine = route._hunter_views.get(entity_id(creature_id))
	var theirs = route._hunter_views.get(entity_id(_other(creature_id)))
	if mine == null or theirs == null or mine.brain == null or theirs.brain == null:
		return
	var a := mine.brain.gimmick as WhiteWolfSpiderGimmick
	var b := theirs.brain.gimmick as WhiteWolfSpiderGimmick
	if a == null or b == null:
		return
	if pack == null:
		pack = SpiderPack.new()
		pack.join(b)
	pack.join(a)


## "Met" = the local runner has line of sight to it within DISCOVER_RANGE (the black one's condition under black_follows_white).
## The dossier entry is created only for a signed-in account and never in a debug run (Backend.account_discover_hunter enforces both).
func _discover(route, delta: float) -> void:
	_discover_left -= delta
	if _discover_left > 0.0 or route.player == null:
		return
	_discover_left = DISCOVER_EVERY
	var level: int = route.facility.current_level()
	var navigation = route._navigations.get(level)
	if navigation == null:
		return
	var here: Vector2 = route.player.grid_position()
	for id in _planned_ids():
		var entity := entity_id(String(id))
		var view = route._hunter_views.get(entity)
		if view == null or view.brain == null or not view.brain.active or int(route._hunter_levels.get(entity, 999999)) != level:
			continue
		if view.brain.position.distance_to(here) <= DISCOVER_RANGE and navigation.has_line_of_sight(here, view.brain.position):
			met[id] = true
			if Backend.signed_in():
				Backend.account_discover_hunter(String(id))
