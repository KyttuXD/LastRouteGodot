# Blocky hunter animation notes

Generators live in `tools/blocky_hunters/` (see its README); every one of the 41 models (A-Z, Void, `_tall` variants)
carries the same clip names on the same rig, built per hunter by `bb_rig.build_clips` from `hunters/motion.py`.

## Clips
`idle walk chase sprint crouch stun stun_recover charge flight jumpscare` (+ `emote_*`, Kathy `scythe_*`).
Loops end exactly where they start (`check_gaps.py` + the Godot validator check it); `stun_recover`, `scythe_swing`,
`scythe_stun_recover` and emotes are one-shots. `HunterView3D` plays the clip by state, the wake-up after a stun, and the
face from `BlockyFace` (stun / blank / chase / scream / derp / neutral+blink).

## Per-hunter stun (`stun.py`, `STYLE_OF` in `hunters/motion.py`)
Each hunter has her own `stun` / `stun_recover` from a style (every model is its own .glb, so no extra clip names):
topple (heavy, slow sideways fall: kathy jyvra solyth void_brown void_green), tumble (quick wobble/twist: eirys nyxie
opalie ravelle zephyra void_orange), float (lifts off, arms drift up, head back: glyra loxelle porcelle wynelle void_black
void_pink void_purple), stiff (rigid: ceryth mavrine thessine void_blue void_gray), cover (hugs herself, ears down: aki
quirith ysolde void_white), curl (crouched low, tail wrapped/tucked: haelith ilyra umbriel verrine), flop (arms and wings
flail: xivvy), shake (trembling: ferryn void_cyan void_red void_yellow), base (briselle dovelle). Styles also drive the
extra bones during the stun (wings flap, tails curl/tuck, ears droop, halos and hair wobble).

## Gait and life (bb_rig.py)
The shared Hytale walk/run clips were small shuffles. Now: chase/sprint/charge get a much longer stride, deeper knees,
harder arm pumping and a forward lean (chase 10 deg, sprint 16, charge ~18 with arms swept back); walk gets a longer stride;
`OVERLAYS` add breathing/weight shift to idle and torso counter-rotation, hip sway and head bob to the gaits.
`ground_fit` is a forward-kinematics pass that moves the Pelvis per key so the lowest foot is on the floor (slack above the
floor: walk 1.5 cm, chase 3, sprint 5, charge 4), which fixed floating/sinking feet.

## Audit tools
* `check_gaps.py` – wedge gaps at joints for every clip/profile, and loop seams.
* `fk_audit.py` – numeric audit from the .glb: foot floating/sinking, arms inside the torso, motion range, identical clips.
* `audit.py` – per-hunter contact sheets (rows = clips, columns = frames) from real Blender renders; `filmstrip.py` – one clip.
* `tools/look/hunter_check.tscn` – in game: `HUNTER_STATE=stun|search|scream|chase|walk HUNTERS=a,b,c`.

## Audit (this pass: all 41 hunters x all clips, sheets looked at + fk_audit)
| Finding | Hunters / clips | Fix |
|---|---|---|
| stun was one shared mild wobble (basically invisible) | all | authored per-hunter stun + wake, stars + face in `HunterView3D` |
| walk / chase / sprint were small shuffles, chase looked like walk | all | bigger stride, knees, arm pump, lean, torso counter-rotation |
| feet floated 6-11 cm in walk/chase/sprint/charge | all Voids, xivvy, solyth, eirys, haelith, jyvra, nyxie, ravelle | `ground_fit` |
| feet sank 6-26 cm in crouch and stun | most hunters (worst xivvy, opalie, zephyra, ravelle) | `ground_fit` |
| idle barely moved (idle looked frozen) | all (worst void_gray, mavrine, ceryth) | breathing/weight-shift overlay, Void idle_amp up |
| `charge` was the sprint plus a slight lean | loxelle (the charger) and all | own bull-rush pose: lean, head up, arms swept back |
| Void models overshot the 200 KB glb budget after the new clips | void_blue cyan orange white | glb writer shares key-time accessors (~25% smaller) |
| arm/hand inside torso | none found (fk_audit) | - |
| extras not following the body (hair, tails, ears, wings, halos) | none stuck; they sway in every clip, stun styles drive them harder | - |
| Remaining limits | flight is a Xivvy-only pose (arms out, wings flap, bob); Void expressions are eye-shape only (lore: no mouth) | - |

## Player mannequin (not a hunter)
`python3 tools/blocky_hunters/build.py player_mannequin` -> `assets/hunters_blocky/player_mannequin/player_mannequin.glb`
(+ `.tscn`, atlas, `.bbmodel`). The wooden mannequin skin (`skins/player_mannequin_source.png`, a standard 64x64 skin, copy of
`LastRoute-3D-refs/mannequin-skin-player.png`) on classic 4 px-arm proportions (`bb_skin.vanilla_cubes(arm_w=4)`), same bone
names / hierarchy / rest pose as the hunters, 1.78 m, both skin layers, 64x64 atlas, no expression cells. Clips (`player_clips.py`):
idle walk chase sprint crouch stun (loops), stun_recover jump (one-shot), sit lay tpose fall climb (loops). `lay` is face-up with the
head toward +Z. Validator: `_check_player_mannequin`; `check_gaps.py` covers it too. Views: `docs/player_mannequin_views.png`,
clips: `docs/player_mannequin_clips.png` (rows idle walk chase sprint crouch stun sit lay tpose jump fall climb).
