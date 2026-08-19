# Character model pipeline

The reviewed `.bbmodel` files committed in `art/props-3d/characters/` are the
editable source of truth. Each embeds its texture, opens directly in
Blockbench, and rebuilds without an uncommitted skin/template directory. The
PNG beside it is deliberately extracted from that embedded texture: Godot can
import it normally, and a reviewer can inspect the exact atlas the GLB uses.
Godot externalizes the imported GLB material to that atlas path, so the
`_0.png` files are runtime dependencies as well as review artifacts. The asset
audit intentionally keeps them in every PCK; excluding them produced missing
materials in a standalone-pack test.

`import_blockbench_hunters.py` is the normal path from reviewed Blockbench
source to the three committed runtime artifacts (`.bbmodel`, `_0.png`, `.glb`).
The older skin-to-rig builders remain useful when creating a hunter from a raw
Minecraft skin, but they are no longer the final authority over a reviewed
Blockbench edit.

## One pipeline now

The mannequin used to go through a separate from-scratch six-box exporter
(`mc_skin.py`), because the first attempt through the real Hytale rig came out
with its head, arms and legs standing apart with daylight between them. The
actual cause was a corrupted bone name in the shared converter at the time
(`Fofrontm` for `Forearm`, from a botched recovery after the toolchain was
lost and rebuilt), not a structural mismatch between a 64×64 skin's six UV
islands and the rig's ~21 parts. With that fixed, the mannequin goes through
the exact same pipeline the hunters do — one converter, one rig, one set of
rules, checked by the same cohesion pass (`scripts/validate_body.gd`) either
way. `mc_skin.py`/`mannequin_anim.py` are still here as a smaller,
dependency-free fallback (no Pillow, no Hytale asset library) if this rig ever
regresses again, but nothing calls them by default.

The one real difference left is **scale**: the mannequin's `.glb.import`
carries `nodes/root_scale=0.9`, every hunter's carries `1.1` — so a hunter
reads as visibly larger than the player without either model's own geometry
changing. Import-time, not exporter code, so it survives a rebuild without
needing to be re-applied.

## Void and KYTTU admin skins

`build_void_hunters.py` converts the supplied `Skins Void` Minecraft skins
through the same reviewed rig and export path. The twelve colour files become
`void_<colour>` hunter sources/runtime scenes at a 1.22 display scale. `Main.png`
is explicitly reserved and becomes `admin_kyttu`, a 0.90-scale player model;
the builder never includes it in the Void hunter list. The committed external
PNG is the converter's final packed 64×96 atlas, not the original 64×64 skin,
so Godot reimports and the embedded GLB sample identical UV rows. Rebuild only
the Void roster (leaving the admin model untouched) with:

```bash
.venv/bin/python tools/characters/build_void_hunters.py \
  "/var/home/kyttu/Documents/Skins Void" --void-only
```

Void models ship the six normal hunter clips. Xivvy additionally receives the
winged `flight` loop from `refine_hunter_animations.py`; Loxelle's authored
`charge` clip is maintained by `add_loxelle_charge_animation.py` before her
reviewed model is re-exported.

## Rebuilding the reviewed models

Re-export every committed hunter and the player from the repository itself:

```bash
python3 tools/characters/import_blockbench_hunters.py \
  art/props-3d/characters --include-void --include-player
```

To bring in a newly reviewed external set (the path is an explicit input, not
a hardcoded dependency):

```bash
python3 tools/characters/import_blockbench_hunters.py \
  "/path/to/reviewed/Hunters"
```

The importer rejects a missing roster entry, invalid embedded PNG, or a model
without all five gameplay clips. `--only Aki,Kathy` is available while
iterating. Then make Godot import and pose the real generated scenes:

Hunter locomotion is intentionally post-processed by
`refine_hunter_animations.py`; the player mannequin is not. Hunters receive a
2.4-second relaxed idle and a one-second walk. `sprint` and `chase` are exact
normalized copies of that walk at 0.67 and 0.50 seconds, respectively, so
faster gameplay never changes their gait or introduces a separate tilted run
pose. The reviewed hunter geometry faces north after its Blockbench turn, so
both rebuild paths also rotate every hunter animation delta from the old
south-facing basis; this is a front/back remap, not a left/right swap or an
all-axis inverse. The player does not receive that remap.

```bash
godot4 --headless --editor --quit --path .
godot4 --headless --path . res://scenes/validate.tscn -- body
```

For visual review with Blender:

```bash
blender --background --python tools/characters/render_character_gallery.py \
  -- --output /tmp/characters.png --animation idle --view threequarter
```

For an animation review sequence, preserving each clip's real authored
cadence:

```bash
blender --background --python tools/characters/render_animation_preview.py \
  -- --output-dir /tmp/animation-frames --models Player,Aki \
  --clips idle,walk,sprint,chase,crouch --view threequarter \
  --fps 30 --one-loop
```

The command produces labelled PNG frames suitable for a GIF or video encoder.
It accepts any comma-separated roster names, so a character-specific movement
review does not need a bespoke scene.

## Building from raw skins (legacy authoring path)

```bash
python3 -m venv .venv && .venv/bin/pip install Pillow
```

Hunters — every roster letter, or a few:

```bash
.venv/bin/python tools/characters/build_hunters.py --only D,K,W
```

The player mannequin:

```bash
.venv/bin/python tools/characters/build_mannequin.py tools/characters/mannequin_skin.png art/props-3d/characters/mannequin.bbmodel art/props-3d/characters/mannequin.glb
```

After using this path, run the reviewed-model importer above so its embedded
texture, PNG, GLB and validation all agree.

## The files

**Shared**

- `mc_to_hytale.py` — the big one. A 64×64 Minecraft skin onto the Hytale
  "Player" rig: per-face box UVs, slim-arm resampling, overlay shells where the
  second layer actually has pixels, skin-tone normalisation onto the roster's
  shared tone, and hair planes. Reads `test-base.bbmodel` as its template and
  never writes to it.
- `hytale_anim.py` — ports `.blockyanim` clips onto a converted model.
- `mc_hytale_map.py`, `build_uv_plan.py`, `hunter_detail.py`,
  `special_characters.py`, `clean_source_skins.py` — region tables, the UV
  packing plan, per-hunter detail passes, and skin cleanup.
- `build_all.py`, `build_<hunter>.py` — geometry only, one `.bbmodel` each.
  `build_hunters.py` is the wrapper that also attaches clips and exports glTF;
  the per-hunter scripts are still useful when iterating on one character.

- `build_mannequin.py` — the player wrapper, same shape as `build_hunters.py`
  minus the roster loop: one skin, one model, skin-tone normalisation skipped
  on purpose (it would drag a wooden mannequin toward the roster's flesh tone).

**Fallback, unused by default**

- `mc_skin.py` — a Minecraft skin to a six-box Blockbench model, stdlib only
  (it decodes PNG with `zlib` rather than pulling in Pillow). Vanilla
  proportions, vanilla UV origins, feet at y=0, 1.7 m tall.
- `mannequin_anim.py` — the five clips `ModelSlot` plays, hand-authored.
  Retargeting was not an option: the Hytale clips address Neck, Forearm, Calf
  and Eyelid, and a six-box figure has none of those bones.

## Rules the exporter enforces

These are all mistakes this project has actually made:

- **64 Blockbench units = 1 metre.** One Minecraft skin pixel is 3.4 units, so
  a 32-pixel figure stands 1.7 m — the height of the player's capsule.
- **`autouv` must stay 0**, or Blockbench regenerates the UVs when the file is
  opened and the careful mapping is gone.
- **Cube and face rotations are preserved.** Aki's four 5-degree skirt-panel
  rotations are the regression case: dropping cube rotation made their faces
  coplanar with the pelvis and caused z-fighting in Godot.
- **Materials retain authored alpha and render both sides.** Quirith and Eirys
  use transparent torso-overlay texels that become black boxes if the runtime
  forces their material opaque. Xivvy's wings are deliberately thin,
  single-face cards and disappear from the front when glTF backface culling is
  enabled. The exporter emits double-sided alpha-scissor materials and
  `ModelSlot.instantiate()` leaves those settings intact.
- **`collision=False` for anything a player wears.** A character's only
  collider is its `CharacterBody3D`'s own shape; exporting `-colonly` meshes
  gave the first mannequin twenty-one static bodies and dropped it through the
  floor.
- **Clip names are `idle`, `walk`, `sprint`, `chase`, `crouch`,** lowercase.
  `AnimationPlayer.has_animation` is case-sensitive, and a clip the game cannot
  find is a body that stands frozen while it slides around.
- **Blockbench loop flags survive a clean Godot import.** The glTF exporter
  uses Godot's recognized `-loop` source suffix; Godot strips the suffix back
  to the gameplay clip name and sets the imported animation's loop mode.
- **A declared loop duration is preserved even when its last authored key is
  earlier.** The exporter closes the un-keyed tail back to the opening pose;
  otherwise Godot trims the clip and visibly snaps at the wrap point.
- **Every rest pose stands on y=0.** `character_floor_lifts.py` stores the
  measured player and hunter root lifts needed by each clip so their soles do
  not pass through the floor. `validate_body.gd` samples every animation and
  checks both rest and posed bounds for the shipped player and hunter rigs.
