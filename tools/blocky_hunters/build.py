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


def taller(cubes, sk, eyes, dy):
    """Make a vanilla-proportioned hunter taller: legs stretch (texture rows stay, texels grow), everything
    above the hips moves up by dy skin pixels. UVs are untouched, so the skin stays a normal skin."""
    from bb_skin import U
    d = dy * U
    ank = 2 * U

    def leg(y):                       # 0..2 px stays (shoe), 2..12 px stretches to 2..12+dy
        return y if y <= ank else ank + (y - ank) * (10 * U + d) / (10 * U)

    def f(y):
        return leg(y) if y <= 12 * U + 1e-9 else y + d
    for c in cubes:
        lo, hi = list(c.lo), list(c.hi)
        lo[1], hi[1] = f(lo[1]), f(hi[1])          # f is continuous at the hips, so seams and overlays follow
        c.lo, c.hi = tuple(lo), tuple(hi)
        if c.pivot is not None:
            c.pivot = (c.pivot[0], f(c.pivot[1]), c.pivot[2])
    sk = {k: (f(v) if k in ("knee_y", "ankle_y") else v + d) if k.endswith("_y") else v for k, v in sk.items()}
    eyes = {k: (v[0], v[1] + d, v[2]) for k, v in eyes.items()}
    return cubes, sk, eyes, f


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


def build(name, tall=0.0):
    try:
        mod = importlib.import_module(f"hunters.{name}")
    except ModuleNotFoundError:
        mod = _generic(name)
    cubes, face = mod.build()
    sk, eyes, extras = mod.SK, mod.EYES, list(mod.EXTRAS)
    if tall:
        cubes, sk, eyes, f = taller(cubes, sk, eyes, tall)
        extras = [(n, par, (pv[0], f(pv[1]), pv[2]), sw) for n, par, pv, sw in extras]
        name = f"{name}_tall"
    extra_bones = {e[0] for e in extras}          # horns, ears, tails, wings do not count towards the height
    top = max(c.hi[1] for c in cubes if c.bone not in extra_bones)
    bones = bb_rig.skeleton(sk, extras)
    extra = getattr(mod, "MODEL_KW", {})
    model = Model(name, bones, cubes, scale=mod.HEIGHT / top, face_painter=face,
                  extras={"eyes": eyes}, **extra)
    from hunters import motion, emotes as emote_lib
    pel = next(x for x in bones if x["name"] == "Pelvis")["pivot"]
    from bb_skin import U as SKIN_U
    emote_clips, emote_meta = emote_lib.compile_emotes(name, {x["name"]: x["rot"] for x in bones}, pel, SKIN_U,
                                                       sk["hip_y"] / bb_rig.HYTALE_PELVIS_Y, bb_rig.CORE_NAMES)
    clips = bb_rig.build_clips(bones, sk["hip_y"], motion.profile(name), emote_clips)
    _record_emotes(name, emote_meta)
    hook = getattr(mod, "CLIP_HOOK", None)             # hunter-specific extra clips (Kathy's scythe set)
    if hook:
        hook(clips, {x["name"]: x["rot"] for x in bones}, pel, SKIN_U)
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    size = bb_gltf.write_glb(model, bones, clips, d / f"{name}.glb", scale=model.scale)
    model.atlas.img.save(d / f"{name}_atlas.png")
    bb_gltf.write_bbmodel(model, bones, d / f"{name}.bbmodel")
    print(f"{name}: {model.triangle_count()} tris, {len(cubes)} cubes, glb {size/1024:.1f} KB, scale {model.scale:.3f}")
    return model


if __name__ == "__main__":
    args = sys.argv[1:]
    tall = 0.0
    for a in list(args):
        if a.startswith("--tall"):
            tall = float(a.split("=")[1]) if "=" in a else 5.0
            args.remove(a)
    if args == ["all"]:
        from hunters.roster import IDS
        args = IDS
    for n in args or ["kathy"]:
        build(n, tall)
