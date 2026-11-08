class_name MusicWing
extends RefCounted

## The music wing, kept out of StreamedRouteGenerator so rooms can be resized freely.
##
##   carve()       the "rehearsal_hall": BOTH great-hall slots of one chunk (StreamedRouteGenerator.large_plan, 21x21 each,
##                 doors facing each other across the vertical hall). The west slot is the 15x13 stage, entered straight
##                 from the vertical hall; the east slot is a three-wide wing hall with two practice rooms, the instrument
##                 store and the control room with its glass-walled vocal booth. when a chunk cannot give both slots,
##                 there is no wing (never a compact one).
##   room_specs()  the furniture recipes of those rooms and the carnival music stage (the mall music store is
##                 data: res://data/rooms/music_store.json)


## Code recipes (room_specs). The mall's music_store is a data recipe, res://data/rooms/music_store.json (RoomRecipes).
const TEMPLATES := ["music_stage", "practice_room", "instrument_storage", "recording_booth", "carnival_stage"]
## The great-hall type the generator hooks (LARGE_ROOM_TYPES); a chunk takes it on both sides or not at all.
const LARGE_TYPE := "rehearsal_hall"
const SLOT := 21
## Canonical layouts with the slot's door on the east side at local (20, 10); a slot whose door is on its west side is
## mirrored. "stage" goes in the chunk's west slot, "rooms" in its east slot (part_for_side).
const LAYOUTS := {
	"stage": [{"type": "music_stage", "rect": Rect2i(6, 4, 15, 13), "door": "east"}],
	"rooms": [
		{"type": "practice_room", "rect": Rect2i(0, 0, 11, 9), "door": "south"},
		{"type": "practice_room", "rect": Rect2i(10, 0, 11, 9), "door": "south"},
		{"type": "instrument_storage", "rect": Rect2i(0, 12, 11, 9), "door": "north"},
		{"type": "recording_booth", "rect": Rect2i(10, 12, 11, 9), "door": "north"},
	],
}
## The wing hall of the "rooms" slot (none in the stage slot).
const HALL := Rect2i(1, 9, 19, 3)
## Studio monitors stand on the mixing desk: its 0.82 m top at hunter scale 1.5.
const MIXING_DESK_TOP := 1.23
## Room sizes (cells) the wing declares for its own rooms; real sizes x 1.5 (docs/ROOM_SIZES.md format).
const SIZE_PROFILES := {
	"music_stage": {"min": Vector2i(9, 9), "preferred": Vector2i(15, 13), "max": Vector2i(21, 21)},
	"carnival_stage": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9)},
	"practice_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13)},
	"instrument_storage": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(11, 11)},
	"recording_booth": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13)},
	"music_store": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9)},
}


## Which part of the wing a chunk side holds: side 0 (west slot) the stage, side 1 (east slot) the rooms.
static func part_for_side(side: int) -> String:
	return "stage" if side == 0 else "rooms"


## Carves `part` of the wing into `rect` (a SLOT x SLOT slot the generator already carved, door `door` on its perimeter):
## the slot is filled solid first, so only the rooms and the hall are open. Returns {"rooms": [{"room_type", "rect",
## "doorway"}], "hall": Rect2i (empty for the stage), "circulation": [Vector2i]} in grid coordinates; the caller wraps
## rooms with _room_entry and records a non-empty hall as a corridor.
static func carve(grid: Array, rect: Rect2i, door: Vector2i, _rng = null, part: String = "rooms") -> Dictionary:
	var flip := door.x == rect.position.x   # door on the west side: mirror the canonical (east-door) layout
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			grid[z][x] = 1
	var rooms := []
	for entry in LAYOUTS[part]:
		var local: Rect2i = entry["rect"]
		var room_rect := _place(local, rect, flip)
		var door_local: Vector2i
		match String(entry["door"]):
			"east": door_local = Vector2i(local.end.x - 1, 10)
			"south": door_local = Vector2i(local.position.x + local.size.x / 2, local.end.y - 1)
			_: door_local = Vector2i(local.position.x + local.size.x / 2, local.position.y)
		var doorway := _place_cell(door_local, rect, flip)
		StreamedRouteGenerator._carve_rect(grid, room_rect)
		StreamedRouteGenerator._seal_room_perimeter_except(grid, room_rect, doorway)
		rooms.append({"room_type": entry["type"], "rect": room_rect, "doorway": doorway})
	var hall := Rect2i()
	var circulation := [door]
	if part == "rooms":
		hall = _place(HALL, rect, flip)
		StreamedRouteGenerator._carve_rect(grid, hall)
		grid[door.y][door.x] = 0
		for z in range(hall.position.y, hall.end.y):
			for x in range(hall.position.x, hall.end.x):
				circulation.append(Vector2i(x, z))
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
			if template == "music_stage" and front >= edge + 6:
				for row_depth in range(edge + 3, front - 2, 3):
					for chair_side in range(-half + 2, half - 1, 5):
						specs.append(StreamedRouteGenerator._sp("waitingChairs", chair_side, row_depth, "back"))
				specs.append(StreamedRouteGenerator._sp("mixingDesk", 0, front - 2, "back"))
				specs.append(StreamedRouteGenerator._sp("studioMonitors", 0, front - 2, "back", {"solid": false, "mount_y": MIXING_DESK_TOP}))
				specs.append(StreamedRouteGenerator._sp("rackGear", 3, front - 2, "back"))
			for light_depth in range(mid, front, 5):
				specs.append(StreamedRouteGenerator._sp("ceilingLight", 0, light_depth, "open", StreamedRouteGenerator._LOOSE))
	return specs
