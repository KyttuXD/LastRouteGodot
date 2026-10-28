class_name MusicWing
extends RefCounted

## The music wing (docs/MUSIC_WING.md), kept out of StreamedRouteGenerator so the BIOMES lane can resize rooms freely.
##
##   carve()       a "rehearsal_hall" great-hall slot (21x21, one door on the vertical hall, StreamedRouteGenerator.large_plan)
##                 split into a stage, an instrument store, a practice room and a control room with a glass-walled vocal
##                 booth off a three-wide wing hall
##   room_specs()  the furniture recipes of those rooms, the mall music store and the carnival music stage
##
## A 21x21 slot with its door in the middle of one side holds two nine-deep bands of rooms either side of a three-wide
## hall, so the stage is 13x9 (not the 15x13 first sketched) and the wing has one practice room.


const TEMPLATES := ["music_stage", "practice_room", "instrument_storage", "recording_booth", "music_store",
	"carnival_stage"]
## The great-hall type the generator hooks (LARGE_ROOM_TYPES), and the wing's rooms (canonical layout: door on the east
## side at local (20, 10); a west-side slot is mirrored).
const LARGE_TYPE := "rehearsal_hall"
const SLOT := 21
const LAYOUT := [
	{"type": "music_stage", "rect": Rect2i(0, 0, 13, 9)},
	{"type": "instrument_storage", "rect": Rect2i(12, 0, 9, 9)},
	{"type": "practice_room", "rect": Rect2i(0, 12, 11, 9)},
	{"type": "recording_booth", "rect": Rect2i(10, 12, 11, 9)},
]
const HALL := Rect2i(1, 9, 19, 3)
## Studio monitors stand on the mixing desk: its 0.82 m top at hunter scale 1.5.
const MIXING_DESK_TOP := 1.23
## Room sizes (cells) this lane declares for its own rooms; real sizes x 1.5 (docs/ROOM_SIZES.md format).
const SIZE_PROFILES := {
	"music_stage": {"min": Vector2i(9, 9), "preferred": Vector2i(13, 9), "max": Vector2i(21, 21)},
	"carnival_stage": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9)},
	"practice_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13)},
	"instrument_storage": {"min": Vector2i(9, 9), "preferred": Vector2i(9, 9), "max": Vector2i(11, 11)},
	"recording_booth": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13)},
	"music_store": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9)},
}


## Carves the wing into `rect` (a SLOT x SLOT area the generator already carved open and sealed, door `door` on its
## perimeter). Returns {"rooms": [{"room_type", "rect", "doorway"}], "hall": Rect2i, "circulation": [Vector2i]} in grid
## coordinates; the caller wraps rooms with _room_entry and records the hall as a corridor.
static func carve(grid: Array, rect: Rect2i, door: Vector2i, _rng = null) -> Dictionary:
	var flip := door.x == rect.position.x   # door on the west side: mirror the canonical (east-door) layout
	var rooms := []
	for entry in LAYOUT:
		var local: Rect2i = entry["rect"]
		var room_rect := _place(local, rect, flip)
		var north := local.position.y == 0
		var door_local := Vector2i(local.position.x + local.size.x / 2, local.end.y - 1 if north else local.position.y)
		var doorway := _place_cell(door_local, rect, flip)
		StreamedRouteGenerator._carve_rect(grid, room_rect)
		StreamedRouteGenerator._seal_room_perimeter_except(grid, room_rect, doorway)
		rooms.append({"room_type": entry["type"], "rect": room_rect, "doorway": doorway})
	var hall := _place(HALL, rect, flip)
	StreamedRouteGenerator._carve_rect(grid, hall)
	var circulation := []
	for z in range(hall.position.y, hall.end.y):
		for x in range(hall.position.x, hall.end.x):
			circulation.append(Vector2i(x, z))
	circulation.append(door)
	for room in rooms:
		circulation.append(room["doorway"])
	return {"rooms": rooms, "hall": hall, "circulation": circulation}


static func _place(local: Rect2i, slot: Rect2i, flip: bool) -> Rect2i:
	var x := slot.position.x + (SLOT - local.end.x if flip else local.position.x)
	return Rect2i(x, slot.position.y + local.position.y, local.size.x, local.size.y)


static func _place_cell(local: Vector2i, slot: Rect2i, flip: bool) -> Vector2i:
	return Vector2i(slot.position.x + (SLOT - 1 - local.x if flip else local.x), slot.position.y + local.y)


static func room_specs(template: String, half: int, depth_span: int, mirror: int) -> Array:
	var front := depth_span - 3
	var mid := front / 2
	var specs := []
	match template:
		"practice_room":
			# foam panels along the back wall, a kit and an amp facing the singer's mic
			for panel_side in range(-half, half + 1, 2):
				specs.append(StreamedRouteGenerator._sp("acousticPanel", panel_side, 0, "open", StreamedRouteGenerator._MOUNT))
			specs.append(StreamedRouteGenerator._sp("drumKit", -2 * mirror, 1, "open"))
			specs.append(StreamedRouteGenerator._sp("ampStack", 2 * mirror, 0, "open", StreamedRouteGenerator._WALL))
			specs.append(StreamedRouteGenerator._sp("electricGuitarStand", mini(half, 4) * mirror, 1, "center"))
			specs.append(StreamedRouteGenerator._sp("bassGuitarStand", -mini(half, 4) * mirror, front - 2, "center"))
			specs.append(StreamedRouteGenerator._sp("micStand", 1 * mirror, front - 3, "back"))
			specs.append(StreamedRouteGenerator._sp("musicStand", 3 * mirror, front - 3, "back"))
			specs.append(StreamedRouteGenerator._sp("comboAmp", mini(half, 4) * mirror, front - 2, "center"))
			specs.append(StreamedRouteGenerator._sp("cableCoil", 1 * mirror, 2, "open", StreamedRouteGenerator._LOOSE))
			specs.append(StreamedRouteGenerator._sp("ceilingLight", 0, mid, "open", StreamedRouteGenerator._LOOSE))
		"instrument_storage":
			for hanger_side in [-2, 2]:
				specs.append(StreamedRouteGenerator._sp("guitarWallHanger", hanger_side, 0, "open", StreamedRouteGenerator._MOUNT))
			specs.append(StreamedRouteGenerator._sp("instrumentCases", -mini(half, 4) * mirror, 0, "open", StreamedRouteGenerator._WALL))
			specs.append(StreamedRouteGenerator._sp("storageShelving", mini(half, 4) * mirror, 0, "open", StreamedRouteGenerator._WALL))
			specs.append(StreamedRouteGenerator._sp("acousticGuitarStand", -2 * mirror, 2, "open"))
			specs.append(StreamedRouteGenerator._sp("bassGuitarStand", 2 * mirror, 2, "open"))
			specs.append(StreamedRouteGenerator._sp("keyboardStand", -2 * mirror, front - 2, "center"))
			specs.append(StreamedRouteGenerator._sp("instrumentCases", mini(half, 4) * mirror, front - 2, "center"))
			specs.append(StreamedRouteGenerator._sp("comboAmp", 3 * mirror, front - 3, "center"))
			specs.append(StreamedRouteGenerator._sp("cableCoil", 0, 2, "open", StreamedRouteGenerator._LOOSE))
			specs.append(StreamedRouteGenerator._sp("cableCoil", -3 * mirror, front - 4, "open", StreamedRouteGenerator._LOOSE))
			specs.append(StreamedRouteGenerator._sp("ceilingLight", 0, mid, "open", StreamedRouteGenerator._LOOSE))
		"recording_booth":
			# a glass wall across the room with a gap in the middle: the vocal booth behind it, the control room in front
			var glass := maxi(2, mid)
			for glass_side in range(-half, half + 1, 2):
				if absi(glass_side) >= 2:
					specs.append(StreamedRouteGenerator._sp("labGlassPartition", glass_side, glass, "open"))
			specs.append(StreamedRouteGenerator._sp("micStand", -1 * mirror, 1, "open"))
			specs.append(StreamedRouteGenerator._sp("musicStand", 1 * mirror, 1, "open"))
			specs.append(StreamedRouteGenerator._sp("onAirSign", 2 * mirror, 0, "open", StreamedRouteGenerator._MOUNT))
			for panel_side in [-mini(half, 4), -2]:
				specs.append(StreamedRouteGenerator._sp("acousticPanel", panel_side * mirror, 0, "open", StreamedRouteGenerator._MOUNT))
			specs.append(StreamedRouteGenerator._sp("mixingDesk", -2 * mirror, glass + 2, "back"))
			specs.append(StreamedRouteGenerator._sp("studioMonitors", -2 * mirror, glass + 2, "back", {"solid": false, "mount_y": MIXING_DESK_TOP}))
			specs.append(StreamedRouteGenerator._sp("officeChair", -2 * mirror, glass + 3, "back"))
			specs.append(StreamedRouteGenerator._sp("rackGear", mini(half, 4) * mirror, glass + 2, "center"))
			specs.append(StreamedRouteGenerator._sp("ceilingLight", 0, glass + 2, "open", StreamedRouteGenerator._LOOSE))
		"music_store":
			# a guitar shop: wall racks of guitars, instruments on stands down the floor, a counter by the door
			for hanger_side in range(-half + 1, half, 3):
				specs.append(StreamedRouteGenerator._sp("guitarWallHanger", hanger_side, 0, "open", StreamedRouteGenerator._MOUNT))
			for stand_side in range(-half + 1, half, 3):
				var stand: String = ["electricGuitarStand", "acousticGuitarStand", "bassGuitarStand"][posmod(stand_side, 3)]
				specs.append(StreamedRouteGenerator._sp(stand, stand_side, 2, "open"))
			specs.append(StreamedRouteGenerator._sp("keyboardStand", -4 * mirror, front - 2, "center"))
			specs.append(StreamedRouteGenerator._sp("ampStack", 5 * mirror, front - 2, "center"))
			specs.append(StreamedRouteGenerator._sp("comboAmp", 3 * mirror, front - 2, "center"))
			specs.append(StreamedRouteGenerator._sp("checkoutCounter", -(half - 1) * mirror, front - 1, "center"))
			specs.append(StreamedRouteGenerator._sp("ceilingLight", 0, mid, "open", StreamedRouteGenerator._LOOSE))
		"music_stage", "carnival_stage":
			# the band at the back under the light truss, monitors facing them at the stage edge, which sits two rows in
			# front of the entrance in a nine-deep room and six rows out in a great hall
			var edge := mini(6, front - 2)
			specs.append(StreamedRouteGenerator._sp("stageLightRig", 0, 0, "open", StreamedRouteGenerator._WALL))
			specs.append(StreamedRouteGenerator._sp("drumKit", 0, mini(2, edge - 2), "open"))
			for amp_side in [-4, 4]:
				specs.append(StreamedRouteGenerator._sp("ampStack", amp_side, 0, "open", StreamedRouteGenerator._WALL))
			for mic_side in [-2, 2]:
				specs.append(StreamedRouteGenerator._sp("micStand", mic_side, edge - 2, "open"))
			specs.append(StreamedRouteGenerator._sp("electricGuitarStand", -4, edge - 1, "open"))
			specs.append(StreamedRouteGenerator._sp("bassGuitarStand", 4, edge - 1, "open"))
			if half >= 6:
				specs.append(StreamedRouteGenerator._sp("keyboardStand", -6, 2, "center"))
				for pa_side in [-half, half]:
					specs.append(StreamedRouteGenerator._sp("paSpeakerPole", pa_side, 1, "open"))
			for monitor_side in [-2, 0, 2]:
				specs.append(StreamedRouteGenerator._sp("stageMonitor", monitor_side, edge, "back"))
			specs.append(StreamedRouteGenerator._sp("cableRun", 0, edge + 1, "open", StreamedRouteGenerator._LOOSE))
			specs.append(StreamedRouteGenerator._sp("cableCoil", 3, edge - 1, "open", StreamedRouteGenerator._LOOSE))
			if template == "music_stage" and front >= 12:
				for row_depth in range(10, front - 3, 3):
					for chair_side in range(-half + 2, half - 1, 5):
						specs.append(StreamedRouteGenerator._sp("waitingChairs", chair_side, row_depth, "back"))
				specs.append(StreamedRouteGenerator._sp("mixingDesk", 0, front - 2, "back"))
				specs.append(StreamedRouteGenerator._sp("studioMonitors", 0, front - 2, "back", {"solid": false, "mount_y": MIXING_DESK_TOP}))
				specs.append(StreamedRouteGenerator._sp("rackGear", 3, front - 2, "back"))
			for light_depth in range(mid, front, 5):
				specs.append(StreamedRouteGenerator._sp("ceilingLight", 0, light_depth, "open", StreamedRouteGenerator._LOOSE))
	return specs
