# Hunter id aliases

Four hunters were renamed to their lore names and their internal ids followed the display names:

| Old id | Current id |
| --- | --- |
| `eirys` | `elise` |
| `jyvra` | `javelle` |
| `quirith` | `quenelle` |
| `zephyra` | `zellia` |

Everything in the repo now uses the current ids: model and texture folders (`assets/hunters_blocky/<id>/`, `art/props-3d/characters/`,
`assets/sprites/hunters/`), the blocky build tools, gimmick class and file names (`EliseGimmick` / `elise_gimmick.gd`, ...), constants
(`ELISE_*`, `JAVELLE_*`, `QUENELLE_*`, `ZELLIA_*`), the stride, emote and personality tables, `death_lines.json`, Night Watch and the backend.

## Old data still loads

Anything that outlives a build can still hold an old id, so the load paths map it with `HunterIdAliases.canonical()`
(`src/config/hunter_id_aliases.gd`) and the backend with `canonicalHunterId()` (`backend/hunter_id_aliases.mjs`):

- `HunterRoster.get_identity`, `HunterBrain._init` and `HunterGimmick.for_id`: any code path, including replicated hunter state from an older client.
- Account progress: `Backend.discovered_hunters()` / `account_discover_hunter()` (the dossier unlocks in `hunter_discoveries`).
- Run snapshots: `StreamedWorldState.adopt()` migrates the stored `hunter_id` of every hunter entry.
- `DeathLines.file_id()` and `HunterDossier.entry()`.
- Room settings: the backend maps an old `persona` before validating it.

The two alias maps are the ONLY places the old ids still appear (this note aside). Suite `hunter_ids` covers the map, every load path and the
absence of old ids from the roster, assets and data; `backend/hunter_id_aliases.test.mjs` covers the Node side.
