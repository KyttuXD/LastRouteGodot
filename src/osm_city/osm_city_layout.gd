class_name OsmCityLayout
extends CityLayout

## A CityLayout filled from a downloaded real-place map (OsmCityMap, docs/CITY_OSM_MAPS.md) instead of the generated plan.
## It keeps CityLayout's fixed 315 x 225 cell frame (7 x 5 chunks at 1 m), so every constant the route code, renderer and
## validators use still holds: a 315 x 225 m window of the map is cut around a spot with open ground, the spawn kiosk
## stands on chunk (0,0)'s centre (ROUNDABOUT_CENTER), the dome gate on GATE_CELL in the south rim, RIM all round.
## OSM building masses become CityLayout buildings: a WALL ring, FLOOR inside, the converter's DOOR cells as doorways.

const BORDER := 2
const MAX_HEIGHT := 60.0
const SHOP_KINDS := {
	"cafe": "cafe", "restaurant": "cafe", "fast_food": "cafe", "bar": "cafe", "pub": "cafe", "ice_cream": "cafe",
	"bank": "office", "pharmacy": "shop", "books": "library", "church": "chapel",
}
const SPAWN_CLEAR := 8   # half-size of the plaza cleared around the spawn kiosk

var map_name := ""
var map_id := ""
var map_version := 0
var attribution := ""
var window_origin := Vector2i.ZERO   # map cell at layout cell (0, 0)
var _shop_kind := {}                 # building number + 1 -> interior kind from OSM shop tags


static func from_map(map: OsmCityMap, p_seed: String) -> OsmCityLayout:
	var layout := OsmCityLayout.new()
	layout.seed_text = p_seed if not p_seed.is_empty() else "CITY"
	layout._rng = SeededRandom.new("%s:OSM-LAYOUT" % layout.seed_text)
	layout.map_name = String(map.manifest.get("name", ""))
	layout.map_id = String(map.manifest.get("id", ""))
	layout.map_version = int(map.manifest.get("version", 0))
	layout.attribution = String(map.manifest.get("attribution", "Map data (c) OpenStreetMap contributors, ODbL"))
	layout._fill(map)
	return layout


func interior_kind_for(building: Dictionary) -> String:
	return String(_shop_kind.get(building["id"], building["kind"]))


func is_outside(gx: int, gz: int) -> bool:
	# the frame, plus every cell outside a boundary-shaped map's real outline (the converter marks those RIM)
	return not in_bounds(gx, gz) or gx < BORDER or gz < BORDER or gx >= WIDTH - BORDER or gz >= GATE_ROW \
		or kinds[index_of(gx, gz)] == RIM


func zone_name(gx: int, gz: int) -> String:
	var name := super(gx, gz)
	return name if name != "" else map_name.to_upper()


func _fill(map: OsmCityMap) -> void:
	kinds.resize(WIDTH * HEIGHT)
	kinds.fill(RIM)
	building_index.resize(WIDTH * HEIGHT)
	building_index.fill(0)
	var map_kinds := _map_grid(map)
	var size: Vector2i = map_kinds["size"]
	window_origin = _choose_window(map_kinds, size)
	var heights := PackedByteArray()
	heights.resize(WIDTH * HEIGHT)
	for gz in HEIGHT:
		for gx in WIDTH:
			var mx := window_origin.x + gx
			var mz := window_origin.y + gz
			if mx < 0 or mz < 0 or mx >= size.x or mz >= size.y:
				continue
			var index := index_of(gx, gz)
			kinds[index] = (map_kinds["kinds"] as PackedByteArray)[mz * size.x + mx]
			heights[index] = (map_kinds["heights"] as PackedByteArray)[mz * size.x + mx]
	_frame()
	_clear_spawn()
	_open_gate()
	_link_gate()
	_extract_buildings(heights, map)
	_seal_unreachable()


## The whole map as one grid: {"size": Vector2i, "kinds", "heights"}.
func _map_grid(map: OsmCityMap) -> Dictionary:
	var counts: Array = map.manifest.get("chunks_xz", [0, 0])
	var chunk := int(map.manifest.get("chunk", CHUNK))
	var size := Vector2i(int(counts[0]) * chunk, int(counts[1]) * chunk)
	var all_kinds := PackedByteArray()
	all_kinds.resize(size.x * size.y)
	all_kinds.fill(RIM)
	var all_heights := PackedByteArray()
	all_heights.resize(size.x * size.y)
	for cz in int(counts[1]):
		for cx in int(counts[0]):
			var data := map.chunk(cx, cz)
			if data.is_empty():
				continue
			for z in chunk:
				var row := (cz * chunk + z) * size.x + cx * chunk
				for x in chunk:
					all_kinds[row + x] = (data["kinds"] as PackedByteArray)[z * chunk + x]
					all_heights[row + x] = (data["heights"] as PackedByteArray)[z * chunk + x]
	return {"size": size, "kinds": all_kinds, "heights": all_heights}


## The densest window (most building cells, sampled every 5 m) whose spawn spot (ROUNDABOUT_CENTER) has at least half
## its surroundings open, nearest the map centre on ties. A map smaller than the frame is centred in it.
func _choose_window(map_kinds: Dictionary, size: Vector2i) -> Vector2i:
	var all_kinds: PackedByteArray = map_kinds["kinds"]
	var span := Vector2i(maxi(0, size.x - WIDTH), maxi(0, size.y - HEIGHT))
	var centre := Vector2(span) / 2.0
	var best := Vector2i(span / 2)
	var best_score := -INF
	for oz in range(0, span.y + 1, 15):
		for ox in range(0, span.x + 1, 15):
			var at := Vector2i(ox, oz) + ROUNDABOUT_CENTER
			var open := 0
			var samples := 0
			for dz in range(-SPAWN_CLEAR, SPAWN_CLEAR + 1, 2):
				for dx in range(-SPAWN_CLEAR, SPAWN_CLEAR + 1, 2):
					samples += 1
					var k := _map_kind(all_kinds, size, at.x + dx, at.y + dz)
					if k != WALL and k != DOOR and k != WATER and k != RIM:
						open += 1
			if open * 2 < samples:
				continue
			var walls := 0
			for z in range(oz + BORDER, oz + GATE_ROW, 5):
				for x in range(ox + BORDER, ox + WIDTH - BORDER, 5):
					var k := _map_kind(all_kinds, size, x, z)
					if k == WALL or k == DOOR:
						walls += 1
			var score := float(walls) - Vector2(ox, oz).distance_to(centre) * 0.05
			if score > best_score:
				best_score = score
				best = Vector2i(ox, oz)
	if size.x < WIDTH:
		best.x = -(WIDTH - size.x) / 2
	if size.y < HEIGHT:
		best.y = -(HEIGHT - size.y) / 2
	return best


static func _map_kind(all_kinds: PackedByteArray, size: Vector2i, x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= size.x or z >= size.y:
		return RIM
	return all_kinds[z * size.x + x]


func _frame() -> void:
	for gz in HEIGHT:
		for gx in WIDTH:
			if is_outside(gx, gz):
				_set_kind(gx, gz, RIM)


## A plaza around the spawn kiosk on chunk (0,0)'s centre (the route code wants the safe room there).
func _clear_spawn() -> void:
	spawn = ROUNDABOUT_CENTER
	for dz in range(-SPAWN_CLEAR, SPAWN_CLEAR + 1):
		for dx in range(-SPAWN_CLEAR, SPAWN_CLEAR + 1):
			_set_kind(spawn.x + dx, spawn.y + dz, PLAZA)
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			var edge := absi(dx) == 4 or absi(dz) == 4
			_set_kind(spawn.x + dx, spawn.y + dz, KIOSK_WALL if edge else KIOSK_FLOOR)
	_register_shelter(spawn, 0, Vector2i(0, 1))
	for door in shelters[-1]["doors"]:
		_set_kind((door as Vector2i).x, (door as Vector2i).y, DOOR)


func _open_gate() -> void:
	for gx in range(GATE_X.x, GATE_X.y + 1):
		_set_kind(gx, GATE_ROW, GATE)
		for gz in range(GATE_CELL.y - 2, GATE_CELL.y + 1):
			_set_kind(gx, gz, PAVE)


## If the gate's apron is not reachable from the spawn, a 3-wide pavement runs north from it until it meets ground that is.
func _link_gate() -> void:
	var reached := _reachable()
	if reached[index_of(GATE_CELL.x, GATE_CELL.y)] == 1:
		return
	for gz in range(GATE_CELL.y, BORDER, -1):
		var joined := false
		for dx in range(-1, 2):
			if reached[index_of(GATE_CELL.x + dx, gz)] == 1:
				joined = true
			if kind_at(GATE_CELL.x + dx, gz) != PAVE:
				_set_kind(GATE_CELL.x + dx, gz, PAVE)
		if joined:
			return


func _reachable() -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(WIDTH * HEIGHT)
	var queue: Array[Vector2i] = [spawn]
	reached[index_of(spawn.x, spawn.y)] = 1
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + (step as Vector2i)
			if in_bounds(next.x, next.y) and reached[index_of(next.x, next.y)] == 0 and is_open(next.x, next.y):
				reached[index_of(next.x, next.y)] = 1
				queue.append(next)
	return reached


## Each 4-connected mass of WALL/DOOR cells becomes one building: cells with a non-mass 8-neighbour stay WALL, the rest
## FLOOR. A doorway is kept only where it has floor behind it; a mass with no doorway left stays sealed and solid.
func _extract_buildings(heights: PackedByteArray, map: OsmCityMap) -> void:
	var shops := {}
	for shop in map.features().get("shops", []):
		var cell: Array = shop["cell"]
		shops[Vector2i(int(cell[0]), int(cell[1])) - window_origin] = String(shop["kind"])
	var seen := PackedByteArray()
	seen.resize(WIDTH * HEIGHT)
	for gz in HEIGHT:
		for gx in WIDTH:
			var kind := kind_at(gx, gz)
			# the spawn kiosk's doorways are already registered and are not part of any OSM mass
			if (kind != WALL and kind != DOOR) or seen[index_of(gx, gz)] == 1 or _door_cells.has(Vector2i(gx, gz)):
				continue
			var cells: Array[Vector2i] = [Vector2i(gx, gz)]
			seen[index_of(gx, gz)] = 1
			var cursor := 0
			while cursor < cells.size():
				var cell: Vector2i = cells[cursor]
				cursor += 1
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = cell + (step as Vector2i)
					var next_kind := kind_at(next.x, next.y)
					if (next_kind == WALL or next_kind == DOOR) and seen[index_of(next.x, next.y)] == 0 \
							and not _door_cells.has(next):
						seen[index_of(next.x, next.y)] = 1
						cells.append(next)
			_add_building(cells, heights, shops)


func _add_building(cells: Array[Vector2i], heights: PackedByteArray, shops: Dictionary) -> void:
	var number := buildings.size() + 1
	var member := {}
	var low := cells[0]
	var high := cells[0]
	var height := 4.0
	for cell in cells:
		member[cell] = true
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
		height = maxf(height, float(heights[index_of(cell.x, cell.y)]))
	var doors := []
	for cell in cells:
		building_index[index_of(cell.x, cell.y)] = number
		var inner := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if not member.has(cell + Vector2i(dx, dz)):
					inner = false
		if inner:
			_set_kind(cell.x, cell.y, FLOOR)
	for cell in cells:
		if kind_at(cell.x, cell.y) != DOOR:
			continue
		var has_floor := false
		var has_street := false
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + (step as Vector2i)
			has_floor = has_floor or kind_at(next.x, next.y) == FLOOR
			has_street = has_street or (not member.has(next) and is_open(next.x, next.y))
		if has_floor and has_street and doors.size() < 2:
			doors.append(cell)
			_door_cells[cell] = true
		else:
			_set_kind(cell.x, cell.y, WALL)
	var id := "OSM%d" % (number - 1)
	var rect := Rect2i(low, high - low + Vector2i.ONE)
	var kind := "office" if height >= 30.0 else "apartment"
	for cell in shops:
		if member.has(cell):
			kind = "shop"
			_shop_kind[id] = String(SHOP_KINDS.get(shops[cell], "shop"))
			break
	var building := {"id": id, "rect": rect, "interior": Rect2i(rect.position + Vector2i.ONE, rect.size - Vector2i(2, 2)),
		"kind": kind, "height": snappedf(clampf(height, 4.0, MAX_HEIGHT), .5),
		"style": "civic" if height >= 45.0 else "brick", "doors": doors, "partition": [], "sealed": doors.is_empty()}
	if doors.is_empty():
		for cell in cells:
			_set_kind(cell.x, cell.y, WALL)
	buildings.append(building)
