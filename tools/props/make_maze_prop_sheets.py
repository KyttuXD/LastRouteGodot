from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).resolve().parents[2]
ROOT = PROJECT_ROOT / "art" / "props-3d" / "props" / "maze" / "previews"
FONT = ImageFont.load_default(size=22)


def make_sheet(filename, entries, columns):
    tile_w, tile_h = 420, 470
    rows = (len(entries) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * tile_w, rows * tile_h), (13, 15, 22))
    draw = ImageDraw.Draw(sheet)
    for index, (source, label) in enumerate(entries):
        image = Image.open(ROOT / source).convert("RGB")
        image.thumbnail((390, 410), Image.Resampling.LANCZOS)
        x = (index % columns) * tile_w + (tile_w - image.width) // 2
        y = (index // columns) * tile_h + 10
        sheet.paste(image, (x, y))
        bounds = draw.textbbox((0, 0), label, font=FONT)
        tx = (index % columns) * tile_w + (tile_w - (bounds[2] - bounds[0])) // 2
        ty = (index // columns) * tile_h + 430
        draw.text((tx, ty), label, fill=(238, 229, 210), font=FONT)
    sheet.save(ROOT / filename, optimize=True)


make_sheet(
    "arcade_variants_gallery.png",
    [
        ("arcade_cabinet_default_hytale_preview.png", "Classic red / blue"),
        ("arcade_cabinet_burgundy_hytale_preview.png", "Burgundy"),
        ("arcade_cabinet_teal_hytale_preview.png", "Teal"),
        ("arcade_cabinet_amber_hytale_preview.png", "Amber"),
        ("arcade_cabinet_ultraviolet_hytale_preview.png", "Ultraviolet"),
        ("arcade_cabinet_cyan_magenta_hytale_preview.png", "Cyan / magenta"),
    ],
    3,
)

make_sheet(
    "maze_props_gallery.png",
    [
        ("wooden_chair_oak_hytale_preview.png", "Oak chair"),
        ("wooden_chair_cushion_hytale_preview.png", "Cushioned chair"),
        ("wooden_table_hytale_preview.png", "Drawer table"),
        ("wooden_dresser_sideboard_hytale_preview.png", "Dresser / sideboard"),
        ("filing_cabinet_hytale_preview.png", "Filing cabinet"),
        ("supply_crates_hytale_preview.png", "Supply crates"),
        ("server_rack_hytale_preview.png", "Server rack"),
        ("vending_machine_hytale_preview.png", "Vending machine"),
        ("floor_lamp_hytale_preview.png", "Floor lamp"),
        ("trash_bin_hytale_preview.png", "Trash bin"),
        ("privacy_curtain_hytale_preview.png", "Privacy curtain"),
        ("lounge_couch_red_hytale_preview.png", "Lounge couch"),
    ],
    4,
)
