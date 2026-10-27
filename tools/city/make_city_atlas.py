#!/usr/bin/env python3
"""Builds the City's pixel atlas (albedo + emission) and the repeating rim wall texture.

    python3 tools/city/make_city_atlas.py

Tile order comes from CityAtlas.NAMES in src/game_3d/city_atlas.gd. Everything is drawn procedurally (fixed seed), 32 px
tiles on a 256 px sheet, nearest-filtered in game. Original art, no external assets.
"""
import random
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
T = 32
SRC = (ROOT / "src/game_3d/city_atlas.gd").read_text()
NAMES = re.findall(r'"([a-z_]+)"', SRC.split("const NAMES := [")[1].split("]")[0])
assert len(NAMES) <= 64, len(NAMES)


def c(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(color, f):
    return tuple(max(0, min(255, int(v * f))) for v in color[:3]) + (color[3],)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


class Tile:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.img = Image.new("RGBA", (T, T), (0, 0, 0, 255))
        self.emit = Image.new("RGBA", (T, T), (0, 0, 0, 255))

    def fill(self, color, jitter=0.0):
        for y in range(T):
            for x in range(T):
                f = 1.0 + (self.rng.random() - .5) * jitter
                self.img.putpixel((x, y), shade(color, f))

    def rect(self, x0, y0, x1, y1, color, emit=None, jitter=0.0):
        for y in range(max(0, y0), min(T, y1)):
            for x in range(max(0, x0), min(T, x1)):
                f = 1.0 + (self.rng.random() - .5) * jitter
                self.img.putpixel((x, y), shade(color, f))
                if emit is not None:
                    self.emit.putpixel((x, y), emit)

    def dots(self, count, color, size=1):
        for _ in range(count):
            x = self.rng.randrange(T - size + 1)
            y = self.rng.randrange(T - size + 1)
            self.rect(x, y, x + size, y + size, color)


def cobbles(t, base, mortar, wet=False):
    t.fill(mortar, .08)
    for row in range(4):
        offset = 4 if row % 2 else 0
        for col in range(5):
            x0 = (col * 8 + offset) % T
            y0 = row * 8
            tone = shade(base, .85 + t.rng.random() * .3)
            t.rect(x0 + 1, y0 + 1, min(T, x0 + 7), y0 + 7, tone, jitter=.06)
            if wet and t.rng.random() < .45:
                t.rect(x0 + 2, y0 + 2, min(T, x0 + 5), y0 + 3, shade(base, 1.7))


def brick(t, base, dark, light):
    t.fill(dark, .05)
    for row in range(8):
        offset = 4 if row % 2 else 0
        for col in range(5):
            x0 = (col * 8 + offset) % T
            y0 = row * 4
            tone = shade(base, .8 + t.rng.random() * .4)
            t.rect(x0, y0, min(T, x0 + 7), y0 + 3, tone, jitter=.05)
    t.dots(10, light)


def window(t, brick_base, frame, glass, emit, top, arch=False):
    brick(t, brick_base, shade(brick_base, .6), shade(brick_base, 1.3))
    gx0, gx1 = 5, 27
    gy0, gy1 = (0, 26) if not top else (6, 32)
    t.rect(gx0 - 1, gy0, gx1 + 1, gy1 + (1 if not top else 0), frame)
    t.rect(gx0, gy0, gx1, gy1, glass, emit=emit)
    # mullion and a few reflections
    t.rect(15, gy0, 17, gy1, frame, emit=None)
    if emit is not None:
        for _ in range(5):
            x = t.rng.randrange(gx0, gx1 - 1)
            y = t.rng.randrange(gy0, gy1 - 1)
            t.rect(x, y, x + 2, y + 1, shade(glass, 1.25), emit=shade(emit, 1.1))
    if top:
        t.rect(3, 0, 29, 6, shade(brick_base, 1.25))   # lintel
    else:
        t.rect(2, 26, 30, 32, shade(brick_base, 1.35))  # sill


def make(name, index):
    t = Tile(index * 7919 + 13)
    amber = c("#e8842c")
    warm = c("#e8842c")
    cyan = c("#4de8e0")
    if name == "cobble":
        cobbles(t, c("#4a4d5c"), c("#23242d"))
    elif name == "cobble_wet":
        cobbles(t, c("#565a6e"), c("#262833"), wet=True)
    elif name == "sidewalk":
        t.fill(c("#6e6c7c"), .08)
        for x in (0, 16):
            t.rect(x, 0, x + 1, T, c("#4b4a58"))
        t.rect(0, 0, T, 1, c("#4b4a58"))
        t.rect(0, 16, T, 17, c("#4b4a58"))
        t.dots(12, c("#85838f"))
    elif name == "plaza":
        t.fill(c("#8a8497"), .07)
        for x in (0, 16):
            t.rect(x, 0, x + 1, T, c("#5d596b"))
        for y in (0, 16):
            t.rect(0, y, T, y + 1, c("#5d596b"))
        t.dots(14, c("#a29cb0"))
    elif name == "grass":
        t.fill(c("#2d5a3a"), .22)
        t.dots(18, c("#3f7a4c"), 2)
        t.dots(8, c("#1f4129"))
    elif name == "path":
        t.fill(c("#a59a88"), .15)
        t.dots(24, c("#8d8272"))
        t.dots(10, c("#bdb2a0"))
    elif name == "water":
        t.fill(c("#1f4f7a"), .10)
        for y in range(0, T, 6):
            t.rect(0, y, T, y + 1, c("#2d6ea0"))
        t.dots(8, c("#7fc0e8"), 2)
        t.dots(3, c("#ffd9a0"))
    elif name == "compass":
        t.fill(c("#c8b88a"), .06)
        t.rect(14, 0, 18, T, c("#5a4a8a"))
        t.rect(0, 14, T, 18, c("#5a4a8a"))
        t.rect(12, 12, 20, 20, c("#e8d9a8"))
        t.rect(2, 2, 6, 6, c("#8a6a3a")); t.rect(26, 2, 30, 6, c("#8a6a3a"))
        t.rect(2, 26, 6, 30, c("#8a6a3a")); t.rect(26, 26, 30, 30, c("#8a6a3a"))
    elif name in ("cross_ns", "cross_ew"):
        cobbles(t, c("#4a4d5c"), c("#23242d"))
        for k in range(0, T, 8):
            if name == "cross_ns":
                t.rect(k + 1, 0, k + 6, T, c("#d8d8e0"), jitter=.08)
            else:
                t.rect(0, k + 1, T, k + 6, c("#d8d8e0"), jitter=.08)
    elif name == "alley":
        cobbles(t, c("#3c3e4a"), c("#1c1d25"))
        t.dots(6, c("#2a2c36"), 2)
    elif name == "wood_floor":
        t.fill(c("#5a4430"), .06)
        for x in range(0, T, 8):
            t.rect(x, 0, x + 1, T, c("#3a2a1c"))
        for y in range(0, T, 16):
            t.dots(2, c("#3a2a1c"))
        t.dots(10, c("#7a6044"))
    elif name == "kiosk_floor":
        t.fill(c("#25706f"), .06)
        for k in (0, 16):
            t.rect(k, 0, k + 1, T, c("#154a4a")); t.rect(0, k, T, k + 1, c("#154a4a"))
        t.rect(12, 12, 20, 20, c("#39b6b0"))
    elif name == "bridge":
        t.fill(c("#7a5c3a"), .08)
        for x in range(0, T, 8):
            t.rect(x, 0, x + 1, T, c("#4a3520"))
        t.dots(10, c("#9a7a52"))
    elif name == "flowers":
        t.fill(c("#2b5236"), .15)
        for col in ("#d6568a", "#f08fb8", "#c76fe0", "#ffd36b"):
            t.dots(9, c(col), 2)
    elif name == "hedge":
        t.fill(c("#1f4a2c"), .25)
        t.dots(24, c("#2f6b3e"), 2)
        t.dots(14, c("#143220"), 2)
    elif name == "brick_a":
        brick(t, c("#5a3a30"), c("#2a1a16"), c("#7d5646"))
    elif name == "brick_b":
        brick(t, c("#4a3a44"), c("#221a22"), c("#6c5666"))
    elif name == "brick_c":
        brick(t, c("#3d3a3a"), c("#1c1b1b"), c("#5b5757"))
    elif name == "win_dark_bot":
        window(t, c("#5a3a30"), c("#2a1c18"), c("#0b101c"), None, False)
    elif name == "win_dark_top":
        window(t, c("#5a3a30"), c("#2a1c18"), c("#0b101c"), None, True)
    elif name == "win_lit_bot":
        window(t, c("#5a3a30"), c("#2a1c18"), c("#a85a1c"), warm, False)
    elif name == "win_lit_top":
        window(t, c("#5a3a30"), c("#2a1c18"), c("#a85a1c"), warm, True)
    elif name == "win_cyan_bot":
        window(t, c("#4a3a44"), c("#201822"), c("#1f8f94"), cyan, False)
    elif name == "win_cyan_top":
        window(t, c("#4a3a44"), c("#201822"), c("#1f8f94"), cyan, True)
    elif name in ("shop_bot", "shop_top"):
        top = name == "shop_top"
        window(t, c("#3d2a24"), c("#161010"), c("#b8742a"), warm, top)
        if not top:
            t.rect(2, 0, 30, 3, c("#7a1f3a"))   # awning edge
    elif name == "stone_base":
        t.fill(c("#46434d"), .1)
        for y in (0, 16):
            t.rect(0, y, T, y + 1, c("#2a2830"))
        t.rect(15, 0, 16, 16, c("#2a2830")); t.rect(7, 16, 8, T, c("#2a2830")); t.rect(23, 16, 24, T, c("#2a2830"))
    elif name == "cornice":
        brick(t, c("#4a342c"), c("#221612"), c("#6a4a3c"))
        t.rect(0, 20, T, 26, c("#6e5a50")); t.rect(0, 26, T, T, c("#2a1e1a"))
    elif name == "civic_a":
        t.fill(c("#6a6670"), .08)
        for y in range(0, T, 8):
            t.rect(0, y, T, y + 1, c("#44414a"))
        t.dots(10, c("#8b8794"))
    elif name == "civic_arch_bot":
        t.fill(c("#6a6670"), .08)
        t.rect(8, 0, 24, T, c("#10131f"), emit=None)
        t.rect(10, 0, 22, T, c("#c9812e"), emit=warm)
        t.rect(6, 0, 8, T, c("#8b8794")); t.rect(24, 0, 26, T, c("#8b8794"))
    elif name == "civic_arch_top":
        t.fill(c("#6a6670"), .08)
        t.rect(8, 8, 24, T, c("#10131f"))
        t.rect(10, 10, 22, T, c("#c9812e"), emit=warm)
        t.rect(11, 4, 21, 8, c("#8b8794")); t.rect(13, 2, 19, 4, c("#8b8794"))
    elif name == "ind_panel":
        t.fill(c("#34383f"), .06)
        for y in (0, 15):
            t.rect(0, y, T, y + 2, c("#1c1f25"))
        for x in (0, 16):
            t.rect(x, 0, x + 2, T, c("#1c1f25"))
        t.dots(8, c("#5a5f69"))
    elif name == "ind_port":
        t.fill(c("#34383f"), .06)
        t.rect(6, 8, 26, 24, c("#0d2a2e"))
        t.rect(8, 10, 24, 22, c("#1fb7b0"), emit=cyan)
        t.rect(6, 8, 26, 9, c("#1c1f25"))
    elif name == "kiosk_wall":
        t.fill(c("#16565c"), .06)
        for y in (0, 16):
            t.rect(0, y, T, y + 1, c("#0c3a40"))
        t.rect(15, 0, 16, T, c("#0c3a40"))
    elif name == "kiosk_sign":
        t.fill(c("#0b2a2e"))
        t.rect(2, 8, 30, 24, c("#39e6dc"), emit=cyan)
        t.rect(6, 12, 26, 20, c("#0b2a2e"))
        t.rect(10, 14, 22, 18, c("#9ff7f1"), emit=c("#9ff7f1"))
    elif name == "plaster":
        t.fill(c("#4f4a52"), .06)
        t.rect(0, 22, T, 24, c("#35303a"))
        t.dots(10, c("#625d66"))
    elif name == "ceiling":
        t.fill(c("#2a2630"), .06)
        for k in (0, 16):
            t.rect(k, 0, k + 1, T, c("#1c1920"))
    elif name == "rim_wall":
        t.fill(c("#222636"), .10)
        for y in range(0, T, 8):
            t.rect(0, y, T, y + 1, c("#10121a"))
        t.rect(15, 0, 17, T, c("#0c0c11"))
        t.dots(3, c("#2a3a4a"))
    elif name == "door":
        t.fill(c("#3a2418"), .08)
        t.rect(4, 2, 28, T, c("#2a1a10"))
        t.rect(23, 16, 25, 18, c("#d8a040"), emit=c("#d8a040"))
    elif name == "pole":
        t.fill(c("#1c1c24"), .08)
    elif name == "lantern":
        t.fill(c("#ffb04a"), .08)
        t.rect(0, 0, T, T, c("#f0a040"), emit=c("#e8842c"))
        for x in (0, 31):
            t.rect(x, 0, x + 1, T, c("#3a2a18"), emit=None)
    elif name == "cyan_lamp":
        t.fill(c("#39e6dc"))
        t.rect(0, 0, T, T, c("#6ff4ec"), emit=cyan)
    elif name == "trunk":
        t.fill(c("#3a2a22"), .12)
        t.dots(10, c("#241812"))
    elif name == "blossom":
        t.fill(c("#7a2f5c"), .22)
        t.dots(18, c("#b84a86"), 2)
        t.dots(10, c("#e69bc4"), 1)
        t.dots(6, c("#4a1a3c"), 2)
    elif name == "cypress":
        t.fill(c("#14301e"), .18)
        t.dots(16, c("#245238"), 2)
    elif name == "wood_bench":
        t.fill(c("#5a3c26"), .1)
        for y in range(0, T, 8):
            t.rect(0, y, T, y + 1, c("#2e1f14"))
    elif name == "planter":
        t.fill(c("#4b4452"), .1)
        t.rect(0, 0, T, 4, c("#6a6272"))
        t.dots(6, c("#2f2a36"))
    elif name == "statue_stone":
        t.fill(c("#6f6c78"), .1)
        t.dots(12, c("#8d8a98")); t.dots(10, c("#4e4b58"))
    elif name == "water_edge":
        t.fill(c("#555160"), .08)
        t.rect(0, 0, T, 3, c("#7b7788"))
        t.dots(8, c("#39384a"))
    elif name == "dome_strut":
        t.fill(c("#1a1d28"), .06)
    elif name == "stone_dark":
        t.fill(c("#2d2b34"), .1)
        t.dots(10, c("#47444f"))
    elif name == "petals":
        cobbles(t, c("#565a6e"), c("#262833"), wet=True)
        t.dots(14, c("#d6568a"), 1)
        t.dots(8, c("#f08fb8"), 1)
    elif name == "hedge_top":
        t.fill(c("#2a5e38"), .2)
        t.dots(16, c("#3f8a52"), 2)
    elif name == "bed_edge":
        t.fill(c("#5a3f33"), .1)
        t.rect(0, 0, T, 3, c("#7e5c4a"))
    elif name == "kiosk_roof":
        t.fill(c("#1d2b3a"), .08)
        for y in range(0, T, 4):
            t.rect(0, y, T, y + 1, c("#101a24"))
    else:
        t.fill(c("#ff00ff"))
    return t


def main():
    sheet = Image.new("RGBA", (256, 256), (0, 0, 0, 255))
    emit = Image.new("RGBA", (256, 256), (0, 0, 0, 255))
    for index, name in enumerate(NAMES):
        tile = make(name, index)
        x, y = (index % 8) * T, (index // 8) * T
        sheet.paste(tile.img, (x, y))
        emit.paste(tile.emit, (x, y))
    out = ROOT / "art/city"
    out.mkdir(parents=True, exist_ok=True)
    sheet.save(out / "city_atlas.png")
    emit.save(out / "city_emission.png")
    rim = make("rim_wall", NAMES.index("rim_wall")).img
    rim.save(out / "rim_wall.png")
    print("wrote", out, len(NAMES), "tiles")


main()
