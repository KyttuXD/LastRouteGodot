# Last Route Node backend

One dependency-free Node.js service provides both backend contracts used by
Last Route:

- the original web-style room/account API (`/api/rooms/*`, `/api/account/*`);
- the Godot ENet room-code directory (`/api/enet/rooms/*`).

The room API stores live room/world state in memory. Accounts and their one
JSON progress slot are persisted to disk with scrypt password hashes. ENet
gameplay does **not** pass through this HTTP service: it publishes the host's
observed address and UDP port so another Godot client can connect directly.

## Local run

Node 18 or newer is the only dependency.

```sh
cd backend
npm test
npm start
curl http://127.0.0.1:1101/api/health
```

Normal game builds already use the primary service at
`http://lastroute.kyttuslab.org:1105`. Override it while testing a local or
self-hosted backend with:

```sh
LASTROUTE_BACKEND_URL=http://127.0.0.1:1101 \
  godot4 --path ..
```

The equivalent game argument is
`--backend-url=http://127.0.0.1:1101`. Use `LASTROUTE_BACKEND_URL=off` (or
`--backend-url=off`) to disable directory use. The lobby's custom-host address
and UDP port are a separate direct ENet path and do not change this backend.

## Pterodactyl deployment

Upload this `backend/` directory to a Node.js egg. Its startup file is
`index.js`, so either of these works:

```sh
npm start
# or, for eggs with a configurable startup filename:
node index.js
```

Pterodactyl normally injects `SERVER_PORT`; common proxy setups inject `PORT`.
The server accepts either, with `PORT` taking precedence. Set a persistent
volume for `LASTROUTE_DATA_DIR` so account data survives reinstall/redeploy.
A practical configuration is:

```text
HOST=0.0.0.0
SERVER_PORT=<the panel's TCP allocation>
LASTROUTE_DATA_DIR=./data
TRUST_PROXY=true
LASTROUTE_ADMIN_PASSWORD=<a long random secret>
```

`TRUST_PROXY=true` is required only when a trusted reverse proxy supplies the
real client IP through `X-Forwarded-For`; do not enable it on a service exposed
directly to untrusted clients. Put HTTPS and request rate limits at the proxy
or panel edge.

The backend allocation is TCP. Public ENet play also needs a separate,
reachable **UDP** allocation (8421 by default) on the machine hosting the
Godot game. The directory is discovery, not NAT traversal or a relay.

The official client uses `lastroute.kyttuslab.org:1105`, currently resolving
to `195.62.47.178`. Point that DNS name at the panel's public address and expose
the backend allocation as TCP 1105.

## Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` / `SERVER_PORT` | `1101` | HTTP listen port |
| `HOST` | `0.0.0.0` | HTTP bind address |
| `LASTROUTE_DATA_DIR` | `./data` | persistent data directory |
| `LASTROUTE_ACCOUNT_STORE` | `<data>/accounts.json` | optional exact account-store path |
| `LASTROUTE_ADMIN_PASSWORD` | empty/disabled | enables `/api/dev/login` |
| `LASTROUTE_PUBLIC_DIR` | empty/disabled | optional static web-client directory |
| `TRUST_PROXY` | `false` | trust the first `X-Forwarded-For` address |
| `ENET_ROOM_TTL_SECONDS` | `60` | remove hosts that stop heartbeating |

The `KYTTU_DATA_DIR`, `KYTTU_ACCOUNT_STORE_PATH`, and `KYTTU_DEV_PASSWORD`
names from the original deployment remain accepted as compatibility aliases.

## API groups

- `GET /api/health`
- `POST /api/enet/rooms/register`, `heartbeat`, `unregister`
- `GET /api/enet/rooms/:code`
- `POST /api/rooms/join`, `state`, `settings`, `start`, `default-start`,
  `office-start`, `abandon`, `custom-map`, `dialog-start`, `dialog-advance`,
  `leave`
- `POST /api/account/register`, `login`, `password`, `rename`, `save`, `load`,
  `logout`
- `POST /api/dev/login`, `reload`

Run the real Godot integration smoke test while the service is running:

```sh
LASTROUTE_BACKEND_URL=http://127.0.0.1:1101 \
  godot4 --headless --path .. res://scenes/backend_smoke.tscn
```
