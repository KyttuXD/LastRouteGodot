#!/usr/bin/env python3
"""Tiles the before/after panels from tools/look/prop_size_sheet.tscn into one contact sheet with captions from the
size dump (docs/PROP_SIZES.md).
    python3 tools/props/prop_size_sheet.py <panel dir> <before.json> <after.json> docs/prop_sizes_before_after.png
"""
import json
import pathlib
import sys
from PIL import Image, ImageDraw, ImageFont

panels = sorted(pathlib.Path(sys.argv[1]).glob("*.png"))
before = json.loads(pathlib.Path(sys.argv[2]).read_text())
after = json.loads(pathlib.Path(sys.argv[3]).read_text())
cols, tile_w, tile_h, cap = 3, 640, 270, 30
rows = (len(panels) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tile_w, rows * (tile_h + cap)), (24, 24, 28))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 17)
except OSError:
    font = ImageFont.load_default()
for i, path in enumerate(panels):
    img = Image.open(path).convert("RGB")
    img = img.crop((0, 90, img.width, img.height - 50)).resize((tile_w, tile_h))
    x, y = (i % cols) * tile_w, (i // cols) * (tile_h + cap)
    sheet.paste(img, (x, y + cap))
    name = path.stem
    b, a = before.get(name, {}), after.get(name, {})
    text = "%s  %.2f -> %.2f m tall (x%.2f)" % (name, b.get("y", 0), a.get("y", 0), a.get("scale", 1))
    draw.text((x + 8, y + 6), text, fill=(230, 230, 230), font=font)
draw.text((8, sheet.height - 22), "left: authored size, right: hunter scale; runner 1.60 m, hunter 2.67 m between them; 1 m floor grid",
          fill=(170, 170, 170), font=font)
sheet.save(sys.argv[4])
print("wrote", sys.argv[4], sheet.size)
