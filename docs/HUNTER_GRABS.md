# Hunter grabs

KT: every hunter grabs a caught runner in a way that fits its personality and body, and a catch varies between a few styles.
One grab plays (about 1.9 s), then the death line and game over as before.

## Styles (`GrabStyles.STYLES`, poses in `GrabStyles.pose`)

| Style | What happens | Needs |
| --- | --- | --- |
| `neck_lift` (NL) | one hand at the throat, the runner raised until the feet leave the floor | ceiling 2.5 m |
| `shoulder_grab` (SG) | both hands on the shoulders, shaken | always fits (the fallback) |
| `tackle` (TK) | knocked flat on the back, the hunter on top | 1.7 m clear behind |
| `wrist_yank` (WY) | one wrist taken, the runner yanked in off balance | - |
| `wrap` (WR) | both arms close round the runner | - |
| `leg_grab` (LG) | an ankle taken from behind, the runner falls on their face and is dragged back | 1.6 m clear ahead |
| `upside_down` (UD) | a leg hoisted to the shoulder, the runner hangs head down; first person is inverted | ceiling 2.4 m |
| `bear_hug` (BH) | crushed in both arms and lifted | ceiling 2.3 m |
| `collar_drag` (CD) | pulled face down by the collar and dragged as the hunter backs off | 1.6 m clear behind the hunter |
| `wall_pin` (WP) | shoved back against a wall and held there | a wall within 1.3 m behind |
| `pounce_pin` (PP) | creature rigs only: pounced on and pinned on the back | 1.7 m clear behind |

## Pools (`res://data/grabs/<hunter_id>.json`, schema `lr.grab/1`)

- **Pool size and weights:** each hunter has a weighted pool of 2-4 styles. The main style always has the most weight.
- **Picking a style:**
  - On a catch, the host rolls `GrabStyles.roll_for(seed, peer, catch number)` and sends it as `grab_roll` with the capture event.
  - The caught runner probes the room (`HunterGrab.probe_room`): ceiling, floor behind them at chest and knee height, and floor behind the hunter.
  - It drops the styles that don't fit, then picks with the roll (`GrabStyles.pick`).
  - If nothing fits, it falls back to the shoulder grab (creature rigs fall back to the pounce).
- **File format:** strict, like `ContentRegistry`. Unknown keys, unknown styles and non-positive weights are errors.
- **Content packs:** packs can replace a pool with `GrabStyles.apply_defs` once the pack loader lists `grabs/<id>` overrides, following the `lr.pack/1` manifest pattern.

## Playing it (`HunterGrab`)

- **Local runner:** the body is moved where the grab puts it. The first-person eye follows the grabbed body's head: lifted, flat on the floor or upside down. A face-to-face hold looks up at the hunter's face.
- **Skinned hands:** set by `PlayerController3D.set_grab_view` (`GRAB_HAND_POSES`), from the same source as the ladder hands. Poses: gripping the arm, pushing, a held wrist, pinned, clawing at the floor, pushing up, or dangling.
- **Hunter body:** the hunter's model is leaned, lowered or moved (for example crouched for a leg grab, or on top for a tackle). Its arm bones go to the named body point (`GrabStyles.BODY_POINTS`). This happens after its clips have run, and is put back on release. The simulated hunter is untouched.
- **Co-op:** the runner's state carries `grab = [style, t, lift, body pitch, hunter forward, drop, lean]`.
  - `RemotePlayers` raises and tips the body from it.
  - It also bends the nearest hunter with `HunterGrab.pose_nearest_hunter`.
  - The host relays it like any other state, and the guard clamps every field.
- **VR:** a headset runner keeps their own tracked view. Others still see the grab.
- **Hooks:** `main_3d.gd` and `infinite_route_test.gd` call `_resolve_capture_outcome` before the (disabled) jumpscare and the death moment. `release()` runs on restart and respawn.

## Check and capture

- `grabs` suite: every A-Z, Void and creature id has a valid 2-4 style pool, with the main style weighted highest.
  - The six approved neck-lifters have NL as their main style. Void hunters never neck-lift. Creature-only styles stay on creature rigs.
  - The pick is repeatable, every pool style shows up, and the main style is the most common.
  - Low ceilings, walls and tight spots rule styles out, with the fallback when nothing fits.
- Then every style plays on the real route scene, and the suite checks:
  - lift or floor height, the inverted view, facing away for the leg grab, and the clip;
  - skinned, mirrored hands;
  - the hunter's hands on the right body point;
  - the state packet, and a guest's copy of the body taken the same way;
  - a clean release that puts the hunter's model back.
- Capture rig: `tools/look/grabs.tscn` gives each style mid-grab and at the hold in first person, then from the side as another player sees it.

![](hunter_grabs_sheet.png)
