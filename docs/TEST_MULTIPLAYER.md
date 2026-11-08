# Testing multiplayer (several instances, or another computer)

## Several instances on one machine
```sh
tools/build/run_multi.sh 3 --test     # 3 tiled windows against a TEST instance of the backend (set BACKEND_URL to its address)
tools/build/run_multi.sh 2 --local    # 2 windows against a throwaway local backend the script starts and stops
```
- Needs a debug game (this checkout run with Godot). Each window gets `--profile=pN`, so it has **its own settings file and
  its own login** (`user://settings_pN.cfg`, `user://last_route_account_pN.cfg`): sign in with a different test account in each, or
  play as guests.
- Windows are tiled across the desktop; Ctrl-C in the terminal (or closing the windows) stops everything, the local
  backend included (killed by exact PID).
- Against a TEST instance every window shows the red **TEST SERVER** badge. The local mode has no badge (it is your own
  loopback server).
- Flow: window 1 CREATE ROOM, read the 5-letter code, windows 2..N JOIN ROOM with it; or press PUBLIC ROUTE in all of them.
  `--scene res://game/infinite_route/infinite_route_test.tscn` skips the menu.

## From another computer
1. Run a TEST instance of the backend on a host you control (see `backend/README.md`) and open **TCP 8205** and **UDP 1205**
   (or the ports you configured) in its firewall.
2. Export test builds with `tools/build/export_test_multiplayer.sh` (needs the Godot export templates for the project's Godot
   version: Godot > Editor > Manage Export Templates > Download and Install). It writes
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
`nc -vz -u <your-server> 1205` is unreliable for UDP; the real check is `curl http://<your-server>:8205/api/health`
(`"instance":"test"`) plus creating a room and seeing the guest connect. If the HTTP check works but guests cannot connect,
UDP 1205 is most likely blocked by a firewall in front of the server.

## Expected checks
- Create/join by code: both players see each other's bodies, flashlight, held item.
- A relay pickup by the guest is claimed on the host. Hunters are the same on both screens.
- One player dies: spectator mode, the other keeps playing; both die: run over; host restart revives.
- Admin menu (key 0) appears only with a signed-in admin account; the region/region map is off by default (F8).
- PUBLIC route: second player joins the running route; closing the first (authority) hands the route over.

## Deliberate host handoff

`tools/build/handoff_test.sh` (GODOT_BIN set) runs a local backend + relay and three headless processes: the old host
hands a private room over mid-route, the successor rebuilds it as the new peer 1, the other guest reconnects with its
resume identity. Local backend only (it refuses `REMOTE=1`).
