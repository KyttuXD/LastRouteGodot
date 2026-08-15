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

## Two pipelines, on purpose

| | Hunters | Player mannequin |
|---|---|---|
| Entry point | `build_hunters.py` | `build_mannequin.py` |
| Rig | Hytale "Player" template, ~21 parts | six Minecraft boxes |
| Source | `~/Documents/Skins Yttu/<L>yttu.png` | `mannequin_skin.png` |
| Needs Pillow | yes | no |
| Needs the Hytale asset library | yes | no |

They are separate because the mannequin tried to be a hunter and it did not
work. A 64×64 Minecraft skin has exactly **six** UV islands; the Hytale rig has
twenty-one parts. Run one through the other and fifteen parts sample whatever
happens to lie under their coordinates — which is why the first mannequin
rendered as a uniform tan figure with its limbs scattered in the air. The
hunters get away with it because `mc_to_hytale.py` does real work to map a skin
onto that rig: repacking regions, building overlay shells, adding hair planes.
The mannequin does not need any of that. It needs to look like a person.

## Building

```bash
python3 -m venv .venv && .venv/bin/pip install Pillow   # hunters only
```

Hunters — every roster letter, or a few:

```bash
.venv/bin/python tools/characters/build_hunters.py --only D,K,W
```

The player mannequin — stdlib only, no venv:

```bash
python3 tools/characters/build_mannequin.py tools/characters/mannequin_skin.png art/props-3d/characters/mannequin.bbmodel art/props-3d/characters/mannequin.glb
```

Then re-import so Godot picks the new mesh up, and check it:

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

**Mannequin only**

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
