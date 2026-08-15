# Character model pipeline

Everything in `art/props-3d/characters/` is a build product. This directory is
what builds it.

That is the point of it being here. An earlier version of this toolchain lived
in a scratch directory outside the repository; the directory was cleared, and
with it went the only way to rebuild any character model in the game. The
scripts were recovered from a session transcript and now live in version
control, where a build product's builder belongs. **Nothing here may import
from a path outside `tools/`.**

**The `.bbmodel` files are committed too**, next to each `.glb`, for the same
reason the toolchain itself is: they're what opens directly in Blockbench for
a hand look or a hand edit, texture (embedded as base64) included, with
nothing to run first. Editing one by hand and rerunning the pipeline will
overwrite it — the skin PNGs are still the actual source of truth — so treat a
hand edit here as a preview of a change to make upstream (the skin, or the
converter), not a permanent one.

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

## Building

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

Then re-import so Godot picks the new mesh up (this is also where a fresh
`.glb.import` gets `root_scale=1.0` again — reapply it, see above), and check:

```bash
godot4 --headless --path . --import
godot4 --headless --path . res://scenes/validate.tscn -- body
```

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
- **Cube-level rotation is dropped.** Only *group* rotation survives as a glTF
  node rotation. Anything that must be turned has to be turned as a group.
- **`collision=False` for anything a player wears.** A character's only
  collider is its `CharacterBody3D`'s own shape; exporting `-colonly` meshes
  gave the first mannequin twenty-one static bodies and dropped it through the
  floor.
- **Clip names are `idle`, `walk`, `sprint`, `chase`, `crouch`,** lowercase.
  `AnimationPlayer.has_animation` is case-sensitive, and a clip the game cannot
  find is a body that stands frozen while it slides around.
