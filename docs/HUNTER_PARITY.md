# Hunter parity: 2D browser game vs the Godot 3D port

Source of truth for mechanics is the 2D game (`LastRoute/games/last-route/src/game/hunters/**`, `hunter-ai.js`,
`config/game-config.js`). This is the audit as it stood and what was done. Status: **Done** (same behaviour and
numbers), **Fixed** (gap closed in this pass), **Partial** (core present, named pieces still missing), **Different**
(deliberately or historically a different design, kept and noted). The validator is `hunter_parity`
(`scripts/validate_hunter_parity.gd`), plus the per-hunter checks in `hunters`.

## A-Z

| Hunter | 2D mechanic | Status | Notes |
| --- | --- | --- | --- |
| Aki | phantom exposure: a held flash starts a fuse, 3 bursts 5 s apart | Done, Fixed | burst toast and alert sound added |
| Briselle | relay tracker: any relay collected locks her on for 12 s at x1.25, a flash breaks it and stuns 3 s | Fixed | replaced the obsolete relay-saboteur; the relay-offline world event remains for other uses |
| Ceryth | non-lethal hiding trap; right answer sends her sprinting (6.4) to a new spot at least 7 away | Fixed | non-lethal; retreats and re-perches with new eyes; leaves the floor only when no spot exists |
| Dovelle | no ability | Done | |
| Elise | running data ratchet; breaches hiding (grabs a hidden player) | Fixed | `breaches_hiding()` hook; the grab needs her last known point within 0.9 |
| Ferryn | round stalker, flash scream | Partial | ember veil (near-invisible unless lit) not ported |
| Glyra | music box threat, never attacks | Done, Fixed | cannot capture; wind-down alert sound added |
| Haelith | relay pursuer | Fixed | skips the relay Opalie guards while more than one is out |
| Ilyra | corner observer, pounce after 15 s (0 on Nightmare), sight x1.8, same room counts as sight | Fixed | delay 0.75 -> 15; sight scale hook; non-lethal |
| Javelle | hiding timeout ejects | Done | |
| Kathy | beam detection; affected-summon (others affect the player, then 10 % roll every 5 s) | Partial | beam done; the affected-summon needs the multi-hunter coordination layer (below) |
| Loxelle | passive incinerator, breaks hiding, non-lethal | Fixed (part) | non-lethal; breaking cover now adds +30 temperature and 11 noise; the repeating chance loop and chase-time break remain |
| Mavrine | lattice mark | Fixed (part) | marks keep 1.25 from hiding spots and within 30 of her; the survey sight scale and the ally signal remain |
| Nyxie | darkness stalker special | Different | dispel range/angle (7 / 0.33 vs 36 / 0.56) and the dead-lamp walk-on are deliberate Godot tuning |
| Opalie | relay guardian | Fixed | guards the first uncollected relay, never grabs while stationed |
| Porcelle | radar-only ghost | Partial | the in-world body stays opaque by design; map marker done |
| Quenelle | flashlight tracker | Fixed | counts only with the torch on, charged and the runner not hidden; lock-on toast and sound |
| Ravelle | tripwire trapper | Fixed (part) | wires are full-hall segments; the pack signal to allies remains |
| Solyth | relay-slot hunter in 2D, heat lock | Different | Godot keeps her as a heat-woken special; the hiding-spot burn, 0.85 player slow and thermal cycle remain |
| Thessine | sound mimic | Done | |
| Umbriel | shapeshifter as a player | Different | Godot disguises her as other hunters; the player-skin disguise with 4.2 / 9 ranges remains |
| Verrine | vent lurker | Fixed | cannot grab unless the player is in the vent network |
| Wynelle | cold materializer | Fixed (part) | safe zones now warm her away and stop the build; the cold slow (walk 0.5 / run 0.7) and proximity chill remain; the freeze now draws the `cold` death line |
| Xivvy | chase accelerator | Fixed | close lock radius scales with exposure (.5 + exposure/200) |
| Ysolde | battery thief | Fixed | never grabs the player; the torch retaliation remains (no torch item) |
| Zellia | merchant | Fixed (part) | fatal deal roll per trade (2 / 5 / 7.5 / 12 % by difficulty) ends the run with the `deal` death line; the repair peer-claim remains |

## Void

| Void | 2D power | Status |
| --- | --- | --- |
| Black | frozen while looked at (11 cells, 0.85 rad), x1.5 otherwise | Fixed |
| Blue | invisible; the beam shoves her 6 back and reveals her 3.5 s | Fixed (map exclusion while hidden still to do) |
| Brown | jams 2 hiding spots within 9 every 18 s for 20 s | Fixed |
| Cyan | 2.5 s of sight broadcasts the position to all hunters, 30 s cooldown | Fixed |
| Gray | anti-idle: a key-mash route when the player idles | Different (the Godot pressure spawner stays; the key-mash route is still to do) |
| Green | submerges and resurfaces 9 cells from the player every 22 s | Fixed |
| Orange | system outages (flashlight / climate / radar offline for 9 s) | Missing (needs player-side forced-off hooks) |
| Pink | never attacks; fake radar contacts | Fixed (part): never grabs, footstep cue; the fake radar contacts remain |
| Purple | radar static / blackout | Missing (needs a radar state the map reads) |
| Red | x1.55 in halls, x0.78 in rooms | Fixed |
| White | frozen by a lit beam (10 cells, 0.42 rad), x1.35 in the dark | Fixed |
| Yellow | speed grows while the map is open, up to x1.7 | Fixed |

## Shared AI

| Behaviour | Status |
| --- | --- |
| Non-lethal / specialist capture gate | Fixed (`immune_to_capture`) |
| Sight scale and breach-hiding hooks | Fixed (`sight_scale`, `breaches_hiding`) |
| Gimmick events in the streamed route (toasts, stuns, alarms, jammed spots) | Fixed: the streamed route used to drop them |
| Hunter coordination (shared sightings, flank offsets, roles) | Missing: needs its own design pass |
| Beam attention geometry (range 12 / 0.28 vs 2D 9 / 0.56) | Different: tuned for the 3D camera |
| Roster stats (speed, sight, hearing) | Different: the Godot values are a deliberate rebalance for its perception model; transcribe from the 2D config only if KT wants it |
| Void captures are an instant game over | Different: 2D gives each Void a struggle with its own grip profile |

## Still to do

Orange and Purple (player systems), Gray's key route, Pink's radar ghosts, Kathy's summon, Ferryn's veil, Umbriel's
player disguise, Solyth's burns, the coordination layer, Void grips. They need hooks outside the brain and are listed here
rather than half-built.
