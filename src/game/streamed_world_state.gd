class_name StreamedWorldState
extends RefCounted

## Host-authoritative mutable state for an otherwise deterministic endless
## route. Chunk meshes may unload; checkpoint damage and claimed pickup ids do
## not. The plain Dictionary snapshot is RPC/save friendly for late joining.

const SCHEMA := 6

var active_checkpoint := ""
var claimed_pickups := {}
var safe_rooms := {}
var hunters := {}
## Explicit admin removals must outlive chunk unload. Without a tombstone the
## deterministic spawn candidate is admitted again on the next stream refresh.
var removed_hunters := {}
var dropped_items := {}
var next_drop_sequence := 1
var sabotaged_relays := {}
## Stable generated door id -> {open, broken}. Closed/unbroken is the
## deterministic default and therefore does not need an entry until changed.
var room_doors := {}
## Room light switches (docs/LIGHT_SWITCHES.md): room id -> on/off, only rooms someone switched. Others use the seeded
## default (about one room in four starts dark).
var room_lights := {}
## One waypoint per player (WaypointState); never a shared list.
var waypoints := WaypointState.new()
var disabled_hiding := {}
## Monotonic local-only revision for data copied into hunter navigation.
## Hunter transforms deliberately do not touch it: only pickup/relay mutations
## can change the navigation-facing fixture lists. This lets the five-floor
## authority window keep its cached navigation instead of rebuilding every
## 0.2 seconds while a hunter is active.
var navigation_revision := 0
## Carnival booths (docs/CARNIVAL_BOOTHS.md): booth id -> unix time the booth is ready again. A booth with no entry (or a past one) is ready; the entry outlives the chunk and a reconnect.
var booth_ready_at := {}
## Merry-go-rounds (docs/CARNIVAL_BOOTHS.md, CarouselRide3D): ride id -> {on, angle (rad, true at t0), t0 (THIS machine's unix time)}. Every machine advances the angle by the same speed from its own clock, so guests
## see the same angle to within the network delay; a snapshot carries the angle at that instant and the receiver re-bases t0 to its own clock.
const CAROUSEL_SPEED := 0.45
var carousels := {}


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
	navigation_revision += 1
	return true


func pickup_available(entity_id: String) -> bool:
	return not entity_id.is_empty() and not claimed_pickups.has(entity_id)


func set_hiding_disabled(entity_id: String, disabled: bool) -> bool:
	if entity_id.is_empty():
		return false
	if disabled:
		disabled_hiding[entity_id] = true
		claimed_pickups[entity_id] = true
	else:
		disabled_hiding.erase(entity_id)
		claimed_pickups.erase(entity_id)
	navigation_revision += 1
	return true


func hiding_disabled(entity_id: String) -> bool:
	return disabled_hiding.has(entity_id)


func set_relay_sabotaged(entity_id: String, sabotaged: bool) -> bool:
	if entity_id.is_empty() or not claimed_pickups.has(entity_id):
		return false
	if sabotaged:
		sabotaged_relays[entity_id] = true
	else:
		sabotaged_relays.erase(entity_id)
	navigation_revision += 1
	return true


func relay_sabotaged(entity_id: String) -> bool:
	return sabotaged_relays.has(entity_id)


func room_door_status(door_id: String) -> Dictionary:
	if door_id.is_empty() or not room_doors.has(door_id):
		return {"open": false, "broken": false}
	return (room_doors[door_id] as Dictionary).duplicate(true)


func apply_room_door_state(door_id: String, open: bool,
		broken: bool = false) -> bool:
	if door_id.is_empty():
		return false
	var canonical := {"open": open or broken, "broken": broken}
	if room_doors.get(door_id, {}) == canonical:
		return false
	room_doors[door_id] = canonical
	return true


func create_drop(item_id: String, durability: int, position: Vector3,
		level: int, source_peer_id: int, source_inventory_slot: int = -1) -> Dictionary:
	if not PlayerController3D.INVENTORY_ITEMS.has(item_id):
		return {}
	var drop_id := "DROP:%d:%d" % [source_peer_id, next_drop_sequence]
	next_drop_sequence += 1
	var record := {"id": drop_id, "item": item_id,
		"durability": maxi(0, durability), "position": position,
		"level": level, "source_peer_id": source_peer_id,
		"source_inventory_slot": source_inventory_slot}
	dropped_items[drop_id] = record
	return record.duplicate(true)


func apply_drop(record: Dictionary) -> bool:
	var drop_id := String(record.get("id", ""))
	var item_id := String(record.get("item", ""))
	if drop_id.is_empty() or dropped_items.has(drop_id) \
			or not PlayerController3D.INVENTORY_ITEMS.has(item_id) \
			or not record.get("position") is Vector3:
		return false
	dropped_items[drop_id] = record.duplicate(true)
	return true


func claim_drop(drop_id: String) -> Dictionary:
	if not dropped_items.has(drop_id):
		return {}
	var record: Dictionary = dropped_items[drop_id]
	dropped_items.erase(drop_id)
	return record.duplicate(true)


func safe_room_status(info: Dictionary) -> Dictionary:
	return _safe_room_state(info).duplicate(true)


func apply_safe_room_status(room_id: String, integrity: int, breached: bool) -> bool:
	if room_id.is_empty():
		return false
	safe_rooms[room_id] = {
		"integrity": maxi(0, integrity),
		"breached": breached or integrity <= 0,
	}
	return true


func apply_checkpoint(checkpoint_id: String) -> bool:
	if checkpoint_id.is_empty():
		return false
	active_checkpoint = checkpoint_id
	return true


func ensure_hunter(spawn: Dictionary) -> Dictionary:
	var entity_id := String(spawn.get("id", ""))
	if entity_id.is_empty() or removed_hunters.has(entity_id):
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
			"active": false,
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


func remove_hunter(entity_id: String) -> bool:
	if entity_id.is_empty() or not hunters.has(entity_id):
		return false
	hunters.erase(entity_id)
	removed_hunters[entity_id] = true
	return true


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
		"emote": brain.emote_id,
		"emote_seq": brain.emote_seq,
		"emote_left": brain.emote_left,
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
	brain.emote_id = int(state.get("emote", -1))
	brain.emote_seq = int(state.get("emote_seq", 0))
	brain.emote_left = float(state.get("emote_left", 0.0))


func hunter_ids_on_level(level: int) -> Array:
	var result := []
	for entity_id in hunters:
		var state: Dictionary = hunters[entity_id]
		if int(state.get("level", 0)) == level:
			result.append(String(entity_id))
	result.sort()
	return result


static func default_room_light(room_id: String) -> bool:
	return absi(hash("%s:ROOM-LIGHT" % room_id)) % 4 != 0


func room_light_on(room_id: String) -> bool:
	return bool(room_lights.get(room_id, default_room_light(room_id)))


## Returns true when this changed the state (idempotent for replayed events).
func set_room_light(room_id: String, on: bool) -> bool:
	if room_id.is_empty():
		return false
	var changed := room_light_on(room_id) != on
	room_lights[room_id] = on
	return changed


## Seconds until the booth is ready again (0 when it is ready). `now` is unix time, passed in so the validators can run a clock.
func booth_cooldown_left(booth_id: String, now: float) -> float:
	return maxf(0.0, float(booth_ready_at.get(booth_id, 0.0)) - now)


## Rest a booth until `until` (idempotent: a replayed event cannot shorten it). Returns true when this changed the state.
func rest_booth(booth_id: String, until: float) -> bool:
	if booth_id.is_empty() or until <= float(booth_ready_at.get(booth_id, 0.0)):
		return false
	booth_ready_at[booth_id] = until
	return true


func carousel_on(ride_id: String) -> bool:
	return bool((carousels.get(ride_id, {}) as Dictionary).get("on", false))


func carousel_angle(ride_id: String, now: float) -> float:
	var c: Dictionary = carousels.get(ride_id, {})
	if c.is_empty():
		return 0.0
	var angle := float(c["angle"])
	if bool(c["on"]):
		angle += CAROUSEL_SPEED * (now - float(c["t0"]))
	return fposmod(angle, TAU)


## Start or stop a ride at `angle` (true now). Returns true when anything changed.
func set_carousel(ride_id: String, on: bool, angle: float, now: float) -> bool:
	if ride_id.is_empty():
		return false
	var before: Dictionary = carousels.get(ride_id, {})
	carousels[ride_id] = {"on": on, "angle": fposmod(angle, TAU), "t0": now}
	return before.is_empty() or bool(before.get("on", false)) != on


## Booths whose rest is over are forgotten, so the snapshot stays small.
func prune_booths(now: float) -> void:
	for id in booth_ready_at.keys():
		if float(booth_ready_at[id]) <= now:
			booth_ready_at.erase(id)


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"active_checkpoint": active_checkpoint,
		"claimed_pickups": claimed_pickups.duplicate(true),
		"safe_rooms": safe_rooms.duplicate(true),
		"hunters": hunters.duplicate(true),
		"removed_hunters": removed_hunters.duplicate(true),
		"dropped_items": dropped_items.duplicate(true),
		"next_drop_sequence": next_drop_sequence,
		"sabotaged_relays": sabotaged_relays.duplicate(true),
		"waypoints": waypoints.snapshot(),
		"disabled_hiding": disabled_hiding.duplicate(true),
		"room_doors": room_doors.duplicate(true),
		"room_lights": room_lights.duplicate(true),
		"booth_ready_at": booth_ready_at.duplicate(true),
		"carousels": _carousel_snapshot(Time.get_unix_time_from_system()),
	}


## The rides with their angle at `now`.
func _carousel_snapshot(now: float) -> Dictionary:
	var out := {}
	for id in carousels:
		out[id] = {"on": bool(carousels[id]["on"]), "angle": carousel_angle(String(id), now)}
	return out


func adopt(snapshot_data: Dictionary) -> bool:
	var schema := int(snapshot_data.get("schema", -1))
	if schema not in [1, 2, 3, 4, 5, SCHEMA]:
		return false
	var pickups = snapshot_data.get("claimed_pickups", {})
	var rooms = snapshot_data.get("safe_rooms", {})
	var hunter_data = snapshot_data.get("hunters", {})
	var removed_hunter_data = snapshot_data.get("removed_hunters", {})
	var drops = snapshot_data.get("dropped_items", {})
	var sabotage = snapshot_data.get("sabotaged_relays", {})
	var shared = snapshot_data.get("shared_waypoints", [])   # legacy: an array of shared waypoints
	var per_player = snapshot_data.get("waypoints", {})
	var hiding = snapshot_data.get("disabled_hiding", {})
	var doors = snapshot_data.get("room_doors", {})
	if not pickups is Dictionary or not rooms is Dictionary \
			or not hunter_data is Dictionary or not removed_hunter_data is Dictionary \
			or not drops is Dictionary or not shared is Array or not per_player is Dictionary \
			or not sabotage is Dictionary or not hiding is Dictionary or not doors is Dictionary:
		return false
	active_checkpoint = String(snapshot_data.get("active_checkpoint", ""))
	claimed_pickups = (pickups as Dictionary).duplicate(true)
	safe_rooms = (rooms as Dictionary).duplicate(true)
	hunters = (hunter_data as Dictionary).duplicate(true)
	HunterIdAliases.migrate_hunter_entries(hunters)   # snapshots saved before the hunter rename
	removed_hunters = (removed_hunter_data as Dictionary).duplicate(true)
	dropped_items = (drops as Dictionary).duplicate(true)
	next_drop_sequence = maxi(1, int(snapshot_data.get("next_drop_sequence", 1)))
	sabotaged_relays = (sabotage as Dictionary).duplicate(true)
	waypoints.adopt(per_player)
	if waypoints.by_peer.is_empty():
		waypoints.adopt_legacy(shared)
	disabled_hiding = (hiding as Dictionary).duplicate(true)
	room_doors = (doors as Dictionary).duplicate(true)
	var lights = snapshot_data.get("room_lights", {})
	room_lights = (lights as Dictionary).duplicate(true) if lights is Dictionary else {}
	var booths = snapshot_data.get("booth_ready_at", {})
	booth_ready_at = (booths as Dictionary).duplicate(true) if booths is Dictionary else {}
	carousels = {}
	var rides = snapshot_data.get("carousels", {})
	if rides is Dictionary:
		var now := Time.get_unix_time_from_system()
		for id in rides:
			if rides[id] is Dictionary:
				carousels[String(id)] = {"on": bool(rides[id].get("on", false)), "angle": float(rides[id].get("angle", 0.0)), "t0": now}
	navigation_revision += 1
	return true


func _safe_room_state(info: Dictionary) -> Dictionary:
	var room_id := String(info.get("id", ""))
	if not safe_rooms.has(room_id):
		safe_rooms[room_id] = {
			"integrity": int(info.get("max_integrity", 100)),
			"breached": false,
		}
	return safe_rooms[room_id]
