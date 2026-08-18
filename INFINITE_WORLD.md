# Infinite endless route

Infinite is the primary player-facing route. New solo and ENet rooms default
to it, and normal staging no longer shows a finite-map scale button. The old
Standard route remains in code as an internal regression and legacy-save
fallback; it is not the direction of new map work.

## Implemented runtime

- Deterministic 32×32 chunks use stable `(x, level, z)` ids, canonical doorway
  seams, and paired vertical stair links. Level zero starts in the middle of
  the world with guaranteed routes both upward and downward.
- The renderer keeps a collidable 3×3 horizontal window plus the current
  chunks immediately above and below. Old geometry, pickup nodes, hunter
  views, navigation caches, and generator cache entries are bounded as the
  runner travels.
- Upper floors trend safer. Gothic begins below level zero, Prison begins at
  level -2, and Inferno begins at level -3. Maze, Mansion, Hotel, Apartment,
  Beach, Gothic, Prison, and Inferno all have deterministic room/corridor
  layouts and authored regional GLB dressing. Hotel and prison chunks use long
  halls serving multiple rooms; landmark rooms reach 15×15 cells.
- Physical stair flights connect unlimited vertical floors. Hunters choose
  targets across the whole room, path across chunk seams, walk to a canonical
  stair, transfer levels, and resume pursuit on the destination floor.
- Safe chunks are temporary checkpoints. Their integrity persists after
  unloading, hunters can breach them, and crowbars/rescue axes can repair them.
- Inventory pickups use stable entity ids. Exactly one runner receives a
  contested item, and the claim remains spent after unload/reload.
- Sparse A–Z and deeper-floor Void hunters have stable entity ids and durable
  position/state/stun data. Capture returns the affected runner to the latest
  intact shared checkpoint.

## ENet authority

Every peer renders the same deterministic base around its own runner. Peer 1
alone owns contested pickup results, checkpoints, safe-room damage/repair,
hunter simulation, target selection, taser hit tests, and capture decisions.
Guests send intent-only interaction packets; the host validates the sender's
fresh replicated level, position, inventory, range, and generated entity data.
Late joiners remain input-frozen until the world mutation ledger and current
hunter report are adopted. The host keeps authority windows around every fresh
runner rather than only around its own camera.

`scripts/validate_streamed_world.gd` covers topology, all regions, authored
dressing, collisions, physical stairs, bounded long-distance streaming,
persistent pickups/checkpoints/hunters, authority callbacks, and snapshot
shape. `scripts/enet_smoke.gd` runs two processes and verifies Infinite room
configuration plus streamed interaction, hunter, durable-event, targeted
effect, and snapshot packets over real ENet.

## Deliberately retained boundaries

Standard remains available internally until streamed equivalents exist for
every finite-only specialist dependency (for example objective guardians,
lockers, and vent-network hunters). The public relay backend already supports
host-promotion frames, but the Godot client still returns guests to staging if
peer 1 disappears; client-side reconnect/authority handoff remains a separate
room reliability task and is not presented as completed here.
