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
  custom map, hunter capture/jumpscare, floor descent, disconnect, and leave.
- [x] Route native ENet through the authenticated Pterodactyl UDP relay. Hosts
  and guests make outbound connections only; no UPnP, player-router forward,
  hairpin NAT, or carrier-grade-NAT exception remains. Deployment must allocate
  UDP 1105 alongside the backend's TCP 8105.
- [x] Explicitly end a guest's live session when peer 1 leaves and return to
  staging with `HOST DISCONNECTED // RETURNED TO STAGING`. Reconnect grace and
  host migration remain future reliability upgrades rather than silent stalls.
- [x] Connect registration/login/session restore to the in-game account screen,
  with uppercase case-insensitive identities, scrypt hashes, restart-safe
  hashed 30-day sessions, ignored persistent `.data/`, and verified `KYTTU`
  release-admin access.
- [x] Connect account save/load to procedural solo route checkpoints. Floor
  boundaries persist seed/configuration, depth, score and coins; the
  account card exposes Continue/Clear, while co-op and authored-map state never
  overwrite the slot.
- [x] Make ordinary CREATE ROOM online-first: probe the primary service, open
  and list the ENet room automatically, and fall back to a playable solo room
  when the service or initial listing is unavailable. Staging no longer repeats
  create/join/code/leave-network controls; JOIN ROOM lives on the main menu.
- [ ] Add TLS termination in front of the public backend. The current debug
  deployment deliberately uses Pterodactyl's plain HTTP allocation so room
  discovery and updates are testable; account/password actions remain disabled
  until HTTPS is available. Built-in per-address API/account throttles remain.
- [x] Issue short-lived, room-bound admin tickets from the primary backend so
  an authenticated `KYTTU` release guest can use shared map/admin tools without
  sending an account session token to the host. Tickets expire after five
  minutes and are bound to the room plus current host token; release hosts
  reject forged, expired or unproved remote admin claims.

## P1 — missing game content

- [x] Add an asynchronous route loading screen between staging and gameplay:
  threaded scene/resource progress, route seed/difficulty readout, rotating
  hunter or control tips, and a co-op "waiting for host snapshot" state that
  never exposes an unfrozen half-built floor.
- [x] Continue the UI pass after loading:
  - [x] Replace the timed game-over auto-reset with a responsive run report,
    final route statistics and explicit solo Restart/Main Menu actions. A
    failed capture now plays the capturing hunter through a local camera-lunge
    presentation and ends that runner's route; co-op exposes Leave/End Route
    with no hidden lives or respawn/rejoin path.
  - [x] Expose authenticated uppercase username rename and password replacement
    from the signed-in account card, with the reserved `KYTTU` setup proof kept
    server-controlled.
  - [x] Add a responsive 26-hunter dossier to room staging, beside route and
    difficulty selection, with live mechanics, counterplay, route/special
    status, and tuning readouts; keep it off the main title screen.
  - [x] Apply consistent title/header typography across lobby, pause, map and
    Office.
- [x] Replace the working hiding spot's placeholder locker box with the first
  detailed modular prop: a floor-pivoted full-height locker with inset panels,
  louvres, hardware and feet, verified through its live hide/burn/regenerate slot.
- [x] Port the original themed-room identities, deterministic prop lists,
  footprints, facing/placement rules, navigation occupancy and collision.
  Current props are coloured mechanical silhouettes; bespoke GLB art remains
  part of the maze visual remodel below.
- [x] Finish the remaining hunter-specific gimmicks listed in
  `HUNTER_ROSTER.md`, including Thessine's synchronized false audio cues.
- [x] Do animation/foot-contact review on the full cast. All 27 models and all
  five gameplay clips are sampled across full loops for finite bounds, floor
  penetration, per-foot contact and loop seams.
- [x] Add a restrained route post-process: two-pixel sampling, colour
  quantization, ordered dither, scanlines and animated grain at a persisted
  0-100 Settings intensity (28% default), beneath the crisp HUD.
- [x] Add a restrained grounded player hop with gravity, midair input lockout,
  settings rebinding, XR input and full vertical remote-body replication.
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
