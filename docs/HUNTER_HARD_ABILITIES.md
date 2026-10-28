# Hunter abilities for Normal, Hard and Nightmare

Extra, persona-anchored abilities on top of each hunter's own gimmick: **Relaxed gets none; Normal gets every one very rarely; Hard has them regularly; Nightmare more often and
stronger.** Code: `HardAbilities` (`src/game/hard_abilities.gd`, one component per brain: `HunterBrain.hard`), host-simulated like every brain, visible state replicated with the
hunter report (`"hard"`). Suite: `hard_abilities`. The host can switch every ability off for the room: **HUNTER ABILITIES ON/OFF** in the lobby (`RoomState.hunter_abilities`).

Built so far (step 1): the **pounce**, the **sprint burst** after losing sight, **intercept** and the **door slam-through**. The rest of the pitch is listed at the end.

## How rare is "rare"

One dial plus a budget instead of a pile of numbers:

- **Mode factor F** scales roll chances: Relaxed 0 (off), Normal 0.12, Hard 1.0, Nightmare 1.6. Cooldowns are explicit per mode.
- **Party budget per ability**: at most one activation of an ability anywhere in the party per 360 s (Normal), 45 s (Hard), 25 s (Nightmare), however many hunters carry it (spawn growth
  cannot make Normal busy). The pounce also never lands twice on one runner within 10 s.

## The pounce (no wind-up, no cue)

Who (build / persona), per mode:

| Normal | Hard | Nightmare |
| --- | --- | --- |
| Haelith (eager wolf-dog), Red Void | + Solyth (hot-tempered: only when the runner is warm, temperature >= 60), Xivvy (hyper), Red Void in halls only | + Black Void (only if she has been unwatched for 3 s), Nyxie (only while the runner's flashlight is off) |

Launch needs ALL of: she is chasing with a live sighting, no stun / stumble / cooldown, the runner is not hidden / in a safe room / in a vent / on a link, the runner is 2.2 to
3.5 cells away (Normal), 4.5 (Hard), 5.5 (Nightmare), the whole capsule line to the runner is clear (walls, props and closed doors block it: the same sweep chase uses), neither end is within
1.5 cells of a level link (ladder, stairs, manhole, grate, elevator, and the shared drop links once they exist: they are `LevelLink`s, so they are covered automatically through
`brain.near_link`), then a roll: 0.35 per eligible second times F (about 4 % Normal, 35 % Hard, 56 % Nightmare) and the budget.

The leap: 0.45 to 0.5 s at 7.2 m/s, direction locked at launch aimed 0.15 s ahead of the runner (a sidestep at launch dodges it). Contact is the ordinary catch (escape struggle, not instant
death). **The only cue is a single footfall as she launches** (`Sound.hunter_footstep`); the pose is the existing `charge` clip. Hit a wall, prop or door and she is stunned 0.8 s.
Land and she **stumbles**: 1.6 s (Normal) / 1.1 s (Hard) / 0.8 s (Nightmare) at 0.3x speed and **cannot catch**; the runner's hop clears the leap if timed.

| | Normal | Hard | Nightmare |
| --- | --- | --- | --- |
| cooldown after landing | 120 s | 28 s | 18 s |
| per chase | 1 | 2 | 2 |
| leap length | 0.45 s | 0.5 s | 0.5 s |

## Burst, intercept, door slam

| Ability | Who (Normal / Hard+) | Trigger | Normal | Hard | Nightmare |
| --- | --- | --- | --- | --- | --- |
| **Burst** after losing sight | Quenelle / + Ferryn, Umbriel | chase sight lost | 12 %: +12 % for 1.0 s, 90 s cooldown | 60 %: +25 % for 1.6 s, 25 s | 100 %: +40 % for 2.2 s, 25 s |
| **Intercept** | Mavrine / + Kathy, Quenelle | chase sight lost | 30 %: aims 0.4 s ahead of the runner | 1.0 s ahead | 1.8 s ahead |
| **Door slam-through** | Elise / + Javelle, Solyth | chasing, reaches a closed room door | 10 % of doors, door open 8 s | every door, 20 s | 35 s |

A slammed door is broken open (loud: `Sound.door_breach`) and put back (closed, working) when its time is up. Counterplay: break line of sight and change direction before a burst ends;
double back at a corner against an intercept; the slam only costs you the door as a barricade.

## Switching them off

`RoomState.hunter_abilities` (host's lobby toggle) or `HardAbilities.enabled = false` (code / tests). Relaxed never has them regardless.

## Hunter director (all modes)

`HunterDirector` (`src/game/hunter_director.gd`) runs host-side once per level and makes the hunters cooperate on every mode. It only gives
wandering or idle hunters somewhere to investigate (`HunterBrain.direct_to`); chasing, stunned and inactive hunters are left alone.

| Mode | Call reach (cells) | Team size | Flank | Cover an exit | Cap per runner | Tick |
| --- | --- | --- | --- | --- | --- | --- |
| Relaxed | 10 | 1 | never | never | 2 | 2.0 s |
| Normal | 16 | 2 | rare (10%) | occasional (25%) | 3 | 1.5 s |
| Hard | 24 | 2 | 60% | 50% | 3 | 1.0 s |
| Nightmare | 40 | up to 3 | always | 80% | 4 | 0.7 s |

- **Share:** a hunter that sees a runner calls up the nearest idle hunters within reach.
- **Split:** the first goes straight in; the others flank (a point beside the runner's escape line) or cover the nearest relay.
- **Scatter:** idle hunters standing within the mode's gap of each other walk apart, unless a runner is close.
- **No overload:** at most `cap` hunters are committed to one runner; surplus directed hunters are sent away.

Validated by `hunter_director`.
