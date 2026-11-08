# Inferno caverns and the cage pit (level -3)

`game/world/regions/inferno_caverns.gd` carves the wide places of level -3; `game/world/regions/inferno_pit_view.gd` draws the cage pit.
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

## Nothing under level -3

Level -3 is the lowest storey and the view clamps its level there, so a missing collider on it is a fall with no end.
Suite: `inferno_ramp` (pocket scan from `tests/validate_inferno_floor.gd`, the net's bookkeeping, the net in the route).

- A collector ramp (`-2` to `-3`) leaves a 12x3 pocket under its slope on the Inferno storey. The slab is the level -2
  chunk's `Ramp` body; the Inferno side gets a floor collider under every pocket cell (`_build_ramp_cell`) and thin wall
  colliders on the pocket's two long sides and its head (`_spawn_ramp_pocket`, flush outside the rect, 3.9 m high). The
  foot stays open. Cave tunnels run along the slope, so drawn walls (`_close_ramp_sides`) alone are not enough.
- `Ramp` and `RampPocket` use `DISABLE_MODE_KEEP_ACTIVE`: a parked (dormant) chunk would otherwise drop them from physics.
- World-bottom net (`game/world/streaming/world_bottom_net.gd`, ticked by `StreamedFacilityView3D._tick_world_bottom`):
  remembers the last floor the runner stood on (grounded, chunk built); 0.3 s under y -15 (the Inferno floor minus 3 m)
  puts her back there, zeroes the fall, rebuilds the chunk under her and emits `runner_recovered` (the route shows a
  message). Noclip and spectating are exempt. Real floors, pits and trenches are all above -15.
