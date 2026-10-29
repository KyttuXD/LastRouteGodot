# Walkability and hunter navigation agree

KT: "yeah lets fix that". A co-op bot stood in a carnival booth doorway (seed LIVEMIX, chunk (1, 0, -4)) on floor a
runner can walk on but the hunters' navigation called blocked by a prop. From there it had no path.

## Cause

`StreamedHunterNavigation` blocked every cell a solid prop reserves (its `occupied_cells`). Physics only blocks the
prop's collider boxes. Wherever the footprint is larger than the collider, a runner can stand where hunters and bots
cannot path:
- the open corner of an L desk;
- the gap between two potted palms;
- the free end of a cart's cell.

## Rule

- **Reserved cells:** a reserved cell is blocked to the navigation only where the prop's collider, grown by the
  navigation's capsule radius (`NAV_RADIUS`, 0.23 m, as in `can_occupy`), covers the cell's centre
  (`StreamedHunterNavigation.collider_plan_rects`).
- **Low props:** a solid prop no taller than `WALK_ON_HEIGHT` (0.25 m, a ledge the runner's capsule rides up) is floor
  to the navigation too. There are none yet.
- **Partly covered cells:** a cell the collider only partly covers, where a runner squeezes in, is still reachable. A
  path starting there goes through `find_path`'s nearest-roomy-cell fallback (two rings).

## Check

The `nav_walkable` suite runs four seeds, levels 0 and 1, about 40,000 reserved prop cells. It fails when:
- the navigation blocks a reserved cell whose centre the prop's collider leaves clear;
- the navigation blocks a walk-on-height prop;
- a runner can reach and stand at a spot (clear by the 0.3 m walkway margin, flood-filled from open floor) from which
  the navigation finds no open cell to path off.

Before the rule it found 776 such cells (palm houses, booths) and the L desk's corner.

## Not covered

The exact booth cell from the report no longer exists: main's carnival layout has changed since that run. The bot side
was fixed separately (0dbc33f7, 3cc47837).
