# The sewer under the maze

Last Route is one maze level (0) over a sewer and waterworks level (-1). Both stream on the same 45 x 45 chunk
coordinates from the same seed, so every peer builds the same tunnels, ladders and pickups.

## The stack

| level | what | how you reach it |
| --- | --- | --- |
| 0 | the maze (every district but the Inferno) | spawn |
| -1 | the sewer | ladders from the maze |
| -2 | the collector: a second sewer, same tunnels and decks, its own rooms, no ladders | ramp tunnels from -1 |
| -3 | the Inferno: a full maze level of Inferno districts, and the only place they appear | ramp tunnels from -2 |

**Ramps** (`SewerRouteGenerator.ramp_between`, LevelLink kind `ramp`) are the seamless link down. Each is a walled,
three-wide tunnel that drops one storey over `RAMP_RUN` (12) cells, about 18 degrees, in one quadrant of a chunk that
both levels reserve (about 35 % of chunks for -1 to -2, 30 % for -2 to -3).

* The top landing sits beside the upper level's tunnel walkway. The bottom landing joins the lower level's tunnels, or
  in the Inferno its central hall; any room the footprint would cut through is dropped.
* You walk it; the level switches on height with no loading break. The upper chunk owns the slope's collider and
  surface. On the lower level the tunnel opens straight up, so its walls run the full storey.
* Hunters walk a ramp as a timed link (walk clip, height and position following the slope), with the same follow and
  avoid rules as ladders. Runners only climb ladders.
* The map shows ramps with the stair icon.
* Below the maze every storey is capped to `LEVEL_HEIGHT` - slab, so tall Inferno halls never rise into the sewer
  above.

**Falls** (`SewerRouteGenerator.falls_between`): the first sewer feeds the collector. In about 28 % of chunks, in a
quadrant no ramp uses:

* On -1 a spur leaves the main channel, crosses the tunnel walkway on a bridge, and runs beside a railed overlook ledge
  to a 7 x 7 drop. The floor is gone there, the drop's cells block movement like the channels, and rough stone cliffs
  fall a full storey.
* The water pours over the lip as a waterfall sheet (`sewer_falls.gdshader`) into an 11 x 12 cistern on -2. The
  cistern has a deep pool under the drop, mist where the falls land, and a walkway ring joined to the collector's
  tunnel. The cistern is open overhead to the drop.
* A looping positional roar (`Sound` cue `waterfall`) carries about 28 m on both levels. Within about 7-13 m of a lip
  it masks a runner's noise for the hunters (`InfiniteRouteTest._falls_noise_mask`).
* In a falls chunk the other sewer level stays loaded, so you can see across the drop.
* There's no jump-down shortcut: the drop is railed and blocked.

## Layout (`src/game/sewer_route_generator.gd`)

* **Main cross.** Every sewer chunk has a nine-wide brick tunnel along x = 22 and z = 22, so tunnels always meet
  across chunk seams. Each tunnel is a three-wide dry walkway, a three-wide channel of deep flowing water, and
  another three-wide walkway. The tunnels cross in a 13 x 13 junction chamber.
* **Deep water, never entered.** The channel is a brick trench: its bed lies 1 m below the walkways
  (`SewerRouteGenerator.CHANNEL_DEPTH`) and the water surface 0.3 m below them (`WATER_SURFACE`). Iron railings line
  every edge where a walkway, room floor or deck meets open water. The channel cells carry a collider from the bed to
  1.2 m above the walkways, so runners and hunters stay out of the water. Channel cells are blocked in the grid, so
  hunter A* never routes through the water (validated).
* **Crossings.** Sparse on purpose: one 3 x 3 m riveted bridge deck (`sewerBridge`) on each tunnel arm either side of
  the junction (`BRIDGE_OFFSETS`, about one every 24 m), spanning the channel on two girders that bear on the walkways.
  The junction's confluence is open water: the channels meet with no deck over them, and the arm bridges join all
  four walkway quadrants around it. The water keeps flowing under every bridge, visible through the grating
  (validated: every dry cell reachable, hunters never route through water).
* **Utility rooms.** One or two quadrants of each chunk hold a pump room or a valve room (7 x 7). Rooms reserve
  their cells: no channel, basin, deck, railing or falls lip inside one (validated on -1 and -2; the overflow
  chamber's railed basin read as the channel through a room and was retired). Each sits on a three-wide dry branch to the tunnel. Each has one
  hiding spot.
* **Pickups.** Relays and batteries, sometimes a tool. They spawn on dry cells only, never by a ladder, and slightly
  thinner than the maze.
* **Look.** The `sewer` district in RefLook/FloorSets/RefDecor: brick walls, worn stone walkways, a fixed 3.2 m
  vault with a plain damp-concrete ceiling (the `vault` ceiling texture, not the maze's coffered beam grid, whose
  1 m beams read as a dense lattice of crosses overhead), dim caged amber lamps (`sewerLamp`) and pipe runs on the
  walls. Every wall-mounted piece (valve wheels, lamps, pipe runs, the pump) has brick directly behind it. A piece whose
  planned wall turned into a doorway or passage slides along the wall to the nearest backed cell, or is left out
  (`_mount_on_walls`; validated: nothing floats). The flowing water is
  `src/look/sewer_water.gdshader`. It reads the depth buffer, so thin water at the trench edges stays see-through and
  greenish while the middle of the channel goes dark and opaque.
* **Sound.** The shared `sewer` ambience bed (AmbienceTable: water swell, drips, rats). Bridges and the plaza record
  the `grate` floor kind, so footsteps on them ring metallic. While climbing,
  `Sound.ladder_rung` clanks once per rung.

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

**Runner.** Step onto the ladder cell, or press E within 1.4 cells, to get on. You mount smoothly at the end you came from
(`PlayerController3D.begin_ladder_climb`), then climb under your own control:

* Hold move up (W / stick forward) to climb up, or move down (S / stick back) to climb down, at a steady
  `LADDER_CLIMB_SPEED` (1.7 m/s). Release to hang still, silent, anywhere on the rungs.
* Keep climbing past either end and you step off smoothly onto the floor in front of the ladder: over the lip of the
  hatch at the top, onto the shaft chamber floor at the bottom. Jump within `LADDER_LET_GO_HEIGHT` of the bottom to let
  go.
* The camera stays free to look around. Movement, items and collision are off on the rungs. The body plays `climb`
  (paused while you hang), which guests see through the replicated clip and transform. The first-person view shows two
  blocky fists working the rungs. The rungs clank only while you move.
* The level switches halfway up, with hysteresis. That gives the vulnerable window: a hunter at either end can grab
  you over that half of the climb, and hanging there is a risk.
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

## Stairwells (`src/game/stairwells.gd`)

Enclosed stairwells, `LevelLink` kinds `stairs` (a switchback: two 2 m half-flights about a 180 degree mid landing,
in a 7 x 9 box) and `spiral` (a helix round a central post, 270 degrees per storey, in a 7 x 7 box). Both enter and
leave by the same doorway on both levels; the bottom and top landings are the same cell one storey apart. Each link
carries a `path` that hunters walk (`LadderTraffic.path_point`) and the validator walks with the movement keys.

* **0 <-> -1 (sparse, 12%).** Placed by the maze chunk itself, which is the source of truth: the sewer and
  `vertical_links` read it from there, as they read ladders. Every maze region runs main halls along rows 9-11 and
  33-35 and the sewer's cross tunnel fills 18-26, so the box goes in an outer room band (`Stairwells.MAZE_AREAS`,
  rows 0-8 / 36-44, inside one room column, clear of the sewer walkways) with its doorway opening onto a main hall.
  A candidate must fit the maze as built: no suite or main hall touched, at most 100 cells of plain rooms dropped, and
  a trial carve that cuts no open area in two. The sewer keeps ladders, rooms, ramps and falls out of its quadrant.
* **+1..+3 (for the upper-levels lane).** Pure seed maths (`Stairwells.plan`): chance 0.55 / 0.45 / 0.35, always one
  at chunk (0, 0), one quadrant (`QUADRANT_AREAS`), clear of the spine x/z 21..23 and the duct lines 6 and 38, inside
  2..41. A level-0 chunk carves its foot only once `is_chunk_allowed` admits the level above.
* **Geometry.** The upper chunk owns the stairs (collider band rule). Switchback flights are solid wedges whose tops
  are the walking slope; the spiral is a helicoid cut into radial rings, so only the ring hugging the post is steeper
  than a walkable floor, with a slab filling the wedge between the helix's top end and the landing. Guard rails close
  the top landing except where the stairs arrive. The lower level keeps a floor under the whole well.

## Streaming

`StreamedFacilityView3D` loads the 3 x 3 window on the runner's level. When the runner's chunk has a ladder, ramp or
stairwell, it also loads the chunk at the other end of it, so a shaft never opens onto nothing. Levels a link in the
3 x 3 reaches are pre-built and parked; a parked chunk in the runner's column is kept up to `PARK_LEVEL_RANGE` (2)
levels away, so the level beyond a ramp is not freed and rebuilt on every round trip.

`snapped_level_for_world_y` puts the runner in the sewer once their feet are more than half a storey below the maze
floor. The minimap only shows the level you are on: in the sewer it draws the sewer, its water, and ladder icons
pointing up (and on the maze, down).

## Props (authored, `tools/props/rebuild_hytale_props.py` SEWER_BUILDERS -> `art/props-3d/props/sewer/`)

`sewerLadder`, `sewerLadderTop`, `sewerManhole`, `sewerFloorGrate`, `sewerValveWheel`, `sewerPump` (solid),
`sewerPipeRun`, `sewerOutflowPipe` (solid, crawl-under), `sewerOverflowGrate`, `sewerLamp`, `sewerBridge`, `sewerGrateDeck`.

## Outflow mains

A 1.5 m rusted main (`sewerOutflowPipe`) comes out of a tunnel's outer wall through a riveted wall plate and runs across
its three-wide walkway. Over the railing it turns down an elbow into the channel with its foot in the flow, and the drop's
flange weeps into the water. The underside is `CRAWL_CLEARANCE`, so a crouched runner crawls under it. A standing runner or any hunter goes round: the main only sits between an arm's bridge and the junction
(`OUTFLOW_OFFSETS`), so there is a crossing on both sides of it. Placement:

* at most one per chunk on either sewer, from its own seed stream (`SewerRouteGenerator._outflow_features`);
* brick behind it with no doorway within a cell, and no lamp, wall main, link or bridge within a cell;
* the corridor ceiling lamp over its cells is skipped (`RefDecor._overhead_cells`).

Hunter navigation reads its three `occupied_cells` like any solid prop, and the minimap draws its collider. `sewer_crawl`
checks the clearance, the placement and that hunters still reach every cell a crawler can.

## Breaking pipes and floods

The Axe breaks the sewer's pipes. Every crawl pipe (hp 3) and outflow main (hp 4) is one `Breach` pipe spec
(docs/BREACH.md): variant `"authored"`, Axe only, from `SewerRouteGenerator._pipe_breakables`. Its props carry
`breakable_id`. A swing is loud: `Breach.NOISE_LEVEL` brings hunters.

When the pipe gives way ("breached", on every machine):

* the view removes its mains, collider and drips;
* an outflow main leaves its torn stump at the wall (the authored `sewer_outflow_pipe_broken`), gushing along the old
  run;
* a rebuilt chunk keeps the pipe broken;
* hunter navigation and the minimap drop the pipe;
* `SewerFloods` starts a flood over the spec's `flood_cells` / `flood_steps`: walkway within `FLOOD_REACH` (12) steps,
  at most `FLOOD_MAX_CELLS` (160).

Unresolved, the flood keeps getting worse. It reaches shin depth (`MAX_DEPTH`, 0.35 m) in `RISE` seconds. Then, over
`CREEP` (6 minutes), it creeps up to knee height (`DEEP_DEPTH`, 0.9 m) and spreads from `START_REACH` to `FULL_REACH`
steps along the walkway, while the gush and spray grow. It never blocks a route, and hunters wade it at their normal
pace.

A flood valve in that chunk stops it: the spread freezes and the water drains in `SHUT_DRAIN` (15 s). Each spread step
is one water mesh, built once; only the holder's height and which steps show change.

`StreamedWorldState.floods` and `flood_shut` keep the burst and shut times. A snapshot carries their ages, so a co-op
join or a reloaded run picks up in the same state.

A runner wading in the flood:

* is slowed, down to `WADE_SPEED_SCALE` at knee depth;
* splashes on every step (`WADE_NOISE` at shin depth up to `WADE_DEEP_NOISE` at knee depth, louder than a sprint);
* stays soaked;
* tires from `WADE_TIRING_DEPTH` on.

## Valve wheels

Every `sewerValveWheel` is a hold-to-use interactable (2 s). The wheel spins with a clank, and turning it is loud. The
host decides what the turn does from the prop's `valve_effect` and publishes `stream_valve`; every machine applies it.
`StreamedWorldState.valve_turns` keeps the count, in the snapshot.

* `"flood"`: shuts the chunk's running floods. With none running, it turns the chunk's pipe drips off and on. A chunk
  with breakable pipes always has a flood valve: a valve room's, or one added on a tunnel wall
  (`_flood_valve_features`).
* `"gate"`: raises or lowers its sluice gate (below).
* Any other effect (room for more) just counts the turn.

## Sluice gates

A lifting leaf (`sewerSluiceGate`) is hinged on one walkway edge across the channel, out on an arm past its bridge
(`GATE_OFFSETS`). It is placed at most once per chunk (`GATE_CHANCE`, own seed stream), with its gate valve on the
hinge side's outer wall. The railings leave its ends open.

Shut, the leaf stands up and the channel stays a wall. Turning its valve swings the leaf down in 2.4 s to lie flat
across the three channel cells. Their channel collider becomes floor, hunter navigation treats them as floor (and
paths over them), and the minimap shows the crossing. Open or shut, the bridges and the junction still connect
everything; open, the gate is a shortcut.

Validator: `sewer_floods`.

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

## The waterfall jump

At each falls lip on the first sewer (-1) the overlook ledge's railing has one gap in front of one open drop cell (`falls_between()["jump"]`: `start` the ledge cell,
`cell` the open drop cell, `dir` the way out, `land` and `exit` in the cistern below). Walking into that cell is a deliberate choice, never an accident: the hint "THE FALLS //
STEP THROUGH THE GAP TO JUMP" shows within 2.4 cells. The route (`_update_falls_jump`) then calls `PlayerController3D.begin_plunge`:

1. **Arc** (about a second, collision off, no damage): off the ledge into the cistern pool; the level changes by itself when the feet cross the storey.
2. **Splash** (0.55 s): `splash_big` cue, the master bus goes muffled (`Sound.set_muffled`), the flashlight flickers for 1.4 s, and a noise burst of 3.0 for 1.2 s tells nearby hunters (it
   beats the falls' roar mask).
3. **Swim** (2-3 s at 1.5 m/s, eye just above the water) to the dry ring beside the pool, then a short climb out.
4. **Soaked** for `SOAKED_SECONDS` (30): drips (`water_drip`) every 1-2.4 s and footsteps 1.45x louder to hunters. It times out by itself.
5. 8% chance (`FALLS_ITEM_DROP_CHANCE`) that the item in hand slipped away: it is dropped at the climb-out point (`at_override` of the normal `stream_drop` event, so co-op guests request it
   through the host like any drop).

Co-op: the plunging runner's position is replicated like any movement; the drop and the noise go through the same host paths as every other drop and noise. Validators: `falls_jump`
(every lip has a jump cell on dry ledge, lands in a pool, swims 2-3 s over pool water to dry ground connected to the collector, the view leaves the railing and collider open there only,
and a live plunge ends on the collector floor, soaked, uncolliding nothing, and soaked times out) and the `plunge` section of `stream_perf` (mid-fall level change frame budget, no rebuilds).
