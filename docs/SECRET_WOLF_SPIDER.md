# The Inferno's secret creatures (white and black wolf spider, working names)

Two secret hunters, made from KT's own `white_wolf_spider.bbmodel` and `black_wolf_spider.bbmodel` (two variants of one species). They were first made
for KYTTU: The City (archived on `archive/city-20261027`); **their home is now Last Route's Inferno, level -3** (KT: "the spider dogs go in the inferno
area with larger biome spaces to traverse"). `SecretCreatures.TRIGGER = "inferno"`: once the local runner has spent 30 s on level -3 the host brings them
(solo or pair by game difficulty, see below); `"off"` stops anything spawning by itself (admin hunter picker only, and only on -3). They are meant to stay
secret: **not** in `HunterRoster`, the dossier lists, the random draw, loading tips, story text or any player-facing string, and nothing says they exist until
the player has met one. This document and the files named in it are the only places that mention them (the `secret_creature` suite greps the whole project).

## What was built

| Part | File |
| --- | --- |
| Source models (KT's, kept untouched as the source of truth) | `tools/city/white_wolf_spider.bbmodel`, `tools/city/black_wolf_spider.bbmodel` |
| Black clips: retargeted from the white ones (bone map documented in the file) | `tools/city/spider_clip_map.py` -> `tools/city/black_wolf_spider.clips.json` |
| bbmodel to glb converter (creature rigs, pure stdlib + Pillow) | `tools/city/bbmodel_creature.py` |
| Game models (white 1080 / black 1164 triangles, about 265 / 275 KB, LODs off, 6 clips each) + converter reports | `assets/city/white_wolf_spider/`, `assets/city/black_wolf_spider/` |
| Config, outside the roster (stats, collider, trigger choice, dossier + death-line placeholders) | `src/config/secret_creatures.gd` |
| Behaviour (lurk, bark, hunt, retreat; the black gimmick subclasses it with harsher numbers) | `src/game/hunter_gimmicks/white_wolf_spider_gimmick.gd`, `black_wolf_spider_gimmick.gd` |
| Presentation for the non-humanoid rig (clips, bark cue, collider) | `src/game_3d/creature_view.gd` |
| Inferno trigger, lair choice and spawn (new file, two hooks) | `src/game/inferno_secrets.gd` |
| Solo/pair rest and recall | `src/game/hunter_gimmicks/spider_pack.gd` |
| Capture tool, validator | `tools/look/creature_check.tscn`, `scripts/validate_secret_creature.gd` |
| Their catch: the pounce-and-pin grab (only style for creature rigs, docs/HUNTER_GRABS.md) | `data/grabs/white_wolf_spider.json`, `data/grabs/black_wolf_spider.json` |

Rebuild the glb after editing the bbmodel: `python3 tools/city/bbmodel_creature.py tools/city/white_wolf_spider.bbmodel assets/city/white_wolf_spider/white_wolf_spider.glb --scale 0.035`
For the black one: `python3 tools/city/spider_clip_map.py` (regenerates the retargeted clips) then
`python3 tools/city/bbmodel_creature.py tools/city/black_wolf_spider.bbmodel assets/city/black_wolf_spider/black_wolf_spider.glb --scale 0.035 --clips tools/city/black_wolf_spider.clips.json`
(then re-import in Godot; commit the regenerated `.import`, palette png and report). `--scale` is metres per Blockbench
unit: 0.035 makes it about 2 m tall at the head and 3.4 m wide with its legs.

### The model

A creature rig, not the shared humanoid rig: 91 cubes (the hidden `hitbox` cube is skipped), groups `root > thorax > abdomen/tail/neck > head > jaw/ears`
and eight legs with shin and foot. Clips come straight from the bbmodel: `idle` (4 s), `walk` (1.2 s), `sprint` (0.6 s)
loop; `bark` (0.9 s), `attack` (1.1 s), `death` (2.6 s) play once. The converter writes quaternion/translation tracks (Blockbench
ZYX order), embeds the 512 x 280 palette as a lossless indexed PNG, nearest filtering, and checks that every loop closes
exactly (`white_wolf_spider.glb.report.json`). Checked in the real game scene: head faces -Z (Godot forward), renders match
Blockbench's own render (attack clip at 0.5 s compared side by side), see the contact sheets:

* `docs/secret_wolf_spider/clips_3m_front34.png`, `clips_3m_side.png`, `clips_8m_front34.png` (idle, walk, sprint, bark, attack, death at two poses)
* `docs/secret_wolf_spider/in_game_next_to_kathy.png` (the real `HunterView3D`)

### The black variant's clips (it shipped with none)

The black rig is named and built differently (`body` instead of thorax + abdomen, `legXn_upper/_lower/_foot` instead of `legXn/shinXn/footXn`, an extra
`tail5`), and KT's model has no animations, so `spider_clip_map.py` retargets the white spider's six clips bone by bone (the mapping and the reasons are in
the file's header): thorax -> body; abdomen + abdomenRear are composed into tail1; tail5 is tail4 delayed 0.07 s at 115 %; neck/head/jaw by name; **legs and
ears side-flipped** (the white model calls the +X side "L", the black one calls it "R"; a bone keeps the side of the body it is on). Both rigs are modelled head toward -Z
with every rest rotation 0, so the keyframes transfer one to one. The clips are sampled at 24 fps and simplified (the key count stays small). A forward-kinematics
pass then checks the feet: for idle/walk/sprint/bark the body is lifted wherever a foot would sink below the floor, so **the feet stay on the ground** (the white
spider's own clips dip up to 0.3 m into the floor in the sprint; the black one is corrected). Loops close exactly. Checked in the real scene at 3 m and 8 m:
`docs/secret_wolf_spider/black_clips_3m_front34.png`, `black_clips_8m_front34.png`, `black_feet_on_ground_8m_side.png`.

## Behaviour (all numbers are constants at the top of the gimmick or `SecretCreatures`)

```
LURK -> BARK (1.25 s, stands still, bark clip + cue) -> HUNT (up to 7 s) -> RETREAT (home, fast) -> LURK (30 s cooldown)
```

* **Lurk:** it stands at its lair (where it spawned) and never wanders. A runner within 15 cells **with line of sight** (or a loud
  runner it can hear: sprinting is heard from about 20 cells, walking from 8, crouching barely) marks it.
* **Bark = the telegraph.** It barks once and does not move for 1.25 s: a head start. Everyone in range hears the cue (`Sound.spider_bark`,
  positional); guests play it from the replicated `bark_seq`. The bark also raises the runner's noise meter.
* **Hunt:** chase speed 4.9 cells/s (faster than any A-Z, about the Voids), poor eyes (sight 7), excellent ears (hearing 1.9). It follows the
  marked runner by sound and light for at most 7 s and is limited by its own stamina. It uses the existing hunter navigation (ground only,
  capsule-clear steering, stuck recovery) and the same capture rules as every hunter (proximity, no capture in a shelter or while hiding).
* **Ends:** a **shelter** (safe room) ends the hunt at once; a **flashlight beam held on it for a moment** drives it off; running out of
  breath or time ends it. It then hurries back to its lair and ignores runners for 30 s, so a shelter dash is never an endless loop.
* **Fair by construction:** the validator proves a standing runner 11 cells away is caught inside the burst (it is a real threat) while the
  bark head start, the shelter rule, the flashlight rule and the cooldown all hold.

Replication: it is a normal durable hunter (`world_state.hunters["SECRET:white_wolf_spider"]`) simulated by the host and streamed like
every other hunter; `WhiteWolfSpiderGimmick.network_state()` carries `phase` and `bark_seq`.

### White vs black

| | White | Black |
| --- | --- | --- |
| Chase speed / sight / hearing | 4.9 / 7.0 / 1.9 | 5.4 / 8.5 / 2.1 |
| Notices a runner within | 15 cells | 19 cells |
| Tell | bark (the cue), then 1.25 s standing still | hiss (a longer, lower cue), then 1.1 s standing still |
| Hunt | up to 7 s, 1.0x speed burst | up to 9 s, 1.05x speed burst |
| Counters | shelter, flashlight beam held on it, hiding, outlasting it | shelter, hiding, outlasting it (**it ignores the flashlight**) |
| Rests after a hunt | 30 s | 60 s |

## Home level and trigger (`SecretCreatures.HOME_LEVEL = -3`, `SecretCreatures.TRIGGER = "inferno"`)

`InfernoSecrets` (one instance on the route, host only) counts the seconds the local runner spends on level -3 (`DWELL_SECONDS` = 30; the clock does not run on
any other level and keeps what it has when the runner climbs back up). At zero it fires once per run (a creature that already exists, or was removed by an admin,
counts as fired): the creature(s) appear 16-23 cells from the runner on level -3, already telegraphing (bark or hiss), on ground that is reachable from the
runner. Same seed + difficulty gives the same lairs.

* **Lair choice:** candidates are sampled around the runner and ranked by open ground (share of the 7 x 7 square around the cell that a hunter can stand on):
  wide ground (>= 90% open: a cavern or a lava hall) first, then roomy ground (>= 60%), then anything. Legs sprawl 3.5 m, so they live in the big spaces.
* **Stays on -3:** the route's ramp/ladder traffic skips them (`SecretCreatures.stays_home`), so they never follow a runner up a ramp; they hunt anywhere on -3.
  The admin picker refuses to summon them on any other level.
* **Sound:** `spider_skitter` (a quick run of dry ticks while it walks/runs, within 30 m) and `inferno_crackle` (an ember crackle with a hollow knock now and then
  while one is within 45 m of the camera), both positional from the creature, plus the existing bark/hiss tells.
* **`TRIGGER = "off"`:** nothing ever spawns by itself; the validator checks that off leaves no trace.
* Needs from the sewer lane for level -3: several open spaces of at least 14 x 14 cells (ideally 20 x 20+, ceiling >= 4 m) joined by halls >= 5 cells wide,
  one within about a chunk of any point, all connected to the ramp landings (the lair choice derives open ground from the chunk grid, no API needed).

### Relationship of the two (`SecretCreatures.RELATIONSHIP`, only matters once the trigger fires)

**Default `"difficulty"` (KT's decision): both creatures, as a SOLO or a PAIR depending on the game difficulty.** `SecretCreatures.DIFFICULTY` is a table keyed by the real difficulty ids; the plan for a trigger is `plan_for(difficulty_id, route_seed)`, pure and seeded, so every peer agrees and a restart repeats it.

| difficulty | who comes | pair chance | notice | chase speed | rest | alert radius |
|---|---|---|---|---|---|---|
| `relaxed` | the white one, alone | 0 | x0.85 | x0.92 | x1.4 | x0.85 |
| `standard` | usually the white one alone, the black one alone 1 time in 4, a pair about 1 time in 10 | 10% | x1.0 | x1.0 | x1.0 | x1.0 |
| `hard` | a pair most of the time (the black one joins 3 s after the white one has noticed you), otherwise solo | 70% | x1.1 | x1.05 | x0.85 | x1.1 |
| `nightmare` | always a pair, spawned together and coordinated: the black one flanks while the white one barks | 100% | x1.2 | x1.1 | x0.7 | x1.2 |

(Knobs multiply the creature's own numbers: notice = sight/hearing, chase = chase speed, rest = the cooldown after a hunt, alert = how far the bark carries. Edit the table, nothing else.) The table has exactly the game's four difficulty ids (the suite fails if one is added or removed without a row); nightmare may not be selectable in the menu yet, its row is ready.

Pair rules: the two are placed at least `PAIR_MIN_GAP` (10 cells) apart, neither on top of the runner (the normal spawn-distance rule), and a coordinated pair flanks (at least `PAIR_FLANK_DEGREES` apart as seen from the runner). Tells are staggered (the white bark first, the black hiss `stagger` seconds later) so it is always telegraphed. They share a rest (`SpiderPack`): when one gives up or is shut out, both go home and neither starts another hunt until the shared cooldown ends, so there is no endless chain-hunt. The host decides everything and replicates the creatures like any hunter; clients never run the plan.

The admin hunter picker (the only listing) offers the white one, the black one and a `pair` entry that summons both, linked, with the current difficulty's knobs. The trigger stays **off** by default, so none of this happens by itself yet.

The older fixed options still work behind the constant: `black_follows_white` (the black one only after the white one has been met, on a second trigger), `black_rare` (one creature per trigger, the black one 1 time in 4), `pair` (both, always).

## Not visible before it is met

* Neither creature is in `HunterRoster.PROFILES`, `IMPLEMENTED_IDS`, `A_Z_IDS`, `VOID_IDS`, the dossier tables, `pick_for_floor` or any validator count (still 26 + 12).
* The pause/lobby dossier gets a "FOUND" section **only after** `Backend.account_discover_hunter` has recorded the encounter (account-only,
  never in a debug run, requires line of sight within 14 cells). Until then no row, no "undiscovered" placeholder, no counter.
* Deaths use `DeathLines` through a fallback in `SecretCreatures` (not the JSON catalog), one entry per creature (cause `white_wolf_spider` / `black_wolf_spider`): caption style, **placeholder text that only
  renders in debug builds**; a release build shows the generic line until KT writes real ones.
* Admin tools can summon it for testing (the hunter picker lists it): that is the only listing.

## Placeholders for KT

* Names: no canon identity exists (searched KT-Lore, the archives, dossier and roster docs), so **White Wolf Spider** and **Black Wolf Spider** are working names (`SecretCreatures.PROFILES`).
* Dossier text (`SecretCreatures.DOSSIER`), death lines (`SecretCreatures.DEATH`, marked `[PLACEHOLDER]`), the bark and hiss sounds (`Sound` cues `spider_bark`, `spider_hiss`, procedural).

## Route hook (`src/infinite_route_test.gd`)

```gdscript
var _inferno_secrets := InfernoSecrets.new()           # next to _hunter_emoter
_inferno_secrets.update(self, delta)                   # in _update_hunters, after the simulates() guard
or entity_id.begins_with("SECRET:")                    # next to the "ADMIN:" check in _repair_duplicate_hunter_identities
SecretCreatures.stays_home(brain.hunter_id)            # first guard in _hunter_ladder_step: never a ramp or ladder
```

Other small edits: `HunterRoster.get_identity`, `HunterGimmick.for_id`, `HunterView3D` (delegates to `CreatureView`), `DeathLines.pick`, `Backend` discovery id check,
`Sound.spider_bark/spider_hiss/spider_skitter/inferno_crackle`, the admin picker lists (+ the level check in the admin summon), the dossier lists in `pause_menu.gd` /
`room_lobby.gd`, and the two admin-picker size assertions in the validators.

## Known limits / follow-ups

* Only the local (host) runner can start the trigger; a co-op guest lingering on -3 does not.
* The creature takes one slot of the streamed hunter population while it exists.
* A creature's phase is not saved with the run: after a reload it is back to lurking at the spot where it was saved.
* Nothing can kill it yet (`CreatureView.play_death()` exists for that day); the `death` clip is checked in the contact sheets only.
* The Inferno behaviour is validated on a hand-made level -3 and (once the sewer lane's Inferno is on main) on the real streamed level; it needs a playtest there.

## Tests

`godot --headless res://scenes/validate.tscn -- secret_creature` (run on the test machines): both models and clips, secrecy (roster, dossier, draw, death lines in debug
vs release), behaviour (lurk, bark head start, hunt, capture, shelter, cooldown, flashlight, hidden runner), determinism and network round trip, the difficulty table
(complete, deterministic, solo/pair odds), the pack (staggered tells, shared rest, no chain-hunt), the Inferno trigger (only on -3, only after the dwell time, off leaves
no trace, one run = one fire, per-difficulty determinism, pair spacing/flank, wide ground preferred, always reachable, no floor = no spawn), the real `HunterView3D`, a live
streamed route (admin summon only on -3), and the whole-project grep for hints.
