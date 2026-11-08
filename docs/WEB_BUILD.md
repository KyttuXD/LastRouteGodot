# Web build (play in the browser)

The game exports to HTML5 and runs in a browser tab. Host the exported `build/web` folder on any static web server
(serve the `.br` copies to browsers that accept them).

## Build

```sh
tools/build/export_web.sh              # -> build/web  (git-ignored): export, drop editor files, brotli-compress
LASTROUTE_ALLOW_DIRTY_BUILD=true tools/build/export_web.sh   # same, with uncommitted changes
# then upload build/web/ to your static host
```

It uses the "Web Debug Tools" preset: single-threaded (no COOP/COEP headers needed), about 94 MB unpacked and 40 MB
with brotli (`index.wasm` 6.7 MB, `index.pck` 33.6 MB). The preset's `html/head_include` script sets
`window.LR_API_BASE`, the server the game talks to:

| Page | API base |
| --- | --- |
| `https://lastroutegodot.games.kyttuslab.org` | the page origin itself (the public game server) |
| local test | `?api=http://127.0.0.1:PORT[/path]` (loopback only) |
| anything else | none: the game falls back to the built-in default, which a browser blocks as mixed content |

`BackendClient._web_api_base()` accepts only those origins, so a page cannot point the game at another server.

## What differs on the web

* **Transport.** Browsers have no UDP and cannot listen, so rooms use `WsRoomPeer` (`game/network/ws_room_peer.gd`), a
  `MultiplayerPeerExtension` over one WebSocket per player to the backend's relay (`backend/ws_relay.mjs`, `/api/ws`).
  Host and guests all connect outbound; the relay forwards packets and never runs game logic. Native builds use the same
  transport for the public route (always) and for private rooms started with `-- --ws-rooms`, so web and native players
  can share a room. A room hosted over ENet is native-only; a browser that tries its code gets a clear message.
* **No update check.** `UpdateManager.check()` returns at once on web and `Build.requires_update_gate()` is false.
* **Menus.** JOIN ROOM and PLAY OFFLINE work; CREATE ROOM makes a solo room (see below); QUIT returns to the game hub.
* **No co-op hosting.** A browser stops a hidden tab's game loop, so a room hosted from a tab froze for all of
  its guests whenever the host switched tabs. `RoomState.web_host_refusal()` refuses private CREATE ROOM and reserved
  rooms on web (`WEB_HOST_REFUSED`; CREATE ROOM stays a playable solo room and its dialog says co-op is hosted from the
  desktop app). The public route may still be held from a browser: it hands the route on when its holder goes quiet.
* **Timeouts.** The health probe waits 25 s on web (the page can stall for seconds while scenes load).

## Protocol (relay)

Text control frames (JSON) and binary data frames `[int32 LE peer][uint8 mode][uint8 channel][payload]`; see the header of
`backend/ws_relay.mjs`. A room is registered over HTTP with `"transport": "ws"` (`/api/enet/rooms/register`, no port),
the host then connects to `/api/ws` with `{"t":"hello","code":...,"role":"host","token":...}`, guests with
`"role":"guest"`. The relay assigns peer ids (host is 1), tells the host about joins and leaves (`{"t":"peer",...}`) and
disconnects every guest when the host leaves. The host can remove a guest with `{"t":"kick","id":N}`. A room whose host
holds its relay socket stays listed even if the page stopped sending heartbeats.

## Tests

```sh
(cd backend && node --test)                     # includes ws_relay.test.mjs
COOP_WS=1 tools/build/coop_test.sh                  # host + guest + late joiner over the WebSocket relay
tools/build/public_test.sh                          # the public route (always WebSocket), incl. a backend restart
```

Browser checks (manual): serve `build/web` from a local backend (`LASTROUTE_PUBLIC_DIR=build/web`) and open
`http://127.0.0.1:PORT/index.html?api=http://127.0.0.1:PORT`. To join from a browser while a native client hosts, start
`coop_test.tscn -- host --ws-rooms --backend=...` and type its room code (a hidden tab stops the game loop, so keep the
hosting tab visible).

## Hidden tabs

A hidden tab pauses the game. Since the web build cannot host a co-op room (above), that only freezes the player's own
game, or the public route while a browser holds it. Every host sends guests a small beat each second
(`RoomState._receive_host_beat`); a guest that hears nothing for `HOST_STALL_SECONDS` (4 s of its OWN running time, so its
own hidden tab does not count) shows `HOST_STALL_NOTICE` on the staging screen and as a HUD toast, then `HOST IS BACK`.
A web host also listens for the page's `visibilitychange` and tells guests at once (`HOST_HIDDEN_NOTICE`), best effort.
Check in a browser: hold the public route in one tab, join it from a desktop client, hide the tab: the desktop shows the
warning within about 4 s and HOST IS BACK when the tab returns. CREATE ROOM in the browser: the staging screen reads
SOLO ROOM // THE BROWSER VERSION CANNOT HOST CO-OP. Suite: `web_host`.

## Known limits

* A hidden browser tab pauses the game (see Hidden tabs); a browser holding the public route still pauses it for guests,
  who are warned. Keeping the simulation ticking in a Worker was not done.
* The viewport must be resized once after load in some embedded browsers (the page dispatches a `resize` itself).
* Admin tools, accounts and the public route behave as on native; unsigned test builds are not involved.
