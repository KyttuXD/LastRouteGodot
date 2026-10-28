class_name PropModelCatalog
extends RefCounted

## Presentation-only catalog for authored room dressing. FacilityGenerator
## owns deterministic placement and collision through RoomCatalog; this file
## only selects which imported model represents a mechanical prop type.
## Multiple paths are intentional visual variants and are selected from the
## stable generated prop id, so every peer sees the same couch/cabinet colour.

## Use the Minecraft-style block rebuilds (BlockyPropModels) where they exist.
const USE_BLOCKY_PROPS := true

## Read MODEL_PATHS, not this: ContentRegistry.DATA entries come from res://data/props (docs/DATA_DRIVEN_CONTENT.md).
const _CODE_MODEL_PATHS := {
	## Mansion pieces (tools/props/blocky_props_mansion.py), blocky-only.
	"mansionMarbleColumn": ContentRegistry.DATA,
	"mansionPorcelainVase": ContentRegistry.DATA,
	## Room-purpose catalog (tools/props/blocky_props_rework4.py): designed blocky-only, so the blocky GLBs are also their
	## catalogue models.
	"ivStand": ContentRegistry.DATA,
	"medicalCart": ContentRegistry.DATA,
	"readingTable": ContentRegistry.DATA,
	"libraryGlobe": ContentRegistry.DATA,
	"storageBarrel": ContentRegistry.DATA,
	"storageShelving": ContentRegistry.DATA,
	"receptionDesk": ContentRegistry.DATA,
	"pottedPlant": ContentRegistry.DATA,
	"standingMirror": ContentRegistry.DATA,
	"arcadeCabinet": ContentRegistry.DATA,
	"arcadeCabinetCyanMagenta": ContentRegistry.DATA,
	"filingCabinet": ContentRegistry.DATA,
	"officeDesk": ContentRegistry.DATA,
	"officeChair": ContentRegistry.DATA,
	"officeCrtSecurityConsole": ContentRegistry.DATA,
	"officeCubiclePartition": ContentRegistry.DATA,
	"officePrinter": ContentRegistry.DATA,
	"officeWaterCooler": ContentRegistry.DATA,
	"officePhotocopier": ContentRegistry.DATA,
	"officeShredder": ContentRegistry.DATA,
	"officeFileBoxes": ContentRegistry.DATA,
	"officeCornerWorkstation": ContentRegistry.DATA,
	"arcadeBasketballHoop": ContentRegistry.DATA,
	"arcadeCarpetCircle": ContentRegistry.DATA,
	"arcadeCarpetRunner": ContentRegistry.DATA,
	"arcadeTokenChanger": ContentRegistry.DATA,
	"backstageRepairStand": ContentRegistry.DATA,
	"breakerCabinet": ContentRegistry.DATA,
	"brokenAquarium": ContentRegistry.DATA,
	"carnivalCarousel": ContentRegistry.DATA,
	"flowerBlue": ContentRegistry.DATA,
	"flowerRose": ContentRegistry.DATA,
	"flowerSun": ContentRegistry.DATA,
	"flowerViolet": ContentRegistry.DATA,
	"gardenPlanterBench": ContentRegistry.DATA,
	"giantTree": ContentRegistry.DATA,
	"grassFern": ContentRegistry.DATA,
	"locker": ContentRegistry.DATA,
	"maintenanceCleaningCart": ContentRegistry.DATA,
	"maintenanceToolCabinet": ContentRegistry.DATA,
	"mascotStatue": ContentRegistry.DATA,
	"prizeClawMachine": ContentRegistry.DATA,
	"prizeCounter": ContentRegistry.DATA,
	"snackKiosk": ContentRegistry.DATA,
	"stagePlatform": ContentRegistry.DATA,
	"stageSpeaker": ContentRegistry.DATA,
	"utilityCart": ContentRegistry.DATA,
	"floorLamp": ContentRegistry.DATA,
	"ceilingLight": [
		"res://art/props-3d/props/mansion/ceiling_light_warm.glb",
		"res://art/props-3d/props/mansion/ceiling_light_cool.glb",
		"res://art/props-3d/props/mansion/ceiling_light_teal.glb",
	],
	"ceilingFan": [
		"res://art/props-3d/props/mansion/ceiling_fan_walnut.glb",
		"res://art/props-3d/props/mansion/ceiling_fan_ivory.glb",
		"res://art/props-3d/props/mansion/ceiling_fan_charcoal.glb",
	],
	"tableLamp": [
		"res://art/props-3d/props/mansion/table_lamp_burgundy.glb",
		"res://art/props-3d/props/mansion/table_lamp_teal.glb",
		"res://art/props-3d/props/mansion/table_lamp_ivory.glb",
	],
	"loungeCouch": [
		"res://art/props-3d/props/maze/lounge_couch_red.glb",
		"res://art/props-3d/props/mansion/lounge_couch_black.glb",
		"res://art/props-3d/props/mansion/lounge_couch_brown.glb",
		"res://art/props-3d/props/mansion/lounge_couch_ivory.glb",
		"res://art/props-3d/props/mansion/lounge_couch_navy.glb",
		"res://art/props-3d/props/mansion/lounge_couch_olive.glb",
		"res://art/props-3d/props/mansion/lounge_couch_violet.glb",
	],
	"loungeCouchWide": [
		"res://art/props-3d/props/mansion/lounge_couch_red_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_black_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_brown_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_ivory_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_navy_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_olive_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_violet_wide.glb",
	],
	"privacyCurtain": ["res://art/props-3d/props/maze/privacy_curtain.glb"],
	"serverRack": ["res://art/props-3d/props/maze/server_rack.glb"],
	"supplyCrates": ["res://art/props-3d/props/maze/supply_crates.glb"],
	"trashBin": ["res://art/props-3d/props/maze/trash_bin.glb"],
	"vendingMachine": ["res://art/props-3d/props/maze/vending_machine.glb"],
	"woodenChair": [
		"res://art/props-3d/props/maze/wooden_chair_oak.glb",
		"res://art/props-3d/props/maze/wooden_chair_walnut.glb",
		"res://art/props-3d/props/maze/wooden_chair_mahogany.glb",
		"res://art/props-3d/props/maze/wooden_chair_ash.glb",
	],
	"woodenChairCushion": [
		"res://art/props-3d/props/maze/wooden_chair_cushion.glb",
		"res://art/props-3d/props/maze/wooden_chair_cushion_walnut.glb",
		"res://art/props-3d/props/maze/wooden_chair_cushion_mahogany.glb",
		"res://art/props-3d/props/maze/wooden_chair_cushion_ash.glb",
	],
	"woodenTable": [
		"res://art/props-3d/props/maze/wooden_table.glb",
		"res://art/props-3d/props/maze/wooden_table_walnut.glb",
		"res://art/props-3d/props/maze/wooden_table_mahogany.glb",
		"res://art/props-3d/props/maze/wooden_table_ash.glb",
	],
	"restaurantPartyTable": [
		"res://art/props-3d/props/maze/restaurant_party_table.glb",
	],
	"woodenDresserSideboard": [
		"res://art/props-3d/props/maze/wooden_dresser_sideboard.glb",
		"res://art/props-3d/props/maze/wooden_dresser_sideboard_walnut.glb",
		"res://art/props-3d/props/maze/wooden_dresser_sideboard_mahogany.glb",
		"res://art/props-3d/props/maze/wooden_dresser_sideboard_ash.glb",
	],
	"retroComputerCompact": [
		"res://art/props-3d/props/maze/retro_computer_compact_ivory.glb",
		"res://art/props-3d/props/maze/retro_computer_compact_charcoal.glb",
		"res://art/props-3d/props/maze/retro_computer_compact_teal.glb",
		"res://art/props-3d/props/maze/retro_computer_compact_burgundy.glb",
	],
	"retroComputerTower": [
		"res://art/props-3d/props/maze/retro_computer_tower_ivory.glb",
		"res://art/props-3d/props/maze/retro_computer_tower_charcoal.glb",
		"res://art/props-3d/props/maze/retro_computer_tower_teal.glb",
		"res://art/props-3d/props/maze/retro_computer_tower_burgundy.glb",
	],
	"retroComputerDesktop": [
		"res://art/props-3d/props/maze/retro_computer_desktop_ivory.glb",
		"res://art/props-3d/props/maze/retro_computer_desktop_charcoal.glb",
		"res://art/props-3d/props/maze/retro_computer_desktop_teal.glb",
		"res://art/props-3d/props/maze/retro_computer_desktop_burgundy.glb",
	],
	"retroComputerTerminal": [
		"res://art/props-3d/props/maze/retro_computer_terminal_ivory.glb",
		"res://art/props-3d/props/maze/retro_computer_terminal_charcoal.glb",
		"res://art/props-3d/props/maze/retro_computer_terminal_teal.glb",
		"res://art/props-3d/props/maze/retro_computer_terminal_burgundy.glb",
	],

	"diningTable": ["res://art/props-3d/props/mansion/grand_dining_table.glb"],
	"diningChair": [
		"res://art/props-3d/props/mansion/dining_chair_burgundy.glb",
		"res://art/props-3d/props/mansion/dining_chair_ivory.glb",
	],
	"diningChairCushion": [
		"res://art/props-3d/props/mansion/dining_chair_cushion_burgundy.glb",
	],
	"diningChandelier": [
		"res://art/props-3d/props/mansion/dining_chandelier.glb",
		"res://art/props-3d/props/mansion/dining_chandelier_crystal.glb",
		"res://art/props-3d/props/mansion/dining_chandelier_gothic.glb",
	],
	"diningSideboard": ["res://art/props-3d/props/mansion/ornate_sideboard.glb"],
	"flowerCenterpiece": [
		"res://art/props-3d/props/mansion/flower_centerpiece.glb",
	],
	"framedWallPortrait": [
		"res://art/props-3d/props/mansion/framed_wall_portrait.glb",
	],
	# Empty residential frames deliberately contain no canvas/image mesh. The
	# wall remains visible through their centre until authored artwork is added.
	"normalPictureFrameEmpty": [
		"res://art/props-3d/props/mansion/normal_picture_frame_empty.glb",
	],
	"normalPaintingFrameEmpty": [
		"res://art/props-3d/props/mansion/normal_painting_frame_empty.glb",
	],
	"luxuryPictureFrameEmpty": [
		"res://art/props-3d/props/mansion/luxury_picture_frame_empty.glb",
	],
	"luxuryPaintingFrameEmpty": [
		"res://art/props-3d/props/mansion/luxury_painting_frame_empty.glb",
	],
	"gothicPictureFrameEmpty": [
		"res://art/props-3d/props/mansion/gothic_picture_frame_empty.glb",
	],
	"gothicPaintingFrameEmpty": [
		"res://art/props-3d/props/mansion/gothic_painting_frame_empty.glb",
	],
	"normalRoomDoor": [
		"res://art/props-3d/props/mansion/normal_room_door.glb",
	],
	"luxuryRoomDoor": [
		"res://art/props-3d/props/mansion/luxury_room_door.glb",
	],
	"gothicRoomDoor": [
		"res://art/props-3d/props/mansion/gothic_room_door.glb",
	],
	"normalDoubleRoomDoor": [
		"res://art/props-3d/props/mansion/normal_double_room_door.glb",
	],
	"luxuryDoubleRoomDoor": [
		"res://art/props-3d/props/mansion/luxury_double_room_door.glb",
	],
	"gothicDoubleRoomDoor": [
		"res://art/props-3d/props/mansion/gothic_double_room_door.glb",
	],
	"heavyMansionDrapes": [
		"res://art/props-3d/props/mansion/heavy_mansion_drapes.glb",
	],
	"mansionAreaRug": ["res://art/props-3d/props/mansion/mansion_area_rug.glb"],
	"corridorCarpet": [
		"res://art/props-3d/props/mansion/corridor_carpet_teal.glb",
		"res://art/props-3d/props/mansion/corridor_carpet_burgundy.glb",
	],
	"hotelCarpet": [
		"res://art/props-3d/props/mansion/hotel_carpet_burgundy.glb",
		"res://art/props-3d/props/mansion/hotel_carpet_navy.glb",
		"res://art/props-3d/props/mansion/hotel_carpet_ivory.glb",
	],
	"apartmentCarpet": [
		"res://art/props-3d/props/mansion/apartment_carpet_olive.glb",
		"res://art/props-3d/props/mansion/apartment_carpet_charcoal.glb",
		"res://art/props-3d/props/mansion/apartment_carpet_rust.glb",
	],
	"beachMat": [
		"res://art/props-3d/props/mansion/beach_mat_teal.glb",
		"res://art/props-3d/props/mansion/beach_mat_sun.glb",
	],
	"mansionBookshelf": [
		"res://art/props-3d/props/mansion/mansion_bookshelf.glb",
	],
	"mansionFireplace": [
		"res://art/props-3d/props/mansion/mansion_fireplace.glb",
	],
	"magazineRack": ["res://art/props-3d/props/mansion/magazine_rack.glb"],
	"tableCandelabra": [
		"res://art/props-3d/props/mansion/table_candelabra.glb",
	],
	"wallSconce": [
		"res://art/props-3d/props/mansion/wall_sconce.glb",
		"res://art/props-3d/props/mansion/wall_sconce_cool.glb",
		"res://art/props-3d/props/mansion/wall_sconce_gothic.glb",
	],
	"bathroomStall": ["res://art/props-3d/props/mansion/bathroom_stall.glb"],
	"bathroomSink": ["res://art/props-3d/props/mansion/bathroom_sink.glb"],
	"bathroomMirror": ["res://art/props-3d/props/mansion/bathroom_mirror.glb"],
	"bathroomVanity": ["res://art/props-3d/props/mansion/bathroom_vanity.glb"],
	"publicRestroomToilet": ["res://art/props-3d/props/mansion/public_restroom_toilet.glb"],
	"publicMensUrinal": ["res://art/props-3d/props/mansion/public_mens_urinal.glb"],
	"publicSinkBank": ["res://art/props-3d/props/mansion/public_sink_bank.glb"],
	"publicHandDryer": ["res://art/props-3d/props/mansion/public_hand_dryer.glb"],
	"publicSoapDispenser": ["res://art/props-3d/props/mansion/public_soap_dispenser.glb"],
	"publicPaperTowelDispenser": ["res://art/props-3d/props/mansion/public_paper_towel_dispenser.glb"],
	"publicBabyChangeStation": ["res://art/props-3d/props/mansion/public_baby_change_station.glb"],
	"publicSanitaryBin": ["res://art/props-3d/props/mansion/public_sanitary_bin.glb"],
	"publicMensRoomSign": ["res://art/props-3d/props/mansion/public_mens_room_sign.glb"],
	"publicWomensRoomSign": ["res://art/props-3d/props/mansion/public_womens_room_sign.glb"],
	"publicMensShowerStall": ["res://art/props-3d/props/mansion/public_mens_shower_stall.glb"],
	"publicWomensShowerStall": ["res://art/props-3d/props/mansion/public_womens_shower_stall.glb"],
	"publicShowerBench": ["res://art/props-3d/props/mansion/public_shower_bench.glb"],
	"houseBathtub": ["res://art/props-3d/props/mansion/house_bathtub.glb"],
	"houseToilet": ["res://art/props-3d/props/mansion/house_toilet.glb"],
	"houseShowerEnclosure": ["res://art/props-3d/props/mansion/house_shower_enclosure.glb"],
	"houseMedicineCabinet": ["res://art/props-3d/props/mansion/house_medicine_cabinet.glb"],
	"houseTowelRack": ["res://art/props-3d/props/mansion/house_towel_rack.glb"],
	"houseBathMat": ["res://art/props-3d/props/mansion/house_bath_mat.glb"],
	"houseBathroomShelf": ["res://art/props-3d/props/mansion/house_bathroom_shelf.glb"],
	"grandStaircase": ["res://art/props-3d/props/mansion/grand_staircase.glb"],
	"grandFoyerStaircase": ["res://art/props-3d/props/mansion/grand_foyer_staircase.glb"],
	"singleBed": [
		"res://art/props-3d/props/mansion/single_bed_burgundy.glb",
		"res://art/props-3d/props/mansion/single_bed_navy.glb",
		"res://art/props-3d/props/mansion/single_bed_violet.glb",
		"res://art/props-3d/props/mansion/single_bed_olive.glb",
		"res://art/props-3d/props/mansion/single_bed_ivory.glb",
		"res://art/props-3d/props/mansion/single_bed_charcoal.glb",
	],
	"doubleBed": [
		"res://art/props-3d/props/mansion/double_bed_burgundy.glb",
		"res://art/props-3d/props/mansion/double_bed_navy.glb",
		"res://art/props-3d/props/mansion/double_bed_violet.glb",
		"res://art/props-3d/props/mansion/double_bed_olive.glb",
		"res://art/props-3d/props/mansion/double_bed_ivory.glb",
		"res://art/props-3d/props/mansion/double_bed_charcoal.glb",
	],
	"bunkBed": [
		"res://art/props-3d/props/prison/bunk_bed_metal.glb",
		"res://art/props-3d/props/prison/bunk_bed_wood.glb",
		"res://art/props-3d/props/prison/bunk_bed_loft.glb",
	],
	"bedroomNightstand": [
		"res://art/props-3d/props/mansion/bedroom_nightstand.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_charcoal.glb",
	],
	"bedroomWardrobe": [
		"res://art/props-3d/props/mansion/bedroom_wardrobe.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_charcoal.glb",
	],
	"bedroomDresser": [
		"res://art/props-3d/props/mansion/bedroom_dresser.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_charcoal.glb",
	],
	"bedroomVanity": [
		"res://art/props-3d/props/mansion/bedroom_vanity.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_charcoal.glb",
	],
	"vanityStool": [
		"res://art/props-3d/props/mansion/vanity_stool.glb",
		"res://art/props-3d/props/mansion/vanity_stool_navy.glb",
		"res://art/props-3d/props/mansion/vanity_stool_violet.glb",
		"res://art/props-3d/props/mansion/vanity_stool_olive.glb",
		"res://art/props-3d/props/mansion/vanity_stool_ivory.glb",
		"res://art/props-3d/props/mansion/vanity_stool_charcoal.glb",
	],
	"bedsideLamp": [
		"res://art/props-3d/props/mansion/bedside_lamp.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_navy.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_violet.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_olive.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_ivory.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_charcoal.glb",
	],
	"toyChest": [
		"res://art/props-3d/props/mansion/toy_chest.glb",
		"res://art/props-3d/props/mansion/toy_chest_navy.glb",
		"res://art/props-3d/props/mansion/toy_chest_violet.glb",
		"res://art/props-3d/props/mansion/toy_chest_olive.glb",
		"res://art/props-3d/props/mansion/toy_chest_ivory.glb",
		"res://art/props-3d/props/mansion/toy_chest_charcoal.glb",
	],
	"laundryHamper": [
		"res://art/props-3d/props/mansion/laundry_hamper.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_navy.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_violet.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_olive.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_ivory.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_charcoal.glb",
	],
	"bedroomRug": [
		"res://art/props-3d/props/mansion/bedroom_rug.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_charcoal.glb",
	],
	"bedroomWallClock": [
		"res://art/props-3d/props/mansion/bedroom_wall_clock.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_charcoal.glb",
	],
	"bedroomBench": [
		"res://art/props-3d/props/mansion/bedroom_bench.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_charcoal.glb",
	],

	"gothicDoubleBed": [
		"res://art/props-3d/props/mansion/gothic_double_bed_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_double_bed_violet.glb",
		"res://art/props-3d/props/mansion/gothic_double_bed_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_double_bed_forest.glb",
		"res://art/props-3d/props/mansion/gothic_double_bed_ivory.glb",
	],
	"gothicNightstand": [
		"res://art/props-3d/props/mansion/gothic_nightstand_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_nightstand_violet.glb",
		"res://art/props-3d/props/mansion/gothic_nightstand_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_nightstand_forest.glb",
		"res://art/props-3d/props/mansion/gothic_nightstand_ivory.glb",
	],
	"gothicWardrobe": [
		"res://art/props-3d/props/mansion/gothic_wardrobe_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_wardrobe_violet.glb",
		"res://art/props-3d/props/mansion/gothic_wardrobe_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_wardrobe_forest.glb",
		"res://art/props-3d/props/mansion/gothic_wardrobe_ivory.glb",
	],
	"gothicDresser": [
		"res://art/props-3d/props/mansion/gothic_dresser_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_dresser_violet.glb",
		"res://art/props-3d/props/mansion/gothic_dresser_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_dresser_forest.glb",
		"res://art/props-3d/props/mansion/gothic_dresser_ivory.glb",
	],
	"gothicVanity": [
		"res://art/props-3d/props/mansion/gothic_vanity_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_violet.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_forest.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_ivory.glb",
	],
	"gothicVanityStool": [
		"res://art/props-3d/props/mansion/gothic_vanity_stool_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_stool_violet.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_stool_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_stool_forest.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_stool_ivory.glb",
	],
	"gothicBedroomBench": [
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_violet.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_forest.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_ivory.glb",
	],
	"gothicBedroomRug": [
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_violet.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_forest.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_ivory.glb",
	],
	"gothicBedsideCandelabra": [
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_violet.glb",
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_forest.glb",
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_ivory.glb",
	],
	"gothicHighbackChair": [
		"res://art/props-3d/props/mansion/gothic_highback_chair_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_highback_chair_violet.glb",
		"res://art/props-3d/props/mansion/gothic_highback_chair_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_highback_chair_forest.glb",
		"res://art/props-3d/props/mansion/gothic_highback_chair_ivory.glb",
	],
	"mansionConsoleTable": ["res://art/props-3d/props/mansion/mansion_console_table.glb"],
	"mansionGrandfatherClock": ["res://art/props-3d/props/mansion/mansion_grandfather_clock.glb"],
	"mansionCoatRack": ["res://art/props-3d/props/mansion/mansion_coat_rack.glb"],
	"mansionTeaCart": ["res://art/props-3d/props/mansion/mansion_tea_cart.glb"],
	"mansionRockingChair": ["res://art/props-3d/props/mansion/mansion_rocking_chair.glb"],
	"mansionRoomDivider": ["res://art/props-3d/props/mansion/mansion_room_divider.glb"],
	"gothicWritingDesk": ["res://art/props-3d/props/mansion/gothic_writing_desk.glb"],
	"gothicBookcase": ["res://art/props-3d/props/mansion/gothic_bookcase.glb"],
	"gothicPedestalTable": ["res://art/props-3d/props/mansion/gothic_pedestal_table.glb"],
	"gothicFloorCandelabra": ["res://art/props-3d/props/mansion/gothic_floor_candelabra.glb"],
	"gothicCoffinChest": ["res://art/props-3d/props/mansion/gothic_coffin_chest.glb"],
	"normalKitchenCounter": ["res://art/props-3d/props/mansion/normal_kitchen_counter.glb"],
	"normalKitchenSink": ["res://art/props-3d/props/mansion/normal_kitchen_sink.glb"],
	"normalKitchenStove": ["res://art/props-3d/props/mansion/normal_kitchen_stove.glb"],
	"normalKitchenFridge": ["res://art/props-3d/props/mansion/normal_kitchen_fridge.glb"],
	"normalKitchenWallCabinet": ["res://art/props-3d/props/mansion/normal_kitchen_wall_cabinet.glb"],
	"normalKitchenIsland": ["res://art/props-3d/props/mansion/normal_kitchen_island.glb"],
	"luxuryKitchenCounter": ["res://art/props-3d/props/mansion/luxury_kitchen_counter.glb"],
	"luxuryKitchenSink": ["res://art/props-3d/props/mansion/luxury_kitchen_sink.glb"],
	"luxuryKitchenStove": ["res://art/props-3d/props/mansion/luxury_kitchen_stove.glb"],
	"luxuryKitchenFridge": ["res://art/props-3d/props/mansion/luxury_kitchen_fridge.glb"],
	"luxuryKitchenWallCabinet": ["res://art/props-3d/props/mansion/luxury_kitchen_wall_cabinet.glb"],
	"luxuryKitchenIsland": ["res://art/props-3d/props/mansion/luxury_kitchen_island.glb"],
	"gothicKitchenCounter": ["res://art/props-3d/props/mansion/gothic_kitchen_counter.glb"],
	"gothicKitchenSink": ["res://art/props-3d/props/mansion/gothic_kitchen_sink.glb"],
	"gothicKitchenStove": ["res://art/props-3d/props/mansion/gothic_kitchen_stove.glb"],
	"gothicKitchenFridge": ["res://art/props-3d/props/mansion/gothic_kitchen_fridge.glb"],
	"gothicKitchenWallCabinet": ["res://art/props-3d/props/mansion/gothic_kitchen_wall_cabinet.glb"],
	"gothicKitchenIsland": ["res://art/props-3d/props/mansion/gothic_kitchen_island.glb"],
	"normalBookcase": ["res://art/props-3d/props/mansion/normal_bookcase.glb"],
	"normalCoffeeTable": ["res://art/props-3d/props/mansion/normal_coffee_table.glb"],
	"normalTvConsole": ["res://art/props-3d/props/mansion/normal_tv_console.glb"],
	"normalEntryBench": ["res://art/props-3d/props/mansion/normal_entry_bench.glb"],
	"mansionDisplayCabinet": ["res://art/props-3d/props/mansion/mansion_display_cabinet.glb"],
	"mansionChaiseLounge": ["res://art/props-3d/props/mansion/mansion_chaise_lounge.glb"],
	"mansionUprightPiano": ["res://art/props-3d/props/mansion/mansion_upright_piano.glb"],
	"mansionBustPedestal": ["res://art/props-3d/props/mansion/mansion_bust_pedestal.glb"],

	"sandCastle": ["res://art/props-3d/props/beach/sand_castle.glb"],
	"beachUmbrella": ["res://art/props-3d/props/beach/beach_umbrella.glb"],
	"tikiBar": ["res://art/props-3d/props/beach/tiki_bar.glb"],
	"beachChair": ["res://art/props-3d/props/beach/beach_chair.glb"],
	"surfboardRack": ["res://art/props-3d/props/beach/surfboard_rack.glb"],
	"palmTree": ["res://art/props-3d/props/beach/palm_tree.glb"],
	"frozenBeachHut": ["res://art/props-3d/props/beach/frozen_beach_hut.glb"],
	"frozenTidelinePool": [
		"res://art/props-3d/props/beach/frozen_tideline_pool.glb",
	],

	"carnivalTicketBooth": [
		"res://art/props-3d/props/carnival/carnival_ticket_booth.glb",
	],
	"popcornCart": ["res://art/props-3d/props/carnival/popcorn_cart.glb"],
	"ringTossStall": ["res://art/props-3d/props/carnival/ring_toss_stall.glb"],
	"strengthTester": ["res://art/props-3d/props/carnival/strength_tester.glb"],
	"circusPedestal": ["res://art/props-3d/props/carnival/circus_pedestal.glb"],
	# the other playable booths (CarnivalBooths) reuse a stall / pedestal body; their game board is the booth node's (docs/CARNIVAL_BOOTHS.md)
	"shootingGallery": ["res://art/props-3d/props/carnival/ring_toss_stall.glb"],
	"whackAMole": ["res://art/props-3d/props/carnival/ring_toss_stall.glb"],
	"duckPond": ["res://art/props-3d/props/carnival/circus_pedestal.glb"],
	"carouselCenterpiece": [
		"res://art/props-3d/props/carnival/carousel_centerpiece.glb",
	],

	"lavaVent": ["res://art/props-3d/props/nether/lava_vent.glb"],
	"emberBrazier": ["res://art/props-3d/props/nether/ember_brazier.glb"],
	"basaltPillar": ["res://art/props-3d/props/nether/basalt_pillar.glb"],
	"basaltRubble": ["res://art/props-3d/props/nether/basalt_rubble.glb"],
	"magmaCrystalCluster": [
		"res://art/props-3d/props/nether/magma_crystal_cluster.glb",
	],
	"infernoAltar": ["res://art/props-3d/props/nether/inferno_altar.glb"],
	"infernoChainLantern": [
		"res://art/props-3d/props/nether/inferno_chain_lantern.glb",
	],
	"lavaPipeManifold": [
		"res://art/props-3d/props/nether/lava_pipe_manifold.glb",
	],
	"charredSupplyCrate": [
		"res://art/props-3d/props/nether/charred_supply_crate.glb",
	],
	"prisonCellGate": ["res://art/props-3d/props/prison/prison_cell_gate.glb"],
	# the sewer under the maze (tools/props/rebuild_hytale_props.py SEWER_BUILDERS)
	"sewerLadder": ["res://art/props-3d/props/sewer/sewer_ladder.glb"],
	"sewerLadderTop": ["res://art/props-3d/props/sewer/sewer_ladder_top.glb"],
	"sewerManhole": ["res://art/props-3d/props/sewer/manhole_frame.glb"],
	"sewerFloorGrate": ["res://art/props-3d/props/sewer/sewer_floor_grate.glb"],
	"sewerValveWheel": ["res://art/props-3d/props/sewer/sewer_valve_wheel.glb"],
	"sewerPump": ["res://art/props-3d/props/sewer/sewer_pump.glb"],
	"sewerPipeRun": ["res://art/props-3d/props/sewer/sewer_pipe_run.glb"],
	"sewerOverflowGrate": ["res://art/props-3d/props/sewer/sewer_overflow_grate.glb"],
	"sewerLamp": ["res://art/props-3d/props/sewer/sewer_lamp.glb"],
	"sewerBridge": ["res://art/props-3d/props/sewer/sewer_bridge.glb"],
	"sewerGrateDeck": ["res://art/props-3d/props/sewer/sewer_grate_deck.glb"],
	"prisonBunk": ["res://art/props-3d/props/prison/prison_bunk.glb"],
	"prisonCafeteriaTable": [
		"res://art/props-3d/props/prison/prison_cafeteria_table.glb",
	],
	"prisonServingCounter": [
		"res://art/props-3d/props/prison/prison_serving_counter.glb",
	],
	"prisonTrayReturn": [
		"res://art/props-3d/props/prison/prison_tray_return.glb",
	],
	"prisonKitchenRack": [
		"res://art/props-3d/props/prison/prison_kitchen_rack.glb",
	],
	"dungeonCage": ["res://art/props-3d/props/prison/dungeon_cage.glb"],
	"restraintChair": ["res://art/props-3d/props/prison/restraint_chair.glb"],
	## Hospital, research lab and greenhouse region props: authored only as blocky models
	## (tools/props/blocky_props_regions.py), so their catalogue entry is the blocky GLB itself.
	"hospitalBed": ["res://art/props-3d/props/blocky/hospitalBed_0.glb", "res://art/props-3d/props/blocky/hospitalBed_1.glb", "res://art/props-3d/props/blocky/hospitalBed_2.glb"],
	"hospitalCurtain": ["res://art/props-3d/props/blocky/hospitalCurtain_0.glb", "res://art/props-3d/props/blocky/hospitalCurtain_1.glb", "res://art/props-3d/props/blocky/hospitalCurtain_2.glb"],
	"ivDripStand": ["res://art/props-3d/props/blocky/ivDripStand.glb"],
	"vitalsMonitor": ["res://art/props-3d/props/blocky/vitalsMonitor.glb"],
	"nursesStation": ["res://art/props-3d/props/blocky/nursesStation_0.glb", "res://art/props-3d/props/blocky/nursesStation_1.glb"],
	"waitingChairs": ["res://art/props-3d/props/blocky/waitingChairs_0.glb", "res://art/props-3d/props/blocky/waitingChairs_1.glb", "res://art/props-3d/props/blocky/waitingChairs_2.glb"],
	"operatingTable": ["res://art/props-3d/props/blocky/operatingTable.glb"],
	"surgicalLight": ["res://art/props-3d/props/blocky/surgicalLight.glb"],
	"instrumentTrolley": ["res://art/props-3d/props/blocky/instrumentTrolley.glb"],
	"morgueCabinet": ["res://art/props-3d/props/blocky/morgueCabinet.glb"],
	"autopsyTable": ["res://art/props-3d/props/blocky/autopsyTable.glb"],
	"pharmacyShelf": ["res://art/props-3d/props/blocky/pharmacyShelf.glb"],
	"xrayMachine": ["res://art/props-3d/props/blocky/xrayMachine.glb"],
	"xrayLightbox": ["res://art/props-3d/props/blocky/xrayLightbox.glb"],
	"medicalSupplyRack": ["res://art/props-3d/props/blocky/medicalSupplyRack.glb"],
	"wheelchair": ["res://art/props-3d/props/blocky/wheelchair_0.glb", "res://art/props-3d/props/blocky/wheelchair_1.glb", "res://art/props-3d/props/blocky/wheelchair_2.glb"],
	"hospitalWardSign": ["res://art/props-3d/props/blocky/hospitalWardSign_0.glb", "res://art/props-3d/props/blocky/hospitalWardSign_1.glb", "res://art/props-3d/props/blocky/hospitalWardSign_2.glb"],
	"labBench": ["res://art/props-3d/props/blocky/labBench.glb"],
	"fumeHood": ["res://art/props-3d/props/blocky/fumeHood.glb"],
	"specimenTank": ["res://art/props-3d/props/blocky/specimenTank_0.glb", "res://art/props-3d/props/blocky/specimenTank_1.glb", "res://art/props-3d/props/blocky/specimenTank_2.glb"],
	"containmentCell": ["res://art/props-3d/props/blocky/containmentCell.glb"],
	"labCoolingUnit": ["res://art/props-3d/props/blocky/labCoolingUnit.glb"],
	"controlConsole": ["res://art/props-3d/props/blocky/controlConsole.glb"],
	"monitorWall": ["res://art/props-3d/props/blocky/monitorWall.glb"],
	"divePod": ["res://art/props-3d/props/blocky/divePod.glb"],
	"divePodFilm": ["res://art/props-3d/props/blocky/divePodFilm.glb"],
	"divePodLit": ["res://art/props-3d/props/blocky/divePodLit.glb"],
	"diveHeadsetStand": ["res://art/props-3d/props/blocky/diveHeadsetStand.glb"],
	"diveHeadsetShelf": ["res://art/props-3d/props/blocky/diveHeadsetShelf.glb"],
	"diveConsole": ["res://art/props-3d/props/blocky/diveConsole.glb"],
	"deconShower": ["res://art/props-3d/props/blocky/deconShower.glb"],
	"coldStorageUnit": ["res://art/props-3d/props/blocky/coldStorageUnit.glb"],
	"labWhiteboard": ["res://art/props-3d/props/blocky/labWhiteboard.glb"],
	"hazardSign": ["res://art/props-3d/props/blocky/hazardSign_0.glb", "res://art/props-3d/props/blocky/hazardSign_1.glb"],
	"labGlassPartition": ["res://art/props-3d/props/blocky/labGlassPartition.glb"],
	"labStool": ["res://art/props-3d/props/blocky/labStool_0.glb", "res://art/props-3d/props/blocky/labStool_1.glb", "res://art/props-3d/props/blocky/labStool_2.glb"],
	"labMicroscope": ["res://art/props-3d/props/blocky/labMicroscope.glb"],
	"gasCylinderRack": ["res://art/props-3d/props/blocky/gasCylinderRack.glb"],
	"biohazardBin": ["res://art/props-3d/props/blocky/biohazardBin.glb"],
	"raisedPlanter": ["res://art/props-3d/props/blocky/raisedPlanter_0.glb", "res://art/props-3d/props/blocky/raisedPlanter_1.glb", "res://art/props-3d/props/blocky/raisedPlanter_2.glb"],
	"pottingBench": ["res://art/props-3d/props/blocky/pottingBench_0.glb", "res://art/props-3d/props/blocky/pottingBench_1.glb", "res://art/props-3d/props/blocky/pottingBench_2.glb"],
	"pottedPalm": ["res://art/props-3d/props/blocky/pottedPalm_0.glb", "res://art/props-3d/props/blocky/pottedPalm_1.glb", "res://art/props-3d/props/blocky/pottedPalm_2.glb"],
	"bananaPlant": ["res://art/props-3d/props/blocky/bananaPlant_0.glb", "res://art/props-3d/props/blocky/bananaPlant_1.glb"],
	"saguaroCactus": ["res://art/props-3d/props/blocky/saguaroCactus.glb"],
	"cactusCluster": ["res://art/props-3d/props/blocky/cactusCluster.glb"],
	"seedlingRack": ["res://art/props-3d/props/blocky/seedlingRack.glb"],
	"irrigationManifold": ["res://art/props-3d/props/blocky/irrigationManifold_0.glb", "res://art/props-3d/props/blocky/irrigationManifold_1.glb", "res://art/props-3d/props/blocky/irrigationManifold_2.glb"],
	"mistingPost": ["res://art/props-3d/props/blocky/mistingPost.glb"],
	"overgrowthPatch": ["res://art/props-3d/props/blocky/overgrowthPatch.glb"],
	"hangingVines": ["res://art/props-3d/props/blocky/hangingVines_0.glb", "res://art/props-3d/props/blocky/hangingVines_1.glb"],
	"domeFountain": ["res://art/props-3d/props/blocky/domeFountain.glb"],
	"wateringCart": ["res://art/props-3d/props/blocky/wateringCart.glb"],
	"greenhouseBench": ["res://art/props-3d/props/blocky/greenhouseBench_0.glb", "res://art/props-3d/props/blocky/greenhouseBench_1.glb", "res://art/props-3d/props/blocky/greenhouseBench_2.glb"],
	"compostBins": ["res://art/props-3d/props/blocky/compostBins_0.glb", "res://art/props-3d/props/blocky/compostBins_1.glb"],
	## Shopping arcade props (tools/props/blocky_props_mall.py), blocky-only like the region props above.
	"shopShelf": ["res://art/props-3d/props/blocky/shopShelf_0.glb", "res://art/props-3d/props/blocky/shopShelf_1.glb", "res://art/props-3d/props/blocky/shopShelf_2.glb"],
	"shopFridge": ["res://art/props-3d/props/blocky/shopFridge_0.glb", "res://art/props-3d/props/blocky/shopFridge_1.glb"],
	"checkoutCounter": ["res://art/props-3d/props/blocky/checkoutCounter_0.glb", "res://art/props-3d/props/blocky/checkoutCounter_1.glb", "res://art/props-3d/props/blocky/checkoutCounter_2.glb"],
	"displayCase": ["res://art/props-3d/props/blocky/displayCase_0.glb", "res://art/props-3d/props/blocky/displayCase_1.glb", "res://art/props-3d/props/blocky/displayCase_2.glb"],
	"coffeeStation": ["res://art/props-3d/props/blocky/coffeeStation_0.glb", "res://art/props-3d/props/blocky/coffeeStation_1.glb"],
	"donutFryer": ["res://art/props-3d/props/blocky/donutFryer.glb"],
	"bakeryRack": ["res://art/props-3d/props/blocky/bakeryRack_0.glb", "res://art/props-3d/props/blocky/bakeryRack_1.glb", "res://art/props-3d/props/blocky/bakeryRack_2.glb"],
	"dinerStool": ["res://art/props-3d/props/blocky/dinerStool_0.glb", "res://art/props-3d/props/blocky/dinerStool_1.glb", "res://art/props-3d/props/blocky/dinerStool_2.glb"],
	"dinerBooth": ["res://art/props-3d/props/blocky/dinerBooth_0.glb", "res://art/props-3d/props/blocky/dinerBooth_1.glb", "res://art/props-3d/props/blocky/dinerBooth_2.glb"],
	"menuBoard": ["res://art/props-3d/props/blocky/menuBoard_0.glb", "res://art/props-3d/props/blocky/menuBoard_1.glb", "res://art/props-3d/props/blocky/menuBoard_2.glb"],
	"donutSign": ["res://art/props-3d/props/blocky/donutSign_0.glb", "res://art/props-3d/props/blocky/donutSign_1.glb"],
	"washingMachine": ["res://art/props-3d/props/blocky/washingMachine_0.glb", "res://art/props-3d/props/blocky/washingMachine_1.glb", "res://art/props-3d/props/blocky/washingMachine_2.glb"],
	"dryerStack": ["res://art/props-3d/props/blocky/dryerStack_0.glb", "res://art/props-3d/props/blocky/dryerStack_1.glb"],
	"flowerStand": ["res://art/props-3d/props/blocky/flowerStand_0.glb", "res://art/props-3d/props/blocky/flowerStand_1.glb"],
	"barberChair": ["res://art/props-3d/props/blocky/barberChair_0.glb", "res://art/props-3d/props/blocky/barberChair_1.glb", "res://art/props-3d/props/blocky/barberChair_2.glb"],
	"barberStation": ["res://art/props-3d/props/blocky/barberStation_0.glb", "res://art/props-3d/props/blocky/barberStation_1.glb"],
	"clothesRack": ["res://art/props-3d/props/blocky/clothesRack_0.glb", "res://art/props-3d/props/blocky/clothesRack_1.glb", "res://art/props-3d/props/blocky/clothesRack_2.glb"],
	"tvWall": ["res://art/props-3d/props/blocky/tvWall_0.glb", "res://art/props-3d/props/blocky/tvWall_1.glb", "res://art/props-3d/props/blocky/tvWall_2.glb"],
	"cinemaSeats": ["res://art/props-3d/props/blocky/cinemaSeats_0.glb", "res://art/props-3d/props/blocky/cinemaSeats_1.glb"],
	"cinemaScreen": ["res://art/props-3d/props/blocky/cinemaScreen_0.glb", "res://art/props-3d/props/blocky/cinemaScreen_1.glb"],
	"ticketBooth": ["res://art/props-3d/props/blocky/ticketBooth_0.glb", "res://art/props-3d/props/blocky/ticketBooth_1.glb", "res://art/props-3d/props/blocky/ticketBooth_2.glb"],
	"concessionCounter": ["res://art/props-3d/props/blocky/concessionCounter_0.glb", "res://art/props-3d/props/blocky/concessionCounter_1.glb"],
	"foodCourtTable": ["res://art/props-3d/props/blocky/foodCourtTable_0.glb", "res://art/props-3d/props/blocky/foodCourtTable_1.glb", "res://art/props-3d/props/blocky/foodCourtTable_2.glb"],
	"mallPlanter": ["res://art/props-3d/props/blocky/mallPlanter_0.glb", "res://art/props-3d/props/blocky/mallPlanter_1.glb", "res://art/props-3d/props/blocky/mallPlanter_2.glb"],
	"mallBench": ["res://art/props-3d/props/blocky/mallBench_0.glb", "res://art/props-3d/props/blocky/mallBench_1.glb"],
}

## Highest local point of ceiling-hung models. Their exported origins stay in
## the same floor-based convention as every other prop, so this offset seats
## that authored top exactly against the 3 m corridor ceiling.
const CEILING_MODEL_TOP := {
	"diningChandelier": .90,
	"ceilingLight": .30,
	"ceilingFan": .59,
	"infernoChainLantern": 1.59,
	"surgicalLight": .90,
	"hangingVines": 1.25,
}

## Actual light emission stays runtime-authored so the shipping GLBs remain
## lightweight and the same fixture variants can share performance limits.
## Energy/range are intentionally modest: fixtures illuminate a room without
## replacing the player's flashlight or creating one shadow map per prop.
const LIGHT_PROFILES := {
	"floorLamp": {"color": Color("ffe1a3"), "energy": .52, "range": 4.0, "height": 1.52},
	"tableLamp": {"color": Color("ffd99a"), "energy": .38, "range": 3.0, "height": .54},
	"bedsideLamp": {"color": Color("ffd5a0"), "energy": .32, "range": 2.6, "height": .54},
	"ceilingLight": {"color": Color("dff8ff"), "energy": .62, "range": 4.8, "height": .12},
	"ceilingFan": {"color": Color("fff0c2"), "energy": .54, "range": 4.4, "height": .16},
	"diningChandelier": {"color": Color("ffd58c"), "energy": .66, "range": 5.2, "height": .55},
	"wallSconce": {"color": Color("ffd292"), "energy": .36, "range": 3.2, "height": 1.62},
	# dim amber caged bulkheads, far apart: the sewer stays mostly dark
	"sewerLamp": {"color": Color("ffa24a"), "energy": .42, "range": 5.0, "height": 0.0},
	"surgicalLight": {"color": Color("f4fbff"), "energy": .85, "range": 4.6, "height": .2},
	"specimenTank": {"color": Color("5fe8d8"), "energy": .42, "range": 3.0, "height": 1.2},
	# the one dive pod left on: a faint glow, the rest of the pod room stays dark
	"divePodLit": {"color": Color("8fe6f0"), "energy": .18, "range": 2.2, "height": .6},
	"xrayLightbox": {"color": Color("e8f4ff"), "energy": .26, "range": 2.4, "height": 1.5},
	"donutSign": {"color": Color("ff8fc8"), "energy": .38, "range": 3.0, "height": .7},
	"menuBoard": {"color": Color("ffe0b0"), "energy": .24, "range": 2.4, "height": .45},
}

## Coordinated furniture families share the same room id. Hash that room id,
## rather than each prop index independently, so wood furniture, computers,
## and themed bedroom sets never receive mismatched finishes inside one room.
const _CODE_COORDINATED_SET_TYPES := [
	"woodenChair", "woodenChairCushion", "woodenTable",
	"woodenDresserSideboard", "retroComputerCompact",
	"retroComputerTower", "retroComputerDesktop", "retroComputerTerminal",
	ContentRegistry.DATA + ":office",
	"singleBed", "doubleBed", "bedroomNightstand", "bedroomWardrobe",
	"bedroomDresser", "bedroomVanity", "vanityStool", "bedsideLamp",
	"toyChest", "laundryHamper", "bedroomRug", "bedroomWallClock",
	"bedroomBench", "gothicDoubleBed", "gothicNightstand",
	"gothicWardrobe", "gothicDresser", "gothicVanity",
	"gothicVanityStool", "gothicBedroomBench", "gothicBedroomRug",
	"gothicBedsideCandelabra", "gothicHighbackChair",
]

## Variant labels are kept beside their ordered paths so validators and future
## UI can reason about a room's actual finish instead of filename substrings.
## Families with the same four/six labels deliberately share ordering: hashing
## one room id therefore gives every member of a given four- or six-variant
## family the same indexed finish even when their individual prop ids differ.
const _CODE_VARIANT_THEMES := {
	"woodenChair": ["oak", "walnut", "mahogany", "ash"],
	"woodenChairCushion": ["oak", "walnut", "mahogany", "ash"],
	"woodenTable": ["oak", "walnut", "mahogany", "ash"],
	"woodenDresserSideboard": ["oak", "walnut", "mahogany", "ash"],
	"retroComputerCompact": ["ivory", "charcoal", "teal", "burgundy"],
	"retroComputerTower": ["ivory", "charcoal", "teal", "burgundy"],
	"retroComputerDesktop": ["ivory", "charcoal", "teal", "burgundy"],
	"retroComputerTerminal": ["ivory", "charcoal", "teal", "burgundy"],
	"officeDesk": ContentRegistry.DATA,
	"officeChair": ContentRegistry.DATA,
	"officeCrtSecurityConsole": ContentRegistry.DATA,
	"officeCubiclePartition": ContentRegistry.DATA,
	"officePrinter": ContentRegistry.DATA,
	"officeWaterCooler": ContentRegistry.DATA,
	"officePhotocopier": ContentRegistry.DATA,
	"officeShredder": ContentRegistry.DATA,
	"officeFileBoxes": ContentRegistry.DATA,
	"officeCornerWorkstation": ContentRegistry.DATA,
	"singleBed": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"doubleBed": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomNightstand": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomWardrobe": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomDresser": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomVanity": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"vanityStool": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedsideLamp": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"toyChest": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"laundryHamper": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomRug": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomWallClock": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomBench": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
}

## The tables above with their res://data/props entries filled in (`"@data:<family>"` splices a family's coordinated ids).
static var MODEL_PATHS: Dictionary = ContentRegistry.resolve(_CODE_MODEL_PATHS, "props", "models")
static var COORDINATED_SET_TYPES: Array = ContentRegistry.splice(_CODE_COORDINATED_SET_TYPES, "coordinated")
static var VARIANT_THEMES: Dictionary = ContentRegistry.resolve(_CODE_VARIANT_THEMES, "props", "themes")


static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


## Packs changed (ContentRegistry.load_packs / unload_packs): recompute the tables read from the registry.
static func rebuild_from_registry() -> void:
	MODEL_PATHS = ContentRegistry.resolve(_CODE_MODEL_PATHS, "props", "models")
	COORDINATED_SET_TYPES = ContentRegistry.splice(_CODE_COORDINATED_SET_TYPES, "coordinated")
	VARIANT_THEMES = ContentRegistry.resolve(_CODE_VARIANT_THEMES, "props", "themes")


static func has_model(type: String) -> bool:
	return MODEL_PATHS.has(type) and not (MODEL_PATHS[type] as Array).is_empty()


## Thin rugs/mats are visual overlays rather than structural floor. Keeping
## their visible plane one centimetre above the GridMap slab prevents depth
## precision from alternating between both surfaces as the camera moves.
const FLOOR_DRESSING_Y := 0.012
const FLOOR_DRESSING_TYPES := [
	"mansionAreaRug", "corridorCarpet", "hotelCarpet",
	"apartmentCarpet", "beachMat", "bedroomRug", "gothicBedroomRug",
	"houseBathMat", "arcadeCarpetCircle", "arcadeCarpetRunner",
	"frozenTidelinePool", "overgrowthPatch",
]
const EMPTY_FRAME_TYPES := [
	"normalPictureFrameEmpty", "normalPaintingFrameEmpty",
	"luxuryPictureFrameEmpty", "luxuryPaintingFrameEmpty",
	"gothicPictureFrameEmpty", "gothicPaintingFrameEmpty",
]
const ROOM_DOOR_TYPES := [
	"normalRoomDoor", "luxuryRoomDoor", "gothicRoomDoor",
	"normalDoubleRoomDoor", "luxuryDoubleRoomDoor", "gothicDoubleRoomDoor",
]
const WALL_MOUNTED_TYPES := EMPTY_FRAME_TYPES + [
	"bathroomMirror", "framedWallPortrait", "bedroomWallClock",
	"publicHandDryer", "publicSoapDispenser", "publicPaperTowelDispenser",
	"publicBabyChangeStation", "publicMensRoomSign", "publicWomensRoomSign",
	"houseMedicineCabinet", "houseTowelRack", "houseBathroomShelf",
	"xrayLightbox", "hospitalWardSign", "monitorWall", "labWhiteboard", "diveHeadsetShelf",
	"hazardSign", "menuBoard", "donutSign", "cinemaScreen",
]


## Walkable decks authored with their walking surface at the model origin
## (z = 0 in the builder) and structure hanging below it: spawned at the cell's
## floor height as authored, never seated on their lowest point, so the deck
## top is flush with the floor collider under it (girders reach down into the
## channel trench). Seating the sewer bridge on its bearings raised the deck
## 0.6 m above the walkway and runners walked through it.
const DECK_TYPES := ["sewerBridge", "sewerGrateDeck"]


static func keeps_authored_pivot(type: String) -> bool:
	return DECK_TYPES.has(type)


static func is_floor_dressing(type: String) -> bool:
	return FLOOR_DRESSING_TYPES.has(type)


static func is_empty_frame(type: String) -> bool:
	return EMPTY_FRAME_TYPES.has(type)


static func is_wall_mounted(type: String) -> bool:
	return WALL_MOUNTED_TYPES.has(type)


static func is_room_door(type: String) -> bool:
	return ROOM_DOOR_TYPES.has(type)


static func is_ceiling_mounted(type: String) -> bool:
	return CEILING_MODEL_TOP.has(type)


static func light_profile(type: String) -> Dictionary:
	return (LIGHT_PROFILES.get(type, {}) as Dictionary).duplicate()


## Authored Blender props present their usable/front side along local +Z after
## glTF conversion. Gameplay uses -Z as forward, so the visual root needs a
## half turn to face into the room instead of back into its supporting wall.
static func authored_visual_yaw(gameplay_yaw: float) -> float:
	return gameplay_yaw + PI


## Region finishes (docs/MANSION_LUXURY.md): the mansion gets its own looks of the ordinary furniture types (lacquer,
## marble tops, velvet, gilt), built as "<type>Mansion" model sets with the same footprints. The type names stay the
## same, so sizes, colliders, surfaces, hiding spots and room rules all apply unchanged.
const REGION_FINISHES := {"mansion": "Mansion"}
## Switch for before/after captures (tools/look/mansion_rooms.gd).
static var use_region_finishes := true


static func region_finish(region: String) -> String:
	return String(REGION_FINISHES.get(region, ""))


static func model_path(type: String, instance_id: String,
		room_id: String = "", finish: String = "") -> String:
	var paths: Array = MODEL_PATHS.get(type, [])
	if paths.is_empty():
		return ""
	if not ContentRegistry.pack_of("props", type).is_empty():
		return String(paths[_variant_index(type, instance_id, room_id, paths.size())])
	if USE_BLOCKY_PROPS and use_region_finishes and not finish.is_empty() and BlockyPropModels.MODELS.has(type + finish):
		var finished: Array = BlockyPropModels.MODELS[type + finish]
		return String(finished[_variant_index(type, instance_id, room_id, finished.size())])
	if USE_BLOCKY_PROPS and BlockyPropModels.MODELS.has(type):
		var blocky: Array = BlockyPropModels.MODELS[type]
		return String(blocky[_variant_index(type, instance_id, room_id, blocky.size())])
	return String(paths[_variant_index(type, instance_id, room_id, paths.size())])


static func variant_theme(type: String, instance_id: String,
		room_id: String = "") -> String:
	var labels: Array = VARIANT_THEMES.get(type, [])
	if labels.is_empty():
		return ""
	return String(labels[_variant_index(type, instance_id, room_id, labels.size())])


static func _variant_index(type: String, instance_id: String,
		room_id: String, size: int) -> int:
	var variant_key := room_id if not room_id.is_empty() else instance_id
	if room_id.is_empty() and COORDINATED_SET_TYPES.has(type) \
			and instance_id.contains("-prop-"):
		variant_key = instance_id.get_slice("-prop-", 0)
	return _stable_index(variant_key, size)


static func visual_y(type: String, wall_height: float, mount_y: float = 0.0) -> float:
	if mount_y > 0.0:
		return mount_y
	if is_floor_dressing(type):
		return FLOOR_DRESSING_Y
	if is_wall_mounted(type):
		return wall_height * .42
	if CEILING_MODEL_TOP.has(type):
		return wall_height - float(CEILING_MODEL_TOP[type])
	return 0.0



## Whether the view may batch repeated placements of `type` into one MultiMesh (docs/DATA_DRIVEN_CONTENT.md).
## A prop's data `batchable` wins; otherwise pure dressing is batchable, doors and anything with an interaction are not.
static func is_batchable(type: String) -> bool:
	var def := ContentRegistry.get_def("props", type)
	if def.has("batchable"):
		return bool(def["batchable"])
	return interaction_for(type).is_empty() and not is_room_door(type)


## Turn decorative furniture into a gameplay surface without coupling the
## generator to model filenames. An empty result remains ordinary dressing.
## Hunter-scale rescale (docs/SEATING.md, docs/SCALE_FIT.md): the world is built for a 2.67 m hunter, and these models were
## authored person-sized. ModelSlot.instantiate_prop scales their children by this factor, so the view, the collider
## emitter (PropColliderSizes) and every audit see the same scaled model. Seats, benches, sofas and stools all scale.
const HUNTER_SCALE := {
	# seats (every chair, stool, bench and sofa you can sit on): seat pans end up about 0.45 m x 1.5
	"barberChair": 1.5, "beachChair": 1.5, "dinerStool": 1.5, "diningChair": 1.5, "diningChairCushion": 1.5,
	"gothicBedroomBench": 1.5, "gothicHighbackChair": 1.5, "greenhouseBench": 1.5, "labStool": 1.5, "loungeCouch": 1.5,
	"loungeCouchWide": 1.5, "mallBench": 1.5, "officeChair": 1.5, "publicShowerBench": 1.5, "waitingChairs": 1.5,
	"wheelchair": 1.5, "woodenChair": 1.5, "woodenChairCushion": 1.5, "dinerBooth": 1.5,
	# beds (the gothic canopy stops at 1.48 so it stays under the hunter-scale bed length)
	"bunkBed": 1.5, "doubleBed": 1.5, "gothicDoubleBed": 1.48, "hospitalBed": 1.5, "prisonBunk": 1.5, "singleBed": 1.5,
	# counters, kitchens, sinks
	"bathroomSink": 1.5, "bathroomVanity": 1.5, "bedroomDresser": 1.5, "checkoutCounter": 1.5, "concessionCounter": 1.5,
	"diningSideboard": 1.5, "luxuryKitchenCounter": 1.5, "luxuryKitchenIsland": 1.5, "luxuryKitchenSink": 1.5,
	"luxuryKitchenStove": 1.5, "normalKitchenCounter": 1.5, "normalKitchenIsland": 1.5, "normalKitchenSink": 1.5,
	"normalKitchenStove": 1.5, "prisonServingCounter": 1.5, "receptionDesk": 1.5, "woodenDresserSideboard": 1.5,
	"normalCoffeeTable": 1.5,
	# storage, lamps, bathrooms
	"clothesRack": 1.5, "filingCabinet": 1.5, "gasCylinderRack": 1.5, "surfboardRack": 1.5, "floorLamp": 1.5,
	"gothicFloorCandelabra": 1.5, "deconShower": 1.5, "houseShowerEnclosure": 1.5, "publicMensShowerStall": 1.5,
	"publicWomensShowerStall": 1.5, "houseToilet": 1.5, "publicRestroomToilet": 1.5, "publicMensUrinal": 1.5,
}
## Multi-seat furniture: this many separate sit points side by side along the prop's width, each its own interactable
## (its own prompt and camera, picked by aim), and each a seat a hunter can take. Anything not listed is one seat.
const SEAT_COUNTS := {"dinerBooth": 4, "waitingChairs": 3, "loungeCouch": 2, "loungeCouchWide": 3, "mallBench": 2, "greenhouseBench": 2,
	"gothicBedroomBench": 2, "publicShowerBench": 2}


static func hunter_scale(type: String) -> float:
	return float(HUNTER_SCALE.get(type, 1.0))


## Props whose seats sit in rows facing each other instead of one row facing out: per row, its centre along the prop's
## local z as a fraction of the depth (gameplay frame: -Z is the prop's front) and the turn from the prop's yaw it faces
## (0 = out of the front, PI = toward the back). The diner booth's two benches face each other across its table.
const SEAT_ROWS := {"dinerBooth": [{"z": .36, "turn": 0.0}, {"z": -.36, "turn": PI}]}


static func seat_count(type: String) -> int:
	return int(SEAT_COUNTS.get(type, 1)) if interaction_for(type) == "sit" else 1


## Sit points of a sit prop `size` big, in its gameplay-local frame: [{"x", "z", "turn", "width", "exit"}]. One row of
## seat_count seats across the width by default, each `width` wide, facing out (turn 0); SEAT_ROWS props split them over
## their rows. "exit" is the local direction you get up toward: out of the front, or out of the nearer open end of a
## booth bench.
static func seat_points(type: String, size: Vector3) -> Array:
	var rows: Array = SEAT_ROWS.get(type, [{"z": 0.0, "turn": 0.0}])
	var per_row := maxi(1, seat_count(type) / rows.size())
	var out := []
	for row_value in rows:
		var row: Dictionary = row_value
		for i in per_row:
			var x := (float(i) + .5) / float(per_row) * size.x - size.x * .5
			var exit := Vector2(0, -1).rotated(-float(row["turn"])) if rows.size() == 1 else Vector2(signf(x) if x != 0.0 else 1.0, 0)
			out.append({"x": x, "z": float(row["z"]) * size.z, "turn": float(row["turn"]), "width": size.x / float(per_row), "exit": exit})
	return out


## Seat centres along a single-row sit prop's local x (kept for callers that only need the row).
static func seat_offsets(type: String, width: float) -> Array:
	var out := []
	for point in seat_points(type, Vector3(width, 1.0, 1.0)):
		out.append(float(point["x"]))
	return out


static func interaction_for(type: String) -> String:
	var lowered := type.to_lower()
	if type == "carouselCenterpiece":
		return "ride"
	if CarnivalBooths.is_booth(type):
		return "play"
	if type.begins_with("retroComputer"):
		return "use"
	if "mirror" in lowered and type != "standingMirror":   # the working-mirror surface is sized for wall mirrors
		return "mirror"
	if type == "dinerBooth":
		return "sit"    # two benches facing across the table, two seats each (SEAT_ROWS)
	if type in ["labBench", "pottingBench"]:
		return ""   # work benches, not seats
	if type in ["controlConsole", "nursesStation", "diveConsole"]:
		return "use"
	# beds are the types that end in "Bed" (and bunks); "bedroomNightstand", "bedroomWardrobe" and "bedroomBench" are not
	if lowered.ends_with("bed") or "bunk" in lowered:
		return "lay"
	for word in ["chair", "couch", "bench", "stool", "sofa"]:
		if word in lowered:
			return "sit"
	return ""


static func _stable_index(value: String, size: int) -> int:
	var result := 0
	for byte in value.to_utf8_buffer():
		result = (result * 31 + int(byte)) & 0x7fffffff
	return result % maxi(1, size)
