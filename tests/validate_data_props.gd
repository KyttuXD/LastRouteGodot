extends RefCounted

## Props as data (docs/DATA_DRIVEN_CONTENT.md): every res://data/props family passes the schema, every model it names
## exists, finishes line up with models, the office pilot is exactly the catalog constants it replaced (paths, finishes,
## coordinated-set order), and the parity fingerprint is printed for the before/after comparison.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- data_props

const Parity := preload("res://tests/data_parity.gd")

const OFFICE := ["officeDesk", "officeChair", "officeCrtSecurityConsole", "officeCubiclePartition", "officePrinter",
	"officeWaterCooler", "officePhotocopier", "officeShredder", "officeFileBoxes", "officeCornerWorkstation"]
const OFFICE_FILES := ["office_desk", "office_task_chair", "office_crt_security_console", "office_cubicle_partition",
	"office_printer", "office_water_cooler", "office_photocopier", "office_shredder", "office_file_boxes",
	"office_corner_workstation"]

## Props as they were in PropModelCatalog before moving to data/props (DATA migration; one claim per commit).
const FROZEN_KEYS := ["mansionMarbleColumn", "mansionPorcelainVase", "ivStand", "medicalCart", "readingTable", "libraryGlobe", "storageBarrel", "storageShelving", "receptionDesk", "pottedPlant", "standingMirror", "arcadeCabinet", "arcadeCabinetCyanMagenta", "filingCabinet", "officeDesk", "officeChair", "officeCrtSecurityConsole", "officeCubiclePartition", "officePrinter", "officeWaterCooler", "officePhotocopier", "officeShredder", "officeFileBoxes", "officeCornerWorkstation", "arcadeBasketballHoop", "arcadeCarpetCircle", "arcadeCarpetRunner", "arcadeTokenChanger", "backstageRepairStand", "breakerCabinet", "brokenAquarium", "carnivalCarousel", "flowerBlue", "flowerRose", "flowerSun", "flowerViolet", "gardenPlanterBench", "giantTree", "grassFern", "locker", "maintenanceCleaningCart", "maintenanceToolCabinet", "mascotStatue", "prizeClawMachine", "prizeCounter", "snackKiosk", "stagePlatform", "stageSpeaker", "utilityCart", "floorLamp", "ceilingLight", "ceilingFan", "tableLamp", "loungeCouch", "loungeCouchWide", "privacyCurtain", "serverRack", "supplyCrates", "trashBin", "vendingMachine", "woodenChair", "woodenChairCushion", "woodenTable", "restaurantPartyTable", "woodenDresserSideboard", "retroComputerCompact", "retroComputerTower", "retroComputerDesktop", "retroComputerTerminal", "diningTable", "diningChair", "diningChairCushion", "diningChandelier", "diningSideboard", "flowerCenterpiece", "framedWallPortrait", "normalPictureFrameEmpty", "normalPaintingFrameEmpty", "luxuryPictureFrameEmpty", "luxuryPaintingFrameEmpty", "gothicPictureFrameEmpty", "gothicPaintingFrameEmpty", "normalRoomDoor", "luxuryRoomDoor", "gothicRoomDoor", "normalDoubleRoomDoor", "luxuryDoubleRoomDoor", "gothicDoubleRoomDoor", "heavyMansionDrapes", "mansionAreaRug", "corridorCarpet", "hotelCarpet", "apartmentCarpet", "beachMat", "mansionBookshelf", "mansionFireplace", "magazineRack", "tableCandelabra", "wallSconce", "bathroomStall", "bathroomSink", "bathroomMirror", "bathroomVanity", "publicRestroomToilet", "publicMensUrinal", "publicSinkBank", "publicHandDryer", "publicSoapDispenser", "publicPaperTowelDispenser", "publicBabyChangeStation", "publicSanitaryBin", "publicMensRoomSign", "publicWomensRoomSign", "publicMensShowerStall", "publicWomensShowerStall", "publicShowerBench", "houseBathtub", "houseToilet", "houseShowerEnclosure", "houseMedicineCabinet", "houseTowelRack", "houseBathMat", "houseBathroomShelf", "grandStaircase", "grandFoyerStaircase", "singleBed", "doubleBed", "bunkBed", "bedroomNightstand", "bedroomWardrobe", "bedroomDresser", "bedroomVanity", "vanityStool", "bedsideLamp", "toyChest", "laundryHamper", "bedroomRug", "bedroomWallClock", "bedroomBench", "gothicDoubleBed", "gothicNightstand", "gothicWardrobe", "gothicDresser", "gothicVanity", "gothicVanityStool", "gothicBedroomBench", "gothicBedroomRug", "gothicBedsideCandelabra", "gothicHighbackChair", "mansionConsoleTable", "mansionGrandfatherClock", "mansionCoatRack", "mansionTeaCart", "mansionRockingChair", "mansionRoomDivider", "gothicWritingDesk", "gothicBookcase", "gothicPedestalTable", "gothicFloorCandelabra", "gothicCoffinChest", "normalKitchenCounter", "normalKitchenSink", "normalKitchenStove", "normalKitchenFridge", "normalKitchenWallCabinet", "normalKitchenIsland", "luxuryKitchenCounter", "luxuryKitchenSink", "luxuryKitchenStove", "luxuryKitchenFridge", "luxuryKitchenWallCabinet", "luxuryKitchenIsland", "gothicKitchenCounter", "gothicKitchenSink", "gothicKitchenStove", "gothicKitchenFridge", "gothicKitchenWallCabinet", "gothicKitchenIsland", "normalBookcase", "normalCoffeeTable", "normalTvConsole", "normalEntryBench", "mansionDisplayCabinet", "mansionChaiseLounge", "mansionUprightPiano", "mansionBustPedestal", "sandCastle", "beachUmbrella", "tikiBar", "beachChair", "surfboardRack", "palmTree", "frozenBeachHut", "frozenTidelinePool", "carnivalTicketBooth", "popcornCart", "ringTossStall", "strengthTester", "circusPedestal", "shootingGallery", "whackAMole", "duckPond", "carouselCenterpiece", "lavaVent", "emberBrazier", "basaltPillar", "basaltRubble", "magmaCrystalCluster", "infernoAltar", "infernoChainLantern", "lavaPipeManifold", "charredSupplyCrate", "prisonCellGate", "sewerLadder", "sewerLadderTop", "sewerManhole", "sewerFloorGrate", "sewerValveWheel", "sewerPump", "sewerPipeRun", "sewerOutflowPipe", "sewerSluiceGate", "sewerOverflowGrate", "sewerLamp", "sewerBridge", "sewerGrateDeck", "prisonBunk", "prisonCafeteriaTable", "prisonServingCounter", "prisonTrayReturn", "prisonKitchenRack", "dungeonCage", "restraintChair", "hospitalBed", "hospitalCurtain", "ivDripStand", "vitalsMonitor", "nursesStation", "waitingChairs", "operatingTable", "surgicalLight", "instrumentTrolley", "morgueCabinet", "autopsyTable", "pharmacyShelf", "xrayMachine", "xrayLightbox", "medicalSupplyRack", "wheelchair", "hospitalWardSign", "labBench", "fumeHood", "specimenTank", "containmentCell", "labCoolingUnit", "controlConsole", "monitorWall", "divePod", "divePodFilm", "divePodLit", "diveHeadsetStand", "diveHeadsetShelf", "diveConsole", "deconShower", "coldStorageUnit", "labWhiteboard", "hazardSign", "labGlassPartition", "labStool", "labMicroscope", "gasCylinderRack", "biohazardBin", "raisedPlanter", "pottingBench", "pottedPalm", "bananaPlant", "saguaroCactus", "cactusCluster", "seedlingRack", "irrigationManifold", "mistingPost", "overgrowthPatch", "hangingVines", "domeFountain", "wateringCart", "greenhouseBench", "compostBins", "shopShelf", "shopFridge", "checkoutCounter", "displayCase", "coffeeStation", "donutFryer", "bakeryRack", "dinerStool", "dinerBooth", "menuBoard", "donutSign", "washingMachine", "dryerStack", "flowerStand", "barberChair", "barberStation", "clothesRack", "tvWall", "cinemaSeats", "cinemaScreen", "ticketBooth", "concessionCounter", "foodCourtTable", "mallPlanter", "mallBench",
	# music wing (new props, data/props/music.json)
	"micStand", "podiumMic", "deskMic", "drumKit", "electricGuitarStand", "acousticGuitarStand", "bassGuitarStand", "keyboardStand", "uprightPianoMusic", "ampStack", "comboAmp", "stageMonitor", "paSpeakerPole", "mixingDesk", "studioMonitors", "rackGear", "musicStand", "cableCoil", "cableRun", "stageLightRig", "acousticPanel", "guitarWallHanger", "instrumentCases", "onAirSign",
	# mansion wardrobe finish (data/props/wardrobe_mansion.json); appended so earlier key order stays put
	"bedroomWardrobeMansion"]
const FROZEN_COORDINATED := ["woodenChair", "woodenChairCushion", "woodenTable", "woodenDresserSideboard", "retroComputerCompact", "retroComputerTower", "retroComputerDesktop", "retroComputerTerminal", "officeDesk", "officeChair", "officeCrtSecurityConsole", "officeCubiclePartition", "officePrinter", "officeWaterCooler", "officePhotocopier", "officeShredder", "officeFileBoxes", "officeCornerWorkstation", "singleBed", "doubleBed", "bedroomNightstand", "bedroomWardrobe", "bedroomDresser", "bedroomVanity", "vanityStool", "bedsideLamp", "toyChest", "laundryHamper", "bedroomRug", "bedroomWallClock", "bedroomBench", "gothicDoubleBed", "gothicNightstand", "gothicWardrobe", "gothicDresser", "gothicVanity", "gothicVanityStool", "gothicBedroomBench", "gothicBedroomRug", "gothicBedsideCandelabra", "gothicHighbackChair"]
const FROZEN_MODELS := {
	"mansionMarbleColumn": ["res://assets/props/blocky/mansionMarbleColumn.glb"],
	"mansionPorcelainVase": ["res://assets/props/blocky/mansionPorcelainVase_0.glb", "res://assets/props/blocky/mansionPorcelainVase_1.glb", "res://assets/props/blocky/mansionPorcelainVase_2.glb"],
	"ivStand": ["res://assets/props/blocky/ivStand.glb"],
	"medicalCart": ["res://assets/props/blocky/medicalCart.glb"],
	"readingTable": ["res://assets/props/blocky/readingTable_0.glb", "res://assets/props/blocky/readingTable_1.glb", "res://assets/props/blocky/readingTable_2.glb"],
	"libraryGlobe": ["res://assets/props/blocky/libraryGlobe_0.glb", "res://assets/props/blocky/libraryGlobe_1.glb"],
	"storageBarrel": ["res://assets/props/blocky/storageBarrel_0.glb", "res://assets/props/blocky/storageBarrel_1.glb", "res://assets/props/blocky/storageBarrel_2.glb"],
	"storageShelving": ["res://assets/props/blocky/storageShelving.glb"],
	"receptionDesk": ["res://assets/props/blocky/receptionDesk_0.glb", "res://assets/props/blocky/receptionDesk_1.glb", "res://assets/props/blocky/receptionDesk_2.glb"],
	"pottedPlant": ["res://assets/props/blocky/pottedPlant_0.glb", "res://assets/props/blocky/pottedPlant_1.glb", "res://assets/props/blocky/pottedPlant_2.glb"],
	"standingMirror": ["res://assets/props/blocky/standingMirror_0.glb", "res://assets/props/blocky/standingMirror_1.glb", "res://assets/props/blocky/standingMirror_2.glb"],
	"arcadeCabinet": ["res://assets/props/maze/arcade_cabinet_default.glb", "res://assets/props/maze/arcade_cabinet_amber.glb", "res://assets/props/maze/arcade_cabinet_burgundy.glb", "res://assets/props/maze/arcade_cabinet_teal.glb", "res://assets/props/maze/arcade_cabinet_ultraviolet.glb"],
	"arcadeCabinetCyanMagenta": ["res://assets/props/maze/arcade_cabinet_cyan_magenta.glb"],
	"filingCabinet": ["res://assets/props/maze/filing_cabinet.glb"],
	"arcadeBasketballHoop": ["res://assets/props/maze/arcade_basketball_hoop.glb"],
	"arcadeCarpetCircle": ["res://assets/props/maze/arcade_carpet_circle.glb"],
	"arcadeCarpetRunner": ["res://assets/props/maze/arcade_carpet_runner.glb"],
	"arcadeTokenChanger": ["res://assets/props/maze/arcade_token_changer.glb"],
	"backstageRepairStand": ["res://assets/props/maze/backstage_repair_stand.glb"],
	"breakerCabinet": ["res://assets/props/maze/breaker_cabinet.glb"],
	"brokenAquarium": ["res://assets/props/maze/broken_aquarium.glb"],
	"carnivalCarousel": ["res://assets/props/maze/carnival_carousel.glb"],
	"flowerBlue": ["res://assets/props/maze/flower_blue.glb"],
	"flowerRose": ["res://assets/props/maze/flower_rose.glb"],
	"flowerSun": ["res://assets/props/maze/flower_sun.glb"],
	"flowerViolet": ["res://assets/props/maze/flower_violet.glb"],
	"gardenPlanterBench": ["res://assets/props/maze/garden_planter_bench.glb"],
	"giantTree": ["res://assets/props/maze/giant_tree.glb"],
	"grassFern": ["res://assets/props/maze/grass_fern.glb"],
	"locker": ["res://assets/props/maze/locker.glb"],
	"maintenanceCleaningCart": ["res://assets/props/maze/maintenance_cleaning_cart.glb"],
	"maintenanceToolCabinet": ["res://assets/props/maze/maintenance_tool_cabinet.glb"],
	"mascotStatue": ["res://assets/props/maze/mascot_statue.glb"],
	"prizeClawMachine": ["res://assets/props/maze/prize_claw_machine.glb"],
	"prizeCounter": ["res://assets/props/maze/prize_counter.glb"],
	"snackKiosk": ["res://assets/props/maze/snack_kiosk.glb"],
	"stagePlatform": ["res://assets/props/maze/stage_platform.glb"],
	"stageSpeaker": ["res://assets/props/maze/stage_speaker.glb"],
	"utilityCart": ["res://assets/props/maze/utility_cart.glb"],
	"floorLamp": ["res://assets/props/maze/floor_lamp.glb", "res://assets/props/mansion/floor_lamp_teal.glb", "res://assets/props/mansion/floor_lamp_ivory.glb"],
	"ceilingLight": ["res://assets/props/mansion/ceiling_light_warm.glb", "res://assets/props/mansion/ceiling_light_cool.glb", "res://assets/props/mansion/ceiling_light_teal.glb"],
	"ceilingFan": ["res://assets/props/mansion/ceiling_fan_walnut.glb", "res://assets/props/mansion/ceiling_fan_ivory.glb", "res://assets/props/mansion/ceiling_fan_charcoal.glb"],
	"tableLamp": ["res://assets/props/mansion/table_lamp_burgundy.glb", "res://assets/props/mansion/table_lamp_teal.glb", "res://assets/props/mansion/table_lamp_ivory.glb"],
	"loungeCouch": ["res://assets/props/maze/lounge_couch_red.glb", "res://assets/props/mansion/lounge_couch_black.glb", "res://assets/props/mansion/lounge_couch_brown.glb", "res://assets/props/mansion/lounge_couch_ivory.glb", "res://assets/props/mansion/lounge_couch_navy.glb", "res://assets/props/mansion/lounge_couch_olive.glb", "res://assets/props/mansion/lounge_couch_violet.glb"],
	"loungeCouchWide": ["res://assets/props/mansion/lounge_couch_red_wide.glb", "res://assets/props/mansion/lounge_couch_black_wide.glb", "res://assets/props/mansion/lounge_couch_brown_wide.glb", "res://assets/props/mansion/lounge_couch_ivory_wide.glb", "res://assets/props/mansion/lounge_couch_navy_wide.glb", "res://assets/props/mansion/lounge_couch_olive_wide.glb", "res://assets/props/mansion/lounge_couch_violet_wide.glb"],
	"privacyCurtain": ["res://assets/props/maze/privacy_curtain.glb"],
	"serverRack": ["res://assets/props/maze/server_rack.glb"],
	"supplyCrates": ["res://assets/props/maze/supply_crates.glb"],
	"trashBin": ["res://assets/props/maze/trash_bin.glb"],
	"vendingMachine": ["res://assets/props/maze/vending_machine.glb"],
	"woodenChair": ["res://assets/props/maze/wooden_chair_oak.glb", "res://assets/props/maze/wooden_chair_walnut.glb", "res://assets/props/maze/wooden_chair_mahogany.glb", "res://assets/props/maze/wooden_chair_ash.glb"],
	"woodenChairCushion": ["res://assets/props/maze/wooden_chair_cushion.glb", "res://assets/props/maze/wooden_chair_cushion_walnut.glb", "res://assets/props/maze/wooden_chair_cushion_mahogany.glb", "res://assets/props/maze/wooden_chair_cushion_ash.glb"],
	"woodenTable": ["res://assets/props/maze/wooden_table.glb", "res://assets/props/maze/wooden_table_walnut.glb", "res://assets/props/maze/wooden_table_mahogany.glb", "res://assets/props/maze/wooden_table_ash.glb"],
	"restaurantPartyTable": ["res://assets/props/maze/restaurant_party_table.glb"],
	"woodenDresserSideboard": ["res://assets/props/maze/wooden_dresser_sideboard.glb", "res://assets/props/maze/wooden_dresser_sideboard_walnut.glb", "res://assets/props/maze/wooden_dresser_sideboard_mahogany.glb", "res://assets/props/maze/wooden_dresser_sideboard_ash.glb"],
	"retroComputerCompact": ["res://assets/props/maze/retro_computer_compact_ivory.glb", "res://assets/props/maze/retro_computer_compact_charcoal.glb", "res://assets/props/maze/retro_computer_compact_teal.glb", "res://assets/props/maze/retro_computer_compact_burgundy.glb"],
	"retroComputerTower": ["res://assets/props/maze/retro_computer_tower_ivory.glb", "res://assets/props/maze/retro_computer_tower_charcoal.glb", "res://assets/props/maze/retro_computer_tower_teal.glb", "res://assets/props/maze/retro_computer_tower_burgundy.glb"],
	"retroComputerDesktop": ["res://assets/props/maze/retro_computer_desktop_ivory.glb", "res://assets/props/maze/retro_computer_desktop_charcoal.glb", "res://assets/props/maze/retro_computer_desktop_teal.glb", "res://assets/props/maze/retro_computer_desktop_burgundy.glb"],
	"retroComputerTerminal": ["res://assets/props/maze/retro_computer_terminal_ivory.glb", "res://assets/props/maze/retro_computer_terminal_charcoal.glb", "res://assets/props/maze/retro_computer_terminal_teal.glb", "res://assets/props/maze/retro_computer_terminal_burgundy.glb"],
	"diningTable": ["res://assets/props/mansion/grand_dining_table.glb"],
	"diningChair": ["res://assets/props/mansion/dining_chair_burgundy.glb", "res://assets/props/mansion/dining_chair_ivory.glb"],
	"diningChairCushion": ["res://assets/props/mansion/dining_chair_cushion_burgundy.glb"],
	"diningChandelier": ["res://assets/props/mansion/dining_chandelier.glb", "res://assets/props/mansion/dining_chandelier_crystal.glb", "res://assets/props/mansion/dining_chandelier_gothic.glb"],
	"diningSideboard": ["res://assets/props/mansion/ornate_sideboard.glb"],
	"flowerCenterpiece": ["res://assets/props/mansion/flower_centerpiece.glb"],
	"framedWallPortrait": ["res://assets/props/mansion/framed_wall_portrait.glb"],
	"normalPictureFrameEmpty": ["res://assets/props/mansion/normal_picture_frame_empty.glb"],
	"normalPaintingFrameEmpty": ["res://assets/props/mansion/normal_painting_frame_empty.glb"],
	"luxuryPictureFrameEmpty": ["res://assets/props/mansion/luxury_picture_frame_empty.glb"],
	"luxuryPaintingFrameEmpty": ["res://assets/props/mansion/luxury_painting_frame_empty.glb"],
	"gothicPictureFrameEmpty": ["res://assets/props/mansion/gothic_picture_frame_empty.glb"],
	"gothicPaintingFrameEmpty": ["res://assets/props/mansion/gothic_painting_frame_empty.glb"],
	"normalRoomDoor": ["res://assets/props/mansion/normal_room_door.glb"],
	"luxuryRoomDoor": ["res://assets/props/mansion/luxury_room_door.glb"],
	"gothicRoomDoor": ["res://assets/props/mansion/gothic_room_door.glb"],
	"normalDoubleRoomDoor": ["res://assets/props/mansion/normal_double_room_door.glb"],
	"luxuryDoubleRoomDoor": ["res://assets/props/mansion/luxury_double_room_door.glb"],
	"gothicDoubleRoomDoor": ["res://assets/props/mansion/gothic_double_room_door.glb"],
	"heavyMansionDrapes": ["res://assets/props/mansion/heavy_mansion_drapes.glb"],
	"mansionAreaRug": ["res://assets/props/mansion/mansion_area_rug.glb"],
	"corridorCarpet": ["res://assets/props/mansion/corridor_carpet_teal.glb", "res://assets/props/mansion/corridor_carpet_burgundy.glb"],
	"hotelCarpet": ["res://assets/props/mansion/hotel_carpet_burgundy.glb", "res://assets/props/mansion/hotel_carpet_navy.glb", "res://assets/props/mansion/hotel_carpet_ivory.glb"],
	"apartmentCarpet": ["res://assets/props/mansion/apartment_carpet_olive.glb", "res://assets/props/mansion/apartment_carpet_charcoal.glb", "res://assets/props/mansion/apartment_carpet_rust.glb"],
	"beachMat": ["res://assets/props/mansion/beach_mat_teal.glb", "res://assets/props/mansion/beach_mat_sun.glb"],
	"mansionBookshelf": ["res://assets/props/mansion/mansion_bookshelf.glb"],
	"mansionFireplace": ["res://assets/props/mansion/mansion_fireplace.glb"],
	"magazineRack": ["res://assets/props/mansion/magazine_rack.glb"],
	"tableCandelabra": ["res://assets/props/mansion/table_candelabra.glb"],
	"wallSconce": ["res://assets/props/mansion/wall_sconce.glb", "res://assets/props/mansion/wall_sconce_cool.glb", "res://assets/props/mansion/wall_sconce_gothic.glb"],
	"bathroomStall": ["res://assets/props/mansion/bathroom_stall.glb"],
	"bathroomSink": ["res://assets/props/mansion/bathroom_sink.glb"],
	"bathroomMirror": ["res://assets/props/mansion/bathroom_mirror.glb"],
	"bathroomVanity": ["res://assets/props/mansion/bathroom_vanity.glb"],
	"publicRestroomToilet": ["res://assets/props/mansion/public_restroom_toilet.glb"],
	"publicMensUrinal": ["res://assets/props/mansion/public_mens_urinal.glb"],
	"publicSinkBank": ["res://assets/props/mansion/public_sink_bank.glb"],
	"publicHandDryer": ["res://assets/props/mansion/public_hand_dryer.glb"],
	"publicSoapDispenser": ["res://assets/props/mansion/public_soap_dispenser.glb"],
	"publicPaperTowelDispenser": ["res://assets/props/mansion/public_paper_towel_dispenser.glb"],
	"publicBabyChangeStation": ["res://assets/props/mansion/public_baby_change_station.glb"],
	"publicSanitaryBin": ["res://assets/props/mansion/public_sanitary_bin.glb"],
	"publicMensRoomSign": ["res://assets/props/mansion/public_mens_room_sign.glb"],
	"publicWomensRoomSign": ["res://assets/props/mansion/public_womens_room_sign.glb"],
	"publicMensShowerStall": ["res://assets/props/mansion/public_mens_shower_stall.glb"],
	"publicWomensShowerStall": ["res://assets/props/mansion/public_womens_shower_stall.glb"],
	"publicShowerBench": ["res://assets/props/mansion/public_shower_bench.glb"],
	"houseBathtub": ["res://assets/props/mansion/house_bathtub.glb"],
	"houseToilet": ["res://assets/props/mansion/house_toilet.glb"],
	"houseShowerEnclosure": ["res://assets/props/mansion/house_shower_enclosure.glb"],
	"houseMedicineCabinet": ["res://assets/props/mansion/house_medicine_cabinet.glb"],
	"houseTowelRack": ["res://assets/props/mansion/house_towel_rack.glb"],
	"houseBathMat": ["res://assets/props/mansion/house_bath_mat.glb"],
	"houseBathroomShelf": ["res://assets/props/mansion/house_bathroom_shelf.glb"],
	"grandStaircase": ["res://assets/props/mansion/grand_staircase.glb"],
	"grandFoyerStaircase": ["res://assets/props/mansion/grand_foyer_staircase.glb"],
	"singleBed": ["res://assets/props/mansion/single_bed_burgundy.glb", "res://assets/props/mansion/single_bed_navy.glb", "res://assets/props/mansion/single_bed_violet.glb", "res://assets/props/mansion/single_bed_olive.glb", "res://assets/props/mansion/single_bed_ivory.glb", "res://assets/props/mansion/single_bed_charcoal.glb"],
	"doubleBed": ["res://assets/props/mansion/double_bed_burgundy.glb", "res://assets/props/mansion/double_bed_navy.glb", "res://assets/props/mansion/double_bed_violet.glb", "res://assets/props/mansion/double_bed_olive.glb", "res://assets/props/mansion/double_bed_ivory.glb", "res://assets/props/mansion/double_bed_charcoal.glb"],
	"bunkBed": ["res://assets/props/prison/bunk_bed_metal.glb", "res://assets/props/prison/bunk_bed_wood.glb", "res://assets/props/prison/bunk_bed_loft.glb"],
	"bedroomNightstand": ["res://assets/props/mansion/bedroom_nightstand.glb", "res://assets/props/mansion/bedroom_nightstand_navy.glb", "res://assets/props/mansion/bedroom_nightstand_violet.glb", "res://assets/props/mansion/bedroom_nightstand_olive.glb", "res://assets/props/mansion/bedroom_nightstand_ivory.glb", "res://assets/props/mansion/bedroom_nightstand_charcoal.glb"],
	"bedroomWardrobe": ["res://assets/props/mansion/bedroom_wardrobe.glb", "res://assets/props/mansion/bedroom_wardrobe_navy.glb", "res://assets/props/mansion/bedroom_wardrobe_violet.glb", "res://assets/props/mansion/bedroom_wardrobe_olive.glb", "res://assets/props/mansion/bedroom_wardrobe_ivory.glb", "res://assets/props/mansion/bedroom_wardrobe_charcoal.glb"],
	"bedroomDresser": ["res://assets/props/mansion/bedroom_dresser.glb", "res://assets/props/mansion/bedroom_dresser_navy.glb", "res://assets/props/mansion/bedroom_dresser_violet.glb", "res://assets/props/mansion/bedroom_dresser_olive.glb", "res://assets/props/mansion/bedroom_dresser_ivory.glb", "res://assets/props/mansion/bedroom_dresser_charcoal.glb"],
	"bedroomVanity": ["res://assets/props/mansion/bedroom_vanity.glb", "res://assets/props/mansion/bedroom_vanity_navy.glb", "res://assets/props/mansion/bedroom_vanity_violet.glb", "res://assets/props/mansion/bedroom_vanity_olive.glb", "res://assets/props/mansion/bedroom_vanity_ivory.glb", "res://assets/props/mansion/bedroom_vanity_charcoal.glb"],
	"vanityStool": ["res://assets/props/mansion/vanity_stool.glb", "res://assets/props/mansion/vanity_stool_navy.glb", "res://assets/props/mansion/vanity_stool_violet.glb", "res://assets/props/mansion/vanity_stool_olive.glb", "res://assets/props/mansion/vanity_stool_ivory.glb", "res://assets/props/mansion/vanity_stool_charcoal.glb"],
	"bedsideLamp": ["res://assets/props/mansion/bedside_lamp.glb", "res://assets/props/mansion/bedside_lamp_navy.glb", "res://assets/props/mansion/bedside_lamp_violet.glb", "res://assets/props/mansion/bedside_lamp_olive.glb", "res://assets/props/mansion/bedside_lamp_ivory.glb", "res://assets/props/mansion/bedside_lamp_charcoal.glb"],
	"toyChest": ["res://assets/props/mansion/toy_chest.glb", "res://assets/props/mansion/toy_chest_navy.glb", "res://assets/props/mansion/toy_chest_violet.glb", "res://assets/props/mansion/toy_chest_olive.glb", "res://assets/props/mansion/toy_chest_ivory.glb", "res://assets/props/mansion/toy_chest_charcoal.glb"],
	"laundryHamper": ["res://assets/props/mansion/laundry_hamper.glb", "res://assets/props/mansion/laundry_hamper_navy.glb", "res://assets/props/mansion/laundry_hamper_violet.glb", "res://assets/props/mansion/laundry_hamper_olive.glb", "res://assets/props/mansion/laundry_hamper_ivory.glb", "res://assets/props/mansion/laundry_hamper_charcoal.glb"],
	"bedroomRug": ["res://assets/props/mansion/bedroom_rug.glb", "res://assets/props/mansion/bedroom_rug_navy.glb", "res://assets/props/mansion/bedroom_rug_violet.glb", "res://assets/props/mansion/bedroom_rug_olive.glb", "res://assets/props/mansion/bedroom_rug_ivory.glb", "res://assets/props/mansion/bedroom_rug_charcoal.glb"],
	"bedroomWallClock": ["res://assets/props/mansion/bedroom_wall_clock.glb", "res://assets/props/mansion/bedroom_wall_clock_navy.glb", "res://assets/props/mansion/bedroom_wall_clock_violet.glb", "res://assets/props/mansion/bedroom_wall_clock_olive.glb", "res://assets/props/mansion/bedroom_wall_clock_ivory.glb", "res://assets/props/mansion/bedroom_wall_clock_charcoal.glb"],
	"bedroomBench": ["res://assets/props/mansion/bedroom_bench.glb", "res://assets/props/mansion/bedroom_bench_navy.glb", "res://assets/props/mansion/bedroom_bench_violet.glb", "res://assets/props/mansion/bedroom_bench_olive.glb", "res://assets/props/mansion/bedroom_bench_ivory.glb", "res://assets/props/mansion/bedroom_bench_charcoal.glb"],
	"gothicDoubleBed": ["res://assets/props/mansion/gothic_double_bed_crimson.glb", "res://assets/props/mansion/gothic_double_bed_violet.glb", "res://assets/props/mansion/gothic_double_bed_midnight.glb", "res://assets/props/mansion/gothic_double_bed_forest.glb", "res://assets/props/mansion/gothic_double_bed_ivory.glb"],
	"gothicNightstand": ["res://assets/props/mansion/gothic_nightstand_crimson.glb", "res://assets/props/mansion/gothic_nightstand_violet.glb", "res://assets/props/mansion/gothic_nightstand_midnight.glb", "res://assets/props/mansion/gothic_nightstand_forest.glb", "res://assets/props/mansion/gothic_nightstand_ivory.glb"],
	"gothicWardrobe": ["res://assets/props/mansion/gothic_wardrobe_crimson.glb", "res://assets/props/mansion/gothic_wardrobe_violet.glb", "res://assets/props/mansion/gothic_wardrobe_midnight.glb", "res://assets/props/mansion/gothic_wardrobe_forest.glb", "res://assets/props/mansion/gothic_wardrobe_ivory.glb"],
	"gothicDresser": ["res://assets/props/mansion/gothic_dresser_crimson.glb", "res://assets/props/mansion/gothic_dresser_violet.glb", "res://assets/props/mansion/gothic_dresser_midnight.glb", "res://assets/props/mansion/gothic_dresser_forest.glb", "res://assets/props/mansion/gothic_dresser_ivory.glb"],
	"gothicVanity": ["res://assets/props/mansion/gothic_vanity_crimson.glb", "res://assets/props/mansion/gothic_vanity_violet.glb", "res://assets/props/mansion/gothic_vanity_midnight.glb", "res://assets/props/mansion/gothic_vanity_forest.glb", "res://assets/props/mansion/gothic_vanity_ivory.glb"],
	"gothicVanityStool": ["res://assets/props/mansion/gothic_vanity_stool_crimson.glb", "res://assets/props/mansion/gothic_vanity_stool_violet.glb", "res://assets/props/mansion/gothic_vanity_stool_midnight.glb", "res://assets/props/mansion/gothic_vanity_stool_forest.glb", "res://assets/props/mansion/gothic_vanity_stool_ivory.glb"],
	"gothicBedroomBench": ["res://assets/props/mansion/gothic_bedroom_bench_crimson.glb", "res://assets/props/mansion/gothic_bedroom_bench_violet.glb", "res://assets/props/mansion/gothic_bedroom_bench_midnight.glb", "res://assets/props/mansion/gothic_bedroom_bench_forest.glb", "res://assets/props/mansion/gothic_bedroom_bench_ivory.glb"],
	"gothicBedroomRug": ["res://assets/props/mansion/gothic_bedroom_rug_crimson.glb", "res://assets/props/mansion/gothic_bedroom_rug_violet.glb", "res://assets/props/mansion/gothic_bedroom_rug_midnight.glb", "res://assets/props/mansion/gothic_bedroom_rug_forest.glb", "res://assets/props/mansion/gothic_bedroom_rug_ivory.glb"],
	"gothicBedsideCandelabra": ["res://assets/props/mansion/gothic_bedside_candelabra_crimson.glb", "res://assets/props/mansion/gothic_bedside_candelabra_violet.glb", "res://assets/props/mansion/gothic_bedside_candelabra_midnight.glb", "res://assets/props/mansion/gothic_bedside_candelabra_forest.glb", "res://assets/props/mansion/gothic_bedside_candelabra_ivory.glb"],
	"gothicHighbackChair": ["res://assets/props/mansion/gothic_highback_chair_crimson.glb", "res://assets/props/mansion/gothic_highback_chair_violet.glb", "res://assets/props/mansion/gothic_highback_chair_midnight.glb", "res://assets/props/mansion/gothic_highback_chair_forest.glb", "res://assets/props/mansion/gothic_highback_chair_ivory.glb"],
	"mansionConsoleTable": ["res://assets/props/mansion/mansion_console_table.glb"],
	"mansionGrandfatherClock": ["res://assets/props/mansion/mansion_grandfather_clock.glb"],
	"mansionCoatRack": ["res://assets/props/mansion/mansion_coat_rack.glb"],
	"mansionTeaCart": ["res://assets/props/mansion/mansion_tea_cart.glb"],
	"mansionRockingChair": ["res://assets/props/mansion/mansion_rocking_chair.glb"],
	"mansionRoomDivider": ["res://assets/props/mansion/mansion_room_divider.glb"],
	"gothicWritingDesk": ["res://assets/props/mansion/gothic_writing_desk.glb"],
	"gothicBookcase": ["res://assets/props/mansion/gothic_bookcase.glb"],
	"gothicPedestalTable": ["res://assets/props/mansion/gothic_pedestal_table.glb"],
	"gothicFloorCandelabra": ["res://assets/props/mansion/gothic_floor_candelabra.glb"],
	"gothicCoffinChest": ["res://assets/props/mansion/gothic_coffin_chest.glb"],
	"normalKitchenCounter": ["res://assets/props/mansion/normal_kitchen_counter.glb"],
	"normalKitchenSink": ["res://assets/props/mansion/normal_kitchen_sink.glb"],
	"normalKitchenStove": ["res://assets/props/mansion/normal_kitchen_stove.glb"],
	"normalKitchenFridge": ["res://assets/props/mansion/normal_kitchen_fridge.glb"],
	"normalKitchenWallCabinet": ["res://assets/props/mansion/normal_kitchen_wall_cabinet.glb"],
	"normalKitchenIsland": ["res://assets/props/mansion/normal_kitchen_island.glb"],
	"luxuryKitchenCounter": ["res://assets/props/mansion/luxury_kitchen_counter.glb"],
	"luxuryKitchenSink": ["res://assets/props/mansion/luxury_kitchen_sink.glb"],
	"luxuryKitchenStove": ["res://assets/props/mansion/luxury_kitchen_stove.glb"],
	"luxuryKitchenFridge": ["res://assets/props/mansion/luxury_kitchen_fridge.glb"],
	"luxuryKitchenWallCabinet": ["res://assets/props/mansion/luxury_kitchen_wall_cabinet.glb"],
	"luxuryKitchenIsland": ["res://assets/props/mansion/luxury_kitchen_island.glb"],
	"gothicKitchenCounter": ["res://assets/props/mansion/gothic_kitchen_counter.glb"],
	"gothicKitchenSink": ["res://assets/props/mansion/gothic_kitchen_sink.glb"],
	"gothicKitchenStove": ["res://assets/props/mansion/gothic_kitchen_stove.glb"],
	"gothicKitchenFridge": ["res://assets/props/mansion/gothic_kitchen_fridge.glb"],
	"gothicKitchenWallCabinet": ["res://assets/props/mansion/gothic_kitchen_wall_cabinet.glb"],
	"gothicKitchenIsland": ["res://assets/props/mansion/gothic_kitchen_island.glb"],
	"normalBookcase": ["res://assets/props/mansion/normal_bookcase.glb"],
	"normalCoffeeTable": ["res://assets/props/mansion/normal_coffee_table.glb"],
	"normalTvConsole": ["res://assets/props/mansion/normal_tv_console.glb"],
	"normalEntryBench": ["res://assets/props/mansion/normal_entry_bench.glb"],
	"mansionDisplayCabinet": ["res://assets/props/mansion/mansion_display_cabinet.glb"],
	"mansionChaiseLounge": ["res://assets/props/mansion/mansion_chaise_lounge.glb"],
	"mansionUprightPiano": ["res://assets/props/mansion/mansion_upright_piano.glb"],
	"mansionBustPedestal": ["res://assets/props/mansion/mansion_bust_pedestal.glb"],
	"sandCastle": ["res://assets/props/beach/sand_castle.glb"],
	"beachUmbrella": ["res://assets/props/beach/beach_umbrella.glb"],
	"tikiBar": ["res://assets/props/beach/tiki_bar.glb"],
	"beachChair": ["res://assets/props/beach/beach_chair.glb"],
	"surfboardRack": ["res://assets/props/beach/surfboard_rack.glb"],
	"palmTree": ["res://assets/props/beach/palm_tree.glb"],
	"frozenBeachHut": ["res://assets/props/beach/frozen_beach_hut.glb"],
	"frozenTidelinePool": ["res://assets/props/beach/frozen_tideline_pool.glb"],
	"carnivalTicketBooth": ["res://assets/props/carnival/carnival_ticket_booth.glb"],
	"popcornCart": ["res://assets/props/carnival/popcorn_cart.glb"],
	"ringTossStall": ["res://assets/props/carnival/ring_toss_stall.glb"],
	"strengthTester": ["res://assets/props/carnival/strength_tester.glb"],
	"circusPedestal": ["res://assets/props/carnival/circus_pedestal.glb"],
	"shootingGallery": ["res://assets/props/carnival/ring_toss_stall.glb"],
	"whackAMole": ["res://assets/props/carnival/ring_toss_stall.glb"],
	"duckPond": ["res://assets/props/carnival/circus_pedestal.glb"],
	"carouselCenterpiece": ["res://assets/props/carnival/carousel_centerpiece.glb"],
	"lavaVent": ["res://assets/props/nether/lava_vent.glb"],
	"emberBrazier": ["res://assets/props/nether/ember_brazier.glb"],
	"basaltPillar": ["res://assets/props/nether/basalt_pillar.glb"],
	"basaltRubble": ["res://assets/props/nether/basalt_rubble.glb"],
	"magmaCrystalCluster": ["res://assets/props/nether/magma_crystal_cluster.glb"],
	"infernoAltar": ["res://assets/props/nether/inferno_altar.glb"],
	"infernoChainLantern": ["res://assets/props/nether/inferno_chain_lantern.glb"],
	"lavaPipeManifold": ["res://assets/props/nether/lava_pipe_manifold.glb"],
	"charredSupplyCrate": ["res://assets/props/nether/charred_supply_crate.glb"],
	"prisonCellGate": ["res://assets/props/prison/prison_cell_gate.glb"],
	"sewerLadder": ["res://assets/props/sewer/sewer_ladder.glb"],
	"sewerLadderTop": ["res://assets/props/sewer/sewer_ladder_top.glb"],
	"sewerManhole": ["res://assets/props/sewer/manhole_frame.glb"],
	"sewerFloorGrate": ["res://assets/props/sewer/sewer_floor_grate.glb"],
	"sewerValveWheel": ["res://assets/props/sewer/sewer_valve_wheel.glb"],
	"sewerPump": ["res://assets/props/sewer/sewer_pump.glb"],
	"sewerPipeRun": ["res://assets/props/sewer/sewer_pipe_run.glb"],
	"sewerOverflowGrate": ["res://assets/props/sewer/sewer_overflow_grate.glb"],
	"sewerLamp": ["res://assets/props/sewer/sewer_lamp.glb"],
	"sewerBridge": ["res://assets/props/sewer/sewer_bridge.glb"],
	"sewerGrateDeck": ["res://assets/props/sewer/sewer_grate_deck.glb"],
	"prisonBunk": ["res://assets/props/prison/prison_bunk.glb"],
	"prisonCafeteriaTable": ["res://assets/props/prison/prison_cafeteria_table.glb"],
	"prisonServingCounter": ["res://assets/props/prison/prison_serving_counter.glb"],
	"prisonTrayReturn": ["res://assets/props/prison/prison_tray_return.glb"],
	"prisonKitchenRack": ["res://assets/props/prison/prison_kitchen_rack.glb"],
	"dungeonCage": ["res://assets/props/prison/dungeon_cage.glb"],
	"restraintChair": ["res://assets/props/prison/restraint_chair.glb"],
	"hospitalBed": ["res://assets/props/blocky/hospitalBed_0.glb", "res://assets/props/blocky/hospitalBed_1.glb", "res://assets/props/blocky/hospitalBed_2.glb"],
	"hospitalCurtain": ["res://assets/props/blocky/hospitalCurtain_0.glb", "res://assets/props/blocky/hospitalCurtain_1.glb", "res://assets/props/blocky/hospitalCurtain_2.glb"],
	"ivDripStand": ["res://assets/props/blocky/ivDripStand.glb"],
	"vitalsMonitor": ["res://assets/props/blocky/vitalsMonitor.glb"],
	"nursesStation": ["res://assets/props/blocky/nursesStation_0.glb", "res://assets/props/blocky/nursesStation_1.glb"],
	"waitingChairs": ["res://assets/props/blocky/waitingChairs_0.glb", "res://assets/props/blocky/waitingChairs_1.glb", "res://assets/props/blocky/waitingChairs_2.glb"],
	"operatingTable": ["res://assets/props/blocky/operatingTable.glb"],
	"surgicalLight": ["res://assets/props/blocky/surgicalLight.glb"],
	"instrumentTrolley": ["res://assets/props/blocky/instrumentTrolley.glb"],
	"morgueCabinet": ["res://assets/props/blocky/morgueCabinet.glb"],
	"autopsyTable": ["res://assets/props/blocky/autopsyTable.glb"],
	"pharmacyShelf": ["res://assets/props/blocky/pharmacyShelf.glb"],
	"xrayMachine": ["res://assets/props/blocky/xrayMachine.glb"],
	"xrayLightbox": ["res://assets/props/blocky/xrayLightbox.glb"],
	"medicalSupplyRack": ["res://assets/props/blocky/medicalSupplyRack.glb"],
	"wheelchair": ["res://assets/props/blocky/wheelchair_0.glb", "res://assets/props/blocky/wheelchair_1.glb", "res://assets/props/blocky/wheelchair_2.glb"],
	"hospitalWardSign": ["res://assets/props/blocky/hospitalWardSign_0.glb", "res://assets/props/blocky/hospitalWardSign_1.glb", "res://assets/props/blocky/hospitalWardSign_2.glb"],
	"labBench": ["res://assets/props/blocky/labBench.glb"],
	"fumeHood": ["res://assets/props/blocky/fumeHood.glb"],
	"specimenTank": ["res://assets/props/blocky/specimenTank_0.glb", "res://assets/props/blocky/specimenTank_1.glb", "res://assets/props/blocky/specimenTank_2.glb"],
	"containmentCell": ["res://assets/props/blocky/containmentCell.glb"],
	"labCoolingUnit": ["res://assets/props/blocky/labCoolingUnit.glb"],
	"controlConsole": ["res://assets/props/blocky/controlConsole.glb"],
	"monitorWall": ["res://assets/props/blocky/monitorWall.glb"],
	"divePod": ["res://assets/props/blocky/divePod.glb"],
	"divePodFilm": ["res://assets/props/blocky/divePodFilm.glb"],
	"divePodLit": ["res://assets/props/blocky/divePodLit.glb"],
	"diveHeadsetStand": ["res://assets/props/blocky/diveHeadsetStand.glb"],
	"diveHeadsetShelf": ["res://assets/props/blocky/diveHeadsetShelf.glb"],
	"diveConsole": ["res://assets/props/blocky/diveConsole.glb"],
	"deconShower": ["res://assets/props/blocky/deconShower.glb"],
	"coldStorageUnit": ["res://assets/props/blocky/coldStorageUnit.glb"],
	"labWhiteboard": ["res://assets/props/blocky/labWhiteboard.glb"],
	"hazardSign": ["res://assets/props/blocky/hazardSign_0.glb", "res://assets/props/blocky/hazardSign_1.glb"],
	"labGlassPartition": ["res://assets/props/blocky/labGlassPartition.glb"],
	"labStool": ["res://assets/props/blocky/labStool_0.glb", "res://assets/props/blocky/labStool_1.glb", "res://assets/props/blocky/labStool_2.glb"],
	"labMicroscope": ["res://assets/props/blocky/labMicroscope.glb"],
	"gasCylinderRack": ["res://assets/props/blocky/gasCylinderRack.glb"],
	"biohazardBin": ["res://assets/props/blocky/biohazardBin.glb"],
	"raisedPlanter": ["res://assets/props/blocky/raisedPlanter_0.glb", "res://assets/props/blocky/raisedPlanter_1.glb", "res://assets/props/blocky/raisedPlanter_2.glb"],
	"pottingBench": ["res://assets/props/blocky/pottingBench_0.glb", "res://assets/props/blocky/pottingBench_1.glb", "res://assets/props/blocky/pottingBench_2.glb"],
	"pottedPalm": ["res://assets/props/blocky/pottedPalm_0.glb", "res://assets/props/blocky/pottedPalm_1.glb", "res://assets/props/blocky/pottedPalm_2.glb"],
	"bananaPlant": ["res://assets/props/blocky/bananaPlant_0.glb", "res://assets/props/blocky/bananaPlant_1.glb"],
	"saguaroCactus": ["res://assets/props/blocky/saguaroCactus.glb"],
	"cactusCluster": ["res://assets/props/blocky/cactusCluster.glb"],
	"seedlingRack": ["res://assets/props/blocky/seedlingRack.glb"],
	"irrigationManifold": ["res://assets/props/blocky/irrigationManifold_0.glb", "res://assets/props/blocky/irrigationManifold_1.glb", "res://assets/props/blocky/irrigationManifold_2.glb"],
	"mistingPost": ["res://assets/props/blocky/mistingPost.glb"],
	"overgrowthPatch": ["res://assets/props/blocky/overgrowthPatch.glb"],
	"hangingVines": ["res://assets/props/blocky/hangingVines_0.glb", "res://assets/props/blocky/hangingVines_1.glb"],
	"domeFountain": ["res://assets/props/blocky/domeFountain.glb"],
	"wateringCart": ["res://assets/props/blocky/wateringCart.glb"],
	"greenhouseBench": ["res://assets/props/blocky/greenhouseBench_0.glb", "res://assets/props/blocky/greenhouseBench_1.glb", "res://assets/props/blocky/greenhouseBench_2.glb"],
	"compostBins": ["res://assets/props/blocky/compostBins_0.glb", "res://assets/props/blocky/compostBins_1.glb"],
	"shopShelf": ["res://assets/props/blocky/shopShelf_0.glb", "res://assets/props/blocky/shopShelf_1.glb", "res://assets/props/blocky/shopShelf_2.glb"],
	"shopFridge": ["res://assets/props/blocky/shopFridge_0.glb", "res://assets/props/blocky/shopFridge_1.glb"],
	"checkoutCounter": ["res://assets/props/blocky/checkoutCounter_0.glb", "res://assets/props/blocky/checkoutCounter_1.glb", "res://assets/props/blocky/checkoutCounter_2.glb"],
	"displayCase": ["res://assets/props/blocky/displayCase_0.glb", "res://assets/props/blocky/displayCase_1.glb", "res://assets/props/blocky/displayCase_2.glb"],
	"coffeeStation": ["res://assets/props/blocky/coffeeStation_0.glb", "res://assets/props/blocky/coffeeStation_1.glb"],
	"donutFryer": ["res://assets/props/blocky/donutFryer.glb"],
	"bakeryRack": ["res://assets/props/blocky/bakeryRack_0.glb", "res://assets/props/blocky/bakeryRack_1.glb", "res://assets/props/blocky/bakeryRack_2.glb"],
	"dinerStool": ["res://assets/props/blocky/dinerStool_0.glb", "res://assets/props/blocky/dinerStool_1.glb", "res://assets/props/blocky/dinerStool_2.glb"],
	"dinerBooth": ["res://assets/props/blocky/dinerBooth_0.glb", "res://assets/props/blocky/dinerBooth_1.glb", "res://assets/props/blocky/dinerBooth_2.glb"],
	"menuBoard": ["res://assets/props/blocky/menuBoard_0.glb", "res://assets/props/blocky/menuBoard_1.glb", "res://assets/props/blocky/menuBoard_2.glb"],
	"donutSign": ["res://assets/props/blocky/donutSign_0.glb", "res://assets/props/blocky/donutSign_1.glb"],
	"washingMachine": ["res://assets/props/blocky/washingMachine_0.glb", "res://assets/props/blocky/washingMachine_1.glb", "res://assets/props/blocky/washingMachine_2.glb"],
	"dryerStack": ["res://assets/props/blocky/dryerStack_0.glb", "res://assets/props/blocky/dryerStack_1.glb"],
	"flowerStand": ["res://assets/props/blocky/flowerStand_0.glb", "res://assets/props/blocky/flowerStand_1.glb"],
	"barberChair": ["res://assets/props/blocky/barberChair_0.glb", "res://assets/props/blocky/barberChair_1.glb", "res://assets/props/blocky/barberChair_2.glb"],
	"barberStation": ["res://assets/props/blocky/barberStation_0.glb", "res://assets/props/blocky/barberStation_1.glb"],
	"clothesRack": ["res://assets/props/blocky/clothesRack_0.glb", "res://assets/props/blocky/clothesRack_1.glb", "res://assets/props/blocky/clothesRack_2.glb"],
	"tvWall": ["res://assets/props/blocky/tvWall_0.glb", "res://assets/props/blocky/tvWall_1.glb", "res://assets/props/blocky/tvWall_2.glb"],
	"cinemaSeats": ["res://assets/props/blocky/cinemaSeats_0.glb", "res://assets/props/blocky/cinemaSeats_1.glb"],
	"cinemaScreen": ["res://assets/props/blocky/cinemaScreen_0.glb", "res://assets/props/blocky/cinemaScreen_1.glb"],
	"ticketBooth": ["res://assets/props/blocky/ticketBooth_0.glb", "res://assets/props/blocky/ticketBooth_1.glb", "res://assets/props/blocky/ticketBooth_2.glb"],
	"concessionCounter": ["res://assets/props/blocky/concessionCounter_0.glb", "res://assets/props/blocky/concessionCounter_1.glb"],
	"foodCourtTable": ["res://assets/props/blocky/foodCourtTable_0.glb", "res://assets/props/blocky/foodCourtTable_1.glb", "res://assets/props/blocky/foodCourtTable_2.glb"],
	"mallPlanter": ["res://assets/props/blocky/mallPlanter_0.glb", "res://assets/props/blocky/mallPlanter_1.glb", "res://assets/props/blocky/mallPlanter_2.glb"],
	"mallBench": ["res://assets/props/blocky/mallBench_0.glb", "res://assets/props/blocky/mallBench_1.glb"],
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

## PropModelCatalog.LIGHT_PROFILES as the code constant had it before the lights moved into data/props `light` (094).
const FROZEN_LIGHTS := {
	"floorLamp": {"color": Color("ffe1a3"), "energy": .52, "range": 4.0, "height": 1.52},
	"tableLamp": {"color": Color("ffd99a"), "energy": .38, "range": 3.0, "height": .54},
	"bedsideLamp": {"color": Color("ffd5a0"), "energy": .32, "range": 2.6, "height": .54},
	"ceilingLight": {"color": Color("dff8ff"), "energy": .62, "range": 4.8, "height": .12},
	"ceilingFan": {"color": Color("fff0c2"), "energy": .54, "range": 4.4, "height": .16},
	"diningChandelier": {"color": Color("ffd58c"), "energy": .66, "range": 5.2, "height": .55},
	"wallSconce": {"color": Color("ffd292"), "energy": .36, "range": 3.2, "height": 1.62},
	"sewerLamp": {"color": Color("ffa24a"), "energy": .42, "range": 5.0, "height": 0.0},
	"surgicalLight": {"color": Color("f4fbff"), "energy": .85, "range": 4.6, "height": .2},
	"specimenTank": {"color": Color("5fe8d8"), "energy": .42, "range": 3.0, "height": 1.2},
	"divePodLit": {"color": Color("8fe6f0"), "energy": .18, "range": 2.2, "height": .6},
	"xrayLightbox": {"color": Color("e8f4ff"), "energy": .26, "range": 2.4, "height": 1.5},
	"donutSign": {"color": Color("ff8fc8"), "energy": .38, "range": 3.0, "height": .7},
	"menuBoard": {"color": Color("ffe0b0"), "energy": .24, "range": 2.4, "height": .45},
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
		var base := "res://assets/props/maze/%s" % OFFICE_FILES[i]
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
	_check_lights()
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


## Fixture lights as data (lr.prop/1 `light`): the table is exactly the old constant (keys, order, colour, energy, range,
## height), every light is a shadowless omni with no sideways offset (so spawned lights sit where they did), and a prop
## with no `light` gives none.
func _check_lights() -> void:
	var table := PropModelCatalog.LIGHT_PROFILES
	_expect(table.is_read_only(), "PropModelCatalog.LIGHT_PROFILES became writable")
	_expect(not table.values().has(ContentRegistry.DATA), "an unresolved @data light is left")
	_expect(var_to_str(table.keys()) == var_to_str(FROZEN_LIGHTS.keys()), "LIGHT_PROFILES key order changed: %s" % [table.keys()])
	for id in FROZEN_LIGHTS:
		var want: Dictionary = FROZEN_LIGHTS[id]
		var got := PropModelCatalog.light_profile(id)
		for key in want:
			_expect(var_to_str(got.get(key)) == var_to_str(want[key]),
				"%s light %s is %s, was %s" % [id, key, var_to_str(got.get(key)), var_to_str(want[key])])
		_expect(got.get("type") == "omni" and got.get("shadows") == false and got.get("offset") == Vector3(0, want["height"], 0),
			"%s light is not the shadowless centred omni it was: %s" % [id, got])
		_expect(ContentRegistry.get_def("props", id).has("light"), "%s light is not read from res://data/props" % id)
	for id in ContentRegistry.ids("props"):
		_expect(ContentRegistry.get_def("props", id).has("light") == FROZEN_LIGHTS.has(id),
			"%s has a light in data but not in LIGHT_PROFILES (or the other way)" % id)
	_expect(PropModelCatalog.light_profile("officeDesk").is_empty(), "a prop without a light gives one")
	var copy := PropModelCatalog.light_profile("floorLamp")
	copy["energy"] = 9.0
	_expect(float(PropModelCatalog.light_profile("floorLamp")["energy"]) == .52, "light_profile hands out the shared table")
	# a pack-style light with every key, and the defaults
	var path := "user://data_props_light_fixture.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "light": {"type": "omni", '
		+ '"color": "#80ff00", "energy": 1, "range": 6, "offset": [0.5, 2, -1], "shadows": true}}, '
		+ '{"id": "b", "models": [], "light": {"color": "102030", "energy": 0.4, "range": 3}}]}')
	file.close()
	var parsed := ContentRegistry.parse_file(path, "props")
	DirAccess.remove_absolute(path)
	_expect((parsed["errors"] as Array).is_empty() and (parsed["defs"] as Array).size() == 2, "a good prop light is rejected: %s" % [parsed["errors"]])
	if (parsed["defs"] as Array).size() == 2:
		var full: Dictionary = parsed["defs"][0]["light"]
		_expect(full["color"] == Color("80ff00") and full["energy"] == 1.0 and full["range"] == 6.0
			and full["offset"] == Vector3(.5, 2, -1) and full["height"] == 2.0 and full["shadows"] == true and full["type"] == "omni",
			"a full prop light parsed wrong: %s" % full)
		var plain: Dictionary = parsed["defs"][1]["light"]
		_expect(plain["offset"] == Vector3(0, .5, 0) and plain["height"] == .5 and plain["shadows"] == false and plain["type"] == "omni",
			"prop light defaults wrong: %s" % plain)


func _check_rejections() -> void:
	var cases := {
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "light": {"energy": 1, "range": 3}}]}': "\"light\" must be a light",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "light": {"color": "nope", "energy": 1, "range": 3}}]}': "\"light\" must be a light",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "light": {"color": "ffffff", "energy": 50, "range": 3}}]}': "\"light\" must be a light",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "light": {"color": "ffffff", "energy": 1, "range": 40}}]}': "\"light\" must be a light",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "light": {"color": "ffffff", "energy": 1, "range": 3, "offset": [0, 9, 0]}}]}': "\"light\" must be a light",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "light": {"color": "ffffff", "energy": 1, "range": 3, "type": "spot"}}]}': "\"light\" must be a light",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "light": {"color": "ffffff", "energy": 1, "range": 3, "script": "res://x.gd"}}]}': "\"light\" must be a light",
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
