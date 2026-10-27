# Spectators (private rooms and the public route)

A caught runner stops playing but never ends the session for anyone else.

- **Guest caught** (private room): becomes a spectator and reports `caught` to the host. The host keeps playing.
- **Host caught while a guest lives**: the host spectates too. It stays the authority: hunters keep being simulated and broadcast, and the room stays open. Host disconnect still uses the existing host-migration / room-close path.
- **Everyone down** (host already spectating and the last living guest falls, or the last guest leaves): the host sees the RUN OVER report. Restarting the run revives every spectating guest at the checkpoint (`revive` player event).
- **Public route**: caught players spectate for a few seconds and rejoin on their own (grace period). The authority can spectate without dropping the route.
- **Solo**: unchanged, normal game over.

Spectators are published with `spectating: true` and `game_over: true`, so hunters never target them, door/objective logic ignores them, and their body is hidden (`visible: false`).

## Controls

| Key | Action |
| --- | --- |
| E | follow the next living runner |
| Q | follow the previous living runner |
| F | free camera |

The `SPECTATING // NAME` strip (`src/ui/spectator_banner.gd`) uses the shared HUD palette.

## Code

- `InfiniteRouteTest._begin_spectating`, `_end_spectating`, `_cycle_spectate_target`, `_update_spectating` (also the party-wipe check).
- `PlayerController3D.spectator_follow_valid` / `spectator_follow_at` drive the follow cam.
- `RemotePlayers` publishes `spectating`; target filtering already skips `game_over`.
- `GameState.game_over` is cleared on respawn (it used to stay set after a host respawn).

## Tests

`scripts/coop_test.sh` covers guest-dies-while-host-lives, host-dies-while-guest-lives (session and simulation continue), party wipe, and revive. `scripts/public_test.sh` covers authority-spectates-while-guest-lives and the reverse.
