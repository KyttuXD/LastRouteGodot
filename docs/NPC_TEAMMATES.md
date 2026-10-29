# NPC teammates

The host can add AI runners to a co-op route: the staging screen's **NPC TEAMMATES** row (host only, 0–4, default none).
Guests need nothing: they see each NPC as another runner.

- **Who runs them:** the host only (`NpcTeammates`, `src/game_3d/npc_teammates.gd`). Each NPC's state goes out through
  `RemotePlayers.npc_state` like a player's. The host keeps it in its runner states, so the hunters' target list, the maps and the
  player list (`NPC · ROOK`) include it, and guests get it through one host-only RPC (`_xnpc_place`).
- **What they do:**
  - keep with the nearest human runner on their storey (each in its own slot around them);
  - sprint away from a chasing hunter;
  - when their runner has been on another storey for 6 s, rejoin them there. They do not walk stairs yet.
- **Caught:** by a hunter's capture (`send_player_event` "capture" to an NPC id) or a chasing hunter within 1.3 m. The NPC goes
  down where it stood and opens the normal revive window (`ReviveDowns`, [revives](REVIVE.md)). A teammate's Revive Kit hold
  brings it back with 4 s of grace. If the window closes, it is out of the run like a caught player.
- **Ids:** `NpcTeammates.ID_BASE` (2,000,000,000) and up, never an ENet peer; `RemotePlayers.is_npc(id)`. Player events to an NPC
  are never sent; a capture becomes `npc_captured`.

## Budget
- **Network:** each NPC sends one full state packet to each guest at 12 Hz, at most
  600 bytes (the suite checks it). Four NPCs to three guests is at most about 86 KB/s of host upload.
- **CPU:** each NPC uses a grid path every 0.5 s (the hunters' `find_path`) plus a straight-line step per frame. There's no
  physics body.

## Not yet
- Walking stairs and ladders. For now, rejoining another storey puts the NPC beside its runner there.
- Picking things up, hiding, relays and doors (players do those).
- Saves: a continued run starts without its NPCs until the host's setting starts them again.

`godot --headless --path . res://scenes/validate.tscn -- npc_teammates` checks:
- the setting clamps;
- the RPC sorts last;
- the NPCs appear in the runner states, the player list and the target list;
- the packet budget;
- following;
- capture, the revive window, revive, and being out.
