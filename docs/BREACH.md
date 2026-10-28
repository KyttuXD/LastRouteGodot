# Breakables (stream_breach)

One API for everything a tool can break in the streamed route: sealed-wing seals (`SealPlanner`), loose boards and pipes
(SEWER's floods). Code: `src/game/breach.gd`, state in `StreamedWorldState.breaches`, view piece `BreakableView`.

## Flow

1. A chunk lists its breakables in `data["breakables"]` as specs (`Breach.make_spec(id, kind, variant, chunk, cell, hp,
   tools, extras, locked)`, ids from `Breach.make_id(chunk, index)`). The index is the spec's position in that list, so the id
   is stable per seed and `StreamedRouteGenerator.breakable_by_id(id)` finds it again on any machine.
2. The view makes one interactable per spec, drawn by its `variant`, showing the damage state from `world_state.breaches`.
3. A tool swing costs `PlayerController3D.TOOL_SWING_COST[tool]` durability (the axe four chops, the crowbar one pry) and
   takes `Breach.TOOL_DAMAGE[tool]` hit points off. The host applies it; a guest sends `{"what": "stream_breach_request",
   "id", "tool"}` and the host publishes `{"what": "stream_breach", id, kind, variant, level, chunk, cell, position, hp, max,
   opened, tool, by}` to everyone (idempotent: it carries the new hp, not a delta).
4. Every machine updates the piece and calls the hooks.

## Hooks

```gdscript
Breach.connect_hook("breached", Breach.KIND_PIPE, _on_pipe_burst)   # callback(event), on every machine
Breach.connect_hook("hit", "", _on_any_hit)                         # kind "" = every kind
Breach.clear_hooks()                                                 # on teardown
```

`"breached"` fires once when hp reaches 0 (the thing opens). A pipe's flood, a seal opening a wing and the hunters' noise
all hang off it.

## Seals

`SealPlanner` places seals per chunk from `SealRules` (open share and seals per ring, chained wings, relays and tools).
Seals never stand on a level link (ramps, stairs, falls) and every relay and tool the rules guarantee is reachable.

## Authored pieces

A spec with variant `"authored"` (or `"none"`) draws nothing and has no collider: only an invisible aim target stands at its
cells, so the owner (SEWER's pipes) draws and removes its own mesh and collider from the "hit" / "breached" hooks.
