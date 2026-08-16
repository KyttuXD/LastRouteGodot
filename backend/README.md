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
# From the repository/server root:
npm test
npm start
curl http://127.0.0.1:1101/api/health
```

Normal game builds use only the primary service at
`http://lastroute.kyttuslab.org:1105`. This endpoint is hardcoded for editor,
debug, and release builds and is shared by accounts, room discovery, and
updates. The game exposes no environment variable, command-line override,
custom directory, or direct-address lobby option.

## Pterodactyl deployment

Upload the repository contents to the Node.js egg. The Pterodactyl-friendly
startup file deliberately lives at the server root, while its implementation
stays in `backend/`. Either of these works from that root:

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
LASTROUTE_PUBLIC_DIR=./web
LASTROUTE_UPDATE_MANIFEST=./updates.json
LASTROUTE_UPDATE_DIR=./updates
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
| `LASTROUTE_UPDATE_MANIFEST` | empty/disabled | update metadata JSON loaded when the server starts |
| `LASTROUTE_UPDATE_DIR` | empty/disabled | directory containing published update archives |
| `TRUST_PROXY` | `false` | trust the first `X-Forwarded-For` address |
| `ENET_ROOM_TTL_SECONDS` | `60` | remove hosts that stop heartbeating |

The `KYTTU_DATA_DIR`, `KYTTU_ACCOUNT_STORE_PATH`, and `KYTTU_DEV_PASSWORD`
names from the original deployment remain accepted as compatibility aliases.

## API groups

- `GET /api/health`
- `GET /api/updates/:channel/:platform`
- `GET`, `HEAD /api/updates/files/:published-file`
- `POST /api/enet/rooms/register`, `heartbeat`, `unregister`
- `GET /api/enet/rooms/:code`
- `POST /api/rooms/join`, `state`, `settings`, `start`, `default-start`,
  `office-start`, `abandon`, `custom-map`, `dialog-start`, `dialog-advance`,
  `leave`
- `POST /api/account/register`, `login`, `password`, `rename`, `save`, `load`,
  `logout`
- `POST /api/dev/login`, `reload`

## Pterodactyl-hosted updates

This supports the intended private-GitHub-to-Pterodactyl flow without putting
a GitHub token in the game:

1. Your existing panel startup/deploy step uses its server-side PAT to pull the
   GitHub Release archives into `LASTROUTE_UPDATE_DIR`, and the matching
   manifest asset to `LASTROUTE_UPDATE_MANIFEST`. If the same Node process
   should host the HTML build, extract its Web ZIP into
   `LASTROUTE_PUBLIC_DIR`; the existing static-file route serves it at `/`.
2. `./scripts/export_test_builds.sh` writes the test archives and a ready-made
   `builds/updates.debug.json` with their SHA-256 values. Point
   `LASTROUTE_UPDATE_MANIFEST` at that file, or copy
   `backend/updates.example.json` and set each channel/platform's dotted numeric
   version, exact local `file`, SHA-256 checksum, notes and optional `required`
   flag. The platform keys are `linux`, `windows`, `macos`, `web`, `steamvr`
   and `quest`.
3. Restart the Node process after changing the manifest. The backend validates
   every entry and only serves local filenames referenced by a valid manifest.
4. Debug exports query the `debug` channel and release exports query `release`.
   The menu reveals an update button when that platform has a newer version.

The generated files are ignored by Git and should be uploaded as GitHub
Release assets, not committed to the source tree. For example, after reviewing
the generated manifest and archives:

```sh
gh release create debug --prerelease \
  --title "Last Route debug 0.0.1.0" \
  builds/LastRoute-*-Debug.zip builds/updates.debug.json
```

Keep the GitHub tags channel-based: use `debug` for debug uploads and
`release` for release uploads. The dotted game version belongs in the build,
manifest, and release title rather than the tag name.

The PAT belongs only in Pterodactyl's private variables or deployment script;
never write it into `updates.json`, the Godot project, an export, or Git. Use
HTTPS in front of the public backend before distributing release builds. The
current client opens the published archive/APK rather than attempting to
overwrite its own running executable. Steam, Meta Quest store builds and the
hosted Web build should eventually use their platform-native deployment
systems; a future signed desktop launcher can consume the same manifest and
verify the included SHA-256 before installation.

Run the real Godot integration smoke test against the deployed primary service:

```sh
godot4 --headless --path .. res://scenes/backend_smoke.tscn
```
