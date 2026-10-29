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
const FROZEN_KEYS := ["mansionMarbleColumn", "mansionPorcelainVase", "ivStand", "medicalCart", "readingTable", "libraryGlobe", "storageBarrel", "storageShelving", "receptionDesk", "pottedPlant", "standingMirror", "arcadeCabinet", "arcadeCabinetCyanMagenta", "filingCabinet", "officeDesk", "officeChair", "officeCrtSecurityConsole", "officeCubiclePartition", "officePrinter", "officeWaterCooler", "officePhotocopier", "officeShredder", "officeFileBoxes", "officeCornerWorkstation", "arcadeBasketballHoop", "arcadeCarpetCircle", "arcadeCarpetRunner", "arcadeTokenChanger", "backstageRepairStand", "breakerCabinet", "brokenAquarium", "carnivalCarousel", "flowerBlue", "flowerRose", "flowerSun", "flowerViolet", "gardenPlanterBench", "giantTree", "grassFern", "locker", "maintenanceCleaningCart", "maintenanceToolCabinet", "mascotStatue", "prizeClawMachine", "prizeCounter", "snackKiosk", "stagePlatform", "stageSpeaker", "utilityCart", "floorLamp", "ceilingLight", "ceilingFan", "tableLamp", "loungeCouch", "loungeCouchWide", "privacyCurtain", "serverRack", "supplyCrates", "trashBin", "vendingMachine", "woodenChair", "woodenChairCushion", "woodenTable", "restaurantPartyTable", "woodenDresserSideboard", "retroComputerCompact", "retroComputerTower", "retroComputerDesktop", "retroComputerTerminal", "diningTable", "diningChair", "diningChairCushion", "diningChandelier", "diningSideboard", "flowerCenterpiece", "framedWallPortrait", "normalPictureFrameEmpty", "normalPaintingFrameEmpty", "luxuryPictureFrameEmpty", "luxuryPaintingFrameEmpty", "gothicPictureFrameEmpty", "gothicPaintingFrameEmpty", "normalRoomDoor", "luxuryRoomDoor", "gothicRoomDoor", "normalDoubleRoomDoor", "luxuryDoubleRoomDoor", "gothicDoubleRoomDoor", "heavyMansionDrapes", "mansionAreaRug", "corridorCarpet", "hotelCarpet", "apartmentCarpet", "beachMat", "mansionBookshelf", "mansionFireplace", "magazineRack", "tableCandelabra", "wallSconce", "bathroomStall", "bathroomSink", "bathroomMirror", "bathroomVanity", "publicRestroomToilet", "publicMensUrinal", "publicSinkBank", "publicHandDryer", "publicSoapDispenser", "publicPaperTowelDispenser", "publicBabyChangeStation", "publicSanitaryBin", "publicMensRoomSign", "publicWomensRoomSign", "publicMensShowerStall", "publicWomensShowerStall", "publicShowerBench", "houseBathtub", "houseToilet", "houseShowerEnclosure", "houseMedicineCabinet", "houseTowelRack", "houseBathMat", "houseBathroomShelf", "grandStaircase", "grandFoyerStaircase", "singleBed", "doubleBed", "bunkBed", "bedroomNightstand", "bedroomWardrobe", "bedroomDresser", "bedroomVanity", "vanityStool", "bedsideLamp", "toyChest", "laundryHamper", "bedroomRug", "bedroomWallClock", "bedroomBench", "gothicDoubleBed", "gothicNightstand", "gothicWardrobe", "gothicDresser", "gothicVanity", "gothicVanityStool", "gothicBedroomBench", "gothicBedroomRug", "gothicBedsideCandelabra", "gothicHighbackChair", "mansionConsoleTable", "mansionGrandfatherClock", "mansionCoatRack", "mansionTeaCart", "mansionRockingChair", "mansionRoomDivider", "gothicWritingDesk", "gothicBookcase", "gothicPedestalTable", "gothicFloorCandelabra", "gothicCoffinChest", "normalKitchenCounter", "normalKitchenSink", "normalKitchenStove", "normalKitchenFridge", "normalKitchenWallCabinet", "normalKitchenIsland", "luxuryKitchenCounter", "luxuryKitchenSink", "luxuryKitchenStove", "luxuryKitchenFridge", "luxuryKitchenWallCabinet", "luxuryKitchenIsland", "gothicKitchenCounter", "gothicKitchenSink", "gothicKitchenStove", "gothicKitchenFridge", "gothicKitchenWallCabinet", "gothicKitchenIsland", "normalBookcase", "normalCoffeeTable", "normalTvConsole", "normalEntryBench", "mansionDisplayCabinet", "mansionChaiseLounge", "mansionUprightPiano", "mansionBustPedestal", "sandCastle", "beachUmbrella", "tikiBar", "beachChair", "surfboardRack", "palmTree", "frozenBeachHut", "frozenTidelinePool", "carnivalTicketBooth", "popcornCart", "ringTossStall", "strengthTester", "circusPedestal", "shootingGallery", "whackAMole", "duckPond", "carouselCenterpiece", "lavaVent", "emberBrazier", "basaltPillar", "basaltRubble", "magmaCrystalCluster", "infernoAltar", "infernoChainLantern", "lavaPipeManifold", "charredSupplyCrate", "prisonCellGate", "sewerLadder", "sewerLadderTop", "sewerManhole", "sewerFloorGrate", "sewerValveWheel", "sewerPump", "sewerPipeRun", "sewerOutflowPipe", "sewerSluiceGate", "sewerOverflowGrate", "sewerLamp", "sewerBridge", "sewerGrateDeck", "prisonBunk", "prisonCafeteriaTable", "prisonServingCounter", "prisonTrayReturn", "prisonKitchenRack", "dungeonCage", "restraintChair", "hospitalBed", "hospitalCurtain", "ivDripStand", "vitalsMonitor", "nursesStation", "waitingChairs", "operatingTable", "surgicalLight", "instrumentTrolley", "morgueCabinet", "autopsyTable", "pharmacyShelf", "xrayMachine", "xrayLightbox", "medicalSupplyRack", "wheelchair", "hospitalWardSign", "labBench", "fumeHood", "specimenTank", "containmentCell", "labCoolingUnit", "controlConsole", "monitorWall", "divePod", "divePodFilm", "divePodLit", "diveHeadsetStand", "diveHeadsetShelf", "diveConsole", "deconShower", "coldStorageUnit", "labWhiteboard", "hazardSign", "labGlassPartition", "labStool", "labMicroscope", "gasCylinderRack", "biohazardBin", "raisedPlanter", "pottingBench", "pottedPalm", "bananaPlant", "saguaroCactus", "cactusCluster", "seedlingRack", "irrigationManifold", "mistingPost", "overgrowthPatch", "hangingVines", "domeFountain", "wateringCart", "greenhouseBench", "compostBins", "shopShelf", "shopFridge", "checkoutCounter", "displayCase", "coffeeStation", "donutFryer", "bakeryRack", "dinerStool", "dinerBooth", "menuBoard", "donutSign", "washingMachine", "dryerStack", "flowerStand", "barberChair", "barberStation", "clothesRack", "tvWall", "cinemaSeats", "cinemaScreen", "ticketBooth", "concessionCounter", "foodCourtTable", "mallPlanter", "mallBench",
	# music wing (new props, data/props/music.json)
	"micStand", "podiumMic", "deskMic", "drumKit", "electricGuitarStand", "acousticGuitarStand", "bassGuitarStand", "keyboardStand", "uprightPianoMusic", "ampStack", "comboAmp", "stageMonitor", "paSpeakerPole", "mixingDesk", "studioMonitors", "rackGear", "musicStand", "cableCoil", "cableRun", "stageLightRig", "acousticPanel", "guitarWallHanger", "instrumentCases", "onAirSign"]
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
	"bedroomDresser": ["res://art/props-3d/props/mansion/bedroom_dresser.glb", "res://art/props-3d/props/mansion/bedroom_dresser_navy.glb", "res://art/props-3d/props/mansion/bedroom_dresser_violet.glb", "res://art/props-3d/props/mansion/bedroom_dresser_olive.glb", "res://art/props-3d/props/mansion/bedroom_dresser_ivory.glb", "res://art/props-3d/props/mansion/bedroom_dresser_charcoal.glb"],
	"bedroomVanity": ["res://art/props-3d/props/mansion/bedroom_vanity.glb", "res://art/props-3d/props/mansion/bedroom_vanity_navy.glb", "res://art/props-3d/props/mansion/bedroom_vanity_violet.glb", "res://art/props-3d/props/mansion/bedroom_vanity_olive.glb", "res://art/props-3d/props/mansion/bedroom_vanity_ivory.glb", "res://art/props-3d/props/mansion/bedroom_vanity_charcoal.glb"],
	"vanityStool": ["res://art/props-3d/props/mansion/vanity_stool.glb", "res://art/props-3d/props/mansion/vanity_stool_navy.glb", "res://art/props-3d/props/mansion/vanity_stool_violet.glb", "res://art/props-3d/props/mansion/vanity_stool_olive.glb", "res://art/props-3d/props/mansion/vanity_stool_ivory.glb", "res://art/props-3d/props/mansion/vanity_stool_charcoal.glb"],
	"bedsideLamp": ["res://art/props-3d/props/mansion/bedside_lamp.glb", "res://art/props-3d/props/mansion/bedside_lamp_navy.glb", "res://art/props-3d/props/mansion/bedside_lamp_violet.glb", "res://art/props-3d/props/mansion/bedside_lamp_olive.glb", "res://art/props-3d/props/mansion/bedside_lamp_ivory.glb", "res://art/props-3d/props/mansion/bedside_lamp_charcoal.glb"],
	"toyChest": ["res://art/props-3d/props/mansion/toy_chest.glb", "res://art/props-3d/props/mansion/toy_chest_navy.glb", "res://art/props-3d/props/mansion/toy_chest_violet.glb", "res://art/props-3d/props/mansion/toy_chest_olive.glb", "res://art/props-3d/props/mansion/toy_chest_ivory.glb", "res://art/props-3d/props/mansion/toy_chest_charcoal.glb"],
	"laundryHamper": ["res://art/props-3d/props/mansion/laundry_hamper.glb", "res://art/props-3d/props/mansion/laundry_hamper_navy.glb", "res://art/props-3d/props/mansion/laundry_hamper_violet.glb", "res://art/props-3d/props/mansion/laundry_hamper_olive.glb", "res://art/props-3d/props/mansion/laundry_hamper_ivory.glb", "res://art/props-3d/props/mansion/laundry_hamper_charcoal.glb"],
	"bedroomRug": ["res://art/props-3d/props/mansion/bedroom_rug.glb", "res://art/props-3d/props/mansion/bedroom_rug_navy.glb", "res://art/props-3d/props/mansion/bedroom_rug_violet.glb", "res://art/props-3d/props/mansion/bedroom_rug_olive.glb", "res://art/props-3d/props/mansion/bedroom_rug_ivory.glb", "res://art/props-3d/props/mansion/bedroom_rug_charcoal.glb"],
	"bedroomWallClock": ["res://art/props-3d/props/mansion/bedroom_wall_clock.glb", "res://art/props-3d/props/mansion/bedroom_wall_clock_navy.glb", "res://art/props-3d/props/mansion/bedroom_wall_clock_violet.glb", "res://art/props-3d/props/mansion/bedroom_wall_clock_olive.glb", "res://art/props-3d/props/mansion/bedroom_wall_clock_ivory.glb", "res://art/props-3d/props/mansion/bedroom_wall_clock_charcoal.glb"],
	"bedroomBench": ["res://art/props-3d/props/mansion/bedroom_bench.glb", "res://art/props-3d/props/mansion/bedroom_bench_navy.glb", "res://art/props-3d/props/mansion/bedroom_bench_violet.glb", "res://art/props-3d/props/mansion/bedroom_bench_olive.glb", "res://art/props-3d/props/mansion/bedroom_bench_ivory.glb", "res://art/props-3d/props/mansion/bedroom_bench_charcoal.glb"],
	"gothicDoubleBed": ["res://art/props-3d/props/mansion/gothic_double_bed_crimson.glb", "res://art/props-3d/props/mansion/gothic_double_bed_violet.glb", "res://art/props-3d/props/mansion/gothic_double_bed_midnight.glb", "res://art/props-3d/props/mansion/gothic_double_bed_forest.glb", "res://art/props-3d/props/mansion/gothic_double_bed_ivory.glb"],
	"gothicNightstand": ["res://art/props-3d/props/mansion/gothic_nightstand_crimson.glb", "res://art/props-3d/props/mansion/gothic_nightstand_violet.glb", "res://art/props-3d/props/mansion/gothic_nightstand_midnight.glb", "res://art/props-3d/props/mansion/gothic_nightstand_forest.glb", "res://art/props-3d/props/mansion/gothic_nightstand_ivory.glb"],
	"gothicWardrobe": ["res://art/props-3d/props/mansion/gothic_wardrobe_crimson.glb", "res://art/props-3d/props/mansion/gothic_wardrobe_violet.glb", "res://art/props-3d/props/mansion/gothic_wardrobe_midnight.glb", "res://art/props-3d/props/mansion/gothic_wardrobe_forest.glb", "res://art/props-3d/props/mansion/gothic_wardrobe_ivory.glb"],
	"gothicDresser": ["res://art/props-3d/props/mansion/gothic_dresser_crimson.glb", "res://art/props-3d/props/mansion/gothic_dresser_violet.glb", "res://art/props-3d/props/mansion/gothic_dresser_midnight.glb", "res://art/props-3d/props/mansion/gothic_dresser_forest.glb", "res://art/props-3d/props/mansion/gothic_dresser_ivory.glb"],
	"gothicVanity": ["res://art/props-3d/props/mansion/gothic_vanity_crimson.glb", "res://art/props-3d/props/mansion/gothic_vanity_violet.glb", "res://art/props-3d/props/mansion/gothic_vanity_midnight.glb", "res://art/props-3d/props/mansion/gothic_vanity_forest.glb", "res://art/props-3d/props/mansion/gothic_vanity_ivory.glb"],
	"gothicVanityStool": ["res://art/props-3d/props/mansion/gothic_vanity_stool_crimson.glb", "res://art/props-3d/props/mansion/gothic_vanity_stool_violet.glb", "res://art/props-3d/props/mansion/gothic_vanity_stool_midnight.glb", "res://art/props-3d/props/mansion/gothic_vanity_stool_forest.glb", "res://art/props-3d/props/mansion/gothic_vanity_stool_ivory.glb"],
	"gothicBedroomBench": ["res://art/props-3d/props/mansion/gothic_bedroom_bench_crimson.glb", "res://art/props-3d/props/mansion/gothic_bedroom_bench_violet.glb", "res://art/props-3d/props/mansion/gothic_bedroom_bench_midnight.glb", "res://art/props-3d/props/mansion/gothic_bedroom_bench_forest.glb", "res://art/props-3d/props/mansion/gothic_bedroom_bench_ivory.glb"],
	"gothicBedroomRug": ["res://art/props-3d/props/mansion/gothic_bedroom_rug_crimson.glb", "res://art/props-3d/props/mansion/gothic_bedroom_rug_violet.glb", "res://art/props-3d/props/mansion/gothic_bedroom_rug_midnight.glb", "res://art/props-3d/props/mansion/gothic_bedroom_rug_forest.glb", "res://art/props-3d/props/mansion/gothic_bedroom_rug_ivory.glb"],
	"gothicBedsideCandelabra": ["res://art/props-3d/props/mansion/gothic_bedside_candelabra_crimson.glb", "res://art/props-3d/props/mansion/gothic_bedside_candelabra_violet.glb", "res://art/props-3d/props/mansion/gothic_bedside_candelabra_midnight.glb", "res://art/props-3d/props/mansion/gothic_bedside_candelabra_forest.glb", "res://art/props-3d/props/mansion/gothic_bedside_candelabra_ivory.glb"],
	"gothicHighbackChair": ["res://art/props-3d/props/mansion/gothic_highback_chair_crimson.glb", "res://art/props-3d/props/mansion/gothic_highback_chair_violet.glb", "res://art/props-3d/props/mansion/gothic_highback_chair_midnight.glb", "res://art/props-3d/props/mansion/gothic_highback_chair_forest.glb", "res://art/props-3d/props/mansion/gothic_highback_chair_ivory.glb"],
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
	"frozenTidelinePool": ["res://art/props-3d/props/beach/frozen_tideline_pool.glb"],
	"carnivalTicketBooth": ["res://art/props-3d/props/carnival/carnival_ticket_booth.glb"],
	"popcornCart": ["res://art/props-3d/props/carnival/popcorn_cart.glb"],
	"ringTossStall": ["res://art/props-3d/props/carnival/ring_toss_stall.glb"],
	"strengthTester": ["res://art/props-3d/props/carnival/strength_tester.glb"],
	"circusPedestal": ["res://art/props-3d/props/carnival/circus_pedestal.glb"],
	"shootingGallery": ["res://art/props-3d/props/carnival/ring_toss_stall.glb"],
	"whackAMole": ["res://art/props-3d/props/carnival/ring_toss_stall.glb"],
	"duckPond": ["res://art/props-3d/props/carnival/circus_pedestal.glb"],
	"carouselCenterpiece": ["res://art/props-3d/props/carnival/carousel_centerpiece.glb"],
	"lavaVent": ["res://art/props-3d/props/nether/lava_vent.glb"],
	"emberBrazier": ["res://art/props-3d/props/nether/ember_brazier.glb"],
	"basaltPillar": ["res://art/props-3d/props/nether/basalt_pillar.glb"],
	"basaltRubble": ["res://art/props-3d/props/nether/basalt_rubble.glb"],
	"magmaCrystalCluster": ["res://art/props-3d/props/nether/magma_crystal_cluster.glb"],
	"infernoAltar": ["res://art/props-3d/props/nether/inferno_altar.glb"],
	"infernoChainLantern": ["res://art/props-3d/props/nether/inferno_chain_lantern.glb"],
	"lavaPipeManifold": ["res://art/props-3d/props/nether/lava_pipe_manifold.glb"],
	"charredSupplyCrate": ["res://art/props-3d/props/nether/charred_supply_crate.glb"],
	"prisonCellGate": ["res://art/props-3d/props/prison/prison_cell_gate.glb"],
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
	"prisonCafeteriaTable": ["res://art/props-3d/props/prison/prison_cafeteria_table.glb"],
	"prisonServingCounter": ["res://art/props-3d/props/prison/prison_serving_counter.glb"],
	"prisonTrayReturn": ["res://art/props-3d/props/prison/prison_tray_return.glb"],
	"prisonKitchenRack": ["res://art/props-3d/props/prison/prison_kitchen_rack.glb"],
	"dungeonCage": ["res://art/props-3d/props/prison/dungeon_cage.glb"],
	"restraintChair": ["res://art/props-3d/props/prison/restraint_chair.glb"],
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
	"bedroomDresser": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomVanity": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"vanityStool": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedsideLamp": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"toyChest": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"laundryHamper": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomRug": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomWallClock": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
	"bedroomBench": ["burgundy", "navy", "violet", "olive", "ivory", "charcoal"],
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
