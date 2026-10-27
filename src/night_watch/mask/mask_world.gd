class_name MaskWorld
extends NightWatchBuilding

## Masked Hours' 3D world: the wing's seven camera rooms (music room, costume store, mask gallery, ballroom, crawlspace, the two dark ducts) built
## from the shared blocky art on NightWatchBuilding's room shell, far from the office; the hall (CAM 8) is the office's own right-hand corridor,
## so a hunter on her last steps and Umbriel's run are really seen in the doorway. Also the paths the hunters WALK (a waypoint graph searched with
## AStar3D, like NightWatchPaths: from a room's centre out its open south mouth, along the lane, in at a north doorway; the ballroom to the hall's
## far end is the one jump, out of sight in the dark) and the changes that turn the Classic office into Masked Hours' (no doors, the mask, the music
## box, two vent grates, the hall light).

const WING_ORIGIN := Vector3(-12.0, 0.0, -66.0)
const HALL_FAR_X := 9.0      # the corridor's far end (office-relative x) where the hall walker comes in
const HALL_NEAR_X := 4.2     # the last step before the doorway
const RUSH_DOOR_X := 3.7     # where Umbriel stops
const OFFICE_WALKER := Vector3(2.1, 0.0, 0.5)   # where the hall walker stands once she is in the office
const VENT_STAND := {"L": Vector3(-2.3, 0.0, -1.55), "R": Vector3(2.3, 0.0, -1.55)}
const TINTS := {
	"music": Color(1.2, 0.95, 1.25), "costume": Color(1.25, 0.85, 1.0), "gallery": Color(1.0, 1.0, 1.3), "ballroom": Color(1.3, 1.1, 0.8),
	"crawl": Color(0.8, 0.85, 0.95), "ductL": Color(0.55, 0.6, 0.7), "ductR": Color(0.55, 0.6, 0.7),
}
const DOORWAY_N := ["ballroom", "ductL", "ductR"]

var astar := AStar3D.new()
var points := {}
var _ids := {}
var _keys := {}
var _jumps := {}
var office: NightWatchOffice
var glints := {}        # duct room -> Node3D (eyeshine)
var duct_lights := {}   # "ductL" / "ductR" -> OmniLight3D


func has_doorway(side: String, id: String) -> bool:
	return side == "N" and DOORWAY_N.has(id)


func _ready() -> void:
	if rooms.is_empty():
		build()


func build() -> void:
	for id in MaskData.ROOMS:
		var info: Dictionary = MaskData.ROOMS[id]
		if not TINTS.has(id):
			continue
		var room := Node3D.new()
		room.name = "Room_%s" % id
		var grid: Vector2i = info["grid"]
		room.position = WING_ORIGIN + Vector3(grid.x * CELL, 0.0, grid.y * CELL)
		add_child(room)
		rooms[id] = room
		_build_room(room, String(id), TINTS[id])
		_dress(room, String(id))
	# the empty bay beside the crawlspace, so the lane has somewhere to run
	var bay := Node3D.new()
	bay.name = "Bay"
	bay.position = WING_ORIGIN + Vector3(2 * CELL, 0.0, 1 * CELL)
	add_child(bay)
	_c(bay, Vector3(ROOM_W, ROOM_H, 0.3), Vector3(0, ROOM_H * 0.5, -ROOM_W * 0.5), "WallBay", {"tint": Color(0.6, 0.6, 0.7), "solid": true})
	for i in 4:
		_c(bay, Vector3(1.0, 0.8, 1.0), Vector3(-1.8 + i * 1.2, 0.4, -1.8), "CrateBay", {"kind": "wood", "tint": Color(0.8, 0.75, 0.7)})
	_build_paths()


func _dress(room: Node3D, id: String) -> void:
	var p := _group(room, id, "Dress")
	match id:
		"music":
			_c(p, Vector3(1.6, 0.8, 1.0), Vector3(0, 0.4, -1.0), "TablePedestal", {})
			_c(p, Vector3(0.9, 0.5, 0.6), Vector3(0, 1.05, -1.0), "BoxMusic", {"kind": "wood", "tint": Color(1.2, 0.9, 1.1)})
			_c(p, Vector3(0.1, 0.5, 0.1), Vector3(0.55, 1.3, -1.0), "HandleCrank", {"kind": "metal"})
			_c(p, Vector3(0.4, 0.06, 0.4), Vector3(0, 1.33, -1.0), "LidMusic", {"kind": "wood", "tint": Color(1.3, 1.0, 1.2)})
			for x in [-2.2, 2.2]:
				_c(p, Vector3(0.5, 2.4, 0.2), Vector3(x, 1.2, -2.7), "CurtainMusic", {"tint": Color(0.9, 0.4, 1.0)})
		"costume":
			for i in 3:
				_c(p, Vector3(0.1, 1.9, 0.1), Vector3(-2.2 + i * 1.6, 0.95, -2.2), "RailRack", {"kind": "metal"})
				_c(p, Vector3(1.2, 0.08, 0.1), Vector3(-2.2 + i * 1.6, 1.85, -2.2), "RailTop", {"kind": "metal"})
				for j in 3:
					_c(p, Vector3(0.18, 0.9, 0.3), Vector3(-2.7 + i * 1.6 + j * 0.45, 1.3, -2.2), "CostumeHung", {"kind": "fabric", "tint": Color(1.0 + j * 0.15, 0.7 + i * 0.2, 0.9)})
			_c(p, Vector3(0.45, 0.8, 0.3), Vector3(2.4, 1.3, 0.4), "MannequinBody", {"kind": "plastic", "tint": Color(1.6, 1.5, 1.4)})
			_c(p, Vector3(0.3, 0.3, 0.3), Vector3(2.4, 1.95, 0.4), "MannequinHead", {"kind": "plastic", "tint": Color(1.7, 1.6, 1.5)})
		"gallery":
			for i in 6:
				for j in 2:
					_c(p, Vector3(0.4, 0.55, 0.1), Vector3(-2.1 + i * 0.84, 1.2 + j * 0.8, -2.8), "MaskWall", {"kind": "plastic", "tint": Color(1.7, 1.65, 1.55)})
					_c(p, Vector3(0.28, 0.07, 0.04), Vector3(-2.1 + i * 0.84, 1.28 + j * 0.8, -2.73), "MaskEyes", {"kind": "plastic", "tint": Color(0.3, 0.3, 0.35)})
			_c(p, Vector3(0.8, 1.0, 0.8), Vector3(0, 0.5, 0.4), "PlinthGallery", {"kind": "concrete"})
			_c(p, Vector3(0.45, 0.55, 0.12), Vector3(0, 1.28, 0.4), "MaskPlinth", {"kind": "plastic", "tint": Color(1.8, 1.75, 1.6)})
		"ballroom":
			for x in [-2.3, 2.3]:
				for z in [-1.8, 1.4]:
					_c(p, Vector3(0.45, 3.0, 0.45), Vector3(x, 1.5, z), "PillarBall", {"solid": true})
			_c(p, Vector3(1.8, 0.1, 1.8), Vector3(0, 2.7, -0.2), "ChandelierRing", {"kind": "metal"})
			_c(p, Vector3(0.9, 0.1, 0.9), Vector3(0, 2.55, -0.2), "GlowChandelier", {})
			_c(p, Vector3(4.6, 0.02, 4.6), Vector3(0, 0.02, -0.2), "RunnerBall", {"kind": "fabric", "tint": Color(1.2, 0.8, 0.7)})
		"crawl":
			for i in 3:
				_c(p, Vector3(5.6, 0.14, 0.14), Vector3(0, 1.3 + i * 0.35, -2.4 + i * 1.5), "PipeCrawl", {"kind": "metal"})
			for i in 3:
				_c(p, Vector3(0.7, 0.55, 0.7), Vector3(-2.0 + i * 1.8, 0.28, 1.5), "CrateCrawl", {"kind": "wood"})
			_c(p, Vector3(0.9, 1.0, 0.2), Vector3(-2.7, 0.8, -0.4), "HatchCrawlL", {"kind": "metal", "tint": Color(0.5, 0.5, 0.55)})
			_c(p, Vector3(0.9, 1.0, 0.2), Vector3(2.7, 0.8, -0.4), "HatchCrawlR", {"kind": "metal", "tint": Color(0.5, 0.5, 0.55)})
		"ductL", "ductR":
			_c(p, Vector3(1.6, 0.1, 5.2), Vector3(0, 0.05, 0.0), "DuctFloor", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
			for sx in [-0.85, 0.85]:
				_c(p, Vector3(0.1, 1.6, 5.2), Vector3(sx, 0.8, 0.0), "DuctSide", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65), "solid": false})
			for i in 5:
				_c(p, Vector3(1.7, 0.06, 0.08), Vector3(0, 1.58, -2.2 + i * 1.1), "DuctRib", {"kind": "metal"})
			_c(p, Vector3(1.4, 1.2, 0.08), Vector3(0, 0.7, -2.5), "DuctGrate", {"kind": "metal", "tint": Color(0.4, 0.4, 0.45)})
			# eyeshine: two glints at one fixed spot whoever she is
			var glint := Node3D.new()
			glint.name = "Glint"
			glint.position = Vector3(0, 0.9, -0.4)
			p.add_child(glint)
			for gx in [-0.12, 0.12]:
				_c(glint, Vector3(0.06, 0.04, 0.04), Vector3(gx, 0, 0), "GlowEye", {})
			glint.visible = false
			glints[id] = glint
			var lamp := OmniLight3D.new()
			lamp.name = "DuctLight"
			lamp.light_color = Color(1.0, 0.95, 0.8)
			lamp.light_energy = 2.2
			lamp.omni_range = 7.0
			lamp.position = Vector3(0, 1.8, 2.2)
			lamp.visible = false
			room.add_child(lamp)
			duct_lights[id] = lamp


# --- the hall (CAM 8) ------------------------------------------------------------------------------------------------------

## The hall's feed camera: over the office doorway, looking back down the corridor.
func hall_camera(office_pos: Vector3) -> Transform3D:
	var from := office_pos + Vector3(NightWatchOffice.HALF_W + 0.1, 2.7, 0.0)
	var target := office_pos + Vector3(HALL_FAR_X, 1.0, 0.0)
	return Transform3D(Basis.IDENTITY, from).looking_at(target, Vector3.UP)


func feed_transform(room: String) -> Transform3D:
	if room == "hall":
		return hall_camera(office.global_position)
	return camera_transform(room)


## Where a hunter stands in a room as the feed sees her (slot 0/1); the hall is the office corridor.
func stand_at(room: String, slot: int, at := "stand") -> Vector3:
	var o := office.global_position
	if room == "hall":
		return o + Vector3(HALL_NEAR_X + slot * 1.2, 0.0, 0.0)
	if room == "office":
		return o + OFFICE_WALKER + Vector3(0, 0, slot * 1.1)
	if MaskData.DUCT_SIDE.has(room):
		var z: float = {"far": -2.0, "stand": -0.2, "near": 1.7}.get(at, -0.2)
		return (rooms[room] as Node3D).global_position + Vector3(0.0, 0.0, z)
	var base := stand_position(room, slot)
	if room == "crawl":
		base += Vector3(0.8, 0.0, 0.2)
	return base


func hall_pos(step: int) -> Vector3:
	return office.global_position + Vector3(lerpf(HALL_FAR_X, HALL_NEAR_X, clampf(float(step) / float(MaskLogic.T["hallSteps"]), 0.0, 1.0)), 0.0, 0.0)


func rush_pos(progress: float) -> Vector3:
	return office.global_position + Vector3(lerpf(HALL_FAR_X, RUSH_DOOR_X, clampf(progress, 0.0, 1.0)), 0.0, 0.0)


# --- walking ---------------------------------------------------------------------------------------------------------------

func _add(key: String, pos: Vector3) -> void:
	var id := astar.get_available_point_id()
	astar.add_point(id, pos)
	_ids[key] = id
	_keys[id] = key
	points[key] = pos


func _link(a: String, b: String, jump := false) -> void:
	astar.connect_points(int(_ids[a]), int(_ids[b]), true)
	if jump:
		_jumps["%s|%s" % [a, b]] = true
		_jumps["%s|%s" % [b, a]] = true


func _cell_key(c: int, r: int) -> String:
	return "L:%d,%d" % [c, r]


func _build_paths() -> void:
	# lane points for every cell of rows 0 and 1, centre / south mouth for every room
	for r in 2:
		for c in 3:
			_add(_cell_key(c, r), WING_ORIGIN + Vector3(c * CELL, 0.0, r * CELL + 4.0))
	for id in rooms:
		var g: Vector2i = MaskData.ROOMS[id]["grid"]
		var centre := (rooms[id] as Node3D).global_position
		_add("C:%s" % id, centre)
		_add("S:%s" % id, centre + Vector3(0, 0, 2.6))
		_link("C:%s" % id, "S:%s" % id)
		if g.y < 2:
			_link("S:%s" % id, _cell_key(g.x, g.y))
	for r in 2:
		for c in 2:
			_link(_cell_key(c, r), _cell_key(c + 1, r))
	# north doorways: the lane above leads into the room below
	for id in DOORWAY_N:
		var g2: Vector2i = MaskData.ROOMS[id]["grid"]
		_link(_cell_key(g2.x, g2.y - 1), "C:%s" % id)
	# the ballroom opens onto the hall's far end (a jump, out of sight)
	if office != null:
		_add("H:far", office.global_position + Vector3(HALL_FAR_X + 0.6, 0.0, 0.0))
		_link("S:ballroom", "H:far", true)


func key_for(room: String) -> String:
	if room == "hall" or room == "office":
		return "H:far"
	return "C:%s" % room


func route(from_key: String, to_key: String) -> Array:
	var out := []
	if not _ids.has(from_key) or not _ids.has(to_key):
		return out
	var last := ""
	for id in astar.get_id_path(int(_ids[from_key]), int(_ids[to_key])):
		var key := String(_keys[id])
		out.append({"p": points[key], "jump": _jumps.has("%s|%s" % [last, key]), "key": key})
		last = key
	return out


## The route from where a hunter stands now to a sim room.
func legs_from(pos: Vector3, to_room: String) -> Array:
	var start := int(astar.get_closest_point(pos))
	if start < 0:
		return []
	return route(String(_keys[start]), key_for(to_room))
