extends RefCounted

## The hospital, research lab and greenhouse biomes over many seeds: each one generates, every room of theirs gets its
## furnished recipe with the props that make it that room (a ward has beds, a morgue its drawer cabinets, the dome its
## fountain), solid props never interpenetrate, the doorway and the cell inside it stay clear, and every free floor cell
## of a room is reachable from its door (so hunters and players can walk the whole room). Hall widths, humps, room sizes
## and seam connectivity are the shared suites' job; they sample every biome in StreamedRouteGenerator.BIOMES.

const SEEDS := ["BIOME-A", "BIOME-B", "BIOME-C", "BIOME-D", "KYTTU-LAB", "ENDLESS-ROUTE"]
const RADIUS := 7
const REGIONS := ["hospital", "lab", "greenhouse"]
const MIN_CHUNKS := 6
## The props a room must show to read as that room.
const KEY_PROPS := {
	"ward": ["hospitalBed", "hospitalCurtain"], "nurses_station": ["nursesStation"],
	"waiting_room": ["waitingChairs"], "operating_theatre": ["operatingTable", "surgicalLight"],
	"icu": ["hospitalBed", "vitalsMonitor"], "morgue": ["morgueCabinet", "autopsyTable"],
	"pharmacy": ["pharmacyShelf"], "imaging": ["xrayMachine"], "supply_closet": ["medicalSupplyRack"],
	"clean_room": ["labGlassPartition", "labBench"], "containment": ["containmentCell", "specimenTank"],
	"server_hall": ["serverRack", "labCoolingUnit"], "control_room": ["controlConsole", "monitorWall"],
	"decon": ["deconShower"], "chem_lab": ["fumeHood", "labBench"], "bio_lab": ["specimenTank", "labBench"],
	"cold_storage": ["coldStorageUnit"], "lab_office": ["officeDesk", "labWhiteboard"],
	"glasshouse": ["raisedPlanter", "mistingPost"], "palm_house": ["pottedPalm"],
	"cactus_room": ["saguaroCactus", "cactusCluster"], "potting_shed": ["pottingBench"],
	"irrigation_room": ["irrigationManifold"], "overgrown_room": ["overgrowthPatch"],
	"dome_atrium": ["domeFountain", "pottedPalm"],
}

var _failures := 0


func run(_host: Node) -> int:
	var chunks_by_region := {}
	var rooms_by_type := {}
	var missing_key := {}
	var unfurnished := []
	var overlaps := []
	var blocked_doors := []
	var pockets := []
	var pocket_types := {}
	var room_count := 0
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord) or generator.is_safe_room(coord):
					continue
				var region := generator.biome_for(coord)
				if not REGIONS.has(region):
					continue
				chunks_by_region[region] = int(chunks_by_region.get(region, 0)) + 1
				var data := generator.chunk(coord)
				var grid: Array = data["grid"]
				var props_by_room := {}
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					var room_id := String(prop.get("room_id", ""))
					if room_id.is_empty():
						continue
					if not props_by_room.has(room_id):
						props_by_room[room_id] = []
					(props_by_room[room_id] as Array).append(prop)
				for room_value in data.get("rooms", []):
					var room: Dictionary = room_value
					var room_type := String(room.get("room_type", ""))
					if not KEY_PROPS.has(room_type):
						continue
					room_count += 1
					var where := "%s %s %s" % [seed_text, coord, room_type]
					rooms_by_type[room_type] = int(rooms_by_type.get(room_type, 0)) + 1
					var props: Array = props_by_room.get(String(room.get("id", "")), [])
					if props.is_empty():
						unfurnished.append(where)
						continue
					var types := {}
					for prop in props:
						types[String(prop["type"])] = true
					for key_type in KEY_PROPS[room_type]:
						if not types.has(key_type):
							missing_key["%s:%s" % [room_type, key_type]] = where
					var overlap := _overlap(props)
					if not overlap.is_empty():
						overlaps.append("%s %s" % [where, overlap])
					var blocked := _solid_cells(props)
					var doorway_value = room.get("doorway")
					if doorway_value is Vector2i:
						var doorway: Vector2i = doorway_value
						var basis := StreamedRouteGenerator._room_template_basis(room)
						var inside: Vector2i = doorway - (basis["open"] as Vector2i)
						if blocked.has(doorway) or blocked.has(inside):
							blocked_doors.append(where)
						var stranded := _stranded(data, room, doorway, blocked)
						if stranded > 0:
							pockets.append("%s: %d cells" % [where, stranded])
							pocket_types[room_type] = int(pocket_types.get(room_type, 0)) + 1
	for region in REGIONS:
		_expect(int(chunks_by_region.get(region, 0)) >= MIN_CHUNKS,
			"%s generated only %d chunks over %d seeds" % [region, int(chunks_by_region.get(region, 0)), SEEDS.size()])
	for room_type in KEY_PROPS:
		_expect(rooms_by_type.has(room_type), "no %s room was ever generated" % room_type)
	_expect(unfurnished.is_empty(), "%d biome rooms have no furnished recipe (e.g. %s)" % [unfurnished.size(),
		unfurnished.slice(0, 4)])
	_expect(missing_key.is_empty(), "rooms missing their defining props: %s" % [missing_key])
	_expect(overlaps.is_empty(), "%d rooms have interpenetrating solid props (e.g. %s)" % [overlaps.size(),
		overlaps.slice(0, 4)])
	_expect(blocked_doors.is_empty(), "%d rooms have a prop in the doorway (e.g. %s)" % [blocked_doors.size(),
		blocked_doors.slice(0, 4)])
	_expect(pockets.is_empty(), "%d rooms have floor walled off by props (by type %s; e.g. %s)" % [pockets.size(),
		pocket_types, pockets.slice(0, 4)])
	if _failures == 0:
		print("  biomes  %s chunks, %d rooms of %d types: furnished, key props, no overlaps, doors clear, all floor reachable"
			% [chunks_by_region, room_count, rooms_by_type.size()])
	return _failures


static func _solid_cells(props: Array) -> Dictionary:
	var cells := {}
	for prop in props:
		if not bool(prop.get("solid", true)) or bool(prop.get("wall_mounted", false)):
			continue
		for cell in prop.get("occupied_cells", []):
			cells[cell] = true
	return cells


static func _overlap(props: Array) -> String:
	for i in props.size():
		var a: Dictionary = props[i]
		if not bool(a.get("solid", true)) or bool(a.get("wall_mounted", false)):
			continue
		for j in range(i + 1, props.size()):
			var b: Dictionary = props[j]
			if not bool(b.get("solid", true)) or bool(b.get("wall_mounted", false)):
				continue
			if not StreamedRouteGenerator._collider_clear(a, [b]):
				return "%s x %s" % [a["type"], b["type"]]
	return ""


## Free interior cells of the room that a player-sized body (CollisionWorld, the hunters' and players' real collision)
## walking in from the door cannot get near: floor walled off behind props, where a pickup or a hider would be stranded.
static func _stranded(data: Dictionary, room: Dictionary, door: Vector2i, blocked: Dictionary) -> int:
	var rect: Rect2i = room.get("rect", Rect2i())
	var grid: Array = data["grid"]
	var world := CollisionWorld.from_chunk(data)
	var area := Rect2(Vector2(rect.position) - Vector2(2, 2), Vector2(rect.size) + Vector2(4, 4))
	var basis := StreamedRouteGenerator._room_template_basis(room)
	var outward := Vector2(basis["open"] as Vector2i)
	var reached := world.flood(Vector2(door) + Vector2(.5, .5) + outward, CollisionWorld.MARGIN_RADIUS, area)
	var stranded := 0
	for z in range(rect.position.y + 1, rect.end.y - 1):
		for x in range(rect.position.x + 1, rect.end.x - 1):
			var cell := Vector2i(x, z)
			if int(grid[z][x]) != 0 or blocked.has(cell):
				continue
			if not world.reached_near(reached, area, Vector2(cell) + Vector2(.5, .5), 0.55):
				stranded += 1
	return stranded


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1
