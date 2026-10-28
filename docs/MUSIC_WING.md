# Music wing: instrument props and the Rehearsal Hall

KT asked for instrument props, a microphone and a small region for them. This page covers the props (done) and the wing
of rooms that uses them (next).

## Props (family `music`)

Original blocky designs in `tools/props/blocky_props_music.py`, authored in metres at real size and built by
`build_blocky_props.py` like every blocky prop (`BLOCKY_ONLY=<ids>` rebuilds just these). In game they are
`HUNTER_SCALE` 1.5, the same as the seats and counters. The thuing bbmodels were not used.

| group | props |
|---|---|
| mics | `micStand`, `podiumMic`, `deskMic` |
| instruments | `drumKit`, `electricGuitarStand`, `acousticGuitarStand`, `bassGuitarStand`, `keyboardStand`, `uprightPianoMusic` |
| gear | `ampStack`, `comboAmp`, `stageMonitor`, `paSpeakerPole`, `mixingDesk`, `studioMonitors`, `rackGear` |
| dressing | `musicStand`, `cableCoil`, `cableRun`, `stageLightRig`, `acousticPanel`, `guitarWallHanger`, `instrumentCases`, `onAirSign` |

- **Data:** the models come from `data/props/music.json` (`lr.prop/1`); `PropModelCatalog._CODE_MODEL_PATHS` lists each id
  as `ContentRegistry.DATA`. Footprints (`RoomCatalog.FOOTPRINTS`), template sizes
  (`StreamedRouteGenerator.TEMPLATE_PROP_SIZES`) and hunter scale stay in code, like every other prop.
- **Mounting:** `acousticPanel`, `guitarWallHanger` and `onAirSign` hang on walls; `cableCoil` and `cableRun` are floor
  dressing; `deskMic` and `studioMonitors` sit on a `mixingDesk` (surface height 0.82 m). The piano, rack, cases and wall
  pieces back onto walls. Mics on their own, cables, panels and the sign are not solid.
- **Colliders and LODs:** `src/config/prop_collider_sizes.gd` was regenerated (`tools/props/emit_collider_sizes.tscn`);
  the props use the standard blocky prop visibility ranges. Dressing is batchable; playable props are not.

## Playable instruments (`MusicProps`)

`micStand`, `podiumMic`, `drumKit`, the three guitars, `keyboardStand` and `uprightPianoMusic` have the furniture action
`music`. The prompt names the action ("PLAY THE DRUMS", "TAP THE MIC"); using it plays a short synthesised cue
(`Sound.music`: feedback squeal, mic thumps, a kick-snare-cymbal fill, a power chord, a strum, a bass note, a chord, a
piano chord) at most once per 0.6 s per prop.

**`music_noise` (on by default, KT):** while `MusicProps.noise_enabled`, playing also calls the player's
`emit_noise_burst`, so nearby hunters hear it. Levels are below the water splash (3.0): drums 2.6, mic 2.2, electric 2.0,
bass 1.8, piano 1.6, keys 1.4, acoustic and podium 1.2. Turned off, the props only make their sound.

## Validator

`music`: every prop of the family is wired (data models, files, footprint, template size, scale 1.5, collider when solid,
mount lists, interaction and batching); every playable prop prompts and has an audible cue; the noise burst follows
`music_noise`.

## Rooms (`src/game/music_wing.gd`, `MusicWing`)

Kept in its own file so the BIOMES lane can resize the generator's rooms freely.

- **Rehearsal hall (hotel, mall):** a great-hall slot (`StreamedRouteGenerator.large_plan`, 21 x 21, one door on the
  vertical hall) of type `rehearsal_hall`, carved by `MusicWing.carve()` into a three-wide wing hall with two nine-deep
  bands of rooms: a 13 x 9 `music_stage` and a 9 x 9 `instrument_storage`, an 11 x 9 `practice_room` and an 11 x 9
  `recording_booth` (control room, glass wall with a gap, vocal booth with a mic and the REC sign). A door-in-the-middle
  21 x 21 slot only holds two nine-deep bands, so the stage is 13 x 9 rather than the 15 x 13 first sketched and there is
  one practice room. A west-side slot is the mirror of the east-side one.
- **Carnival:** `carnival_stage`, a 21 x 9 bank room (band under the light truss, monitors, mics).
- **Mall:** `music_store`, a 20 x 9 shopfront of guitar racks, instruments on stands, amps and a counter.
- **Recipes:** `MusicWing.room_specs()` sizes each room to its rect like the biome recipes; the stage edge sits two rows
  in front of the entrance in a nine-deep room and six rows out in a great hall, where rows of chairs and a mixing desk
  follow. `MusicWing.SIZE_PROFILES` declares this lane's own min / preferred / max sizes.
- **Generator hooks (BIOMES lane wires them after its room resize):** `rehearsal_hall` in `LARGE_ROOM_TYPES` for hotel
  and mall at about 5 % per side, calling `MusicWing.carve(grid, big, big_door, rng)` in the merged-sides branch;
  `carnival_stage` in `BANK_BIG_TYPES["carnival"]`; `music_store` as a mall shop role; and the template dispatch
  `if template in MusicWing.TEMPLATES: specs.append_array(MusicWing.room_specs(template, half, depth_span, mirror))`.

The `music` suite carves the wing into a stand-alone grid both ways (four rooms of their declared sizes, doorways open,
every cell reachable from the slot's door) and checks every recipe at its usual sizes (catalogued props, inside the
room, no two solid props on one cell, the entrance kept clear, the defining props present). Once the hooks are in, the
`biomes`-style room checks (overlaps, doorways, reachability) cover the generated rooms too.
