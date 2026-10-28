class_name Breach
extends RefCounted

## The shared breakable-thing API (stream_breach): seals across a sealed wing, loose boards and burst-able pipes all go
## through here. A chunk lists its breakables as specs in data["breakables"]; the view makes an interactable for each; a tool
## swing at one asks the host (guests ask by "stream_breach_request"), the host applies the damage to
## StreamedWorldState.breaches and publishes "stream_breach" to everyone; every machine then updates the piece and calls the
## hooks below, so a feature can react (SEWER floods on a burst pipe, hunters come to the noise).
##
## Spec (Breach.make_spec): {id, kind, variant, chunk, cell, hp, tools, locked, extras}.
##   id       "BRK:<x>:<y>:<z>:<index>", found again by StreamedRouteGenerator.breakable_by_id(id)
##   kind     KIND_SEAL / KIND_BOARD / KIND_PIPE
##   variant  the themed form ("chainedGate", "crackedWall", "boardedDoorway", "pipe", ...), the view picks its look by it
##   hp       hit points; each committed swing deals TOOL_DAMAGE[tool] (a lockpick opens a locked door in one go)
##   tools    which tools can work it (SealRules.seal_tools for seals); swing cost comes from PlayerController3D.TOOL_SWING_COST
##   extras   free-form data for the feature that owns it (a pipe's flood radius, a seal's wing id, ...)
##
## Hooks (Breach.connect_hook(event, kind, callback); kind "" = every kind; Breach.clear_hooks() on teardown):
##   "hit"      callback(event) after any accepted swing: hp left, tool, world position
##   "breached" callback(event) once, when hp reaches 0 and the thing opens, on EVERY machine (host and guests)
## event: {id, kind, variant, level, chunk, cell, position (Vector3), hp, max, opened, tool, by (peer id)}

const KIND_SEAL := "seal"
const KIND_BOARD := "board"
const KIND_PIPE := "pipe"
const KINDS := [KIND_SEAL, KIND_BOARD, KIND_PIPE]

## Hit points a committed swing takes off: the axe splits two boards a chop, the crowbar pries one.
const TOOL_DAMAGE := {"rescue_axe": 2, "crowbar": 1, "lockpick": 1}
## Loud enough to draw hunters: seconds they investigate after a breach (SealRules.INVESTIGATE_SECONDS for seals).
const NOISE_LEVEL := {"rescue_axe": 18.0, "crowbar": 12.0, "lockpick": 3.0}

static var _hooks := {}


static func make_spec(id: String, kind: String, variant: String, chunk: Vector3i, cell: Vector2i, hp: int, tools: Array,
		extras: Dictionary = {}, locked: bool = false) -> Dictionary:
	return {"id": id, "kind": kind, "variant": variant, "chunk": chunk, "cell": cell, "hp": maxi(1, hp),
		"tools": tools.duplicate(), "locked": locked, "extras": extras.duplicate(true)}


static func make_id(chunk: Vector3i, index: int) -> String:
	return "BRK:%d:%d:%d:%d" % [chunk.x, chunk.y, chunk.z, index]


## The chunk and index inside an id, or an empty Dictionary for a malformed one.
static func parse_id(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts.size() != 5 or parts[0] != "BRK":
		return {}
	return {"chunk": Vector3i(int(parts[1]), int(parts[2]), int(parts[3])), "index": int(parts[4])}


static func accepts(spec: Dictionary, tool: String) -> bool:
	return (spec.get("tools", []) as Array).has(tool)


## Hit points this swing takes off (0 when the tool cannot work it). A lockpick on a locked door opens it outright.
static func damage_for(spec: Dictionary, tool: String, hp_now: int) -> int:
	if not accepts(spec, tool):
		return 0
	if tool == "lockpick":
		return hp_now if bool(spec.get("locked", false)) else 0
	return int(TOOL_DAMAGE.get(tool, 0))


static func swing_cost(tool: String) -> int:
	return int(PlayerController3D.TOOL_SWING_COST.get(tool, 1))


static func connect_hook(event: String, kind: String, callback: Callable) -> void:
	var key := "%s|%s" % [event, kind]
	if not _hooks.has(key):
		_hooks[key] = []
	if not (_hooks[key] as Array).has(callback):
		(_hooks[key] as Array).append(callback)


static func clear_hooks() -> void:
	_hooks.clear()


static func dispatch(event: String, payload: Dictionary) -> void:
	for key in ["%s|" % event, "%s|%s" % [event, String(payload.get("kind", ""))]]:
		for callback in (_hooks.get(key, []) as Array):
			if (callback as Callable).is_valid():
				(callback as Callable).call(payload)
