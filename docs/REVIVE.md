# Revive Kit, Stim Pack and item stacks

KT approved these on 2026-10-28. The numbers live in `GameConfig` (`REVIVE_*`, `STIM_*`). The stack sizes live in
`PlayerController3D.STACK_MAX`.

## Stacks

| item | per slot |
|---|---|
| battery | 5 |
| Stim Pack | 3 |
| Revive Kit | 2 |
| tools (flashlight, taser, lockpick, crowbar, rescue axe) | 1 |

- **Where the count lives:** in the slot's existing `inventory_slot_durability` entry. A battery stored 0 there
  before stacks existed, so a count reads as `max(1, value)`. Old saves load as stacks of one, and neither the save
  format nor the snapshot format changes.
- **Picking up:** a pickup merges into the first matching stack that has room, then goes to empty slots. It is all
  or nothing: a dropped stack of 3 needs room for all 3 (`PlayerController3D.can_accept_item`).
- **Using:** using one item takes one off the stack. A battery recharge uses one battery.
- **Dropping:** tapping the drop key drops one. Holding it for `DROP_STACK_HOLD` (0.5 s) drops the whole stack. The
  dropped record's `durability` is the count.
- **HUD:** a slot holding 2 or more shows a count badge, "xN" (`HUD._apply_stack_badge`).
- **Host checks:** pickup and drop claims go through `_target_can_take`, which uses the runner's reported inventory.
  A guest slot reported above the cap is a GuestGuard strike (reason `stack`).

## Stim Pack

- **Using it:** while the stim is in your hand, `tool_use` starts a 0.6 s injection. The stim is used up only when
  the injection lands; a grab or a stun cuts it off and nothing is used.
- **Boost:** stamina goes to full. For 6 s, sprint speed is ×1.2 and sprint drain is ×0.5.
- **Crash:** for the 10 s after the boost, stamina regen is ×0.5. A heartbeat plays every 0.8 s and makes noise 3.0,
  which nearby hunters hear. If you are in a locker during the crash, a hunter walking past is twice as likely to
  look in (HunterInspect).
- **Limits:** you can't take another stim until the crash is over. Spectating clears both the boost and the crash.
- **Sync:** `stim_boost` and `stim_crash` replicate in the player state.
- **GuestGuard:** the boost raises a guest's allowed speed only when a sample reports `stim_boost` and also carries
  one stim fewer than the sample before. The window lasts for the boost plus 1 s, and the unbroken-sprint clock
  restarts, because the stim refilled the tank.

## Revive Kit

- **Spawning:** Stim Packs (18% per chunk) and Revive Kits (6% per chunk in co-op, 3% solo) roll from their own
  seeded stream after every other pickup, on cells left over. No older pickup moves.
- **Co-op (private rooms; the public route keeps its own rejoin):**
  - The host opens a 90 s window at the spot where a runner was caught (`ReviveDowns` in
    `StreamedWorldState.downs`, carried in the world snapshot).
  - Every other peer sees a `RouteInteractable3D.Kind.REVIVE_SPOT` marker there: a ring, a light column, and the
    runner's name with a countdown, drawn through walls.
  - A teammate carrying a kit sees "HOLD [E] REVIVE NAME". Without a kit the marker says the runner needs one.
- **The hold:** takes 3 s. It breaks if the reviver sprints, moves 0.5 m from where they started, or is grabbed or
  stunned. While it runs, the reviver makes noise 6.
- **Host checks:** the host times the hold from the start request. On the finish it checks the kit, the floor, the
  range (1.6 m plus 0.6 m of slack), the window, and that the downed runner is still spectating.
- **Result:** the reviver uses up one kit. The revived runner comes back at the spot with 25 stamina and 3.5 s of
  grace. `revive_at` is a host move, so GuestGuard lets the jump pass.
- **Spectator lines:** "NAME IS REVIVING YOU", "A TEAMMATE HAS A REVIVE KIT", "WAITING FOR A REVIVE KIT", and when
  the window closes, "REVIVE WINDOW CLOSED".
- **Restarts:** a run restart (the party-wipe revive) clears every window.
- **Solo:** the kit is a second wind. On a struggle catch it is used up automatically, the hold breaks the way the
  rescue axe's cut-free does (her stagger is doubled), and 3.5 s of grace follows. Void and other inescapable grabs
  never reach the struggle, so the kit can't save you from those.

## Models

`tools/props/rebuild_hytale_props.py` (`make_revive_kit`, `make_stim_pack`) builds both models with the same pixel-atlas
pipeline as the other tools, and also builds the hotbar icons.

- **Revive Kit:** a charcoal hard case with a hi-vis orange lid, defib paddles clipped on top, a white pulse-line
  emblem and a green charge lamp. There is deliberately no red cross, because that emblem is legally protected.
- **Stim Pack:** a chunky autoinjector with a yellow plunger and safety cap, a ribbed grip and a cyan dose window. Its
  floor pickup is drawn ×1.3.

## Validators

`item_stacks`, `stim`, `revive` (`scripts/validate_*.gd`).
