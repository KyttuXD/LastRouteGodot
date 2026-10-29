class_name WaypointState
extends RefCounted

## The waypoints of a run: ONE per player, never more. Placing a new one replaces the player's old one, clearing removes
## it. Pure data (no nodes), so the host, the guests, the offline run, the save code and the validators all share it.
## See docs/WAYPOINTS.md.

## Reaching within this distance (metres, XZ) clears the waypoint.
const ARRIVAL_RADIUS := 2.0
## Longest reach of the crosshair placement.
const MAX_PLACE_RANGE := 90.0
## Host-side flood guard: a peer may change its waypoint this often (ms).
const MIN_CHANGE_INTERVAL_MSEC := 150

## peer_id (int) -> {"at": Vector2, "level": int, "peer_id": int}
var by_peer := {}


func get_for(peer_id: int) -> Dictionary:
	return (by_peer[peer_id] as Dictionary).duplicate(true) if by_peer.has(peer_id) else {}


func has_for(peer_id: int) -> bool:
	return by_peer.has(peer_id)


## Snaps to the centre of the cell, replaces whatever this peer had. Returns {"changed", "waypoint", "replaced"}.
func place(peer_id: int, at: Vector2, level: int) -> Dictionary:
	var snapped := Vector2(floori(at.x) + .5, floori(at.y) + .5)
	var replaced := by_peer.has(peer_id)
	var waypoint := {"at": snapped, "level": level, "peer_id": peer_id}
	by_peer[peer_id] = waypoint
	return {"changed": true, "waypoint": waypoint.duplicate(true), "replaced": replaced}


func clear(peer_id: int) -> bool:
	return by_peer.erase(peer_id)


func clear_all() -> void:
	by_peer.clear()


## Applies a host broadcast: a waypoint dictionary sets, an empty one clears. Returns whether anything changed.
func apply(peer_id: int, waypoint: Dictionary) -> bool:
	if waypoint.is_empty():
		return by_peer.erase(peer_id)
	if not waypoint.get("at") is Vector2:
		return false
	by_peer[peer_id] = {"at": waypoint["at"], "level": int(waypoint.get("level", 0)), "peer_id": peer_id}
	return true


## True when `position` (world XZ) is within the arrival radius of this peer's waypoint on `level`.
func reached(peer_id: int, position: Vector2, level: int) -> bool:
	var waypoint: Dictionary = by_peer.get(peer_id, {})
	if waypoint.is_empty() or int(waypoint.get("level", level)) != level:
		return false
	return position.distance_to(waypoint["at"]) <= ARRIVAL_RADIUS


## Waypoints on one level (everyone's), each tagged with "mine" for the local peer.
func on_level(level: int, local_peer_id: int) -> Array:
	var result := []
	var ids := by_peer.keys()
	ids.sort()
	for peer_id in ids:
		var waypoint: Dictionary = by_peer[peer_id]
		if int(waypoint.get("level", 0)) != level:
			continue
		var copy := waypoint.duplicate(true)
		copy["mine"] = int(peer_id) == local_peer_id
		result.append(copy)
	return result


func snapshot() -> Dictionary:
	return by_peer.duplicate(true)


## Adopts a snapshot dictionary (peer_id -> waypoint). Anything malformed is dropped; at most one per peer by construction.
func adopt(data) -> void:
	by_peer.clear()
	if not data is Dictionary:
		return
	for key in data:
		var waypoint = data[key]
		if waypoint is Dictionary and (waypoint as Dictionary).get("at") is Vector2:
			var peer_id := int(key)
			by_peer[peer_id] = {"at": waypoint["at"], "level": int(waypoint.get("level", 0)), "peer_id": peer_id}


## Old saves and snapshots kept an ARRAY of shared waypoints. Keep only the most recent one, owned by `owner_peer_id`.
func adopt_legacy(entries, owner_peer_id: int = 1) -> void:
	if not entries is Array:
		return
	for index in range((entries as Array).size() - 1, -1, -1):
		var entry = entries[index]
		if entry is Dictionary and (entry as Dictionary).get("at") is Vector2:
			by_peer[owner_peer_id] = {"at": entry["at"], "level": int(entry.get("level", 0)), "peer_id": owner_peer_id}
			return


## --- screen helpers shared by the HUD overlay and the validators ---

## Where a world point shows on screen. `behind` is true when it is behind the camera. When it is off screen (or behind) the
## result is clamped to the edge of the safe rectangle, along the direction from the screen centre, and `edge` is true.
## Returns {"position": Vector2, "edge": bool, "angle": float} (angle = direction from centre, radians).
static func screen_marker(projected: Vector2, behind: bool, viewport: Vector2, margin: float) -> Dictionary:
	var centre := viewport * .5
	var direction := projected - centre
	if behind:
		direction = -direction
		if direction.length_squared() < 1.0:
			direction = Vector2(0, 1)
	var inside := not behind and Rect2(Vector2(margin, margin), viewport - Vector2(margin, margin) * 2.0).has_point(projected)
	if inside:
		return {"position": projected, "edge": false, "angle": direction.angle()}
	if direction.length_squared() < .0001:
		direction = Vector2(0, -1)
	var half := centre - Vector2(margin, margin)
	var scale := minf(half.x / maxf(absf(direction.x), .0001), half.y / maxf(absf(direction.y), .0001))
	return {"position": centre + direction * scale, "edge": true, "angle": direction.angle()}
