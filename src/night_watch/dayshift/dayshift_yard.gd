class_name DayshiftYard
extends Node3D

## Salvage Run's 3D map (DayshiftMap): the ship and the scrap yard around the cargo bay (CargoBay at the origin). The bay's two halls continue as gantries (the Classic hall
## walls are opened at their ends); west: the dock (containers, a forklift), the airlock (a ring door and warning lights), the engine room (an engine block, pipes, gauges) and the bridge
## (consoles, a captain's chair, a star map); east: the cargo hold (shelving, pallets, barrels); south: the open scrap yard (scrap piles, a fence) with the crane, and the strip of
## ground under the bay's window. The hunters WALK this graph (AStar3D): Ravelle from the airlock to the left gantry, Ceryth from the hold to the right gantry, Ysolde from the crane
## to the window. Nothing jumps; every doorway is a gap in a wall recorded in `wall_boxes` for the path validator.

const A := preload("res://src/night_watch/night_watch_art.gd")
const H := 3.6
const THICK := 0.2
const STEEL := Color(0.8, 0.85, 1.0)
const RUST := Color(1.6, 0.9, 0.6)
const CONTAINERS := [Color(1.7, 0.5, 0.4), Color(0.5, 1.0, 1.7), Color(1.8, 1.5, 0.4), Color(0.6, 1.6, 0.7), Color(1.5, 0.7, 1.6)]
## where each hunter starts her walk (room centre) and the key of her first stand
const ORIGINS := {"ravelle": "C:airlock", "ceryth": "C:hold", "ysolde": "C:crane"}

var astar := AStar3D.new()
var points := {}
var _ids := {}
var _keys := {}
var rooms := {}
var wall_boxes := []
var office: Node3D


func _ready() -> void:
	if rooms.is_empty():
		build()


func _b(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o: Dictionary = opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _wall(parent: Node3D, along_x: bool, fixed: float, a: float, b: float, gaps: Array, tint: Color, node_name := "WallShip", height := H) -> void:
	var cuts := [a]
	for g in gaps:
		cuts.append(float(g[0]))
		cuts.append(float(g[1]))
	cuts.append(b)
	var i := 0
	while i < cuts.size() - 1:
		var s: float = cuts[i]
		var e: float = cuts[i + 1]
		i += 2
		if e - s < 0.05:
			continue
		var length := e - s
		var mid := (s + e) * 0.5
		_b(parent, Vector3(length, height, THICK) if along_x else Vector3(THICK, height, length), Vector3(mid, height * 0.5, fixed) if along_x else Vector3(fixed, height * 0.5, mid), node_name, {"tint": tint})
		wall_boxes.append({"name": node_name, "rect": Rect2(Vector2(s, fixed - THICK * 0.5), Vector2(length, THICK)) if along_x else Rect2(Vector2(fixed - THICK * 0.5, s), Vector2(THICK, length))})


func _slab(parent: Node3D, x0: float, x1: float, z0: float, z1: float, tint: Color, ceiling := true, node_name := "FloorShip") -> void:
	_b(parent, Vector3(x1 - x0, 0.2, z1 - z0), Vector3((x0 + x1) * 0.5, -0.1, (z0 + z1) * 0.5), node_name, {"tint": tint})
	if ceiling:
		_b(parent, Vector3(x1 - x0, 0.2, z1 - z0), Vector3((x0 + x1) * 0.5, H + 0.1, (z0 + z1) * 0.5), "CeilingShip", {"tint": Color(0.8, 0.8, 0.9)})


func build() -> void:
	var root := A.prop(self, "Ship")
	var hull := Color(1.0, 1.05, 1.25)
	var warm := Color(1.4, 1.1, 0.9)
	# gantries: the bay's halls carried on (their end walls are opened by the cargo bay)
	for side in [-1.0, 1.0]:
		var g := A.prop(root, "Gantry%s" % ("L" if side < 0.0 else "R"))
		var x0: float = minf(side * 9.3, side * 14.5)
		var x1: float = maxf(side * 9.3, side * 14.5)
		_slab(g, x0, x1, -1.7, 1.7, Color(0.8, 0.85, 1.0))
		_wall(g, true, -1.7, x0, x1, [], hull)
		_wall(g, true, 1.7, x0, x1, [], hull)
		for i in 4:
			_b(g, Vector3(0.1, 0.1, 3.2), Vector3(side * (10.0 + i * 1.2), 0.02, 0), "GratingGantry", {"kind": "metal", "tint": Color(0.7, 0.7, 0.8)})
		_b(g, Vector3(0.5, 0.3, 0.1), Vector3(side * 12.0, 2.4, -1.6), "SignGantry", {"kind": "label", "tint": Color(1.5, 1.2, 0.5)})
	_build_dock(root, hull)
	_build_airlock(root, hull)
	_build_engine(root, hull)
	_build_bridge(root, hull)
	_build_hold(root, warm)
	_build_yard(root)
	_build_paths()
	for id in ["airlock", "dockL", "gantryL", "engine", "bridge", "hold", "gantryR", "yard", "crane"]:
		var marker := Node3D.new()
		marker.name = "Room_%s" % id
		marker.position = points["C:%s" % id] if points.has("C:%s" % id) else Vector3.ZERO
		add_child(marker)
		rooms[id] = marker


func _container(parent: Node3D, pos: Vector3, tint: Color, size := Vector3(3.0, 1.4, 1.3)) -> void:
	var c := A.prop(parent, "Container", pos)
	_b(c, size, Vector3(0, size.y * 0.5, 0), "BodyContainer", {"kind": "metal", "tint": tint, "solid": true})
	for i in 4:
		_b(c, Vector3(0.06, size.y, size.z + 0.04), Vector3(-size.x * 0.4 + i * size.x * 0.27, size.y * 0.5, 0), "RibContainer", {"kind": "metal", "tint": tint * Color(0.8, 0.8, 0.8)})
	_b(c, Vector3(0.5, 0.2, 0.04), Vector3(size.x * 0.3, size.y * 0.8, size.z * 0.5 + 0.03), "LabelContainer", {"kind": "label", "tint": Color(1.5, 1.4, 0.7)})


func _build_dock(root: Node3D, hull: Color) -> void:
	var d := A.prop(root, "Dock", Vector3.ZERO)
	_slab(d, -26.0, -14.5, -9.0, 9.0, Color(0.85, 0.85, 1.0))
	_wall(d, false, -26.0, -9.0, 9.0, [[-2.0, 2.0]], hull)
	_wall(d, false, -14.5, -9.0, 9.0, [[-1.7, 1.7]], hull)
	_wall(d, true, -9.0, -26.0, -14.5, [[-22.0, -19.0]], hull)
	_wall(d, true, 9.0, -26.0, -14.5, [[-22.0, -19.0]], hull)
	# containers stacked in the corners (the lanes along z = 0 and x = -20.5 stay clear), a forklift, crates, a yellow lane line
	_container(d, Vector3(-23.5, 0, 6.0), CONTAINERS[0])
	_container(d, Vector3(-23.5, 1.4, 6.0), CONTAINERS[1])
	_container(d, Vector3(-17.0, 0, 6.2), CONTAINERS[2])
	_container(d, Vector3(-23.5, 0, -6.2), CONTAINERS[3])
	_container(d, Vector3(-16.5, 0, -6.0), CONTAINERS[4], Vector3(2.4, 1.4, 1.3))
	var fl := A.prop(d, "Forklift", Vector3(-17.5, 0, 3.0))
	_b(fl, Vector3(1.2, 0.9, 1.8), Vector3(0, 0.55, 0), "BodyForklift", {"kind": "metal", "tint": Color(1.8, 1.5, 0.3)})
	_b(fl, Vector3(0.9, 1.0, 0.1), Vector3(0, 1.0, -0.9), "MastForklift", {"kind": "metal"})
	_b(fl, Vector3(0.9, 0.08, 0.8), Vector3(0, 0.3, -1.3), "ForkForklift", {"kind": "metal", "tint": Color(0.7, 0.7, 0.8)})
	_b(d, Vector3(10.0, 0.012, 0.15), Vector3(-20.2, 0.007, 0.0), "LaneLine", {"kind": "label", "tint": Color(1.7, 1.4, 0.4)})
	_b(d, Vector3(0.5, 0.2, 0.06), Vector3(-25.8, 2.4, 0.0), "SignDock", {"kind": "label", "tint": Color(1.5, 1.2, 0.5)})


func _build_airlock(root: Node3D, hull: Color) -> void:
	var a := A.prop(root, "Airlock", Vector3.ZERO)
	_slab(a, -32.0, -26.0, -3.0, 3.0, Color(0.7, 0.75, 0.95))
	_wall(a, false, -32.0, -3.0, 3.0, [], hull)
	_wall(a, true, -3.0, -32.0, -26.0, [], hull)
	_wall(a, true, 3.0, -32.0, -26.0, [], hull)
	# a heavy ring door frame at the dock side, a wheel, warning lights (glowing cubes), a lever
	for sz in [-1.9, 1.9]:
		_b(a, Vector3(0.4, 2.8, 0.3), Vector3(-26.2, 1.4, sz), "FrameAirlock", {"kind": "metal", "tint": Color(1.6, 0.7, 0.4)})
	_b(a, Vector3(0.4, 0.3, 4.1), Vector3(-26.2, 2.9, 0), "FrameAirlock", {"kind": "metal", "tint": Color(1.6, 0.7, 0.4)})
	_b(a, Vector3(0.2, 0.9, 0.9), Vector3(-31.8, 1.5, 0), "WheelAirlock", {"kind": "metal", "tint": Color(0.7, 0.7, 0.8)})
	for sz in [-2.4, 2.4]:
		_b(a, Vector3(0.2, 0.2, 0.2), Vector3(-26.4, 2.8, sz), "GlowLampAirlock", {})
	_b(a, Vector3(0.1, 0.6, 0.1), Vector3(-29.0, 0.3, 2.4), "LeverAirlock", {"kind": "metal", "tint": Color(1.7, 0.5, 0.4)})


func _build_engine(root: Node3D, hull: Color) -> void:
	var e := A.prop(root, "EngineRoom", Vector3.ZERO)
	_slab(e, -26.0, -14.5, -22.0, -9.0, Color(0.75, 0.8, 0.95))
	_wall(e, false, -26.0, -22.0, -9.0, [], hull)
	_wall(e, false, -14.5, -22.0, -9.0, [[-17.0, -14.0]], hull)
	_wall(e, true, -22.0, -26.0, -14.5, [], hull)
	_b(e, Vector3(5.0, 2.2, 3.0), Vector3(-21.0, 1.1, -18.0), "BlockEngine", {"kind": "metal", "tint": Color(1.2, 0.7, 0.5), "solid": true})
	for i in 4:
		_b(e, Vector3(0.5, 0.5, 3.2), Vector3(-23.0 + i * 1.4, 2.45, -18.0), "PistonEngine", {"kind": "metal", "tint": STEEL})
	for i in 3:
		_b(e, Vector3(0.25, 3.0, 0.25), Vector3(-24.5, 1.5, -12.0 - i * 2.2), "PipeEngine", {"kind": "metal", "tint": Color(1.6, 0.8, 0.4)})
		_b(e, Vector3(0.2, 0.2, 0.06), Vector3(-24.4, 1.8, -12.0 - i * 2.2 + 0.2), "GlowGaugeEngine", {})
	_b(e, Vector3(1.2, 1.0, 1.0), Vector3(-16.5, 0.5, -12.0), "CrateEngine", {"kind": "wood"})


func _build_bridge(root: Node3D, hull: Color) -> void:
	var b := A.prop(root, "Bridge", Vector3.ZERO)
	_slab(b, -14.5, 2.0, -22.0, -10.0, Color(0.7, 0.8, 1.1))
	_wall(b, true, -22.0, -14.5, 2.0, [], hull)
	_wall(b, true, -10.0, -14.5, 2.0, [], hull)
	_wall(b, false, 2.0, -22.0, -10.0, [], hull)
	_b(b, Vector3(7.0, 1.0, 1.0), Vector3(-6.0, 0.5, -20.6), "ConsoleBridge", {"kind": "metal", "tint": Color(0.7, 0.8, 1.1), "solid": true})
	for i in 5:
		_b(b, Vector3(0.7, 0.4, 0.04), Vector3(-8.5 + i * 1.3, 1.25, -20.9), "ScreenBridge", {})
	_b(b, Vector3(0.8, 0.9, 0.8), Vector3(-6.0, 0.45, -17.5), "ChairBridge", {"kind": "fabric", "tint": Color(1.7, 0.5, 0.5)})
	_b(b, Vector3(2.0, 0.08, 2.0), Vector3(-1.0, 1.0, -16.0), "TableMapBridge", {"kind": "metal", "tint": Color(0.7, 0.8, 1.1)})
	_b(b, Vector3(1.6, 0.02, 1.6), Vector3(-1.0, 1.06, -16.0), "GlowMapBridge", {})
	_b(b, Vector3(4.0, 1.4, 0.1), Vector3(-6.0, 2.0, -21.9), "WindowBridge", {"kind": "glass", "tint": Color(0.6, 0.9, 1.2)})


func _build_hold(root: Node3D, warm: Color) -> void:
	var h := A.prop(root, "Hold", Vector3.ZERO)
	_slab(h, 14.5, 26.0, -9.0, 9.0, Color(1.0, 0.95, 0.85))
	_wall(h, false, 26.0, -9.0, 9.0, [], warm)
	_wall(h, false, 14.5, -9.0, 9.0, [[-1.7, 1.7]], warm)
	_wall(h, true, -9.0, 14.5, 26.0, [], warm)
	_wall(h, true, 9.0, 14.5, 26.0, [[18.0, 21.0]], warm)
	for i in 3:   # shelving along the east wall, pallets, barrels
		_b(h, Vector3(0.6, 0.05, 12.0), Vector3(25.4, 0.7 + i * 0.8, -2.0), "ShelfHold", {"kind": "metal"})
		for j in 5:
			_b(h, Vector3(0.45, 0.5, 0.9), Vector3(25.4, 1.0 + i * 0.8, -6.5 + j * 2.3), "BoxHold", {"kind": "wood", "tint": CONTAINERS[(i + j) % 5]})
	for pos in [Vector3(17.0, 0, -6.5), Vector3(21.0, 0, -6.5), Vector3(17.0, 0, 6.0)]:
		_b(h, Vector3(1.6, 0.18, 1.6), pos + Vector3(0, 0.09, 0), "PalletHold", {"kind": "wood"})
		_b(h, Vector3(1.4, 1.0, 1.4), pos + Vector3(0, 0.68, 0), "StackHold", {"kind": "wood", "tint": RUST})
	for pos in [Vector3(23.0, 0, 6.5), Vector3(24.0, 0, 5.5), Vector3(24.0, 0, 7.5)]:
		_b(h, Vector3(0.7, 0.95, 0.7), pos + Vector3(0, 0.48, 0), "BarrelHold", {"kind": "metal", "tint": Color(1.7, 0.6, 0.4)})
	_b(h, Vector3(0.5, 0.2, 0.06), Vector3(14.7, 2.4, 0.0), "SignHold", {"kind": "label", "tint": Color(1.5, 1.2, 0.5)})


func _build_yard(root: Node3D) -> void:
	var y := A.prop(root, "ScrapYard", Vector3.ZERO)
	_slab(y, -26.0, 26.0, 9.0, 28.0, Color(0.7, 0.72, 0.8), false, "GroundYard")
	_slab(y, -6.0, 6.0, 2.5, 9.0, Color(0.7, 0.72, 0.8), false, "GroundYard")
	# a fence round the outside
	_wall(y, true, 28.0, -26.0, 26.0, [], Color(0.7, 0.75, 0.9), "FenceYard", 2.2)
	_wall(y, false, -26.0, 9.0, 28.0, [], Color(0.7, 0.75, 0.9), "FenceYard", 2.2)
	_wall(y, false, 26.0, 9.0, 28.0, [], Color(0.7, 0.75, 0.9), "FenceYard", 2.2)
	# scrap piles of rusty cubes (clear of the lanes down x -20.5, x -1.5, x 19.5 and along z 18), a wrecked hull plate, drums
	var piles := [Vector3(-14, 0, 14), Vector3(-8, 0, 24), Vector3(6, 0, 25), Vector3(15, 0, 12), Vector3(-22, 0, 22), Vector3(22, 0, 24)]
	for i in piles.size():
		var p := A.prop(y, "ScrapPile", piles[i])
		for k in 6:
			_b(p, Vector3(1.0 + (k % 3) * 0.4, 0.6 + (k % 2) * 0.4, 1.0 + (k % 2) * 0.5), Vector3(-0.9 + (k % 3) * 0.9, 0.35 + (k / 3) * 0.7, -0.4 + (k % 2) * 0.8), "ScrapBlock", {"kind": "metal", "tint": RUST * Color(1.0 - 0.08 * k, 1.0, 1.0)})
	_b(y, Vector3(6.0, 0.4, 3.0), Vector3(-12.0, 1.6, 20.0), "HullPlateYard", {"kind": "metal", "tint": Color(0.9, 1.0, 1.3), "rotation": Vector3(0.0, 0.4, 0.2)})
	# the crane: two legs, a boom, a cable and a hook (the crane's spot is where Ysolde waits)
	var c := A.prop(y, "Crane", Vector3(10.0, 0, 22.0))
	for sx in [-1.6, 1.6]:
		_b(c, Vector3(0.3, 7.0, 0.3), Vector3(sx, 3.5, 0), "LegCrane", {"kind": "metal", "tint": Color(1.7, 1.4, 0.3)})
	_b(c, Vector3(4.0, 0.3, 0.3), Vector3(0, 7.0, 0), "BeamCrane", {"kind": "metal", "tint": Color(1.7, 1.4, 0.3)})
	_b(c, Vector3(0.3, 0.3, 6.0), Vector3(0, 7.3, -2.5), "BoomCrane", {"kind": "metal", "tint": Color(1.7, 1.4, 0.3)})
	_b(c, Vector3(0.05, 4.5, 0.05), Vector3(0, 4.7, -4.5), "CableCrane", {"kind": "plastic"})
	_b(c, Vector3(0.5, 0.4, 0.5), Vector3(0, 2.3, -4.5), "HookCrane", {"kind": "metal", "tint": Color(1.6, 0.6, 0.4)})
	_b(c, Vector3(0.4, 0.3, 0.1), Vector3(0, 7.7, 0.4), "GlowLampCrane", {})
	# the window's strip: a bench and a lamp post by the bay
	_b(y, Vector3(0.1, 2.6, 0.1), Vector3(1.8, 1.3, 5.0), "PostYard", {"kind": "metal"})
	_b(y, Vector3(0.5, 0.12, 0.3), Vector3(1.5, 2.6, 5.0), "GlowYardLamp", {})


# --- walking -------------------------------------------------------------------------------------------------------------------------

func _add(key: String, x: float, z: float) -> void:
	var id := astar.get_available_point_id()
	var pos := Vector3(x, 0.0, z)
	astar.add_point(id, pos)
	_ids[key] = id
	_keys[id] = key
	points[key] = pos


func _link_chain(keys: Array) -> void:
	for i in range(keys.size() - 1):
		astar.connect_points(int(_ids[keys[i]]), int(_ids[keys[i + 1]]), true)


func _build_paths() -> void:
	for p in [["C:airlock", -29.0, 0.0], ["A1", -26.3, 0.0], ["C:dockL", -20.0, 0.0], ["G:L", -12.0, 0.0], ["HL", -9.3, 0.0], ["D:L3", -8.8, 0.0],
			["N1", -20.5, -7.5], ["N2", -20.5, -10.5], ["C:engine", -20.0, -15.5], ["E1", -14.5, -15.5], ["E2", -12.0, -15.5], ["C:bridge", -6.0, -16.0],
			["S1", -20.5, 7.5], ["S2", -20.5, 10.5], ["Y_W", -20.5, 15.0], ["C:yard", 0.0, 18.0], ["Y_S", -1.5, 8.0], ["W:stand", -1.5, 3.45],
			["C:crane", 10.0, 20.0], ["C:hold", 20.0, 0.0], ["G:R", 12.0, 0.0], ["HR", 9.3, 0.0], ["D:R3", 8.8, 0.0],
			["S3", 19.5, 7.5], ["S4", 19.5, 10.5], ["Y_E", 19.5, 15.0]]:
		_add(String(p[0]), float(p[1]), float(p[2]))
	_link_chain(["C:airlock", "A1", "C:dockL", "G:L", "HL", "D:L3"])
	_link_chain(["C:dockL", "N1", "N2", "C:engine", "E1", "E2", "C:bridge"])
	_link_chain(["C:dockL", "S1", "S2", "Y_W", "C:yard"])
	_link_chain(["C:yard", "Y_S", "W:stand"])
	_link_chain(["C:yard", "C:crane"])
	_link_chain(["C:hold", "G:R", "HR", "D:R3"])
	_link_chain(["C:hold", "S3", "S4", "Y_E", "C:yard"])


func route(from_key: String, to_key: String) -> Array:
	var out := []
	if not _ids.has(from_key) or not _ids.has(to_key):
		return out
	for id in astar.get_id_path(int(_ids[from_key]), int(_ids[to_key])):
		var key := String(_keys[id])
		out.append({"p": points[key], "jump": false, "key": key})
	return out


## The walk from a hunter's origin to her first stand: Ravelle to the left gantry's end, Ceryth to the right's, Ysolde to the window.
func legs_to(hunter: String, target_key: String) -> Array:
	return route(String(ORIGINS[hunter]), target_key)


func legs_from(pos: Vector3, target_key: String) -> Array:
	var start := int(astar.get_closest_point(pos))
	if start < 0:
		return []
	return route(String(_keys[start]), target_key)
