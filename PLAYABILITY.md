# Playability roadmap

This is the short, current list of work between the present debug build and a
reliable public playtest. `MIGRATION.md` remains the detailed port history;
this file is the order in which unfinished work should be attacked.

## P0 — public co-op playtest

- [x] Host-authoritative route state, interactions, hunter effects, custom-map
  edits, and late-join snapshots.
- [x] Primary-only account/room/update backend with no client-selectable host.
- [x] Commit-aware debug update gate. A build embeds its Git SHA, so publishing
  another `debug` release can update clients without changing `0.0.1.0`.
- [x] Backend GitHub Release mirror with verified SHA-256 files and live
  manifest reload; optional GitHub-source watcher requests a Pterodactyl
  restart when `main` advances.
- [ ] Run a real two-machine Internet soak test: host, late join, guest admin
  custom map, hunter capture/recovery, floor descent, disconnect, and rejoin.
- [ ] Decide the public gameplay transport. Room codes currently discover a
  player-hosted ENet UDP endpoint; they do not provide NAT traversal or a relay.
  A host therefore needs reachable/forwarded UDP 8421. A relay or dedicated
  authoritative game server is required for zero-configuration Internet play.
- [ ] Add reconnect grace and host migration, or explicitly end a room with a
  clear explanation when peer 1 leaves.
- [ ] Connect the existing Node account/save endpoints to an in-game account
  screen and checkpoint progression.
- [ ] Put the public backend behind HTTPS and edge rate limits before a release
  account rollout.

## P1 — missing game content

- [ ] Replace the working hiding spot's placeholder locker box with the first
  detailed modular prop; hiding interactions and hunter counters already work.
- [ ] Port the original themed-room population and prop placement rules.
- [ ] Finish the remaining hunter-specific gimmicks listed in
  `HUNTER_ROSTER.md`, then do animation/foot-contact review on the full cast.
- [ ] Replace placeholder Office Mode art while preserving its working
  simulation and physical controls.
- [ ] Implement Hide & Seek after the core co-op route survives the soak test.
- [ ] Add a browser-compatible WebRTC/WebSocket transport if Web co-op is a
  release requirement; Web exports cannot use native ENet UDP.
- [ ] Complete SteamVR and Quest controller/hardware testing (`XR.md`).

## Maze visual remodel

The current route shell is intentionally boxy prototype geometry. Remodel it
as a modular kit rather than unique per-floor meshes so procedural generation,
custom maps, collision, and network cell coordinates remain unchanged.

- Establish a 1 m grid, bottom-centre pivots, consistent doorway clearance,
  and a separate simple collision mesh for every module.
- Build floor, wall, ceiling, inside/outside corner, doorway, damaged-panel,
  trim, support, pipe/cable, vent, light, and decal variants.
- Keep visual dressing independent from the canonical walkability grid. Small
  bevels, recesses, panels, grime, and silhouette breaks should add detail
  without changing which cells players and hunters can occupy.
- Create themed prop families for the room types before porting the original
  population tables, with explicit footprint and facing metadata.
- Add distance/visibility culling and LODs after the first complete art pass;
  verify collision and navigation on procedural and authored PNG maps.

The first art slice should cover one corridor, one generic room, one doorway,
one relay alcove, and one hiding spot. Once that kit survives generation and
co-op, expand it across the route instead of remodeling every placeholder at
once.
