# Web build (play in the browser)

The game exports to HTML5 and runs in a browser tab. The site (LastRoute repo, `docs/DOWNLOADS.md`) hosts it at
`https://kyttuslab.org/downloads/web/`; the downloads page shows "Play in browser" once the export is uploaded.

## Build

```sh
scripts/export_web.sh              # -> build/web  (git-ignored): export, drop editor files, brotli-compress
LASTROUTE_ALLOW_DIRTY_BUILD=true scripts/export_web.sh   # same, with uncommitted changes
rsync -a --delete build/web/ vps3:/root/web/data/downloads/web/    # publish (the site serves .br copies to browsers that accept them)
```

It uses the "Web Debug Tools" preset: single-threaded (no COOP/COEP headers needed), about 94 MB unpacked and 40 MB
with brotli (`index.wasm` 6.7 MB, `index.pck` 33.6 MB). The preset's `html/head_include` script sets
`window.LR_API_BASE`, the server the game talks to:

| Page | API base |
| --- | --- |
| `https://kyttuslab.org/...` | `https://kyttuslab.org/godot2-api` (`?server=test` -> `/godot2-test-api`) |
| local test | `?api=http://127.0.0.1:PORT[/path]` (loopback only) |
| anything else | none: the game falls back to the built-in default, which a browser blocks as mixed content |

`BackendClient._web_api_base()` accepts only those origins, so a page cannot point the game at another server.

## What differs on the web

* **Transport.** Browsers have no UDP and cannot listen, so rooms use `WsRoomPeer` (`src/network/ws_room_peer.gd`), a
  `MultiplayerPeerExtension` over one WebSocket per player to the backend's relay (`backend/ws_relay.mjs`, `/api/ws`).
  Host and guests all connect outbound; the relay forwards packets and never runs game logic. Native builds use the same
  transport for the public route (always) and for private rooms started with `-- --ws-rooms`, so web and native players
  can share a room. A room hosted over ENet is native-only; a browser that tries its code gets a clear message.
* **No update check.** `UpdateManager.check()` returns at once on web and `Build.requires_update_gate()` is false.
* **Menus.** CREATE ROOM, JOIN ROOM and PLAY OFFLINE all work; QUIT returns to Kyttu's Lab.
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
COOP_WS=1 scripts/coop_test.sh                  # host + guest + late joiner over the WebSocket relay
scripts/public_test.sh                          # the public route (always WebSocket), incl. a backend restart
```

Browser checks (manual): serve `build/web` from a local backend (`LASTROUTE_PUBLIC_DIR=build/web`) and open
`http://127.0.0.1:PORT/index.html?api=http://127.0.0.1:PORT`. To join from a browser while a native client hosts, start
`coop_test.tscn -- host --ws-rooms --backend=...` and type its room code (a hidden tab stops the game loop, so keep the
hosting tab visible).

## Known limits

* A hidden browser tab pauses the game; as host it freezes the room for its guests.
* The viewport must be resized once after load in some embedded browsers (the page dispatches a `resize` itself).
* Admin tools, accounts and the public route behave as on native; unsigned test builds are not involved.
