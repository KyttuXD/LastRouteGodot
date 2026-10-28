# Carnival booths

The carnival district's game stalls are playable: walk up, interact, play a 10-30 second first-person game, win a small prize, and the booth rests. They are loud, so they are a risk. Generic carnival wording only: no lore text on signs.

## Booths

| Prop | Game | Controls | Prize | Noise |
|---|---|---|---|---|
| `ringTossStall` | RING TOSS: five necks on a turning disc, three rings, two on to win | aim (look), throw (`tool_use`) | battery | quiet |
| `strengthTester` | STRENGTH TESTER: hold to wind up, release on a high meter, ring the bell at 92% | hold / release `tool_use` | relay hint (where the nearest unsecured relay is) | the bell is the loudest thing in the carnival |

| `prizeClawMachine` | CLAW MACHINE: steer the claw (`move_*`), drop it (`tool_use`), a grip that is a chance; two drops, one prize wins | tool (lockpick or crowbar) | quiet motor |
| `shootingGallery` | SHOOTING GALLERY: two rails of flip-up tin targets, eight shots, four hits win | aim, `tool_use` | tool | LOUD |
| `whackAMole` | WHACK-A-MOLE: six holes, 20 s, six whacks win | aim, `tool_use` | battery | medium |
| `duckPond` | DUCK POND: hook the marked duck as the ducks circle; five hooks, two caught wins | aim, `tool_use` | battery | quiet |

Placement: a 21-wide midway has ring toss, shooting gallery and whack-a-mole along the back wall, the claw machine beside the ticket booth and a strength tester at each end; the big top's centre is the duck pond. The shooting gallery and whack-a-mole reuse the ring-toss stall model and the duck pond the circus pedestal (their game boards are the booth node's); the props lane can give them their own models. The table is `CarnivalBooths.BOOTHS` (`src/game/carnival/carnival_booths.gd`): game, length, cooldowns, noise per event, prize.

## How it works

- **Rules** are pure and steppable: `CarnivalGame` subclasses in `src/game/carnival/`. The validators play them with bots (a good bot wins, a careless or idle one does not, a seed gives the same game).
- **The booth node** `CarnivalBooth3D` (`src/game_3d/carnival_booth_3d.gd`) sits at the prop: a chase of bulbs round the roof (dim and red while resting, flashing on a win), and while a game runs a pop-up **game board** between the booth and the player (turning disc and rings, the tower, puck and bell). It builds the overlay (title, time, instruction), reads the input, plays the sounds and makes the noise (`Sound.carnival`, `PlayerController3D.emit_noise_burst`). The board does not depend on the prop model's orientation.
- **Input** is the normal action set, so touch and XR work through the CITY/XR lane's actions: look to aim, `tool_use` to fire or hold, `move_*` for the claw, `interact` / `pause` to leave. While playing, `PlayerController3D.movement_locked` stops walking, sprinting, jumping and tool swings; looking stays free.
- **Host authority** (`infinite_route_test.gd`, `_request_booth` / `_accept_booth` / `_apply_booth_event`): the booth id is `cx:cy:cz:propType:cellX:cellY`; the host re-derives the booth from the generated chunk (an invented id does nothing), checks the player is at it, lets one player at a time play, then judges the result the player reports (a time and a score the game can reach, else it counts as a cancelled game: a 10 s rest, no prize). A win rests the booth for the long cooldown and pays; a loss for the short one. The host frees a booth whose player left (length + 12 s). Events: `stream_booth` (`start`, `finish`), relayed like doors and pickups.
- **Cooldown** is `StreamedWorldState.booth_ready_at` (booth id -> unix time ready; schema 6, older snapshots load with no booth rests), so it survives chunk unload, reconnects and late joiners.
- **Prizes**: battery and tool go to the winner's pockets if there is room (else "POCKETS FULL"); the relay hint is a message with the direction and distance.

## Validator

`carnival_booths`: data and rules for every booth, bots for every game, the world state through a snapshot, the booth node (prompt, board, movement lock, overlay, exactly one report, cancel, remote turn) and the route flow in a real generated carnival chunk (start, a second player turned away, an impossible result, the cooldown, a late joiner's snapshot, a winning result and its prize, a game left unfinished).
