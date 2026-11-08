# Physical vents

Requested on 2026-10-28: "i want vents physical not teleport based" and "verrine should follow vents". REGIONS
owns the ducts themselves: `VentNetwork`, the sheet-metal duct view and the hatches. WORLD owns movement through them.

## The ducts (REGIONS)

- Storey 0's ducts run in a plenum between the ordinary ceilings and the storey above. A duct is `VentNetwork.DUCT_HEIGHT`
  (1.2 m) tall inside, its floor is at `VentNetwork.DUCT_FLOOR` (4.8 m), along the lines x/z = 6 and 38 in every chunk.
  Ordinary ceilings top out at 4.6 m (`RefLook.CORRIDOR_RANGE` / `ROOM_RANGE`), so the ducts are hidden over corridors and
  rooms and show only where they cross a taller hall or glasshouse (4.8 to 7.5 m). `validate_vents_view` locks the clearance.
- Where a duct line crosses a wall, the wall stops under the duct and, in a room taller than the duct, goes on above it.
- Grates are `LevelLink`s with `from_cell`, `chunk`, `from_level`, `duct_level` and `duct_y`
  (`VentNetwork.duct_floor_y(level)`). A grate is a louvred ceiling grille with a short sheet-metal riser up to the duct.
- Chunks under a mezzanine deck or in the void have no storey-0 duct (`VentNetwork.has_ducts`, `chunk["ducted"]`): the lines
  stop, capped, at their edge and `VentNetwork.crawlable()` is false there. A deck can therefore cut the lattice in two. (the decks and the void were removed, so today every maze chunk is ducted.)
- Only storey 0 has physical ducts for now (`PlayerController3D.VENT_STOREYS`). The upper storeys keep logical ducts at
  `VentNetwork.UPPER_DUCT_FLOOR` (2.7 m) under their own ceilings until they get a plenum of their own.
- The duct skin is galvanised sheet painted by `RefTextures.duct_material` (sheet panels one per metre, bolted joint rings
  every 2 m, louvred grilles), built in `StreamedFacilityView3D._spawn_ducts`.

## Moving through them (`VentCrawl`)

The same movement is used by runners and hunters.

- **Climbing:** a climb through a grate's hatch takes `CLIMB_SECONDS` (1.4 s) and lifts you from the storey floor to
  the duct floor.
- **Crawling:** you move at `CRAWL_SPEED` (1.4 m/s), on duct cells only, sliding along the duct walls.
- **Climbing out:** you climb out at a grate and land under its hatch.
- **No teleports:** nothing ever jumps from one grate to another, and `validate_vents` checks every frame's step.
- **Sound:** every 0.9 m crawled makes a sheet-metal thump with noise 2.5 that hunters can hear. Hatches bang when
  someone climbs through.

### Runners

- Standing under a grille shows "CLIMB INTO VENT"; [E] climbs in.
- The move keys crawl, with a crouched camera.
- At a grate, [E] climbs out.
- `in_vent` is true while you are inside, and Verrine's speed ramp still reads `vent_time_in`.

### Co-op

- The player state carries `duct`, a hot bool.
- GuestGuard holds a guest reporting `duct` to crawl speed, and skips the wall sweep, because the ducts run through
  walls.
- A hunter's height in a duct reaches guests through `presentation_y`, and `in_vents` gives them the crawl pose.

## Hunters (`VentNav`)

- **Verrine:** always in the vents (see below).
- **Other hunters:** only on Hard and Nightmare, while chasing or investigating, and only when the vent route is at
  most `SHORTER_RATIO` (half) of the floor path. The route is: walk to the entry grate, climb in, crawl the duct
  path, then climb out at the exit grate.
- **Pose:** in the ducts a hunter plays the Night Watch `vent` crawl pose (Verrine has her own).
- **Sound:** a hunter's thumps and hatch bangs play as metal sounds for the host.

## Verrine

Once the scene hands her the storey-0 duct layer, Verrine:
- starts in the ducts and patrols them, visible (the no-invisibility rule);
- chases a runner who crawls in;
- crawls to the grate nearest a runner who comes within 12 cells of one on her floor, then bursts out beside them;
- climbs back in after 8 s without a sighting.

Her old grate teleports (`use_vent`, `remote_vent_entered`) are off.

## Retired

- The old wall-grate "vent" fixtures, which teleported between grates, are no longer spawned. Their generator
  records stay, so no seed moves.
- `_use_streamed_vent` is gone.

## Validators

- `vents` covers the crawl, routes, Verrine and GuestGuard headless across 3 seeds, plus an in-scene climb in,
  crawl and climb out.
- `vents_view` is REGIONS' check of the duct view.
