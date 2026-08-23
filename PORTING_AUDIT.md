# Porting audit

This is the concise source comparison for work that is still genuinely absent
from Infinite. It complements `PLAYABILITY.md`; completed systems should be
removed from this list instead of being left as historical “TODO” text.

## Highest-value remaining ports

1. **Custom-map metadata:** load and validate sibling dialogue triggers and
   authored mechanics. Exact prop colors, PNG topology, region flood fill,
   room transfer, guest-admin edit and late-join base-state are complete. PNG
   map loading remains an authenticated admin tool and is not exposed through
   ordinary Infinite discovery.
2. **Reconnect and host promotion:** the backend can elect a replacement relay
   host, but the Godot room client still returns guests to staging when peer 1
   disappears. The replacement must adopt the canonical world snapshot and
   resume host-authoritative hunters/pickups before clients unfreeze.
3. **Story presentation:** the first original branching scene is now converted
   to validated JSON with host-owned state, save persistence and late-join
   adoption. Playback is deliberately admin-only through the `0` menu; the
   schema rejects automatic Infinite triggers. Port the remaining authored
   scenes, portraits, camera rails and path-aware actor choreography.
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
- The former 2D scene was removed; the 3D route is the sole gameplay runtime
  implementation.
- Hide & Seek and XR hardware certification remain separate future milestones,
  not missing Infinite-mode ports.
