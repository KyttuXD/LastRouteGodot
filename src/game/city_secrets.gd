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
## Triggers (SecretCreatures.TRIGGER): "garden_vigil" = stand still in a garden with the flashlight OFF for VIGIL_SECONDS
## (nothing in normal play looks like that); "fountains" = stand at all FOUNTAIN_COUNT fountains in one run.
## Only the local runner counts. The creature appears out of reach, already barking: the telegraph comes first.

const ENTITY_ID := "SECRET:white_wolf_spider"
const VIGIL_SECONDS := 45.0
const VIGIL_STILL_SPEED := 0.45        # cells per second: slower than this counts as standing still
const VIGIL_DECAY := 2.0               # moving, light on or leaving the garden drains the vigil this much faster
const FOUNTAIN_RADIUS := 4.0
const SPAWN_MIN_DISTANCE := 16.0
const SPAWN_MAX_DISTANCE := 23.0
const DISCOVER_RANGE := 14.0
const DISCOVER_EVERY := 0.5

var fired := false
var vigil := 0.0
var fountains_seen := {}

var _last_position := Vector2.ZERO
var _has_last := false
var _discover_left := 0.0


func update(route, delta: float) -> void:
	if not SecretCreatures.is_city_generator(route.facility.generator):
		return
	_discover(route, delta)
	if fired or SecretCreatures.TRIGGER == "off":
		return
	if route.world_state.has_hunter(ENTITY_ID) or route.world_state.removed_hunters.has(ENTITY_ID):
		fired = true
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
	match SecretCreatures.TRIGGER:
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

func _fire(route, layout, player_position: Vector2) -> void:
	fired = true
	var spawn_position = _pick_lair(route, layout, player_position)
	if spawn_position == null:
		fired = false          # nowhere open yet: try again on a later tick
		vigil = VIGIL_SECONDS * .9
		return
	_spawn(route, spawn_position, player_position)


## A deterministic open garden / plaza / path cell SPAWN_MIN..MAX cells from the runner (seeded by the route seed).
func _pick_lair(route, layout, player_position: Vector2):
	var rng := SeededRandom.new("%s:SECRET-LAIR" % route.facility.generator.world_seed)
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


func _spawn(route, spawn_position: Vector2, target_position: Vector2) -> void:
	var level: int = route.facility.current_level()
	var navigation = route._navigations.get(level)
	if navigation == null:
		fired = false
		return
	var cell := Vector2i(floori(spawn_position.x), floori(spawn_position.y))
	var state: Dictionary = route.world_state.ensure_hunter({
		"id": ENTITY_ID, "hunter_id": SecretCreatures.WHITE_WOLF_SPIDER,
		"origin_chunk": navigation.cell_chunk(cell, level),
		"cell": StreamedHunterNavigation.local_cell(cell), "level": level,
	})
	if state.is_empty():
		return
	state["position"] = spawn_position
	state["active"] = true
	state["state"] = int(HunterBrain.State.IDLE)
	state["facing"] = (target_position - spawn_position).normalized()
	route.world_state.hunters[ENTITY_ID] = state
	route._hunter_stream_signature = ""
	route._refresh_hunter_stream()
	var view = route._hunter_views.get(ENTITY_ID)
	if view != null and view.brain != null:
		view.brain.activate_at(target_position)
		var gimmick := view.brain.gimmick as WhiteWolfSpiderGimmick
		if gimmick != null:
			gimmick.start_with_bark()
		view.sync_from_brain()
		route._store_hunter(ENTITY_ID, view)


## The dossier entry is created only after an actual encounter: line of sight within DISCOVER_RANGE (account only,
## never in a debug run: Backend.account_discover_hunter enforces both).
func _discover(route, delta: float) -> void:
	_discover_left -= delta
	if _discover_left > 0.0 or not Backend.signed_in():
		return
	_discover_left = DISCOVER_EVERY
	var view = route._hunter_views.get(ENTITY_ID)
	if view == null or view.brain == null or not view.brain.active or route.player == null:
		return
	var here: Vector2 = route.player.grid_position()
	if view.brain.position.distance_to(here) <= DISCOVER_RANGE \
			and route.facility.generator.has_line_of_sight(here, view.brain.position):
		Backend.account_discover_hunter(SecretCreatures.WHITE_WOLF_SPIDER)
