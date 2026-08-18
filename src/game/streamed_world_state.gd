class_name StreamedWorldState
extends RefCounted

## Host-authoritative mutable state for an otherwise deterministic endless
## route. Chunk meshes may unload; checkpoint damage and claimed pickup ids do
## not. The plain Dictionary snapshot is RPC/save friendly for late joining.

const SCHEMA := 1

var active_checkpoint := ""
var claimed_pickups := {}
var safe_rooms := {}


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


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"active_checkpoint": active_checkpoint,
		"claimed_pickups": claimed_pickups.duplicate(true),
		"safe_rooms": safe_rooms.duplicate(true),
	}


func adopt(snapshot_data: Dictionary) -> bool:
	if int(snapshot_data.get("schema", -1)) != SCHEMA:
		return false
	var pickups = snapshot_data.get("claimed_pickups", {})
	var rooms = snapshot_data.get("safe_rooms", {})
	if not pickups is Dictionary or not rooms is Dictionary:
		return false
	active_checkpoint = String(snapshot_data.get("active_checkpoint", ""))
	claimed_pickups = (pickups as Dictionary).duplicate(true)
	safe_rooms = (rooms as Dictionary).duplicate(true)
	return true


func _safe_room_state(info: Dictionary) -> Dictionary:
	var room_id := String(info.get("id", ""))
	if not safe_rooms.has(room_id):
		safe_rooms[room_id] = {
			"integrity": int(info.get("max_integrity", 100)),
			"breached": false,
		}
	return safe_rooms[room_id]
