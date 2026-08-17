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
LASTROUTE_AUTO_UPDATE=true
LASTROUTE_GITHUB_REPO=KyttuXD/LastRouteGodot
LASTROUTE_GITHUB_TAG=debug
LASTROUTE_GITHUB_TOKEN=<private GitHub PAT>
LASTROUTE_UPDATE_POLL_SECONDS=15
# Source watching is automatic while the PAT above is configured.
LASTROUTE_GITHUB_BRANCH=main
LASTROUTE_SOURCE_POLL_SECONDS=30
LASTROUTE_UPDATE_MANIFEST=./updates/updates.debug.json
LASTROUTE_UPDATE_DIR=./updates
TRUST_PROXY=true
LASTROUTE_ADMIN_PASSWORD=<a long random secret>
```

`TRUST_PROXY=true` is required only when a trusted reverse proxy supplies the
real client IP through `X-Forwarded-For`; do not enable it on a service exposed
directly to untrusted clients. Put HTTPS and request rate limits at the proxy
or panel edge.

The backend allocation is TCP. Public ENet play also needs reachable **UDP
8421 on the player's hosting machine**. Native clients now ask a compatible
home router to forward that port through UPnP and remove the mapping when the
room closes. When host and guest share one public address, the directory gives
the guest the host's validated private LAN address to avoid relying on router
hairpinning. If UPnP is unavailable, the host must forward UDP 8421 manually;
the lobby reports that condition. The directory remains discovery rather than
a gameplay relay, so carrier-grade NAT still needs a future relay/dedicated
transport.

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
| `LASTROUTE_CUSTOM_MAP_DIR` | `./art/custom-maps` when present | safe PNG-only custom-map directory exposed below `/api/custom-maps/` |
| `LASTROUTE_UPDATE_MANIFEST` | empty/disabled | update metadata JSON reloaded for update requests |
| `LASTROUTE_UPDATE_DIR` | empty/disabled | directory containing published update archives |
| `LASTROUTE_AUTO_UPDATE` | auto when a token exists | mirror the stable GitHub Release tag into the local update directory |
| `LASTROUTE_GITHUB_REPO` | `KyttuXD/LastRouteGodot` | GitHub owner/repository used for release and source checks |
| `LASTROUTE_GITHUB_TAG` | `debug` | stable `debug` or `release` asset channel to mirror |
| `LASTROUTE_GITHUB_TOKEN` | `GITHUB_TOKEN`, `GH_TOKEN`, or `ACCESS_TOKEN` | private server-side PAT; the named variable takes priority |
| `LASTROUTE_UPDATE_POLL_SECONDS` | `15` (minimum `10`) | poll interval for hot release-asset synchronization |
| `LASTROUTE_RESTART_ON_GITHUB_UPDATE` | auto when a token exists | request a Pterodactyl restart when the watched source branch advances; set `false` to disable |
| `LASTROUTE_GITHUB_BRANCH` | `main` | branch watched for backend source changes |
| `LASTROUTE_SOURCE_POLL_SECONDS` | `30` (minimum `15`) | source-commit check interval |
| `LASTROUTE_DEPLOYED_REVISION` | local `git rev-parse HEAD` | exact deployed SHA when the server directory has no `.git` folder |
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

`GET /api/health` reports the exact Git commit currently published for each
update channel under `updates.<channel>.revision`, together with its version
and platform list. The same short commit is printed in the Pterodactyl console
after every successful GitHub Release sync.

## Pterodactyl-hosted updates

This supports the intended private-GitHub-to-Pterodactyl flow without putting
a GitHub token in the game:

1. Set `LASTROUTE_AUTO_UPDATE=true` and provide the server-side PAT as
   `LASTROUTE_GITHUB_TOKEN`; the common Pterodactyl `ACCESS_TOKEN` variable is
   also accepted. At startup and every `LASTROUTE_UPDATE_POLL_SECONDS`, Node
   reads the stable `debug` GitHub Release, downloads changed artifacts,
   verifies their manifest SHA-256 values, and atomically publishes the
   manifest last. Existing files remain usable if GitHub is unavailable.
2. `./scripts/export_test_builds.sh` stamps the current Git commit into every
   export and writes the test archives plus a ready-made
   `builds/updates.debug.json` with their SHA-256 values. Point
   `LASTROUTE_UPDATE_MANIFEST` at that file, or copy
   `backend/updates.example.json` and set each channel/platform's dotted numeric
   version, Git `revision`, exact local `file`, SHA-256 checksum, notes and
   optional `required` flag. The platform keys are `linux`, `windows`, `macos`,
   `web`, `steamvr` and `quest`.
3. The backend reloads the manifest on each update request, so a successful
   asset poll becomes available without restarting Node. It only serves local
   filenames referenced by a valid manifest.
4. Debug exports query the `debug` channel and release exports query `release`.
   Exported debug builds compare both version and Git revision, and keep PLAY
   locked until the check succeeds. If the revision changed, the client
   automatically downloads and installs the matching archive even while the
   version remains `0.0.1.0`.

Desktop clients SHA-256-check and unpack the archive under their private user
data folder. Required/debug updates then start an independent helper; optional
release updates wait for INSTALL & RESTART. The helper waits for the game to
exit, keeps a backup of the replaced files, installs the staged build, and
relaunches it. Web refreshes the hosted page with a revision cache-buster.
Quest downloads and verifies its APK, then opens Android's package installer;
Android still requires the player to approve a sideloaded package replacement.
Existing clients from before automatic installation require one final manual
install of this bridge build. After that, newly published commits do not need a
version change or browser download.

## Pterodactyl source auto-restart

With the server-side GitHub PAT configured, the backend watches GitHub `main`
automatically. When the remote SHA differs from the deployed repository's
`git rev-parse HEAD`, the service closes its HTTP listener and exits with
status 75. Enable Pterodactyl's automatic crash restart and keep the existing
`git pull` in the startup command: the restart runs that pull, then launches
the current `index.js`. The watcher never runs `git pull` itself and never
rewrites source files while Node is executing them. Set
`LASTROUTE_RESTART_ON_GITHUB_UPDATE=false` only when a deployment must stay
pinned.

If the startup pull fails or Pterodactyl crash restart is disabled, this cannot
self-heal; the logs will show the local and remote short SHAs. Leave the option
off on a manually managed production release branch.

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
