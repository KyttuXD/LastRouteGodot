# Blocky hunter animation notes

Generators live in `tools/blocky_hunters/` (see its README); every one of the 41 models (A-Z and Void; the `_tall` variants were removed)
carries the same clip names on the same rig, built per hunter by `bb_rig.build_clips` from `hunters/motion.py`.

## Clips
`idle walk chase sprint crouch stun stun_recover charge flight jumpscare` (+ `emote_*`, Kathy `scythe_*`).
Loops end exactly where they start (`check_gaps.py` + the Godot validator check it); `stun_recover`, `scythe_swing`,
`scythe_stun_recover` and emotes are one-shots. `HunterView3D` plays the clip by state, the wake-up after a stun, and the
face from `BlockyFace` (stun / blank / chase / scream / derp / neutral+blink).

## Per-hunter stun (`stun.py`, `STYLE_OF` in `hunters/motion.py`)
Each hunter has her own `stun` / `stun_recover` from a style (every model is its own .glb, so no extra clip names):
topple (heavy, slow sideways fall: kathy javelle solyth void_brown void_green), tumble (quick wobble/twist: elise nyxie
opalie ravelle zellia void_orange), float (lifts off, arms drift up, head back: glyra loxelle porcelle wynelle void_black
void_pink void_purple), stiff (rigid: ceryth mavrine thessine void_blue void_gray), cover (hugs herself, ears down: aki
quenelle ysolde void_white), curl (crouched low, tail wrapped/tucked: haelith ilyra umbriel verrine), flop (arms and wings
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
* `dev/look/hunter_check.tscn` – in game: `HUNTER_STATE=stun|search|scream|chase|walk HUNTERS=a,b,c`.

## Audit (this pass: all 41 hunters x all clips, sheets looked at + fk_audit)
| Finding | Hunters / clips | Fix |
|---|---|---|
| stun was one shared mild wobble (basically invisible) | all | authored per-hunter stun + wake, stars + face in `HunterView3D` |
| walk / chase / sprint were small shuffles, chase looked like walk | all | bigger stride, knees, arm pump, lean, torso counter-rotation |
| feet floated 6-11 cm in walk/chase/sprint/charge | all Voids, xivvy, solyth, elise, haelith, javelle, nyxie, ravelle | `ground_fit` |
| feet sank 6-26 cm in crouch and stun | most hunters (worst xivvy, opalie, zellia, ravelle) | `ground_fit` |
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
head toward +Z. Validator: `_check_player_mannequin`; `check_gaps.py` covers it too. Views: `docs/images/player_mannequin_views.png`,
clips: `docs/images/player_mannequin_clips.png` (rows idle walk chase sprint crouch stun sit lay tpose jump fall climb).

## Hunter emote clips (docs/HUNTER_EMOTES.md)
Every non-Void hunter carries the 12 catalog clips `emote_<id>` plus the shared wave/shrug/cheer/bow and her
personal ones; `emotes.json` lists them with the catalog face. Built in `hunters/emotes.py` (`NEW_TEMPLATES`, `MOVING_TEMPLATES`):
* Static one-shots (laugh, look_around, smug, dance, flinch, stretch, yawn, hum, victory) start and end at the idle pose.
* **Moving** emotes (taunt, point, beckon) are layered on the hunter's own `sprint` clip: legs, pelvis and extra bones keep the stride,
  only head/chest/one arm are overridden, blended in and out so the clip starts and ends on the run. Kathy uses her LEFT hand (the
  scythe is in the right). Void: only void_pink's beckon (built the same way); the rest use their shared stand-ins.
* Persona: `ENERGY` scales every gesture (Aki .65 ... Xivvy 1.4); variants: glyra waltz dance, xivvy hop dance, haelith/opalie/ravelle
  the older bouncy dance, opalie/ravelle/xivvy/zellia the older bouncy laugh; smug is arms-crossed for kathy mavrine ceryth thessine
  javelle briselle ilyra verrine and hands-behind-the-back for the rest; glyra hums bigger. Extra bones (ears, tails, wings, hair) sway
  in every emote automatically.
* `check_gaps.py` now also checks every emote (and `--all` lists each pose over the plug limit); a few existing emotes (bow, smash,
  tilt) were over it and were trimmed. Validator: `_check_catalog_emotes` (clips present, one-shot, catalog length/face, moving ones keep leg tracks).

## Mesh LODs (hands vanish, stripes smear)

The glb imports must keep `meshes/generate_lods=false`. With generated LODs on, a viewport with a high LOD threshold (low-res or
scaled 3D, as in the game) decimates the cube meshes: hands/forearms disappear, wolf-ear tips are cut and striped socks turn into
flat blocks. It looked like a UV bug. Repro: `HUNTERS=verrine HUNTER_STATE=walk CAM_DIST=8 LOD=3000 godot --path . res://dev/look/hunter_check.tscn -- out.png`
(`LOD=` sets `Viewport.mesh_lod_threshold`, `CAM_YAW=` orbits the camera). `validate blocky` fails if any import turns LODs on again.
