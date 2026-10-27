# The City's secret creatures (white and black wolf spider, working names)

Two secret hunters for **KYTTU: The City**, made from KT's own `white_wolf_spider.bbmodel` and `black_wolf_spider.bbmodel` (two variants of one species).
**Status: built but OFF** (KT's decision): `SecretCreatures.TRIGGER = "off"`, so nothing spawns by itself in normal play; only the admin hunter
picker can summon them, for testing. The validator checks the default is off and that "off" leaves no trace. It is meant to stay secret: it is
**not** in `HunterRoster`, the dossier lists, the random draw, loading tips, story text or any player-facing string, and
nothing says it exists until the player has met it. This document and the files named in it are the only places that
mention it (the `secret_creature` suite greps the whole project to keep that true).

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
| City trigger and spawn (new file, one hook) | `src/game/city_secrets.gd` |
| Capture tool, validator | `tools/look/creature_check.tscn`, `scripts/validate_secret_creature.gd` |

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

## The trigger (`SecretCreatures.TRIGGER`, default `"off"`)

City only (`CitySecrets` does nothing unless the route's generator reports biome `city`), host only, once per run (a creature that
already exists, or was removed by an admin, counts as fired). It appears 16-23 cells from the runner on an open garden/plaza/path cell
(seeded by the route seed), already barking.

| Option | What the player does | Why |
| --- | --- | --- |
| `garden_vigil` (**default**) | stands **still** in a garden with the **flashlight off** for 45 s (moving, the light, or leaving drains it twice as fast) | nothing in normal play looks like this: least discoverable, still fair (the bark comes first) |
| `fountains` | stands at all four fountains (roundabout, both garden fountains, the grand plaza pool) in one run | discoverable by a curious explorer |
| `off` (**shipped default**) | never | nothing spawns by itself; admin picker only |

Both trigger implementations stay behind the constant for later. **Question for KT (answered for now: off).**

### Relationship of the two (`SecretCreatures.RELATIONSHIP`, only matters once a trigger is armed)

1. `black_follows_white` (**default**): the first trigger brings the white one; the black one only comes for a runner who has **met** the white one (line of sight within 14 cells), on a second trigger. Least intrusive and the most telegraphed: you learn the species first.
2. `black_rare`: every trigger brings exactly one creature, the black one 1 time in 4 (seeded by the route seed, so every peer agrees). Simple; a first-time player can meet the dangerous one.
3. `pair`: both at once (a few cells apart): the hardest, no learning curve.

**Question for KT:** which relationship do you prefer? Default stays the first until you say.

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

## Route hook (the City lane adds these three lines to `src/infinite_route_test.gd`; they are already in this branch)

```gdscript
var _city_secrets := CitySecrets.new()                 # next to _hunter_emoter
_city_secrets.update(self, delta)                      # in _update_hunters, after the simulates() guard
or entity_id.begins_with("SECRET:")                    # next to the "ADMIN:" check in _repair_duplicate_hunter_identities
```

The City layout is read through the generator's `layout` object (`GARDENS`, `ROUNDABOUT_CENTER`, `GRAND_PLAZA`, `ORIGIN_OFFSET`, `is_open`, `kind_at`),
so the file compiles on a branch without the City. Other small edits: `HunterRoster.get_identity`, `HunterGimmick.for_id`, `HunterView3D`
(delegates to `CreatureView`), `DeathLines.pick`, `Backend` discovery id check, `Sound.spider_bark`, the admin picker lists, the dossier
lists in `pause_menu.gd` / `room_lobby.gd`, and the two admin-picker size assertions in the validators.

## Known limits / follow-ups

* Only the local (host) runner can start the trigger; a co-op guest lingering in a garden does not.
* The creature takes one slot of the streamed hunter population while it exists.
* A creature's phase is not saved with the run: after a reload it is back to lurking at the spot where it was saved.
* Nothing can kill it yet (`CreatureView.play_death()` exists for that day); the `death` clip is checked in the contact sheets only.
* The in-City behaviour has been exercised on the maze route and with a fake City layout; it needs a playtest in the real City once the City lane merges.

## Tests

`godot --headless res://scenes/validate.tscn -- secret_creature` (run on the test machines): both models and clips, the shipped trigger is off and leaves no trace, the three relationship options, secrecy (roster, dossier, draw,
death lines in debug vs release), behaviour (lurk, bark head start, hunt, capture, shelter, cooldown, flashlight, hidden runner), determinism
and network round trip, trigger (never in the maze, vigil build/drain, seeded lair), the real `HunterView3D`, a live streamed route
(admin summon and the City spawn path), and the whole-project grep for hints.
