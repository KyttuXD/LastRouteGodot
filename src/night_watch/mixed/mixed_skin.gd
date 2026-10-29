class_name MixedSkin
extends RefCounted

## Mixed Shift's ROTATION: nine SKINS, one for each mode's map (its own transit hub, Classic's pizzeria, Dead Air's radio station, Masked Hours' party floor, Bedtime's house wing, the Facility,
## Salvage Run's yard, the Descent's shaft, Open Air's campsite). Mixed's rules (MixedLogic) run on one fixed shape -- nine camera rooms, two door halls, three vents, the music box -- so a skin gives
## that shape the other map's names, palette, light, props and minimap labels. Because every threat's role is already played on that shape (door arrival, vent run, camera stare, music box, winding),
## EVERY hunter works on EVERY skin: a map without vents still has the duct slot (named for the map: crawlspace, shaft, pipe run), and nothing is placed that the shape cannot walk.
##
## A skin is {id, name, mode, labels {map room: name}, tint (multiplies floors and walls), light (ambient colour), sky (background), kit (the prop set), theme}.
## `pick(seed)` is the rotation: a shuffled bag of all nine, never the same skin twice in a row, refilled when empty; ENDLESS draws the next one at each roster rotation.

const SKINS := [
	{"id": "transit", "name": "TRANSIT HUB", "mode": "mixed", "kit": "bench", "tint": Color(1.0, 1.0, 1.0), "light": Color(0.38, 0.40, 0.55), "sky": Color(0.02, 0.02, 0.03),
		"labels": {"platform": "PLATFORM", "concourse": "CONCOURSE", "ticket_hall": "TICKET HALL", "west_arcade": "WEST ARCADE", "lost_property": "LOST PROPERTY", "cafe": "CAFE", "east_arcade": "EAST ARCADE", "newsstand": "NEWSSTAND", "duct": "VENT RUN"},
		"theme": "the station as it is"},
	{"id": "pizzeria", "name": "THE PIZZERIA", "mode": "classic", "kit": "pizzeria", "tint": Color(1.3, 1.1, 0.9), "light": Color(0.5, 0.38, 0.34), "sky": Color(0.03, 0.02, 0.02),
		"labels": {"platform": "SHOW STAGE", "concourse": "DINING AREA", "ticket_hall": "BACKSTAGE", "west_arcade": "WEST HALL", "lost_property": "SUPPLY CLOSET", "cafe": "KITCHEN", "east_arcade": "EAST HALL", "newsstand": "CORNER", "duct": "VENT RUN"},
		"theme": "Classic's pizzeria: checker floor, party tables, a show stage"},
	{"id": "station", "name": "RADIO STATION", "mode": "lure", "kit": "studio", "tint": Color(0.9, 1.0, 1.25), "light": Color(0.28, 0.42, 0.5), "sky": Color(0.01, 0.03, 0.04),
		"labels": {"platform": "ON-AIR STUDIO", "concourse": "NEWSROOM", "ticket_hall": "RECORDS", "west_arcade": "WEST CORRIDOR", "lost_property": "TAPE VAULT", "cafe": "BREAK ROOM", "east_arcade": "EAST CORRIDOR", "newsstand": "TRANSMITTER", "duct": "CABLE RUN"},
		"theme": "Dead Air: mic stands, speaker stacks, a blinking on-air light"},
	{"id": "party", "name": "PARTY FLOOR", "mode": "mask", "kit": "party", "tint": Color(1.4, 1.1, 1.5), "light": Color(0.48, 0.36, 0.55), "sky": Color(0.03, 0.01, 0.04),
		"labels": {"platform": "PRIZE STAGE", "concourse": "PARTY ROOM", "ticket_hall": "ARCADE", "west_arcade": "LEFT HALL", "lost_property": "PARTS CLOSET", "cafe": "KITCHEN", "east_arcade": "RIGHT HALL", "newsstand": "GAME AREA", "duct": "AIR DUCT"},
		"theme": "Masked Hours: balloons, tables, streamers, arcade cabinets"},
	{"id": "house", "name": "THE HOUSE WING", "mode": "bedroom", "kit": "house", "tint": Color(1.25, 1.05, 0.85), "light": Color(0.42, 0.34, 0.3), "sky": Color(0.03, 0.02, 0.01),
		"labels": {"platform": "NURSERY", "concourse": "LANDING", "ticket_hall": "PLAYROOM", "west_arcade": "WEST PASSAGE", "lost_property": "LINEN CLOSET", "cafe": "STUDY", "east_arcade": "EAST PASSAGE", "newsstand": "TOY ROOM", "duct": "CRAWLSPACE"},
		"theme": "Bedtime: beds, wardrobes, toy chests, a night light"},
	{"id": "facility", "name": "THE FACILITY", "mode": "story", "kit": "lab", "tint": Color(0.85, 1.15, 1.0), "light": Color(0.3, 0.46, 0.4), "sky": Color(0.01, 0.03, 0.02),
		"labels": {"platform": "CONTROL ROOM", "concourse": "ATRIUM", "ticket_hall": "ARCHIVE", "west_arcade": "WEST CORRIDOR", "lost_property": "SPECIMEN STORE", "cafe": "STAFF ROOM", "east_arcade": "EAST CORRIDOR", "newsstand": "LAB", "duct": "SERVICE PIPE"},
		"theme": "the Facility: lab benches, consoles, pipe racks, a green status light"},
	{"id": "yard", "name": "SALVAGE YARD", "mode": "dayshift", "kit": "yard", "tint": Color(1.3, 1.0, 0.8), "light": Color(0.5, 0.4, 0.3), "sky": Color(0.04, 0.025, 0.01),
		"labels": {"platform": "CRANE DECK", "concourse": "MAIN YARD", "ticket_hall": "SCRAP HEAP", "west_arcade": "PORT ALLEY", "lost_property": "PARTS CAGE", "cafe": "SITE OFFICE", "east_arcade": "STARBOARD ALLEY", "newsstand": "CARGO BAY", "duct": "BILGE RUN"},
		"theme": "Salvage Run: containers, scrap, barrels, a crane arm"},
	{"id": "shaft", "name": "THE SHAFT", "mode": "descent", "kit": "shaft", "tint": Color(0.8, 0.85, 1.0), "light": Color(0.26, 0.3, 0.46), "sky": Color(0.005, 0.01, 0.03),
		"labels": {"platform": "LIFT HEAD", "concourse": "MID LANDING", "ticket_hall": "MACHINE ROOM", "west_arcade": "LEFT GANTRY", "lost_property": "COUNTERWEIGHTS", "cafe": "CONTROL CAB", "east_arcade": "RIGHT GANTRY", "newsstand": "CABLE DECK", "duct": "SHAFT WALL"},
		"theme": "the Descent: pillars, hanging cables, lift frames"},
	{"id": "camp", "name": "THE CAMPSITE", "mode": "extra", "kit": "camp", "tint": Color(0.9, 1.15, 0.85), "light": Color(0.28, 0.4, 0.34), "sky": Color(0.01, 0.025, 0.02),
		"labels": {"platform": "BUS STOP", "concourse": "FIRE CIRCLE", "ticket_hall": "SUPPLY SHED", "west_arcade": "WEST TRAIL", "lost_property": "WOODPILE", "cafe": "MESS TENT", "east_arcade": "EAST TRAIL", "newsstand": "LOOKOUT", "duct": "DRAIN PIPE"},
		"theme": "Open Air: tents, logs, lanterns"},
]

## the bag of skins not yet visited, and the one just used (a process-wide rotation: a new night is a new scene)
static var _bag: Array = []
static var _last := ""


static func ids() -> Array:
	var out := []
	for s in SKINS:
		out.append(String(s["id"]))
	return out


static func index_of(id: String) -> int:
	for i in SKINS.size():
		if String(SKINS[i]["id"]) == id:
			return i
	return 0


static func skin(index: int) -> Dictionary:
	return SKINS[clampi(index, 0, SKINS.size() - 1)]


static func reset() -> void:
	_bag = []
	_last = ""


## The next skin of the rotation, as an index: from a seeded shuffle of the not-yet-visited skins; a fresh bag never starts with the skin just used.
static func pick(seed_number: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_number) + 17 * (SKINS.size() - _bag.size())
	if _bag.is_empty():
		_bag = ids()
		for i in range(_bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = t
		if _bag.size() > 1 and String(_bag[0]) == _last:
			var k := rng.randi_range(1, _bag.size() - 1)
			var u = _bag[0]
			_bag[0] = _bag[k]
			_bag[k] = u
	var id := String(_bag.pop_front())
	_last = id
	return index_of(id)


## The skin's layout for the camera screen: Mixed's hub with this skin's names.
static func layout_for(index: int) -> Dictionary:
	var layout := MixedMap.map_layout()
	layout["labels"] = (skin(index)["labels"] as Dictionary).duplicate()
	layout["theme"] = String(skin(index)["theme"])
	return layout
