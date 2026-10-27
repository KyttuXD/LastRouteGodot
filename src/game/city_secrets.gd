class_name CitySecrets
extends RefCounted

## The City's secret trigger and spawn (docs/SECRET_WOLF_SPIDER.md). One instance lives on the streamed route node and
## is updated from its host-side hunter tick; it does nothing unless the route's generator is the City, and nothing at
## all on guests (the host spawns a durable "SECRET:" hunter state which the normal hunter replication carries).
##
## Hook for the route (3 lines, the only change outside this file's neighbours):
##   var _city_secrets := CitySecrets.new()                       # next to _hunter_emoter
##   _city_secrets.update(self, delta)                            # first line of _update_hunters after the simulates() guard
##   (and `or entity_id.begins_with("SECRET:")` next to the "ADMIN:" check in _repair_duplicate_hunter_identities)
##
## Triggers (SecretCreatures.TRIGGER, "off" for now: nothing ever spawns by itself): "garden_vigil" = stand still in a garden with
## the flashlight OFF for VIGIL_SECONDS (nothing in normal play looks like that); "fountains" = stand at all the fountains in one run.
## Only the local runner counts. A creature appears out of reach, already telegraphing (bark or hiss): the warning comes first.
## SecretCreatures.RELATIONSHIP says which creature a trigger brings: "black_follows_white" (first the white one; the black one only
## for a runner who has MET the white one, on a second trigger), "black_rare" (one creature per run, black 1 time in 4) or "pair".

const ENTITY_ID := "SECRET:white_wolf_spider"   # the white one (kept for callers); see entity_id() for any creature
const VIGIL_SECONDS := 45.0
const VIGIL_STILL_SPEED := 0.45        # cells per second: slower than this counts as standing still
const VIGIL_DECAY := 2.0               # moving, light on or leaving the garden drains the vigil this much faster
const FOUNTAIN_RADIUS := 4.0
const SPAWN_MIN_DISTANCE := 16.0
const SPAWN_MAX_DISTANCE := 23.0
const DISCOVER_RANGE := 14.0
const DISCOVER_EVERY := 0.5

## Test hooks: the validator arms a trigger / relationship without touching the shipped constants.
static var trigger_override := ""
static var relationship_override := ""

var fired := false                  # at least one creature has been spawned this run
var vigil := 0.0
var fountains_seen := {}
var spawned := {}                   # creature id -> true
var met := {}                       # creature id -> true once the local runner has seen it (account-independent)

var _last_position := Vector2.ZERO
var _has_last := false
var _discover_left := 0.0


static func trigger() -> String:
	return trigger_override if not trigger_override.is_empty() else SecretCreatures.TRIGGER


static func relationship() -> String:
	return relationship_override if not relationship_override.is_empty() else SecretCreatures.RELATIONSHIP


static func entity_id(creature_id: String) -> String:
	return "SECRET:%s" % creature_id


func update(route, delta: float) -> void:
	if not SecretCreatures.is_city_generator(route.facility.generator):
		return
	_discover(route, delta)
	if trigger() == "off" or _finished(route):
		return
	var player = route.player
	if player == null:
		return
	var position: Vector2 = player.grid_position()
	var speed := position.distance_to(_last_position) / maxf(delta, 0.001) if _has_last else 99.0
	_last_position = position
	_has_last = true
	var layout = route.facility.generator.get("layout")
	if layout == null:
		return
	match trigger():
		"fountains":
			_update_fountains(layout, position)
			if fountains_seen.size() >= _fountain_cells(layout).size():
				_fire(route, layout, position)
		_:
			var still: bool = speed <= VIGIL_STILL_SPEED and not bool(player.get("flashlight_enabled"))
			if still and _in_garden(layout, position):
				vigil += delta
			else:
				vigil = maxf(0.0, vigil - delta * VIGIL_DECAY)
			if vigil >= VIGIL_SECONDS:
				_fire(route, layout, position)


## ---------------------------------------------------------------- City geometry (read through the layout object so
## this file also compiles where the City generator is not merged yet)

static func _constant(layout, name: String):
	var script = layout.get_script()
	if script == null:
		return null
	return script.get_script_constant_map().get(name)


## World cell (the route's grid) -> City layout cell.
static func city_cell(layout, world_cell: Vector2) -> Vector2i:
	var offset: Vector2i = _constant(layout, "ORIGIN_OFFSET") if _constant(layout, "ORIGIN_OFFSET") != null else Vector2i.ZERO
	return Vector2i(floori(world_cell.x), floori(world_cell.y)) + offset


static func world_cell(layout, city: Vector2i) -> Vector2:
	var offset: Vector2i = _constant(layout, "ORIGIN_OFFSET") if _constant(layout, "ORIGIN_OFFSET") != null else Vector2i.ZERO
	return Vector2(city - offset) + Vector2(.5, .5)


static func _in_garden(layout, world_position: Vector2) -> bool:
	var cell := city_cell(layout, world_position)
	for rect_value in (_constant(layout, "GARDENS") if _constant(layout, "GARDENS") != null else []):
		var rect: Rect2i = rect_value
		if rect.grow(-1).has_point(cell):
			return true
	return false


## Roundabout fountain, both garden fountains and the grand plaza's pool (city cells).
static func _fountain_cells(layout) -> Array:
	var cells: Array = []
	var round_center = _constant(layout, "ROUNDABOUT_CENTER")
	if round_center != null:
		cells.append(Vector2i(round_center))
	for rect_value in (_constant(layout, "GARDENS") if _constant(layout, "GARDENS") != null else []):
		var rect: Rect2i = rect_value
		cells.append(rect.position + rect.size / 2)
	var plaza = _constant(layout, "GRAND_PLAZA")
	if plaza != null:
		var r: Rect2i = plaza
		cells.append(r.position + r.size / 2)
	return cells


func _update_fountains(layout, position: Vector2) -> void:
	var here := city_cell(layout, position)
	var index := 0
	for cell_value in _fountain_cells(layout):
		var cell: Vector2i = cell_value
		if Vector2(here - cell).length() <= FOUNTAIN_RADIUS:
			fountains_seen[index] = true
		index += 1


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
	var white := SecretCreatures.WHITE_WOLF_SPIDER
	var black := SecretCreatures.BLACK_WOLF_SPIDER
	match relationship():
		"pair":
			return [] if spawned.has(white) or spawned.has(black) else [white, black]
		"black_rare":
			if spawned.has(white) or spawned.has(black):
				return []
			var roll := SeededRandom.new("%s:SECRET-PICK" % route.facility.generator.world_seed).next_float()
			return [black] if roll < SecretCreatures.BLACK_CHANCE else [white]
		_:
			if not spawned.has(white):
				return [white]
			if not spawned.has(black) and met.has(white):
				return [black]
			return []


func _fire(route, layout, player_position: Vector2) -> void:
	var plan := _plan(route)
	if plan.is_empty():
		vigil = 0.0                      # armed, but nothing is due yet (e.g. the black one waits until the white one has been met)
		fountains_seen.clear()
		return
	var spawned_now := false
	for id in plan:
		var spawn_position = _pick_lair(route, layout, player_position, String(id))
		if spawn_position != null and _spawn(route, String(id), spawn_position, player_position):
			spawned_now = true
	if spawned_now:
		vigil = 0.0
		fountains_seen.clear()
	else:
		vigil = VIGIL_SECONDS * .9       # nowhere open yet: try again on a later tick


## A deterministic open garden / plaza / path cell SPAWN_MIN..MAX cells from the runner (seeded by the route seed and the creature).
func _pick_lair(route, layout, player_position: Vector2, creature_id: String = SecretCreatures.WHITE_WOLF_SPIDER):
	var rng := SeededRandom.new("%s:SECRET-LAIR:%s" % [route.facility.generator.world_seed, creature_id])
	var preferred: Array = []
	var fallback: Array = []
	var kinds_wanted: Array = [_constant(layout, "GRASS"), _constant(layout, "PATH"), _constant(layout, "PLAZA")]
	var here := city_cell(layout, player_position)
	var reach := int(SPAWN_MAX_DISTANCE)
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := here + Vector2i(dx, dz)
			var distance := Vector2(dx, dz).length()
			if distance < SPAWN_MIN_DISTANCE or distance > SPAWN_MAX_DISTANCE:
				continue
			if not layout.is_open(cell.x, cell.y):
				continue
			(preferred if kinds_wanted.has(layout.kind_at(cell.x, cell.y)) else fallback).append(cell)
	var pool := preferred if not preferred.is_empty() else fallback
	if pool.is_empty():
		return null
	var cell: Vector2i = pool[rng.next_index(pool.size())]
	return world_cell(layout, cell)


func _spawn(route, creature_id: String, spawn_position: Vector2, target_position: Vector2) -> bool:
	var level: int = route.facility.current_level()
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
			gimmick.start_with_bark()
		view.sync_from_brain()
		route._store_hunter(entity, view)
	spawned[creature_id] = true
	fired = true
	return true


## "Met" = the local runner has line of sight to it within DISCOVER_RANGE (the black one's condition under black_follows_white).
## The dossier entry is created only for a signed-in account and never in a debug run (Backend.account_discover_hunter enforces both).
func _discover(route, delta: float) -> void:
	_discover_left -= delta
	if _discover_left > 0.0 or route.player == null:
		return
	_discover_left = DISCOVER_EVERY
	var here: Vector2 = route.player.grid_position()
	for id in _planned_ids():
		var view = route._hunter_views.get(entity_id(String(id)))
		if view == null or view.brain == null or not view.brain.active:
			continue
		if view.brain.position.distance_to(here) <= DISCOVER_RANGE \
				and route.facility.generator.has_line_of_sight(here, view.brain.position):
			met[id] = true
			if Backend.signed_in():
				Backend.account_discover_hunter(String(id))
