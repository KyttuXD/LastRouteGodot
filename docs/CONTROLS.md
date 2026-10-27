# Controls by game

The CONTROLS section of the settings is game-aware. `ControlsRegistry` (`src/config/controls_registry.gd`) holds, per game id,
the tabs and the rebindable actions each tab shows; the settings panel shows the tabs of the game that is open
(`GameRegistry.active_game_id`, set when the hub launches a game).

- **Last Route:** MOVEMENT, ACTIONS, SYSTEM. No OFFICE tab, no office wording anywhere in its settings.
- **Night Watch:** registers an OFFICE tab (left door, right door, desk light, vent hatch, monitor, radio, breaker, camera reboot,
  emergency flash, rear flash). A default registration exists so those actions have an owner; the Night Watch lane replaces it:

```gdscript
ControlsRegistry.register("night_watch", [
	{"title": "OFFICE", "actions": ["office_left_door", "office_right_door", "office_desk_light", "office_vent", ...]},
	{"title": "CAMERAS", "actions": [...]},          # more tabs are fine
])
```

Rules: an action appears on one tab of one game only; every action in `Settings.REBINDABLE_ACTIONS` must be owned by some game
(otherwise it would show under OTHER); a game opens its settings with `GameRegistry.active_game_id = "<id>"`.

Registering only decides what is shown. The office actions stay in the InputMap, in `Settings.REBINDABLE_ACTIONS` and in the
settings file's `[controls]` section, so saved office rebinds keep loading and saving; Last Route simply never shows or reads
them (nothing in Last Route reacts to an `office_*` action, so A/D and the other shared physical keys cannot clash with its
movement keys, and the settings have no key-conflict detection that could have treated them as clashes).

The `controls` validator checks the registry shape, that Last Route's real settings panel shows exactly three tabs with no
OFFICE text, and that an office rebind round-trips through save and load.
