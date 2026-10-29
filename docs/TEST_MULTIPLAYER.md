# Testing multiplayer (several instances, or another computer)

## Several instances on one Mac
```sh
scripts/run_multi.sh 3 --test     # 3 tiled windows against the TEST instance (http://lastroute.kyttuslab.org:8205, UDP relay 1205)
scripts/run_multi.sh 2 --local    # 2 windows against a throwaway local backend the script starts and stops
```
- Needs a debug game (this checkout run with Godot). Each window gets `--profile=pN`, so it has **its own settings file and
  its own login** (`user://settings_pN.cfg`, `user://last_route_account_pN.cfg`): sign in with a different test account in each, or
  play as guests.
- Windows are tiled across the desktop; Ctrl-C in the terminal (or closing the windows) stops everything, the local
  backend included (killed by exact PID).
- Against the TEST instance every window shows the red **TEST SERVER** badge. The local mode has no badge (it is your own
  loopback server).
- Flow: window 1 CREATE ROOM, read the 5-letter code, windows 2..N JOIN ROOM with it; or press PUBLIC ROUTE in all of them.
  `--scene res://scenes/infinite_route_test.tscn` skips the menu.

## From another computer
1. Install the TEST instance once (see "VPS commands" below) and open **TCP 8205** and **UDP 1205** in the provider firewall.
2. On the Mac: `scripts/export_test_multiplayer.sh` (needs the Godot **4.7.2 export templates**: Godot > Editor > Manage Export
   Templates > Download and Install; this machine does not have them yet). It writes
   `build/test/KyttusLab-TEST-<date>-<revision>-{macOS,Windows,Linux}.zip` (never committed). The builds point at the TEST
   instance by default (custom feature `test_server`), show the TEST SERVER badge, and carry the git revision.
3. Copy the zip to the other computer, unzip, run. macOS: right-click > Open the first time. Windows: SmartScreen > More info > Run.
4. On both computers: one creates a room, the other joins with the code (or both press PUBLIC ROUTE).

## Ports and firewall
| What | Port | Direction |
| --- | --- | --- |
| HTTP API (rooms, accounts, PUBLIC route state) | TCP 8205 | clients -> server |
| Gameplay relay (all game traffic) | UDP 1205 | clients -> server (outbound only for players) |
Players never forward ports: the host's game is relayed through the server's UDP port. Check from any machine:
`nc -vz -u lastroute.kyttuslab.org 1205` is unreliable for UDP; the real check is `curl http://lastroute.kyttuslab.org:8205/api/health`
(`"instance":"test"`) plus creating a room and seeing the guest connect. If the HTTP check works but guests cannot connect,
UDP 1205 is blocked at the provider firewall (the Linux host has no ufw rule to change: `ufw` is inactive on VPS 3).

## Expected checks
- Create/join by code: both players see each other's bodies, flashlight, held item.
- A relay pickup by the guest is claimed on the host. Hunters are the same on both screens.
- One player dies: spectator mode, the other keeps playing; both die: run over; host restart revives.
- Admin menu (key 0) appears only with a signed-in admin account; the region/region map is off by default (F8).
- PUBLIC route: second player joins the running route; closing the first (authority) hands the route over.

## Reset the test data
`sudo deploy/deploy.sh --instance test --wipe-data --apply` on the VPS (accounts and PUBLIC route state; refused for production).
The PUBLIC route keeps its state for the UTC day, so wipe before a clean PUBLIC test.

## VPS commands (NOT run: each needs KT's OK)
Read-only dry run (safe, prints everything it would change; this is what `deploy/deploy.sh --instance test` printed locally:
8 changes, nothing touched, production not touched):
```sh
deploy/deploy.sh --instance test
```
Install / update the TEST instance (on VPS 3, in the copied repo directory, after the OK):
```sh
sudo deploy/deploy.sh --instance test --apply --no-start
sudo deploy/firewall.sh --instance test            # dry run; ufw is inactive on VPS 3
# provider panel: allow TCP 8205 and UDP 1205
sudo deploy/deploy.sh --instance test --apply
curl -s http://127.0.0.1:8205/api/health           # "instance":"test"
```
Later updates are `sudo deploy/deploy.sh --instance test --apply` (new release dir, automatic rollback if the smoke test fails).
Details: [DEPLOY_VPS3.md](DEPLOY_VPS3.md).

## Git
The state to test is committed on the local branch `test-push` (not pushed). To publish it: `git push godot2 test-push`.
