# Hunter roster port plan

Working plan for porting LastRoute's 26 hunters. Built from a full audit of
every per-hunter file in the original (`src/game/hunters/*.js`,
cross-referenced against `hunter-gimmicks.js`, `hunter-ai.js`, and
`game-config.js`) against what this port actually has today.

**Status: 2 of 26 ported** — Dovelle (zero-gimmick baseline) and Quirith
(flashlight tracker). See `MIGRATION.md`'s "Hunter roster" section for how
they're wired.

## How a hunter gets added

1. Port her gimmick as a `HunterGimmick` subclass in
   `src/game/hunter_gimmicks/` — one script per hunter, mirroring the
   original's one-file-per-hunter layout. Override only the hooks she needs;
   each has a no-op default.
2. Register her in `HunterGimmick.for_id()`.
3. Add her tuning constants to `GameConfig` and an entry to
   `HunterRoster._identities()`, plus her id in `HunterRoster.IMPLEMENTED_IDS`.
4. Add a placeholder scene at `art/props-3d/characters/<id>.tscn`.

A hunter whose gimmick is **only different tuning numbers** needs no gimmick
class at all — steps 3 and 4 alone. The `HunterGimmick` hook surface
(`before_perception`, `speed_scale`) is meant to grow: adding a new hook of
that shape when a real hunter needs one is the established mechanism, not a
new system.

## Terminology

- **Self-contained** — portable today using only what exists now, plus a new
  `HunterGimmick` subclass (and possibly a new hook of the existing shape).
- **Needs-new-system** — requires simulation data or infrastructure that
  doesn't exist anywhere in this port yet.

## Recommended order

### Tier 1 — the two cheap unlocks (do these first)

Neither is a hunter; both are small changes that unblock many hunters at
once, and both are far cheaper than the big subsystems below.

| Unlock | Hunters unblocked | What it takes |
| --- | --- | --- |
| **Relay/battery collected-state wiring** | up to 6 — Briselle, Haelith, Opalie, Ysolde outright; Solyth, Zephyra partially | `facility_generator.gd` already declares a `"collected": false` key on every relay and battery, but nothing ever writes `true` to it — `interactable.gd`/`route_interactable_3d.gd`'s `activate()` only flips a local `completed` flag on the presentation node and bumps `GameState.relays_collected`. Any hunter reading `generator.relays`/`generator.batteries` today sees everything as uncollected. Fix: have `activate()` also update the matching generator entry. |
| **Directional flashlight beam-aim detection** | up to 5 — Aki, Ferryn, Ilyra outright; Briselle, Nyxie partially | The original's "lit by player beam" / "flash triggered" signal needs the player's *facing*, not just on/off. Both player controllers already compute a facing rotation; it's simply never threaded into the `target` dictionary passed to `HunterBrain.update()` (currently `position`/`hidden`/`in_safe_zone`/`noise`/`flashlight_on`). Add a `facing` field plus cone/dwell math — mechanically the same shape of change that `flashlight_on` was for Quirith. |

A third, trivial gap: **room-at(x, y) lookup**. Rooms carry bounding data but
there's no point→room query. Never gates anything on its own.

### Tier 2 — self-contained hunters, ascending complexity

| # | Hunter | Tier | Gimmick | Size |
| --- | --- | --- | --- | --- |
| 1 | **Eirys** | difficult | Cumulative ratchet: every second spent sprinting outside a safe zone (never decays); at 50s total she permanently locks into a blind chase. Sprint state is inferable from the existing per-frame `noise` value, since sprint noise is a distinct constant. Her `breachesHiding` flag is a pure no-op while hiding doesn't exist. | ~15-20 lines, 1 rule |
| 2 | **Xivvy** | intermediate | Auto-locks to chase on pure proximity (no sight/hearing), then chase speed permanently ramps with chase duration. Caveat: her lock radius scales with player exposure, which doesn't exist — evaluating the same formula at exposure's rest value (0) gives a constant 0.5× radius, a legitimate default rather than a fabricated number. Full fidelity on that one knob wants the exposure meter later. | ~20-25 lines, 2 rules |
| 3 | **Kathy** | difficult | A search-beam cone that spots the player past ordinary sight range. Needs new self-tracked facing bookkeeping (derived from her own movement) that no ported hunter has needed yet. Her second ability (`affectedSummon`) requires other already-active route hunters, which is structurally impossible at `ROUTE_HUNTER_COUNT = 1` in *both* codebases — permanently inert, not a blocker. | ~20-30 lines, 1 rule |
| 4 | **Umbriel** | difficult | Every 30s, disguises as a random other roster hunter. On Standard this is purely cosmetic — attribute-copying is Nightmare-only. Just a timer, an exclusion-aware random pick, and telling `HunterView3D` to load a different model than `brain.hunter_id` implies. **Best deferred until more of the roster exists**, since her disguise pool is whatever's ported. Only self-contained hunter that touches the presentation layer. | ~40-50 lines |
| 5 | **Ravelle** | difficult | Two invisible tripwires at doorway-shaped cells (detected by scanning `generator.grid`), refreshed every 30s unless triggered; crossing one locks chase and *permanently* adds speed. Her "fake doorway" decoy is consumed only by the original's renderer — zero gameplay logic reads it, so it's future art, not a dependency. | ~50-60 lines, 4-5 rules |
| 6 | **Mavrine** | intermediate | Periodically scans for a valid open cell (never on the player, never near start/lift/relays/hiding spots), drops an invisible ~6s tripwire "frame", pursues if crossed. Uses only already-public generator API. Most complex of the self-contained set: a 4-phase state machine plus a real candidate-search algorithm. | ~90-110 lines |

### Tier 3 — blocked on new systems

Grouped by what unblocks them. `(sec.)` = secondary/partial dependency.

| Subsystem | Hunters | Count |
| --- | --- | --- |
| Room/player temperature (+ heater station) | Loxelle, Solyth, Wynelle, Zephyra (sec.) | 4 |
| Hiding spots | Ceryth, Jyvra, Loxelle, Solyth (sec.) | 4 |
| Accumulating noise/corruption meter | Ferryn, Glyra | 2 |
| Audio system (positional / mimicked cues) | Haelith, Thessine | 2 |
| Concurrent multi-hunter activation | Nyxie, Solyth, Ysolde (sec.) | 2 (+1 sec.) |
| Exposure/sanity meter | Aki | 1 |
| Currency/inventory + shop UI | Zephyra | 1 |
| Player radar/gadget item | Porcelle | 1 |
| Vent-travel network | Verrine | 1 |
| Player stun/incapacitation state | Ilyra | 1 |
| Torch player ability | Ysolde (sec.) | 1 (sec.) |

Notes worth keeping:

- **Thessine** is mechanically *identical to Dovelle* without audio — her
  gimmick only ever plays fake sound cues and changes no state. She isn't
  degraded without an audio system, she's indistinguishable.
- **Jyvra** is an ordinary chaser whose entire identity is one hiding-spot
  twist. She'd be trivial to add today, but it would be a Dovelle reskin
  rather than a port of her.
- **Porcelle**'s AI needs nothing new (~4 lines); she's blocked purely
  because the player has no way to detect an invisible hunter without the
  radar gadget.
- **Wynelle** does *not* need multi-hunter concurrency — she fits the
  existing single-hunter slot, just activating on a temperature trigger
  instead of a relay count.
- **Concurrent multi-hunter activation** is a real structural change:
  `main_3d.gd` owns exactly one `hunter_view`, not a collection. Worth
  sequencing around whenever Nyxie/Solyth/Ysolde are tackled together.
- **Co-op/remote-player awareness** and **developer/debug mode** block
  *none* of the 24 — every such branch in the original is an optional QA or
  multiplayer path.

## Dead code in the original (don't port these)

`hunter-gimmicks.js` defines **eleven** gimmick types, but only **three** are
wired to any hunter via `HUNTER_ABILITIES`: `phantomExposure` (Aki),
`emberVeil` (Ferryn), `latticeMark` (Mavrine). The other eight —
`dualSensor`, `occlusionScan`, `coilTrace`, `carrierSweep`, `scentLine`,
`quietPerch`, `routeEcho`, `resonancePlate` — are orphaned, referenced by no
hunter. Likewise `jyvra.js`'s `resolveRouteEchoPrediction` and
`loxelle.js`'s `resolvePlateCharge` are unreachable (their hunters' real
abilities are `hidingTimeout` and `passiveIncinerator`/`breaksHiding`).

## Tuning reference

From `HUNTER_PROFILES` in the original's `game-config.js`. Radius is **0.22**
for every hunter (`hunterRadius`/`xivvyRadius`/`nyxieRadius` are separate
constants that all hold the same value).

| id | tier | baseSpeed | chaseSpeed | chaseProgScale | sightRange | hearingScale | spawnDistance |
|---|---|---|---|---|---|---|---|
| dovelle *(ported)* | easy | .80 | 3.55 | .18 | 8.0 | 1.00 | 12 |
| quirith *(ported)* | easy | .81 | 3.50 | .17 | 8.1 | 0.85 | 12 |
| aki | easy | .82 | 3.55 | .20 | 8.2 | 1.00 | 11 |
| briselle | easy | .84 | 3.62 | .18 | 7.7 | 1.00 | 12 |
| ceryth | intermediate | .78 | 3.45 | .17 | 8.6 | 0.88 | 12 |
| eirys | difficult | .82 | 3.58 | .18 | 8.1 | 1.05 | 12 |
| ferryn | intermediate | .80 | 2.75 | .17 | 8.3 | 0.92 | 12 |
| glyra | easy | .81 | 3.52 | .18 | 7.9 | 1.12 | 12 |
| haelith | easy | .83 | 3.60 | .18 | 7.8 | 1.18 | 12 |
| ilyra | intermediate | .77 | 3.68 | .17 | 8.7 | 0.80 | 12 |
| jyvra | easy | .80 | 3.56 | .18 | 8.0 | 1.00 | 12 |
| kathy | difficult | .82 | 4.15 | .20 | 8.2 | 1.00 | 16 |
| loxelle | easy | .80 | 3.555 | .18 | 7.9 | 1.12 | 13 |
| mavrine | intermediate | .80 | 3.50 | .17 | 8.2 | 0.95 | 12 |
| nyxie | special | .90 | 3.90 | .15 | 8.4 | 0.00 | 10 |
| opalie | easy | .83 | 3.47 | .18 | 7.7 | 1.10 | 13 |
| porcelle | intermediate | .80 | 3.55 | .17 | 8.0 | 0.90 | 13 |
| ravelle | difficult | .81 | 3.15 | .18 | 7.7 | 1.00 | 12 |
| solyth | special | .80 | 3.00 | .17 | 7.6 | 0.95 | 12 |
| thessine | intermediate | .78 | 3.44 | .17 | 8.4 | 0.90 | 13 |
| umbriel | difficult | .82 | 3.46 | .18 | 8.5 | 0.86 | 12 |
| verrine | intermediate | .83 | 3.66 | .18 | 7.7 | 1.10 | 13 |
| wynelle | difficult | .81 | 3.00 | .18 | 7.8 | 1.15 | 12 |
| xivvy | intermediate | .97 | 4.35 | .12 | 6.72 | 0.84 | 13 |
| ysolde | easy | .80 | 3.54 | .18 | 8.1 | 1.00 | 12 |
| zephyra | easy | .83 | 3.60 | .17 | 8.0 | 0.95 | 12 |

### Per-hunter ability constants

Only for hunters not yet ported. Source: `HUNTER_ABILITIES` in
`game-config.js`.

| Hunter | Ability constants |
| --- | --- |
| aki | `phantomExposure{initialDelay:10, burstInterval:5, burstCount:3}` |
| briselle | `saboteur{dwell:5, chance:.5}` |
| ceryth | `hidingTrap{lockSeconds:30, torchSeconds:2.5}` |
| eirys | `runningData{secondsToFull:50}`, `breachesHiding:true` |
| ferryn | `roundStalker{flashNoise:100}`; `emberVeil{exposureDuration:999, exposureDecay:1, revealedDuration:.01, veiledAlpha:.08}` |
| glyra | `musicBoxThreat{baySeconds:20, noisePerSecond:1}` |
| haelith | `relayPursuer:true`; hardcoded `AUDIBLE_RANGE=9`, `FOOTSTEP_INTERVAL=0.4` |
| ilyra | `cornerObserver{sightScale:1.8, stunSeconds:5, pounceDelay:15, banishSeconds:30}` |
| jyvra | `hidingTimeout{seconds:8}` (code fallback `ejectStall:2.2`) |
| kathy | `beamDetection{range:11.5, halfAngle:.24}`, `affectedSummon{checkInterval:5, spawnChance:.1}` |
| loxelle | `passiveIncinerator{interval:5, chance:.25, regenerateSeconds:60, easyRegenerateScale:.5}`, `breaksHiding{stallSeconds:10, reach:1.45, noise:11, temperatureIncrease:30}`, `nonLethal:true` |
| mavrine | `latticeMark{surveyDelay:6.2, surveyDuration:.9, projectionDuration:6, cooldownDuration:4.2, pingDuration:.45, triggerRadius:.62}` |
| nyxie | `darknessStalker{emptyDelay:10, timerDelay:120, nightmareTimerDelay:30, timerDespawnRange:7}` |
| opalie | `relayGuardian{suppressionRadius:1.5}` |
| porcelle | `radarOnly:true` |
| ravelle | `tripwireTrapper{refreshSeconds:30, count:2, triggerRadius:.8, speedPerTrigger:.08, fakeRoomSeconds:60}` |
| solyth | `heatManifest{threshold:100, reliefThreshold:95}` (+ `temperatureSyttuHidingBurnInterval:15`, `temperatureSyttuBatteryBurnInterval:30`) |
| thessine | `soundMimic{interval:10, chance:.5, rareChance:.08}` |
| umbriel | `shapeshifter{interval:30, excludedIds:["kathy"], nightmareCopiesAbilities:true}` |
| verrine | `ventLurker{count:4, initialSpeedScale:.4, speedPerSecond:.025, maximumSpeedScale:2.4}` |
| wynelle | `coldMaterializer{warmThreshold:60, deepColdThreshold:30, perDegreeRate:.5, deepColdRate:1, deathGraceSeconds:10, dematerializeResetProgress:50}` |
| xivvy | `flight:true`, `chaseAccelerator{speedPerSecond:.035, maximumSpeedScale:1.8, closeLockRadius:1.5, wingNoisePerSecond:1.2}` |
| ysolde | `batteryThief{stealRange:.8, torchRange:7}` |
| zephyra | `merchant{nightmareDeathChance:.1, pesticideSeconds:60, offers:{cool:{cost:2}, warm:{cost:2}, repair:{cost:3}, pesticide:{cost:4}}}` |

## Difficulty tiers and selection

From `NORMAL_ROUTE_HUNTER_TIERS`. The original weights a seeded draw across
all 26 by tier (Standard: easy .35 / intermediate .50 / difficult .15); this
port currently does a seeded uniform draw across `IMPLEMENTED_IDS` instead,
which is the honest equivalent for a small pool. Restore the real tier
weighting once enough of the roster exists to make it meaningful.

- **easy** — aki, briselle, dovelle, glyra, haelith, jyvra, loxelle, opalie, quirith, ysolde, zephyra
- **intermediate** — ceryth, ferryn, ilyra, mavrine, porcelle, thessine, verrine, xivvy
- **difficult** — eirys, kathy, ravelle, umbriel, wynelle
- **special** (never in the random draw; summoned by a rule) — solyth (temperature extreme), nyxie (darkness)
