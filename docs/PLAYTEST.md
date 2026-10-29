# Playtest system (bots and agents that play the real game)

Kyttu's Lab can be played by a **bot** (automated, headless, many seeds in parallel) or by a **Claude agent** (step by step with
screenshots) through one small protocol. Everything runs on the TEST machines (Mac mini, Windows PCs); this Mac only edits and drives.

## Safety
- The bridge exists only in **debug builds started with `--playtest`** (or `--playtest-runner`). Release templates never qualify
  (`OS.has_feature("template_release")`), a normal debug run is untouched (the autoload does not process, opens no socket, installs no logger).
- The TCP server binds **127.0.0.1 only**. Use an SSH tunnel to reach it from another machine.
- A playtest is a **DEBUG RUN** (`GameState.debug_run`): no progress, discoveries or accounts are written.
- Online bots refuse production (`:8105`) unless the process was started with `--i-know-this-is-production`. Co-op bots use a local backend
  by default; the TEST instance (`REMOTE=1 BACKEND_URL=...:8205`) is allowed.
- Windowed playtest windows never pause on focus loss (`PauseMenu._handle_focus_lost` returns when the bridge is enabled).

## Quick start
```sh
# one headless bot run (fast, ~3x real time because of --fixed-fps 60), on the Mac mini:
Claude-Setup/mini-run.sh . <lane> --godot "--fixed-fps 60 res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route --scenario=survive --seed=ALPHA --minutes=5"
# a swarm over several machines, one summary:
tools/playtest/swarm.py --seeds 8 --minutes 8 --machines mini,ak-bee
# a bot party (host + N guests) on one machine:
Claude-Setup/mini-run.sh . <lane> --sh "scripts/playtest_multi.sh --guests 2 --minutes 3"
# windowed run with screenshots (rendering check):
Claude-Setup/mini-run.sh . <lane> --scene "res://scenes/playtest_runner.tscn -- --playtest-runner --scenario=probe --probe-x=10 --probe-z=20 --out=.playtest/probe"
```
Exit code: `0` pass, `1` thresholds failed, `2` could not run (no bot for the game, bad scenario).

## Runner options
`--game --scenario --seed --difficulty --minutes` (game minutes) `--bot-seed --name --out --target --hunters --screenshots --passive --hash-frames`
and thresholds `--max-stuck=3 --max-soft-locks=0 --max-errors=0 --max-unreachable=6 --min-fps=0 --max-pitch-median-deg=15`.
`--observe-every=N` builds the bot's observation every Nth physics tick (default 1; `soak` 3): a full observation every tick
costs more than the game itself on old machines, so the fps of a run at 1 is not a player's fps.
Bot scenarios run with the master bus muted (`--mute=false` keeps the sound; `flythrough`/`sequence` keep it unless `--mute`).
Bot scenarios keep the mouse uncaptured (the look stick aims), so someone using the machine cannot turn the bot's view.

| scenario | what it does |
|---|---|
| `survive` | play for N minutes; a death shows the death scene, then the bot restarts like a player |
| `explore_coverage` | until `--target` distinct chunks were visited |
| `collect_relays` | until `--target` relays were collected |
| `reach_depth` | until `--target` depth |
| `menu_tour` | hub -> Last Route menu -> every safe button -> solo lobby -> a real route -> leave -> back to games -> hub; fails on engine errors, a lost way back, a scene that never loads |
| `death_scene_tour` | summons each hunter (`--hunters=a,b` or all A-Z + Void) next to a passive bot and records who killed, how fast, and the death line; fails on a missing line or an engine error; hunters that never kill (non-lethal by design) are listed, not failed |
| `coop_bot` | one client of a bot party (`--role=host|guest --dir=<shared> --guests=N`), driven by `scripts/playtest_multi.sh`; reports peers/remote bodies seen |
| `soak` | a long run for leak hunting (PerfLog measures). Plays like `survive` and on timers: changes level along 0, +1, -1, -2, -3 through real level links, put at each link's far end because the bot does not climb (`--level-every=150`, or `--hop-every=20` for quick hops). Every `--save-every=600` it saves into a scratch save folder with cloud off, leaves to the menu and CONTINUEs. Every `--pause-every=60` it opens the pause menu and flips the graphics quality and back. Every `--seam-every=90` it sprints across a chunk seam. It winds music boxes within 2.5 m, and `--hunters=all|N|ids` re-summons hunters after every restart. Stuck/unreachable limits scale with `--minutes`; fails when a save/load does not resume |
| `probe` | teleports to `--probe-x/--probe-z` (`--probe-y` for another level, e.g. `-3.96` in the sewer), takes 4 screenshots turning 90 degrees (windowed), optionally presses interact on the nearest `--probe-interact=ROOM_DOOR`; for looking at a stuck spot a bot found |

## Reports (`.playtest/<name>/`)
`report.json`, `report.md`, `events.jsonl`: outcome, game time, deaths (hunter + cause), relays, depth, chunk coverage, **stuck spots** (one per
spot within 3 m, with a repeat `count`, the focused interactable and the nearest ones), **soft-locks** (stuck > 12 s), **unreachable goals**
(nav found no path), **door failures**, the camera **pitch median** (fails beyond `--max-pitch-median-deg`: a bot that stares at the floor draws a different game), engine **errors/warnings** from the log, fps p5/avg and frame-time p95/max, sampled online peers. The swarm
writes `.playtest-results/<stamp>/summary.md` (+ `summary.json`) with a table per seed and the distinct problems across seeds.

## Protocol (agents)
Start any debug build with `--playtest=47600` (windowed, on a test machine); tunnel: `ssh -L 47600:127.0.0.1:47600 <host>`.
One JSON object per line; replies echo `id`. `tools/playtest/client.py` wraps it (stdlib only) and contains an example agent loop.

| cmd | fields | reply |
|---|---|---|
| `hello` | | protocol, games, version, revision |
| `start_run` | `game, seed, difficulty, debug` | `obs` |
| `observe` | | `obs` (see below) |
| `act` | `act` | applies input |
| `step` | `frames, act?, observe?` | advances N physics frames, then `obs` |
| `ui` / `press` / `action` | `name` | visible buttons / press one / pulse an input action (`ui_accept`, `ui_cancel`...) |
| `admin` | `name, ...` | debug helpers: `god, no_target, noclip, speed, teleport` |
| `time_scale` | `scale` | |
| `screenshot` | `path` | windowed runs only |
| `log` | `since` | engine errors/warnings since a sequence number |
| `leave_run` / `quit` | | |

`act = {"move": [strafe_right, forward], "look": [turn_right, look_down], "hold": {"sprint": true}, "pulse": ["interact"]}` (values -1..1). Input
goes through the real `Input` actions, so the player controller, pause menu and focus handling see exactly what a keyboard would send. Look uses the
controller-stick actions (no mouse capture needed, deterministic).

`obs` (Last Route): `frame, time, scene, fps, frame_ms, nodes, ui{buttons[]}, run{over, depth, score, relays, death}, player{pos, yaw, pitch, vel,
hidden, stamina, lamp, in_safe_room, item...}, focus{kind, prompt} (what interact would hit), world{chunk, region, relays[], batteries[], safe_zones[],
hiding_spots[]}, hunters[{id, state, pos, dist, los, stuck, stun}], interactables[{kind, pos, dist, completed, door_open}], online{peers, remotes}, log{errors}`.

### How an agent playtests step by step
1. Start the game windowed on the mini with `--playtest=47600`, open the tunnel, `client.hello()`.
2. `start_run(seed=...)`, then loop: `observe()` -> decide -> `step(6, act=...)`. Take a `screenshot()` whenever something looks wrong and read it.
3. `log()` after interesting moments; `admin("teleport", x=..., z=...)` to jump to a place a bot flagged.
4. For menus: `ui()` lists the buttons, `press("name")`, `action("ui_cancel")`.

## Bot adapters (one per game)
`src/playtest/bots/bot_adapter.gd` is the interface (`available, start_run, observe, decide, run_over, after_run_over, leave_run, attach, admin`).
A game registers its adapter with one key in `GameRegistry.GAMES`: `"playtest_bot": "res://src/playtest/bots/<game>_bot.gd"` (the City and Night Watch
lanes plug in this way; `city_bot.gd` / `night_watch_bot.gd` are stubs that report unavailable). `LastRouteBot` plans with the same
`StreamedHunterNavigation` the hunters use, steers with the look stick, collects relays, flees to safe rooms / hiding spots, walks to a spot in front
of closed doors and presses interact, and detects stuck spots and soft-locks.

## Determinism
`--fixed-fps 60` gives a fixed timestep; the bot uses a seeded RNG (`seed|bot-seed`). `--hash-frames=N` stores a hash of the observation at frame N
(`report.state_hash`); two runs with the same seed must match (`scripts/playtest_check.sh`).

## Checks
`scripts/validate_runner.gd` suite `playtest` (fast): off by default and release-safe, protocol answers, input round trip, adapters, thresholds, hashes.
`scripts/playtest_check.sh` (on a test machine): a 60 s bot run without stuck/soft-lock that finds a relay, the menu tour, and the determinism hash.

## Headless bots on one machine (load tests)

`bots.sh --local N` (or the Bot Tests menu's "Headless extras") adds N `--headless` bot guests on each picked mac/linux device,
besides its windowed bot. Headless runs take no screenshots. Measured on KT-Mini4-2 (M4, 10 cores, 16 GB) on 2026-10-28:
one headless host and N-1 guests in a TEST-service room, 4 minutes each. The machine was also running other lanes'
validators, so treat the CPU figures as upper bounds.

| bots | RSS per bot (avg / max) | CPU per bot | load avg (1 min) | fps avg / min | runs passed |
|-----:|------------------------:|------------:|-----------------:|--------------:|------------:|
| 2 | 692 / 730 MB | 44 % | 2.6 | 137 / 15 | 2 / 2 |
| 4 | 689 / 785 MB | 40 % | 3.3 | 140 / 16 | 3 / 4 (one soft lock) |
| 6 | 684 / 730 MB | 63 % | 6.1 | 136 / 1 | 6 / 6 |
| 8 | 694 / 833 MB | 68 % | 8.0 | 130 / 1 | 7 / 8 (one bot: 63 unreachable goals) |

- A 1-bot run is not a test: the host waits for a guest.
- Frame rates are uncapped.
- About 700 MB per bot means 8 bots use about 5.6 GB.
- From 6 bots up, short stalls drop a frame to 1 fps.
- So 6 is a comfortable count for a 10-core, 16 GB machine.

## NPC teammates: host cost

Measured on 2026-10-28 with a windowed host on KT-Mini4-1 (`--npcs=N`) and one headless guest on KT-Mini4-2, in a
TEST-service room, about 3 minutes each, after the first 30 s. Frame times are the p95 of each second's drawn frames; network is
the host's ENet bytes per second.

| NPCs | host fps avg / min | frame p95 (median second / worst) | host tx | host rx |
|-----:|-------------------:|----------------------------------:|--------:|--------:|
| 0 | 74 / 43 | 18.5 / 88 ms | 174 KB/s | 7.3 KB/s |
| 2 | 70 / 15 | 19.7 / 241 ms | 176 KB/s | 7.3 KB/s |
| 4 | 42 / 2 | 29.4 / 1249 ms | 156 KB/s | 7.0 KB/s |
| 8 | 52 / 1 | 23.4 / 1344 ms | 183 KB/s | 7.1 KB/s |

- **Network:** NPCs add little to host upload. Most of the 174 KB/s happens with no NPCs at all (the host's hunter and
  world broadcasts to one guest).
- **Unreliable rows:** the 4- and 8-NPC runs overlapped validator runs on the same machine, so their minimum fps and
  worst-second spikes are not NPC cost. Repeat those rows on an idle host before trusting them.
- **Median frame time:** it moves about 1–11 ms from 0 to 8 NPCs.
- **Headless bots:** see the table above.
