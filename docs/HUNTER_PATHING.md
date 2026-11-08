# Hunter pathing and stuck detection

Hunters move on the streamed 2D grid (`StreamedHunterNavigation`: structural walls plus solid props, 8-way A*), and
`HunterView3D` only presents that simulated position. A hunter that "walks in place" is therefore a simulation that
asked to move and did not, or a view playing a walk clip for a body that is not moving.

## Real-play failures found (and fixed)

| Symptom | Cause | Fix |
| --- | --- | --- |
| Visible chase pinned on a jamb, wall edge or prop corner | Direct chase trusted a zero-width line of sight, but the body has a 0.33-cell radius (`GameConfig.HUNTER_RADIUS`) and the branch never tracked progress | Charge straight only if the whole capsule sweep is clear (`_clear_sweep`), otherwise follow the A* route; progress tracking also runs while charging |
| Hunter stands forever with an INVESTIGATE/CHASE goal | Goal outside the streamed 3x3 window or inside geometry: A* returns no route and the hunter just returned | Walk toward the nearest reachable point on the way; after 1.6 s give the goal up and SEARCH |
| SEARCH stands still | Search points were chosen by "nearest open cell", which can lie behind a wall | Search points must have an A* route from the hunter |
| Walk or chase clip plays without displacement | The clip followed the state only | `HunterView3D` drops to idle after 0.35 s of near-zero speed |

Haelith is the one intended stand-still: she sits on the uncollected relay she reached.

## Telemetry

`HunterBrain.stuck_seconds` counts seconds a non-idle, non-stunned, non-emoting, non-held hunter moved less than
0.004 cells per tick. The admin ROUTE DEBUG hunter list appends `STUCK 2.4s` once it reaches 1 s.

## Validator

`hunter_real` (tests/validate_hunter_real.gd) drives the real `HunterBrain.update()` on real generated chunks
(props, every district, 2 seeds) for all 26 A-Z and 12 Void hunters at their real speeds, in a visible-chase mode
(a runner walking a route in sight, Verrine with an active vent) and a no-target patrol mode. Any hunter standing
still in a walking/chasing state for more than 1 s fails it. `hunter_nav` keeps the long abstract trips.

## Hunters never fall (FALL FIX)

Hunters are grid simulations; their presentation body (`HunterView3D`, a `CharacterBody3D`) used to fall under gravity and
only caught itself 4 m below the floor. A hunter on a chunk with no loaded floor collider (far hunters, a chunk still
streaming, a chunk freed under her, a guest that has not built the host's chunk) dropped through the map and snapped back
to odd places. Now:

* the body's height is the level floor height (or the authored stair ramp), approached at 14 m/s; there is no gravity.
  Collision stays only for the planar slide against walls that are loaded;
* if a body is ever more than 1 m below its floor it is put back and `HunterBrain.fall_recoveries` counts it; the admin
  hunter list shows `RECOVERED xN`. The playtest bridge can read the counter from the brain;
* other bodies: pickups, dropped items and props are not physics bodies (positions come from cells), players only exist
  inside the loaded window, and remote hunters on guests use the same view, so they follow the host position on the floor.

Validator `hunter_fall`: all 38 hunters walk 60 simulated seconds 60 chunks from any floor collision (min y stays above
-0.2 m, no recoveries, they keep progressing), a hunter whose collider is freed mid-walk stays up, and a body pushed below the
floor is recovered and counted. It fails on the old gravity code (hunters reached y = -3.9).
