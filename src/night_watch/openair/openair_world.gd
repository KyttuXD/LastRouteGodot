class_name NightWatchOpenAirWorld
extends Node3D

## Open Air's three outdoor sets, built from NightWatchArt cubes like the security room: the ROOFTOP (a parapet roof with the stair door on
## the left and the hatch on the right, a lantern post and a torch stand each side), the BUS STOP (a shelter with a heat lamp and bench on a
## pavement beside the road, three places a fuel canister turns up, a bus that comes up the road at dawn) and the CAMPFIRE (a fire pit,
## a log pile, firewood at the edge of the trees, a torch post each side and a tent, in a clearing ringed with trees). The things you can
## aim at are NightWatchStation nodes (the shared interactables); the hunters' waypoint graph (NightWatchOpenAirPaths) is built here too,
## on the same coordinates, so they walk the catwalks, the road and the trees. Real lights: the lantern / lamp / fire and one torch spot.

const A := preload("res://src/night_watch/night_watch_art.gd")
const D := preload("res://src/night_watch/openair/openair_data.gd")

var watch := 0
var stations := {}             # station id -> NightWatchStation
var prompts := {}              # station id -> its prompt (the validator reads them)
var props := {}
var paths: NightWatchOpenAirPaths
var spawn := Vector3.ZERO
var light: OmniLight3D         # the lantern / the heat lamp / the fire
var torch_spot: SpotLight3D
var weather_fx: CPUParticles3D
var env: Environment
var slabs := {}                # rooftop: "L"/"R" -> the bar slab (door / hatch cover)
var can_nodes := {}            # bus stop: canister index -> Node3D
var bus: Node3D
var fire_glow: MeshInstance3D
var pile: Node3D
var tent_zone := Rect2()       # campfire: the floor of the tent (x, z)
var tent_in := Vector3.ZERO
var tent_out := Vector3.ZERO
var bar_progress := {"L": 0.0, "R": 0.0}
var _fire_flicker := 0.0

const SLAB_OPEN_Y := 3.6
const SLAB_CLOSED_Y := 1.2
const ROOF_X := 6.5
const ROOF_Z := 5.0


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _prop(prop_name: String) -> Node3D:
	var node := A.prop(self, prop_name)
	props[prop_name] = node
	return node


func _station(id: String, prompt: String, pos: Vector3, focus := Vector3.ZERO) -> NightWatchStation:
	var st := NightWatchStation.new()
	st.name = "Station_" + id
	st.station_id = id
	st.prompt_text = prompt
	st.focus_local = focus
	st.position = pos
	add_child(st)
	prompts[id] = prompt
	stations[id] = st
	return st


func _point_light(node_name: String, pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = node_name
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	add_child(l)
	return l


func build(watch_index: int) -> void:
	watch = clampi(watch_index, 0, 2)
	paths = NightWatchOpenAirPaths.new()
	match watch:
		0:
			_build_rooftop()
		1:
			_build_busstop()
		2:
			_build_campfire()
	_build_sky()
	torch_spot = SpotLight3D.new()
	torch_spot.name = "TorchSpot"
	torch_spot.light_color = Color(1.0, 0.72, 0.4)
	torch_spot.light_energy = 0.0
	torch_spot.spot_range = 9.0
	torch_spot.spot_angle = 38.0
	add_child(torch_spot)


## The night sky: a dark dome round the set (the open horizon otherwise renders pale in the compatibility renderer).
func _build_sky() -> void:
	var dome := MeshInstance3D.new()
	dome.name = "NightSky"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(220.0, 120.0, 220.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.03, 0.07)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mesh.material = mat
	dome.mesh = mesh
	dome.position = Vector3(0, 40.0, -2.0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)


# --- the rooftop -------------------------------------------------------------------------------------------------------------

func _build_rooftop() -> void:
	spawn = Vector3(0.0, 0.0, 1.6)
	var roof := _prop("Roof")
	_c(roof, Vector3(ROOF_X * 2.0 + 0.4, 0.3, ROOF_Z * 2.0 + 0.4), Vector3(0, -0.15, 0), "Floor", {"solid": true, "kind": "concrete", "tint": Color(0.8, 0.8, 0.85)})
	for z in [-ROOF_Z - 0.1, ROOF_Z + 0.1]:
		_c(roof, Vector3(ROOF_X * 2.0 + 0.4, 1.1, 0.2), Vector3(0, 0.55, z), "ParapetWall", {"solid": true, "kind": "concrete"})
	var piece := ROOF_Z - 1.0
	for s in [-1.0, 1.0]:
		var x: float = s * (ROOF_X + 0.1)
		for zz in [-1.0 - piece * 0.5, 1.0 + piece * 0.5]:
			_c(roof, Vector3(0.2, 1.1, piece), Vector3(x, 0.55, zz), "ParapetWall", {"solid": true, "kind": "concrete"})
		# the doorway's frame, a header, and an invisible block beyond it (the player stays on the roof)
		_c(roof, Vector3(0.3, 0.2, 2.2), Vector3(x, 2.5, 0), "DoorHeader", {"kind": "metal"})
		for zz in [-1.0, 1.0]:
			_c(roof, Vector3(0.3, 2.5, 0.2), Vector3(x, 1.25, zz), "DoorFrame", {"kind": "metal", "tint": Color(0.7, 0.55, 0.3)})
		var block := StaticBody3D.new()
		block.collision_layer = 1
		block.collision_mask = 0
		block.position = Vector3(s * (ROOF_X + 0.6), 1.0, 0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.4, 2.0, 2.4)
		cs.shape = bs
		block.add_child(cs)
		roof.add_child(block)
		# the slab: the stair door (L) / the hatch cover (R), slid down to bar it
		var tag := "L" if s < 0.0 else "R"
		var slab := _c(roof, Vector3(0.18, 2.4, 2.0), Vector3(x, SLAB_OPEN_Y, 0), "Slab" + tag, {"kind": "metal", "tint": Color(0.6, 0.62, 0.7) if s < 0.0 else Color(0.7, 0.55, 0.3)})
		slabs[tag] = slab
	# the catwalk each hunter climbs: a gantry from the far end round the corner to the door
	var walk := _prop("Catwalks")
	for s in [-1.0, 1.0]:
		_c(walk, Vector3(2.3, 0.2, 2.4), Vector3(s * (ROOF_X + 1.35), -0.1, 0), "CatwalkPlatform", {"kind": "metal"})
		_c(walk, Vector3(2.0, 0.2, 6.0), Vector3(s * (ROOF_X + 2.2), -0.1, -3.6), "CatwalkPlatform", {"kind": "metal"})
		_c(walk, Vector3(2.0, 0.2, 7.0), Vector3(s * (ROOF_X + 2.2), -0.1, -9.0), "CatwalkPlatform", {"kind": "metal"})
		_c(walk, Vector3(0.08, 0.9, 6.0), Vector3(s * (ROOF_X + 3.1), 0.45, -3.6), "CatwalkRail", {"kind": "metal"})
	_c(walk, Vector3(ROOF_X * 2.0 + 4.0, 0.2, 2.0), Vector3(0, -0.1, -ROOF_Z - 3.2), "CatwalkPlatform", {"kind": "metal"})
	_c(walk, Vector3(ROOF_X * 2.0 + 4.0, 0.08, 0.1), Vector3(0, 0.5, -ROOF_Z - 4.1), "CatwalkRail", {"kind": "metal"})
	# the lantern post, a torch stand each side, a vent box, a few crates
	var kit := _prop("Kit")
	_c(kit, Vector3(0.14, 1.9, 0.14), Vector3(0, 0.95, -3.0), "LanternPost", {"kind": "metal", "solid": true})
	_c(kit, Vector3(0.5, 0.5, 0.5), Vector3(0, 2.1, -3.0), "LanternGlow", {})
	for s in [-1.0, 1.0]:
		_c(kit, Vector3(0.12, 1.4, 0.12), Vector3(s * 4.8, 0.7, -1.6), "TorchStand", {"kind": "metal", "solid": true})
		_c(kit, Vector3(0.22, 0.22, 0.22), Vector3(s * 4.8, 1.5, -1.6), "TorchGlow", {})
	_c(kit, Vector3(1.4, 1.0, 1.0), Vector3(-2.6, 0.5, -3.6), "CrateStack", {"solid": true})
	_c(kit, Vector3(0.9, 0.8, 0.9), Vector3(2.8, 0.4, 3.8), "CrateSmall", {"solid": true})
	_c(kit, Vector3(1.6, 0.6, 1.2), Vector3(3.6, 0.3, -3.5), "VentBox", {"kind": "metal", "solid": true})
	light = _point_light("LanternLight", Vector3(0, 2.1, -2.7), Color(1.0, 0.8, 0.5), 2.2, 11.0)
	_station("barL", "BAR THE STAIR DOOR  Z", Vector3(-5.9, 1.1, 1.5))
	_station("barR", "SHUT THE HATCH  X", Vector3(5.9, 1.1, 1.5))
	_station("torchL", "TORCH LEFT (HOLD)  G", Vector3(-4.8, 1.2, -1.6))
	_station("torchR", "TORCH RIGHT (HOLD)  H", Vector3(4.8, 1.2, -1.6))
	_station("lantern", "RELIGHT THE LANTERN (HOLD)  F", Vector3(0.0, 1.3, -2.8))
	# hunter waypoints: L3..L0 (far end, round the corner, to the stair door), R3..R0, the two far ends joined round the back
	var walkers := {"L": -1.0, "R": 1.0}
	for tag in walkers:
		var s: float = walkers[tag]
		paths.add(tag + "3", Vector3(s * (ROOF_X + 2.2), 0, -11.0))
		paths.add(tag + "2", Vector3(s * (ROOF_X + 2.2), 0, -5.5))
		paths.add(tag + "1", Vector3(s * (ROOF_X + 2.2), 0, -1.6))
		paths.add(tag + "0", Vector3(s * (ROOF_X + 1.0), 0, 0))
		paths.chain([tag + "3", tag + "2", tag + "1", tag + "0"])
	paths.add("B", Vector3(0, 0, -ROOF_Z - 3.2))
	paths.add("BL", Vector3(-(ROOF_X + 2.2), 0, -ROOF_Z - 3.2))
	paths.add("BR", Vector3(ROOF_X + 2.2, 0, -ROOF_Z - 3.2))
	paths.chain(["BL", "B", "BR"])
	paths.link("BL", "L2")
	paths.link("BR", "R2")


# --- the bus stop --------------------------------------------------------------------------------------------------------------

func _build_busstop() -> void:
	spawn = Vector3(0.0, 0.0, 1.2)
	var ground := _prop("Street")
	_c(ground, Vector3(30.0, 0.3, 8.0), Vector3(0, -0.15, 3.0), "Floor", {"solid": true, "kind": "concrete", "tint": Color(0.75, 0.75, 0.8)})
	_c(ground, Vector3(60.0, 0.3, 7.0), Vector3(0, -0.2, -4.0), "RoadFloor", {"kind": "floor", "tint": Color(0.45, 0.45, 0.5)})
	for x in range(-24, 25, 4):
		_c(ground, Vector3(1.6, 0.02, 0.14), Vector3(float(x), 0.0, -4.0), "RoadStripe", {"kind": "label", "tint": Color(0.9, 0.9, 0.8)})
	_c(ground, Vector3(30.0, 0.22, 0.3), Vector3(0, 0.0, -0.4), "Kerb", {"kind": "concrete", "solid": true})
	_c(ground, Vector3(30.0, 1.2, 0.3), Vector3(0, 0.6, 7.2), "BackFence", {"solid": true, "kind": "wall"})
	for s in [-1.0, 1.0]:
		_c(ground, Vector3(0.3, 1.2, 8.0), Vector3(s * 15.0, 0.6, 3.0), "SideFence", {"solid": true, "kind": "wall"})
	# the shelter: roof, posts, glass back, a bench, the sign
	var shelter := _prop("Shelter")
	_c(shelter, Vector3(5.0, 0.15, 2.4), Vector3(0, 2.4, 3.6), "ShelterRoof", {"kind": "metal", "tint": Color(0.6, 0.62, 0.7)})
	for x in [-2.3, 2.3]:
		for z in [2.5, 4.7]:
			_c(shelter, Vector3(0.12, 2.4, 0.12), Vector3(x, 1.2, z), "ShelterPost", {"kind": "metal", "solid": true})
	_c(shelter, Vector3(4.6, 1.6, 0.06), Vector3(0, 1.35, 4.8), "ShelterGlass", {"kind": "glass", "tint": Color(0.5, 0.6, 0.65)})
	_c(shelter, Vector3(2.0, 0.45, 0.5), Vector3(0.6, 0.25, 4.3), "Bench", {"solid": true})
	_c(shelter, Vector3(0.1, 2.6, 0.1), Vector3(3.2, 1.3, 1.6), "SignPost", {"kind": "metal", "solid": true})
	_c(shelter, Vector3(0.9, 0.5, 0.06), Vector3(3.2, 2.7, 1.6), "SignPlate", {"tint": Color(0.3, 0.6, 0.9)})
	# the heat lamp: a post with a hood and a glowing element
	var lamp := _prop("HeatLamp")
	_c(lamp, Vector3(0.14, 1.7, 0.14), Vector3(-1.5, 0.85, 3.0), "LampPost", {"kind": "metal", "solid": true})
	_c(lamp, Vector3(0.6, 0.12, 0.6), Vector3(-1.5, 1.75, 3.0), "LampHood", {"kind": "metal"})
	fire_glow = _c(lamp, Vector3(0.4, 0.08, 0.4), Vector3(-1.5, 1.66, 3.0), "LampGlow", {})
	light = _point_light("LampLight", Vector3(-1.5, 1.5, 3.0), Color(1.0, 0.6, 0.3), 0.0, 8.0)
	_point_light("StreetLight", Vector3(-6.0, 3.4, -0.6), Color(0.7, 0.8, 1.0), 1.2, 12.0)
	_c(lamp, Vector3(0.12, 3.4, 0.12), Vector3(-6.0, 1.7, -0.6), "StreetPost", {"kind": "metal", "solid": true})
	# three places a canister turns up
	var spots := [Vector3(-4.2, 0.0, 1.2), Vector3(4.6, 0.0, 2.6), Vector3(-0.6, 0.0, 5.6)]
	for i in 3:
		var can := Node3D.new()
		can.name = "Canister%d" % i
		can.position = spots[i]
		_c(can, Vector3(0.3, 0.5, 0.3), Vector3(0, 0.25, 0), "FuelCanister", {"kind": "metal", "tint": Color(0.9, 0.35, 0.25)})
		_c(can, Vector3(0.12, 0.1, 0.12), Vector3(0, 0.55, 0), "FuelCap", {"kind": "metal"})
		add_child(can)
		can_nodes[i] = can
		_station("can%d" % i, "PICK UP THE CANISTER", spots[i] + Vector3(0, 0.45, 0))
		can.visible = false
		(stations["can%d" % i] as NightWatchStation).disabled = true
	_station("lamp", "HEAT LAMP  Y", Vector3(-1.5, 1.2, 3.0))
	# the bus, off the end of the road until dawn
	bus = Node3D.new()
	bus.name = "Bus"
	_c(bus, Vector3(6.0, 2.2, 2.2), Vector3(0, 1.4, 0), "BusBody", {"kind": "metal", "tint": Color(0.9, 0.75, 0.3)})
	_c(bus, Vector3(5.6, 0.7, 2.3), Vector3(0, 1.8, 0), "BusWindow", {"kind": "glass", "tint": Color(0.5, 0.6, 0.7)})
	_c(bus, Vector3(0.1, 0.3, 0.5), Vector3(3.05, 0.8, 0.6), "BusHeadGlow", {})
	for x in [-1.9, 1.9]:
		_c(bus, Vector3(0.9, 0.9, 2.5), Vector3(x, 0.45, 0), "BusWheel", {"kind": "metal", "tint": Color(0.2, 0.2, 0.22)})
	bus.position = Vector3(-40.0, 0.0, -4.4)
	add_child(bus)
	# the road Wynelle walks: W0 far down it to W4 at the shelter
	for i in 5:
		paths.add("W%d" % i, Vector3(lerpf(-24.0, -3.2, float(i) / 4.0), 0, lerpf(-4.6, -1.3, float(i) / 4.0)))
	paths.chain(["W0", "W1", "W2", "W3", "W4"])
	weather_fx = _make_weather(Vector3(0, 8, 0), Vector3(14, 0.1, 10), Color(0.95, 0.97, 1.0), 60.0, Vector3(0.0, -1.0, 0.0), 1.2)


# --- the campfire ----------------------------------------------------------------------------------------------------------------

func _build_campfire() -> void:
	spawn = Vector3(1.4, 0.0, 2.6)
	var ground := _prop("Clearing")
	_c(ground, Vector3(34.0, 0.3, 34.0), Vector3(0, -0.15, -2.0), "Floor", {"solid": true, "kind": "floor", "tint": Color(0.55, 0.62, 0.5)})
	for i in 10:
		var a := TAU * float(i) / 10.0
		_c(ground, Vector3(0.4, 0.28, 0.5), Vector3(cos(a) * 0.95, 0.12, sin(a) * 0.95), "FireStone", {"kind": "concrete", "solid": true, "tint": Color(0.7, 0.7, 0.75)})
	fire_glow = _c(ground, Vector3(0.8, 0.5, 0.8), Vector3(0, 0.3, 0), "FireGlow", {})
	_c(ground, Vector3(1.0, 0.15, 0.2), Vector3(0, 0.1, 0), "Kindling", {"kind": "wood", "tint": Color(0.6, 0.5, 0.4)})
	light = _point_light("FireLight", Vector3(0, 1.0, 0), Color(1.0, 0.62, 0.3), 2.6, 12.0)
	# the trees, a ring of trunks with square crowns (a fixed pattern, so every run looks the same)
	var trees := _prop("Trees")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4141
	for i in 46:
		var a := TAU * float(i) / 46.0 + rng.randf_range(-0.06, 0.06)
		var r := rng.randf_range(11.5, 15.5)
		var h := rng.randf_range(4.0, 6.5)
		var p := Vector3(cos(a) * r, 0, sin(a) * r - 2.0)
		_c(trees, Vector3(0.5, h, 0.5), p + Vector3(0, h * 0.5, 0), "TreeTrunk", {"kind": "wood", "solid": true, "tint": Color(0.5, 0.42, 0.34)})
		_c(trees, Vector3(2.6, 1.8, 2.6), p + Vector3(0, h + 0.2, 0), "TreeCrown", {"kind": "fabric", "tint": Color(0.3, 0.5, 0.35)})
	# the log pile (it shrinks as the logs go on the fire), firewood at the edge of the trees
	pile = Node3D.new()
	pile.name = "LogPile"
	pile.position = Vector3(3.4, 0.0, -2.6)
	add_child(pile)
	for i in 10:
		_c(pile, Vector3(0.9, 0.22, 0.22), Vector3(float(i % 2) * 0.08, 0.12 + 0.22 * float(i / 2), (float(i % 5) - 2.0) * 0.16), "PileLog", {"kind": "wood"})
	var wood := _prop("Firewood")
	_c(wood, Vector3(2.4, 1.0, 0.9), Vector3(0, 0.5, 6.2), "WoodStack", {"kind": "wood", "solid": true})
	_c(wood, Vector3(0.12, 1.4, 0.12), Vector3(-1.4, 0.7, 6.2), "WoodPost", {"kind": "metal", "solid": true})
	_station("wood", "FETCH WOOD (HOLD)  F", Vector3(0, 1.2, 5.4))
	_station("fire", "THROW A LOG ON THE FIRE  Y", Vector3(0, 0.9, 0), Vector3(0, 0.0, 0))
	for s in [-1.0, 1.0]:
		var t := "L" if s < 0.0 else "R"
		var kit := _prop("TorchPost" + t)
		_c(kit, Vector3(0.12, 1.6, 0.12), Vector3(s * 3.9, 0.8, 0.5), "TorchStand", {"kind": "metal", "solid": true})
		_c(kit, Vector3(0.22, 0.22, 0.22), Vector3(s * 3.9, 1.7, 0.5), "TorchGlow", {})
		_station("torch" + t, "TORCH %s (HOLD)  %s" % ["LEFT" if s < 0.0 else "RIGHT", "G" if s < 0.0 else "H"], Vector3(s * 3.9, 1.3, 0.5))
	# the tent: a small blocky tent on the right, open towards the fire
	var tent := _prop("Tent")
	_c(tent, Vector3(2.6, 0.08, 2.6), Vector3(6.0, 0.04, 2.0), "TentFloor", {"kind": "fabric", "tint": Color(0.5, 0.45, 0.4)})
	_c(tent, Vector3(0.08, 1.6, 2.6), Vector3(7.3, 0.8, 2.0), "TentWallBack", {"kind": "fabric", "solid": true, "tint": Color(0.8, 0.55, 0.3)})
	for z in [0.7, 3.3]:
		_c(tent, Vector3(2.6, 1.6, 0.08), Vector3(6.0, 0.8, z), "TentWallSide", {"kind": "fabric", "solid": true, "tint": Color(0.8, 0.55, 0.3)})
	_c(tent, Vector3(2.8, 0.08, 3.0), Vector3(6.0, 1.7, 2.0), "TentRoof", {"kind": "fabric", "tint": Color(0.85, 0.6, 0.35)})
	_c(tent, Vector3(2.8, 0.08, 0.08), Vector3(6.0, 1.9, 2.0), "TentRidge", {"kind": "metal"})
	tent_zone = Rect2(4.7, 0.8, 2.5, 2.4)
	tent_in = Vector3(6.2, 0.0, 2.0)
	tent_out = Vector3(3.9, 0.0, 2.0)
	_station("tent", "ENTER THE TENT  T", Vector3(4.8, 1.0, 2.0))
	# hunter waypoints: Verrine V3..V0 (left trees to the edge of the light), Quenelle Q3..Q0 (right), Ysolde Y2..Y0 (the trees, out of them, the log pile)
	paths.add("V3", Vector3(-12.5, 0, -7.0))
	paths.add("V2", Vector3(-10.0, 0, -4.6))
	paths.add("V1", Vector3(-7.4, 0, -2.4))
	paths.add("V0", Vector3(-5.2, 0, -0.8))
	paths.chain(["V3", "V2", "V1", "V0"])
	paths.add("Q3", Vector3(12.5, 0, -7.0))
	paths.add("Q2", Vector3(10.0, 0, -4.6))
	paths.add("Q1", Vector3(7.4, 0, -2.4))
	paths.add("Q0", Vector3(5.2, 0, -0.8))
	paths.chain(["Q3", "Q2", "Q1", "Q0"])
	paths.add("Y2", Vector3(5.0, 0, -11.0))
	paths.add("Y1", Vector3(4.6, 0, -6.8))
	paths.add("Y0", Vector3(2.6, 0, -2.4))
	paths.chain(["Y2", "Y1", "Y0"])
	weather_fx = _make_weather(Vector3(0, 8, -2), Vector3(14, 0.1, 14), Color(0.6, 0.7, 0.95), 140.0, Vector3(0.0, -1.0, 0.0), 0.7)


func _make_weather(pos: Vector3, extents: Vector3, color: Color, amount: float, dir: Vector3, life: float) -> CPUParticles3D:
	var fx := CPUParticles3D.new()
	fx.name = "Weather"
	fx.position = pos
	fx.amount = int(amount) * 4
	fx.lifetime = 7.0 * life
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fx.emission_box_extents = extents
	fx.direction = dir
	fx.spread = 5.0
	fx.initial_velocity_min = 1.2 if life > 1.0 else 7.0
	fx.initial_velocity_max = 2.0 if life > 1.0 else 9.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 0.06) if life > 1.0 else Vector3(0.02, 0.35, 0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	fx.mesh = mesh
	fx.emitting = false
	add_child(fx)
	return fx


# --- what the game shows -----------------------------------------------------------------------------------------------------

## The rooftop's barriers slide down to bar (1 = shut) and up to open; call every frame, or with `snap` to jump.
func animate(bars: Dictionary, delta: float, snap := false) -> void:
	for tag in slabs:
		var target := 1.0 if bool(bars.get(tag, false)) else 0.0
		bar_progress[tag] = target if snap else move_toward(float(bar_progress[tag]), target, delta * 4.0)
		(slabs[tag] as Node3D).position.y = lerpf(SLAB_OPEN_Y, SLAB_CLOSED_Y, float(bar_progress[tag]))
	if fire_glow != null and watch == 2:
		_fire_flicker += delta * 9.0


func set_light_energy(energy: float) -> void:
	if light != null:
		light.light_energy = energy


## The campfire's flames and glow follow the fire (0..100).
func set_fire(fire_percent: float) -> void:
	var t := clampf(fire_percent / 100.0, 0.0, 1.0)
	light.light_energy = 0.1 + 2.6 * t
	fire_glow.scale = Vector3(0.4 + 0.6 * t, 0.15 + 0.85 * t, 0.4 + 0.6 * t)
	fire_glow.visible = t > 0.01


func set_pile(logs: int) -> void:
	for i in pile.get_child_count():
		(pile.get_child(i) as Node3D).visible = i < mini(logs, 10)


func set_cans(present: Array) -> void:
	for i in can_nodes:
		var here := present.has(i)
		(can_nodes[i] as Node3D).visible = here
		(stations["can%d" % i] as NightWatchStation).disabled = not here


func set_weather(on: bool) -> void:
	if weather_fx != null:
		weather_fx.emitting = on


## 0 to 1: the bus comes up the road to the stop.
func set_bus(progress: float) -> void:
	if bus != null:
		bus.position.x = lerpf(-40.0, -3.5, clampf(progress, 0.0, 1.0))


## The torch spot: held on `side` ("L" / "R", "" for none) from the player at `origin`.
func set_torch(side: String, origin: Vector3) -> void:
	if side == "":
		torch_spot.light_energy = 0.0
		return
	torch_spot.light_energy = 4.0
	torch_spot.global_position = origin + Vector3(0, 1.4, 0)
	torch_spot.look_at(origin + Vector3((-1.0 if side == "L" else 1.0) * 6.0, 0.6, -1.0))


## The hunter's stand-point for a key (world coordinates).
func point(key: String) -> Vector3:
	return paths.points[key]


func in_tent(pos: Vector3) -> bool:
	return watch == 2 and tent_zone.has_point(Vector2(pos.x, pos.z))
