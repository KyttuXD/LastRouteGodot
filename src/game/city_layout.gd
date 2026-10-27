class_name CityLayout
extends RefCounted

## The master plan of KYTTU: The City: one deterministic 225 x 135 cell grid (1 cell = 1 m) of tile kinds for the whole
## bounded domed oval, plus its buildings, shelters, gardens, plazas and street furniture. Pure data (no nodes), a pure
## function of the seed, so the host and every guest build the same city. CityRouteGenerator slices it into the 45 x 45
## chunks the route code streams; docs/CITY_PROJECT.md has the zone map.
##
## Coordinates: city cell (gx, gz) with gx 0..224, gz 0..134. A route cell is X = gx - 90, Z = gz - 45, so chunk (0, 0)
## covers gx 90..134, gz 45..89 and its centre cell (the spawn, the roundabout) is gx 112, gz 67.

const WIDTH := 315
const HEIGHT := 225
const CHUNK := 45
const CHUNK_MIN := Vector2i(-3, -2)
const CHUNK_MAX := Vector2i(3, 2)
const ORIGIN_OFFSET := Vector2i(135, 90)
## Downtown (the original 225 x 135 plan) sits at this offset inside the grown grid; the outskirts ring it.
const DOWNTOWN_SHIFT := Vector2i(45, 45)

## The dome ellipse (cell centres): outside it is solid rim, the outer ring road is the band just inside.
const ELLIPSE_CENTER := Vector2(157.5, 112.5)
const ELLIPSE_AXES := Vector2(111.0, 65.0)
const RING_ROAD_FROM := 0.93
const RING_PAVE_FROM := 0.89
const BUILD_LIMIT := 0.88
const DECOR_LIMIT := 0.86
## The outskirts: everything between the downtown ellipse (r 1) and the outer rim (outer_r 1) is suburbs, then farmland.
const OUTER_AXES := Vector2(155.0, 110.0)
const SUBURB_TO := 1.28      # downtown-ellipse radius where the suburbs give way to farmland
const OUTER_WALL_FROM := 0.965   # outer_r from which the perimeter wall and its tree line stand

# Tile kinds.
const RIM := 0
const ROAD := 1
const PAVE := 2
const PLAZA := 3
const GRASS := 4
const PATH := 5
const WATER := 6
const WALL := 7
const FLOOR := 8
const DOOR := 9
const HEDGE := 10
const BED := 11
const POST := 12
const CROSS_NS := 13
const CROSS_EW := 14
const KIOSK_FLOOR := 15
const KIOSK_WALL := 16
const BRIDGE := 17
const BLOCK := 18
const ALLEY := 19
const COMPASS := 20
const GATE := 21
const FIELD := 22
const DIRT := 23
const GRAVEL := 24
const KIND_COUNT := 25

const KIND_NAMES := ["rim", "road", "pave", "plaza", "grass", "path", "water", "wall", "floor", "door", "hedge", "bed",
	"post", "cross_ns", "cross_ew", "kiosk_floor", "kiosk_wall", "bridge", "block", "alley", "compass", "gate", "field", "dirt", "gravel"]
const OPEN_KINDS := [ROAD, PAVE, PLAZA, GRASS, PATH, FLOOR, DOOR, CROSS_NS, CROSS_EW, KIOSK_FLOOR, BRIDGE, ALLEY, COMPASS, FIELD, DIRT, GRAVEL]
## Kinds a person can stand on outdoors (a door opens onto one of these).
const OUTDOOR_KINDS := [ROAD, PAVE, PLAZA, GRASS, PATH, ALLEY, COMPASS, CROSS_NS, CROSS_EW, BRIDGE, FIELD, DIRT, GRAVEL]

## [centre cell, width]: the central avenue and the main street are 9 wide, the others 5. Centres sit on chunk centres.
const NS_STREETS := [[67, 5], [112, 5], [157, 9], [202, 5], [247, 5]]
const EW_STREETS := [[67, 5], [112, 9], [157, 5]]
const ROUNDABOUT_CENTER := Vector2i(157, 112)
## The two arterials (the avenue and the main street) run on past downtown to the outer rim.
const AVENUE_X := 157
const MAIN_STREET_Z := 112
## The dome gate across the south end of the avenue: nine blocked cells on row GATE_ROW, the interaction cell in front.
## The gate now stands at the south end of the avenue on the OUTER rim (the escape leaves the whole city).
const GATE_ROW := 219
const GATE_CELL := Vector2i(157, 218)
const GATE_X := Vector2i(153, 161)
const SHELTER_PLAZAS := [Vector2i(112, 67), Vector2i(202, 67), Vector2i(112, 157), Vector2i(202, 157)]
const GARDENS := [Rect2i(115, 70, 38, 38), Rect2i(162, 70, 38, 38)]
## North end of the avenue; it runs over the first secondary street (rows 20..24), so the plaza is 85 x 22.
const GRAND_PLAZA := Rect2i(115, 48, 85, 22)

## Collider footprint and height (x, height, z; metres, centred in the cell, bench rotated by its yaw) of every piece of
## street furniture. They match what is drawn: a lamp post blocks its pole, not the metre around it (the test in
## validate_city compares them with the visible footprints). The statue is the whole 3 x 3 plinth.
const DECOR_COLLIDERS := {
	"lamp": Vector3(.3, 3.5, .3), "tree": Vector3(.4, 5.0, .4), "cypress": Vector3(1.1, 4.8, 1.1),
	"bench": Vector3(.9, .9, .4), "planter": Vector3(.84, .9, .84), "bollard": Vector3(.26, .8, .26),
	"statue": Vector3(3.0, 3.8, 3.0),
	"plaza_light": Vector3(.25, 4.4, .25), "banner": Vector3(.2, 4.0, .2), "market_stall": Vector3(.9, 1.0, .9),
	"newsstand": Vector3(.9, 1.1, .9), "phone_booth": Vector3(.78, 2.1, .78), "hydrant": Vector3(.26, .55, .26),
}
## The widest visible footprint of the same pieces (what the renderer draws), for the collider-vs-visual check.
const DECOR_VISIBLE := {
	"lamp": Vector3(.84, 3.5, .84), "tree": Vector3(2.2, 5.0, 2.2), "cypress": Vector3(1.1, 4.8, 1.1),
	"bench": Vector3(.9, .9, .4), "planter": Vector3(.84, .9, .84), "bollard": Vector3(.24, .8, .24),
	"statue": Vector3(3.0, 3.8, 3.0),
	"plaza_light": Vector3(.9, 4.6, .9), "banner": Vector3(1.1, 4.2, 1.1), "market_stall": Vector3(1.9, 2.5, 1.9),
	"newsstand": Vector3(1.0, 2.5, 1.0), "phone_booth": Vector3(.84, 2.26, .84), "hydrant": Vector3(.4, .62, .4),
}
## "hall" is last on purpose: it is only given to big civic lots, never drawn at random.
const BUILDING_KINDS := ["shop", "cafe", "office", "apartment", "lobby", "workshop", "library", "chapel", "hall"]

## Footprints (metres) of the interior props this plan places; all of them are shared prop types.
const PROP_SIZES := {
	"woodenTable": Vector3(.9, .8, .9), "woodenChair": Vector3(.65, 1.0, .65),
	"diningTable": Vector3(.95, .8, .95), "diningChair": Vector3(.65, 1.0, .65),
	"normalBookcase": Vector3(.95, 2.0, .45), "officeDesk": Vector3(.95, .9, .72),
	"officeChair": Vector3(.68, 1.42, .68), "supplyCrates": Vector3(.95, 1.0, .8),
	"vendingMachine": Vector3(.85, 1.9, .6), "floorLamp": Vector3(.55, 1.75, .55),
	"filingCabinet": Vector3(.6, 1.3, .5), "officeWaterCooler": Vector3(.58, 1.82, .52),
	"singleBed": Vector3(.95, .78, .95), "bedroomNightstand": Vector3(.6, .82, .55),
	"bedroomWardrobe": Vector3(.95, 2.15, .65), "serverRack": Vector3(.8, 2.0, .55),
	"officeFileBoxes": Vector3(.95, .92, .68), "normalKitchenCounter": Vector3(.95, 1.05, .7),
	"normalKitchenFridge": Vector3(.85, 2.05, .75), "trashBin": Vector3(.5, .8, .5),
}
## Interior prop recipes per building kind: [type, role]. Roles: "wall" (back against a wall), "row" (grid of groups),
## "seat" (chair beside a row piece), "scatter" (anywhere free).
const INTERIOR_RECIPES := {
	"cafe": [["woodenTable", "row"], ["woodenChair", "seat"], ["normalKitchenCounter", "wall"], ["normalKitchenFridge", "wall"], ["floorLamp", "scatter"]],
	"shop": [["normalBookcase", "wall"], ["supplyCrates", "scatter"], ["officeDesk", "row"], ["vendingMachine", "wall"], ["floorLamp", "scatter"]],
	"office": [["officeDesk", "row"], ["officeChair", "seat"], ["filingCabinet", "wall"], ["officeWaterCooler", "wall"], ["floorLamp", "scatter"]],
	"apartment": [["singleBed", "wall"], ["bedroomNightstand", "wall"], ["bedroomWardrobe", "wall"], ["woodenTable", "scatter"], ["woodenChair", "seat"], ["floorLamp", "scatter"]],
	"lobby": [["woodenChair", "row"], ["floorLamp", "wall"], ["vendingMachine", "wall"], ["normalBookcase", "wall"]],
	"workshop": [["supplyCrates", "row"], ["serverRack", "wall"], ["officeFileBoxes", "scatter"], ["filingCabinet", "wall"], ["trashBin", "scatter"]],
	"hall": [["diningTable", "row"], ["diningChair", "seat"], ["floorLamp", "wall"], ["normalBookcase", "wall"]],
	"library": [["normalBookcase", "row"], ["normalBookcase", "wall"], ["woodenTable", "scatter"], ["woodenChair", "seat"], ["floorLamp", "wall"]],
	"chapel": [["woodenChair", "row"], ["floorLamp", "wall"], ["floorLamp", "wall"], ["normalBookcase", "wall"]],
}
## Interiors at least this wide get a partition wall with a two-wide doorway, so the building has two rooms.
const PARTITION_MIN := 11

## Kinds that draw as a tall solid mass: street furniture keeps its footprint clear of them.
const SOLID_MASS_KINDS := [WALL, KIOSK_WALL, GATE, RIM]

var seed_text := ""
var kinds := PackedByteArray()
var building_index := PackedInt32Array()   # city cell -> building number + 1 (0 = none)
var _decor_floor := {}   # decor cell -> the tile kind it replaced (restored when the furniture is pruned)
var decor := {}          # Vector2i -> {"type": String, "yaw": float}
var buildings: Array = []
var shelters: Array = []
var gardens: Array = []
var plazas: Array = []
var spawn := Vector2i(157, 112)
var _rng: SeededRandom
var _door_cells := {}


static func build(p_seed: String) -> CityLayout:
	var layout := CityLayout.new()
	layout.seed_text = p_seed if not p_seed.is_empty() else "CITY"
	layout._plan()
	return layout


# ---------------------------------------------------------------- queries

static func index_of(gx: int, gz: int) -> int:
	return gz * WIDTH + gx


static func in_bounds(gx: int, gz: int) -> bool:
	return gx >= 0 and gz >= 0 and gx < WIDTH and gz < HEIGHT


func kind_at(gx: int, gz: int) -> int:
	return int(kinds[index_of(gx, gz)]) if in_bounds(gx, gz) else RIM


## The building a wall or floor cell belongs to ({} for none).
func building_at(gx: int, gz: int) -> Dictionary:
	if not in_bounds(gx, gz):
		return {}
	var number := building_index[index_of(gx, gz)]
	return buildings[number - 1] if number > 0 else {}


## The name the HUD shows for the place a cell belongs to.
func zone_name(gx: int, gz: int) -> String:
	if gz >= GATE_ROW - 3 and gz <= GATE_ROW + 3 and gx >= GATE_X.x and gx <= GATE_X.y:
		return "DOME GATE"
	var building := building_at(gx, gz)
	if not building.is_empty():
		var kind := String(building["kind"])
		return "CIVIC HALL" if String(building["style"]) == "civic" else kind.to_upper()
	for shelter in shelters:
		if (shelter["rect"] as Rect2i).has_point(Vector2i(gx, gz)):
			return "SHELTER"
	var cell := Vector2i(gx, gz)
	if Vector2(cell).distance_to(Vector2(ROUNDABOUT_CENTER)) <= 15.5:
		return "FOUNTAIN ROUNDABOUT"
	for rect in gardens:
		if rect.has_point(cell):
			return "GARDEN"
	if GRAND_PLAZA.has_point(cell):
		return "GRAND PLAZA"
	for rect in plazas:
		if rect.has_point(cell):
			return "SHELTER PLAZA"
	var here := kind_at(gx, gz)
	if here == ALLEY:
		return "ALLEY"
	var r := ellipse_r(gx, gz)
	if r >= 1.0:
		if here == FIELD or here == DIRT:
			return "FARMLAND"
		if r >= SUBURB_TO:
			return "FARM ROAD" if here == ROAD or here == GRAVEL else "FARMLAND"
		if gx >= AVENUE_X - 4 and gx <= AVENUE_X + 4:
			return "AVENUE // SUBURBS"
		if gz >= MAIN_STREET_Z - 4 and gz <= MAIN_STREET_Z + 4:
			return "MAIN STREET // SUBURBS"
		return "SUBURBS"
	if r >= RING_PAVE_FROM:
		return "RING ROAD"
	if here == GRASS:
		return "PARKLAND"
	if gx >= AVENUE_X - 4 and gx <= AVENUE_X + 4:
		return "CENTRAL AVENUE"
	if gz >= MAIN_STREET_Z - 4 and gz <= MAIN_STREET_Z + 4:
		return "MAIN STREET"
	return "STREET"


func is_open(gx: int, gz: int) -> bool:
	return OPEN_KINDS.has(kind_at(gx, gz))


static func ellipse_r(gx: int, gz: int) -> float:
	var dx := (float(gx) + .5 - ELLIPSE_CENTER.x) / ELLIPSE_AXES.x
	var dz := (float(gz) + .5 - ELLIPSE_CENTER.y) / ELLIPSE_AXES.y
	return sqrt(dx * dx + dz * dz)


## Radius in the OUTER ellipse (1.0 = the city's rim wall); the same centre as the downtown ellipse.
static func outer_r(gx: int, gz: int) -> float:
	var dx := (float(gx) + .5 - ELLIPSE_CENTER.x) / OUTER_AXES.x
	var dz := (float(gz) + .5 - ELLIPSE_CENTER.y) / OUTER_AXES.y
	return sqrt(dx * dx + dz * dz)


static func chunk_origin(coord: Vector3i) -> Vector2i:
	return Vector2i(coord.x, coord.z) * CHUNK + ORIGIN_OFFSET


static func chunk_in_range(coord: Vector3i) -> bool:
	return coord.y == 0 and coord.x >= CHUNK_MIN.x and coord.x <= CHUNK_MAX.x \
		and coord.z >= CHUNK_MIN.y and coord.z <= CHUNK_MAX.y


## 45 x 45 grid of the chunk, 0 = open floor, 1 = blocked, as the route code expects.
func chunk_grid(coord: Vector3i) -> Array:
	var origin := chunk_origin(coord)
	var grid := []
	for z in CHUNK:
		var row := []
		row.resize(CHUNK)
		for x in CHUNK:
			row[x] = 0 if is_open(origin.x + x, origin.y + z) else 1
		grid.append(row)
	return grid


func chunk_has_open_cells(coord: Vector3i) -> bool:
	var origin := chunk_origin(coord)
	for z in CHUNK:
		for x in CHUNK:
			if is_open(origin.x + x, origin.y + z):
				return true
	return false


func chunk_kinds(coord: Vector3i) -> PackedByteArray:
	var origin := chunk_origin(coord)
	var out := PackedByteArray()
	out.resize(CHUNK * CHUNK)
	for z in CHUNK:
		for x in CHUNK:
			out[z * CHUNK + x] = kind_at(origin.x + x, origin.y + z)
	return out


## Street furniture of the chunk as {type, cell (chunk local), yaw}.
func chunk_decor(coord: Vector3i) -> Array:
	var origin := chunk_origin(coord)
	var out := []
	for cell_value in decor.keys():
		var cell: Vector2i = cell_value
		var local := cell - origin
		if local.x < 0 or local.y < 0 or local.x >= CHUNK or local.y >= CHUNK:
			continue
		var entry: Dictionary = decor[cell]
		out.append({"type": String(entry["type"]), "cell": local, "yaw": float(entry["yaw"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector2i = a["cell"]
		var cb: Vector2i = b["cell"]
		return ca.y < cb.y if ca.y != cb.y else ca.x < cb.x)
	return out


func buildings_in_chunk(coord: Vector3i) -> Array:
	var origin := chunk_origin(coord)
	var rect := Rect2i(origin, Vector2i(CHUNK, CHUNK))
	var out := []
	for building in buildings:
		if rect.intersects(building["rect"] as Rect2i):
			out.append(building)
	return out


func shelter_for_chunk(coord: Vector3i) -> Dictionary:
	for shelter in shelters:
		if (shelter["chunk"] as Vector3i) == coord:
			return shelter
	return {}


## Interior furniture entries of one building (city cells), deterministic from the seed and the building id.
func building_props(building: Dictionary) -> Array:
	if bool(building.get("sealed", false)):
		return []
	var kind := String(building["kind"])
	var recipe: Array = INTERIOR_RECIPES.get(kind, [])
	if recipe.is_empty():
		return []
	var rng := SeededRandom.new("%s:CITY-PROPS:%s" % [seed_text, building["id"]])
	var interior: Rect2i = building["interior"]
	var taken := {}
	# Doorways and the lane behind them stay clear (two cells deep, three wide).
	for door_value in building["doors"]:
		var door: Vector2i = door_value
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				taken[door + Vector2i(dx, dz)] = true
	for wall_value in building.get("partition", []):
		var wall_cell: Vector2i = wall_value
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				taken[wall_cell + Vector2i(dx, dz)] = true
	var props := []
	var index := 0
	var row_cells := []
	for entry_value in recipe:
		var type := String((entry_value as Array)[0])
		var role := String((entry_value as Array)[1])
		match role:
			"row":
				var step := 4 if kind != "lobby" else 3
				var x0 := interior.position.x + 2
				var z0 := interior.position.y + 2
				for z in range(z0, interior.end.y - 2, step):
					for x in range(x0, interior.end.x - 2, step):
						var cell := Vector2i(x, z)
						if taken.has(cell) or rng.next_float() < .18:
							continue
						taken[cell] = true
						row_cells.append(cell)
						props.append(_prop(building, index, type, cell, 0.0))
						index += 1
			"seat":
				for cell_value in row_cells.duplicate():
					var base: Vector2i = cell_value
					for side in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
						var seat_cell: Vector2i = base + (side as Vector2i)
						if taken.has(seat_cell) or not interior.has_point(seat_cell) or rng.next_float() < .35:
							continue
						taken[seat_cell] = true
						var yaw := atan2(float(-side.x), float(-side.y))
						props.append(_prop(building, index, type, seat_cell, yaw))
						index += 1
			"wall":
				var count := 0
				var candidates := _wall_hugging_cells(interior)
				while count < 3 and not candidates.is_empty():
					var pick: Dictionary = candidates.pop_at(rng.next_index(candidates.size()))
					var wall_cell: Vector2i = pick["cell"]
					if taken.has(wall_cell):
						continue
					taken[wall_cell] = true
					props.append(_prop(building, index, type, wall_cell, float(pick["yaw"])))
					index += 1
					count += 1
			_:
				# Loose pieces stand axis-aligned with a free cell all round, so a turned table cannot reach into a row
				# piece or a bookcase beside it (the geometry audit's prop_in_prop rule).
				var tries := 0
				var placed := 0
				while placed < 2 and tries < 12:
					tries += 1
					var cell := Vector2i(interior.position.x + 1 + rng.next_index(maxi(1, interior.size.x - 2)),
						interior.position.y + 1 + rng.next_index(maxi(1, interior.size.y - 2)))
					var crowded := false
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							if taken.has(cell + Vector2i(dx, dz)):
								crowded = true
					if crowded:
						continue
					taken[cell] = true
					props.append(_prop(building, index, type, cell, float(rng.next_index(4)) * PI * .5))
					index += 1
					placed += 1
	# Cells sealed after the plan (unreachable pockets became wall) cannot hold furniture: it would stand inside the mass.
	props = props.filter(func(prop: Dictionary) -> bool: return kind_at((prop["cell"] as Vector2i).x, (prop["cell"] as Vector2i).y) == FLOOR)
	return _keep_floor_connected(building, props)


## Drops furniture until every free floor cell of the interior can be reached from the first doorway.
func _keep_floor_connected(building: Dictionary, props: Array) -> Array:
	var interior: Rect2i = building["interior"]
	var doors: Array = building["doors"]
	var start: Vector2i = doors[0]
	for _attempt in 16:
		var blocked := {}
		for wall_value in building.get("partition", []):
			blocked[wall_value] = true
		for prop in props:
			blocked[prop["cell"]] = true
		var seen := {}
		var queue: Array[Vector2i] = []
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var inside: Vector2i = start + (step as Vector2i)
			if interior.has_point(inside) and not blocked.has(inside):
				seen[inside] = true
				queue.append(inside)
		var cursor := 0
		while cursor < queue.size():
			var cell: Vector2i = queue[cursor]
			cursor += 1
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = cell + (step as Vector2i)
				if interior.has_point(next) and not blocked.has(next) and not seen.has(next):
					seen[next] = true
					queue.append(next)
		var offenders := {}
		for gz in range(interior.position.y, interior.end.y):
			for gx in range(interior.position.x, interior.end.x):
				var cell := Vector2i(gx, gz)
				if blocked.has(cell) or seen.has(cell):
					continue
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if blocked.has(cell + (step as Vector2i)):
						offenders[cell + (step as Vector2i)] = true
		if offenders.is_empty():
			return props
		props = props.filter(func(prop: Dictionary) -> bool: return not offenders.has(prop["cell"]))
	return props


func _prop(building: Dictionary, index: int, type: String, cell: Vector2i, yaw: float) -> Dictionary:
	return {"id": "%s:%d" % [building["id"], index], "type": type, "cell": cell, "yaw": yaw,
		"size": PROP_SIZES.get(type, Vector3(.9, 1.0, .9)), "room_id": String(building["id"])}


## Cells along the inside of the facade with the direction that faces into the room.
func _wall_hugging_cells(interior: Rect2i) -> Array:
	var out := []
	for x in range(interior.position.x + 1, interior.end.x - 1):
		out.append({"cell": Vector2i(x, interior.position.y), "yaw": 0.0})
		out.append({"cell": Vector2i(x, interior.end.y - 1), "yaw": PI})
	for z in range(interior.position.y + 1, interior.end.y - 1):
		out.append({"cell": Vector2i(interior.position.x, z), "yaw": -PI * .5})
		out.append({"cell": Vector2i(interior.end.x - 1, z), "yaw": PI * .5})
	return out


# ---------------------------------------------------------------- planning

func _plan() -> void:
	_rng = SeededRandom.new("%s:CITY-LAYOUT" % seed_text)
	kinds.resize(WIDTH * HEIGHT)
	kinds.fill(RIM)
	building_index.resize(WIDTH * HEIGHT)
	building_index.fill(0)
	_lay_ground()
	_lay_outskirts()
	_lay_streets()
	_lay_arterials()
	_lay_roundabout()
	for center in SHELTER_PLAZAS:
		_lay_shelter_plaza(center)
	for rect in GARDENS:
		_lay_garden(rect)
	_lay_grand_plaza()
	_lay_blocks()
	_lay_gate()
	_fill_verges()
	_lay_crosswalks()
	_scatter_verge_trees()
	_lay_street_furniture()
	_remove_thin_alleys()
	_fill_slivers()
	_seal_unreachable()
	_absorb_orphan_walls()
	_prune_clipping_decor()


func _set_kind(gx: int, gz: int, kind: int) -> void:
	if in_bounds(gx, gz):
		kinds[index_of(gx, gz)] = kind


func _lay_ground() -> void:
	for gz in HEIGHT:
		for gx in WIDTH:
			var r := ellipse_r(gx, gz)
			if r >= 1.0:
				continue
			if r >= RING_ROAD_FROM:
				_set_kind(gx, gz, ROAD)
			elif r >= RING_PAVE_FROM:
				_set_kind(gx, gz, PAVE)
			else:
				_set_kind(gx, gz, BLOCK)


func _stamp_street_cell(gx: int, gz: int, kind: int) -> void:
	if not in_bounds(gx, gz) or ellipse_r(gx, gz) >= 1.0:
		return
	var current := kind_at(gx, gz)
	if kind == ROAD or current == BLOCK or current == PAVE:
		if kind == ROAD or current != ROAD:
			_set_kind(gx, gz, kind)


func _lay_streets() -> void:
	for street in NS_STREETS:
		var width: int = street[1]
		var x0: int = (street[0] as int) - width / 2
		var edge := 2 if width == 9 else 1
		for gx in range(x0, x0 + width):
			var off := gx - x0
			var kind := PAVE if off < edge or off >= width - edge else ROAD
			for gz in HEIGHT:
				_stamp_street_cell(gx, gz, kind)
	for street in EW_STREETS:
		var width: int = street[1]
		var z0: int = (street[0] as int) - width / 2
		var edge := 2 if width == 9 else 1
		for gz in range(z0, z0 + width):
			var off := gz - z0
			var kind := PAVE if off < edge or off >= width - edge else ROAD
			for gx in WIDTH:
				_stamp_street_cell(gx, gz, kind)


## Everything between the downtown ellipse and the outer rim: grass and fields, a suburb ring road, farm tracks, and the
## perimeter wall band (RIM) with its tree line just inside it. Lots for houses and farms are planned by _lay_outskirt_lots
## (a later pass); the ground here is already walkable so the city is one connected space.
func _lay_outskirts() -> void:
	for gz in HEIGHT:
		for gx in WIDTH:
			var inner := ellipse_r(gx, gz)
			if inner < 1.0:
				continue
			var outer := outer_r(gx, gz)
			if outer >= OUTER_WALL_FROM:
				continue   # stays RIM: the perimeter wall
			if inner < SUBURB_TO:
				_set_kind(gx, gz, GRASS)
			else:
				# Farmland: strips of crops with soil between, broken by the farm tracks laid below.
				var band := int(floor((float(gx) + float(gz) * 0.35) / 7.0))
				_set_kind(gx, gz, FIELD if band % 3 != 2 else GRASS)
	# Suburb ring road: a 7-wide asphalt loop (2 kerb cells each side) along the suburb/farm boundary.
	for gz in HEIGHT:
		for gx in WIDTH:
			var inner := ellipse_r(gx, gz)
			if inner >= SUBURB_TO - 0.045 and inner < SUBURB_TO + 0.015:
				_set_kind(gx, gz, ROAD)
			elif (inner >= SUBURB_TO - 0.06 and inner < SUBURB_TO - 0.045) or (inner >= SUBURB_TO + 0.015 and inner < SUBURB_TO + 0.03):
				_set_kind(gx, gz, PAVE)
	# Farm tracks: dirt lanes radiating from the ring road to the rim at eight bearings, 3 wide.
	for bearing in 8:
		var angle := TAU * float(bearing) / 8.0 + PI / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		var side := Vector2(-direction.y, direction.x)
		for step in 200:
			var at := ELLIPSE_CENTER + Vector2(direction.x * ELLIPSE_AXES.x, direction.y * ELLIPSE_AXES.y) * (SUBURB_TO + float(step) * .004)
			for offset in [-1.0, 0.0, 1.0]:
				var cell := Vector2i(roundi(at.x + side.x * offset - .5), roundi(at.y + side.y * offset - .5))
				if in_bounds(cell.x, cell.y) and [FIELD, GRASS].has(kind_at(cell.x, cell.y)):
					_set_kind(cell.x, cell.y, DIRT)


## The avenue and the main street continue through the suburbs and the farmland to the outer rim as 9-wide arterials
## (asphalt with a 2-cell kerb/pavement each side), so the gate at the far south is reached by road.
func _lay_arterials() -> void:
	for gz in HEIGHT:
		for gx in range(AVENUE_X - 4, AVENUE_X + 5):
			_stamp_outskirt_street(gx, gz, PAVE if absi(gx - AVENUE_X) >= 3 else ROAD)
	for gx in WIDTH:
		for gz in range(MAIN_STREET_Z - 4, MAIN_STREET_Z + 5):
			_stamp_outskirt_street(gx, gz, PAVE if absi(gz - MAIN_STREET_Z) >= 3 else ROAD)


func _stamp_outskirt_street(gx: int, gz: int, kind: int) -> void:
	if not in_bounds(gx, gz) or ellipse_r(gx, gz) < 1.0 or outer_r(gx, gz) >= OUTER_WALL_FROM:
		return
	var current := kind_at(gx, gz)
	if current == RIM:
		return
	if kind == ROAD or current != ROAD:
		_set_kind(gx, gz, kind)


## Fountain roundabout: a 9 x 9 kiosk (the spawn shelter) on an island ringed by water with four 3-wide bridges, a
## compass-rose island, then a 4-wide road ring and a 2-wide pavement.
func _lay_roundabout() -> void:
	var c := ROUNDABOUT_CENTER
	for dz in range(-15, 16):
		for dx in range(-15, 16):
			var distance := sqrt(float(dx * dx + dz * dz))
			if distance > 15.0:
				continue
			var gx := c.x + dx
			var gz := c.y + dz
			var ax := absi(dx)
			var az := absi(dz)
			var kind := PAVE
			if ax <= 4 and az <= 4:
				kind = KIOSK_WALL if ax == 4 or az == 4 else KIOSK_FLOOR
				if dz == 4 and ax <= 1:
					kind = DOOR
			elif distance <= 5.3:
				kind = COMPASS
			elif distance <= 8.2:
				kind = BRIDGE if ax <= 1 or az <= 1 else WATER
			elif distance < 9.0:
				kind = COMPASS
			elif distance < 13.0:
				kind = ROAD
			_set_kind(gx, gz, kind)
	_register_shelter(c, 1, Vector2i(0, 1))


func _lay_shelter_plaza(c: Vector2i) -> void:
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			var gx := c.x + dx
			var gz := c.y + dz
			if ellipse_r(gx, gz) >= 0.95:
				continue
			var ax := absi(dx)
			var az := absi(dz)
			var kind := PLAZA
			if ax <= 4 and az <= 4:
				kind = KIOSK_WALL if ax == 4 or az == 4 else KIOSK_FLOOR
			_set_kind(gx, gz, kind)
	# The door faces the main street (south for the north pair, north for the south pair).
	var facing := 1 if c.y < ROUNDABOUT_CENTER.y else -1
	for dx in range(-1, 2):
		_set_kind(c.x + dx, c.y + 4 * facing, DOOR)
	_register_shelter(c, 0, Vector2i(0, facing))
	plazas.append(Rect2i(c.x - 10, c.y - 10, 21, 21))


func _register_shelter(center: Vector2i, _kind_index: int, facing: Vector2i) -> void:
	var chunk := Vector3i(floori(float(center.x - ORIGIN_OFFSET.x) / CHUNK), 0,
		floori(float(center.y - ORIGIN_OFFSET.y) / CHUNK))
	var doors := []
	for dx in range(-1, 2):
		doors.append(center + Vector2i(dx, 4 * facing.y))
	shelters.append({"id": "SHELTER:%d:%d" % [center.x, center.y], "center": center, "chunk": chunk,
		"rect": Rect2i(center.x - 4, center.y - 4, 9, 9), "doors": doors, "facing": facing})
	for door in doors:
		_door_cells[door] = true


func _lay_garden(rect: Rect2i) -> void:
	gardens.append(rect)
	var mid := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)
	for gz in range(rect.position.y, rect.end.y):
		for gx in range(rect.position.x, rect.end.x):
			if kind_at(gx, gz) != BLOCK:
				continue
			var kind := GRASS
			var on_edge := gx == rect.position.x or gx == rect.end.x - 1 \
				or gz == rect.position.y or gz == rect.end.y - 1
			var dx := gx - mid.x
			var dz := gz - mid.y
			if on_edge:
				kind = HEDGE
				if absi(dx) <= 1 or absi(dz) <= 1:
					kind = PATH
			elif absi(dx) <= 1 or absi(dz) <= 1:
				kind = PATH
			if absi(dx) <= 3 and absi(dz) <= 3 and not on_edge:
				kind = PLAZA
				if absi(dx) <= 1 and absi(dz) <= 1:
					kind = WATER
			_set_kind(gx, gz, kind)
	# Four flower beds (blocked), each with a two-cell grass walkway around it.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var near_x: int = mid.x + int(sx) * 4
			var far_x: int = mid.x + int(sx) * (rect.size.x / 2 - 3)
			var near_z: int = mid.y + int(sz) * 4
			var far_z: int = mid.y + int(sz) * (rect.size.y / 2 - 3)
			var x0: int = mini(near_x, far_x) + 1
			var x1: int = maxi(near_x, far_x) - 1
			var z0: int = mini(near_z, far_z) + 1
			var z1: int = maxi(near_z, far_z) - 1
			for gz in range(z0, z1 + 1):
				for gx in range(x0, x1 + 1):
					if kind_at(gx, gz) == GRASS:
						_set_kind(gx, gz, BED)
	for corner in [Vector2i(-4, -4), Vector2i(4, -4), Vector2i(-4, 4), Vector2i(4, 4)]:
		_place_decor(mid + (corner as Vector2i), "tree", 0.0)
	for bench in [Vector2i(-2, -7), Vector2i(2, 7), Vector2i(-7, 2), Vector2i(7, -2)]:
		_place_decor(mid + (bench as Vector2i), "bench", 0.0)


func _lay_grand_plaza() -> void:
	var rect := GRAND_PLAZA
	plazas.append(rect)
	for gz in range(rect.position.y, rect.end.y):
		for gx in range(rect.position.x, rect.end.x):
			if ellipse_r(gx, gz) >= RING_PAVE_FROM:
				continue
			var current := kind_at(gx, gz)
			if current == BLOCK or current == ROAD or current == PAVE:
				_set_kind(gx, gz, PLAZA)
	var mid_x := ROUNDABOUT_CENTER.x
	# Statue on a 3 x 3 plinth, a long reflecting pool south of it, benches facing the pool.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			_set_kind(mid_x + dx, 14 + dz, POST)
	decor[Vector2i(mid_x, 14)] = {"type": "statue", "yaw": 0.0}
	for gz in range(18, 22):
		for gx in range(mid_x - 7, mid_x + 8):
			_set_kind(gx, gz, WATER)
	for bench_x in [mid_x - 12, mid_x - 4, mid_x + 4, mid_x + 12]:
		_place_decor(Vector2i(bench_x, 16), "bench", 0.0)
	for tree_x in [mid_x - 30, mid_x - 22, mid_x + 22, mid_x + 30]:
		_place_decor(Vector2i(tree_x, 16), "cypress", 0.0)
		_place_decor(Vector2i(tree_x, 23), "tree", 0.0)
	for bench_x in [mid_x - 10, mid_x + 10]:
		_place_decor(Vector2i(bench_x, 23), "bench", PI)
	# The plaza is the lit heart of the city: cyan lights in two rows, banners, and a row of market stalls (the rows sit
	# inside DECOR_LIMIT, which the dome edge makes tight at the plaza's far north).
	for light_x in range(mid_x - 40, mid_x + 41, 8):
		_place_decor(Vector2i(light_x, 12), "plaza_light", 0.0)
		_place_decor(Vector2i(light_x + 4, 21), "plaza_light", 0.0)
	for banner_x in [mid_x - 34, mid_x - 26, mid_x - 14, mid_x + 14, mid_x + 26, mid_x + 34]:
		_place_decor(Vector2i(banner_x, 17), "banner", 0.0)
	for stall_x in [mid_x - 24, mid_x - 20, mid_x - 16, mid_x + 16, mid_x + 20, mid_x + 24]:
		_place_decor(Vector2i(stall_x, 14), "market_stall", 0.0)


# ---------------------------------------------------------------- blocks and buildings

func _street_spans(streets: Array, limit: int) -> Array:
	var spans := []
	for street in streets:
		var width: int = street[1]
		var from: int = (street[0] as int) - width / 2
		spans.append([from, from + width])
	var bands := []
	var cursor := 0
	for span in spans:
		if span[0] > cursor:
			bands.append([cursor, span[0]])
		cursor = span[1]
	if cursor < limit:
		bands.append([cursor, limit])
	return bands


func _lay_blocks() -> void:
	var x_bands := _street_spans(NS_STREETS, WIDTH)
	var z_bands := _street_spans(EW_STREETS, HEIGHT)
	for zb in z_bands:
		for xb in x_bands:
			var rect := Rect2i(xb[0], zb[0], xb[1] - xb[0], zb[1] - zb[0])
			_plan_block(rect)


func _plan_block(rect: Rect2i) -> void:
	var rows := [rect]
	if rect.size.y >= 30:
		rows = _split_with_alley(rect, true)
	var pieces := []
	for row_value in rows:
		var row: Rect2i = row_value
		if row.size.x >= 40:
			pieces.append_array(_split_with_alley(row, false))
		else:
			pieces.append(row)
	for piece_value in pieces:
		for lot in _split_lots(piece_value as Rect2i):
			_try_building(lot)


func _split_with_alley(rect: Rect2i, horizontal: bool) -> Array:
	var out := []
	if horizontal:
		var first := (rect.size.y - 3) / 2
		out.append(Rect2i(rect.position.x, rect.position.y, rect.size.x, first))
		out.append(Rect2i(rect.position.x, rect.position.y + first + 3, rect.size.x, rect.size.y - first - 3))
		for gx in range(rect.position.x, rect.end.x):
			for gz in range(rect.position.y + first, rect.position.y + first + 3):
				if kind_at(gx, gz) == BLOCK:
					_set_kind(gx, gz, ALLEY)
	else:
		var first := (rect.size.x - 3) / 2
		out.append(Rect2i(rect.position.x, rect.position.y, first, rect.size.y))
		out.append(Rect2i(rect.position.x + first + 3, rect.position.y, rect.size.x - first - 3, rect.size.y))
		for gz in range(rect.position.y, rect.end.y):
			for gx in range(rect.position.x + first, rect.position.x + first + 3):
				if kind_at(gx, gz) == BLOCK:
					_set_kind(gx, gz, ALLEY)
	return out


func _split_lots(rect: Rect2i) -> Array:
	var longest := maxi(rect.size.x, rect.size.y)
	if longest <= 17:
		return [rect]
	var ratio := .4 + _rng.next_float() * .2
	var out := []
	if rect.size.x >= rect.size.y:
		var cut := clampi(roundi(rect.size.x * ratio), 9, rect.size.x - 9)
		out.append_array(_split_lots(Rect2i(rect.position.x, rect.position.y, cut, rect.size.y)))
		out.append_array(_split_lots(Rect2i(rect.position.x + cut, rect.position.y, rect.size.x - cut, rect.size.y)))
	else:
		var cut := clampi(roundi(rect.size.y * ratio), 9, rect.size.y - 9)
		out.append_array(_split_lots(Rect2i(rect.position.x, rect.position.y, rect.size.x, cut)))
		out.append_array(_split_lots(Rect2i(rect.position.x, rect.position.y + cut, rect.size.x, rect.size.y - cut)))
	return out


func _try_building(lot: Rect2i) -> void:
	if lot.size.x < 9 or lot.size.y < 9:
		return
	if not _lot_buildable(lot) or _choose_doors(lot).is_empty():
		# Overlaps the roundabout or the dome edge, or has no frontage: try the two halves of a big lot.
		var longest := maxi(lot.size.x, lot.size.y)
		if longest < 18:
			return
		if lot.size.x >= lot.size.y:
			var cut := lot.size.x / 2
			_try_building(Rect2i(lot.position.x, lot.position.y, cut, lot.size.y))
			_try_building(Rect2i(lot.position.x + cut, lot.position.y, lot.size.x - cut, lot.size.y))
		else:
			var cut := lot.size.y / 2
			_try_building(Rect2i(lot.position.x, lot.position.y, lot.size.x, cut))
			_try_building(Rect2i(lot.position.x, lot.position.y + cut, lot.size.x, lot.size.y - cut))
		return
	var doors := _choose_doors(lot)
	var id := "B%d" % buildings.size()
	for gz in range(lot.position.y, lot.end.y):
		for gx in range(lot.position.x, lot.end.x):
			var edge := gx == lot.position.x or gx == lot.end.x - 1 or gz == lot.position.y or gz == lot.end.y - 1
			_set_kind(gx, gz, WALL if edge else FLOOR)
	for door in doors:
		_set_kind((door as Vector2i).x, (door as Vector2i).y, DOOR)
		_door_cells[door] = true
	var area := lot.size.x * lot.size.y
	var center_z := lot.position.y + lot.size.y / 2 - DOWNTOWN_SHIFT.y
	var west_or_east := lot.position.x < 65 + DOWNTOWN_SHIFT.x or lot.position.x >= 160 + DOWNTOWN_SHIFT.x
	var kind: String = BUILDING_KINDS[_rng.next_index(BUILDING_KINDS.size() - 1)]
	var height := 12.0 + _rng.next_float() * 16.0
	var style := "brick"
	if kind == "chapel":
		style = "civic"
		height = 16.0 + _rng.next_float() * 6.0
	if area >= 260 and (center_z < 25 or center_z > 110):
		kind = "hall"
		height = 18.0 + _rng.next_float() * 6.0
		style = "civic"
	elif west_or_east and _rng.next_float() < .5:
		kind = "workshop"
		height = 14.0 + _rng.next_float() * 6.0
		style = "industrial"
	for gz in range(lot.position.y, lot.end.y):
		for gx in range(lot.position.x, lot.end.x):
			building_index[index_of(gx, gz)] = buildings.size() + 1
	var building := {"id": id, "rect": lot, "interior": Rect2i(lot.position + Vector2i.ONE, lot.size - Vector2i(2, 2)),
		"kind": kind, "height": snappedf(height, .5), "style": style, "doors": doors, "partition": []}
	building["partition"] = _lay_partition(building)
	buildings.append(building)


## A wall across the middle of a big interior with a two-wide doorway in it; empty when a door is too close to the line.
## Returns the wall cells (the doorway cells stay floor).
func _lay_partition(building: Dictionary) -> Array:
	var interior: Rect2i = building["interior"]
	if maxi(interior.size.x, interior.size.y) < PARTITION_MIN or mini(interior.size.x, interior.size.y) < 5:
		return []
	var vertical := interior.size.x >= interior.size.y
	var length := interior.size.y if vertical else interior.size.x
	var across := interior.size.x if vertical else interior.size.y
	var line := (interior.position.x if vertical else interior.position.y) + across / 2 + _rng.next_index(3) - 1
	for door_value in building["doors"]:
		var door: Vector2i = door_value
		if absi((door.x if vertical else door.y) - line) <= 3:
			return []
	var gap := (interior.position.y if vertical else interior.position.x) + 1 + _rng.next_index(maxi(1, length - 3))
	var cells := []
	for step in length:
		var along := (interior.position.y if vertical else interior.position.x) + step
		if along == gap or along == gap + 1:
			continue
		var cell := Vector2i(line, along) if vertical else Vector2i(along, line)
		cells.append(cell)
		_set_kind(cell.x, cell.y, WALL)
	return cells


func _lot_buildable(lot: Rect2i) -> bool:
	for corner in [lot.position, Vector2i(lot.end.x - 1, lot.position.y), Vector2i(lot.position.x, lot.end.y - 1),
			Vector2i(lot.end.x - 1, lot.end.y - 1)]:
		if ellipse_r((corner as Vector2i).x, (corner as Vector2i).y) > BUILD_LIMIT:
			return false
	for gz in range(lot.position.y, lot.end.y):
		for gx in range(lot.position.x, lot.end.x):
			if kind_at(gx, gz) != BLOCK:
				return false
	return true


## One or two 2-wide doorways, on the sides that face open ground. Empty when no side has a usable frontage.
func _choose_doors(lot: Rect2i) -> Array:
	var sides := []
	# [outward step, wall cells along the side]
	var north := []
	var south := []
	var west := []
	var east := []
	for gx in range(lot.position.x + 2, lot.end.x - 3):
		north.append(Vector2i(gx, lot.position.y))
		south.append(Vector2i(gx, lot.end.y - 1))
	for gz in range(lot.position.y + 2, lot.end.y - 3):
		west.append(Vector2i(lot.position.x, gz))
		east.append(Vector2i(lot.end.x - 1, gz))
	for entry in [[north, Vector2i(0, -1), Vector2i(1, 0)], [south, Vector2i(0, 1), Vector2i(1, 0)],
			[west, Vector2i(-1, 0), Vector2i(0, 1)], [east, Vector2i(1, 0), Vector2i(0, 1)]]:
		var cells: Array = entry[0]
		var out: Vector2i = entry[1]
		var along: Vector2i = entry[2]
		var usable := []
		for cell_value in cells:
			var cell: Vector2i = cell_value
			var next := cell + along
			if OUTDOOR_KINDS.has(kind_at((cell + out).x, (cell + out).y)) \
					and OUTDOOR_KINDS.has(kind_at((next + out).x, (next + out).y)):
				usable.append(cell)
		if usable.size() >= 4:
			sides.append({"usable": usable, "along": along, "count": usable.size()})
	if sides.is_empty():
		return []
	sides.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) > int(b["count"]))
	var doors := []
	var wanted := 2 if (lot.size.x + lot.size.y) >= 32 and sides.size() > 1 else 1
	for side_index in mini(wanted, sides.size()):
		var side: Dictionary = sides[side_index]
		var usable: Array = side["usable"]
		var pick: Vector2i = usable[_rng.next_index(usable.size())]
		doors.append(pick)
		doors.append(pick + (side["along"] as Vector2i))
	return doors


func _fill_verges() -> void:
	for gz in HEIGHT:
		for gx in WIDTH:
			if kind_at(gx, gz) == BLOCK:
				_set_kind(gx, gz, GRASS)


## Leftover ground between the buildings and the dome edge is parkland: scattered blossom trees, never in a doorway.
func _scatter_verge_trees() -> void:
	var rng := SeededRandom.new("%s:CITY-VERGE" % seed_text)
	for gz in range(2, HEIGHT - 2):
		for gx in range(2, WIDTH - 2):
			if kind_at(gx, gz) != GRASS or rng.next_float() > (.035 if ellipse_r(gx, gz) < 1.0 else .012):
				continue
			var crowded := false
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					if kind_at(gx + dx, gz + dz) == POST:
						crowded = true
			if not crowded:
				_place_decor(Vector2i(gx, gz), "tree", 0.0)


func _lay_crosswalks() -> void:
	var c := ROUNDABOUT_CENTER
	# Across the avenue (stripes along the road) and the main street, just outside the roundabout.
	for gz in [c.y - 18, c.y - 17, c.y + 17, c.y + 18]:
		for gx in range(c.x - 2, c.x + 3):
			if kind_at(gx, gz) == ROAD:
				_set_kind(gx, gz, CROSS_NS)
	for gx in [c.x - 18, c.x - 17, c.x + 17, c.x + 18]:
		for gz in range(c.y - 2, c.y + 3):
			if kind_at(gx, gz) == ROAD:
				_set_kind(gx, gz, CROSS_EW)


# ---------------------------------------------------------------- street furniture

func _place_decor(cell: Vector2i, type: String, yaw: float) -> bool:
	if not in_bounds(cell.x, cell.y):
		return false
	var r := ellipse_r(cell.x, cell.y)
	if r > DECOR_LIMIT and (r < 1.0 or outer_r(cell.x, cell.y) > OUTER_WALL_FROM - .03):
		return false
	var current := kind_at(cell.x, cell.y)
	if not [PAVE, PLAZA, GRASS, PATH, COMPASS].has(current):
		return false
	if _decor_clips_solid(cell, type) or _decor_clips_decor(cell, type, yaw):
		return false
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if _door_cells.has(cell + Vector2i(dx, dz)):
				return false
	_decor_floor[cell] = current
	_set_kind(cell.x, cell.y, POST)
	decor[cell] = {"type": type, "yaw": yaw}
	return true


## Vertical parts of a piece of street furniture: [{half (footprint half extents, yaw applied), y0, y1}]. Mirrors what
## CityFacilityView3D._add_decor draws (a tree is a thin trunk under a wide canopy, a lamp a pole under a lantern head).
static func decor_parts(type: String, yaw: float) -> Array:
	var along_x := absf(sin(yaw)) < .5
	match type:
		"tree":
			return [_part(.28, .28, 0.0, 2.7), _part(2.2, 2.2, 2.5, 5.0)]
		"lamp":
			return [_part(.14, .14, 0.0, 3.1), _part(.84, .84, 2.98, 3.51)]
		"bench":
			return [_part(.9 if along_x else .4, .4 if along_x else .9, 0.0, .9)]
		"statue":
			return [_part(3.0, 3.0, 0.0, 1.2), _part(2.0, 2.0, 1.2, 1.55), _part(.9, .6, 1.55, 3.65)]
	var vis: Vector3 = DECOR_VISIBLE.get(type, Vector3.ONE)
	return [_part(vis.x, vis.z, 0.0, vis.y)]


static func _part(w: float, d: float, y0: float, y1: float) -> Dictionary:
	return {"half": Vector2(w, d) * .5, "y0": y0, "y1": y1}


## True when the visible footprint of a piece of street furniture (a tree canopy is 2.2 m wide) would reach into a solid
## mass (facade, kiosk, gate, rim) around its cell: a canopy through a facade is the clipping GeometryAudit flags.
func _decor_clips_solid(cell: Vector2i, type: String) -> bool:
	var widest := 0.0
	for part in decor_parts(type, 0.0):
		widest = maxf(widest, maxf((part["half"] as Vector2).x, (part["half"] as Vector2).y))
	var reach := ceili(widest - .5 - .1)
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if SOLID_MASS_KINDS.has(kind_at(cell.x + dx, cell.y + dz)):
				return true
	return false


## True when a new piece would interpenetrate furniture already standing nearby (a lamp head inside a canopy). Parts
## are compared with their height spans, so a bench under a tree is fine.
func _decor_clips_decor(cell: Vector2i, type: String, yaw: float) -> bool:
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var other_cell := cell + Vector2i(dx, dz)
			if not decor.has(other_cell):
				continue
			var other: Dictionary = decor[other_cell]
			var blend := .3 if type == String(other["type"]) and ["tree", "cypress"].has(type) else 0.0
			for a in decor_parts(type, yaw):
				for b in decor_parts(String(other["type"]), float(other["yaw"])):
					if float(a["y1"]) <= float(b["y0"]) or float(b["y1"]) <= float(a["y0"]):
						continue
					var ox := (a["half"] as Vector2).x + (b["half"] as Vector2).x - absf(float(dx))
					var oz := (a["half"] as Vector2).y + (b["half"] as Vector2).y - absf(float(dz))
					if minf(ox, oz) > .1 + blend:
						return true
	return false


## Furniture that ended up against a mass sealed or thinned after it was placed is taken away again (floor restored).
func _prune_clipping_decor() -> void:
	for cell_value in decor.keys():
		var cell: Vector2i = cell_value
		if _decor_clips_solid(cell, String(decor[cell]["type"])) and _decor_floor.has(cell):
			_set_kind(cell.x, cell.y, int(_decor_floor[cell]))
			decor.erase(cell)


## Solid cells left without a building (thinned alleys, sealed pockets) used to draw as 6 m stubs between 12-28 m towers.
## They join the building they touch (multi-source flood through the orphans), so a facade is one continuous mass; an
## orphan no building can reach becomes a low hedge.
func _absorb_orphan_walls() -> void:
	var queue: Array[Vector2i] = []
	for gz in HEIGHT:
		for gx in WIDTH:
			if building_index[index_of(gx, gz)] > 0:
				queue.append(Vector2i(gx, gz))
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		var owner := building_index[index_of(cell.x, cell.y)]
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + (step as Vector2i)
			if in_bounds(next.x, next.y) and kind_at(next.x, next.y) == WALL and building_index[index_of(next.x, next.y)] == 0:
				building_index[index_of(next.x, next.y)] = owner
				queue.append(next)
	for gz in HEIGHT:
		for gx in WIDTH:
			if kind_at(gx, gz) == WALL and building_index[index_of(gx, gz)] == 0:
				_set_kind(gx, gz, HEDGE)


func _lay_street_furniture() -> void:
	# Lamp posts along every street's pavement, staggered across the road; trees on the avenue between the lamps.
	for street in NS_STREETS:
		var width: int = street[1]
		var x0: int = (street[0] as int) - width / 2
		var inner := [x0 + (1 if width == 9 else 0), x0 + width - (2 if width == 9 else 1)]
		var spacing := 8 if width == 9 else 10
		for side in 2:
			for gz in range(4 + side * (spacing / 2), HEIGHT - 3, spacing):
				if not _place_decor(Vector2i(inner[side], gz), "lamp", 0.0 if side == 0 else PI):
					continue
			if width == 9:
				for gz in range(8 + side * 4, HEIGHT - 3, 8):
					_place_decor(Vector2i(inner[side], gz), "tree", 0.0)
	for street in EW_STREETS:
		var width: int = street[1]
		var z0: int = (street[0] as int) - width / 2
		var inner := [z0 + (1 if width == 9 else 0), z0 + width - (2 if width == 9 else 1)]
		var spacing := 8 if width == 9 else 10
		for side in 2:
			for gx in range(4 + side * (spacing / 2), WIDTH - 3, spacing):
				_place_decor(Vector2i(gx, inner[side]), "lamp", PI * .5 if side == 0 else -PI * .5)
			if width == 9:
				for gx in range(8 + side * 4, WIDTH - 3, 8):
					_place_decor(Vector2i(gx, inner[side]), "tree", 0.0)
	# Hydrants along the pavements, one every few blocks.
	for street in NS_STREETS:
		var hx: int = (street[0] as int) - (street[1] as int) / 2 + 1
		for gz in range(14, HEIGHT - 6, 22):
			_place_decor(Vector2i(hx, gz), "hydrant", 0.0)
	for street in EW_STREETS:
		var hz: int = (street[0] as int) - (street[1] as int) / 2 + 1
		for gx in range(20, WIDTH - 6, 26):
			_place_decor(Vector2i(gx, hz), "hydrant", 0.0)
	# Bollards beside every doorway and planters on the shelter plazas' corners.
	for shelter in shelters:
		var center: Vector2i = shelter["center"]
		for corner in [Vector2i(-7, -7), Vector2i(7, -7), Vector2i(-7, 7), Vector2i(7, 7)]:
			_place_decor(center + (corner as Vector2i), "planter", 0.0)
		for bench in [Vector2i(-6, 0), Vector2i(6, 0)]:
			_place_decor(center + (bench as Vector2i), "bench", PI * .5)
		_place_decor(center + Vector2i(0, -7), "phone_booth", 0.0)
		_place_decor(center + Vector2i(4, 7), "newsstand", PI)
		_place_decor(center + Vector2i(-4, 7), "phone_booth", PI)
	for building in buildings:
		var doors: Array = building["doors"]
		if doors.is_empty():
			continue
		var door: Vector2i = doors[0]
		var rect: Rect2i = building["rect"]
		var out := Vector2i.ZERO
		if door.y == rect.position.y:
			out = Vector2i(0, -1)
		elif door.y == rect.end.y - 1:
			out = Vector2i(0, 1)
		elif door.x == rect.position.x:
			out = Vector2i(-1, 0)
		else:
			out = Vector2i(1, 0)
		var along := Vector2i(out.y, out.x)
		_place_decor(door + out * 2 + along * 3, "bollard", 0.0)
		_place_decor(door + out * 2 - along * 3, "bollard", 0.0)


## The gate: a 9-wide closed barrier across the avenue (the escape objective, see CityRouteGenerator pickups).
func _lay_gate() -> void:
	for gx in range(GATE_X.x, GATE_X.y + 1):
		_set_kind(gx, GATE_ROW, GATE)
		# A clear 2-cell apron of road in front of the gate so the pickup cell is never swallowed by the wall band.
		for row in [GATE_ROW - 1, GATE_ROW - 2]:
			if kind_at(gx, row) == RIM:
				_set_kind(gx, row, ROAD)


## Relays the party must have recovered before the gate answers.
static func gate_relays_required(difficulty_id: String) -> int:
	match difficulty_id:
		"relaxed": return 6
		"hard": return 14
		"nightmare": return 16
		_: return 10


## An alley is 3 wide; leftover 1-2 cell slivers (clipped by the dome edge or the roundabout) become solid.
func _remove_thin_alleys() -> void:
	# Removing a thin strip can leave its neighbours thin, so repeat until the alleys that remain are all 3+ wide.
	while _remove_thin_alley_pass():
		pass


func _remove_thin_alley_pass() -> bool:
	var thin := []
	for gz in HEIGHT:
		for gx in WIDTH:
			if kind_at(gx, gz) != ALLEY:
				continue
			var across_x := 1
			var across_z := 1
			for sign in [-1, 1]:
				var x: int = gx + int(sign)
				while kind_at(x, gz) == ALLEY:
					across_x += 1
					x += int(sign)
				var z: int = gz + int(sign)
				while kind_at(gx, z) == ALLEY:
					across_z += 1
					z += int(sign)
			if mini(across_x, across_z) < 3:
				thin.append(Vector2i(gx, gz))
	for cell in thin:
		_wall_over((cell as Vector2i).x, (cell as Vector2i).y)
	return not thin.is_empty()


## Turns a cell into solid wall, taking any furniture standing on it away.
func _wall_over(gx: int, gz: int) -> void:
	decor.erase(Vector2i(gx, gz))
	_set_kind(gx, gz, WALL)


## A 1-2 cell open strip between two different building masses is a slot that shows nothing but a gap between facades
## (and a mesh-thin dead end for anyone who walks in): it is closed into wall unless a doorway opens onto it. The
## masses it joins absorb it in _absorb_orphan_walls.
func _fill_slivers() -> void:
	var fill := {}
	for gz in HEIGHT:
		for gx in WIDTH:
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var start := Vector2i(gx, gz)
				var a := building_index[index_of(gx, gz)]
				if a == 0 or kind_at(gx, gz) != WALL:
					continue
				for gap in [1, 2]:
					var far: Vector2i = start + (step as Vector2i) * (int(gap) + 1)
					if not in_bounds(far.x, far.y):
						break
					var b := building_index[index_of(far.x, far.y)]
					if b == 0 or b == a or kind_at(far.x, far.y) != WALL:
						continue
					var cells := []
					var closable := true
					for k in range(1, int(gap) + 1):
						var m: Vector2i = start + (step as Vector2i) * k
						if [WALL, DOOR, FLOOR].has(kind_at(m.x, m.y)):
							closable = false
						for around in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i.ZERO]:
							if kind_at(m.x + (around as Vector2i).x, m.y + (around as Vector2i).y) == DOOR:
								closable = false
						cells.append(m)
					if closable:
						for m in cells:
							fill[m] = true
					break
	for cell in fill:
		_wall_over((cell as Vector2i).x, (cell as Vector2i).y)


## Open cells that cannot be reached from the spawn become solid, so the city is one connected walkable space.
func _seal_unreachable() -> void:
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
			if not in_bounds(next.x, next.y) or reached[index_of(next.x, next.y)] == 1 \
					or not is_open(next.x, next.y):
				continue
			reached[index_of(next.x, next.y)] = 1
			queue.append(next)
	for gz in HEIGHT:
		for gx in WIDTH:
			if is_open(gx, gz) and reached[index_of(gx, gz)] == 0:
				_set_kind(gx, gz, WALL)
	# A building whose every doorway got sealed is now a solid mass: no rooms, props or lamp for it.
	for building in buildings:
		var enterable := false
		for door_value in building["doors"]:
			var door: Vector2i = door_value
			if kind_at(door.x, door.y) == DOOR:
				enterable = true
		building["sealed"] = not enterable


# ---------------------------------------------------------------- map image

const MAP_COLORS := {
	RIM: Color("0b0b10"), ROAD: Color("3a3d4d"), PAVE: Color("6c6a78"), PLAZA: Color("8d8798"), GRASS: Color("2f5a3a"),
	PATH: Color("a59b8a"), WATER: Color("2a5c8a"), WALL: Color("1a1822"), FLOOR: Color("5a4630"), DOOR: Color("f2c14e"),
	HEDGE: Color("1d4027"), BED: Color("b04a7a"), POST: Color("e8a33a"), CROSS_NS: Color("d8d8e0"),
	CROSS_EW: Color("d8d8e0"), KIOSK_FLOOR: Color("39b6b0"), KIOSK_WALL: Color("14636a"), BRIDGE: Color("a58a5a"),
	BLOCK: Color("ff00ff"), ALLEY: Color("55535f"), COMPASS: Color("c9b88a"), GATE: Color("39e6dc"),
	FIELD: Color("6b8a3a"), DIRT: Color("5e4a36"), GRAVEL: Color("7d7466"),
}


func to_image(scale: int = 4) -> Image:
	var image := Image.create(WIDTH * scale, HEIGHT * scale, false, Image.FORMAT_RGBA8)
	for gz in HEIGHT:
		for gx in WIDTH:
			var color: Color = MAP_COLORS.get(kind_at(gx, gz), Color.MAGENTA)
			image.fill_rect(Rect2i(gx * scale, gz * scale, scale, scale), color)
	return image
