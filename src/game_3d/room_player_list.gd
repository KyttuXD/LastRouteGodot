class_name RoomPlayerList
extends RefCounted

## The rows of the active-room player list (hold O in a run, the pause menu's PLAYERS tab, the staging screen): name, ping, status,
## floor, host badge, voice-talking. Pure data from plain dictionaries, so the layout and the live updates are testable without a network.
##
##   roster   RoomState.roster_rows(): [{id, name, host, you}]
##   states   RemotePlayers' replicated state per peer id: {depth, spectating, game_over, escape_active, received_usec}
##   local    the same fields for this player (GameState)
##   pings    {peer_id: ms} as the host measured and broadcast them
##   talking  {peer_id: true} while a peer's voice is playing (empty with voice chat off)
##   can_pulse  the viewer is an admin with the visual permission: other players get a pulse button

const STATUS_ALIVE := "ALIVE"
const STATUS_CAUGHT := "CAUGHT"
const STATUS_SPECTATING := "SPECTATING"
const STATUS_DISCONNECTED := "DISCONNECTED"
const STATUS_LOBBY := "IN LOBBY"
## A peer whose state has been quiet this long is shown as disconnected (the host drops them from the roster a little later).
const QUIET_DISCONNECT_USEC := 8_000_000


static func build(roster: Array, states: Dictionary, local: Dictionary, pings: Dictionary, talking: Dictionary,
		can_pulse: bool, now_usec: int, in_run: bool = true) -> Array:
	var rows: Array = []
	for entry in roster:
		var id := int(entry.get("id", 0))
		var you := bool(entry.get("you", false))
		var state: Dictionary = local if you else states.get(id, {})
		var status := STATUS_LOBBY
		var floor_value = null
		if in_run:
			status = _status(state, you, now_usec)
			if state.has("depth"):
				floor_value = -int(state["depth"])
		rows.append({
			"id": id, "name": String(entry.get("name", "?")), "host": bool(entry.get("host", false)), "you": you,
			"ping": -1 if (not pings.has(id) and not you) else int(pings.get(id, 0)),
			"status": status, "level": floor_value,
			"talking": bool(talking.get(id, false)),
			"can_pulse": can_pulse and not you and status != STATUS_DISCONNECTED,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["host"] != b["host"]:
			return a["host"]
		return String(a["name"]) < String(b["name"]))
	return rows


static func _status(state: Dictionary, you: bool, now_usec: int) -> String:
	if state.is_empty():
		return STATUS_ALIVE   # on the roster but no state packet yet: just joined
	if not you and now_usec - int(state.get("received_usec", now_usec)) > QUIET_DISCONNECT_USEC:
		return STATUS_DISCONNECTED
	if bool(state.get("spectating", false)):
		return STATUS_SPECTATING
	if bool(state.get("game_over", false)) or bool(state.get("escape_active", false)):
		return STATUS_CAUGHT
	return STATUS_ALIVE


static func floor_text(level) -> String:
	return "-" if level == null else "%+d" % int(level)


static func ping_text(ping: int) -> String:
	return "-" if ping < 0 else "%d MS" % ping
