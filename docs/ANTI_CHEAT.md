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

## Consequences (server-enforced, `backend/moderation.mjs`)

Inputs: host kick reports (`/api/moderation/report`, host-token checked), the client's build report at sign-in and
room join (`/api/moderation/integrity`: commit + SHA-256 of the PCK/executable against the published manifests and an
owner allow-list), and server-side refusals. The build hash is a signal, not proof: a modified client can spoof it.

- Strikes in a room: snap back, then kick (above).
- Kicks reported by 2+ distinct hosts within 7 days, or an unknown build hash: the account is flagged for 24 h, 7 days
  on any later flag. Never automatically permanent; owner accounts are never auto-flagged.
- While flagged: no public route, no hosting public rooms, no skin uploads (403 `FLAGGED` with a clear message and the
  end time). Solo, offline and private rooms still work; the host sees "NOTICE // <name> IS FLAGGED" in chat.
- Every kick puts the guest's device hash (and its last IP hash) on a public-join cooldown: 1 h, doubling, max 24 h.
  Only salted hashes are stored.
- Owners (KYTTU/AYTTU) review in the admin panel: `/api/admin/flags`, `/api/admin/flags/set` (clear / extend / ban /
  unban / troll_on / troll_off), `/api/admin/builds/add|remove`. Full API: `backend/README.md`.
- The player sees the restriction via `ModerationClient` (`Backend.moderation`), shown as an account message.

## Troll mode

On for a guest the host caught this room (any strike), or that the server reports as flagged, owner-trolled, or a
device kicked in the last 24 h (`/api/moderation/peers`, polled every 30 s). Host side (authoritative):
`RemotePlayers.best_target` gives every hunter only the trolled guest on that floor, with hiding and safe rooms ignored,
and leaves teammates alone; hunters chase it 15 % faster; its pickups are refused (they vanish on its screen only).
Its own client (told by a `troll` player event): 1.6× sprint drain, flashlight flicker and fake hunter footsteps, and a
2.5× longer caught scare.
