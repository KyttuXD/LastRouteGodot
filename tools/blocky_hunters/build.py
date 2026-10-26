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


def build(name, tall=0.0):
    mod = importlib.import_module(f"hunters.{name}")
    cubes, face = mod.build()
    sk, eyes, extras = mod.SK, mod.EYES, list(mod.EXTRAS)
    if tall:
        cubes, sk, eyes, f = taller(cubes, sk, eyes, tall)
        extras = [(n, par, (pv[0], f(pv[1]), pv[2]), sw) for n, par, pv, sw in extras]
        name = f"{name}_tall"
    top = max(c.hi[1] for c in cubes)
    bones = bb_rig.skeleton(sk, extras)
    extra = getattr(mod, "MODEL_KW", {})
    model = Model(name, bones, cubes, scale=mod.HEIGHT / top, face_painter=face,
                  extras={"eyes": eyes}, **extra)
    clips = bb_rig.build_clips(bones, sk["hip_y"])
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
    for n in args or ["kathy"]:
        build(n, tall)
