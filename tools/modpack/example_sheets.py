#!/usr/bin/env python3
"""Builds the contact sheets in docs/modding/examples/sheets from the example packs (headless: Pillow, numpy, ffmpeg).

    python3 tools/modpack/example_sheets.py <work dir>

<work dir> holds the files from example_layout.gd (arcade.json, library.json) and example_render.gd
(render_frostbite.png, render_ladder.png); see docs/modding/examples/README.md for the commands.
"""
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODS = os.path.join(ROOT, "examples", "mods")
OUT = os.path.join(ROOT, "docs", "modding", "examples", "sheets")
WORK = sys.argv[1]
BG = (24, 24, 34)
FONT = ImageFont.load_default(14)
SMALL = ImageFont.load_default(11)


def sheet(width, height):
    img = Image.new("RGB", (width, height), BG)
    return img, ImageDraw.Draw(img)


def title(d, text, y=8):
    d.text((12, y), text, fill=(235, 235, 245), font=FONT)


def fit(img, box_w, box_h):
    img = img.convert("RGBA")
    scale = min(box_w / img.width, box_h / img.height)
    return img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))), Image.NEAREST if scale > 1 else Image.LANCZOS)


def paste(sh, img, x, y):
    sh.paste(img, (x, y), img)


def layout(d, sh, data, x, y, cell, label):
    """Top-down plan of a generated room: floor cells, props coloured by type, the doorway marked."""
    rx, rz, rw, rh = data["rect"]
    palette = {}
    d.rectangle([x, y, x + rw * cell, y + rh * cell], fill=(46, 44, 62), outline=(120, 120, 150))
    for prop in data["props"]:
        colour = palette.setdefault(prop["type"], [(214, 58, 168), (37, 195, 216), (230, 180, 70), (120, 200, 110),
                                                    (190, 120, 230), (230, 120, 90), (120, 150, 240)][len(palette) % 7])
        for cx, cz in prop["cells"]:
            px, pz = x + (cx - rx) * cell, y + (cz - rz) * cell
            d.rectangle([px + 1, pz + 1, px + cell - 2, pz + cell - 2], fill=colour if prop["solid"] else tuple(c // 2 for c in colour))
    dx, dz = data["doorway"]
    d.rectangle([x + (dx - rx) * cell + 2, y + (dz - rz) * cell + 2, x + (dx - rx + 1) * cell - 3, y + (dz - rz + 1) * cell - 3],
                outline=(255, 255, 255))
    d.text((x, y - 16), label, fill=(235, 235, 245), font=FONT)
    ly = y + rh * cell + 8
    for name, colour in palette.items():
        d.rectangle([x, ly, x + 10, ly + 10], fill=colour)
        d.text((x + 16, ly - 2), name, fill=(200, 200, 215), font=SMALL)
        ly += 15
    return ly


def neon_arcade():
    sh, d = sheet(900, 640)
    title(d, "neon_arcade: floors, walls, ceiling (shown 6x) and the ARCADE room as generated for seed SHEET-A")
    x = 12
    for name in ("arcade_floor_a", "arcade_floor_b"):
        paste(sh, Image.open(f"{MODS}/neon_arcade/assets/{name}.png").convert("RGBA").resize((192, 192), Image.NEAREST), x, 40)
        d.text((x, 236), name, fill=(200, 200, 215), font=SMALL)
        x += 204
    for name in ("arcade_wall_a", "arcade_wall_b"):
        img = Image.open(f"{MODS}/neon_arcade/assets/{name}.png").convert("RGBA")
        paste(sh, img.resize((img.width * 3, img.height * 3), Image.NEAREST), x, 40)
        d.text((x, 428), name, fill=(200, 200, 215), font=SMALL)
        x += 108
    paste(sh, Image.open(f"{MODS}/neon_arcade/assets/arcade_ceiling.png").convert("RGBA").resize((96, 96), Image.NEAREST), 12, 262)
    d.text((12, 362), "arcade_ceiling", fill=(200, 200, 215), font=SMALL)
    data = json.load(open(f"{WORK}/arcade.json"))["neon_arcade_hall"]
    layout(d, sh, data, 12, 400, 14, "neon_arcade_hall (dim = walk-over)")
    sh.save(f"{OUT}/neon_arcade.png")


def library_rooms():
    sh, d = sheet(900, 560)
    title(d, "library_rooms: the reading room and the archive as generated for seed SHEET-A, and the new ladder prop")
    data = json.load(open(f"{WORK}/library.json"))
    layout(d, sh, data["library_rooms_reading"], 12, 56, 14, "library_rooms_reading")
    layout(d, sh, data["library_rooms_archive"], 12, 300, 14, "library_rooms_archive")
    paste(sh, fit(Image.open(f"{WORK}/render_ladder.png").crop((520, 60, 920, 600)), 300, 400), 560, 100)
    d.text((560, 510), "library_rooms_ladder", fill=(200, 200, 215), font=SMALL)
    sh.save(f"{OUT}/library_rooms.png")


def frostbite_aki():
    sh, d = sheet(900, 420)
    title(d, "frostbite_aki: Aki (left) and Frostbite Aki, and their portraits")
    paste(sh, fit(Image.open(f"{WORK}/render_frostbite.png").crop((320, 180, 1120, 780)), 560, 380), 12, 32)
    for i, (name, path) in enumerate((("Aki", f"{ROOT}/assets/ui/hunter_portraits/aki.png"),
                                      ("Frostbite Aki", f"{MODS}/frostbite_aki/assets/frostbite_aki.png"))):
        paste(sh, Image.open(path).convert("RGBA").resize((192, 192), Image.NEAREST), 600 + (i % 1) * 0, 40 + i * 210)
        d.text((800, 130 + i * 210), name, fill=(200, 200, 215), font=SMALL)
    d.text((12, 400), "chase 3.55 -> 3.3, speed 0.82 -> 0.8, sight 8.2 -> 7.8", fill=(200, 200, 215), font=SMALL)
    sh.save(f"{OUT}/frostbite_aki.png")


def decode(path):
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "a.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", "11025", wav], check=True)
        with wave.open(wav) as w:
            return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32768, w.getframerate()


def rainy_night():
    files = [("rain_roof_loop", "ambience maze"), ("rain_sewer_loop", "ambience sewer"), ("door_creak_a", "cue door_open"),
             ("door_creak_b", "cue door_open / door_close"), ("wet_step_a", "cue footstep_walk (3 variants)")]
    sh, d = sheet(900, 40 + 86 * len(files))
    title(d, "rainy_night: waveforms of the generated audio (loops are seamless)")
    for i, (name, use) in enumerate(files):
        x, sr = decode(f"{MODS}/rainy_night/assets/{name}.ogg")
        y = 40 + i * 86
        d.text((12, y), f"{name}.ogg  ({len(x) / sr:.1f} s)  {use}", fill=(200, 200, 215), font=SMALL)
        mid, width = y + 46, 876
        for px in range(width):
            seg = x[px * len(x) // width:(px + 1) * len(x) // width]
            if len(seg):
                h = int(min(1.0, np.abs(seg).max()) * 30)
                d.line([(12 + px, mid - h), (12 + px, mid + h)], fill=(37, 195, 216))
    sh.save(f"{OUT}/rainy_night.png")


def gentle_grabs():
    sh, d = sheet(900, 330)
    title(d, "gentle_grabs: grab pool weights, built in (grey) against the pack (teal)")
    base = {k: json.load(open(f"{ROOT}/data/grabs/{k}.json"))["pool"] for k in ("kathy", "glyra")}
    pack = {k: json.load(open(f"{MODS}/gentle_grabs/grabs/{k}.json"))["pool"] for k in ("kathy", "glyra")}
    y = 40
    for hunter in ("kathy", "glyra"):
        d.text((12, y), hunter, fill=(235, 235, 245), font=FONT)
        y += 24
        for style in sorted(set(base[hunter]) | set(pack[hunter])):
            d.text((12, y), style, fill=(200, 200, 215), font=SMALL)
            d.rectangle([160, y, 160 + 40 * base[hunter].get(style, 0), y + 6], fill=(120, 120, 140))
            d.rectangle([160, y + 8, 160 + 40 * pack[hunter].get(style, 0), y + 14], fill=(37, 195, 216))
            y += 20
        y += 14
    sh.save(f"{OUT}/gentle_grabs.png")


def death_lines_plus():
    sh, d = sheet(900, 640)
    title(d, "death_lines_plus: the added lines (each hunter's built-in lines stay in the pool)")
    y = 36
    for k, name in enumerate(sorted(os.listdir(f"{MODS}/death_lines_plus/deaths"))):
        data = json.load(open(f"{MODS}/death_lines_plus/deaths/{name}"))
        col, row = divmod(k, 19)
        d.text((12 + col * 450, 36 + row * 30), f"{data['id']}: {data['lines'][0]}"[:68], fill=(200, 200, 215), font=SMALL)
    sh.save(f"{OUT}/death_lines_plus.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for fn in (neon_arcade, library_rooms, frostbite_aki, rainy_night, gentle_grabs, death_lines_plus):
        fn()
        print("sheet", fn.__name__)
