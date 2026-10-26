class_name RefDecor
extends RefCounted

## Wall/ceiling dressing for the reference look, built per streamed chunk from
## the chunk's own grid, rooms and coordinates only -- no randomness outside a
## seeded hash -- so every co-op peer builds the same lamps, pipes and frames.
##
## Everything is a MultiMeshInstance3D (one per mesh kind per chunk), so a
## chunk with hundreds of fixtures costs a handful of draw calls. Real
## OmniLights are NOT created here: lamps are registered with LampField, which
## lends a small pool of lights to the lamps nearest the player.

const SCONCE_Y := 2.05
const SLICE_ROWS := 9

const STREAK_SHADER := preload("res://src/look/ref_streak.gdshader")

static var _mesh_cache := {}
static var _mat_cache := {}

# -- builder -----------------------------------------------------------------

var _data: Dictionary
var _coord: Vector3i
var _region: String
var _root: Node3D
var _room_map := {}
var _row := 0
var _size := 45
var _salt := 0
var _transforms := {}      # mesh key -> Array[Transform3D]
var _decal_pool := PackedVector3Array()
var _decal_streak := PackedVector3Array()
var _halo := PackedVector3Array()
## Lamps lent to LampField: Array of [Vector3 position, Color, float energy, int flicker]
var lamps: Array = []


var _heights := {}
var _corridor_h := 3.3
var _room_ids := {}
var _budget := {}          # room id -> {"lamp": n, "window": n}


func _init(root: Node3D, data: Dictionary, room_map: Dictionary,
		heights: Dictionary = {}, corridor_h: float = 3.3) -> void:
	_heights = heights
	_corridor_h = corridor_h
	_room_ids = RefLook.chunk_room_ids(data)
	_root = root
	_data = data
	_coord = data.get("coord", Vector3i.ZERO)
	_region = String(data.get("region", "maze"))
	_room_map = room_map
	_size = (data["grid"] as Array).size()
	_salt = hash(String(data.get("chunk_id", "")))


## Builds SLICE_ROWS grid rows; returns true once the whole chunk is done and
## the instance nodes have been attached.
func step() -> bool:
	if _row == 0:
		_room_lamps()
		_arches()
	var grid: Array = _data["grid"]
	var end_row := mini(_row + SLICE_ROWS, _size)
	while _row < end_row:
		for x in _size:
			_cell(grid, x, _row)
		_row += 1
	if _row < _size:
		return false
	_flush()
	return true


## Archways: the generator opens three-cell doorways ("arch" room-door props).
## Each gets a header wall above the opening, stepped corner blocks and
## pilasters with brass caps on both faces of both shoulders.
func _arches() -> void:
	for prop_value in _data.get("region_props", []):
		var prop: Dictionary = prop_value
		if not bool(prop.get("arch", false)):
			continue
		var cells: Array = prop.get("doorway_cells", [])
		if cells.size() != 3:
			continue
		var across: Vector2i = prop.get("across", Vector2i.RIGHT)
		var outward: Vector2i = prop.get("outward", Vector2i.UP)
		var centre := Vector3(0, 0, 0)
		for cell_value in cells:
			var cell: Vector2i = cell_value
			centre += Vector3(cell.x + .5, 0, cell.y + .5)
		centre /= 3.0
		var room_h := _hh((cells[1] as Vector2i) - outward)
		var hall_h := _hh((cells[1] as Vector2i) + outward)
		var top := maxf(room_h, hall_h)
		var along_x := absi(across.x) > 0
		_add("arch_header", _box_t(centre + Vector3(0, (3.0 + top) * .5, 0),
			Vector3(3.0 if along_x else 1.0, top - 3.0, 1.0 if along_x else 3.0)))
		for side in [-1.0, 1.0]:
			var off: Vector3 = Vector3(across.x, 0, across.y) * side
			_add("arch_header", _box_t(centre + off * 1.28 + Vector3(0, 2.8, 0),
				Vector3(.44 if along_x else 1.0, .44, 1.0 if along_x else .44)))
			for face in [-1.0, 1.0]:
				var depth: Vector3 = Vector3(outward.x, 0, outward.y) * face * .62
				var column: Vector3 = centre + off * 1.7 + depth
				var size := Vector3(.42 if along_x else .34, 1.0, .34 if along_x else .42)
				_add("arch_header", _box_t(column + Vector3(0, top * .5, 0), size * Vector3(1, top - .12, 1)))
				for cap in [.06, top - .08]:
					_add("arch_cap", _box_t(column + Vector3(0, cap, 0),
						Vector3(.56 if along_x else .46, .12, .46 if along_x else .56)))


static func _box_t(centre: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(size), centre)


## One hanging light at the middle of each big enough room: a chandelier in the
## carpeted regions, a caged strip lamp elsewhere.
func _room_lamps() -> void:
	var style := _style()
	for room_value in _data.get("rooms", []):
		var room: Dictionary = room_value
		var rect: Rect2i = room.get("rect", Rect2i())
		if mini(rect.size.x, rect.size.y) < 4:
			continue
		var cx := rect.position.x + rect.size.x / 2
		var cz := rect.position.y + rect.size.y / 2
		var height := _hh(Vector2i(cx, cz))
		if height > RefLook.TALL_ROOM:
			_tall_room(rect, height)
		if _h(cx, cz, 111, 100) >= int(float(style["lit_rooms"]) * 100.0):
			continue
		if not _take(String(room.get("id", "")), "lamp"):
			continue
		var world := Vector3(cx + .5, 0, cz + .5)
		var fancy := _region in ["mansion", "hotel", "apartment", "gothic", "carnival"] \
			and String(room.get("room_type", "")) not in ["hotel_bathroom", "house_bathroom", "stairwell"]
		if fancy or height > RefLook.TALL_ROOM:
			_pendant(world, height, cx, cz)
		else:
			_ceiling_lamp(world, cx, cz, height)
		_decal_pool.append(Vector3(world.x, 0, world.z))


## Iron roof ribs across a tall room, and pendant lights on a lattice.
func _tall_room(rect: Rect2i, height: float) -> void:
	for z in range(rect.position.y + 2, rect.end.y - 1, 6):
		var rib := Transform3D(Basis.IDENTITY.scaled(Vector3(float(rect.size.x), 1.0, 1.0)),
			Vector3(rect.position.x + rect.size.x * .5, height - .22, z + .5))
		_add("rib", rib)
	for z in range(rect.position.y + 3, rect.end.y - 2, 7):
		for x in range(rect.position.x + 3, rect.end.x - 2, 7):
			if x == rect.position.x + rect.size.x / 2 and z == rect.position.y + rect.size.y / 2:
				continue
			if _h(x, z, 113, 3) != 0:
				_pendant(Vector3(x + .5, 0, z + .5), height, x, z)


## A chandelier hung on a chain. Short chain in ordinary rooms; in tall rooms it
## hangs well below the roof so its light actually reaches the floor.
func _pendant(world: Vector3, height: float, x: int, z: int) -> void:
	var drop := .95 if height <= RefLook.TALL_ROOM else clampf((height - 3.2) * .6, 1.2, 2.6)
	var pos := world + Vector3(0, height - maxf(drop, .95), 0)
	_add("chandelier", Transform3D(Basis(Vector3.UP, _h(x, z, 112, 8) * PI / 4.0), pos))
	var chain := height - pos.y - .1
	if chain > 1.0:
		_add("chain", Transform3D(Basis.IDENTITY.scaled(Vector3(1, chain, 1)),
			Vector3(pos.x, pos.y + .2 + chain * .5, pos.z)))
	var tall := height > RefLook.TALL_ROOM
	lamps.append([_root.position + pos - Vector3(0, .35, 0), RefLook.AMBER_SOFT,
		2.4 if tall else 1.5, 1, 15.0 if tall else 9.0])
	_halo.append(pos)


## Ceiling height of a cell (see RefLook.ceiling_height).
func _hh(cell: Vector2i) -> float:
	return float(_heights.get(cell, _corridor_h))


## Fixtures per room are budgeted: 2-4 lamps and 1-3 windows each, picked by the
## room id so every peer agrees. Corridors have no budget (they use spacing).
func _take(room_id: String, what: String) -> bool:
	if room_id == "":
		return true
	var used: Dictionary = _budget.get(room_id, {})
	var cap := (2 + absi(hash(room_id)) % 3) if what == "lamp" else (1 + absi(hash(room_id + "w")) % 3)
	if int(used.get(what, 0)) >= cap:
		return false
	used[what] = int(used.get(what, 0)) + 1
	_budget[room_id] = used
	return true


func _room_id_at(cell: Vector2i) -> String:
	return String(_room_ids.get(cell, ""))


func _open(grid: Array, x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < _size and z < _size and int(grid[z][x]) == 0


func _h(x: int, z: int, salt: int, count: int) -> int:
	return RefLook.pick(_coord.x * _size + x, _coord.z * _size + z, salt + _salt, count)


func _add(key: String, t: Transform3D) -> void:
	if not _transforms.has(key):
		_transforms[key] = []
	(_transforms[key] as Array).append(t)


static func _facing_basis(normal: Vector3) -> Basis:
	# local +Z points out of the wall into the room
	return Basis(Vector3.UP, atan2(normal.x, normal.z))


func _style() -> Dictionary:
	return STYLE.get(_region, STYLE["maze"])


## Per-region fixture recipe: which lamp family, how dense, which wall extras.
const STYLE := {
	"maze": {"lamp": "ceiling", "wall_lamp": 11, "teal": 9, "pipe": 3, "cable": 20, "frame": 0, "lit_rooms": .8},
	"mansion": {"lamp": "sconce", "wall_lamp": 6, "teal": 22, "pipe": 8, "cable": 40, "frame": 7, "lit_rooms": .9},
	"hotel": {"lamp": "sconce", "wall_lamp": 5, "teal": 14, "pipe": 8, "cable": 40, "frame": 6, "lit_rooms": .9},
	"apartment": {"lamp": "sconce", "wall_lamp": 7, "teal": 20, "pipe": 6, "cable": 30, "frame": 8, "lit_rooms": .85},
	"beach": {"lamp": "lantern", "wall_lamp": 3, "teal": 28, "pipe": 99, "cable": 99, "frame": 0, "lit_rooms": .9},
	"gothic": {"lamp": "lantern", "wall_lamp": 6, "teal": 30, "pipe": 6, "cable": 30, "frame": 0, "lit_rooms": .8},
	"carnival": {"lamp": "ceiling", "wall_lamp": 6, "teal": 20, "pipe": 6, "cable": 20, "frame": 0, "lit_rooms": .9},
	"prison": {"lamp": "ceiling", "wall_lamp": 10, "teal": 9, "pipe": 2, "cable": 14, "frame": 0, "lit_rooms": .7},
	"inferno": {"lamp": "ceiling", "wall_lamp": 8, "teal": 99, "pipe": 3, "cable": 20, "frame": 0, "lit_rooms": .7},
}

const DIRS := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]


func _cell(grid: Array, x: int, z: int) -> void:
	var style := _style()
	if int(grid[z][x]) != 0:
		_wall_cell(grid, x, z, style)
	else:
		_open_cell(grid, x, z, style)


func _wall_cell(grid: Array, x: int, z: int, style: Dictionary) -> void:
	for dir_value in DIRS:
		var d: Vector2i = dir_value
		if not _open(grid, x + d.x, z + d.y):
			continue
		var n := Vector3(d.x, 0, d.y)
		var base := Vector3(x + .5 + d.x * .5, 0, z + .5 + d.y * .5)
		# position along the wall run, so spacing is regular instead of random
		var along: int = x if d.y != 0 else z
		var line: int = z if d.y != 0 else x
		var rt: String = _room_map.get(Vector2i(x + d.x, z + d.y), "")
		var lit_room := rt == "" or _h(x + d.x, z + d.y, 91, 100) < int(float(style["lit_rooms"]) * 100.0)
		var spacing: int = maxi(int(style["wall_lamp"]), 6)
		var rid := _room_id_at(Vector2i(x + d.x, z + d.y))
		var wants_lamp := false
		if lit_room and int(style["wall_lamp"]) < 90:
			if rid == "":
				# corridors: one lamp about every ten metres, sides alternating
				wants_lamp = (along + _h(0, line, 5, 12)) % 12 == 0 and (along / 12 + line) % 2 == 0
			else:
				wants_lamp = (along + line * 3 + _h(0, line, 5, spacing)) % spacing == 0 \
					and _take(rid, "lamp")
		if wants_lamp:
			_wall_lamp(base, n, String(style["lamp"]) if String(style["lamp"]) != "ceiling" else "sconce_short", x, z)
		elif int(style["teal"]) < 90 and _h(x, z, 21 + d.x * 3 + d.y, int(style["teal"]) * 3) == 0:
			_add("teal", Transform3D(_facing_basis(n), base + Vector3(0, 1.45, 0) + n * .02))
		elif int(style["frame"]) > 0 and rid != "" \
				and _h(x, z, 33 + d.x * 5 + d.y, int(style["frame"]) * 2) == 0:
			var frame_variant := _h(x, z, 35, 2)
			_add("frame%d" % frame_variant, Transform3D(_facing_basis(n),
				base + Vector3(0, 1.75, 0) + n * .03))
		var face_height := _hh(Vector2i(x + d.x, z + d.y))
		var tiers := RefLook.wall_tiers(face_height)
		var tier_height := face_height / tiers
		# windows only in a few room kinds, 1-3 per room, never in corridors
		if rid != "" and _wants_window(rt) and (along + line) % 4 == 1 \
				and _h(x, z, 131 + d.x * 5 + d.y, 2) == 0 and _take(rid, "window"):
			var tall: bool = _region == "beach"
			for tier in tiers:
				_add("window_tall" if tall else "window", Transform3D(_facing_basis(n),
					base + Vector3(0, (2.0 if tall else 1.95) + tier * tier_height, 0) + n * .02))
		# upper tiers of a tall room carry their own lamps (emissive only)
		if tiers > 1 and rid != "" and lit_room and int(style["wall_lamp"]) < 90 \
				and (along + line * 3) % (spacing * 3) == 0:
			for tier in range(1, tiers):
				var up := base + n * .02 + Vector3(0, SCONCE_Y + tier * tier_height, 0)
				var tier_basis := _facing_basis(n)
				if String(style["lamp"]) == "lantern":
					tier_basis = tier_basis.scaled(Vector3.ONE * 1.7)
				_add("lantern" if String(style["lamp"]) == "lantern" else "sconce",
					Transform3D(tier_basis, up))
				_halo.append(up + n * .1)
		# pilasters down both sides of halls, between the lamps
		if rid == "" and along % 6 == 3 and _open_run(grid, x, z, d):
			var hall_top := _hh(Vector2i(x + d.x, z + d.y)) - .1
			var across_x := d.y != 0
			var column := base + n * .16 + Vector3(0, hall_top * .5, 0)
			_add("arch_header", _box_t(column, Vector3(.42 if across_x else .32, hall_top, .32 if across_x else .42)))
			for cap in [.06, hall_top - .06]:
				_add("arch_cap", _box_t(base + n * .16 + Vector3(0, cap, 0),
					Vector3(.54 if across_x else .42, .12, .42 if across_x else .54)))
		# pipes run along the top of the wall in multi-cell stretches
		if int(style["pipe"]) < 90 and _h(along / 7, line, 61 + d.x + d.y * 2, int(style["pipe"]) * 2) == 0:
			var axis := Basis(Vector3.UP, 0.0) if d.y != 0 else Basis(Vector3.UP, PI * .5)
			var pipe_top := minf(_hh(Vector2i(x + d.x, z + d.y)), 3.6)
			var pipe_pos := base + Vector3(0, pipe_top - 0.30, 0) + n * .09
			_add("pipe", Transform3D(axis, pipe_pos))
			if _h(x, z, 62, 7) == 0:
				_add("pipe_brass", Transform3D(axis, base + Vector3(0, pipe_top - 0.55, 0) + n * .08))


const WINDOW_ROOMS := ["cove", "tide_pool", "beach_hut", "boardwalk_room", "drawing_room",
	"dining_room", "office_reception", "cubicle_room", "office_job", "private_office",
	"office_suite", "lounge"]


## True when the wall run on both sides of this wall cell is solid (so a pilaster
## here does not flank an opening).
func _open_run(grid: Array, x: int, z: int, d: Vector2i) -> bool:
	var along := Vector2i(1, 0) if d.y != 0 else Vector2i(0, 1)
	for k in [-2, -1, 1, 2]:
		var cx: int = x + along.x * k
		var cz: int = z + along.y * k
		if _open(grid, cx, cz) or not _open(grid, cx + d.x, cz + d.y):
			return false
	return true


func _wants_window(room_type: String) -> bool:
	return WINDOW_ROOMS.has(room_type)


func _open_cell(grid: Array, x: int, z: int, style: Dictionary) -> void:
	var rt: String = _room_map.get(Vector2i(x, z), "")
	var lit_room := _h(x, z, 77, 100) < int(float(style["lit_rooms"]) * 100.0)
	var world := Vector3(x + .5, 0, z + .5)
	if String(style["lamp"]) == "ceiling":
		var rid := _room_id_at(Vector2i(x, z))
		# lamps sit on a lattice inside rooms (budgeted) and every ten metres down halls
		if rid != "":
			if x % 5 == 2 and z % 5 == 2 and _lit_block(x, z, style) \
					and _hh(Vector2i(x, z)) <= RefLook.TALL_ROOM and _take(rid, "lamp"):
				_ceiling_lamp(world, x, z, _hh(Vector2i(x, z)))
		elif _is_corridor_mid(grid, x, z) and (x + z) % 12 == 0:
			_ceiling_lamp(world, x, z, _hh(Vector2i(x, z)))
	# (sconce regions light their corridors from the walls only)
	if int(style["cable"]) < 90 and _h(x, z, 71, int(style["cable"]) * 2) == 0 and lit_room \
			and _hh(Vector2i(x, z)) <= RefLook.TALL_ROOM:
		var yaw := PI * .5 if _h(x, z, 72, 2) == 0 else 0.0
		_add("swag", Transform3D(Basis(Vector3.UP, yaw), world + Vector3(0, _hh(Vector2i(x, z)) - 0.01, 0)))
	# cables snaking along the foot of the wall in the industrial regions
	if _region in ["maze", "prison", "inferno", "carnival"] and _h(x, z, 141, 60) == 0:
		for d in DIRS:
			var dd: Vector2i = d
			if not _open(grid, x + dd.x, z + dd.y):
				var yaw_c := atan2(float(dd.y), float(-dd.x)) if dd.x != 0 or dd.y != 0 else 0.0
				_add("floor_cable", Transform3D(Basis(Vector3.UP, PI * .5 if dd.x == 0 else 0.0),
					world + Vector3(dd.x * .25, .03, dd.y * .25)))
				break
	# planters of dusky flowers against the walls of garden rooms
	if _region == "beach" and rt in ["cove", "tide_pool", "beach_hut", "boardwalk_room"] \
			and _h(x, z, 151, 7) == 0:
		for d in DIRS:
			var dw: Vector2i = d
			if not _open(grid, x + dw.x, z + dw.y):
				_add("planter", Transform3D(Basis(Vector3.UP, _h(x, z, 152, 4) * PI * .5),
					world + Vector3(dw.x * .1, 0, dw.y * .1)))
				break
	# lantern pedestals in the corners of garden rooms
	if _region == "beach" and rt in ["cove", "tide_pool", "beach_hut", "boardwalk_room"]:
		var rect := _room_rect(rt, x, z)
		if rect.size != Vector2i.ZERO and ((x == rect.position.x and z == rect.position.y) \
				or (x == rect.end.x - 1 and z == rect.position.y) \
				or (x == rect.position.x and z == rect.end.y - 1) \
				or (x == rect.end.x - 1 and z == rect.end.y - 1)):
			_pedestal(world)
	# petals / litter on garden and stone floors
	if (_region == "beach" or _region == "gothic") and _h(x, z, 81, 5) == 0:
		_add("petal", Transform3D(Basis(Vector3.UP, _h(x, z, 82, 360) * PI / 180.0),
			world + Vector3(0, .012, 0)))


func _room_rect(room_type: String, x: int, z: int) -> Rect2i:
	for room_value in _data.get("rooms", []):
		var room: Dictionary = room_value
		var rect: Rect2i = room.get("rect", Rect2i())
		if String(room.get("room_type", "")) == room_type and rect.has_point(Vector2i(x, z)):
			return rect
	return Rect2i()


func _pedestal(world: Vector3) -> void:
	_add("pedestal", Transform3D(Basis.IDENTITY, world))
	var top := world + Vector3(0, 1.25, 0)
	lamps.append([_root.position + top, RefLook.AMBER_SOFT, .9, 1])
	_halo.append(top)
	_decal_pool.append(Vector3(world.x, 0, world.z))


func _lit_block(x: int, z: int, style: Dictionary) -> bool:
	return _h(x / 8, z / 8, 99, 100) < int(float(style["lit_rooms"]) * 100.0)


func _is_corridor_mid(grid: Array, x: int, z: int) -> bool:
	if _room_map.has(Vector2i(x, z)):
		return false
	return (_open(grid, x, z - 1) and _open(grid, x, z + 1) \
			and not _open(grid, x, z - 2) and not _open(grid, x, z + 2)) \
		or (_open(grid, x - 1, z) and _open(grid, x + 1, z) \
			and not _open(grid, x - 2, z) and not _open(grid, x + 2, z))


func _wall_lamp(base: Vector3, n: Vector3, kind: String, x: int, z: int) -> void:
	var pos := base + n * .02 + Vector3(0, SCONCE_Y, 0)
	var key := "lantern" if kind == "lantern" else "sconce"
	var lamp_basis := _facing_basis(n)
	if key == "lantern":
		lamp_basis = lamp_basis.scaled(Vector3.ONE * 1.7)
	_add(key, Transform3D(lamp_basis, pos))
	var flicker := _h(x, z, 41, 4)
	var light_pos := pos + n * .45
	lamps.append([_root.position + light_pos, RefLook.AMBER_SOFT if flicker != 0 else RefLook.AMBER, 1.0, flicker])
	_halo.append(light_pos - n * .35)
	# warm pool and glossy streak on the floor in front of the wall
	var floor_pos := Vector3(base.x, 0, base.z) + n * .85
	_decal_pool.append(floor_pos)
	_decal_streak.append(Vector3(base.x, 0, base.z) + n * 1.0)


func _ceiling_lamp(world: Vector3, x: int, z: int, height: float, small: bool = false) -> void:
	var pos := world + Vector3(0, height, 0)
	var yaw := PI * .5 if _h(x, z, 51, 2) == 0 else 0.0
	_add("ceiling_small" if small else "ceiling", Transform3D(Basis(Vector3.UP, yaw), pos))
	var flicker := _h(x, z, 52, 5)
	lamps.append([_root.position + pos - Vector3(0, .5, 0), RefLook.AMBER_SOFT, 1.1, flicker])
	_halo.append(pos - Vector3(0, .2, 0))
	_decal_pool.append(Vector3(world.x, 0, world.z))
	_decal_streak.append(Vector3(world.x, 0, world.z))


func _flush() -> void:
	for key in _transforms:
		var list: Array = _transforms[key]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh_for(key)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "Ref_%s" % key
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(inst)
	_flush_points("pool", _decal_pool, .014, Vector3(1.0, 1.0, 1.0))
	_flush_points("streak", _decal_streak, .02, Vector3.ONE)
	_flush_points("halo", _halo, 0.0, Vector3.ONE)


func _flush_points(key: String, points: PackedVector3Array, lift: float, _scale: Vector3) -> void:
	if points.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_for(key)
	mm.instance_count = points.size()
	for i in points.size():
		var p := points[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, p.y + lift, p.z)))
	var inst := MultiMeshInstance3D.new()
	inst.name = "Ref_%s" % key
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# draw additive light after opaque geometry, never through walls' depth
	_root.add_child(inst)


# -- meshes & materials --------------------------------------------------------

static func mesh_for(key: String) -> Mesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh: Mesh
	match key:
		"sconce": mesh = _build_sconce()
		"lantern": mesh = _build_lantern()
		"chandelier": mesh = _build_chandelier()
		"ceiling": mesh = _build_ceiling(Vector3(.86, .07, .26))
		"ceiling_small": mesh = _build_ceiling(Vector3(.6, .06, .18))
		"teal": mesh = _build_teal()
		"window": mesh = _build_window(Vector2(.95, 1.25))
		"window_tall": mesh = _build_window(Vector2(.8, 2.5))
		"pedestal": mesh = _build_pedestal()
		"planter": mesh = _build_planter()
		"floor_cable": mesh = _build_floor_cable()
		"frame0": mesh = _build_frame(Vector2(.62, .84))
		"frame1": mesh = _build_frame(Vector2(.8, .56))
		"pipe": mesh = _build_pipe(false)
		"pipe_brass": mesh = _build_pipe(true)
		"swag": mesh = _build_swag()
		"arch_header": mesh = _merge([["stone", _box(Vector3.ONE), Transform3D.IDENTITY]])
		"arch_cap": mesh = _merge([["brass", _box(Vector3.ONE), Transform3D.IDENTITY]])
		"rib": mesh = _merge([["iron", _box(Vector3(1.0, .3, .3)), _t(0, 0, 0)],
			["brass", _box(Vector3(1.0, .05, .34)), _t(0, -.17, 0)]])
		"chain": mesh = _merge([["iron", _cyl(.02, 1.0, 5), _t(0, 0, 0)]])
		"pool": mesh = _build_decal(3.4, "pool")
		"streak": mesh = _build_decal(2.0, "streak")
		"halo": mesh = _build_halo(1.1)
		"petal": mesh = _build_decal(.5, "petal")
		_: mesh = BoxMesh.new()
	_mesh_cache[key] = mesh
	return mesh


static func material(key: String) -> Material:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: Material
	match key:
		"brass":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("5a4020")
			s.metallic = .7
			s.roughness = .45
			m = s
		"iron":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("1a1617")
			s.metallic = .5
			s.roughness = .5
			m = s
		"rust":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("3a2418")
			s.metallic = .5
			s.roughness = .6
			m = s
		"canvas":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("160a12")
			s.roughness = 1.0
			m = s
		"amber", "amber_slow", "amber_fast":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("2a1406")
			s.emission_enabled = true
			s.emission = Color(1.0, .52, .13)
			s.emission_energy_multiplier = 1.15
			s.roughness = .3
			m = s
		"stone":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("2e2826")
			s.roughness = .8
			m = s
		"leaf":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("1f3a1c")
			s.roughness = 1.0
			m = s
		"bloom":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("8a2e52")
			s.roughness = .9
			m = s
		"bloom_pale":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("b09a88")
			s.roughness = .9
			m = s
		"night":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("070b16")
			s.emission_enabled = true
			s.emission = Color("17294a")
			s.emission_energy_multiplier = .8
			m = s
		"teal":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color("041418")
			s.emission_enabled = true
			s.emission = RefLook.TEAL
			s.emission_energy_multiplier = .95
			m = s
		"streak":
			var sm := ShaderMaterial.new()
			sm.shader = STREAK_SHADER
			sm.set_shader_parameter("streak_tex", _glow_texture("streak"))
			sm.render_priority = 1
			m = sm
		"pool", "petal", "halo":
			m = _decal_material(key)
		_:
			m = StandardMaterial3D.new()
	_mat_cache[key] = m
	return m


static func _decal_material(key: String) -> Material:
	var s := StandardMaterial3D.new()
	s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.cull_mode = BaseMaterial3D.CULL_DISABLED
	s.albedo_texture = _glow_texture(key)
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if key == "petal":
		s.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		s.albedo_color = Color(1, 1, 1, .9)
	if key == "halo":
		s.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		s.billboard_keep_scale = true
		s.no_depth_test = false
	else:
		s.render_priority = 1
	s.albedo_color = s.albedo_color if key == "petal" else Color(1, .62, .26, 1)
	return s


## Soft additive sprites, authored at 32x32 and drawn nearest so the glow
## stays chunky and posterises into bands under the pixel pass.
static func _glow_texture(key: String) -> Texture2D:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for y in size:
		for x in size:
			var u := (x + .5) / size * 2.0 - 1.0
			var v := (y + .5) / size * 2.0 - 1.0
			var a := 0.0
			match key:
				"pool":
					a = clampf(1.0 - Vector2(u, v).length(), 0, 1)
					a = a * a * .55
				"streak":
					# long vertical wet reflection, broken into dashes
					var w := clampf(1.0 - absf(u) * 1.9, 0, 1)
					var t := (v + 1.0) * .5
					var fade := pow(clampf(1.0 - t, 0, 1), 1.3)
					a = w * fade * (.8 if (y / 2 + int(rng.randf() * 2.0)) % 3 != 0 else .3)
				"halo":
					a = clampf(1.0 - Vector2(u, v).length(), 0, 1)
					a = pow(a, 2.4) * .8
				"petal":
					var px := (x * 7 + y * 13) % 11
					var c := Color("8a2a46") if px < 4 else Color("5a1830")
					if px < 6 and rng.randf() < .12:
						img.set_pixel(x, y, Color(c.r, c.g, c.b, 1))
					else:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
			# quantise to 6 bands: chunky pixel-glow
			a = floorf(a * 6.0) / 6.0
			img.set_pixel(x, y, Color(a, a, a, a))
	return ImageTexture.create_from_image(img)


static func _quad(size: float, horizontal: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * .5
	var pts := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
	if not horizontal:
		pts = [Vector3(-h, -h, 0), Vector3(h, -h, 0), Vector3(h, h, 0), Vector3(-h, h, 0)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var order := [0, 1, 2, 0, 2, 3] if horizontal else [0, 2, 1, 0, 3, 2]
	for i in order:
		st.set_normal(Vector3.UP if horizontal else Vector3.BACK)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	return st.commit()


static func _build_decal(size: float, key: String) -> Mesh:
	var mesh := _quad(size, true)
	mesh.surface_set_material(0, material(key))
	return mesh


static func _build_halo(size: float) -> Mesh:
	var mesh := _quad(size, false)
	mesh.surface_set_material(0, material("halo"))
	return mesh


## Merge boxes/cylinders into one surface per material.
static func _merge(parts: Array) -> ArrayMesh:
	# parts: [ [material_key, Mesh, Transform3D], ... ]
	var by_mat := {}
	var order: Array = []
	for part in parts:
		var key: String = part[0]
		if not by_mat.has(key):
			by_mat[key] = SurfaceTool.new()
			(by_mat[key] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
			order.append(key)
		(by_mat[key] as SurfaceTool).append_from(part[1], 0, part[2])
	var mesh := ArrayMesh.new()
	for key in order:
		(by_mat[key] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(key))
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(radius: float, height: float, sides: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func _build_sconce() -> Mesh:
	# brass backplate, glowing amber tube, brass caps and a clamp
	return _merge([
		["brass", _box(Vector3(.12, .52, .03)), _t(0, 0, .015)],
		["amber", _cyl(.045, .42), _t(0, 0, .085)],
		["brass", _box(Vector3(.09, .05, .09)), _t(0, .23, .085)],
		["brass", _box(Vector3(.09, .05, .09)), _t(0, -.23, .085)],
		["brass", _box(Vector3(.1, .03, .1)), _t(0, 0, .085)],
	])


static func _build_lantern() -> Mesh:
	var m := _merge([
		["iron", _box(Vector3(.1, .1, .04)), _t(0, .14, .02)],
		["iron", _box(Vector3(.03, .03, .1)), _t(0, .14, .07)],
		["amber", _box(Vector3(.16, .2, .16)), _t(0, 0, .15)],
		["brass", _box(Vector3(.2, .03, .2)), _t(0, .11, .15)],
		["brass", _box(Vector3(.2, .03, .2)), _t(0, -.11, .15)],
		["iron", _box(Vector3(.02, .2, .02)), _t(-.09, 0, .07)],
		["iron", _box(Vector3(.02, .2, .02)), _t(.09, 0, .07)],
		["iron", _box(Vector3(.02, .2, .02)), _t(-.09, 0, .23)],
		["iron", _box(Vector3(.02, .2, .02)), _t(.09, 0, .23)],
	])
	return m


static func _build_ceiling(size: Vector3) -> Mesh:
	# a caged strip lamp: wide dark frame, emissive panel, cross bars
	return _merge([
		["iron", _box(Vector3(size.x + .08, .04, size.z + .08)), _t(0, .02, 0)],
		["amber", _box(Vector3(size.x, size.y, size.z)), _t(0, -.02, 0)],
		["iron", _box(Vector3(.03, .08, size.z + .06)), _t(-size.x * .3, -.02, 0)],
		["iron", _box(Vector3(.03, .08, size.z + .06)), _t(size.x * .3, -.02, 0)],
		["brass", _box(Vector3(size.x + .1, .015, .03)), _t(0, -.06, size.z * .5)],
		["brass", _box(Vector3(size.x + .1, .015, .03)), _t(0, -.06, -size.z * .5)],
	])


static func _build_chandelier() -> Mesh:
	var parts := [["iron", _cyl(.02, .75, 5), _t(0, .52, 0)],
		["brass", _box(Vector3(.14, .08, .14)), _t(0, .16, 0)]]
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var rx := cos(a) * .42
		var rz := sin(a) * .42
		parts.append(["brass", _box(Vector3(.2, .035, .05)),
			Transform3D(Basis(Vector3.UP, -a - PI * .5), Vector3(rx * .98, 0, rz * .98))])
		if i % 4 != 3:
			parts.append(["amber", _cyl(.022, .13, 5), _t(rx, .08, rz)])
		parts.append(["brass", _box(Vector3(.05, .24, .02)), _t(rx * .5, .1, rz * .5)])
	parts.append(["amber", _cyl(.03, .15, 5), _t(0, .2, 0)])
	return _merge(parts)


static func _build_window(size: Vector2) -> Mesh:
	var parts := [["iron", _box(Vector3(size.x + .12, size.y + .12, .06)), _t(0, 0, .03)],
		["night", _box(Vector3(size.x, size.y, .02)), _t(0, 0, .065)],
		["iron", _box(Vector3(.04, size.y, .05)), _t(0, 0, .07)],
		["iron", _box(Vector3(size.x, .04, .05)), _t(0, size.y * .15, .07)]]
	if size.y > 2.0:
		parts.append(["iron", _box(Vector3(size.x, .04, .05)), _t(0, -size.y * .25, .07)])
	return _merge(parts)


static func _build_planter() -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7731
	var parts := [["stone", _box(Vector3(.8, .34, .8)), _t(0, .17, 0)],
		["iron", _box(Vector3(.86, .05, .86)), _t(0, .355, 0)]]
	for i in 16:
		var x := rng.randf_range(-.34, .34)
		var z := rng.randf_range(-.34, .34)
		var h := rng.randf_range(.12, .5)
		var key := "leaf"
		var size := Vector3(.16, h, .16)
		parts.append([key, _box(size), _t(x, .36 + h * .5, z)])
		if i % 3 == 0:
			parts.append(["bloom" if i % 2 == 0 else "bloom_pale", _box(Vector3(.12, .1, .12)),
				_t(x, .36 + h + .04, z)])
	return _merge(parts)


static func _build_pedestal() -> Mesh:
	return _merge([
		["rust", _box(Vector3(.42, .9, .42)), _t(0, .45, 0)],
		["iron", _box(Vector3(.5, .08, .5)), _t(0, .92, 0)],
		["iron", _box(Vector3(.5, .1, .5)), _t(0, .05, 0)],
		["brass", _box(Vector3(.3, .5, .02)), _t(0, .5, .22)],
		["amber", _box(Vector3(.18, .26, .18)), _t(0, 1.1, 0)],
		["brass", _box(Vector3(.24, .03, .24)), _t(0, 1.25, 0)],
		["brass", _box(Vector3(.24, .03, .24)), _t(0, .97, 0)],
		["iron", _box(Vector3(.02, .26, .02)), _t(-.1, 1.1, -.1)],
		["iron", _box(Vector3(.02, .26, .02)), _t(.1, 1.1, -.1)],
		["iron", _box(Vector3(.02, .26, .02)), _t(-.1, 1.1, .1)],
		["iron", _box(Vector3(.02, .26, .02)), _t(.1, 1.1, .1)],
	])


static func _build_floor_cable() -> Mesh:
	var parts := []
	var segs := 12
	var prev := Vector3.ZERO
	for i in segs + 1:
		var a := float(i) / segs
		var p := Vector3((a - .5) * 3.0, .0, sin(a * TAU * 1.1) * .35)
		if i > 0:
			var dir := p - prev
			var len := dir.length()
			var cyl := _cyl(.035, len, 5)
			# lay the Y-axis cylinder along `dir` (XZ plane)
			var basis := Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis(Vector3.RIGHT, PI * .5)
			parts.append(["iron", cyl, Transform3D(basis, (p + prev) * .5)])
		prev = p
	return _merge(parts)


static func _build_teal() -> Mesh:
	return _merge([
		["iron", _box(Vector3(.36, .46, .05)), _t(0, 0, .025)],
		["teal", _box(Vector3(.24, .3, .01)), _t(0, .03, .055)],
		["brass", _box(Vector3(.05, .03, .02)), _t(0, -.12, .06)],
	])


static func _build_frame(size: Vector2) -> Mesh:
	var parts := [
		["brass", _box(Vector3(size.x, size.y, .05)), _t(0, 0, .025)],
		["canvas", _box(Vector3(size.x - .12, size.y - .12, .02)), _t(0, 0, .055)],
	]
	return _merge(parts)


static func _build_pipe(brass: bool) -> Mesh:
	var cyl := _cyl(.055 if not brass else .04, 1.0)
	var key := "rust" if not brass else "brass"
	return _merge([
		[key, cyl, Transform3D(Basis(Vector3.BACK, PI * .5), Vector3.ZERO)],
		["iron", _box(Vector3(.06, .15, .14)), _t(-.3, 0, 0)],
		["iron", _box(Vector3(.06, .15, .14)), _t(.3, 0, 0)],
	])


static func _build_swag() -> Mesh:
	# a drooping cable span: 6 segments along a parabola, 4 m long
	var parts := []
	var seg := 8
	for i in seg:
		var a := float(i) / seg
		var b := float(i + 1) / seg
		var ax := (a - .5) * 4.0
		var bx := (b - .5) * 4.0
		var ay := -(1.0 - pow((a - .5) * 2.0, 2.0)) * .45
		var by := -(1.0 - pow((b - .5) * 2.0, 2.0)) * .45
		var mid := Vector3((ax + bx) * .5, (ay + by) * .5, 0)
		var dir := Vector3(bx - ax, by - ay, 0)
		var len := dir.length()
		var cyl := _cyl(.025, len, 5)
		var basis := Basis(Vector3.BACK, atan2(-dir.x, dir.y))
		parts.append(["iron", cyl, Transform3D(basis, mid)])
	return _merge(parts)


## Flicker: LampField drives the emission of the shared amber materials.
static func amber_materials() -> Array:
	return [material("amber"), material("amber_slow"), material("amber_fast")]
