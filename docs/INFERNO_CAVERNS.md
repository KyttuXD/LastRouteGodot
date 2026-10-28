# Inferno caverns and the cage pit (level -3)

`src/game/inferno_caverns.gd` carves the wide places of level -3; `src/game_3d/inferno_pit_view.gd` draws the cage pit.
Suite: `inferno_caverns`.

## Caverns

- Every -3 chunk (except a safe room) gets a cavern 16-22 cells across, and a second 14-16 cells across when it fits.
  Rooms it overlaps are dropped; ramp footprints keep a 2-cell margin; seam openings stay (5 cells of margin).
- A rough ellipse, so the middle always holds a clear 7x7. The view lifts its cells (and its halls) to the storey cap.
- A 5-wide hall joins each cavern to the maze's circulation; up to 3 one-cell dead-end crevices cut into the rim.
- API: `StreamedRouteGenerator.inferno_caverns_at(coord)`, `dump_landing(coord) -> Vector2i` (a chunk-local walkable
  cell with a clear 3x3 inside the main cavern or a hall; (-1, -1) off level -3). Chunk data key: `inferno_caverns`
  (each `{rect, cells, halls, crevices, pit?}`).
- Wide ground (a fully open 7x7): 3% before, about 11-14% now.

## Cage pit

About a quarter of the large caverns are a pit district (`cavern["pit"]`):

- a 3-wide lava channel across the cavern with a 3-wide chain bridge; lava cells are rock to the walk grid (hunter A*
  never crosses them), listed as floor and structural voids, and covered by invisible blockers; never instant death;
- 12 iron cages on chains from the ceiling at three heights (2.5 m high, 2.1 m walk-under, 0.75 m in the way), some
  swaying, some with the door ajar; a row of cages against a wall; all empty;
- glowing floor cracks, an orange underglow light, rising embers and a low rumble (`Sound.pit_rumble`).
