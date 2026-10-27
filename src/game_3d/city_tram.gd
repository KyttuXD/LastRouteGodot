class_name CityTram
extends Node3D

## Ambient traffic on rails: an elevated tram line over the avenue and one over the main street, each with two cars that
## glide end to end above head height (rail at 6 m, cars 6.3 m to 8.5 m, well above lamps, canopies and doorway signs).
## Visual only: no collision, no nav change, deterministic from the run clock so every peer sees the same cars.
## Coordinates are route space; the layout's origin_offset maps city cells to it.

const RAIL_Y := 6.0
const CAR_SIZE := Vector3(1.8, 2.2, 5.0)
const SPEED := 6.5
const CARS_PER_LINE := 2

var _cars: Array[Node3D] = []
var _lines: Array = []   # {axis: "x"|"z", at: float, from: float, to: float}
var _clock := 0.0
## The layout whose streets the trams run over (set before the node enters the tree).
var layout: CityLayout


func _ready() -> void:
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.16, 0.22, 0.30)

	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.9, 0.7, 0.35)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.72, 0.3)
	glow.emission_energy_multiplier = 1.6

	var rail := StandardMaterial3D.new()
	rail.albedo_color = Color(0.08, 0.09, 0.12)
	for material in [body, glow, rail]:
		MaterialLook.tame(material)
	var centre := Vector2(CityLayout.ROUNDABOUT_CENTER) + Vector2(.5, .5) - Vector2(layout.origin_offset)
	# Rails run where the street is inside the rim; the roundabout kiosk is 4.5 m tall so the rail clears it.
	_lines = [
		{"axis": "z", "at": centre.x, "from": _street_end(true, centre.x, -1), "to": _street_end(true, centre.x, 1)},
		{"axis": "x", "at": centre.y, "from": _street_end(false, centre.y, -1), "to": _street_end(false, centre.y, 1)},
	]
	for line_value in _lines:
		var line: Dictionary = line_value
		var length := float(line["to"]) - float(line["from"])
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(.3, .25, length) if line["axis"] == "z" else Vector3(length, .25, .3)
		beam.mesh = beam_mesh
		beam.material_override = rail
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var middle := (float(line["from"]) + float(line["to"])) * .5
		beam.position = Vector3(float(line["at"]), RAIL_Y, middle) if line["axis"] == "z" else Vector3(middle, RAIL_Y, float(line["at"]))
		add_child(beam)
		for index in CARS_PER_LINE:
			var car := Node3D.new()
			car.name = "Tram_%s_%d" % [line["axis"], index]
			car.set_meta("line", line)
			car.set_meta("phase", float(index) / float(CARS_PER_LINE))
			var shell := MeshInstance3D.new()
			var shell_mesh := BoxMesh.new()
			shell_mesh.size = CAR_SIZE if line["axis"] == "z" else Vector3(CAR_SIZE.z, CAR_SIZE.y, CAR_SIZE.x)
			shell.mesh = shell_mesh
			shell.material_override = body
			shell.position = Vector3(0, RAIL_Y + .3 + CAR_SIZE.y * .5, 0)
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			car.add_child(shell)
			var windows := MeshInstance3D.new()
			var window_mesh := BoxMesh.new()
			window_mesh.size = shell_mesh.size * Vector3(1.04, .35, .8) if line["axis"] == "z" else shell_mesh.size * Vector3(.8, .35, 1.04)
			windows.mesh = window_mesh
			windows.material_override = glow
			windows.position = shell.position + Vector3(0, .35, 0)
			windows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			car.add_child(windows)
			add_child(car)
			_cars.append(car)
	_place(0.0)


## Where the street leaves the city ellipse in the given direction (route space), kept 6 m short of the rim.
func _street_end(along_z: bool, at: float, direction: int) -> float:
	var position := 0.0
	for step in 140:
		var candidate := float(direction * step)
		var gx := (at if along_z else candidate) + layout.origin_offset.x
		var gz := (candidate if along_z else at) + layout.origin_offset.y
		if CityLayout.ellipse_r(int(gx), int(gz)) >= CityLayout.RING_PAVE_FROM:
			break
		position = candidate
	return position - float(direction) * 12.0


func car_count() -> int:
	return _cars.size()


func _process(delta: float) -> void:
	_clock += delta
	_place(_clock)


func _place(time: float) -> void:
	for car in _cars:
		var line: Dictionary = car.get_meta("line")
		var span := float(line["to"]) - float(line["from"])
		var cycle := span * 2.0 / SPEED
		var t := fmod(time / cycle + float(car.get_meta("phase")), 1.0)
		# Out and back: 0..0.5 forward, 0.5..1 back, with a short pause at each end.
		var along := 0.0
		if t < .5:
			along = smoothstep(.02, .48, t) * span
		else:
			along = (1.0 - smoothstep(.52, .98, t)) * span
		var position := float(line["from"]) + along
		car.position = Vector3(float(line["at"]), 0, position) if line["axis"] == "z" else Vector3(position, 0, float(line["at"]))
