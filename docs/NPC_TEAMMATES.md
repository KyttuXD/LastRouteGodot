# NPC teammates

Admins and devs can add AI runners to a co-op route: the staging screen's **NPC TEAMMATES** scroller (◀ N ▶, 0–16, default 0). Players never see it; it shows only with admin tools (`Build.tools_enabled()`) for the host.
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

## Admin tools

The admin menu's **NPCS** page needs the `world` permission and works solo or as host. A guest admin's commands go to the
host, which checks the guest's admin proof first and logs refused ones (`[coop] admin request refused …`).
- **Spawn:** ◀ N ▶ NPCs with a smartness (30/50/70/90), at the crosshair's floor when it is walkable and within 40 m, else
  beside you.
- **Remove:** the nearest NPC, or all of them.
- **One NPC from the live list** (name, state, distance): teleport to me, go to me, follow me / stop following, set smartness,
  chat on or off, freeze or resume, hunters ignore or target it, down, revive, kill, remove, and spectate it (your camera only).
- **Sync:** the admin flags ride the NPC's state (`no_target`, `npc_admin`: [frozen | chat << 1, smartness, followed peer]), so
  every peer lists the same. A removed NPC disappears on every guest at once (`_xnpc_remove`).
- **Smartness:** sets how early an NPC notices a chasing hunter, from half the range at 0 to one and a half times at 100.
- **Chat:** with chat on, an NPC calls out a hunter chasing it within 12 m, at most once every 30 s, read aloud by the TTS in
  its own voice.
