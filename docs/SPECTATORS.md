# Spectators (private rooms and the public route)

A caught runner stops playing but never ends the session for anyone else.

- **Guest caught** (private room): becomes a spectator and reports `caught` to the host. The host keeps playing.
- **Host caught while a guest lives**: the host spectates too. It stays the authority: hunters keep being simulated and broadcast, and the room stays open. Host disconnect still uses the existing host-migration / room-close path.
- **Everyone down** (host already spectating and the last living guest falls, or the last guest leaves): the host sees the RUN OVER report. Restarting the run revives every spectating guest at the checkpoint (`revive` player event).
- **Public route**: caught players spectate for a few seconds and rejoin on their own (grace period). The authority can spectate without dropping the route.
- **Revive Kit** (private rooms): a caught runner can be revived where they went down for 90 s by a teammate with a kit; solo a kit is a one-time second wind on a catch. See [REVIVE.md](REVIVE.md).
- **Solo**: unchanged, normal game over.

Spectators are published with `spectating: true` and `game_over: true`, so hunters never target them and door/objective logic ignores them.

## Ghosts ("more of a ghost player mode, not a free noclip thing")

A spectating runner is a **ghost**, not a free camera:
- **Body:** the same walking body, with world collision, gravity, speed, stairs, ladders, falls and level links. Nothing collides with it (`collision_layer` 0). It never flies and never passes through walls.
- **Look:** see-through (`PlayerController3D.GHOST_FADE`) and washed out by a pale overlay (`set_ghost_look`).
  - Other ghosts always see it.
  - Living runners see it faintly (fade .8), unless Settings → `show_ghosts` is off.
- **No interaction:** hunters ignore it, and its footsteps make no noise. It can't use, drop, pick up, open, hide, revive or trigger anything; no prompt shows. Its hotbar waits for a revive.
- **Follow:** [F] puts the camera over a living teammate's shoulder (a separate camera, while the body stays put). [LEFT]/[RIGHT] choose who, and [F] again returns to the ghost. The map and waypoints keep working.
- **Revive:** a revive ([REVIVE.md](REVIVE.md)) stands the runner up at the revive spot.
- **Anti-cheat:** GuestGuard checks ghosts like runners ([ANTI_CHEAT.md](ANTI_CHEAT.md)).
- **Free camera:** only the admin noclip.

## Controls

| Key | Action |
| --- | --- |
| E | follow the next living runner |
| Q | follow the previous living runner |
| F | free camera |

The `SPECTATING // NAME` strip (`game/hud/spectator_banner.gd`) uses the shared HUD palette.

## Code

- `InfiniteRouteTest._begin_spectating`, `_end_spectating`, `_cycle_spectate_target`, `_update_spectating` (also the party-wipe check).
- `PlayerController3D.spectator_follow_valid` / `spectator_follow_at` drive the follow cam.
- `RemotePlayers` publishes `spectating`; target filtering already skips `game_over`.
- `GameState.game_over` is cleared on respawn (it used to stay set after a host respawn).

## Tests

`tools/build/coop_test.sh` covers guest-dies-while-host-lives, host-dies-while-guest-lives (session and simulation continue), party wipe, and revive. `tools/build/public_test.sh` covers authority-spectates-while-guest-lives and the reverse.
