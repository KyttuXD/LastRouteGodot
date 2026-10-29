class_name ControlsRegistry
extends RefCounted

## Which rebindable actions each game shows on its CONTROLS settings tabs. A game registers its own tabs; the settings panel
## shows the active game's tabs only, so Last Route has MOVEMENT / ACTIONS / SYSTEM and Night Watch registers an OFFICE tab.
##
##   ControlsRegistry.register("night_watch", [{"title": "OFFICE", "actions": ["office_left_door", ...]}])
##   ControlsRegistry.tabs_for("night_watch")   # -> Array of {title, actions}
##
## Registering only decides what is SHOWN. Every action stays in Settings.REBINDABLE_ACTIONS and in the settings file, so a
## player's saved rebinds (including office ones) survive and round-trip even when the game that owns them is not the one
## open. An action may appear on one tab of one game only (the `controls` validator checks).

const LAST_ROUTE_TABS := [
	{"title": "MOVEMENT", "actions": ["move_up", "move_down", "move_left", "move_right", "look_up", "look_down",
		"look_left", "look_right", "sprint", "crouch", "jump"]},
	{"title": "ACTIONS", "actions": ["interact", "flashlight", "taser", "tool_use", "inventory", "drop_item", "chat", "toggle_map", "player_list"]},
	{"title": "SYSTEM", "actions": ["pause"]},
]

## Night Watch's default tab, so its (hidden from Last Route) office actions have an owner until the Night Watch lane
## replaces this with its own registration.
const NIGHT_WATCH_TABS := [
	{"title": "OFFICE", "actions": ["office_left_door", "office_right_door", "office_desk_light", "office_vent", "office_cameras",
		"office_radio", "office_breaker", "office_reboot", "office_emergency_flash", "office_rear_flash"]},
]

## Games that show another game's tabs (the City plays like Last Route and shares its controls); the validator counts an
## action's owner once, so an alias is not a second owner.
const ALIASES := {}

static var _tabs := {}


static func _ensure_defaults() -> void:
	if _tabs.is_empty():
		_tabs["last_route"] = LAST_ROUTE_TABS.duplicate(true)
		_tabs["night_watch"] = NIGHT_WATCH_TABS.duplicate(true)


## Replaces a game's tabs (call once when the game starts or from its registry entry).
static func register(game_id: String, tabs: Array) -> void:
	_ensure_defaults()
	_tabs[game_id] = tabs.duplicate(true)


static func tabs_for(game_id: String) -> Array:
	_ensure_defaults()
	return (_tabs.get(ALIASES.get(game_id, game_id), _tabs["last_route"]) as Array).duplicate(true)


static func game_ids() -> Array:
	_ensure_defaults()
	return _tabs.keys()


## Every action some game shows; the rest (if any) go under OTHER on the active game's last tab.
static func registered_actions() -> Dictionary:
	_ensure_defaults()
	var out := {}
	for game_id in _tabs:
		for tab in _tabs[game_id]:
			for action in tab["actions"]:
				out[String(action)] = String(game_id)
	return out
