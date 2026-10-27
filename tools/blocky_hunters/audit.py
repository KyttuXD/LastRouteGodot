"""Per-hunter clip audit sheets: rows = clips, columns = frames across the clip, from real Blender renders.

  python3 tools/blocky_hunters/audit.py OUTDIR [hunter ...] [--clips=a,b] [--frames=6] [--view=threeq]

One Blender run per (hunter, clip) renders all frames; sheets land in OUTDIR/<hunter>.png."""
import os, struct, json, subprocess, sys, tempfile, shutil, glob
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
ONE_SHOT = ("stun_recover", "scythe_swing", "scythe_stun_recover")


def lengths(glb):
    with open(glb, "rb") as f:
        f.read(12)
        n, _ = struct.unpack("<II", f.read(8))
        g = json.loads(f.read(n))
    return {a["name"].replace("-loop", ""): max(g["accessors"][s["input"]]["max"][0] for s in a["samplers"])
            for a in g.get("animations", [])}


def render(h, clip, length, frames, view, tmp, attach=None):
    env = dict(os.environ, FRAME_Y="-0.1,2.2" if h.startswith("void") else "-0.1,2.0")
    loop = clip not in ONE_SHOT and not clip.startswith("emote")
    ts = [length * i / (frames if loop else frames - 1) for i in range(frames)]
    env["TIMES"] = ",".join("%.4f" % t for t in ts)
    if attach:
        env["ATTACH"] = attach
    d = f"{tmp}/{h}_{clip}"
    subprocess.run([BLENDER, "--background", "--python", f"{ROOT}/tools/blocky_hunters/render_blender.py", "--", d, clip,
                    "0", h, view], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return [f"{d}/{h}_{clip}_{view}_t{i}.png" for i in range(frames)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opt = dict(a[2:].split("=") for a in sys.argv[1:] if a.startswith("--"))
    out, hunters = args[0], args[1:]
    frames, view = int(opt.get("frames", 6)), opt.get("view", "threeq")
    os.makedirs(out, exist_ok=True)
    if not hunters:
        hunters = sorted(os.path.basename(p[:-1]) for p in glob.glob(f"{ROOT}/assets/hunters_blocky/*/")
                         if not p[:-1].endswith("_tall"))
    tmp = tempfile.mkdtemp()
    for h in hunters:
        ln = lengths(f"{ROOT}/assets/hunters_blocky/{h}/{h}.glb")
        default = ["idle", "walk", "chase", "sprint", "crouch", "stun", "stun_recover", "charge", "flight"]
        if h.startswith("kathy"):
            default += ["scythe_idle", "scythe_walk", "scythe_swing", "scythe_stun"]
        clips = opt["clips"].split(",") if "clips" in opt else default
        attach = f"{h}:R-HandProp:{ROOT}/assets/props_3d/kathy_scythe.glb" if h == "kathy" else None
        with ThreadPoolExecutor(4) as ex:
            res = list(ex.map(lambda c: render(h, c, ln[c], frames, view, tmp, attach if c.startswith("scythe") else None), clips))
        w = 900 // 3
        sheet = None
        for r, files in enumerate(res):
            for c, f in enumerate(files):
                if not os.path.exists(f):
                    continue
                im = Image.open(f).convert("RGB")
                im = im.resize((im.width // 3, im.height // 3))
                if sheet is None:
                    sheet = Image.new("RGB", (im.width * frames, im.height * len(clips)), (50, 50, 50))
                sheet.paste(im, (c * im.width, r * im.height))
        if sheet:
            sheet.save(f"{out}/{h}.png")
            print(h, sheet.size)
    shutil.rmtree(tmp)


main()
