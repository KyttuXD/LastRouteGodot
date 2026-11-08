# Hunter abilities for Normal, Hard and Nightmare

Extra, persona-anchored abilities on top of each hunter's own gimmick: **Relaxed gets none; Normal gets every one very rarely; Hard has them regularly; Nightmare more often and
stronger.** Code: `HardAbilities` (`game/hunters/ai/hard_abilities.gd`, one component per brain: `HunterBrain.hard`), host-simulated like every brain, visible state replicated with the
hunter report (`"hard"`). Suite: `hard_abilities`. There is no separate room setting: abilities follow the difficulty alone (Relaxed none, Normal very rare, Hard regular, Nightmare full); the staging menu's difficulty buttons describe it (`RoomState.DIFFICULTY_BLURBS`).

Built: the **pounce**, the **sprint burst** after losing sight, **intercept** and the **door slam-through** (`HardAbilities`); the **hunter director**; the **difficulty tweaks** the brain reads; and **vent routes** for Hard and Nightmare. Persona gimmicks that already change with difficulty are listed after those. Code bugs against this spec are under [For the maintainer to check](#for-the-maintainer-to-check).

## How rare is "rare"

- **FREQUENCY** is an on/off gate: Relaxed 0 (off), Normal 0.12, Hard 1.0, Nightmare 1.6 (`HardAbilities.FREQUENCY`). Only a positive value enables the abilities. It does not multiply the rolls. Each ability uses the chance in its own table (Normal slams about 10% of doors, which `hard_abilities` locks).
- **Cooldowns** are explicit per mode.
- **Party budget per ability**: at most one activation of an ability anywhere in the party per 360 s (Normal), 45 s (Hard), 25 s (Nightmare), however many hunters carry it (spawn growth
  cannot make Normal busy). The pounce also never lands twice on one runner within 10 s.

## The pounce (no wind-up, no cue)

Who (build / persona), per mode:

| Normal | Hard | Nightmare |
| --- | --- | --- |
| Haelith (eager wolf-dog), Red Void (halls only) | + Solyth (hot-tempered: only when the runner is warm, temperature >= 60), Xivvy (hyper) | + Black Void (only if she has been unwatched for 3 s), Nyxie (only while the runner's flashlight is off) |

Launch needs ALL of: she is chasing with a live sighting, no stun / stumble / cooldown, the runner is not hidden / in a safe room / in a vent / on a link, the runner is 2.2–3.5 cells away on Normal, 2.2–4.5 on Hard, 2.2–5.5 on Nightmare (the near edge stays 2.2), the whole capsule line to the runner is clear (walls, props and closed doors block it: the same sweep chase uses), neither end is within
1.5 cells of a level link (ladder, stairs, manhole, grate, elevator, and the shared drop links once they exist: they are `LevelLink`s, so they are covered automatically through
`brain.near_link`), then a roll at the mode's stored rate: 0.35 per eligible second on Normal and Hard, 0.56 on Nightmare. `FREQUENCY` is not multiplied in. The party budget still applies. Red Void's halls-only check (`room_at` empty) applies on every mode she can pounce.

The leap: 0.45 to 0.5 s at 7.2 m/s, direction locked at launch aimed 0.15 s ahead of the runner (a sidestep at launch dodges it). Contact is the ordinary catch (escape struggle, not instant
death). **The only cue is a single footfall as she launches** (`Sound.hunter_footstep`); the pose is the existing `charge` clip. Hit a wall, prop or door and she is stunned 0.8 s, and that same per-mode cooldown starts.
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
| **Intercept** | Mavrine / + Kathy, Quenelle | chase sight lost | 30 %: aims 0.4 s ahead of the runner | always: 1.0 s ahead | always: 1.8 s ahead |
| **Door slam-through** | Elise / + Javelle, Solyth | chasing, reaches a closed room door | 10 % of doors, door open 8 s | every door, 20 s | 35 s |

Hard and Nightmare roll the slam on every closed door she reaches. The party budget still allows one slam in the party at a time (45 s on Hard, 25 s on Nightmare). A slammed door is broken open (loud: `Sound.door_breach`) and put back (closed, working) when its time is up. Quenelle on Hard and Nightmare can burst and intercept on the same lost sighting; each spends its own budget. Counterplay: break line of sight and change direction before a burst ends;
double back at a corner against an intercept; the slam only costs you the door as a barricade.

## Switching them off

`HardAbilities.enabled = false` (code / tests only; the room has no toggle, and old saved values are ignored). Relaxed never has them regardless.

## Hunter director (all modes)

`HunterDirector` (`game/hunters/ai/hunter_director.gd`) runs host-side once per level and makes the hunters cooperate on every mode. It only gives
wandering or idle hunters somewhere to investigate (`HunterBrain.direct_to`); chasing, stunned and inactive hunters are left alone.

| Mode | Call reach (cells) | Share roll | Team size | Flank | Cover an exit | Cap per runner | Gap (cells) | Tick |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Relaxed | 10 | 50% | 1 | never | never | 2 | 7 | 2.0 s |
| Normal | 16 | 80% | 2 | rare (10%) | occasional (25%) | 3 | 8 | 1.5 s |
| Hard | 24 | always | 2 | 60% | 50% | 3 | 9 | 1.0 s |
| Nightmare | 40 | always | up to 3 | always | 80% | 4 | 10 | 0.7 s |

- **Share:** a hunter that sees a runner calls the nearest idle hunters within reach. Each candidate passes the mode's share roll. The call is remembered for 9 s (`DIRECTED_HOLD`).
- **Split:** the first called hunter goes straight to the runner. Each later one rolls flank, and rolls cover only when that flank roll misses. A flank point is 4 cells off the spotter-to-runner line, rotated ±1.2 rad. Cover is the nearest relay within 16 cells, otherwise 6 cells ahead along that line.
- **Scatter:** idle hunters standing within the mode's gap walk apart (held 16 s), unless a runner is within 12 cells (`SCATTER_CLEAR`).
- **No overload:** at most `cap` hunters are committed to one runner; surplus directed hunters are sent about 14 cells away.
- **Separation:** every frame, on every mode, active hunters closer than 1.1 cells push apart at 2.5 cells/s. A push into a wall or prop is skipped. Chasers are included; this is the one director rule that moves a hunter who is already chasing.

Validated by `hunter_director`.

## Difficulty tweaks

`GameConfig.DIFFICULTY_PROFILES`, read by `HunterBrain.difficulty_profile` and by the route for hide checks, the taser and the escape stun. `hard_abilities` locks the direction of these (sight, hearing, search, hide checks and relay-alert fields rise; stamina drain, hide tell, taser, escape stun, spawn distance and emote rates fall), Nightmare search time at 5 s, Relaxed hide-checks at 0, and escape presses staying at 6 (`GameConfig.ESCAPE_PRESSES`). Safe rooms per floor are `SAFE_ZONE_LIMITS_BY_DIFFICULTY`.

| | Relaxed | Normal | Hard | Nightmare |
| --- | --- | --- | --- | --- |
| hunter speed | 0.82 | 1.00 | 1.085 | 1.17 |
| sight | 0.86 | 1.02 | 1.10 | 1.22 |
| hearing | 0.86 | 1.03 | 1.12 | 1.25 |
| capture distance | 0.90 | 1.00 | 1.04 | 1.08 |
| search time (s) | 3.2 | 3.4 | 4.0 | 5.0 |
| lost-sight grace (s) | 3.0 | 3.2 | 3.6 | 4.5 |
| chase stamina drain / s | 14.0 | 13.5 | 12.0 | 10.0 |
| hide tell (s) | 1.6 | 1.5 | 1.3 | 1.0 |
| hide trail (cells) | 3.0 | 3.2 | 3.5 | 4.0 |
| hide cooldown (s) | 20 | 19 | 16 | 12 |
| hide-spot search chance | 0 | 0.05 | 0.25 | 0.45 |
| camp limit (s) | 6 | 9 | 12 | 15 |
| taser stun (s) | 2.8 | 2.7 | 2.4 | 2.0 |
| taser cooldown (s) | 8.0 | 8.5 | 9.0 | 10.0 |
| escape stun (s) | 3.0 | 2.9 | 2.6 | 2.2 |
| spawn distance (cells) | 12 | 12 | 11 | 10 |
| emote on spot | 0.30 | 0.27 | 0.15 | 0.08 |
| emote while chasing | 1.00 | 0.90 | 0.50 | 0.25 |
| relay alert radius (cells) | 0 | 8 | 18 | 30 |
| relay alert chance | 0 | 0.25 | 1 | 1 |
| safe rooms | 3 | 2 | 1 | 0 |

Hide-spot search (`hide_random`) is the chance a search walks to the hiding spot nearest the last sighting, within 8 cells, instead of a random point beside it. Camp limit is how long she will stand on one hidden runner before she leaves (`HunterBrain._camp_guard`, radius 2 cells, then a 30 s ignore). `room` locks the Hard column of this table, including the relay-alert pair.

On the endless route the first hunter wakes after 3 / 1 / 0 / 0 relays (Relaxed / Normal / Hard / Nightmare). Population then grows by one hunter every 3 / 2 / 1 / 1 relays. Nightmare starts at 2 awake instead of 1, so 0 relays is 2 hunters and 3 relays is 5 (`streamed_hunter_population`). Gray Void's pressure clocks, separate from her own grace inside the gimmick, are 360 / 255 / 135 / 105 s of idle and 240 / 142 / 80 / 60 s of standing still.

The same profile also scales the runner (move speed, lamp drain, sprint drain). Those rows live in `GameConfig` and are outside this hunter list.

## Vents

Physical ducts are [VENTS.md](VENTS.md). Who takes one (`VentNav.uses_vents`, `HunterBrain._vent_step`):

- **Verrine** always hunts the ducts, through her own gimmick. She does not use this shared route.
- **Every other hunter** only on Hard and Nightmare, only while chasing or investigating, and only when the vent route is at most half the floor path (`VentNav.SHORTER_RATIO` = 0.5). The route is: walk to the entry grate, climb in, crawl, climb out.

## Gimmicks that change with difficulty

These are the persona scripts, not `HardAbilities`. Hard uses the Normal number wherever a row names Nightmare only.

| Hunter | What the code does |
| --- | --- |
| Ilyra | Shadow-pounce delay is 15 s (`ILYRA_POUNCE_DELAY`). Nightmare is 0 s. |
| Quenelle | Flashlight lock is 8 s. Nightmare is 5 s (`QUENELLE_NIGHTMARE_LOCK_SECONDS`). |
| Gray Void | Relay grace 180 s, idle 45 s, 2.5 s per signal node. Nightmare is 120 s, 30 s and 1.8 s. |
| Glyra | Hunt speed ×1.3 on Normal and Hard, ×1.5 on Nightmare. A wound music box plays 45 s / 35 s / 25 s (Normal / Hard / Nightmare). |
| Solyth, Wynelle | Relaxed keeps them in the roster and never wakes them. |

## Peek, inspect, naps, seats

Corner peek (`HunterPeek.DIFFICULTY`): chance scale 1.0 / 1.15 / 1.3, reaction 0.45 / 0.25 / 0.12 s, ambush wait 2.5 / 2.0 / 1.6 s (Normal / Hard / Nightmare). The scale multiplies that hunter's own peek chance and is clamped to 1.

Locker inspect (`HunterInspect.DIFFICULTY`): chance scale 1.0 / 1.15 / 1.3, linger 1.5 / 2.0 / 2.5 s, cooldown 40 / 30 / 22 s.

Naps (`HunterNaps`, [REST_AND_SLEEP.md](REST_AND_SLEEP.md)): chance per patrol second 0.02 / 0.012 / 0.003 / 0 (Relaxed / Normal / Hard / Nightmare). Nightmare never naps.

Seats (`HunterSeats`): chance per patrol second 0.012 / 0.007 / 0.002 / 0. Nightmare never sits.

## For the maintainer to check

Code was left as it is. These are the mismatches.

1. **A runner in a duct is not marked `in_vent` on the live target.** The pounce refuses `target.in_vent` and `target.on_link`. `_hunter_target` in `game/infinite_route/infinite_route_test.gd` sets `duct` from the crawl and never sets `in_vent` or `on_link`. `PlayerController3D.in_vent` is the duct flag, and guest snapshots copy it (`remote_players.gd`), so a guest can be protected while the host's own runner is not. The 1.5-cell `near_link` check is wired and is a separate gate. The suite only passes because it sets `in_vent` on the stub target.

2. **The hop does not clear the leap.** Capture is planar distance in `HunterBrain.update`. A jump never sets a flag the pounce or the catch reads, so timing a hop does not beat contact.

3. **Intercept spends the party budget before the aim point is known to be open.** `_on_sight_lost` calls `_budget_ok("intercept", true)` and then `nearest_open_position`. An empty result still consumes the budget and does not move `last_known`.

4. **Nightmare cover does not run.** Flank is rolled first; cover is the else. Nightmare flank is 1.0, so the 80% cover roll is skipped. On Hard the 50% cover roll only happens after the 60% flank roll misses (about 20% of extra hunters). The table lists the stored roll thresholds. Confirm whether cover should be its own hunter in the team.

5. **`relay_alert_radius` and `relay_alert_chance` are in the profile above, and `hard_abilities` plus `room` lock the numbers, and nothing in gameplay reads them.**

6. **Relaxed peek and inspect use the Normal row.** `HunterPeek.DIFFICULTY` and `HunterInspect.DIFFICULTY` have no `relaxed` entry, so `difficulty()` falls back to Normal.

7. **Named in the gimmick comments, not built.** Umbriel's Nightmare copy of the disguised hunter's abilities (`nightmareCopiesAbilities`) is cosmetic on every mode. Loxelle's hiding-spot regen is 30 s on every mode (`LOXELLE_REGEN_SECONDS`); the Nightmare split is absent. Opalie does not retarget onto Briselle's relay on Nightmare. Those comments still say the port has no difficulty selection; Ilyra, Quenelle and Gray Void already branch on Nightmare.

8. **Zellia's fatal deal is only on the finite route.** `main_3d.gd` rolls `ZELLIA_DEATH_CHANCE` (2% / 5% / 7.5% / 12%). The endless route never handles a Zellia trade. `zellia_gimmick.gd` describes that finite-route roll.

9. **Door slam is called from the endless route only** (`infinite_route_test.gd` `_operate_hunter_room_door`). `main_3d.gd` does not call `door_slam_seconds`.
