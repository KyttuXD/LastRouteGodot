"""Build blocky hunters: python3 tools/blocky_hunters/build.py kathy [aki xivvy]

Writes assets/hunters_blocky/<name>/<name>.glb, <name>_atlas.png, <name>.bbmodel and the Godot
import sidecar. Needs only Pillow + numpy."""
import sys, pathlib, importlib
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from bb_core import Model
import bb_rig, bb_gltf

REPO = HERE.parent.parent
OUT = REPO / "assets" / "hunters_blocky"


def _generic(name):
    """A hunter with no module of her own: plain supplied skin on the standard cubes."""
    import types
    from bb_skin import U, vanilla_sk, eye_locators, source_hunter
    from hunters import pony
    ns = types.SimpleNamespace(NAME=name, HEIGHT=1.78, DESIGN_TOP=32 * U, SK=vanilla_sk(),
                               EXTRAS=pony.EXTRAS if name in pony.HAIRY else [], EYES=eye_locators(), MODEL_KW={})
    ns.build = lambda: source_hunter(name, vars(ns), pony.apply if name in pony.HAIRY else None)
    return ns


EMOTES_JSON = OUT / "emotes.json"


def _record_emotes(name, meta):
    """assets/hunters_blocky/emotes.json: hunter id -> its emote clips (label, face) for BlockyEmotes."""
    import json
    table = json.loads(EMOTES_JSON.read_text()) if EMOTES_JSON.exists() else {}
    table[name] = meta
    OUT.mkdir(parents=True, exist_ok=True)
    EMOTES_JSON.write_text(json.dumps(dict(sorted(table.items())), indent=1))


def build(name):
    if name.startswith("void_"):                      # the 12 Void hunters: hunters/void_set.py
        from hunters import void_set
        mod = void_set.module(name)
    else:
        try:
            mod = importlib.import_module(f"hunters.{name}")
        except ModuleNotFoundError:
            mod = _generic(name)
    cubes, face = mod.build()
    sk, eyes, extras = mod.SK, mod.EYES, list(mod.EXTRAS)
    extra_bones = {e[0] for e in extras}          # horns, ears, tails, wings do not count towards the height
    top = max(c.hi[1] for c in cubes if c.bone not in extra_bones)
    bones = bb_rig.skeleton(sk, extras)
    extra = getattr(mod, "MODEL_KW", {})
    model = Model(name, bones, cubes, scale=mod.HEIGHT / top, face_painter=face,
                  extras={"eyes": eyes}, **extra)
    from hunters import motion, emotes as emote_lib
    pel = next(x for x in bones if x["name"] == "Pelvis")["pivot"]
    from bb_skin import U as SKIN_U
    if hasattr(mod, "emissive"):                       # glowing texels (Void eyes): glTF emissiveTexture
        model.emissive = mod.emissive(model.atlas.img)
    if getattr(mod, "PLAYER", False):                  # the player mannequin: its own clip set, no emotes
        import player_clips
        clips = player_clips.build(bones, sk["hip_y"], motion.profile(name))
    else:
        emote_clips, emote_meta = emote_lib.compile_emotes(name, {x["name"]: x["rot"] for x in bones}, pel, SKIN_U,
                                                           sk["hip_y"] / bb_rig.HYTALE_PELVIS_Y, bb_rig.CORE_NAMES)
        new_clips, new_meta = emote_lib.compile_new(name, {x["name"]: x["rot"] for x in bones}, pel, SKIN_U,
                                                    sk["hip_y"] / bb_rig.HYTALE_PELVIS_Y, bb_rig.CORE_NAMES)
        emote_clips.update(new_clips)
        clips = bb_rig.build_clips(bones, sk["hip_y"], motion.profile(name), emote_clips)
        moving_meta = emote_lib.compile_moving(name, clips, {x["name"]: x["rot"] for x in bones})
        clips_have = {m["clip"] for m in new_meta + moving_meta}
        emote_meta = [m for m in emote_meta if m["clip"] not in clips_have] + new_meta + moving_meta
        if name.startswith("void_pink"):                   # her beckon was static; the moving one replaced it in the clip set
            emote_meta = [m for i, m in enumerate(emote_meta) if m["clip"] != "emote_beckon" or m in moving_meta]
        _record_emotes(name, emote_meta)
    hook = getattr(mod, "CLIP_HOOK", None)             # hunter-specific extra clips (Kathy's scythe set)
    if hook:
        hook(clips, {x["name"]: x["rot"] for x in bones}, pel, SKIN_U)
    if not getattr(mod, "PLAYER", False):
        import hairsim                                    # hair / tail chains: baked spring-damper follow with collision (hairsim.py)
        hairsim.simulate(model, bones, clips, model.scale, sway=bb_rig.SWAY_SCALE * float(motion.profile(name).get("sway", 1.0)), verbose=True)
        import clearance                                  # swaying parts must not pass through the body (clearance.py)
        clearance.solve(model, bones, clips, model.scale, verbose=True)
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    size = bb_gltf.write_glb(model, bones, clips, d / f"{name}.glb", scale=model.scale)
    model.atlas.img.save(d / f"{name}_atlas.png")
    if getattr(model, "emissive", None) is not None:
        model.emissive.save(d / f"{name}_emissive.png")
    bb_gltf.write_bbmodel(model, bones, d / f"{name}.bbmodel")
    if getattr(mod, "PLAYER", False):                  # a ready-to-instance scene (player_mannequin.tscn)
        (d / f"{name}.tscn").write_text(
            '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://assets/hunters_blocky/%s/%s.glb" id="1_model"]\n\n'
            '; The player body on the blocky hunter rig (tools/blocky_hunters, hunters/player_mannequin.py). Clips: idle walk chase\n'
            '; sprint crouch stun stun_recover sit lay tpose jump fall climb. Not wired into PlayerModels yet.\n'
            '[node name="Player" type="Node3D"]\n\n[node name="Model" parent="." instance=ExtResource("1_model")]\n' % (name, name))
    print(f"{name}: {model.triangle_count()} tris, {len(cubes)} cubes, glb {size/1024:.1f} KB, scale {model.scale:.3f}")
    return model


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["all"]:
        from hunters.roster import IDS
        args = IDS
    elif args == ["void"]:
        from hunters.void_set import IDS
        args = IDS
    for n in args or ["kathy"]:
        build(n)
