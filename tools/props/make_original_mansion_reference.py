from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).resolve().parents[2]
ROOT = PROJECT_ROOT.parent / "LastRoute-OG" / "LastRoute-github" / "last-route" / "assets" / "environment"
OUT = PROJECT_ROOT / "art_source" / "reference" / "lastroute_mansion_reference.png"
OUT.parent.mkdir(parents=True, exist_ok=True)
FONT = ImageFont.load_default(size=20)
ENTRIES = [
    ("dining-table-south.png", "Grand dining table"),
    ("dining-chair-south.png", "Dining chair"),
    ("dining-chair-cushion-south.png", "Cushioned chair"),
    ("dining-chandelier-south.png", "Chandelier"),
    ("mansion-bookshelf-south.png", "Bookshelf"),
    ("magazine-rack-south.png", "Magazine rack"),
    ("mansion-fireplace-south.png", "Fireplace"),
    ("bathroom-stall-south.png", "Bathroom stall"),
    ("bathroom-sink-south.png", "Sink"),
    ("bathroom-mirror-south.png", "Mirror"),
    ("bathroom-vanity-south.png", "Vanity"),
    ("lounge-couch-brown-south.png", "Brown lounge couch"),
]

tile_w, tile_h, columns = 320, 330, 4
rows = (len(ENTRIES) + columns - 1) // columns
sheet = Image.new("RGB", (tile_w * columns, tile_h * rows), (17, 13, 14))
draw = ImageDraw.Draw(sheet)
for index, (filename, label) in enumerate(ENTRIES):
    source = Image.open(ROOT / filename).convert("RGBA")
    scale = min(5, 260 // max(source.width, 1), 260 // max(source.height, 1))
    source = source.resize((source.width * scale, source.height * scale), Image.Resampling.NEAREST)
    x0 = (index % columns) * tile_w
    y0 = (index // columns) * tile_h
    checker = Image.new("RGB", (280, 270), (39, 33, 36))
    sheet.paste(checker, (x0 + 20, y0 + 10))
    px = x0 + (tile_w - source.width) // 2
    py = y0 + 10 + (270 - source.height) // 2
    sheet.paste(source, (px, py), source)
    bounds = draw.textbbox((0, 0), label, font=FONT)
    tx = x0 + (tile_w - (bounds[2] - bounds[0])) // 2
    draw.text((tx, y0 + 292), label, fill=(236, 220, 190), font=FONT)
sheet.save(OUT)
