class_name StreamedWorldState
extends RefCounted

## Host-authoritative mutable state for an otherwise deterministic endless
## route. Chunk meshes may unload; checkpoint damage and claimed pickup ids do
## not. The plain Dictionary snapshot is RPC/save friendly for late joining.

const SCHEMA := 2

var active_checkpoint := ""
var claimed_pickups := {}
var safe_rooms := {}
var hunters := {}


func activate_checkpoint(chunk_data: Dictionary) -> bool:
	if not bool(chunk_data.get("safe_room", false)):
		return false
	var info: Dictionary = chunk_data.get("safe_room_data", {})
	if info.is_empty():
		return false
	var state := _safe_room_state(info)
	if bool(state.get("breached", false)):
		return false
	active_checkpoint = String(info.get("checkpoint_id", ""))
	return not active_checkpoint.is_empty()


func damage_safe_room(info: Dictionary, amount: int) -> Dictionary:
	var state := _safe_room_state(info)
	if not bool(info.get("breachable", true)):
		return state.duplicate(true)
	state["integrity"] = maxi(0, int(state["integrity"]) - maxi(0, amount))
	state["breached"] = int(state["integrity"]) <= 0
	safe_rooms[String(info.get("id", ""))] = state
	return state.duplicate(true)


func repair_safe_room(info: Dictionary, amount: int) -> Dictionary:
	var state := _safe_room_state(info)
	if not bool(info.get("repairable", true)):
		return state.duplicate(true)
	state["integrity"] = mini(int(info.get("max_integrity", 100)),
		int(state["integrity"]) + maxi(0, amount))
	state["breached"] = int(state["integrity"]) <= 0
	safe_rooms[String(info.get("id", ""))] = state
	return state.duplicate(true)


func claim_pickup(entity_id: String) -> bool:
	if entity_id.is_empty() or claimed_pickups.has(entity_id):
		return false
	claimed_pickups[entity_id] = true
	return true


func pickup_available(entity_id: String) -> bool:
	return not entity_id.is_empty() and not claimed_pickups.has(entity_id)


func safe_room_status(info: Dictionary) -> Dictionary:
	return _safe_room_state(info).duplicate(true)


func ensure_hunter(spawn: Dictionary) -> Dictionary:
	var entity_id := String(spawn.get("id", ""))
	if entity_id.is_empty():
		return {}
	if not hunters.has(entity_id):
		var coord: Vector3i = spawn.get("origin_chunk", Vector3i.ZERO)
		var cell: Vector2i = spawn.get("cell", Vector2i.ZERO)
		hunters[entity_id] = {
			"hunter_id": String(spawn.get("hunter_id", HunterRoster.DEFAULT_ID)),
			"position": Vector2(
				coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5,
				coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5),
			"level": int(spawn.get("level", coord.y)),
			"origin_chunk": coord,
			"active": true,
			"state": HunterBrain.State.IDLE,
			"facing": Vector2(0, 1),
			"stamina": GameConfig.HUNTER_STAMINA_MAX,
			"winded": false,
			"stun_timer": 0.0,
			"has_last_known": false,
			"last_known": Vector2.ZERO,
		}
	return (hunters[entity_id] as Dictionary).duplicate(true)


func has_hunter(entity_id: String) -> bool:
	return hunters.has(entity_id)


func hunter_state(entity_id: String) -> Dictionary:
	if not hunters.has(entity_id):
		return {}
	return (hunters[entity_id] as Dictionary).duplicate(true)


func store_hunter(entity_id: String, brain: HunterBrain, level: int,
		origin_chunk: Vector3i) -> void:
	if entity_id.is_empty() or brain == null:
		return
	hunters[entity_id] = {
		"hunter_id": brain.hunter_id,
		"position": brain.position,
		"level": level,
		"origin_chunk": origin_chunk,
		"active": brain.active,
		"state": int(brain.state),
		"facing": brain.facing,
		"stamina": brain.stamina,
		"winded": brain.winded,
		"stun_timer": brain.stun_timer,
		"has_last_known": brain.has_last_known,
		"last_known": brain.last_known,
		"idle_timer": brain.idle_timer,
		"has_wander_target": brain.has_wander_target,
		"wander_target": brain.wander_target,
		"search_timer": brain.search_timer,
		"search_visits": brain.search_visits,
		"has_search_target": brain.has_search_target,
		"search_target": brain.search_target,
	}


func restore_hunter(brain: HunterBrain, state: Dictionary) -> void:
	if brain == null or state.is_empty():
		return
	brain.position = state.get("position", brain.position)
	brain.active = bool(state.get("active", true))
	brain.state = clampi(int(state.get("state", HunterBrain.State.WANDER)),
		HunterBrain.State.IDLE, HunterBrain.State.SEARCH)
	brain.facing = state.get("facing", Vector2(0, 1))
	brain.stamina = float(state.get("stamina", GameConfig.HUNTER_STAMINA_MAX))
	brain.winded = bool(state.get("winded", false))
	brain.stun_timer = float(state.get("stun_timer", 0.0))
	brain.has_last_known = bool(state.get("has_last_known", false))
	brain.last_known = state.get("last_known", Vector2.ZERO)
	brain.idle_timer = float(state.get("idle_timer", 0.0))
	brain.has_wander_target = bool(state.get("has_wander_target", false))
	brain.wander_target = state.get("wander_target", Vector2.ZERO)
	brain.search_timer = float(state.get("search_timer", 0.0))
	brain.search_visits = int(state.get("search_visits", 0))
	brain.has_search_target = bool(state.get("has_search_target", false))
	brain.search_target = state.get("search_target", Vector2.ZERO)


func hunter_ids_on_level(level: int) -> Array:
	var result := []
	for entity_id in hunters:
		var state: Dictionary = hunters[entity_id]
		if int(state.get("level", 0)) == level:
			result.append(String(entity_id))
	result.sort()
	return result


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"active_checkpoint": active_checkpoint,
		"claimed_pickups": claimed_pickups.duplicate(true),
		"safe_rooms": safe_rooms.duplicate(true),
		"hunters": hunters.duplicate(true),
	}


func adopt(snapshot_data: Dictionary) -> bool:
	var schema := int(snapshot_data.get("schema", -1))
	if schema not in [1, SCHEMA]:
		return false
	var pickups = snapshot_data.get("claimed_pickups", {})
	var rooms = snapshot_data.get("safe_rooms", {})
	var hunter_data = snapshot_data.get("hunters", {})
	if not pickups is Dictionary or not rooms is Dictionary \
			or not hunter_data is Dictionary:
		return false
	active_checkpoint = String(snapshot_data.get("active_checkpoint", ""))
	claimed_pickups = (pickups as Dictionary).duplicate(true)
	safe_rooms = (rooms as Dictionary).duplicate(true)
	hunters = (hunter_data as Dictionary).duplicate(true)
	return true


func _safe_room_state(info: Dictionary) -> Dictionary:
	var room_id := String(info.get("id", ""))
	if not safe_rooms.has(room_id):
		safe_rooms[room_id] = {
			"integrity": int(info.get("max_integrity", 100)),
			"breached": false,
		}
	return safe_rooms[room_id]
