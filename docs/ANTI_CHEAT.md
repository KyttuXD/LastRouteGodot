# Anti-cheat (co-op host checks)

The host owns hunters and floor state; each guest owns its own transform and meters. `GuestGuard`
(`src/game/guest_guard.gd`) checks every guest sample on the host in `RemotePlayers._place` before targeting,
pickups, relays or checkpoints use it.

| Check | Rule |
|---|---|
| Speed | Leaky budget at the fastest legit sprint × 1.35, capped at one 1 s lag gap of credit + 1 m |
| Fly | Same budget for upward motion at 4.5 m/s (ladders 2.15, jumps 3). Falls and plunges are never capped |
| Teleport | > 12 m on one floor needs a floor change, a host-known spot (spawn / current checkpoint) or admin rights |
| No-clip | Capsule cast + ray along the path through static world geometry; doors (`RouteInteractable3D`), vents and hiding are ignored |
| Position | Grid `position` must match `at` within 1.5 m |
| Stamina | An unbroken sprint longer than a full tank + 1.5 s |
| Lamp | Charge outside 0..100, or rising without a battery being used up |
| Interactions | At most 8 interaction requests per guest per second (`RemotePlayers._interaction_allowed`) |

A violation rewrites the sample to the last good spot, sends the guest an `anticheat_snap` event that moves it back,
and adds a strike. Strikes decay one per 30 s clean; 5 strikes kick the guest (`RemotePlayers.kick_guest`) with a
system notice to the room. Authorised admin peers (`remote_admin_peer_allowed`) and spectators are exempt.

Cost: a few comparisons per 20 Hz sample plus one shape cast when the guest moved.

Validator: `anti_cheat` (synthetic cheaters corrected / kicked; sprint with lag, ladders, plunges, stairs, respawns,
admins and battery use pass).
