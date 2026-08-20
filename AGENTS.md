# Last Route agent notes

## Publishing to GitHub

- Never stage, commit, push, tag, or create a release unless the user has
  explicitly authorized that action in the current conversation.
- When a commit and push are authorized, use `scripts/push_to_github.sh` from
  the repository instead of assembling an ad-hoc Git command sequence.
- Read `scripts/PUSHING.md` before using the helper. In particular, its default
  staging mode includes every tracked and untracked path shown by
  `git status`; this repository may contain unrelated user work.
- Keep the full test run enabled unless the same working-tree revision was
  already validated and the user accepts `--skip-tests`.
- Do not force-push. If the helper reports that the remote branch diverged,
  stop and resolve it without discarding either the local or remote history.
- The helper only commits and pushes. Version bumps, tags, GitHub releases,
  and release artifacts are separate operations requiring separate user
  authorization.

## Ongoing handoff notes

- When changing generation-heavy systems, prefer extending existing deterministic
  templates and catalog entries so multiplayer peers stay in sync.
- The office-area direction is currently anchored in:
  - `src/game/streamed_route_generator.gd` (`_room_template_specs` for
    `office_reception`, `office_cubicles`, `office_job`, `office_meeting`,
    `private_office`)
  - `src/config/room_catalog.gd` (`office` room type props)
- For the new office job-environment iteration:
  - `office_roles` now includes `office_job` in the generated office suite
    room assignment.
  - `office_job` is mapped to `_room_template_specs` with dense desk/table/cabinet
    furniture so co-op peers share identical layout from the same seed.
- Next agent should verify the edited office templates visually in both
  single-player and co-op host/client runs before touching validator scripts.

- Prison cafeteria generation is wired through `src/game/streamed_route_generator.gd`:
  the prison region has a registered fallback prop set, and the
  `prison_cafeteria` template builds a rear-wall serving counter and kitchen
  rack, repeated bolted table/bench units, a side tray-return cabinet, and
  ceiling lights.
  Keep this deterministic/template-driven so host and guests agree from the
  same seed; validate visually when Godot is available.

- Empty picture/painting frame GLBs are now given a deterministic white canvas
  at runtime by `StreamedFacilityView3D._add_blank_frame_canvas()`. Keep the
  authored frame mesh and canvas separate so future artwork can replace only
  the child surface without re-exporting every frame model.

- The ten-piece office family has coordinated neutral, charcoal, and teal GLB
  variants. Keep every office type in `COORDINATED_SET_TYPES`, keep the three
  `VARIANT_THEMES` arrays in identical order, and add any future office finish
  to every silhouette so one generated room cannot mix unrelated palettes.

- Stair flights occupy the full `stair_path_cells()` span. `_fixtures()` and
  `_pickups()` now use `_stair_door_exclusion(stairs)` rather than excluding
  only each stair anchor, preventing props, relays, batteries, and tools from
  spawning on treads or the upper landing.

- Never add a room/custom-map prop type without a real authored asset. The
  required chain is builder in `tools/props/rebuild_hytale_props.py`, source
  `.blend`, exported `.glb`, Godot import, `PropModelCatalog` entry, footprint,
  and deterministic runtime placement. Do not substitute an unrelated GLB or
  leave a catalog-only placeholder.
- The office set now has authored desk, task chair, three-CRT security console,
  cubicle partition, printer, and water-cooler models. Residential `bunkBed`
  selects distinct metal, wood, and loft-bed GLBs; `prisonBunk` remains only
  the institutional prison-cell model.
- The next authored equipment batch adds a photocopier, shredder, stacked file
  boxes, and an L-shaped corner workstation to deterministic office templates.
  Prison cafeterias use dedicated bolted table/bench units, a guarded serving
  counter, tray return, and kitchen rack; do not replace these with generic
  dining/kitchen silhouettes or run the legacy prison-cell dresser in them.
- Regional floor dressing no longer aliases bedroom/bathroom meshes. Corridor,
  hotel, apartment, and beach types own ten dedicated thin GLBs. Keep their
  bottom pivots flush and rely on `FLOOR_DRESSING_Y` for the small runtime lift;
  do not thicken them into collision or return them to random maze corridors.
