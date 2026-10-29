#!/usr/bin/env python3
"""Generates the original art and sound for the example packs in examples/mods (everything is procedural: no copied
assets). Re-run to rebuild; output is deterministic.

    python3 tools/modpack/example_assets.py [neon_arcade|rainy_night|frostbite_aki|library_rooms|all]

Needs numpy, Pillow and ffmpeg (Vorbis encoder) on the PATH.
"""
import json
import os
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODS = os.path.join(ROOT, "examples", "mods")
SR = 44100


def out(pack, rel):
    path = os.path.join(MODS, pack, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


# ---------------------------------------------------------------- neon arcade textures

def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def floor_tile(base, grout, trim, diagonal=False):
    """32x32: four dark tiles with a one-pixel neon line inset from the grout."""
    img = np.zeros((32, 32, 4), np.uint8)
    img[..., :3] = rgb(base)
    img[..., 3] = 255
    rng = np.random.RandomState(7)
    img[..., :3] = np.clip(img[..., :3].astype(int) + rng.randint(-3, 4, (32, 32, 1)), 0, 255)
    for i in range(32):
        for edge in (0, 15, 16, 31):
            img[edge, i, :3] = rgb(grout)
            img[i, edge, :3] = rgb(grout)
    for i in range(2, 14):
        for ox, oy in ((0, 0), (16, 0), (0, 16), (16, 16)):
            if (ox + oy) // 16 % 2 == (1 if diagonal else 0) or not diagonal:
                for a, b in ((2, i), (13, i), (i, 2), (i, 13)):
                    img[oy + a, ox + b, :3] = rgb(trim)
    return Image.fromarray(img)


def wall_panel(base, trim_a, trim_b, pins):
    """32x128: floor at the bottom. A dark panel, a neon rail at head height, a baseboard glow."""
    img = np.zeros((128, 32, 4), np.uint8)
    img[..., :3] = rgb(base)
    img[..., 3] = 255
    if pins:
        for x in range(0, 32, 8):
            img[:, x, :3] = [c + 10 for c in rgb(base)]
    img[0:6, :, :3] = rgb(base)[0] // 2, rgb(base)[1] // 2, rgb(base)[2] // 2
    img[100:102, :, :3] = rgb(trim_a)
    img[104:105, :, :3] = rgb(trim_b)
    img[118:119, :, :3] = rgb(trim_a)
    img[121:128, :, :3] = [c // 3 for c in rgb(base)]
    for y in range(40, 90, 10):
        img[y, ::2, :3] = [c + 12 for c in rgb(base)]
    return Image.fromarray(img)


def ceiling_tile():
    img = np.zeros((32, 32, 4), np.uint8)
    img[..., :3] = (16, 14, 26)
    img[..., 3] = 255
    for i in range(32):
        for e in (0, 31):
            img[e, i, :3] = (34, 30, 54)
            img[i, e, :3] = (34, 30, 54)
    img[14:18, 14:18, :3] = (70, 200, 220)   # a small cyan panel light
    img[15:17, 15:17, :3] = (190, 250, 255)
    return Image.fromarray(img)


def neon_arcade():
    p = "neon_arcade"
    floor_tile("#15131f", "#07060d", "#d63aa8").save(out(p, "assets/arcade_floor_a.png"))
    floor_tile("#17141f", "#07060d", "#25c3d8", diagonal=True).save(out(p, "assets/arcade_floor_b.png"))
    wall_panel("#1d1830", "#25c3d8", "#d63aa8", False).save(out(p, "assets/arcade_wall_a.png"))
    wall_panel("#211a36", "#d63aa8", "#25c3d8", True).save(out(p, "assets/arcade_wall_b.png"))
    ceiling_tile().save(out(p, "assets/arcade_ceiling.png"))


# ---------------------------------------------------------------- rainy night audio

def write_ogg(path, samples, quality=4):
    samples = np.clip(samples, -1, 1)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "a.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((samples * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "vorbis", "-strict", "-2",
                        "-ac", "2", "-q:a", str(quality), path], check=True)


def periodic_noise(seconds, lo, hi, seed, slope=0.0):
    """Band-limited noise built in the frequency domain, so the loop is exactly seamless."""
    n = int(SR * seconds)
    rng = np.random.RandomState(seed)
    spec = rng.randn(n // 2 + 1) + 1j * rng.randn(n // 2 + 1)
    freq = np.fft.rfftfreq(n, 1 / SR)
    shape = ((freq >= lo) & (freq <= hi)).astype(float)
    edge = np.clip(np.minimum((freq - lo) / max(lo * 0.5, 1), (hi - freq) / max(hi * 0.3, 1)), 0, 1)
    gain = edge * (np.maximum(freq, 1.0) / 1000.0) ** slope
    x = np.fft.irfft(spec * shape * gain, n)
    return x / np.max(np.abs(x))


def drops(seconds, rate, seed, freq_lo=1800, freq_hi=5200, decay=0.004):
    """Single raindrop pings scattered over a looping buffer (wrapping at the end)."""
    n = int(SR * seconds)
    buf = np.zeros(n)
    rng = np.random.RandomState(seed)
    for _ in range(int(rate * seconds)):
        at = rng.randint(n)
        f = rng.uniform(freq_lo, freq_hi)
        length = int(SR * decay * 8)
        t = np.arange(length) / SR
        ping = np.sin(2 * np.pi * f * t) * np.exp(-t / decay) * rng.uniform(0.2, 1.0)
        idx = (at + np.arange(length)) % n
        buf[idx] += ping
    return buf


def thunder(n, starts, seed, length=4.5, lowpass=170):
    """Rolling rumbles: lowpassed noise with a slow swell and a long tail, wrapped round the loop."""
    rng = np.random.RandomState(seed)
    buf = np.zeros(n)
    for start in starts:
        m = int(SR * length)
        noise = rng.randn(m)
        spec = np.fft.rfft(noise)
        freq = np.fft.rfftfreq(m, 1 / SR)
        spec *= 1.0 / (1.0 + (freq / lowpass) ** 3)
        rumble = np.fft.irfft(spec, m)
        rumble /= np.max(np.abs(rumble))
        t = np.arange(m) / SR
        env = (1 - np.exp(-t / 0.35)) * np.exp(-t / 1.4)
        flutter = 0.6 + 0.4 * np.sin(2 * np.pi * 3.1 * t + rng.uniform(0, 6))
        piece = rumble * env * flutter
        idx = (int(SR * start) + np.arange(m)) % n
        buf[idx] += piece
    return buf


def normalise(x, peak):
    return x / np.max(np.abs(x)) * peak


def rainy_night():
    p = "rainy_night"
    n = SR * 24
    # the maze: rain on a flat roof overhead, thunder far off
    roof = periodic_noise(24, 900, 7000, 11, slope=-0.4) * 0.55 + drops(24, 220, 5) * 0.5
    maze = normalise(roof, 0.5) + thunder(n, [4.0, 15.5], 3) * 0.45
    write_ogg(out(p, "assets/rain_roof_loop.ogg"), normalise(maze, 0.8))
    # the sewers: rain heard down a grate, muffled, with big slow drips echoing in the pipes
    wash = periodic_noise(24, 120, 1400, 21, slope=-0.8)
    drip = drops(24, 4, 8, 500, 1300, 0.03)
    echo = np.roll(drip, int(SR * 0.23)) * 0.5 + np.roll(drip, int(SR * 0.47)) * 0.25
    sewer = normalise(wash, 0.45) + (drip + echo) * 0.35 + thunder(n, [9.0], 6, lowpass=110) * 0.35
    write_ogg(out(p, "assets/rain_sewer_loop.ogg"), normalise(sewer, 0.8))
    # door creak: a slow saw sweep through a resonant band, wood noise on top
    t = np.arange(int(SR * 1.1)) / SR
    sweep = 150 + 90 * np.sin(2 * np.pi * 1.3 * t) + 60 * t
    phase = 2 * np.pi * np.cumsum(sweep) / SR
    saw = 2 * ((phase / (2 * np.pi)) % 1) - 1
    creak = saw * (np.sin(np.pi * t / t[-1]) ** 0.7) * (0.6 + 0.4 * np.sin(2 * np.pi * 17 * t))
    spec = np.fft.rfft(creak)
    freq = np.fft.rfftfreq(len(creak), 1 / SR)
    spec *= 1.0 / (1.0 + ((freq - 900) / 700) ** 2)
    creak = np.fft.irfft(spec, len(creak))
    write_ogg(out(p, "assets/door_creak_a.ogg"), normalise(creak, 0.6))
    t2 = np.arange(int(SR * 0.9)) / SR
    sweep2 = 210 - 80 * t2
    ph2 = 2 * np.pi * np.cumsum(sweep2) / SR
    creak2 = (2 * ((ph2 / (2 * np.pi)) % 1) - 1) * np.sin(np.pi * t2 / t2[-1]) * (0.7 + 0.3 * np.sin(2 * np.pi * 23 * t2))
    sp2 = np.fft.rfft(creak2)
    f2 = np.fft.rfftfreq(len(creak2), 1 / SR)
    sp2 *= 1.0 / (1.0 + ((f2 - 700) / 500) ** 2)
    write_ogg(out(p, "assets/door_creak_b.ogg"), normalise(np.fft.irfft(sp2, len(creak2)), 0.6))
    # wet footsteps: a short slap of bandpassed noise plus a soft low thud, three variants
    for i, seed in enumerate((31, 32, 33)):
        rng = np.random.RandomState(seed)
        m = int(SR * 0.22)
        tt = np.arange(m) / SR
        slap = rng.randn(m)
        sp = np.fft.rfft(slap)
        ff = np.fft.rfftfreq(m, 1 / SR)
        sp *= np.exp(-((ff - rng.uniform(1500, 2600)) / 1400) ** 2)
        slap = np.fft.irfft(sp, m) * np.exp(-tt / 0.03)
        thud = np.sin(2 * np.pi * rng.uniform(70, 95) * tt) * np.exp(-tt / 0.05)
        splash = rng.randn(m) * np.exp(-tt / 0.09) * (tt > 0.04) * 0.25
        write_ogg(out(p, "assets/wet_step_%s.ogg" % "abc"[i]), normalise(slap + thud * 1.5 + splash, 0.7))


# ---------------------------------------------------------------- frostbite aki

def rewrite_glb(src, dst, mutate):
    data = open(src, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    mutate(doc)
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + len(rest)
    open(dst, "wb").write(struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(text), 0x4E4F534A) + text + rest)


def frostbite_aki():
    p = "frostbite_aki"

    def ice(doc):
        for mat in doc["materials"]:
            tint = [0.55, 0.78, 1.0, 1.0] if mat.get("name") == "model" else [0.85, 0.95, 1.0, 1.0]
            mat["pbrMetallicRoughness"]["baseColorFactor"] = tint
        doc["asset"]["extras"]["hunter"] = "frostbite_aki"
    rewrite_glb(os.path.join(ROOT, "assets/hunters_blocky/aki/aki.glb"), out(p, "assets/frostbite_aki.glb"), ice)
    src = Image.open(os.path.join(ROOT, "assets/ui/hunter_portraits/aki.png")).convert("RGBA")
    a = np.asarray(src).astype(float)
    tint = np.array([0.6, 0.82, 1.0])
    grey = a[..., :3].mean(axis=2, keepdims=True)
    mix = 0.55 * a[..., :3] * tint + 0.45 * (grey * tint + np.array([30, 45, 60]))
    rng = np.random.RandomState(4)
    frost = (rng.rand(*a.shape[:2]) > 0.985)[..., None] * 90
    a[..., :3] = np.clip(mix + frost, 0, 255)
    Image.fromarray(a.astype(np.uint8)).save(out(p, "assets/frostbite_aki.png"))


# ---------------------------------------------------------------- library rooms: a rolling ladder prop

def box(cx, cy, cz, sx, sy, sz):
    """Vertices (position, normal) and indices of an axis-aligned box."""
    faces = [((1, 0, 0), [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]),
             ((-1, 0, 0), [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)]),
             ((0, 1, 0), [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)]),
             ((0, -1, 0), [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)]),
             ((0, 0, 1), [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
             ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)])]
    verts, idx = [], []
    for normal, corners in faces:
        base = len(verts)
        for c in corners:
            verts.append(((cx + c[0] * sx / 2, cy + c[1] * sy / 2, cz + c[2] * sz / 2), normal))
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    return verts, idx


def write_glb(path, parts, name):
    """parts: list of (boxes, [r, g, b]). One mesh primitive and material per part, bottom pivot."""
    binary = bytearray()
    views, accessors, primitives, materials = [], [], [], []
    for pi, (boxes, color) in enumerate(parts):
        verts, idx = [], []
        for b in boxes:
            v, i = box(*b)
            idx += [x + len(verts) for x in i]
            verts += v
        pos = np.array([v[0] for v in verts], "<f4")
        nor = np.array([v[1] for v in verts], "<f4")
        ind = np.array(idx, "<u2")
        refs = []
        for arr, target, comp, kind in ((pos, 34962, 5126, "VEC3"), (nor, 34962, 5126, "VEC3"), (ind, 34963, 5123, "SCALAR")):
            while len(binary) % 4:
                binary.append(0)
            views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": arr.nbytes, "target": target})
            binary += arr.tobytes()
            acc = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0] if arr.ndim == 1 else len(arr)),
                   "type": kind}
            if kind == "VEC3" and arr is pos:
                acc["min"], acc["max"] = pos.min(axis=0).tolist(), pos.max(axis=0).tolist()
            accessors.append(acc)
            refs.append(len(accessors) - 1)
        primitives.append({"attributes": {"POSITION": refs[0], "NORMAL": refs[1]}, "indices": refs[2], "material": pi})
        materials.append({"name": "mat%d" % pi, "pbrMetallicRoughness": {"baseColorFactor": color + [1.0],
                                                                        "metallicFactor": 0.0, "roughnessFactor": 0.85}})
    while len(binary) % 4:
        binary.append(0)
    doc = {"asset": {"version": "2.0", "generator": "LastRoute example_assets.py"}, "scene": 0,
           "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}], "meshes": [{"primitives": primitives}],
           "materials": materials, "accessors": accessors, "bufferViews": views,
           "buffers": [{"byteLength": len(binary)}]}
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + bytes(binary))


def library_rooms():
    p = "library_rooms"
    w, h, d = 0.7, 2.3, 0.45
    rails, rungs = [], []
    lean = 0.0
    for x in (-w / 2 + 0.03, w / 2 - 0.03):
        rails.append((x, h / 2, 0, 0.05, h, 0.06))
    for k in range(1, 8):
        y = k * h / 8
        rungs.append((0, y, 0, w - 0.04, 0.035, 0.1))
    wheels = [(x, 0.04, z, 0.08, 0.08, 0.04) for x in (-w / 2 + 0.03, w / 2 - 0.03) for z in (0.0,)]
    wood = ([*rails, *rungs], [0.36, 0.22, 0.12])
    iron = (wheels + [(0, h - 0.01, lean, w - 0.02, 0.025, 0.05)], [0.12, 0.12, 0.14])
    write_glb(out(p, "assets/rolling_ladder.glb"), [wood, iron], "rolling_ladder")


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    for name, fn in (("neon_arcade", neon_arcade), ("rainy_night", rainy_night), ("frostbite_aki", frostbite_aki),
                     ("library_rooms", library_rooms)):
        if which in ("all", name):
            fn()
            print("generated", name)
