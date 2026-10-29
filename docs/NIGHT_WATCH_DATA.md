# Night Watch as data

Night Watch is locked for players (`GameRegistry`, "NIGHT WATCH // COMING BACK SOON") until it is fully data-driven and moddable. The
plan (phases, unlock criteria) is owned by the Night Watch lane; this page is the format.

## Rules

- Same pack rules as Last Route content ([DATA_DRIVEN_CONTENT.md](DATA_DRIVEN_CONTENT.md)): data plus assets only (`.json .glb .png .ogg`),
  ids `<pack>_` prefixed, overrides listed in `pack.json`, a bad file rejects the whole pack.
- Behaviour stays code. A mode names one of nine rulesets (`classic mask lure bedroom story dayshift mixed openair descent`) and tunes its
  numbers; there are no expressions or scripts.
- Night Watch-only hunters use the hunter pack format (`lr.hunter/1`) and join a mode through its cast.
- Packs may change a mode's colours and texts; menu layout and art stay the game's.

## Kinds (`src/night_watch/data/nw_schemas.gd`)

| kind | schema | holds |
|---|---|---|
| `nw_modes` | `nw.mode/1` | title, blurb, ruleset, office, building, cast, level count, presets, Custom Night sliders, ratings, colours, texts |
| `nw_rules` | `nw.rules/1` | the ruleset's parameters (numbers, booleans, tables of them) |
| `nw_casts` | `nw.cast/1` | hunters with their per-night levels and a pose per state (`idle walk peek door vent window scare`) |
| `nw_offices` | `nw.office/1` | room size (height at least 3.2 m), spawn, entrances, stations, up to 400 pieces, lamps, palette, room tone |
| `nw_buildings` | `nw.building/1` | rooms, graph, cams, hunter paths |
| `nw_calls` | `nw.calls/1` | per level: the call's lines |
| `nw_sounds` | `nw.sounds/1` | cue -> synth recipe or a pack `.ogg` |
| `nw_scares` | `nw.scare/1` | per hunter: pose, framing, duration (200–6000 ms), sound |

Unknown keys are errors. `data_night_watch` checks the schemas and prints the Night Watch parity fingerprint
(`Parity.nw_hash()`: every table the modes read and every office spec), which must be equal before and after each migration commit.
