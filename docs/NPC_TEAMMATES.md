# NPC teammates

Admins and devs can add AI runners to a co-op route: the staging screen's **NPC TEAMMATES** scroller (◀ N ▶, default 0, no upper limit on the stepper). The run itself has no cap: `NpcTeammates.COUNT_LIMIT` is 0 (unlimited), and admin spawn requests are not capped per request either. Players never see it; it shows only with admin tools (`Build.tools_enabled()`) for the host.
Guests need nothing: they see each NPC as another runner.

- **Who runs them:** the host only (`NpcTeammates`, `game/player/npc_teammates.gd`). Each NPC's state goes out through
  `RemotePlayers.npc_state` like a player's. The host keeps it in its runner states, so the hunters' target list, the maps and the
  player list (`NPC · ROOK`) include it, and guests get it through one host-only RPC (`_xnpc_place`).
- **What they do:**
  - keep with the nearest human runner on their storey (each in its own slot around them);
  - sprint away from a chasing hunter;
  - when their runner is on another storey, walk to a stair, spiral, ladder or ramp and cross it. They do not teleport.
- **Caught:** by a hunter's capture (`send_player_event` "capture" to an NPC id) or a chasing hunter within 1.3 m. The NPC goes
  down where it stood and opens the normal revive window (`ReviveDowns`, [revives](REVIVE.md)). A teammate's Revive Kit hold
  brings it back with 4 s of grace. If the window closes, it is out of the run like a caught player.
- **Ids:** `NpcTeammates.ID_BASE` (2,000,000,000) and up, never an ENet peer; `RemotePlayers.is_npc(id)`. Player events to an NPC
  are never sent; a capture becomes `npc_captured`.

## Budget

Source of truth: `NpcPerfTable` (`game/config/npc_perf_table.gd`). `SEND_HZ`, `COUNT_LIMIT` and `REPATH` are the same numbers as `NpcTeammates`. The suite fails if this table, that script, or `NpcTeammates` disagree.

The count is unlimited (`COUNT_LIMIT` 0), so the rows are estimates for the counts an admin is likely to run, not a cap. Each NPC adds one packet per guest at `SEND_HZ`, and one grid search per `REPATH`. The first searches are staggered over `REPATH` so a large batch does not pathfind on one frame. Slots past 8 sit on a wider ring, so a big group spreads out instead of stacking on the 2.4 m ring.

The host sends one full state packet per NPC to each guest. An NPC has no physics body. One grid pathfind (the hunters' `find_path`) runs per NPC every `REPATH` seconds, plus a straight-line step per frame.

Formula: `npc_count * guest_count * SEND_HZ * packet_size` bytes/s of host upload, with `packet_size` at most `PACKET_BUDGET`. Pathfinds/s = `npc_count / REPATH`.

Constants: SEND_HZ=12, PACKET_BUDGET=600, COUNT_LIMIT=0, REPATH=0.5.

KB/s is bytes/s / 1000. The cells below are the ceiling, using a packet of `PACKET_BUDGET` bytes. Four NPCs to three guests is 86.4 KB/s (the same case the old note called about 86 KB/s).

| NPCs | Guests | Bytes/s | KB/s | Pathfinds/s |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 7200 | 7.2 | 2 |
| 1 | 3 | 21600 | 21.6 | 2 |
| 4 | 1 | 28800 | 28.8 | 8 |
| 4 | 3 | 86400 | 86.4 | 8 |
| 8 | 1 | 57600 | 57.6 | 16 |
| 8 | 3 | 172800 | 172.8 | 16 |
| 16 | 1 | 115200 | 115.2 | 32 |
| 16 | 3 | 345600 | 345.6 | 32 |
| 32 | 1 | 230400 | 230.4 | 64 |
| 32 | 3 | 691200 | 691.2 | 64 |
| 64 | 1 | 460800 | 460.8 | 128 |
| 64 | 3 | 1382400 | 1382.4 | 128 |

## Not yet
- Picking things up, hiding, relays and doors (players do those).
- Saves: a continued run starts without its NPCs until the host's setting starts them again.

`godot --headless --path . res://tests/scenes/validate.tscn -- npc_teammates` checks:
- the setting clamps;
- the RPC sorts last;
- the NPCs appear in the runner states, the player list and the target list;
- the packet budget and the performance table (helper, formula, and the rows above);
- following;
- capture, the revive window, revive, and being out;
- hunters ignore leaves an NPC out of the hunt, and hunters target makes them prefer it over a closer runner. The two clear each other.
- an NPC whose runner is on another storey reaches it along a stair or ladder (its position follows the link, and it is not moved there in one frame).

## Admin tools

The admin menu's **NPCS** page needs the `world` permission and works solo or as host. A guest admin's commands go to the
host, which checks the guest's admin proof first and logs refused ones (`[coop] admin request refused …`).
- **Spawn:** ◀ N ▶ NPCs (up to 16 per click) with a smartness (30/50/70/90), at the crosshair's floor when it is walkable and
  within 40 m, else beside you. Click again for more: the run has no total cap.
- **Remove:** the nearest NPC, or all of them.
- **One NPC from the live list** (name, state, distance): teleport to me, go to me, follow me / stop following, set smartness,
  chat on or off, freeze or resume, hunters ignore or target it, down, revive, kill, remove, and spectate it (your camera only).
- **ALL NPCS:** one row runs a bulk op on every NPC in the run (`admin_world` "npc" with `"all": true`, the list in
  `NpcTeammates.BULK_OPS`): all to me, all follow me / stop following, all freeze / resume, all ignore / target / clear,
  all chat on / off, all smart. Down, revive, kill, goto and remove stay per NPC; the host refuses any other bulk op.
- **Clear hunter flags:** drops both ignore and target from one NPC (`clear` in `NpcTeammates.OPS`).
- **Hunters ignore:** hunters skip that NPC. The list shows `IGNORED`.
- **Hunters target:** hunters on that NPC's floor prefer it over every other runner there (the closest marked NPC, when
  several are marked). The list shows `TARGET`. Ignore and target clear each other. Your own NO TARGET toggle still hides
  only you; it does not stop hunters choosing an NPC.
- **Sync:** the admin flags ride the NPC's state (`no_target`, `hunt_target`, `npc_admin`: [frozen | chat << 1, smartness,
  followed peer]), so every peer lists the same. A removed NPC disappears on every guest at once (`_xnpc_remove`).
- **Smartness:** sets how early an NPC notices a chasing hunter, from half the range at 0 to one and a half times at 100.
- **Chat:** with chat on, an NPC calls out a hunter chasing it within 12 m, at most once every 30 s, read aloud by the TTS in
  its own voice.
