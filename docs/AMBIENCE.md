# Ambience and floor footsteps

## Ambient beds

`AmbienceTable` (`src/audio/ambience_table.gd`) holds one bed per district and optional beds per room purpose. A bed is a
list of layers that `AmbienceSynth` (`src/audio/ambience_synth.gd`) renders procedurally into a 10 s seamless loop at
22.05 kHz (no audio files):

| layer | what |
| --- | --- |
| `hum` | a drone: narrow-band noise ringing at the frequency with a faint sine under it, slowly breathing (mains, fans) |
| `noise` | low-passed stereo room tone (capped at 1.6 kHz, so no hiss), optional `swell` period (wind, waves, water) |
| `pulse` | sparse details at jittered intervals near `every`: short ones are resonant ticks (drips, clanks, relays), ones of 0.25 s or longer soft swelled notes (chimes, muzak) |
| `chirp` | scattered soft trills (birds, rats) |

Every bed then gets a small room reverb sized per space (`AmbienceSynth.SPACE_OF`), a 30 Hz DC block, its 1 s tail
crossfaded into its head (no click at the seam), and loudness normalisation to -54 dBFS RMS, which `Sound.AMBIENCE_GAIN_DB`
(-6 dB) plays about 12 dB under a walking step. One guard frame after `loop_end` repeats frame 0 (Android's mixer reads one
frame past the end). Render and measure all beds with `tools/audio/render_ambience.tscn` and
`python3 tools/audio/analyse_ambience.py <dir>` (clicks, DC, hiss, pure tones, level against the footsteps).

Beds: maze office hum, mansion creaks, hotel mains, apartment, beach waves and gulls, gothic wind and creaks, carnival muffled
music, prison clanks, inferno roar, hospital fluorescent hum and monitor beeps, lab fans and airlock hiss, greenhouse misting,
drips and birds, sewer water, drips and rats, mall muzak and escalator hum; room beds for the chapel, archive, kitchen, big
top and offices.

The run scene picks `AmbienceTable.key_for(region, room_purpose)` where the runner stands (room purpose first, else the
district) and calls `Sound.set_ambience(key)`: a 1.6 s crossfade between two players, nothing when the key is unchanged,
silence on leaving the run. A hunter chasing within 18 m ducks the bed by 14 dB (`Sound.set_ambience_duck`). Beds play on
the SFX bus, so the SFX volume and mute apply; every peer runs its own (guests hear their own surroundings).

New biome or room: `AmbienceTable.register("hospital", layers)` or `register("pump_room", layers, true)` for a room purpose.

## Footsteps by floor

`SurfaceSounds` (`src/audio/surface_sounds.gd`) maps every painted floor kind to a surface: carpet (soft, muffled), wood
(hollow knock), tile (sharp click: checker, vinyl, epoxy), concrete (gritty), metal (clang and ring: plates, grates, the safe
room), stone, grass (rustle), water (splash). The view records the floor kind of every cell it builds
(`StreamedFacilityView3D.floor_kind_at`); the runner's steps (`Sound.footstep(mode, surface)`) and hunter steps
(`Sound.hunter_footstep(pan, volume, surface)`) use it, with walk / sprint / crouch / hunter levels and four pitch variants.
Hearing and gameplay are unchanged: only the sound differs.

## Validator

`ambience`: every district has a bed, room beds override, registration works, crossfade / same-key / duck / stop, every bed
is a seamless loop that is neither silent nor clipping, every floor kind (FloorSets and all painted kinds) maps to a known
surface, every surface renders a step for every gait, carpet is softer than concrete, and the run scene drives both.
