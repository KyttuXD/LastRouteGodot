# Character models

## The player mannequin

Every player wears the same body. A runner is anonymous — the roster is the
hunters — so this is one shared mannequin rather than a model per player.

```bash
python3 tools/characters/build_mannequin.py \
    tools/characters/mannequin_skin.png \
    /tmp/mannequin.bbmodel \
    art/props-3d/characters/mannequin.glb
```

`art/props-3d/characters/player.tscn` instances the result, and
`PlayerController3D.BODY_MODEL_SCENE` points at that scene.

### Two things that will bite

**Export with `collision=False`.** `bbmodel_to_glb` emits a `-colonly` body per
mesh by default, which is right for a building and wrong for a body: twenty-one
static colliders parented to the player and moving with him fight the world's
own colliders and shove him out through the floor.

**The clip names are case-sensitive.** Godot asks for `idle`, `walk`, `chase`,
`sprint`, `crouch`; the Hytale sources ship `Idle`, `Walk`, `Run`, `Sprint`,
`Crouch`. `AnimationPlayer.has_animation()` just returns on a miss, so a
mismatch leaves a figure silently frozen rather than erroring. The script
renames them on the way in.

`scripts/validate_player.gd` checks both, plus that the model stands between
1.4 and 2.2 m — the capsule it replaced set the collision the world was built
around.
