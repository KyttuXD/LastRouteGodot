# Waypoints

Every player has at most ONE waypoint. Placing a new one replaces the old one, clearing removes it, reaching it clears it.
The same system runs in The Last Route and in The City (both use `src/infinite_route_test.gd`).

## Audit of the old system (what was wrong)

The first waypoint system lived only on the fullscreen map (click, or the centre crosshair of the map):

| Finding | Where | Effect |
| --- | --- | --- |
| waypoints were an ARRAY (`_map_waypoints`, `StreamedWorldState.shared_waypoints`) | `infinite_route_test.gd`, `streamed_world_state.gd` | each click added another pin and another route segment; markers and trail segments overlapped |
| online, the list was shared by the whole party (toggle by clicking near an existing one) | `toggle_shared_waypoint` | no per-player ownership, a teammate's click could remove your pin |
| the route used the map-DISCOVERED floor only (`_discovered_waypoint_path`) | `_refresh_waypoint_route` | a waypoint on floor you had not seen yet (every City street before exploring it) produced no route and no trail |
| the floor trail was always drawn, full length, a flat ribbon | `_update_waypoint_ground_trail` | trivialised navigation; at City scale a very long strip |
| arrival radius 5 cells | `WAYPOINT_ARRIVAL_RADIUS` | cleared before you were anywhere near |
| no world marker, no HUD pin, no distance | n/a | the waypoint only existed on the map |
| old saves kept the whole array (`discovery.waypoints`) | run save | restored several pins at once |

## Design

* **Data**: `WaypointState` (`src/game/waypoint_state.gd`) holds `peer_id -> {at, level}`; one entry per peer by construction.
  `StreamedWorldState.waypoints` owns it, so it rides in the world-state snapshot (late joiners and reconnects get everyone's pins).
  Offline runs use peer id 1.
* **Placement**: the `waypoint` key (default **B**, gamepad R3) places at the crosshair: the view ray is marched over the live
  floor grid and lands on the floor, or on the open floor in front of the wall or prop it hits (range 90 m). Pressing it on the
  same cell clears it. `waypoint_clear` (default **X**) clears outright. The fullscreen map still places at the map cursor.
  All paths go through `_request_waypoint`: a guest asks the host, the host (or the offline run) decides and publishes one
  `stream_waypoint` event `{peer_id, waypoint | {}}`, which every peer applies idempotently. A guest may change its pin every
  150 ms at most.
* **Display** (`src/ui/waypoint_overlay.gd`, on the HUD): a diamond over the waypoint, visible through walls, with the distance
  in metres; when off screen or behind you the pin clamps to the screen edge as an arrow. Your pin is amber, teammates' pins
  are tinted per player and labelled with their name. The crosshair area stays clear. Spectators see everyone's pins.
  The map and minimap show the same single waypoint and the route to it.
* **Guidance** (Settings > Controls > ACTIONS > WAYPOINT, `Settings.waypoint_guidance`): `off` (pin only), `arrow` (default:
  plus the edge arrow), `path` (plus small floor chevrons along the next 28 m of the route). Also: show distance, pin size,
  pin opacity, arrival chime (all in `Settings`, saved in the settings file).
* **Route**: the live navigation grid first (everything streamed in: the whole City, undiscovered maze floor), then the
  map-discovered floor as a fallback. The map line shows the full route; the floor chevrons only the next stretch.
* **Clearing**: arrival (within 2 m, soft chime unless turned off), the clear key, death (`_respawn_after_death`), leaving the
  run, and a player leaving the room (the host clears their pin). Nothing is saved across runs.
* **Noise**: waypoints make no noise and alert no hunter.
* **Admin** (permission `player`): TELEPORT TO WAYPOINT, CLEAR WAYPOINT.
* **Saves**: the Last Route run save still writes `discovery.waypoints` as a one-element array (old builds can read it); the
  single waypoint also rides in `world_state.waypoints`. A legacy save with several waypoints keeps the most recent one
  (`WaypointState.adopt_legacy`).

## Co-op

Each player owns one pin. The host validates the level of the requesting player and publishes the new state; guests only
render. A late joiner adopts the host snapshot and sees the same pins. Public routes behave the same.

## Validators

`waypoints` (`scripts/validate_waypoints.gd`): place twice gives one, replace/clear/arrival, per-player independence,
host/guest/late-joiner agreement, legacy migration, malformed data, the edge clamp at 1280x720 / 1920x1080 / 3440x1440,
controls registration and no key conflicts (B, X, R3), settings clamps, and a City run-scene pass (A then B gives only B, one
trail node, a route over open street cells, a teammate pin next to ours, arrival clears). `streamed_world` covers the Last
Route live scene (map click, GPS line, chevrons, replace, arrival).
