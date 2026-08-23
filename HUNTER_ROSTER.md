# Hunter roster port plan

Working plan for porting LastRoute's 26 hunters. Built from a full audit of
every per-hunter file in the original (`src/game/hunters/*.js`,
cross-referenced against `hunter-gimmicks.js`, `hunter-ai.js`, and
`game-config.js`) against what this port actually has today.

**Status: 26 of 26 A-Z hunters ported, plus 12 Void incursion models.** Dovelle (baseline), Quirith (flashlight
tracker), Eirys (sprint ratchet), Xivvy (proximity lock + chase ramp), Kathy
(search beam), Ravelle (doorway tripwires), Mavrine (lattice mark), Umbriel
(shapeshifter), Wynelle (cold materializer), Thessine (see below), Haelith
(relay pursuer), Ysolde (battery thief), Opalie (relay guardian), Aki
(phantom exposure), Porcelle (radar-only), Jyvra (locker ejection), Loxelle
(passive incinerator), Ceryth (hiding trap), **Briselle** (relay sabotage +
resecure hold), **Ferryn** (permanent stalk + facility-wide scream),
**Glyra** (spawn-room music box), **Ilyra** (corner observer + shadow
pounce), **Verrine** (vent lurker) and **Zephyra** (coin exchange), plus the
two rule-summoned specials Nyxie (darkness stalker) and Solyth
(heat-summoned). See `MIGRATION.md`'s "Hunter roster" section for how
they're wired.

## Roster categories and discovery

The dossier now has three explicit sections: **A-Z Hunters**, **Void
Hunters**, and **Secret Characters** (currently marked coming soon). Names,
abilities, counterplay, and tuning are hidden until the signed-in player
personally discovers that hunter. Merely rolling a floor or receiving a host
snapshot does not unlock anything. Ordinary hunters unlock from a nearby,
clear encounter; Porcelle unlocks through her intended readable surface, the
full facility map. Discoveries live in the account progress document alongside
the optional route checkpoint, and clearing a route never clears the dossier.
Guests receive no permanent discovery data.

The twelve colour skins are the Void roster. Their models are visibly larger
than A-Z hunters, their baseline
speed/perception is more aggressive, and a deterministic incursion can add one
as an extra hunter from depth two onward.

The first shipped Void pass gives them a shared, honest `VOID INCURSION`
mechanic rather than inventing twelve half-implemented abilities. These are
the intended colour identities for later focused passes:

| Void | Candidate identity | Counterplay direction |
| --- | --- | --- |
| Black | Eats nearby light and creates moving dark pockets | carry reserve light and leave the drained region |
| Blue | Leaves a cold trail which slows prolonged pursuit | take warmer biome routes and avoid retracing it |
| Brown | Specializes in boards and damaged barriers | do not rely on a single barricaded choke point |
| Cyan | Interferes with taser charge and powered tools | use mechanical tools or fire the taser early |
| Gray | Moves while unobserved and holds still under scrutiny | coordinate sightlines instead of fleeing alone |
| Green | Creates temporary toxic area denial | rotate objectives before safe paths close |
| Orange | Telegraphs a short, violent burst charge | sidestep at the cue and force a wall impact |
| Pink | Mimics safe-room light and comfort audio | verify a safe-room marker before committing |
| Purple | Short-phases between connected dark cells | keep multiple exits and avoid isolated rooms |
| Red | Berserks after taking tool damage | stun to escape, not to start a long fight |
| White | Nearly blind but exceptionally sensitive to noise | walk, close interactions quietly, avoid impacts |
| Yellow | Disrupts powered lights and nearby switches | carry a flashlight and restore circuits behind it |

These rows are design commitments, not claims that the colour mechanics are
already live. The roster and dossier currently label them as aggressive extra
pursuers until each mechanic has its own authoritative co-op implementation
and validation.

## Current refinement pass

- Xivvy now owns a real looping `flight` clip. After a short pursuit takeoff,
  her presentation rises, floats, and flaps; she still uses grounded idle/walk
  before takeoff and after reset.
- Loxelle no longer deletes a locker on a timer from a distance. She approaches
  the target, braces, plays a charge animation, crosses the final gap, then
  breaks the locker and ejects its occupant on impact.
- Boarded doors and three-cell hallway barricades lose one authored plank per
  valid tool strike. Every strike still consumes durability, including the
  final one; collision opens only after the last piece breaks.

**The roster is complete.** Every hunter that had a gimmick to port now has
one; what remains beyond this point is polish (real art in place of the
honest placeholders — hiding spots, the music box, vent grates, coin
pickups — and the reserved Nightmare-only branches this file records as
deliberately unported), not new hunters.

**All 26 have models and tuning.** `HunterRoster.PROFILES` carries every
hunter's `HUNTER_PROFILES` row and `art/props-3d/characters/` has a model for
each, built by `tools/characters/build_hunters.py`. That is deliberately *not*
a claim that 26 are playable: `IMPLEMENTED_IDS` is the pool the game draws
from, and a hunter with a profile but no gimmick stays out of it, because
shipping her would be a Dovelle reskin wearing someone else's name. What it
buys is that adding a hunter is now one line plus her gimmick, that the draw
can be weighted by real tiers, and that Umbriel can wear the whole cast's faces
rather than only the finished ones.

**Thessine is fully ported.** Her gameplay-neutral audio mimic now rolls on the
authoritative hunter timer and broadcasts one false cue decision to every peer,
replaying an active hunter's real synthesized sound when possible and falling
back to her uncanny/rare cue pool otherwise.

**The tier-weighted draw is restored.** `pick_for_floor()` does the original's
difficulty-aware seeded pick rather than a uniform draw. Relaxed and Standard
use their source weights; Hard is the exact Standard/Nightmare midpoint; the
original Nightmare row is retained but that mode is not selectable until its
larger hunter lineup exists. A tier with nobody implemented drops out and the
rest renormalise. The `roster` check suite asserts all three live distributions,
that every implemented hunter is reachable, and that the draw is replay-stable.

Nyxie and Solyth are **specials**: registered but never entered into the
random draw, always present on a floor but inert, woken by their own rule
and hunting *alongside* whichever route hunter was drawn. That is why
`main_3d.gd` now holds a collection of hunters rather than one.

## How a hunter gets added

1. Port her gimmick as a `HunterGimmick` subclass in
   `src/game/hunter_gimmicks/` — one script per hunter, mirroring the
   original's one-file-per-hunter layout. Override only the hooks she needs;
   each has a no-op default.
2. Register her in `HunterGimmick.for_id()`.
3. Add her **ability** constants to `GameConfig` (ranges, intervals,
   thresholds — the things her gimmick script reads by name).
4. Add her id to `HunterRoster.IMPLEMENTED_IDS`.

Her movement/perception tuning and her model are already there — every hunter's
`HUNTER_PROFILES` row is in `HunterRoster.PROFILES` and every model is built.
A hunter whose gimmick is **only different tuning numbers** needs step 4 alone. The `HunterGimmick` hook surface
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
| **Directional flashlight beam-aim detection** — **BUILT** | Aki is **ported**; Ferryn and Ilyra still need a second system each | The original's "lit by player beam" / "flash triggered" signal needs the player's *facing*, not just on/off. Both player controllers already compute a facing rotation; it's simply never threaded into the `target` dictionary passed to `HunterBrain.update()` (currently `position`/`hidden`/`in_safe_zone`/`noise`/`flashlight_on`). Add a `facing` field plus cone/dwell math — mechanically the same shape of change that `flashlight_on` was for Quirith. |

A third, trivial gap: **room-at(x, y) lookup**. Rooms carry bounding data but
there's no point→room query. Never gates anything on its own.

**Sequencing note:** the beam-aim unlock was *deferred* rather than built
with Tier 2, because it turned out to unblock nothing on its own. Kathy —
the only Tier 2 hunter with a cone check — reads her **own** facing, which
now lives on `HunterBrain.facing`, not the player's. Every hunter that needs
the *player's* beam (Aki, Ferryn, Ilyra) is also blocked by a second missing
system (exposure meter, noise meter, player stun respectively), so build it
alongside whichever of those lands first. The shared cone maths is already
in place as `HunterBrain.beam_reaches()`.

### Tier 2 — self-contained hunters *(all ported)*

| # | Hunter | Tier | Gimmick | Size |
| --- | --- | --- | --- | --- |
| 1 | **Eirys** *(ported)* | difficult | Cumulative ratchet: every second spent sprinting outside a safe zone (never decays); at 50s total she permanently locks into a blind chase. Sprint state is inferable from the existing per-frame `noise` value, since sprint noise is a distinct constant. Her `breachesHiding` flag is a pure no-op while hiding doesn't exist. | ~15-20 lines, 1 rule |
| 2 | **Xivvy** *(ported)* | intermediate | Auto-locks to chase on pure proximity (no sight/hearing), then chase speed permanently ramps with chase duration. Caveat: her lock radius scales with player exposure, which doesn't exist — evaluating the same formula at exposure's rest value (0) gives a constant 0.5× radius, a legitimate default rather than a fabricated number. Full fidelity on that one knob wants the exposure meter later. | ~20-25 lines, 2 rules |
| 3 | **Kathy** *(ported)* | difficult | A search-beam cone that spots the player past ordinary sight range. Needs new self-tracked facing bookkeeping (derived from her own movement) that no ported hunter has needed yet. Her second ability (`affectedSummon`) requires other already-active route hunters, which is structurally impossible at `ROUTE_HUNTER_COUNT = 1` in *both* codebases — permanently inert, not a blocker. | ~20-30 lines, 1 rule |
| 4 | **Umbriel** *(ported)* | difficult | Every 30s, disguises as a random other roster hunter. On Standard this is purely cosmetic — attribute-copying is Nightmare-only. Just a timer, an exclusion-aware random pick, and telling `HunterView3D` to load a different model than `brain.hunter_id` implies. **Best deferred until more of the roster exists**, since her disguise pool is whatever's ported. Only self-contained hunter that touches the presentation layer. | ~40-50 lines |
| 5 | **Ravelle** *(ported)* | difficult | Two invisible tripwires at doorway-shaped cells (detected by scanning `generator.grid`), refreshed every 30s unless triggered; crossing one locks chase and *permanently* adds speed. Her "fake doorway" decoy is consumed only by the original's renderer — zero gameplay logic reads it, so it's future art, not a dependency. | ~50-60 lines, 4-5 rules |
| 6 | **Mavrine** *(ported)* | intermediate | Periodically scans for a valid open cell (never on the player, never near start/lift/relays/hiding spots), drops an invisible ~6s tripwire "frame", pursues if crossed. Uses only already-public generator API. Most complex of the self-contained set: a 4-phase state machine plus a real candidate-search algorithm. | ~90-110 lines |

### Tier 3 — blocked on new systems

Grouped by what unblocks them. `(sec.)` = secondary/partial dependency.

| Subsystem | Hunters | Count |
| --- | --- | --- |
| Hiding spots | Ceryth, Jyvra, Loxelle | 3 |
| Audio system (positional / mimicked cues) | Haelith (ported; her footstep tell is the missing half), Thessine (ported; her cues change no state) | 0 blocked |
| Room/player temperature — **BUILT** | Loxelle (still needs hiding spots), Zephyra (sec.) | 1 (+1 sec.) |
| Accumulating noise/corruption meter — **BUILT** | Ferryn (also needs player beam-aim), Glyra (also needs a music-box prop) | 2 |
| Concurrent multi-hunter activation — **BUILT** | Ysolde (sec.) | 1 (sec.) |
| Exposure/sanity meter — **BUILT** | Aki (also needs player beam-aim) | 1 |
| Relay/battery collected-state — **BUILT** | Briselle (also needs a sabotaged-relay state) — Haelith, Opalie and Ysolde are **ported** | 1 |
| ~~Currency/inventory + shop UI~~ — **BUILT**; Zephyra is **ported** | 0 |
| ~~Player radar/gadget item~~ — Porcelle is **ported**; her radar was always the map | 0 |
| ~~Vent-travel network~~ — **BUILT**; Verrine is **ported** | 0 |
| ~~Player stun/incapacitation state~~ — **BUILT**; Ilyra is **ported** | 0 |
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

From `NORMAL_ROUTE_HUNTER_TIERS`. **Implemented** — `pick_for_floor()` draws by
tier weight over whichever tiers have implemented hunters in them, renormalising
so a partial roster does not distort the shares.

- **Relaxed:** easy .70 / intermediate .25 / difficult .05 (original)
- **Standard:** easy .35 / intermediate .50 / difficult .15 (original)
- **Hard:** easy .2625 / intermediate .5125 / difficult .225 (exact midpoint)
- **Nightmare:** easy .175 / intermediate .525 / difficult .30 (original,
  reserved and not selectable)

- **easy** — aki, briselle, dovelle, glyra, haelith, jyvra, loxelle, opalie, quirith, ysolde, zephyra
- **intermediate** — ceryth, ferryn, ilyra, mavrine, porcelle, thessine, verrine, xivvy
- **difficult** — eirys, kathy, ravelle, umbriel, wynelle
- **special** (never in the random draw; summoned by a rule) — solyth (temperature extreme), nyxie (darkness)


## The objective-driven three, and the hook they needed

Haelith, Ysolde and Opalie were the first hunters whose behaviour is about the
**floor** rather than the player, and all three depend on the generator's
`collected` flag actually meaning something — which for a long time nothing
wrote.

They also needed a genuinely new hook. `HunterGimmick.before_perception` runs
ahead of the shared sight/hearing block, which is right for Kathy (her beam
*feeds* perception) and wrong for these three: in the original they live in the
movement block, where they **override** what perception just decided. Ported
onto `before_perception` first, every one of them became an ordinary chaser the
moment she laid eyes on anybody. `after_perception` is that call site, and the
`hunters` check suite is what caught it — by driving a real brain across real
frames on a real facility rather than confirming the gimmick had been called.

What is deliberately absent, so it is not mistaken for finished:

- **Haelith's footsteps.** In the original they are her whole counter — panned
  and attenuated so the cue itself carries direction and distance. Without
  audio she is genuinely harder than she should be, not merely quieter.
- **Ysolde's torch retaliation**, which fires on a player torch ability that
  does not exist. She currently has no answer to being confronted.
- **Opalie's Nightmare pairing** with Briselle, which needs both a difficulty
  selection and Briselle.

Opalie also brought the first interaction **veto**: a guardian denies
everything inside her radius — the lift, a battery, a safe zone, not just her
relay — and testing her pings your position to every active hunter. It is a
simulation rule checked where the interaction resolves, matching the original's
`performInteraction` → `guardianBlocking` path, not a renderer effect.

Ysolde brought the first hunter who **changes the shared world**: her theft
goes out as the same event a player's own pickup does, so a battery stolen on
the host does not stay glowing on a client.


## Beam attention, and what it cost to build

`HunterBrain` now tracks how long the **player's** torch has been held on a
hunter, and exposes the two signals gimmicks read off it: `beam_alerted` (true
every frame the beam stays on target once the dwell completes) and
`flash_triggered` (only the rising edge — one deliberate flash). A gimmick that
fired on the former when it meant the latter would retrigger sixty times a
second, and the `hunters` suite drives both cases rather than asserting about
them.

This was HUNTER_ROSTER.md's second Tier 1 unlock, deferred for a long time
because it unblocked nothing on its own. **Aki** is the first gimmick to read
it: she does nothing until you point a torch at her and hold it, then spikes
your exposure to full three times, five seconds apart.

## Correction: Porcelle was never blocked on a gadget *(resolved)*

This plan recorded Porcelle as needing a "player radar/gadget item". She does
not. The original's dossier is explicit — *"She only shows on the full-screen
radar map, so tracking her means giving up your view of your surroundings"* —
and that radar is the **map overlay**, which this port already has on `M`.

What she actually needs is for the map to draw hunters at all, which it does
not yet. That is a HUD feature, not a gadget, and it is the whole of her
counterplay: porting her invisibility without it would ship a hunter who cannot
be seen or found by any means. She is the cheapest remaining hunter once the
map shows hunters.

## What the ten hunters in this section used to need

All ten are ported now: Ferryn, Briselle, Glyra, Verrine (a vent network: 4
vents at room centres, player `in_vent` travel), Ilyra (a player
stun/incapacitation state), Zephyra (coins: a per-run counter, a scatter of
pickups, and a shop menu resolved through the same indirection
music_box_resolver/vent_resolver already use), and Ceryth/Jyvra/Loxelle
(hiding spots).

Hiding spots are the biggest single unlock at three hunters, and are harder
here than the plan implies: in the original they are derived from *props*
(`locker`, `privacyCurtain`, `supplyCrates`) placed by `populateRooms`, which is
the deferred room-content milestone. Placing spots directly on open cells near
room walls — the same simplification `place_hunter_spawn()` already makes — is
the honest way to unblock the three without porting the whole prop catalogue
first.


## The map became a real map

`MapOverlay` was a coloured rectangle with the caption FACILITY MAP and a
legend for symbols it never drew. `src/ui/facility_map.gd` replaces it: walls,
relays, batteries, the lift, a facing wedge for the player, and **every active
hunter** with her initial on it.

Porcelle is why it had to stop being a placeholder. She is invisible in the room
and drawn only here, so the map is the whole of her counterplay — and the price
the original charges for using it is the balance: reading the map means not
looking at the room she is walking through. Shipping her invisibility against a
placeholder map would have put a hunter on the floor who could not be found by
any means, which is not a hard hunter but a broken one.

The `hunters` suite drives both halves together through the real scene, because
"the gimmick returns true" is exactly the check that passes while the model is
still on screen.
