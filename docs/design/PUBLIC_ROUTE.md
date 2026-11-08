# Public route and multiplayer testing

## What the PUBLIC route is

An always-open shared route anyone joins from the title screen (**PUBLIC ROUTE**
button): no lobby, no host choice, relay room code `PUBLC` (shown to players as PUBLIC ROUTE). The Node backend owns the
parts that must outlive any one player; gameplay is still the host-authoritative
ENet session, relayed over UDP so nobody forwards a port.

| Piece | Where |
| --- | --- |
| Server state, resume records, claims, persistence, rate limits | `backend/public_route.mjs`, wired in `backend/server.mjs` (`/api/public/join`, `/state`, `/leave`, `GET /status`) |
| Client flow (join, authority vs guest, periodic state post, rejoin) | `game/autoload/public_route.gd` (autoload `PublicRoute`) |
| Daily roster, hunter scaling | `game/config/public_roster.gd` |
| Route scene hooks (restore, resume, patrol, grace, spectate) | `game/infinite_route/infinite_route_test.gd` (`RoomState.public_route`) |
| Title button | `game/menus/main_menu.gd` (`_build_public_button`) |

How it works:

* **Authority.** `PUBLC` is the one persistent ENet code. The first client to register
  it (the backend answers 409 to everyone after) becomes the authority and simulates
  hunters exactly like a private host. Everyone else joins that room as a guest. If the
  authority disappears its listing lapses (15 s without a state post) and the next client
  to join becomes the authority, restoring the route from the backend's copy.
* **Backend-owned state.** World seed, claimed relays/items, the last hunter snapshot
  (opaque, size-limited, only accepted from the holder of the ENet host token), the UTC
  day, per-player resume records (6 h TTL) and a sticky hunter target. State is
  persisted (debounced) to `<data>/lastroute/godot_publicroom.json` and survives a
  backend restart.
* **Shared progress.** Relay claims count for everyone (HUD: `PUBLIC ROUTE // N ONLINE //
  M RELAYS`); batteries/tools/coins respawn 3 minutes after being taken; relays do not.
* **Resume.** Every client posts position and inventory about once a second. A crash,
  reload or handoff returns the runner to the nearest valid cell to the saved spot (never
  the hub unless nothing open is within 12 cells) with their hotbar.
* **Hunters.** The UTC day picks a featured pair (weighted easy 50 / intermediate 40 /
  difficult 10) and the rest of the lineup is a day-mixed weighted draw. The number of
  active hunters is `1 + floor((players - 1) / 2)`, capped at 8, and they are always
  active. Idle hunters patrol around a real runner (the one fewest hunters are on), so
  walking far from the hub does not make you safe.
* **Safe rooms.** Public chunks roll a 22% safe-room chance each (private routes: ~5.5%);
  the roll is seeded per chunk so every client agrees.
* **Grace, spectate, abuse limits.** 10 s capture immunity after joining/rejoining; a
  captured runner spectates for 8 s and returns automatically; the server clamps
  positions, sanitises inventories, limits state posts per session (4/s) and joins per
  address, and rejects snapshots/claims from anyone but the ENet host-token holder.

Not built: per-player tints/nametags beyond the existing callsign tags, a backpack in the
resume record (hotbar only), and TLS (the primary origin is plain HTTP).

## Running it locally (no windows)

```sh
# backend on free high ports, test-only values, throw-away data dir
HOST=127.0.0.1 LASTROUTE_HTTP_PORT=18105 LASTROUTE_RELAY_HOST=127.0.0.1 LASTROUTE_RELAY_PORT=11105 \
  LASTROUTE_DATA_DIR=/tmp/lr-data LASTROUTE_AUTO_UPDATE=false node index.js
# smoke tests against it (loopback-only `--backend` override)
godot --headless --path . res://tests/scenes/backend_smoke.tscn -- --backend=http://127.0.0.1:18105
npm test                      # backend unit tests, including backend/public_route.test.mjs
tools/build/coop_test.sh          # host + guest + late joiner + reconnect through the relay
tools/build/public_test.sh        # PUBLIC route: authority, guest crash + resume, backend restart, handoff
```

Both scripts start their own backend, run every client headless, and kill every process
they started by exact PID. To play it by hand, run the backend as above and start the game
with `-- --backend=http://127.0.0.1:18105`; only loopback origins are accepted by that
override.
