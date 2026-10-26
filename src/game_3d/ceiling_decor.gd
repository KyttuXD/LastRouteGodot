class_name CeilingDecor
extends Node3D

## Strings of fairy lights hung across the maze's ceiling.
##
## Placement is sparse and seeded, not authored: the facility is procedural,
## so there is no fixed spot to hand-place a light in. A handful of open
## floor cells along the generated corridors are picked per floor (same seed,
## same lights, like everything else about a floor), and each gets a short
## strand -- a thin wire and a few small coloured bulbs hanging just under the
## ceiling slab.
##
## Each bulb dims and brightens on its own slow, slightly irregular cycle
## rather than a shared clock, which is what actually reads as "fairy
## lights" instead of a set of lights all fading in lockstep.

const BULB_COLORS := [
	Color(0.95, 0.35, 0.45), Color(0.35, 0.75, 0.95), Color(0.95, 0.80, 0.30),
	Color(0.45, 0.90, 0.55), Color(0.80, 0.45, 0.95),
]
const BULB_RADIUS := 0.05
const BULB_ENERGY := 0.35
const BULB_RANGE := 1.8
## Cycle length varies per bulb within this band, in seconds -- shared exactly
## would read as one light blinking through a mirror, not a string of them.
const FLICKER_PERIOD_MIN := 2.2
const FLICKER_PERIOD_MAX := 4.5
## Never fully dark: a light that hits zero looks broken, not dim.
const FLICKER_FLOOR := 0.15

var _bulbs: Array[OmniLight3D] = []
var _phases: Array[float] = []
var _periods: Array[float] = []


## `anchors`: world-space points along the ceiling to hang a strand from, each
## already offset down from the ceiling slab. `rng`: the floor's own seeded
## generator, so bulb colours/timing are stable for a given seed like
## everything else about the floor, not re-rolled every load.
func build(anchors: Array, rng: SeededRandom) -> void:
	for i in anchors.size():
		var at: Vector3 = anchors[i]
		var bulb_count := 3 + rng.next_index(3)
		_add_strand(at, bulb_count, rng)


func _add_strand(anchor: Vector3, bulb_count: int, rng: SeededRandom) -> void:
	var strand := Node3D.new()
	strand.position = anchor
	add_child(strand)

	var span := 0.7 + rng.next_float() * 0.5
	var sag := 0.12 + rng.next_float() * 0.10
	var start := Vector3(-span * 0.5, 0.0, 0.0)
	var end := Vector3(span * 0.5, 0.0, 0.0)

	var wire := MeshInstance3D.new()
	var wire_mesh := BoxMesh.new()
	wire_mesh.size = Vector3(span, 0.01, 0.01)
	wire.mesh = wire_mesh
	wire.position = Vector3(0.0, -sag * 0.4, 0.0)
	var wire_material := StandardMaterial3D.new()
	wire_material.albedo_color = Color(0.05, 0.05, 0.06)
	wire_material.roughness = 0.9
	wire.material_override = wire_material
	strand.add_child(wire)

	for i in bulb_count:
		var t := (float(i) + 0.5) / float(bulb_count)
		var along: Vector3 = start.lerp(end, t)
		# A shallow parabola, not a straight line -- a string of lights hangs
		# with real sag, heaviest at the middle.
		var drop := sag * (1.0 - pow(2.0 * t - 1.0, 2.0))
		var color: Color = BULB_COLORS[rng.next_index(BULB_COLORS.size())]

		var bulb_mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = BULB_RADIUS
		sphere.height = BULB_RADIUS * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		bulb_mesh.mesh = sphere
		bulb_mesh.position = along + Vector3(0.0, -drop, 0.0)
		var bulb_material := StandardMaterial3D.new()
		bulb_material.albedo_color = color
		bulb_material.emission_enabled = true
		bulb_material.emission = color
		bulb_material.emission_energy_multiplier = 1.5
		bulb_mesh.material_override = bulb_material
		strand.add_child(bulb_mesh)

		var light := OmniLight3D.new()
		light.position = bulb_mesh.position
		light.light_color = color
		light.omni_range = BULB_RANGE
		light.light_energy = BULB_ENERGY
		light.shadow_enabled = false
		strand.add_child(light)
		LampField.make_budgeted(light)

		_bulbs.append(light)
		_phases.append(rng.next_float() * TAU)
		_periods.append(lerpf(FLICKER_PERIOD_MIN, FLICKER_PERIOD_MAX, rng.next_float()))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in _bulbs.size():
		var wave := 0.5 + 0.5 * sin(now * TAU / _periods[i] + _phases[i])
		_bulbs[i].light_energy = BULB_ENERGY * lerpf(FLICKER_FLOOR, 1.0, wave)
