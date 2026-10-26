# Deploying the Godot 2 backend on VPS 3

Everything here is **prepared, not applied**. Nothing in this repo logs into a server. Every command
marked **[KT OK]** changes the server and must only be run after KT approves it. Commands marked
**[read-only]** change nothing.

## What actually runs on the server

One dependency-free Node service (`index.js` -> `backend/server.mjs`):

| Part | Port | Notes |
| --- | --- | --- |
| HTTP API: room codes, accounts, updates, PUBLIC route state | **TCP 8105** | the game client hardcodes `http://lastroute.kyttuslab.org:8105` |
| Authenticated UDP gameplay relay (co-op and PUBLIC route traffic) | **UDP 1105** | players connect outbound only; this is the single inbound game port |

No Godot dedicated server is needed. Co-op and the PUBLIC route are *host-authoritative*: a player's game
is the host (the PUBLIC route authority is a runner chosen through the backend), the Node service only
relays packets and stores state. So there is **no Godot headless export** to build or ship. (If that ever
changes: `export_presets.cfg` has a "Linux Debug Tools" preset; the command would be
`godot --headless --path . --export-debug "Linux Debug Tools" build/server.x86_64`, with the matching
Godot export templates installed on the build machine, and a second unit modelled on the Node one.)
Node has no npm dependencies: there is no `npm install` step.

Service name `lastroute-godot2`, user `lastroute2`, code in `/opt/lastroute-godot2`, data in
`/var/lib/lastroute-godot2`, secrets in `/etc/lastroute-godot2/lastroute-godot2.env`. None of these
collides with `last-route.service` (the website/web game), which is never touched.

## Files in this repo

| File | Purpose |
| --- | --- |
| `deploy/lastroute-godot2.service` | hardened systemd unit (no new privileges, read-only OS, private /tmp, only its state dir writable, memory cap 512 MB, journald logs, `Restart=on-failure`) |
| `deploy/lastroute-godot2.env.example` | environment template, no secrets |
| `deploy/deploy.sh` | idempotent install/upgrade/rollback, **dry run by default** |
| `deploy/firewall.sh` | opens only TCP 8105 and UDP 1105 (`--instance test`: 8205/1205), **dry run by default** |
| `deploy/smoke.mjs` | network smoke test (health, room register/resolve/unregister, PUBLIC status) |
| `deploy/nginx-godot.kyttuslab.org.conf.example` | optional HTTPS front for a future subdomain |

## Port plan

* Open **TCP 8105** and **UDP 1105**, nothing else. Not 80/443 (website), not the Minecraft port.
* Before anything: confirm both are free on VPS 3 (pre-flight step 3). If anything holds them, stop and
  ask KT; the ports are baked into the shipped client (`PRIMARY_BASE_URL` in
  `src/autoload/backend_client.gd`, relay port returned by the backend), so changing them means a client
  change too. `deploy.sh` aborts on a port conflict and never kills the other process.
* Hosting: the game must run on **VPS 3 = 194.156.90.219**. `195.62.47.178` is VPS 2 (the overflow
  Minecraft host) and must **not** be used for Last Route. `lastroute.kyttuslab.org` does not resolve at
  all today, so the DNS record below has to be created. Whether TCP 8105 / UDP 1105 are free on VPS 3 is
  still to be checked read-only (pre-flight step 3).

### Cloudflare DNS (kyttuslab.org)

* Record: **A** `lastroute` -> `194.156.90.219` (VPS 3), **DNS only (grey cloud)**. (AAAA only if IPv6
  ports are opened too.) The website itself (`kyttuslab.org`, currently proxied through Cloudflare to VPS 3)
  stays proxied and is not changed.
* The orange-cloud proxy cannot carry UDP at all, and it only proxies a short list of HTTP ports (8105 is
  not on it), so the record **must** stay DNS-only. The relay host name the backend hands out
  (`LASTROUTE_RELAY_HOST`) must be this same name or the IP.
* Optional later: **A** `godot` -> same IP, orange cloud allowed (443 only) for the nginx snippet. The
  game port record stays grey.

## Facts found on VPS 3 (read-only checks, 2026-10-26)

Host `green-duck-34581` (194.156.90.219), Ubuntu 24.04.5, 3.8 GB RAM (~3.2 GB free), 25 GB root disk (12 GB
free), Node v18.19.1 at `/usr/bin/node` (system package, fine), git 2.43. Running: `last-route.service`
(root, `/root/web`, Node on 0.0.0.0:80, `Restart=always`) and `kyttu-discord-bot.service`. TCP 8105 and UDP
1105 are **free**. ufw is inactive and iptables is all ACCEPT (a provider-side cloud firewall may exist).
No nginx, Caddy or Docker, and no `lastroute2` user yet. Consequences: plain systemd, no Docker; no reverse
proxy exists, so the game's HTTP API (TCP 8105) and relay (UDP 1105) bind directly; TLS for the API is an
optional later step (a Cloudflare-proxied standard HTTPS port with a small proxy in front; Cloudflare never
proxies 8105 or UDP). `deploy/firewall.sh` prints "no host firewall rule is needed" on such a host.
`deploy/deploy.sh` (dry run) also prints the exact read-only pre-flight commands for the target.

## Pre-flight (all [read-only], run on VPS 3 via SSH once KT restored access)

```sh
# 1. who am I, what is this box
hostnamectl; uname -a; uptime
# 2. resources
df -h /opt /var /etc; free -h; nproc
# 3. ports: expect NOTHING on tcp/8105 and udp/1105 (and note what holds 80/443/25565)
ss -tulpn | grep -E ':(8105|1105)\b' || echo "8105/1105 free"
ss -tulpn
# 4. node: must be >= 18 and at a system path (not under /home or /root, the unit blocks those)
command -v node; node --version
# 5. existing services: look, do not touch
systemctl list-units --type=service --state=running | grep -Ei 'last|route|node|nginx|minecraft|discord|pterodactyl|wings'
systemctl cat last-route.service | head -40
# 6. firewall and proxy in use
sudo ufw status verbose 2>/dev/null; sudo iptables -S 2>/dev/null | head -40
nginx -v 2>&1; ls /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null
# 7. does the name already point here?
dig +short lastroute.kyttuslab.org   # expected: empty until the record exists, then 194.156.90.219
curl -s ifconfig.me                  # expected: 194.156.90.219 (this must be VPS 3, not VPS 2)
```

Back up first: `sudo tar czf ~/pre-godot2-$(date +%F).tgz /etc/systemd/system /etc/nginx` (small, config only).
Expected downtime: **none** for the website, the bot and Minecraft; only new files, a new unit and two new
listening ports are added.

## Deploy, in this order

Copy this repo (or just `deploy/`, `backend/`, `index.js`, `package.json`, `docs/`) to the server, for
example `rsync -a --exclude .git --exclude .data --exclude .env ./ vps3:/tmp/lastroute-godot2-src/`.
All commands below run on VPS 3 from that directory.

| # | Command | Needs KT OK? |
| --- | --- | --- |
| 1 | `deploy/deploy.sh` (dry run: prints every change, performs none) | no |
| 2 | `sudo deploy/deploy.sh --apply --no-start` creates user, dirs, release, env file (admin password generated with `openssl rand`), installs and enables the unit, does **not** start it | **[KT OK]** |
| 3 | `sudo grep ADMIN /etc/lastroute-godot2/lastroute-godot2.env` then store the value in KT's password manager; edit the env only if the pre-flight changed a port or name | **[KT OK]** (touches secrets) |
| 4 | `sudo deploy/firewall.sh` (dry run) then `sudo deploy/firewall.sh --apply` | dry run no, apply **[KT OK, firewall change]** |
| 5 | `sudo deploy/deploy.sh --apply` starts the service, waits for `/api/health`, runs `deploy/smoke.mjs`, and **rolls back by itself** if the smoke test fails | **[KT OK]** |
| 6 | From outside (KT's laptop): `curl http://lastroute.kyttuslab.org:8105/api/health` and `node deploy/smoke.mjs http://lastroute.kyttuslab.org:8105` | no |
| 7 | Cloudflare: A `lastroute` DNS-only -> VPS 3 IP (only if it does not already) | **[KT OK]** |
| 8 | Optional TLS front: install `deploy/nginx-godot.kyttuslab.org.conf.example` as its own site, `sudo nginx -t`, **only then** `sudo systemctl reload nginx` | **[KT OK]** |

Useful afterwards (read-only): `systemctl status lastroute-godot2`, `journalctl -u lastroute-godot2 -f`,
`curl -s http://127.0.0.1:8105/api/health`, `curl -s http://127.0.0.1:8105/api/public/status`.

Owner account: the generated `LASTROUTE_ADMIN_PASSWORD` is the *setup key* for the `KYTTU`/`AYTTU` accounts
(see `backend/README.md` "Accounts and release admin"). It is not a login password.

### Updates

`LASTROUTE_AUTO_UPDATE` and `LASTROUTE_RESTART_ON_GITHUB_UPDATE` are **off** in the template. Turning them
on needs a read-only GitHub token (`LASTROUTE_GITHUB_TOKEN`) for the repository that holds the update
release; KT creates it in GitHub, it goes only into the env file on the server. With restart-on-update on,
the process exits with code 75 when the watched branch advances and systemd restarts it
(`Restart=on-failure`). A new backend release is otherwise shipped with `deploy.sh --apply`.

## Test instance (a second copy on the same VPS)

A separate instance for experiments and tests, so production data is never touched:

| | production | test |
| --- | --- | --- |
| service | `lastroute-godot2` | `lastroute-godot2-test` |
| user | `lastroute2` | `lastroute2test` |
| code | `/opt/lastroute-godot2` | `/opt/lastroute-godot2-test` |
| env (secrets) | `/etc/lastroute-godot2/` | `/etc/lastroute-godot2-test/` (own generated admin key) |
| data | `/var/lib/lastroute-godot2` | `/var/lib/lastroute-godot2-test` |
| ports | TCP 8105 / UDP 1105 | **TCP 8205 / UDP 1205** |
| `/api/health` `instance` | `"production"` | `"test"` |

`deploy.sh --instance test` never touches the production unit, files or ports, and refuses to run if its
env file would use 8105/1105. Everything is a dry run until `--apply`. Each step marked **[KT OK]** needs
approval (it is a change on VPS 3).

```sh
# on VPS 3, from the copied repo directory
deploy/deploy.sh --instance test                       # dry run: prints the read-only pre-flight and every change
sudo deploy/deploy.sh --instance test --apply --no-start   # [KT OK] user, dirs, release, env (generated admin key), unit
sudo deploy/firewall.sh --instance test                # dry run; ufw is inactive on VPS 3 so no host rule is needed
# (cloud firewall: allow TCP 8205 and UDP 1205 in the provider panel)  [KT]
sudo deploy/deploy.sh --instance test --apply          # [KT OK] start, health + smoke (instance must say "test"), auto-rollback
curl -s http://127.0.0.1:8205/api/health               # "instance":"test"
```

DNS: the same `lastroute.kyttuslab.org` name serves both instances (different ports), so no new record is
needed. The test instance returns `lastroute.kyttuslab.org:1205` as its relay address (`LASTROUTE_RELAY_PORT`
in its env file).

* **Reset / wipe:** `sudo deploy/deploy.sh --instance test --wipe-data --apply` stops the test service,
  empties `/var/lib/lastroute-godot2-test` (accounts, PUBLIC route state) and starts it again. It is refused
  for production. Wiping before a PUBLIC route test is recommended because the PUBLIC route keeps its state for
  the UTC day.
* **Redeploy / roll back the test instance:** `sudo deploy/deploy.sh --instance test --apply` (new release dir),
  `sudo deploy/deploy.sh --instance test --rollback --apply`.
* **Promote a tested release to production:** the release directory is just a copy of the repo, so promote by
  deploying the *same source* to production after the test instance passed: copy the tested release dir
  (`/opt/lastroute-godot2-test/releases/<release>`) and run `sudo deploy/deploy.sh --src <that dir> --apply`
  (production is the default instance). Production data is untouched except by its own code upgrade. The
  production env file is never overwritten.
* **Remove it:** `sudo systemctl disable --now lastroute-godot2-test`, delete the unit, `/opt/lastroute-godot2-test`,
  `/etc/lastroute-godot2-test`, `/var/lib/lastroute-godot2-test` and the `lastroute2test` user (all test-only).

### Pointing the game and the test scripts at the test instance

* **Godot client (debug builds only):** run with `-- --backend=http://lastroute.kyttuslab.org:8205`. That one
  origin (exact match) is accepted on top of the loopback override; any other host is ignored with a warning,
  and release/exported-release builds ignore the flag entirely. While it is active the menu and HUD show a
  red **TEST SERVER // lastroute.kyttuslab.org:8205** badge. There is no separate relay flag: the room
  directory tells the client the relay address and port (from the server's env), so pointing the client at the
  test HTTP origin is enough. Account sign-in stays disabled for that plain-HTTP origin.
* **Test scripts:** `REMOTE=1 BACKEND_URL=http://lastroute.kyttuslab.org:8205 scripts/coop_test.sh` and
  `scripts/public_test.sh` run the real clients against that server instead of starting a local one.
  Skipped when remote: the local server log, and in `public_test.sh` the backend-restart step (the "authority
  survives a restart" check only re-confirms the authority still holds). `scripts/remote_smoke.sh` runs the
  node smoke test (with the instance check), `backend_smoke.tscn` and the co-op test (host + guest + late
  joiner) against the test instance.
* **Production is protected:** all of them refuse any target on port 8105, any host except loopback and the
  test URL, and the Godot side refuses if the client silently fell back to the production origin. To really
  target production you must pass `--i-know-this-is-production`; don't.

## Rollback

```sh
sudo deploy/deploy.sh --rollback --apply        # [KT OK] previous release, service restarted
# full removal (also [KT OK]); leaves data in /var/lib/lastroute-godot2 unless you delete it:
sudo systemctl disable --now lastroute-godot2
sudo rm /etc/systemd/system/lastroute-godot2.service && sudo systemctl daemon-reload
sudo deploy/firewall.sh   # prints the matching ufw/iptables rules; remove them with: ufw delete allow 8105/tcp ; ufw delete allow 1105/udp
```

The last 5 release directories are kept under `/opt/lastroute-godot2/releases`.

## Troubleshooting

* **First start fails with `EACCES` on `/opt/lastroute-godot2/releases/<rel>/index.js`** (journal:
  `Permission denied`): the release files kept private modes (0700) from the source machine, so the
  unprivileged `lastroute2` user cannot read them. This happened on the first VPS 3 deploy and was fixed by
  hand with `chmod -R u=rwX,go=rX <release dir>`. `deploy.sh` now normalises modes (`u=rwX,go=rX`, root
  owned, parent directories traversable) right after copying and prints a hint if a start fails with a
  permission error. A failed smoke test rolls back to the previous release, or stops the service when there
  is none.
* `journalctl -u lastroute-godot2 -n 50 --no-pager` is the first place to look; `systemctl status
  lastroute-godot2` shows the exit code (75 = restart requested by the updater, normal).

## What was verified locally (no remote host was contacted)

* `deploy.sh` dry run, `--apply --prefix <tmp>` (staging, no root, no systemd), a second run (idempotent:
  env file untouched, unit unchanged, new release dir), `--rollback`, and release pruning to 5.
* The deployed copy started with the generated env file (ports overridden to free ones) passes
  `deploy/smoke.mjs`, and `scripts/coop_test.sh` / `scripts/public_test.sh` pass against that copy
  (`SERVER_ROOT=<release dir>`).
* `npm test` backend tests pass (35). Test instance: `deploy.sh --instance test` staged next to production (separate
  unit/user/env/data/release dirs, ports 8205/1205, different generated admin key, `"instance":"test"` in health,
  wipe and rollback work, wipe refused for production). `scripts/coop_test.sh` and `scripts/public_test.sh` pass in
  default mode and with `REMOTE=1` against a loopback server; `scripts/remote_smoke.sh` passes; production and
  unknown targets are refused. Not run: anything against the real VPS.
* **Not** verifiable on a Mac: the systemd unit itself (`systemd-analyze verify`, the sandboxing options,
  `StateDirectory`) and `useradd`/`chown`/`ufw`. On the VPS run `systemd-analyze verify
  /etc/systemd/system/lastroute-godot2.service` after step 2; if a hardening option is rejected by an old
  systemd, remove just that line.

## Questions for KT before deploying

Answered: host/IP (VPS 3, 194.156.90.219), plain systemd (no Docker), no headless Godot server, Node 18
present, host firewall off, ports 8105/1105 free. Still open:

1. Cloud firewall: check in the provider panel that TCP 8105 and UDP 1105 are allowed (KT).
2. Subdomain: create `lastroute.kyttuslab.org` as a DNS-only A record to 194.156.90.219 (matches the client);
   a TLS front such as `godot.kyttuslab.org` is optional and later.
3. Updates: enable GitHub release sync? It is off by default and needs a token and a repo choice
   (`KyttuXD/LastRouteGodot2` or the old `KyttuXD/LastRouteGodot`).
4. Explicit OK on the exact deploy commands (steps 2 to 5 above).
