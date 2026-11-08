# Controls by game

The CONTROLS section of the settings is game-aware. `ControlsRegistry` (`game/config/controls_registry.gd`) holds, per game id,
the tabs and the rebindable actions each tab shows; the settings panel shows the tabs of the game that is open
(`GameRegistry.active_game_id`, set when the hub launches a game).

- **Last Route:** MOVEMENT, ACTIONS, SYSTEM. No OFFICE tab, no office wording anywhere in its settings.
- **Night Watch:** registers an OFFICE tab (left door, right door, desk light, vent hatch, monitor, radio, breaker, camera reboot,
  emergency flash, rear flash). A default registration exists so those actions have an owner; Night Watch replaces it:

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

## Default bindings

Fresh installs use the `[input]` map in `project.godot`. Settings can replace or add keyboard and mouse bindings for
every action in `Settings.REBINDABLE_ACTIONS`. A rebind moves that key off any other action in the same live group
(Last Route gameplay, or the office actions). Gamepad bindings stay on the action. The player-facing one-pager is
[QUICK_START.md](QUICK_START.md).

Glyph names below are what Godot prints for the default events (`QuoteLeft` is the `` ` `` key, `Slash` is `/`).

### Last Route

| Action | Settings label | Keyboard / mouse | Gamepad |
| --- | --- | --- | --- |
| `move_up` / `move_left` / `move_down` / `move_right` | MOVE UP / LEFT / DOWN / RIGHT | W A S D | Left stick |
| `look_up` / `look_left` / `look_down` / `look_right` | LOOK UP / LEFT / DOWN / RIGHT | I J K L, and the arrow keys | Right stick |
| `sprint` | SPRINT | Shift (hold) | Left-stick click (L3) |
| `crouch` | CROUCH | C (hold) | B |
| `jump` | JUMP / HOP | Space | A |
| `interact` | INTERACT | E, right click | X |
| `tool_use` | USE HELD TOOL | Left click | Right trigger |
| `flashlight` | FLASHLIGHT | F | RB |
| `taser` | TASER | G | LB |
| `inventory` | INVENTORY | Tab | Y |
| `drop_item` | DROP HELD ITEM | Q | D-pad down |
| `chat` | ROOM CHAT | T, Slash (`/`) | none |
| `toggle_map` | TOGGLE MAP | M | View |
| `player_list` | PLAYER LIST (HOLD) | O (hold) | none |
| `pause` | PAUSE | Escape, P | Menu |

These are read in code and are not Settings rows:

| What | Default | Where |
| --- | --- | --- |
| Hotbar slots 1–5 | Physical keys `1`–`5` | `PlayerController3D._unhandled_input` |
| Cycle the five-slot hotbar | Wheel up / wheel down | same |
| Gamepad hotbar | D-pad left / D-pad right (`hotbar_previous`, `hotbar_next`) | InputMap; not rebindable |
| Quick chat | `` ` `` (`quick_chat`, QuoteLeft) and D-pad up | InputMap; `RoomChat` registers it if the action is missing; rebindable (ACTIONS tab) |
| Push to talk | `X` (`push_to_talk`) and right stick click | created by `VoiceChat.ensure_actions()` (Settings registers it before capturing defaults); rebindable (ACTIONS tab) |
| Gameplay HUD | F1 | `HUD._input` |
| Fullscreen | F11 (`toggle_fullscreen`) | `Settings._unhandled_input`; not rebindable |

Phone buttons (`TouchControls`) press the same actions: USE, JUMP, DUCK, LIGHT, TOOL, `<` `>`, BAG, MAP, CHAT, QUICK, and
II (pause). Movement is the D-pad (double-tap an arrow and hold to sprint) or the floating stick when `touch_move` is
`stick`.

### Night Watch office

Shown on the OFFICE tab, never on Last Route. The camera keys `office_camera_1` … `office_camera_8` stay on `1`–`8`
and are not in `REBINDABLE_ACTIONS`.

| Action | Default key |
| --- | --- |
| Left door, right door | A, D |
| Desk light | L |
| Vent hatch | V |
| Monitor | C |
| Radio | R |
| Breaker | B |
| Camera reboot | N |
| Emergency flash | F |
| Rear flash | Q |
| Cameras 1–8 | `1`–`8` (fixed) |
