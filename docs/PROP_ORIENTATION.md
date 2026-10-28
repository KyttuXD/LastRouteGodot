# Prop orientation

KT: "check other connected props and make sure they're rotated correctly or decently". `StreamedRouteGenerator.orient_props`
runs on every furnished room after placement, so recipes added later follow the same rules.

1. **Seats in front of wide screens.** A screen too wide to turn (a lab control console) whose seat sits off to its side
   gets the seat moved onto the open floor in front of it.
2. **Backs to the wall.** A wall-backed type (`RoomCatalog.WALL_BACKED_TYPES`: beds, wardrobes, cabinets, bookcases,
   toilets, sinks, stoves, fridges, counters, vending machines, arcade cabinets, couches, TVs and more) that does not
   already have its back on a wall, and whose cell touches one, turns its back to that wall and slides flush. This only
   applies to props that fit in one cell both ways.
   - Recipe wall-backed props were also off the wall: small ones sat at the cell centre, about 19 cm out, and deep ones
     were placed from their authored size rather than the fitted collider.
   - All of them are now placed with the back 2 cm off the wall, measured from the collider boxes' real back extent,
     offsets included.
3. **Facing pairs**, from the table `ORIENT_PAIRS`, child to the nearest anchor within reach:
   - chairs and stools to tables, desks, counters, islands, workstations, bars, stations and consoles;
   - sofas to the TV or the coffee table;
   - benches to pianos and vanities;
   - computers, monitors, consoles and terminals to seats, and monitors to beds (vitals monitors).

   Wall-backed children keep their wall, and the TV keeps its wall while the sofa turns to it. Turns snap to 45°, and a
   prop wider than a cell only flips 180°, which keeps its footprint.

Check: `prop_orientation` over three seeds, levels 0 to 5, and every district. Every pair must face its anchor with dot
> 0.7 (2,357 pairs), and every wall-backed prop that sits against a wall must have its back within 15 cm of it (10,745
props). `screen_facing` runs the screen pairs on their own.

Before and after: `docs/orientation_before_after.png` (`tools/look/orientation_rooms.tscn`). No lab room matched the
capture's filter.

Not covered by the pass: doors, and hiding props' approach sides. Those already open toward their own open side.
Nightstands beside the bed head come from the bedroom recipe and are not re-placed. The 55-prop hunter-scale rescale
(the `scale_fit` worklist) is a separate pass.
