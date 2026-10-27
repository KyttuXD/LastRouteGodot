# The sewer under the maze

Last Route is one maze level (0) over a sewer and waterworks level (-1). Both stream on the same 45 x 45 chunk
coordinates from the same seed, so every peer builds the same tunnels, ladders and pickups.

## Layout (`src/game/sewer_route_generator.gd`)

* **Main cross.** Every sewer chunk has a nine-wide brick tunnel along x = 22 and z = 22, so tunnels always meet
  across chunk seams. Each tunnel is a three-wide dry walkway, a three-wide channel of shallow flowing water, and
  another three-wide walkway. The tunnels cross in a 13 x 13 junction chamber.
* **Water is wading only.** It is never deep and nobody drowns. A runner in it moves at 0.55x
  (`PlayerController3D.WADE_SPEED_SCALE`) and makes 1.6x the noise. Hunter A* weights water cells 2.5x, so hunters keep
  to the walkways. Three-wide footbridges (grates) cross the channel at regular spacing, so a dry walker reaches
  everything without wading (validated).
* **Utility rooms.** One or two quadrants of each chunk hold a pump room, a valve room or an overflow chamber
  (9 x 9, with a central basin and a barred weir). Each sits on a three-wide dry branch to the tunnel. Each has one
  hiding spot.
* **Pickups.** Relays and batteries, sometimes a tool. They spawn on dry cells only, never by a ladder, and slightly
  thinner than the maze.
* **Look.** The `sewer` district in RefLook/FloorSets/RefDecor: brick walls, worn stone walkways, a fixed 3.2 m
  vault, dim caged amber lamps (`sewerLamp`) and pipe runs on the walls. The flowing water is
  `src/look/sewer_water.gdshader`.
* **Sound.** One-shot `Sound.sewer_drip / sewer_gurgle / sewer_rat` cues around a runner in the sewer, a
  `sewer_splash` per wading stride, and a `ladder_rung` clank per rung while climbing.

## Ladders (the only way between the levels)

Every entrance is a `LevelLink` (`src/game/level_link.gd`) of kind `ladder`, with `cover` set to `manhole` (a lid
dragged aside) or `grate` (a floor grate swung up).

* The top end is an open, prop-free maze hallway cell with a clear 3 x 3 around it.
* The bottom end is a dry 3 x 3 shaft chamber in the sewer. The rungs hang on solid brick (`link.wall`) on the side
  away from the tunnel.
* The maze keeps its walkable collider over the opening but draws no floor there. It lines the shaft in brick down to
  the sewer vault, and the sewer leaves its vault open under it.
* About 55 % of chunks have a ladder (the origin chunk always does), and a ladder usually leads up into a different
  chunk from where you went down.

**Runner.** Step onto the ladder cell, or press E within 1.4 cells, to climb.

* The climb is a smooth 2.4 s glide over the storey. The body plays `climb`, which guests see through the
  replicated clip and transform. The first-person view shows two blocky fists working the rungs.
* Movement, items and collision are off while you climb.
* The level switches halfway up, with hysteresis. That gives the short vulnerable window: a hunter at either end can
  grab you over that half of the climb.
* Once you're off, the ladder re-arms only after you step away, so arriving at the top doesn't send you straight back
  down.

**Hunters** (`InfiniteRouteTest._hunter_ladder_step`, `LadderTraffic`):

* When the runner a hunter was chasing or investigating turns up on the other level, she walks to the nearest ladder
  (`HunterBrain.head_to`) and climbs it. On arrival she resumes the chase where the runner went.
* While climbing she plays her `climb` clip (alternating hands and feet) with collision off. Her climb speed scales
  with her base speed (`LadderTraffic.climb_seconds_for_speed`).
* Only one climber is on a ladder at a time, so others wait at the ladder.
* A hunter on a ladder never grabs anyone.
* Guests show the host's climb from the replicated `climbing` / `presentation_y` / `climb_yaw`.

### Sewer affinity (KT tunes these lists in `HunterRoster`)

| group | hunters | behaviour |
| --- | --- | --- |
| prefer (stalkers, ambushers) | Verrine, Umbriel, Wynelle, Glyra, Loxelle, Ravelle | follow a runner down or up, and also drift down a nearby ladder on their own while idle or wandering |
| avoid | Kathy, Ferryn, Solyth, Porcelle | follow the runner to the ladder and wait at the top (30 s) to ambush them coming back up; never climb |
| follow (everyone else, Void included) | the rest | follow a runner down or up, never climb on their own |

## Streaming

`StreamedFacilityView3D` loads the 3 x 3 window on the runner's level. When the runner's chunk has a ladder, it also
loads the chunk at the other end of it, so a shaft never opens onto nothing.

`snapped_level_for_world_y` puts the runner in the sewer once their feet are more than half a storey below the maze
floor. The minimap only shows the level you are on: in the sewer it draws the sewer, its water, and ladder icons
pointing up (and on the maze, down).

## Props (authored, `tools/props/rebuild_hytale_props.py` SEWER_BUILDERS -> `art/props-3d/props/sewer/`)

`sewerLadder`, `sewerLadderTop`, `sewerManhole`, `sewerFloorGrate`, `sewerValveWheel`, `sewerPump` (solid),
`sewerPipeRun`, `sewerOverflowGrate`, `sewerLamp`.

Build them with:

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/props/rebuild_hytale_props.py -- sewer

## Validator

`sewers` (`scripts/validate_sewers.gd`) checks:

* every sewer chunk is deterministic;
* every dry cell sits in a 3 x 3 dry block;
* every link is a covered ladder with a ladder at its foot and brick behind its rungs;
* lids sit on open, prop-free maze floor;
* every ladder is reachable on dry walkways;
* every ladder reaches every other one below;
* one climber per ladder;
* hunter A* routes between ladders below and to every lid above;
* the view streams the sewer window, keeps the maze collider over the shaft, and stays inside the streaming frame
  budget;
* a runner climbs down and back up (smoothly, ending on the far floor, collision restored).
