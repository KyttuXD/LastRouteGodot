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

New region or room: `AmbienceTable.register("hospital", layers)` or `register("pump_room", layers, true)` for a room purpose.

## Level layer

`LevelAmbience` (`src/audio/level_ambience.gd`, a node of the run scene) adds a bed per level under whichever district bed
is playing, so the two blend. The run scene calls `level_ambience.update(listener, level, chunk_data)` every frame next
to `Sound.set_ambience`; the bed is `LevelAmbience.key_for(level, chunk_data)`:

| level | bed | what you hear | reverb (Level bus) |
| --- | --- | --- | --- |
| 0 maze | `level:maze` | a deep building hum, distant thuds (now and then a double) | tight, almost dry |
| +1 Mezzanine | `level:mezzanine` | airy gusting wind, metal creaks; the grating steps ring | open, metallic |
| -1 / -2 sewers | `level:sewer` | running water, drips, pipe groans, far thumps | big, with a late echo |
| -3 Inferno | `level:inferno` | low fire roar, ember cracks, deep rumble | large, darker |
| void shaft | `level:void` | deep hollow wind with a high whistle over it, a sub hum | huge, long echo |

A chunk may name its own bed with `"ambience_level"` in its data (the void shaft sets `"void"` on every level it spans);
otherwise the level decides. Level beds are `AmbienceTable` entries (`register("level:<name>", layers)`), rendered by
`AmbienceSynth` with the level layer kinds `wind`, `thump`, `creak`, `groan`, `water` and `crackle`, and prerendered at
boot with the district beds. They play at `LevelAmbience.GAIN_DB` (a few dB under the district bed, more in the void,
which has no district bed of its own) and duck with it in a chase.

**Level bus.** Level beds, positional sources and the runner's footsteps (`Sound.footstep_bus`) play on the `Level` bus,
made at run start after the project's buses. It sends to `SFX`, so the SFX volume and mute apply, through one
`AudioEffectReverb` set from `LevelAmbience.REVERB` (room size, damping, wet, pre-delay, pre-delay feedback). A level
change crossfades the bed over `FADE` (2.4 s) and glides the reverb over the same time. The crossfade follows streaming:
the level is the one the runner's chunk is on, and a bed not rendered yet fades in as soon as the worker pool has it.

**Positional sources.** Chunk views register sources with `LevelAmbience.add(anchor, kind, at, id)`. The anchor is the
chunk's node, so unloading the chunk removes them:

| kind | where | sound | range |
| --- | --- | --- | --- |
| `falls` | the lip of every waterfall (-1) and its pool (-2) | `FallsLoop`, the seamless roar | 28 m |
| `outflow` | the drop flange of every outflow main | a trickle of small bubbles | 14 m |
| `flood` | a burst pipe while it runs (`SewerFloods`, SEWER lane wires it) | `FallsLoop`, pitched up | 22 m |
| `lava` | the lava channel of every Inferno pit, one every 6 m | slow thick bubbles, a faint sizzle, embers | 16 m |

Only the `MAX_EMITTERS` (6) nearest sources within range play, on a fixed pool of `AudioStreamPlayer3D` (inverse-distance
falloff), re-picked four times a second; a playing source is preferred over one at about the same distance, so they do
not swap. Each pick casts one ray per playing source to the listener: with a wall or floor in between, the source eases
9 dB quieter and low-passed to 1.1 kHz. `LevelAmbience.set_intensity(id, db, pitch)` rides one source (a flood worsening
until its valve is shut). Mute stops them.

**Storeys.** A source is heard on its own level only (`LevelAmbience.storey_state`, the level from the source's world
height): on the level above or below it, in the sewers and the maze, it is a faint (-18 dB), dark (450 Hz) rumble through the
floor; from +1 up nothing below is heard, and two or more levels away never. The gate eases between these states at 1.5 a
second, so a stairwell never cuts a sound, and a source that falls out of range, off the storey or away with its chunk fades
out before its player is freed. Only the listener's level bed plays (`level:sewer` has no wind, `level:mezzanine` no water).

**Mods.** `Sound.ambience_stream(key)` is the one lookup for district beds, level beds and the positional loops
(`emitter:<kind>`); `Sound.ambience_override(key)` is where content packs' recordings come first (`ambience/` packs,
docs/modding).

Listen with `tools/audio/render_level_clips.tscn` (one 16 s clip per level: district bed, level bed, steps or a walk past
the level's sources, the bus reverb approximated offline).

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

`level_ambience`: every level and the void have a seamless level bed, the sewers and the void echo more than the maze, a
level change crossfades the bed and glides the reverb (no cut, no jump), the Level bus sends to SFX and carries the steps
while a run is on, mute and chase ducking apply, every positional loop is seamless and FallsLoop is the waterfall, the
real sewer and Inferno views register their falls (both levels), outflow trickles and lava where they draw them (and no
chunk builds a player of its own), only the nearest six within range play, a wall muffles a source, a source's level and
pitch can be ridden, a source is heard on its own storey only (faint and muffled one level away in the sewers and maze, never from +1 up, never two levels away, always faded not cut), and an unloaded chunk or a finished flood takes its sources with it.
