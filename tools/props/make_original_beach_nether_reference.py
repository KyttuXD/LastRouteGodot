from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).resolve().parents[2]
ROOT = PROJECT_ROOT.parent / "LastRoute-OG" / "LastRoute-github" / "last-route" / "assets" / "environment"
OUT = PROJECT_ROOT / "art" / "props-3d" / "reference" / "lastroute_beach_nether_reference.png"
OUT.parent.mkdir(parents=True, exist_ok=True)
FONT = ImageFont.load_default(size=20)
ENTRIES = [
    ("sand-castle-south.png", "Sand castle"),
    ("beach-umbrella-south.png", "Beach umbrella"),
    ("beach-tiki-bar-south.png", "Tiki bar"),
    ("beach-chair-south.png", "Beach chair"),
    ("surfboard-rack-south.png", "Surfboard rack"),
    ("palm-tree-south.png", "Palm tree"),
    ("lava-vent-south.png", "Lava vent"),
    ("ember-brazier-south.png", "Ember brazier"),
    ("basalt-pillar-south.png", "Basalt pillar"),
]
tile_w, tile_h, columns = 340, 350, 3
rows = (len(ENTRIES) + columns - 1) // columns
sheet = Image.new("RGB", (tile_w * columns, tile_h * rows), (17, 13, 14))
draw = ImageDraw.Draw(sheet)
for index, (filename, label) in enumerate(ENTRIES):
    source = Image.open(ROOT / filename).convert("RGBA")
    scale = max(1, min(6, 280 // max(source.width, 1), 280 // max(source.height, 1)))
    source = source.resize((source.width * scale, source.height * scale), Image.Resampling.NEAREST)
    x0 = (index % columns) * tile_w
    y0 = (index // columns) * tile_h
    panel = Image.new("RGB", (300, 285), (39, 33, 36))
    sheet.paste(panel, (x0 + 20, y0 + 10))
    sheet.paste(source, (x0 + (tile_w - source.width) // 2,
                         y0 + 10 + (285 - source.height) // 2), source)
    bounds = draw.textbbox((0, 0), label, font=FONT)
    draw.text((x0 + (tile_w - bounds[2] + bounds[0]) // 2, y0 + 310),
              label, fill=(236, 220, 190), font=FONT)
sheet.save(OUT)
