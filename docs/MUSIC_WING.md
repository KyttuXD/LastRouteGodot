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

## Rooms (next)

A rare wing, not a biome: a 15 x 13 stage room, two 9 x 9 practice rooms with foam-panel walls, a 9 x 9 instrument
store and an 11 x 9 control room with a glass-walled vocal booth (real sizes x 1.5), in hotel and mall chunks, plus a
small music stage in the carnival. The hook into the generator is being agreed with the BIOMES lane.
