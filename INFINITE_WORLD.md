# Infinite route foundation

The first infinite-map phase is now implemented as a deterministic topology
layer in `src/game/streamed_route_generator.gd`. It does not replace the
current playable finite facility yet. That fallback remains intentional until
chunk unload/reload, host migration, late joining, and persistent mutations can
all be proven without deleting a room out from under connected players.

## What exists in this phase

- The world is divided into deterministic 16×16 chunks addressed by `(x, z,
  level)` coordinates.
- Adjacent chunks derive each shared doorway from one canonical boundary key,
  so opposite sides cannot disagree about whether a seam is open.
- Vertical links are also canonical pairs. An `up` stair in one level has the
  matching `down` stair in the chunk above; the origin route is guaranteed to
  begin with a usable stair link.
- Four-chunk regions select biome-style room language: Maze, Mansion, Hotel,
  and Apartment. Each biome already carries a distinct stair intent (service,
  grand foyer, hotel stairwell, or apartment stairwell).
- Temporary safe-room chunks are deterministic and the origin starts safe.
- Prospective inventory pickups receive stable global ids containing their
  chunk coordinate. This is the key required for host-authoritative, exactly
  once collection after chunks begin unloading.
- A configurable active radius returns the chunk coordinates which should be
  loaded around a runner.

The headless `streamed_world` validation regenerates chunks, verifies every
seam from both sides, checks paired stairs between levels, reaches all four
biomes, checks safe-room availability, rejects duplicate pickup ids, and
checks the active radius.

## Next integration gate

The next phase will render those active chunks and retire them outside the
radius. Before the service lift and map-size settings are removed, the host
must retain a compact mutation ledger for pickups, broken boards, doors,
lights, and safe-room state. Late joiners and replacement hosts must receive
that ledger plus the world seed, and a collected pickup id must remain spent
even after its owning chunk unloads and rebuilds. Only then can the fixed-floor
lift become unnecessary and the route operate as continuous endless survival.
