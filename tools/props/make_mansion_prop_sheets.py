from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).resolve().parents[2]
ROOT = PROJECT_ROOT / "art" / "props-3d" / "props" / "mansion" / "previews"
FONT = ImageFont.load_default(size=22)


def sheet(filename, entries, columns=4):
    tile_w, tile_h = 420, 470
    rows = (len(entries) + columns - 1) // columns
    result = Image.new("RGB", (columns * tile_w, rows * tile_h), (13, 15, 22))
    draw = ImageDraw.Draw(result)
    for index, (source, label) in enumerate(entries):
        image = Image.open(ROOT / source).convert("RGB")
        image.thumbnail((390, 410), Image.Resampling.LANCZOS)
        x0 = (index % columns) * tile_w
        y0 = (index // columns) * tile_h
        result.paste(image, (x0 + (tile_w - image.width) // 2, y0 + 10))
        bounds = draw.textbbox((0, 0), label, font=FONT)
        draw.text((x0 + (tile_w - bounds[2] + bounds[0]) // 2, y0 + 430),
                  label, fill=(238, 229, 210), font=FONT)
    result.save(ROOT / filename, optimize=True)


sheet("mansion_dining_decor_gallery.png", [
    ("grand_dining_table_hytale_preview.png", "Grand dining table"),
    ("dining_chair_burgundy_hytale_preview.png", "Arched burgundy chair"),
    ("dining_chair_cushion_burgundy_hytale_preview.png", "Burgundy chair"),
    ("dining_chair_ivory_hytale_preview.png", "Ivory chair"),
    ("dining_chandelier_hytale_preview.png", "Dining chandelier"),
    ("ornate_sideboard_hytale_preview.png", "Ornate sideboard"),
    ("table_candelabra_hytale_preview.png", "Table candelabra"),
    ("flower_centerpiece_hytale_preview.png", "Flower centerpiece"),
    ("framed_wall_portrait_hytale_preview.png", "Framed portrait"),
    ("wall_sconce_hytale_preview.png", "Wall sconce"),
    ("heavy_mansion_drapes_hytale_preview.png", "Heavy drapes"),
    ("mansion_area_rug_hytale_preview.png", "Patterned rug"),
])

sheet("mansion_rooms_gallery.png", [
    ("mansion_bookshelf_hytale_preview.png", "Mansion bookshelf"),
    ("magazine_rack_hytale_preview.png", "Magazine rack"),
    ("mansion_fireplace_hytale_preview.png", "Mansion fireplace"),
    ("bathroom_stall_hytale_preview.png", "Bathroom stall"),
    ("bathroom_sink_hytale_preview.png", "Bathroom sink"),
    ("bathroom_mirror_hytale_preview.png", "Bathroom mirror"),
    ("bathroom_vanity_hytale_preview.png", "Bathroom vanity"),
], 4)

sheet("mansion_couch_variants_gallery.png", [
    ("lounge_couch_brown_hytale_preview.png", "Brown"),
    ("lounge_couch_black_hytale_preview.png", "Black"),
    ("lounge_couch_navy_hytale_preview.png", "Navy"),
    ("lounge_couch_olive_hytale_preview.png", "Olive"),
    ("lounge_couch_violet_hytale_preview.png", "Violet"),
    ("lounge_couch_ivory_hytale_preview.png", "Ivory"),
], 3)

sheet("mansion_wide_couch_variants_gallery.png", [
    ("lounge_couch_red_wide_hytale_preview.png", "Wide red"),
    ("lounge_couch_brown_wide_hytale_preview.png", "Wide brown"),
    ("lounge_couch_black_wide_hytale_preview.png", "Wide black"),
    ("lounge_couch_navy_wide_hytale_preview.png", "Wide navy"),
    ("lounge_couch_olive_wide_hytale_preview.png", "Wide olive"),
    ("lounge_couch_violet_wide_hytale_preview.png", "Wide violet"),
    ("lounge_couch_ivory_wide_hytale_preview.png", "Wide ivory"),
], 4)

sheet("mansion_bedroom_gallery.png", [
    ("single_bed_burgundy_hytale_preview.png", "Single bed - burgundy"),
    ("single_bed_navy_hytale_preview.png", "Single bed - navy"),
    ("double_bed_burgundy_hytale_preview.png", "Double bed - burgundy"),
    ("double_bed_violet_hytale_preview.png", "Double bed - violet"),
    ("bedroom_nightstand_hytale_preview.png", "Nightstand"),
    ("bedroom_wardrobe_hytale_preview.png", "Wardrobe"),
    ("bedroom_dresser_hytale_preview.png", "Bedroom dresser"),
    ("bedroom_vanity_hytale_preview.png", "Vanity table"),
    ("vanity_stool_hytale_preview.png", "Vanity stool"),
    ("bedside_lamp_hytale_preview.png", "Bedside lamp"),
    ("toy_chest_hytale_preview.png", "Toy chest"),
    ("laundry_hamper_hytale_preview.png", "Laundry hamper"),
    ("bedroom_rug_hytale_preview.png", "Bedroom rug"),
    ("bedroom_wall_clock_hytale_preview.png", "Wall clock"),
    ("bedroom_bench_hytale_preview.png", "Bedroom bench"),
], 4)

normal_themes = ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"]
sheet("mansion_normal_bed_colorways_gallery.png", [
    ("%s_bed_%s_hytale_preview.png" % (size, theme),
     "%s %s" % (theme.title(), size))
    for theme in normal_themes for size in ("single", "double")
], 4)

sheet("mansion_normal_bedroom_colorways_gallery.png", [
    (("bedroom_wardrobe_hytale_preview.png" if theme == "burgundy"
      else "bedroom_wardrobe_%s_hytale_preview.png" % theme),
     "%s wardrobe" % theme.title())
    for theme in normal_themes
] + [
    (("bedroom_bench_hytale_preview.png" if theme == "burgundy"
      else "bedroom_bench_%s_hytale_preview.png" % theme),
     "%s bench" % theme.title())
    for theme in normal_themes
], 4)

gothic_themes = ["crimson", "violet", "midnight", "forest", "ivory"]
sheet("mansion_gothic_bed_colorways_gallery.png", [
    ("gothic_double_bed_%s_hytale_preview.png" % theme,
     "%s Gothic bed" % theme.title())
    for theme in gothic_themes
], 5)

sheet("mansion_gothic_bedroom_colorways_gallery.png", [
    ("gothic_%s_%s_hytale_preview.png" % (piece, theme),
     "%s %s" % (theme.title(), label))
    for theme in gothic_themes
    for piece, label in (("wardrobe", "wardrobe"),
                         ("vanity", "vanity"),
                         ("bedroom_bench", "bench"))
], 5)

sheet("mansion_gothic_crimson_set_gallery.png", [
    ("gothic_double_bed_crimson_hytale_preview.png", "Four-post bed"),
    ("gothic_nightstand_crimson_hytale_preview.png", "Nightstand"),
    ("gothic_wardrobe_crimson_hytale_preview.png", "Spired wardrobe"),
    ("gothic_dresser_crimson_hytale_preview.png", "Carved dresser"),
    ("gothic_vanity_crimson_hytale_preview.png", "Arched vanity"),
    ("gothic_vanity_stool_crimson_hytale_preview.png", "Vanity stool"),
    ("gothic_bedroom_bench_crimson_hytale_preview.png", "Tufted bench"),
    ("gothic_bedroom_rug_crimson_hytale_preview.png", "Patterned rug"),
    ("gothic_bedside_candelabra_crimson_hytale_preview.png", "Candelabra"),
], 3)

sheet("mansion_household_expansion_gallery.png", [
    ("mansion_console_table_hytale_preview.png", "Console table"),
    ("mansion_grandfather_clock_hytale_preview.png", "Grandfather clock"),
    ("mansion_coat_rack_hytale_preview.png", "Coat rack"),
    ("mansion_tea_cart_hytale_preview.png", "Tea cart"),
    ("mansion_rocking_chair_hytale_preview.png", "Rocking chair"),
    ("mansion_room_divider_hytale_preview.png", "Room divider"),
    ("gothic_highback_chair_crimson_hytale_preview.png", "Gothic high-back chair"),
    ("gothic_writing_desk_hytale_preview.png", "Gothic writing desk"),
    ("gothic_bookcase_hytale_preview.png", "Gothic bookcase"),
    ("gothic_pedestal_table_hytale_preview.png", "Gothic pedestal table"),
    ("gothic_floor_candelabra_hytale_preview.png", "Floor candelabra"),
    ("gothic_coffin_chest_hytale_preview.png", "Coffin storage chest"),
], 4)

kitchen_pieces = [
    ("counter", "Counter"),
    ("sink", "Sink"),
    ("stove", "Stove / range"),
    ("fridge", "Refrigerator"),
    ("wall_cabinet", "Wall cabinet"),
    ("island", "Kitchen island"),
]
sheet("mansion_kitchen_sets_gallery.png", [
    ("%s_kitchen_%s_hytale_preview.png" % (style, piece),
     "%s %s" % (style.title(), label))
    for style in ("normal", "luxury", "gothic")
    for piece, label in kitchen_pieces
], 3)

sheet("mansion_house_and_luxury_expansion_gallery.png", [
    ("normal_bookcase_hytale_preview.png", "Normal bookcase"),
    ("normal_coffee_table_hytale_preview.png", "Normal coffee table"),
    ("normal_tv_console_hytale_preview.png", "TV and console"),
    ("normal_entry_bench_hytale_preview.png", "Entry bench"),
    ("mansion_display_cabinet_hytale_preview.png", "Display cabinet"),
    ("mansion_chaise_lounge_hytale_preview.png", "Chaise lounge"),
    ("mansion_upright_piano_hytale_preview.png", "Upright piano"),
    ("mansion_bust_pedestal_hytale_preview.png", "Bust pedestal"),
], 4)

sheet("public_bathroom_utilities_gallery.png", [
    ("public_restroom_toilet_hytale_preview.png", "Public toilet"),
    ("public_mens_urinal_hytale_preview.png", "Men's urinal"),
    ("public_sink_bank_hytale_preview.png", "Three-basin sink bank"),
    ("public_hand_dryer_hytale_preview.png", "Hand dryer"),
    ("public_soap_dispenser_hytale_preview.png", "Soap dispenser"),
    ("public_paper_towel_dispenser_hytale_preview.png", "Paper towel dispenser"),
    ("public_sanitary_bin_hytale_preview.png", "Sanitary bin"),
    ("public_baby_change_station_hytale_preview.png", "Baby changing station"),
    ("public_mens_room_sign_hytale_preview.png", "Men's room sign"),
    ("public_womens_room_sign_hytale_preview.png", "Women's room sign"),
], 5)

sheet("public_shower_props_gallery.png", [
    ("public_mens_shower_stall_hytale_preview.png", "Men's shower stall"),
    ("public_womens_shower_stall_hytale_preview.png", "Women's shower stall"),
    ("public_shower_bench_hytale_preview.png", "Public shower bench"),
], 3)

sheet("house_bathroom_props_gallery.png", [
    ("house_bathtub_hytale_preview.png", "House bathtub"),
    ("house_toilet_hytale_preview.png", "House toilet"),
    ("house_shower_enclosure_hytale_preview.png", "House shower enclosure"),
    ("house_medicine_cabinet_hytale_preview.png", "Medicine cabinet"),
    ("house_towel_rack_hytale_preview.png", "Towel rack"),
    ("house_bath_mat_hytale_preview.png", "Bath mat"),
    ("house_bathroom_shelf_hytale_preview.png", "Bathroom shelf"),
], 4)
