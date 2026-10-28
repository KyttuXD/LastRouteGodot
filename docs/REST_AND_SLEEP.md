# Resting, sleeping and hunter naps

## The rest camera

These were actually wrong before the fix:

- **Lying was at sitting height in the middle of the bed.** The body went to the "lie down" marker, which sits 0.48 m up
  at the bed's centre, and the eye went 0.72 m above that. The eye ended up about 1.2 m up in the middle of the bed.
- **Unclamped look.** Seated or lying, you could turn a full 360° and pitch ±80°, so you could stare into the backrest,
  headboard or wall from a few centimetres away. That was the clipping.
- **Snapping.** Mounting and leaving teleported the body and the eye in a single frame.
- **Furniture you could "lie down" on that is not a bed.** `interaction_for` treated any type containing "bed" as a bed,
  so the bedroom nightstand, wardrobe, dresser and vanity offered LIE DOWN, and the gothic bedroom bench was a bed instead
  of a seat. Beds are now only types ending in `Bed`, plus bunks.

The hiding-props camera fit did not interfere. "Lie down" aims at the mattress and "Hide under bed" aims low at the foot,
and they are separate interactables.

The fix (`PlayerController3D.rest_spot`, `_clamp_rest_look`, `_advance_rest_ease`):
- **Sitting:** the body sits 6 cm forward of the seat centre, clear of the backrest. The eye is at 1.15 m, facing out of
  the seat. Look range is ±75° yaw and −54° to +34° pitch.
- **Lying:** the body is at the pillow end (from the prop's footprint, which the furniture now carries as `rest_size`).
  The eye is just above the mattress, 0.72–1.05 m by bed height, looking along the bed toward its foot, tipped up a
  little. Look range is ±55° yaw and −20° to +60° pitch, so you can look up at the ceiling.
- **Transitions:** mounting and getting up ease the eye over 0.35 s in both directions. Input waits for the ease.

## Runner sleep

In a bed, **jump** sleeps. Jump or interact wakes you.

- **While asleep:** the screen fades to dark, stamina refills (9 per second) and the torch goes off.
- **Hunters nearby:** a hunter within 12 m gives a muffled stir cue every 3 s. Within 5 m it wakes you with a jolt (a
  view kick and a sound). A catch also wakes you.
- **Vulnerable:** you are an ordinary target while asleep. Sleeping is not hiding.
- **Accidental sleep (solo only):** lying idle for 50 s makes you drowsy, with slow blinks, a darkening screen and a yawn.
  8 s later you doze off. Moving the mouse or pressing any key resets the clock.
- **Co-op:** no accidental sleep (`accidental_sleep_enabled` is off online). The `asleep` flag replicates, and teammates
  see "z Z" over a sleeping runner.
- **Not a free pause:** a sleeper does not move, so the anti-idle pressure (the gray void) keeps running as it would for
  anyone standing still.

## Hunter naps (`src/game/hunter_naps.gd`)

The nap logic is host-side, next to the brain:
1. A patrolling hunter (wandering or idle, with no runner within 14 m) now and then walks to a bed within 14 m. Beds come
   from the hiding-spot fixtures, which now carry the bed's position and facing.
2. At the bed it yawns (the yawn emote), then lies on its back on the mattress and sleeps for 25–45 s.
3. Asleep, it does not hunt: the brain is not updated, so it cannot see, hear or catch anyone. Peers near it hear a snore.

A nap ends one of two ways:
- **Startled awake:** a runner within 3 m, a loud runner (noise 3 or more within 10 m), or a torch beam pointed at it
  within 7 m. It flinches, stalls for half a second, then investigates where the runner was.
- **Waking on its own:** it gets up quietly when the nap time runs out.

**Chance per second of patrol:** Relaxed 2%, Normal 1.2%, Hard 0.3%, Nightmare never.

**Who naps:** never the Voids, the secret creatures, or any hunter whose persona never yawns
(`HunterEmotePersonality`).

**Wake meter** (KT: "if you enter a room with a sleeping hunter, they should eventually wake up and notice you"):
- **Filling:** while a runner is in her room, or in line of sight within 10 m, the meter fills every second. The base
  rate is 0.03, so she always wakes; a sneaking runner with the torch off wakes her in about 13 s at 6 m. On top of that
  it adds up to 0.12 for closeness, 0.04 × the runner's noise, 0.15 for sprinting, and 0.25 for a torch pointed at her.
- **Cues:** at 35% she stirs, at 60% she turns over onto her side, and at 85% the snore stops. Nearby peers hear stirring
  instead of snoring.
- **Full:** she wakes and goes straight for the runner if they are still in the room or in sight.
- **Instant catch:** for 3 s after that wake, a catch skips the escape struggle. The capture event carries
  `"reason": "woke_grab"` (`HunterNaps.WOKE_GRAB_REASON`), meaning "woke up and grabbed you", for the hunters lane's
  catch details.
- **Leaving the room:** the meter drains at 0.02 per second, and she sleeps on.

The close, loud and torch-in-face rules still wake her at once.

**Replication:** the hunter report carries `asleep`, `sleep_yaw` and `sleep_stage`, so guests see the same hunter lying in the same
bed.

## Checks

The `rest_and_sleep` suite covers:
- **Rest camera**, on all 24 sit and lie furniture types: eye height, facing out, the yaw and pitch clamp, eye position
  (pillow end, never into the backrest), and no camera jump of more than 0.2 m in a frame either way.
- **Runner sleep:** sleep, stamina, the dark screen, the stir cue and the jolt awake, and the replicated flag.
- **Accidental sleep:** drowsy first, input shakes it off, solo dozes off, co-op never does.
- **Hunter naps:** eligibility by persona and difficulty, walk, yawn and sleep, quiet runners not waking it, and loud,
  close and torch-in-face wakes.
- **Wake meter:** a sneaking runner still fills it, while noise, running and the torch fill it much faster. All three
  cues happen, she wakes into a chase, the catch window is instant and closes after 3 s, and the meter drains once the
  runner leaves.
