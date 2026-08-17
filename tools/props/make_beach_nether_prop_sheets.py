from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE = PROJECT_ROOT / "art" / "props-3d" / "props"
FONT = ImageFont.load_default(size=22)


def sheet(root_name, filename, entries, columns):
    root = BASE / root_name / "previews"
    tile_w, tile_h = 420, 470
    rows = (len(entries) + columns - 1) // columns
    result = Image.new("RGB", (columns * tile_w, rows * tile_h), (13, 15, 22))
    draw = ImageDraw.Draw(result)
    for index, (source, label) in enumerate(entries):
        image = Image.open(root / source).convert("RGB")
        image.thumbnail((390, 410), Image.Resampling.LANCZOS)
        x0 = (index % columns) * tile_w
        y0 = (index // columns) * tile_h
        result.paste(image, (x0 + (tile_w - image.width) // 2, y0 + 10))
        bounds = draw.textbbox((0, 0), label, font=FONT)
        draw.text((x0 + (tile_w - bounds[2] + bounds[0]) // 2, y0 + 430),
                  label, fill=(238, 229, 210), font=FONT)
    result.save(root / filename, optimize=True)


sheet("beach", "beach_props_gallery.png", [
    ("sand_castle_hytale_preview.png", "Sand castle"),
    ("beach_umbrella_hytale_preview.png", "Beach umbrella"),
    ("tiki_bar_hytale_preview.png", "Frozen tiki bar"),
    ("beach_chair_hytale_preview.png", "Beach chair"),
    ("surfboard_rack_hytale_preview.png", "Surfboard rack"),
    ("palm_tree_hytale_preview.png", "Frosted palm tree"),
    ("frozen_beach_hut_hytale_preview.png", "Frozen beach hut"),
], 4)

sheet("nether", "nether_props_gallery.png", [
    ("lava_vent_hytale_preview.png", "Lava vent"),
    ("ember_brazier_hytale_preview.png", "Ember brazier"),
    ("basalt_pillar_hytale_preview.png", "Basalt pillar"),
    ("magma_crystal_cluster_hytale_preview.png", "Magma crystals"),
    ("basalt_rubble_hytale_preview.png", "Basalt rubble"),
    ("inferno_altar_hytale_preview.png", "Inferno altar"),
    ("inferno_chain_lantern_hytale_preview.png", "Chain lantern"),
    ("lava_pipe_manifold_hytale_preview.png", "Lava-pipe manifold"),
    ("charred_supply_crate_hytale_preview.png", "Charred crate"),
], 3)
