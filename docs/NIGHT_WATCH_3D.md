# Night Watch 3D (plan, audit and first playable slice)

Night Watch is the 2D browser game in `LastRoute/games/night-watch` (about 8,500 lines of plain ES modules, nine games sharing one roster, one save and one progression). KT decided to build it as a 3D game inside the Kyttu's Lab app, as the second card on the game hub. This page is the audit of the 2D game, the 2D to 3D mapping, the milestone plan, the slice that exists now and the open questions. Nothing here changes version information.

Related: [GAME_HUB.md](GAME_HUB.md) (registry, themes, the old port plan), [DEATH_SCENES.md](DEATH_SCENES.md), [HUNTER_PARITY.md](HUNTER_PARITY.md), [BLOCKY_HUNTERS.md](BLOCKY_HUNTERS.md).

## 1. What the 2D game is

A Five Nights at Freddy's style shift: you sit in a fixed office from 12 AM to 6 AM, hunters walk a building toward your doors, and you hold them off with a few tools and a limited resource. The 2D game is an "anthology" in the spirit of Help Wanted: each game is a miniature of one FNaF era, all sharing the same roster (24 Last Route hunters plus Kathy and Zellia).

| # | Mode (id) | Core loop | Tools | Resource / limit |
|---|---|---|---|---|
| 1 | Classic (`classic`) | 4 hunters walk a graph of 8 camera rooms toward two doors | doors A/D, door lights Q/E (held), 8 cameras (Space, 1-8, arrows) | power meter (percent) |
| 2 | Masked Hours (`mask`) | no doors; hall hunters, vent hunters, a music box | mask, flashlight, vent lights, wind the music box | flashlight battery, music box |
| 3 | Dead Air (`lure`) | one vent crawler plus phantoms that break systems; temperature swings | lure, vent seal, reboots, climate | systems down, temperature |
| 4 | Bedtime (`bedroom`) | no cameras, listen: closet, hall, bed | closet door, hall light, bed light (one hand at a time) | one battery, never recharges |
| 5 | The Facility (`story`) | six rooms, each with a station, ordered task list | station tasks | noise you make draws the others |
| 6 | The Descent (`descent`) | elevator shaft, repair wires/signal/pipes before she reaches the window | repair puzzles | time |
| 7 | Salvage Run (`dayshift`) | day budget shop, then salvage pieces at night for a quota | upgrades, doors, window | budget, quota |
| 8 | Open Air (`extra`) | three outdoor watches (rooftop, bus stop, campfire) | per watch | per watch |
| 9 | Mixed Shift (`mixed`) | 3-7 threats drawn each night, a pacing director; QUIET/STEADY/RESTLESS/CHAOS/ENDLESS | Classic's tools plus three vents | power, director pressure |

Progress is per level key `mode:index` (night, `beatFive`, `cleared`, stars, best hour); a mode's Custom Night (AI slider 0-20 per hunter, four presets, a score and rating) unlocks after night 5. Device settings: volume, Calm mode (no flicker), Scare (full / short / off). The 2D game keeps the account on the shared Last Route session (`/api/v1/saves/save`, game id `night-watch`), supports pause and resume of every game (`resume.js`), Zellia's headset call box (`callbox.js`), an admin/debug layer, and per-hunter death lines and scenes (`deathlines.js`, `scene.js`).

### 1.1 Classic in detail (the spine, and the first target)

- **Clock:** a night is 270 s (45 s per hour), 12 AM to 6 AM (`core/time.js`). AI steps up +1 at 3 AM and +2 from 4 AM. The same shift also scales the old eight-minute tuning by `TIME_SCALE`.
- **Building graph** (`classic-data.js`): stage, dining, backstage, west hall, supply closet, kitchen, east hall, east corner; doors L and R hang off the two halls; the office is one step from either door. Eight numbered cameras; each room has a stereo pan (-1 west to +1 east) so footsteps are positional.
- **Hunters and what is special about each:** Dovelle walks to the left door (from night 1). Ravelle takes the right door and, when a shut door turns her away, tries the other (from night 2). Aki only moves while the cameras are DOWN (from night 3). Ilyra freezes while you watch her room (from night 4). Nyxie never walks: when the power dies she reaches the office after a blackout whose length depends on her level (11 s at level 1 down to 4 s). Kathy hunts alone on night 7 (door light dips, flickers on hall cameras, a hum at the door; the K key "meets her eyes" to send her back).
- **Movement:** no fixed tick; after each move a hunter waits a random time from a 3 s window that slides with her AI level (level 1: 12.5-15.5 s; level 10: 8-11 s; level 20: 3-6 s; level 0 never moves). Per-night stretch `NIGHT_PACE` and wait spreads (+/-15%), phases (`pressure.js`) and a "focus" for how straight she walks. All from a seeded RNG, so the same seed replays the same night.
- **At the door:** an open unlit door gives a grace time before the attack (9.0 s on night 1 down to 5.8 s on night 6, never under 5.2 s). Two defences: shut the door for 0.45 s (she retreats two rooms) or hold the light on her (2.0-4.5 s by night) and she is pushed back to her start. Halfway through the stare-down she flinches. Two hunters can share a door (second one waits behind).
- **Power:** 100%, base drain 0.10%/s and 0.07%/s per device in use (door, light or camera), scaled by `TIME_SCALE`. At 0 the doors open and lights die and Nyxie comes.
- **Zellia's calls:** one scripted headset call per night (nights 1-7), subtitle box with a Mute button, typed out word by word.
- **Death:** a scare (full / short / off) then the CAUGHT card with the hunter's line, Retry and Menu. The Godot 2 game already has the same idea as `DeathMoment` and `death_lines.json` (see [DEATH_SCENES.md](DEATH_SCENES.md)).

## 2. Mapping 2D to 3D

| 2D concept | 3D plan | Source in Godot 2 |
|---|---|---|
| Fixed office picture with parallax | A real first-person office room: desk, chair, monitor, two doorways with sliding slabs; the player sits at the desk and can look around (limited yaw/pitch, free look optional) | new scene `scenes/night_watch.tscn`, new files under `src/night_watch/` |
| Door slab and light buttons (A/D/Q/E) | Interact with door buttons on the desk, or hotkeys A/D (doors) and held Q/E (lights); doors are cube slabs on a tween; lights are SpotLight3D shining down the hall (counted in the light budget) | `LampField` budget rules from [REF_LOOK.md](REF_LOOK.md), 2D key map kept |
| Camera view (8 cameras, map) | A desk monitor showing a `SubViewport` per camera (one rendered at a time, so one camera cost); the camera map is a UI panel | new `NightWatchMonitor` |
| Camera rooms | Small blocky rooms (stage, dining, backstage, halls, closet, kitchen, corner), cube props in the Godot 2 style, each with a `Camera3D` and a stand position per hunter | new `NightWatchBuilding` (own files, NEW props only) |
| Hunters (sprites with poses) | Blocky hunter models and clips (idle, walk, stun, emotes, scythe for Kathy) placed in the rooms from the graph; the door pose is the looming pose | `assets/hunters_blocky/<id>`, `HunterRoster`, `BlockyEmotes` |
| Hunter AI (`classic-logic.js`) | Ported 1:1 as pure GDScript (`night_watch_classic.gd`), deterministic from a seed, no scene dependency, so a headless validator can replay a night | new `NightWatchClassic` (RefCounted) |
| Power meter | HUD bar and a desk gauge; same drain numbers | `ui_hud_bar.gd` pattern |
| Shift clock | Wall clock model and HUD (12 AM to 6 AM, 270 s) | new |
| Zellia calls | Subtitle box (same typed-out style as `DeathMoment`), Mute key N | `death_moment.gd` pattern |
| Death scare and CAUGHT | No jumpscare (KT removed them): the existing `DeathMoment` line then the run-over card | `DeathMoment`, `DeathLines`, `run_report.gd` |
| Progress (`night`, `cleared`, Custom Night) | Account save namespaced `night_watch` (separate keys, backward compatible `game` field exactly as the City lane did) | `RunSaves`, `Backend`, `RoomState.game_id()` |
| Settings (volume, Calm, Scare) | Shared settings panel (Calm = no light flicker); the Scare setting becomes the existing `short_death_scenes` / reduced motion | `settings_panel.gd` |
| Pause and resume | Pause menu now; saved-night resume is a later milestone | `pause_menu.gd` |
| Admin overlay | Admin menu rows for Night Watch (set night, hunter levels, power, skip hour) | `admin_menu.gd` |
| Hub card | Unlock the card, launch the menu scene | `GameRegistry` |

## 3. What is new work in 3D

1. The office as a room (collision-free seat, head-turn limits, door frames that line up with the hall cameras).
2. The monitor with live feeds from small rooms, camera noise/glitch states, and positional audio (pan from the graph becomes real 3D audio from the hall).
3. Door and vent interaction that feels physical (button prompts, slab animation, light cone) and still obeys the 2D timings (0.45 s shut-door rule, light push times, door grace).
4. Hunters approaching through rooms you can only see on a feed, then standing in a real doorway; hunters at the door need a pose that reads in the light cone.
5. Light budget: only two door spot lights and the desk lamp are real lights; room feeds use emissive materials.
6. Camera-feed rendering cost: render only the active feed at a reduced resolution (SubViewport 480x270 matches the 2D picture, nearest filtering, no post effects).
7. Modes beyond Classic: mask/vents, bedroom (no cameras), facility tasks, descent puzzles, salvage shop, open air and Mixed Shift each need their own interaction set (see the milestone plan).

## 4. Milestones

| # | Milestone | Contents | Status |
|---|---|---|---|
| M0 | Plan | this page, hub entry, registry flip, menu | in this slice |
| M1 | Classic office and monitor | office room, desk, 4 camera rooms (slice) then all 8, monitor and map | slice has 4 rooms |
| M2 | Classic rules | `NightWatchClassic` port: graph, pacer, door grace, shut door, light push, Dovelle/Ravelle/Aki/Ilyra, Nyxie blackout, power, clock | slice has Dovelle, Ravelle, Aki |
| M3 | Win, death, saves | 6 AM win, DeathMoment, run-over card, night progress save, night select | slice (night select 1-3) |
| M4 | Classic complete | nights 1-6, Custom Night sliders, Kathy night 7, Zellia calls, resume | planned |
| M5 | Masked Hours + Bedtime | mask, flashlight, vents, music box; listen-only bedroom | planned |
| M6 | Dead Air, Facility, Descent | reboots/climate, six stations, repair puzzles | planned |
| M7 | Salvage Run + Open Air + Mixed Shift | shop, outdoor watches, director | planned |
| M8 | Polish | audio pass, accessibility (Calm, short scenes), multiplayer spectating of a friend's office (optional), web build | planned |

## 5. The first playable slice (this lane)

Entry: hub card NIGHT WATCH is unlocked and opens `scenes/night_watch_menu.tscn` (night select 1-3, BACK TO GAMES). The shift loads `scenes/night_watch.tscn`:

- **Office:** a blocky 6x4 m room, desk with monitor, left and right doorways with sliding slabs, a desk lamp; first-person seat with limited look (yaw +/-70, pitch +/-35).
- **Controls:** A / D toggle the left / right door, hold Q / E for the door light, Space opens/closes the monitor, 1-4 pick a camera, Esc pauses.
- **Monitor:** four live `SubViewport` feeds (stage, dining, west hall, east hall), the map, noise on switch.
- **Rules:** the pure `NightWatchClassic` port: Dovelle (left door), Ravelle (right door, alternates), Aki (only moves while the monitor is down); graph, pacer, grace, shut-door and light-push rules and the power meter exactly as in the 2D numbers; 270 s clock; win at 6 AM.
- **Death:** attack at the door ends the night with the `DeathMoment` (hunter name and line) and the run-over card with Retry and BACK TO GAMES.
- **Saves:** `night_watch` namespace (highest night cleared), account-synced when signed in.
- **Tests:** suite `night_watch` (scripts/validate_night_watch.gd): the port reproduces the 2D pacing numbers, deterministic replay, win and loss paths, door/light rules, power, saves namespace, hub card, office and monitor load.

Everything is deterministic from a seed, uses no post effects and adds no version information.

## 6. Risks

- **Scope.** Nine 2D games cannot be ported at once; the plan is Classic first (the spine and Mixed Shift's base), then one mode per milestone.
- **Readability.** A hunter at a doorway must read clearly in a door light cone and on a 480x270 feed at nearest filtering; blocky models were built for first-person chases at 3-10 m, so camera poses and door poses need a pass.
- **Feed cost.** Multiple `SubViewport` cameras can double the cost; only the active feed renders.
- **Duplicated rules.** Two implementations (2D JS and 3D GDScript) can drift. The pure port keeps the numbers in one table (`NightWatchClassic.NIGHT_LEVELS` etc.), and the validator checks them against values copied from the 2D docs.
- **Hub and save files** are shared with other lanes (hub, registry, room state); edits are additive.

## 7. Questions for KT

1. First-person feel: a seated office you look around in (this slice), or a walkable security room?
2. Should Night Watch be single-player only at first, or should a friend be able to spectate or share the office?
3. Which mode after Classic: Mixed Shift (a director and many threats), Bedtime (the audio-first one) or Masked Hours?
4. Keep the 45 s per hour night length, or longer in 3D?
5. Hunter art at doors: keep the blocky models or give Night Watch its own looming pose set?
