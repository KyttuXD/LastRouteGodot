extends RefCounted

## Props as data (docs/DATA_DRIVEN_CONTENT.md): every res://data/props family passes the schema, every model it names
## exists, finishes line up with models, the office pilot is exactly the catalog constants it replaced (paths, finishes,
## coordinated-set order), and the parity fingerprint is printed for the before/after comparison.
##
##   godot --headless --path . res://scenes/validate.tscn -- data_props

const Parity := preload("res://scripts/data_parity.gd")

const OFFICE := ["officeDesk", "officeChair", "officeCrtSecurityConsole", "officeCubiclePartition", "officePrinter",
	"officeWaterCooler", "officePhotocopier", "officeShredder", "officeFileBoxes", "officeCornerWorkstation"]
const OFFICE_FILES := ["office_desk", "office_task_chair", "office_crt_security_console", "office_cubicle_partition",
	"office_printer", "office_water_cooler", "office_photocopier", "office_shredder", "office_file_boxes",
	"office_corner_workstation"]

## Props as they were in PropModelCatalog before moving to data/props (DATA migration; one claim per commit).
const FROZEN_KEYS := ["mansionMarbleColumn", "mansionPorcelainVase", "ivStand", "medicalCart", "readingTable", "libraryGlobe", "storageBarrel", "storageShelving", "receptionDesk", "pottedPlant", "standingMirror", "arcadeCabinet", "arcadeCabinetCyanMagenta", "filingCabinet", "officeDesk", "officeChair", "officeCrtSecurityConsole", "officeCubiclePartition", "officePrinter", "officeWaterCooler", "officePhotocopier", "officeShredder", "officeFileBoxes", "officeCornerWorkstation", "arcadeBasketballHoop", "arcadeCarpetCircle", "arcadeCarpetRunner", "arcadeTokenChanger", "backstageRepairStand", "breakerCabinet", "brokenAquarium", "carnivalCarousel", "flowerBlue", "flowerRose", "flowerSun", "flowerViolet", "gardenPlanterBench", "giantTree", "grassFern", "locker", "maintenanceCleaningCart", "maintenanceToolCabinet", "mascotStatue", "prizeClawMachine", "prizeCounter", "snackKiosk", "stagePlatform", "stageSpeaker", "utilityCart", "floorLamp", "ceilingLight", "ceilingFan", "tableLamp", "loungeCouch", "loungeCouchWide", "privacyCurtain", "serverRack", "supplyCrates", "trashBin", "vendingMachine", "woodenChair", "woodenChairCushion", "woodenTable", "restaurantPartyTable", "woodenDresserSideboard", "retroComputerCompact", "retroComputerTower", "retroComputerDesktop", "retroComputerTerminal", "diningTable", "diningChair", "diningChairCushion", "diningChandelier", "diningSideboard", "flowerCenterpiece", "framedWallPortrait", "normalPictureFrameEmpty", "normalPaintingFrameEmpty", "luxuryPictureFrameEmpty", "luxuryPaintingFrameEmpty", "gothicPictureFrameEmpty", "gothicPaintingFrameEmpty", "normalRoomDoor", "luxuryRoomDoor", "gothicRoomDoor", "normalDoubleRoomDoor", "luxuryDoubleRoomDoor", "gothicDoubleRoomDoor", "heavyMansionDrapes", "mansionAreaRug", "corridorCarpet", "hotelCarpet", "apartmentCarpet", "beachMat", "mansionBookshelf", "mansionFireplace", "magazineRack", "tableCandelabra", "wallSconce", "bathroomStall", "bathroomSink", "bathroomMirror", "bathroomVanity", "publicRestroomToilet", "publicMensUrinal", "publicSinkBank", "publicHandDryer", "publicSoapDispenser", "publicPaperTowelDispenser", "publicBabyChangeStation", "publicSanitaryBin", "publicMensRoomSign", "publicWomensRoomSign", "publicMensShowerStall", "publicWomensShowerStall", "publicShowerBench", "houseBathtub", "houseToilet", "houseShowerEnclosure", "houseMedicineCabinet", "houseTowelRack", "houseBathMat", "houseBathroomShelf", "grandStaircase", "grandFoyerStaircase", "singleBed", "doubleBed", "bunkBed", "bedroomNightstand", "bedroomWardrobe", "bedroomDresser", "bedroomVanity", "vanityStool", "bedsideLamp", "toyChest", "laundryHamper", "bedroomRug", "bedroomWallClock", "bedroomBench", "gothicDoubleBed", "gothicNightstand", "gothicWardrobe", "gothicDresser", "gothicVanity", "gothicVanityStool", "gothicBedroomBench", "gothicBedroomRug", "gothicBedsideCandelabra", "gothicHighbackChair", "mansionConsoleTable", "mansionGrandfatherClock", "mansionCoatRack", "mansionTeaCart", "mansionRockingChair", "mansionRoomDivider", "gothicWritingDesk", "gothicBookcase", "gothicPedestalTable", "gothicFloorCandelabra", "gothicCoffinChest", "normalKitchenCounter", "normalKitchenSink", "normalKitchenStove", "normalKitchenFridge", "normalKitchenWallCabinet", "normalKitchenIsland", "luxuryKitchenCounter", "luxuryKitchenSink", "luxuryKitchenStove", "luxuryKitchenFridge", "luxuryKitchenWallCabinet", "luxuryKitchenIsland", "gothicKitchenCounter", "gothicKitchenSink", "gothicKitchenStove", "gothicKitchenFridge", "gothicKitchenWallCabinet", "gothicKitchenIsland", "normalBookcase", "normalCoffeeTable", "normalTvConsole", "normalEntryBench", "mansionDisplayCabinet", "mansionChaiseLounge", "mansionUprightPiano", "mansionBustPedestal", "sandCastle", "beachUmbrella", "tikiBar", "beachChair", "surfboardRack", "palmTree", "frozenBeachHut", "frozenTidelinePool", "carnivalTicketBooth", "popcornCart", "ringTossStall", "strengthTester", "circusPedestal", "shootingGallery", "whackAMole", "duckPond", "carouselCenterpiece", "lavaVent", "emberBrazier", "basaltPillar", "basaltRubble", "magmaCrystalCluster", "infernoAltar", "infernoChainLantern", "lavaPipeManifold", "charredSupplyCrate", "prisonCellGate", "sewerLadder", "sewerLadderTop", "sewerManhole", "sewerFloorGrate", "sewerValveWheel", "sewerPump", "sewerPipeRun", "sewerOverflowGrate", "sewerLamp", "sewerBridge", "sewerGrateDeck", "prisonBunk", "prisonCafeteriaTable", "prisonServingCounter", "prisonTrayReturn", "prisonKitchenRack", "dungeonCage", "restraintChair", "hospitalBed", "hospitalCurtain", "ivDripStand", "vitalsMonitor", "nursesStation", "waitingChairs", "operatingTable", "surgicalLight", "instrumentTrolley", "morgueCabinet", "autopsyTable", "pharmacyShelf", "xrayMachine", "xrayLightbox", "medicalSupplyRack", "wheelchair", "hospitalWardSign", "labBench", "fumeHood", "specimenTank", "containmentCell", "labCoolingUnit", "controlConsole", "monitorWall", "divePod", "divePodFilm", "divePodLit", "diveHeadsetStand", "diveHeadsetShelf", "diveConsole", "deconShower", "coldStorageUnit", "labWhiteboard", "hazardSign", "labGlassPartition", "labStool", "labMicroscope", "gasCylinderRack", "biohazardBin", "raisedPlanter", "pottingBench", "pottedPalm", "bananaPlant", "saguaroCactus", "cactusCluster", "seedlingRack", "irrigationManifold", "mistingPost", "overgrowthPatch", "hangingVines", "domeFountain", "wateringCart", "greenhouseBench", "compostBins", "shopShelf", "shopFridge", "checkoutCounter", "displayCase", "coffeeStation", "donutFryer", "bakeryRack", "dinerStool", "dinerBooth", "menuBoard", "donutSign", "washingMachine", "dryerStack", "flowerStand", "barberChair", "barberStation", "clothesRack", "tvWall", "cinemaSeats", "cinemaScreen", "ticketBooth", "concessionCounter", "foodCourtTable", "mallPlanter", "mallBench"]
const FROZEN_COORDINATED := ["woodenChair", "woodenChairCushion", "woodenTable", "woodenDresserSideboard", "retroComputerCompact", "retroComputerTower", "retroComputerDesktop", "retroComputerTerminal", "officeDesk", "officeChair", "officeCrtSecurityConsole", "officeCubiclePartition", "officePrinter", "officeWaterCooler", "officePhotocopier", "officeShredder", "officeFileBoxes", "officeCornerWorkstation", "singleBed", "doubleBed", "bedroomNightstand", "bedroomWardrobe", "bedroomDresser", "bedroomVanity", "vanityStool", "bedsideLamp", "toyChest", "laundryHamper", "bedroomRug", "bedroomWallClock", "bedroomBench", "gothicDoubleBed", "gothicNightstand", "gothicWardrobe", "gothicDresser", "gothicVanity", "gothicVanityStool", "gothicBedroomBench", "gothicBedroomRug", "gothicBedsideCandelabra", "gothicHighbackChair"]
const FROZEN_MODELS := {
	"mansionMarbleColumn": ["res://art/props-3d/props/blocky/mansionMarbleColumn.glb"],
	"mansionPorcelainVase": ["res://art/props-3d/props/blocky/mansionPorcelainVase_0.glb", "res://art/props-3d/props/blocky/mansionPorcelainVase_1.glb", "res://art/props-3d/props/blocky/mansionPorcelainVase_2.glb"],
	"ivStand": ["res://art/props-3d/props/blocky/ivStand.glb"],
	"medicalCart": ["res://art/props-3d/props/blocky/medicalCart.glb"],
	"readingTable": ["res://art/props-3d/props/blocky/readingTable_0.glb", "res://art/props-3d/props/blocky/readingTable_1.glb", "res://art/props-3d/props/blocky/readingTable_2.glb"],
	"libraryGlobe": ["res://art/props-3d/props/blocky/libraryGlobe_0.glb", "res://art/props-3d/props/blocky/libraryGlobe_1.glb"],
	"storageBarrel": ["res://art/props-3d/props/blocky/storageBarrel_0.glb", "res://art/props-3d/props/blocky/storageBarrel_1.glb", "res://art/props-3d/props/blocky/storageBarrel_2.glb"],
	"storageShelving": ["res://art/props-3d/props/blocky/storageShelving.glb"],
	"receptionDesk": ["res://art/props-3d/props/blocky/receptionDesk_0.glb", "res://art/props-3d/props/blocky/receptionDesk_1.glb", "res://art/props-3d/props/blocky/receptionDesk_2.glb"],
	"pottedPlant": ["res://art/props-3d/props/blocky/pottedPlant_0.glb", "res://art/props-3d/props/blocky/pottedPlant_1.glb", "res://art/props-3d/props/blocky/pottedPlant_2.glb"],
	"standingMirror": ["res://art/props-3d/props/blocky/standingMirror_0.glb", "res://art/props-3d/props/blocky/standingMirror_1.glb", "res://art/props-3d/props/blocky/standingMirror_2.glb"],
	"arcadeCabinet": ["res://art/props-3d/props/maze/arcade_cabinet_default.glb", "res://art/props-3d/props/maze/arcade_cabinet_amber.glb", "res://art/props-3d/props/maze/arcade_cabinet_burgundy.glb", "res://art/props-3d/props/maze/arcade_cabinet_teal.glb", "res://art/props-3d/props/maze/arcade_cabinet_ultraviolet.glb"],
	"arcadeCabinetCyanMagenta": ["res://art/props-3d/props/maze/arcade_cabinet_cyan_magenta.glb"],
	"filingCabinet": ["res://art/props-3d/props/maze/filing_cabinet.glb"],
	"arcadeBasketballHoop": ["res://art/props-3d/props/maze/arcade_basketball_hoop.glb"],
	"arcadeCarpetCircle": ["res://art/props-3d/props/maze/arcade_carpet_circle.glb"],
	"arcadeCarpetRunner": ["res://art/props-3d/props/maze/arcade_carpet_runner.glb"],
	"arcadeTokenChanger": ["res://art/props-3d/props/maze/arcade_token_changer.glb"],
	"backstageRepairStand": ["res://art/props-3d/props/maze/backstage_repair_stand.glb"],
	"breakerCabinet": ["res://art/props-3d/props/maze/breaker_cabinet.glb"],
	"brokenAquarium": ["res://art/props-3d/props/maze/broken_aquarium.glb"],
	"carnivalCarousel": ["res://art/props-3d/props/maze/carnival_carousel.glb"],
	"flowerBlue": ["res://art/props-3d/props/maze/flower_blue.glb"],
	"flowerRose": ["res://art/props-3d/props/maze/flower_rose.glb"],
	"flowerSun": ["res://art/props-3d/props/maze/flower_sun.glb"],
	"flowerViolet": ["res://art/props-3d/props/maze/flower_violet.glb"],
	"gardenPlanterBench": ["res://art/props-3d/props/maze/garden_planter_bench.glb"],
	"giantTree": ["res://art/props-3d/props/maze/giant_tree.glb"],
	"grassFern": ["res://art/props-3d/props/maze/grass_fern.glb"],
	"locker": ["res://art/props-3d/props/maze/locker.glb"],
	"maintenanceCleaningCart": ["res://art/props-3d/props/maze/maintenance_cleaning_cart.glb"],
	"maintenanceToolCabinet": ["res://art/props-3d/props/maze/maintenance_tool_cabinet.glb"],
	"mascotStatue": ["res://art/props-3d/props/maze/mascot_statue.glb"],
	"prizeClawMachine": ["res://art/props-3d/props/maze/prize_claw_machine.glb"],
	"prizeCounter": ["res://art/props-3d/props/maze/prize_counter.glb"],
	"snackKiosk": ["res://art/props-3d/props/maze/snack_kiosk.glb"],
	"stagePlatform": ["res://art/props-3d/props/maze/stage_platform.glb"],
	"stageSpeaker": ["res://art/props-3d/props/maze/stage_speaker.glb"],
	"utilityCart": ["res://art/props-3d/props/maze/utility_cart.glb"],
	"floorLamp": ["res://art/props-3d/props/maze/floor_lamp.glb", "res://art/props-3d/props/mansion/floor_lamp_teal.glb", "res://art/props-3d/props/mansion/floor_lamp_ivory.glb"],
	"ceilingLight": ["res://art/props-3d/props/mansion/ceiling_light_warm.glb", "res://art/props-3d/props/mansion/ceiling_light_cool.glb", "res://art/props-3d/props/mansion/ceiling_light_teal.glb"],
	"ceilingFan": ["res://art/props-3d/props/mansion/ceiling_fan_walnut.glb", "res://art/props-3d/props/mansion/ceiling_fan_ivory.glb", "res://art/props-3d/props/mansion/ceiling_fan_charcoal.glb"],
	"tableLamp": ["res://art/props-3d/props/mansion/table_lamp_burgundy.glb", "res://art/props-3d/props/mansion/table_lamp_teal.glb", "res://art/props-3d/props/mansion/table_lamp_ivory.glb"],
	"loungeCouch": ["res://art/props-3d/props/maze/lounge_couch_red.glb", "res://art/props-3d/props/mansion/lounge_couch_black.glb", "res://art/props-3d/props/mansion/lounge_couch_brown.glb", "res://art/props-3d/props/mansion/lounge_couch_ivory.glb", "res://art/props-3d/props/mansion/lounge_couch_navy.glb", "res://art/props-3d/props/mansion/lounge_couch_olive.glb", "res://art/props-3d/props/mansion/lounge_couch_violet.glb"],
	"loungeCouchWide": ["res://art/props-3d/props/mansion/lounge_couch_red_wide.glb", "res://art/props-3d/props/mansion/lounge_couch_black_wide.glb", "res://art/props-3d/props/mansion/lounge_couch_brown_wide.glb", "res://art/props-3d/props/mansion/lounge_couch_ivory_wide.glb", "res://art/props-3d/props/mansion/lounge_couch_navy_wide.glb", "res://art/props-3d/props/mansion/lounge_couch_olive_wide.glb", "res://art/props-3d/props/mansion/lounge_couch_violet_wide.glb"],
	"privacyCurtain": ["res://art/props-3d/props/maze/privacy_curtain.glb"],
	"serverRack": ["res://art/props-3d/props/maze/server_rack.glb"],
	"supplyCrates": ["res://art/props-3d/props/maze/supply_crates.glb"],
	"trashBin": ["res://art/props-3d/props/maze/trash_bin.glb"],
	"vendingMachine": ["res://art/props-3d/props/maze/vending_machine.glb"],
	"woodenChair": ["res://art/props-3d/props/maze/wooden_chair_oak.glb", "res://art/props-3d/props/maze/wooden_chair_walnut.glb", "res://art/props-3d/props/maze/wooden_chair_mahogany.glb", "res://art/props-3d/props/maze/wooden_chair_ash.glb"],
	"woodenChairCushion": ["res://art/props-3d/props/maze/wooden_chair_cushion.glb", "res://art/props-3d/props/maze/wooden_chair_cushion_walnut.glb", "res://art/props-3d/props/maze/wooden_chair_cushion_mahogany.glb", "res://art/props-3d/props/maze/wooden_chair_cushion_ash.glb"],
	"woodenTable": ["res://art/props-3d/props/maze/wooden_table.glb", "res://art/props-3d/props/maze/wooden_table_walnut.glb", "res://art/props-3d/props/maze/wooden_table_mahogany.glb", "res://art/props-3d/props/maze/wooden_table_ash.glb"],
	"restaurantPartyTable": ["res://art/props-3d/props/maze/restaurant_party_table.glb"],
	"woodenDresserSideboard": ["res://art/props-3d/props/maze/wooden_dresser_sideboard.glb", "res://art/props-3d/props/maze/wooden_dresser_sideboard_walnut.glb", "res://art/props-3d/props/maze/wooden_dresser_sideboard_mahogany.glb", "res://art/props-3d/props/maze/wooden_dresser_sideboard_ash.glb"],
	"retroComputerCompact": ["res://art/props-3d/props/maze/retro_computer_compact_ivory.glb", "res://art/props-3d/props/maze/retro_computer_compact_charcoal.glb", "res://art/props-3d/props/maze/retro_computer_compact_teal.glb", "res://art/props-3d/props/maze/retro_computer_compact_burgundy.glb"],
	"retroComputerTower": ["res://art/props-3d/props/maze/retro_computer_tower_ivory.glb", "res://art/props-3d/props/maze/retro_computer_tower_charcoal.glb", "res://art/props-3d/props/maze/retro_computer_tower_teal.glb", "res://art/props-3d/props/maze/retro_computer_tower_burgundy.glb"],
	"retroComputerDesktop": ["res://art/props-3d/props/maze/retro_computer_desktop_ivory.glb", "res://art/props-3d/props/maze/retro_computer_desktop_charcoal.glb", "res://art/props-3d/props/maze/retro_computer_desktop_teal.glb", "res://art/props-3d/props/maze/retro_computer_desktop_burgundy.glb"],
	"retroComputerTerminal": ["res://art/props-3d/props/maze/retro_computer_terminal_ivory.glb", "res://art/props-3d/props/maze/retro_computer_terminal_charcoal.glb", "res://art/props-3d/props/maze/retro_computer_terminal_teal.glb", "res://art/props-3d/props/maze/retro_computer_terminal_burgundy.glb"],
	"diningTable": ["res://art/props-3d/props/mansion/grand_dining_table.glb"],
	"diningChair": ["res://art/props-3d/props/mansion/dining_chair_burgundy.glb", "res://art/props-3d/props/mansion/dining_chair_ivory.glb"],
	"diningChairCushion": ["res://art/props-3d/props/mansion/dining_chair_cushion_burgundy.glb"],
	"diningChandelier": ["res://art/props-3d/props/mansion/dining_chandelier.glb", "res://art/props-3d/props/mansion/dining_chandelier_crystal.glb", "res://art/props-3d/props/mansion/dining_chandelier_gothic.glb"],
	"diningSideboard": ["res://art/props-3d/props/mansion/ornate_sideboard.glb"],
	"flowerCenterpiece": ["res://art/props-3d/props/mansion/flower_centerpiece.glb"],
	"framedWallPortrait": ["res://art/props-3d/props/mansion/framed_wall_portrait.glb"],
	"normalPictureFrameEmpty": ["res://art/props-3d/props/mansion/normal_picture_frame_empty.glb"],
	"normalPaintingFrameEmpty": ["res://art/props-3d/props/mansion/normal_painting_frame_empty.glb"],
	"luxuryPictureFrameEmpty": ["res://art/props-3d/props/mansion/luxury_picture_frame_empty.glb"],
	"luxuryPaintingFrameEmpty": ["res://art/props-3d/props/mansion/luxury_painting_frame_empty.glb"],
	"gothicPictureFrameEmpty": ["res://art/props-3d/props/mansion/gothic_picture_frame_empty.glb"],
	"gothicPaintingFrameEmpty": ["res://art/props-3d/props/mansion/gothic_painting_frame_empty.glb"],
	"normalRoomDoor": ["res://art/props-3d/props/mansion/normal_room_door.glb"],
	"luxuryRoomDoor": ["res://art/props-3d/props/mansion/luxury_room_door.glb"],
	"gothicRoomDoor": ["res://art/props-3d/props/mansion/gothic_room_door.glb"],
	"normalDoubleRoomDoor": ["res://art/props-3d/props/mansion/normal_double_room_door.glb"],
	"luxuryDoubleRoomDoor": ["res://art/props-3d/props/mansion/luxury_double_room_door.glb"],
	"gothicDoubleRoomDoor": ["res://art/props-3d/props/mansion/gothic_double_room_door.glb"],
	"heavyMansionDrapes": ["res://art/props-3d/props/mansion/heavy_mansion_drapes.glb"],
	"mansionAreaRug": ["res://art/props-3d/props/mansion/mansion_area_rug.glb"],
	"corridorCarpet": ["res://art/props-3d/props/mansion/corridor_carpet_teal.glb", "res://art/props-3d/props/mansion/corridor_carpet_burgundy.glb"],
	"hotelCarpet": ["res://art/props-3d/props/mansion/hotel_carpet_burgundy.glb", "res://art/props-3d/props/mansion/hotel_carpet_navy.glb", "res://art/props-3d/props/mansion/hotel_carpet_ivory.glb"],
	"apartmentCarpet": ["res://art/props-3d/props/mansion/apartment_carpet_olive.glb", "res://art/props-3d/props/mansion/apartment_carpet_charcoal.glb", "res://art/props-3d/props/mansion/apartment_carpet_rust.glb"],
	"beachMat": ["res://art/props-3d/props/mansion/beach_mat_teal.glb", "res://art/props-3d/props/mansion/beach_mat_sun.glb"],
	"mansionBookshelf": ["res://art/props-3d/props/mansion/mansion_bookshelf.glb"],
	"mansionFireplace": ["res://art/props-3d/props/mansion/mansion_fireplace.glb"],
	"magazineRack": ["res://art/props-3d/props/mansion/magazine_rack.glb"],
	"tableCandelabra": ["res://art/props-3d/props/mansion/table_candelabra.glb"],
	"wallSconce": ["res://art/props-3d/props/mansion/wall_sconce.glb", "res://art/props-3d/props/mansion/wall_sconce_cool.glb", "res://art/props-3d/props/mansion/wall_sconce_gothic.glb"],
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
	"singleBed": ["res://art/props-3d/props/mansion/single_bed_burgundy.glb", "res://art/props-3d/props/mansion/single_bed_navy.glb", "res://art/props-3d/props/mansion/single_bed_violet.glb", "res://art/props-3d/props/mansion/single_bed_olive.glb", "res://art/props-3d/props/mansion/single_bed_ivory.glb", "res://art/props-3d/props/mansion/single_bed_charcoal.glb"],
	"doubleBed": ["res://art/props-3d/props/mansion/double_bed_burgundy.glb", "res://art/props-3d/props/mansion/double_bed_navy.glb", "res://art/props-3d/props/mansion/double_bed_violet.glb", "res://art/props-3d/props/mansion/double_bed_olive.glb", "res://art/props-3d/props/mansion/double_bed_ivory.glb", "res://art/props-3d/props/mansion/double_bed_charcoal.glb"],
	"bunkBed": ["res://art/props-3d/props/prison/bunk_bed_metal.glb", "res://art/props-3d/props/prison/bunk_bed_wood.glb", "res://art/props-3d/props/prison/bunk_bed_loft.glb"],
	"bedroomNightstand": ["res://art/props-3d/props/mansion/bedroom_nightstand.glb", "res://art/props-3d/props/mansion/bedroom_nightstand_navy.glb", "res://art/props-3d/props/mansion/bedroom_nightstand_violet.glb", "res://art/props-3d/props/mansion/bedroom_nightstand_olive.glb", "res://art/props-3d/props/mansion/bedroom_nightstand_ivory.glb", "res://art/props-3d/props/mansion/bedroom_nightstand_charcoal.glb"],
	"bedroomWardrobe": ["res://art/props-3d/props/mansion/bedroom_wardrobe.glb", "res://art/props-3d/props/mansion/bedroom_wardrobe_navy.glb", "res://art/props-3d/props/mansion/bedroom_wardrobe_violet.glb", "res://art/props-3d/props/mansion/bedroom_wardrobe_olive.glb", "res://art/props-3d/props/mansion/bedroom_wardrobe_ivory.glb", "res://art/props-3d/props/mansion/bedroom_wardrobe_charcoal.glb"],
	# FROZEN_MODELS_END
}
const FROZEN_THEMES := {
	"woodenChair": ["oak", "walnut", "mahogany", "ash"],
	"woodenChairCushion": ["oak", "walnut", "mahogany", "ash"],
	"woodenTable": ["oak", "walnut", "mahogany", "ash"],
	"woodenDresserSideboard": ["oak", "walnut", "mahogany", "ash"],
	"retroComputerCompact": ["ivory", "charcoal", "teal", "burgundy"],
	"retroComputerTower": ["ivory", "charcoal", "teal", "burgundy"],
	"retroComputerDesktop": ["ivory", "charcoal", "teal", "burgundy"],
	"retroComputerTerminal": ["ivory", "charcoal", "teal", "burgundy"],
	"singleBed": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"doubleBed": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomNightstand": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomWardrobe": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	# FROZEN_THEMES_END
}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_expect(ContentRegistry.errors().is_empty(), "res://data has errors: %s" % ", ".join(ContentRegistry.errors()))
	for id in ContentRegistry.ids("props"):
		var def := ContentRegistry.get_def("props", id)
		for path in def["models"]:
			_expect(ResourceLoader.exists(String(path)), "%s names a missing model %s" % [id, path])
		_expect(not def.has("themes") or (def["themes"] as Array).size() == (def["models"] as Array).size(),
			"%s has %d finishes for %d models" % [id, (def.get("themes", []) as Array).size(), (def["models"] as Array).size()])
		_expect(PropModelCatalog.MODEL_PATHS.get(id, []) == def["models"], "%s is not in PropModelCatalog.MODEL_PATHS" % id)
	# pilot parity with the constants as they were
	_expect(ContentRegistry.family("office") == OFFICE, "office family order changed: %s" % [ContentRegistry.family("office")])
	for i in OFFICE.size():
		var type: String = OFFICE[i]
		var base := "res://art/props-3d/props/maze/%s" % OFFICE_FILES[i]
		_expect(var_to_str(PropModelCatalog.MODEL_PATHS.get(type)) == var_to_str([base + ".glb", base + "_charcoal.glb",
			base + "_teal.glb"]), "%s model paths differ from the old constant" % type)
		_expect(var_to_str(PropModelCatalog.VARIANT_THEMES.get(type)) == var_to_str(["neutral", "charcoal", "teal"]),
			"%s finishes differ from the old constant" % type)
	var coordinated := PropModelCatalog.COORDINATED_SET_TYPES
	var start := coordinated.find("officeDesk")
	_expect(start == coordinated.find("retroComputerTerminal") + 1 and coordinated.slice(start, start + OFFICE.size()) == OFFICE
		and coordinated.find("singleBed") == start + OFFICE.size(), "office coordinated-set entries moved")
	_expect(not coordinated.any(func(v): return String(v).begins_with(ContentRegistry.DATA)), "an unresolved @data marker is left")
	for table in [PropModelCatalog.MODEL_PATHS, PropModelCatalog.VARIANT_THEMES]:
		_expect(not table.values().has(ContentRegistry.DATA), "an unresolved @data value is left")
	_expect(PropModelCatalog.MODEL_PATHS.is_read_only(), "PropModelCatalog.MODEL_PATHS became writable")
	# DATA migration parity: every migrated prop's paths and finishes, the table's key order and the coordinated set are what they were in code
	for id in FROZEN_MODELS:
		_expect(var_to_str(PropModelCatalog.MODEL_PATHS.get(id)) == var_to_str(FROZEN_MODELS[id]), "%s model paths differ from the old constant" % id)
	for id in FROZEN_THEMES:
		_expect(var_to_str(PropModelCatalog.VARIANT_THEMES.get(id)) == var_to_str(FROZEN_THEMES[id]), "%s finishes differ from the old constant" % id)
	_expect(var_to_str(PropModelCatalog.MODEL_PATHS.keys()) == var_to_str(Array(FROZEN_KEYS)), "PropModelCatalog.MODEL_PATHS key order changed")
	_expect(var_to_str(PropModelCatalog.COORDINATED_SET_TYPES) == var_to_str(Array(FROZEN_COORDINATED)), "PropModelCatalog.COORDINATED_SET_TYPES changed")
	_check_rejections()
	_check_export_presets()
	print("  parity props %s" % Parity.props_hash())
	if _failures == 0:
		print("  data_props OK")
	return _failures


## Every export preset ships res://data: JSON is not an imported resource, so a preset without the filter would export
## a build whose migrated hunters, props and regions are simply missing.
func _check_export_presets() -> void:
	var presets := ConfigFile.new()
	if presets.load("res://export_presets.cfg") != OK:
		return
	for section in presets.get_sections():
		if not section.ends_with(".options") and presets.has_section_key(section, "include_filter"):
			_expect("data/*.json" in String(presets.get_value(section, "include_filter")),
				"export preset %s does not include data/*.json" % presets.get_value(section, "name", section))


func _check_rejections() -> void:
	var cases := {
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": "one.glb"}]}': "\"models\" must be strings",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "colour": "red"}]}': "unknown key \"colour\"",
		'{"schema": "lr.prop/1", "family": "x"}': "needs \"family\"",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"models": []}]}': "\"id\" must be",
	}
	var path := "user://data_props_fixture.json"
	for text in cases:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var parsed := ContentRegistry.parse_file(path, "props")
		var joined := " | ".join(parsed["errors"])
		_expect((parsed["defs"] as Array).is_empty() and path in joined and String(cases[text]) in joined,
			"bad prop file not rejected clearly (%s): %s" % [cases[text], joined])
	DirAccess.remove_absolute(path)
