class_name NightWatchStation
extends RouteInteractable3D

## Something the player can aim at and use with the shared INTERACT action in the Night Watch security room: the monitor, the DOOR and
## LIGHT buttons on the wall panels, the desk lamp, the chair, the breaker box and the vent hatch. It is a RouteInteractable3D (the
## class the shared player controller already knows: same aim cone, range, line of sight and prompt), with no model and no rules of
## its own: the scene gives it a prompt and a callable. It is a FURNITURE kind so none of Last Route's relay or light rules apply.

var station_id := ""
## Called with the player when the interact action presses on it; returns the message to show ("" for none).
var on_activate: Callable
## Where the controller aims at, relative to this node (defaults to the node's own position).
var focus_local := Vector3.ZERO


func _init() -> void:
	kind = RouteInteractable3D.Kind.FURNITURE


func _ready() -> void:
	add_to_group("interactable")
	_interaction_focus_local = focus_local


func get_prompt() -> String:
	return "" if disabled else prompt_text


func activate(player: PlayerController3D) -> String:
	last_activation_failed = false
	if on_activate.is_valid():
		return String(on_activate.call(player))
	return ""
