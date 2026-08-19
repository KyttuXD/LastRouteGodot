# Porting audit

This is the concise source comparison for work that is still genuinely absent
from Infinite. It complements `PLAYABILITY.md`; completed systems should be
removed from this list instead of being left as historical “TODO” text.

## Highest-value remaining ports

1. **Custom-map metadata:** load and validate the original sibling data for
   explicit prop cells, dialogue triggers and authored mechanics. The PNG map,
   region flood fill, room transfer, guest-admin edit and late-join base-state
   path are already complete.
2. **Reconnect and host promotion:** the backend can elect a replacement relay
   host, but the Godot room client still returns guests to staging when peer 1
   disappears. The replacement must adopt the canonical world snapshot and
   resume host-authoritative hunters/pickups before clients unfreeze.
3. **Story presentation:** import the original YAML dialogue/cutscene data into
   a validated Godot-facing format, then add host-owned trigger state so a late
   joiner cannot replay or skip another runner's event.
4. **Office presentation:** replace remaining Office placeholder environment
   art and decide whether a full shift remains a separate mode. Infinite can
   already choose Office Void identities as deterministic rare spawns.
5. **Network release work:** perform the real two-machine Internet soak test,
   add TLS termination, and choose a WebRTC/WebSocket transport if browser
   multiplayer must ship.

## Performance state

- Hunter perception, line-of-sight, replanning and replication run on bounded
  intervals rather than every rendered frame.
- Infinite pathfinding uses one cached native `AStarGrid2D` per active
  authority window and rebuilds only when chunks or navigation mutations
  change.
- Only the host simulates hunter decisions; guests interpolate authoritative
  reports.
- Mirrors render only the nearest mirror within range through one low-resolution
  viewport and update at a bounded rate.
- Next optimization should be evidence-led. Spatial buckets for very dense prop
  or interaction queries remain a candidate, not an assumed requirement.

## Intentionally retained references

- The finite route remains as an internal regression/save fallback but is not
  exposed by normal staging.
- The legacy 2D scene remains source reference and is not a second gameplay
  implementation.
- Hide & Seek and XR hardware certification remain separate future milestones,
  not missing Infinite-mode ports.
