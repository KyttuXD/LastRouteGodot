class_name ReviveDowns
extends RefCounted

## Co-op revives (docs/REVIVE.md). A caught co-op runner is "down" where they were caught for
## GameConfig.REVIVE_WINDOW_SECONDS while they spectate; a teammate carrying a Revive Kit holds [E] at that spot for
## REVIVE_HOLD_SECONDS and they are back. The host owns every record: it notes the down (where the hunter took them),
## times each hold from its start request, checks the finish (kit, floor, range, window, still spectating) and
## publishes the result; every peer keeps the same records from those events to draw the markers and the prompts.
## Lives in StreamedWorldState (`downs`), so a late joiner's snapshot carries the open windows.

## Seconds a hold may finish early, for the start request's trip to the host.
const HOLD_SLACK := .4
## Metres past REVIVE_RANGE the host still accepts (the reviver's samples lag a little).
const RANGE_SLACK := .6

## peer id -> {"at": Vector3, "depth": int (as a runner state's "depth"), "left": float, "name": String, "by": int (reviving now, 0 none)}
var downs := {}
## host only: reviver peer id -> {"peer": downed peer id, "since": seconds}
var holds := {}


func down(peer: int, at: Vector3, depth: int, display_name: String,
		left: float = GameConfig.REVIVE_WINDOW_SECONDS) -> void:
	downs[peer] = {"at": at, "depth": depth, "left": left, "name": display_name, "by": 0}


func is_down(peer: int) -> bool:
	return downs.has(peer) and float(downs[peer]["left"]) > 0.0


func clear(peer: int) -> void:
	downs.erase(peer)
	for reviver in holds.keys():
		if int(holds[reviver]["peer"]) == peer:
			holds.erase(reviver)


func clear_all() -> void:
	downs.clear()
	holds.clear()


## Counts every window down; returns the peers whose window just closed (they stay spectating).
func tick(delta: float) -> Array:
	var closed := []
	for peer in downs.keys():
		downs[peer]["left"] = float(downs[peer]["left"]) - delta
		if float(downs[peer]["left"]) <= 0.0:
			closed.append(peer)
	for peer in closed:
		clear(int(peer))
	return closed


func set_reviver(peer: int, by: int) -> void:
	if downs.has(peer):
		downs[peer]["by"] = by


## Why the host refuses `reviver` (its replicated state) reviving `peer` now, or "" when it may. `finishing` also
## needs a hold started at least REVIVE_HOLD_SECONDS ago. `downed_spectating`: the downed peer's own state agrees it is
## out (a stale record never pulls a living runner across the map).
func refusal(reviver: int, peer: int, reviver_state: Dictionary, downed_spectating: bool, now: float,
		finishing: bool) -> String:
	if not is_down(peer):
		return "window"
	if reviver == peer:
		return "self"
	if not downed_spectating:
		return "not_down"
	if bool(reviver_state.get("spectating", false)) or bool(reviver_state.get("game_over", false)):
		return "reviver_down"
	if not _carries_kit(reviver_state):
		return "no_kit"
	var record: Dictionary = downs[peer]
	var at = reviver_state.get("at")
	if not at is Vector3 or int(reviver_state.get("depth", 999999)) != int(record["depth"]) \
			or Vector2((at as Vector3).x, (at as Vector3).z).distance_to(
				Vector2((record["at"] as Vector3).x, (record["at"] as Vector3).z)) > GameConfig.REVIVE_RANGE + RANGE_SLACK:
		return "range"
	if finishing:
		var hold: Dictionary = holds.get(reviver, {})
		if hold.is_empty() or int(hold["peer"]) != peer \
				or now - float(hold["since"]) < GameConfig.REVIVE_HOLD_SECONDS - HOLD_SLACK:
			return "hold"
	return ""


func start_hold(reviver: int, peer: int, now: float) -> void:
	holds[reviver] = {"peer": peer, "since": now}
	set_reviver(peer, reviver)


func stop_hold(reviver: int) -> int:
	var hold: Dictionary = holds.get(reviver, {})
	holds.erase(reviver)
	if hold.is_empty():
		return 0
	var peer := int(hold["peer"])
	if downs.has(peer) and int(downs[peer]["by"]) == reviver:
		downs[peer]["by"] = 0
	return peer


static func _carries_kit(state: Dictionary) -> bool:
	var owned = state.get("owned_items", {})
	if owned is Dictionary and bool((owned as Dictionary).get("revive_kit", false)):
		return true
	var order = state.get("inventory_order", [])
	return order is Array and (order as Array).has("revive_kit")


func snapshot() -> Dictionary:
	var out := {}
	for peer in downs:
		out[str(peer)] = (downs[peer] as Dictionary).duplicate()
	return out


func adopt(data) -> void:
	downs.clear()
	holds.clear()
	if not data is Dictionary:
		return
	for key in data:
		var record = data[key]
		if record is Dictionary and record.get("at") is Vector3:
			down(int(key), record["at"], int(record.get("depth", 0)), String(record.get("name", "")),
				clampf(float(record.get("left", 0.0)), 0.0, GameConfig.REVIVE_WINDOW_SECONDS))
