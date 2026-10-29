# Server hosting: dedicated hosts, regions and load split

KT, 2026-10-28: "lets do regional, and load splitting like that, and we can also work on server sync performance".

Rooms used to be hosted only by a player's game. This adds rooms hosted by a headless game on our VPSes, spread over
regions by load and ping, with the VPS 3 backend staying the single room directory.

| VPS  | Where      | Size            | Role                                                        |
|------|------------|-----------------|-------------------------------------------------------------|
| vps1 | Virginia   | 12 cores, 31 GB | primary dedicated-host region (capacity 11 at 700 MB/room)  |
| vps2 | Texas      | 4 cores, 7.9 GB | secondary region (capacity 3); also hosts the mod files     |
| vps3 | California | 4 cores, 3 GB   | the directory + relay only -- no dedicated hosts            |

Measured read-only on 2026-10-28: both vps1 and vps2 run Ubuntu 24.04 x86_64, mostly idle, with neither Godot nor Node
installed yet (the deploy installs Node 20+ and copies the game build).

## Stages

1. **Dedicated headless host** (done, `--dedicated-host`).
2. **Region agent** (done): spawns/stops dedicated hosts per VPS under a CPU/RAM-aware capacity; systemd unit.
3. **Regions and load split** (next): a relay per region, clients ping regions, rooms go to the lowest-ping region
   with capacity.
4. **Sync performance**: profiling, interest management, delta compression, 30 Hz sim / 20 Hz send with backoff,
   an 8-guest load test at 150 ms / 5% loss.

## 1. Dedicated headless host

```
LastRoute-Dedicated.x86_64 --headless -- --dedicated-host CODE [--seed TEXT] [--mode N] [--scale N]
    [--difficulty N] [--port N] [--idle-minutes M]
```

(from a project checkout: `godot --headless --path <project> -- --dedicated-host ...`)

- Hosts CODE through the directory and relay like any host, then starts the route at once; guests late-join into it.
  It shows as SERVER and has no runner: its player node is parked (no physics, input or body), hunters, Gray and
  anti-idle only ever see guests, and guests neither draw nor target it (its state is marked `syncing`).
- Quits after the room has been empty for `--idle-minutes` (default 10), unregistering first: the code stops
  resolving at once. Killed, the relay drops it within about a second (HOST_ALIVE).
- Reserved codes (KATHY, AKIRI): the host proves access with a one-time spawn ticket from the region agent
  (`LASTROUTE_SPAWN_TICKET`), or `LASTROUTE_ROOM_PASSWORD` / `LASTROUTE_HOST_SESSION` -- always the environment,
  never the command line.
- Build: `scripts/build_dedicated_host.sh` (the existing "Linux Debug Tools" export, same version and revision as the
  player builds) writes `builds/dedicated/LastRoute-Dedicated.x86_64` and a manifest.
- Guests on a different build are refused before they connect ("BUILD MISMATCH // HOST <rev> YOU <rev> // UPDATE",
  `NetProtocol.fingerprint()`), so a dedicated host and its players must run the same network protocol.

## 2. Region agent

`backend/region_agent.mjs`, one per region VPS, run by `deploy/lastroute-region-agent.service` with
`/etc/lastroute-agent/agent.env` (names in `deploy/region-agent.env.example`).

- **Capacity** = min(cores - 1, (RAM - 1 GB) / `LASTROUTE_ROOM_MB`), capped by `LASTROUTE_MAX_ROOMS`. A new room
  is refused while load average is above 80% of the cores or free RAM is under one room's budget.
- **Reports** every 5 s to `POST /api/regions/report`: label, relay endpoint, capacity, load, free RAM, and each
  dedicated host (code, PID, uptime, RSS). The answer carries the spawn/stop requests for this region; the agent
  needs no inbound port.
- **Auth**: each request is signed -- `x-lr-region`, `x-lr-time`, `x-lr-signature` = HMAC-SHA256(token,
  `region\ntime\nbody`) -- with a 60 s clock window and no replays. The token itself never travels (the directory is
  plain HTTP). Tokens: `LASTROUTE_AGENT_TOKEN` on the agent, `LASTROUTE_AGENT_TOKENS=virginia:<t>,texas:<t>` on the
  directory; generated on the servers, never in the repo.
- **Spawning**: the game binary with `--dedicated-host CODE --port <18100+> --idle-minutes N`; the spawn ticket and
  region go in the child's environment (the agent's own token does not). **Stopping**: SIGTERM to that exact child,
  SIGKILL after 10 s. Stopping the agent stops its rooms.
- **Directory (VPS 3)**: `GET /api/regions` (public: live regions, relay endpoint, free slots);
  `POST /api/admin/regions` (owner): `list`, `spawn { region, code, seed?, difficulty?, idleMinutes? }`,
  `stop { region, code }`. A spawn for a reserved code mints a 5-minute, single-use spawn ticket that only that
  code's registration accepts. Rooms registered by a dedicated host carry `dedicated` and `region`.

### Deploy (coordinator, after KT's OK)

On vps1 / vps2: create user `lastroute-region`; install Node 20+; copy the repo's `backend/` to
`/opt/lastroute-region/current/backend` and the build to `/opt/lastroute-region/current/game/`; write
`/etc/lastroute-agent/agent.env` with a generated token; install and start the unit. On VPS 3: add the matching
`LASTROUTE_AGENT_TOKENS` to the backend's env and restart it. Check with `POST /api/admin/regions {action: "list"}`.

## Not built yet

- A relay per region and client region choice (stage 3).
- Sync performance work (stage 4).
