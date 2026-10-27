# Rescue axe and held tools

Before/after (top row before, bottom row after; first person left, third person right): `docs/rescue_axe_before_after.png`.

## Held poses
`src/game_3d/held_item_poses.gd` is the one table for every held item: grip point in model space, first-person hand position/scale/yaw/pitch, third-person tilt, `REACH`
(how far ahead of the camera the model extends) and the swing profiles. Models are placed by their grip, which is the origin of the view / hand anchor, so swings pivot
around the handle. The first-person hand slides back (`viewmodel_push_for`) when a wall is closer than the model's reach; the remote hand anchor holds the axe/crowbar
upright and leaning forward, scale .29/.30.

## The axe's use
- **Cut free**: in a hunter's hold, a click (tool_use) with the axe in the inventory breaks the grab at once: 8 durability (a third of its life), the hunter is staggered twice as long, loud.
- **Cut a teammate free**: swing at a grabbed teammate within 3.4 m (`stream_axe_rescue`, host validates the axe, the grab and the distance, then tells the victim).
- **Chop boards**: two boards per chop (crowbar: one), repairs a safe room by 18 (crowbar 12).
- A committed chop costs 6 durability (24 = four chops), emits noise 18 for 0.9 s (sprint is 10.5), thud, debris and a light camera kick.
- A swing with nothing to work is a free whoosh: no durability, no noise, no deny blip. The axe is never required to progress.

Peers see swings through `tool_swing_seq/item/hit` in the movement state (one swing per counter bump; the first packet only adopts the counter).

## Checks
`rescue_axe` suite (held pose bounds at every FOV/aspect, wall push-back, grip placement, chop damage, durability, noise, guest swing) and `tools/look/held_items.tscn` captures.

Not done: the finite-game struggle (main_3d) has no axe break-free; the streamed route generates no boarded paths (boards exist in the finite maze only).
