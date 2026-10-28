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

Host-caused long moves never strike: a vent transit (`vent_used`), being pulled out of hiding (`hide_found`), an axe
rescue and a revive call `GuestGuard.allow_jump` for 3 s.

## Consequences (manual only, `backend/moderation.mjs`)

KT: "accounts shouldnt be auto banned, only manually". Automatic consequences stay inside the room: snap-back,
strikes, the host kick after 5 strikes, and in-room troll mode from strikes.

Signals go to a review queue, never a restriction: host kick reports (`/api/moderation/report`, host-token checked),
and the client's build report at sign-in and room join (`/api/moderation/integrity`: commit + SHA-256 of the
PCK/executable against the published manifests and an owner allow-list). The build hash is a signal, not proof: a
modified client can spoof it. Each opens a review entry (account, reason, kick reports, build hash, timestamps); kicks
from 2+ different hosts in 7 days are marked `kicks` as the stronger signal.

- Owners (KYTTU/AYTTU) read the queue in the hub admin MODERATION list (`/api/admin/flags`, `reviews` = accounts with
  open entries) and act with `/api/admin/flags/set`: `extend` (flag for N hours), `clear`, `ban`, `unban`,
  `troll_on` / `troll_off`, or `dismiss`. Any action closes the open reviews.
- Only an owner flag or ban restricts an account: no public route, no hosting public rooms, no skin uploads (403
  `FLAGGED` with a clear message and the end time). Solo, offline and private rooms still work; the host sees
  "NOTICE // <name> IS FLAGGED" in chat.
- No automatic device/IP cooldowns. Only salted hashes of device ids and IPs are stored.
- The player sees an owner restriction via `ModerationClient` (`Backend.moderation`), shown as an account message.

## Troll mode

On for a guest the host caught this room (any strike), or that an owner flagged or trolled on the server (`/api/moderation/peers`, polled every 30 s). Host side (authoritative):
`RemotePlayers.best_target` gives every hunter only the trolled guest on that floor, with hiding and safe rooms ignored,
and leaves teammates alone; hunters chase it 15 % faster; its pickups are refused (they vanish on its screen only).
Its own client (told by a `troll` player event): 1.6× sprint drain, flashlight flicker and fake hunter footsteps, and a
2.5× longer caught scare.

## Lag never counts as cheating

- Credit is earned for the real time between arrivals, capped by the longest gap in the last 10 s, so a 3–10 s freeze
  and its catch-up burst add up to the legit distance. A move beyond the budget and 12 m is a teleport.
- Budgets widen a little with round trip (ENet RTT) and measured arrival jitter.
- Samples carry `seq`: duplicates and out-of-order samples are dropped unjudged; packet loss or a gap > 0.3 s skips
  the wall sweep.
- Heavy lag (RTT > 400 ms, a gap > 1.5 s, or jitter > 250 ms, held 5 s): movement and stamina violations still snap
  back but are tagged `lag`: no strike, no kick, no troll mode, nothing reported to the server. The guest sees
  "CONNECTION UNSTABLE" (a real correction shows "POSITION CORRECTED").
- `anti_cheat` simulates 300 / 800 / 2000 ms RTT, jitter, 10 % loss, 3 s and 10 s freezes, reordering and duplicates:
  zero strikes for legit runs, while speed and teleport cheats are still snapped back under every link (struck below
  the heavy-lag line).
