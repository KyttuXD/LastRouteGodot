# Ambience and floor footsteps

## Ambient beds

`AmbienceTable` (`src/audio/ambience_table.gd`) holds one bed per district and optional beds per room purpose. A bed is a
list of layers that the Sound system renders procedurally into a 6 s seamless loop (no audio files):

| layer | what |
| --- | --- |
| `hum` | steady tone (fluorescent hum, mains, engine) |
| `noise` | steady filtered noise, optional `swell` period (wind, waves, fans, water) |
| `pulse` | a short tone repeated `every` seconds (monitor beeps, drips, clanks, music) |
| `chirp` | scattered short triplets (birds, rats) |

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
