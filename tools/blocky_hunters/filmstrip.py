"""Clip filmstrips from real Blender renders: one row per clip, N frames evenly across the clip.

  python3 tools/blocky_hunters/filmstrip.py OUT.png HUNTER CLIP[,CLIP...] [frames=8] [view=threeq] [attach=prop.glb:node]

Frames are rendered with render_blender.py (one Blender run each) and joined into a sheet, so what you see is what the
.glb plays."""
import json, os, struct, subprocess, sys, tempfile, shutil
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")


def clip_lengths(glb):
    with open(glb, "rb") as f:
        f.read(12)
        n, _ = struct.unpack("<II", f.read(8))
        g = json.loads(f.read(n))
    out = {}
    for a in g.get("animations", []):
        mx = max(g["accessors"][s["input"]]["max"][0] for s in a["samplers"])
        out[a["name"].replace("-loop", "")] = mx
    return out


def main():
    out, hunter, clips = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
    frames = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    view = sys.argv[5] if len(sys.argv) > 5 else "threeq"
    attach = sys.argv[6] if len(sys.argv) > 6 else None
    glb = f"{ROOT}/assets/hunters_blocky/{hunter}/{hunter}.glb"
    lens = clip_lengths(glb)
    tmp = tempfile.mkdtemp()
    env = dict(os.environ)
    if attach:
        prop, node = attach.split(":")
        env["ATTACH"] = f"{hunter}:{node}:{os.path.abspath(prop)}"
    env.setdefault("FRAME_Y", "-0.1,2.0")
    rows = []
    for clip in clips:
        length = lens[clip]
        loop = clip in lens and not clip.startswith("emote") and clip not in ("stun_recover", "scythe_swing", "stun_recover")
        row = []
        for i in range(frames):
            t = length * i / (frames if loop else max(1, frames - 1))
            subprocess.run([BLENDER, "--background", "--python", f"{ROOT}/tools/blocky_hunters/render_blender.py", "--",
                            tmp, clip, f"{t:.4f}", hunter, view], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            im = Image.open(f"{tmp}/{hunter}_{clip}_{view}.png").convert("RGB")
            row.append(im.resize((im.width // 3, im.height // 3)))
        rows.append(row)
    w, h = rows[0][0].size
    sheet = Image.new("RGB", (w * frames, h * len(rows)))
    for r, row in enumerate(rows):
        for c, im in enumerate(row):
            sheet.paste(im, (c * w, r * h))
    sheet.save(out)
    shutil.rmtree(tmp)
    print(out, sheet.size)


main()
