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
  deployment deliberately enables account/password actions on the hardcoded
  Pterodactyl HTTP origin so testing is possible, and suppresses the in-game
  warning there. This transport is unencrypted and remains documented as a
  deployment risk; built-in per-address API/account throttles still apply.
- [x] Issue short-lived, room-bound admin tickets from the primary backend so
  an authenticated `KYTTU`/`AYTTU` owner or scoped roster admin can use permitted shared map/admin tools without
  sending an account session token to the host. Tickets expire after five
  minutes and are bound to the room plus current host token; release hosts
  reject forged, expired or unproved remote admin claims.

## P1 — missing game content

- [x] Add an asynchronous route loading screen between staging and gameplay:
  threaded scene/resource progress, route seed/difficulty readout, and a co-op
  "waiting for host snapshot" state that never exposes an unfrozen half-built
  floor. Field notes and live-play tutorial prompts are removed; the main-menu
  Tutorial owns that guidance.
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
- [x] Add a restrained route post-process: clean, detail-aware pixel sampling
  weighted toward prop textures, with broad walls/floors/stairs/lights kept
  clearer at a persisted 0-100 Settings intensity (42% default). Animated
  static, grain and scanlines are intentionally absent; the HUD stays crisp.
  F1 provides a Minecraft-style clean view by hiding the gameplay HUD while
  preserving inventory, map, escape, pause, chat, and admin interfaces.
- [x] Replace Infinite's numeric danger percentage/bar with a procedural,
  pixel-block crimson edge vignette that pulses faster and stronger as a
  same-floor hunter approaches, and spikes during an active chase.
- [x] Add a restrained grounded player hop with gravity, midair input lockout,
  settings rebinding, XR input and full vertical remote-body replication.
- [x] Add desktop gamepad movement/look and gameplay/menu controls while
  preserving them through keyboard rebinding. Align first-person height to the
  authored player eyes, add grounded movement bob, and make crouch lower both
  the POV and a headroom-tested physical capsule.
- [ ] Replace placeholder Office Mode art while preserving its working
  simulation and physical controls.
- [ ] Implement Hide & Seek after the core co-op route survives the soak test.
- [ ] Add a browser-compatible WebRTC/WebSocket transport if Web co-op is a
  release requirement; Web exports cannot use native ENet UDP.
- [ ] Complete SteamVR and Quest controller/hardware testing (`XR.md`).

## Infinite visual expansion

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

## Infinite route world

- [x] Replace normal fixed-map scale selection with Infinite-only staging.
- [x] Add explicit main-menu offline play, disabling backend/update traffic
  while retaining the same local room and gameplay simulation.
- [x] Generate canonical horizontal seams and paired vertical stairs from the
  room seed plus integer chunk coordinates.
- [x] Stream a bounded collidable renderer around each runner and persist
  pickups, safe checkpoints, safe-room damage, and hunter state across unload.
- [x] Add safer upper floors, harder lower floors, eight multi-chunk regions,
  variable room sizes, long multi-room hotel/prison halls, and authored GLB
  dressing for every region.
- [x] Make peer 1 arbitrate contested pickups, checkpoint mutations, hunter
  simulation, taser/capture decisions, split-party authority windows, and
  late-join snapshots over ENet.
- [x] Let hunters cross chunk seams and follow targets between vertical levels
  by physically walking deterministic stair ramps under normal collision and
  gravity, without a floor teleport.
- [x] Restore finite-style room/corridor chunks, perimeter-first expansion,
  textured stairs, sealed vertical joins, denser authored props/fixtures, a
  starting checkpoint marker, and difficulty-specific hunter activation.
- [x] Add a discovered-only current-floor minimap and full map with stair
  markers (white directional stair icons on the full/admin map), room-based
  relay/prop discovery, local player waypoints that clear inside a five-cell
  arrival radius, a discovery-bounded teal GPS map line/ground trail, and
  bounded debug reveal.
- [x] Scale Infinite hunter population indefinitely from relay progress while
  retaining bounded nearby presentation/navigation streaming; let grounded
  hunters traverse authored stairs between floors.
- [x] Add host-authoritative anti-AFK and stalled-relay pressure: difficulty-
  scaled timers wake Gray Void when the party stops moving or avoids relay
  progress, with relay recovery resetting both clocks.
- [x] Add host-authoritative admin summon/remove grids for every A-Z and Void
  hunter, including persistent removal across deterministic chunk refresh.
- [x] Add animated regional room doors with host-authoritative open/broken
  state, ordinary hunter use, and Loxelle chase-breach animation.
- [x] Add a five-slot inventory opened with Tab. It supports true empty slots,
  drag-to-swap, model icons and condition bars; Shift remains sprint-only and
  the player starts with a switched-off flashlight.
- [x] Add authored small/medium/large backpack pickups that expand the full
  inventory by 5/10/15 slots while preserving the five-slot quick bar.
- [x] Add host-authoritative equipment dropping and single-winner E/right-click
  pickup with remaining durability retained in late-join snapshots. Q drops
  the selected local item.
- [x] Add persistent named Infinite saves with create, overwrite, rename, load
  and delete controls in the pause menu and a startup load browser. Saves
  retain the host player/inventory/meter state, shared mutations, hunters,
  discovered map, waypoints, anti-idle pressure, and run statistics. Offline
  and online-solo hosts can save/load; a populated co-op host can archive the
  shared world but cannot replace it until guests leave, and guests have no
  save/load authority.
- [x] Show fresh co-op runner markers on the minimap and fullscreen map only
  when those runners are on the local player's current floor.
- [x] Add a pause-menu statistics view for time, distance, floors/rooms,
  relays/items, hunter encounters, chases and checkpoints.
- [x] Remove tools and flashlights from their inventory slot when durability
  reaches zero, with dedicated break/failure audio instead of routine action
  log text.
- [x] Add room chat on T or `/`, and categorized settings controls that can
  preserve multiple keyboard/mouse bindings per action.
- [x] Bound the level-zero arrival area to a finite 3x3 chunk floor while every
  upper/lower level remains horizontally unbounded.
- [x] Port streamed equivalents for objective guardians, deterministic vent
  networks, coins, and relay sabotage/resecuring. Objective-driven hunters now
  read the streamed navigation adapter instead of being excluded from Infinite.
  Vent exits validate player-sized clearance and move roomward before choosing
  the nearest safe open cell, preventing wall/grate entrapment.
- [x] Add `scripts/validate_all.sh` as the single import + backend + complete
  Godot validation entry point.
- [x] Add region-specific floor/wall textures, remove false region-transition
  floor strips while retaining authored non-solid room rugs, enforce one
  canonical threshold per room, three-cell corridors and wider stair
  clearance, and cache native
  `AStarGrid2D` navigation by authority window rather than rebuilding paths in
  GDScript for each hunter decision.
- [x] Separate hunter direct sight from retained pursuit: flashlight visibility
  extends acquisition range, routed hearing keeps a chase alive around corners,
  and interval-limited senses/replans avoid per-frame path rebuilds.
- [x] Normalize imported prop front axes and floor seating, use full-width couch
  variants for lounge placement, and validate that streamed furniture is
  room-facing, grounded, and not substituted with the miniature couch model.
- [x] Close stacked geometry deterministically: walls end below the next slab,
  the ceiling fills the remaining inset exactly, and validators reject floor /
  ceiling overlap. Add aligned 2x2 A-Z eye glows, Kathy's eye beam, independent
  head look, the darker unlit profile, and rendered co-op flashlight syncing.
- [x] Make authored beds, chairs, benches and couches usable with replicated
  sit/lay clips; add a bounded one-at-a-time planar mirror renderer and allow
  Office Void hunters to enter Infinite as rare late-roster spawns.
- [ ] Add client reconnect and relay host-promotion handoff; the backend relay
  protocol already elects a replacement, but the Godot client still returns to
  staging when peer 1 disappears.

## Port-parity audit

The finite Godot route and the original Canvas game were rechecked while the
Infinite pass was active. These are the remaining functional gaps rather than
stale presentation notes:

- [~] Port the original custom-map sibling data. The original exact per-pixel
  prop palette now reaches runtime prop placement, in addition to PNG topology,
  regions, host transfer and late joining. Sibling authored mechanics and
  walk-up dialog triggers remain; loading a custom PNG stays admin-only.
- [ ] Add reconnect/host-promotion adoption in the Godot client after the Node
  relay elects a replacement host.
- [~] Port story dialogue/cutscene content. A validated Godot JSON format now
  carries branching dialogs plus ordered cutscene steps. Playback is admin-only
  from the `0` menu—normal Infinite discovery never autoplays it. Host/guest
  state, late joining and named saves preserve the active story. Wait/dialog
  steps are playable; camera rails, actor choreography, portraits, and
  additional original content remain to port.
- [x] Add authoritative named A-Z/Void hunter summon/remove controls to the
  admin menu. Safe arbitrary teleport remains a separate future tool; existing
  gameplay/admin controls are live rather than stubs.
- [ ] Add spatial buckets/culling for dense interactable and prop queries after
  profiling identifies a real remaining hot path. Hunter perception and path
  generation are already interval-limited and native-grid cached.
- [ ] Finish Office environment art, then decide whether Office encounters are
  embedded specialist rooms or remain a separate full shift. Rare Void hunter
  identities can already enter Infinite without starting an Office shift.
