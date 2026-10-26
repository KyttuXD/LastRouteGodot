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
| `deploy/firewall.sh` | opens only TCP 8105 and UDP 1105, **dry run by default** |
| `deploy/smoke.mjs` | network smoke test (health, room register/resolve/unregister, PUBLIC status) |
| `deploy/nginx-godot.kyttuslab.org.conf.example` | optional HTTPS front for a future subdomain |

## Port plan

* Open **TCP 8105** and **UDP 1105**, nothing else. Not 80/443 (website), not the Minecraft port.
* Before anything: confirm both are free on VPS 3 (pre-flight step 3). If anything holds them, stop and
  ask KT; the ports are baked into the shipped client (`PRIMARY_BASE_URL` in
  `src/autoload/backend_client.gd`, relay port returned by the backend), so changing them means a client
  change too. `deploy.sh` aborts on a port conflict and never kills the other process.
* Hosting note: `lastroute.kyttuslab.org` currently resolves to `195.62.47.178`, and the older backend
  documentation describes a Pterodactyl panel at that address on the same ports. If that panel host *is*
  VPS 3 and is still serving 8105/1105, this deploy would clash. See the questions at the end.

### Cloudflare DNS (kyttuslab.org)

* Record: **A** `lastroute` -> VPS 3's public IPv4, **DNS only (grey cloud)**. (AAAA only if IPv6 ports
  are opened too.)
* The orange-cloud proxy cannot carry UDP at all, and it only proxies a short list of HTTP ports (8105 is
  not on it), so the record **must** stay DNS-only. The relay host name the backend hands out
  (`LASTROUTE_RELAY_HOST`) must be this same name or the IP.
* Optional later: **A** `godot` -> same IP, orange cloud allowed (443 only) for the nginx snippet. The
  game port record stays grey.

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
dig +short lastroute.kyttuslab.org; curl -s ifconfig.me
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

## Rollback

```sh
sudo deploy/deploy.sh --rollback --apply        # [KT OK] previous release, service restarted
# full removal (also [KT OK]); leaves data in /var/lib/lastroute-godot2 unless you delete it:
sudo systemctl disable --now lastroute-godot2
sudo rm /etc/systemd/system/lastroute-godot2.service && sudo systemctl daemon-reload
sudo deploy/firewall.sh   # prints the matching ufw/iptables rules; remove them with: ufw delete allow 8105/tcp ; ufw delete allow 1105/udp
```

The last 5 release directories are kept under `/opt/lastroute-godot2/releases`.

## What was verified locally (no remote host was contacted)

* `deploy.sh` dry run, `--apply --prefix <tmp>` (staging, no root, no systemd), a second run (idempotent:
  env file untouched, unit unchanged, new release dir), `--rollback`, and release pruning to 5.
* The deployed copy started with the generated env file (ports overridden to free ones) passes
  `deploy/smoke.mjs`, and `scripts/coop_test.sh` / `scripts/public_test.sh` pass against that copy
  (`SERVER_ROOT=<release dir>`).
* `npm test` backend tests pass.
* **Not** verifiable on a Mac: the systemd unit itself (`systemd-analyze verify`, the sandboxing options,
  `StateDirectory`) and `useradd`/`chown`/`ufw`. On the VPS run `systemd-analyze verify
  /etc/systemd/system/lastroute-godot2.service` after step 2; if a hardening option is rejected by an old
  systemd, remove just that line.

## Questions for KT before deploying

1. Is `lastroute.kyttuslab.org` (195.62.47.178) VPS 3, and is anything (Pterodactyl, the old backend)
   already using TCP 8105 / UDP 1105 there? Should the Godot 2 service replace it or live beside it on
   other ports (needs a client change)?
2. Subdomain: keep `lastroute.kyttuslab.org` for the game (matches the client) and add `godot.kyttuslab.org`
   only if a TLS front is wanted, or something else?
3. Plain systemd (prepared) or Docker? Plain systemd is what is prepared; Docker would only add a layer for a
   dependency-free Node service.
4. Godot headless server: not needed with the current host-authoritative design. Confirm.
5. Updates: enable GitHub release sync (needs a token and which repo: `KyttuXD/LastRouteGodot2` or the old
   `KyttuXD/LastRouteGodot`)? Default is off.
6. Node on VPS 3: is a system Node >= 18 installed (not nvm under a home directory)?
7. Is a cloud-provider firewall in front of the VPS (separate from ufw)? TCP 8105 and UDP 1105 must be allowed
   there as well.
