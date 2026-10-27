class_name CityDoor
extends Node3D

## A City building entrance: a two-metre, three-metre-high doorway with a pair of sliding leaves (shopfront glass, steel, wood
## or civic style by building kind). The leaves are never locked: they slide into the wall whenever the runner or a hunter is
## within OPEN_RANGE, and only the leaves carry colliders, so the opening itself is always clear when they are open. The
## leaf colliders sit exactly in the doorway plane; nothing else (wall, prop, furniture) may stand across it.
## Local space: x along the facade, z out to the street, origin at the doorway's bottom centre.

const WIDTH := 2.0
const HEIGHT := 3.0
const OPEN_RANGE := 3.6
const SLIDE_SECONDS := 0.35
const GROUPS := ["city_door_agents", "streamed_hunter"]

var style := "glass"
var _leaves: Array[Node3D] = []
var _bodies: Array[StaticBody3D] = []
var _open := 0.0
var _target_open := 0.0
var _poll := randf() * 0.2


static func style_for(kind: String) -> String:
	match kind:
		"shop", "cafe", "office", "lobby":
			return "glass"
		"workshop":
			return "steel"
		"apartment", "library":
			return "wood"
		_:
			return "civic"


func _ready() -> void:
	var leaf_color := Color(0.16, 0.20, 0.26)
	var glow := Color(0.35, 0.85, 0.85)
	match style:
		"steel":
			leaf_color = Color(0.20, 0.21, 0.24)
			glow = Color(1.0, 0.62, 0.25)
		"wood":
			leaf_color = Color(0.32, 0.20, 0.12)
			glow = Color(1.0, 0.72, 0.38)
		"civic":
			leaf_color = Color(0.26, 0.17, 0.12)
			glow = Color(0.95, 0.8, 0.5)
	for index in 2:
		var leaf := Node3D.new()
		leaf.name = "Leaf%d" % index
		leaf.position = Vector3((-.5 if index == 0 else .5) * WIDTH * .5, 0, 0)
		add_child(leaf)
		_leaves.append(leaf)
		var panel := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(WIDTH * .5 - .04, HEIGHT - .08, .07)
		panel.mesh = mesh
		panel.position = Vector3(0, HEIGHT * .5, 0)
		panel.material_override = _matte(leaf_color, Color(0, 0, 0))
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.add_child(panel)
		var window := MeshInstance3D.new()
		var window_mesh := BoxMesh.new()
		window_mesh.size = Vector3(WIDTH * .5 - .34, HEIGHT - .9, .09)
		window.mesh = window_mesh
		window.position = Vector3(0, HEIGHT * .5 + .2, 0)
		window.material_override = _matte(glow * .35, glow, .9 if style == "glass" else .5)
		window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.add_child(window)
		var body := StaticBody3D.new()
		body.name = "LeafCollider"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WIDTH * .5, HEIGHT, .12)
		shape.shape = box
		shape.position = Vector3(0, HEIGHT * .5, 0)
		body.add_child(shape)
		leaf.add_child(body)
		_bodies.append(body)
	_apply_open()


static func _matte(color: Color, emission: Color, emission_energy: float = 0.7) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.metallic = 0.0
	if emission != Color(0, 0, 0):
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material


func is_open() -> bool:
	return _target_open > .5


## Test and build helper: jump straight to open or closed.
func set_open_instant(value: bool) -> void:
	_target_open = 1.0 if value else 0.0
	_open = _target_open
	_apply_open()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2
		_target_open = 1.0 if _agent_near() else 0.0
	if not is_equal_approx(_open, _target_open):
		_open = move_toward(_open, _target_open, delta / SLIDE_SECONDS)
		_apply_open()


func _agent_near() -> bool:
	var here := global_position
	for group in GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var agent := node as Node3D
			if agent != null and agent.global_position.distance_to(here) < OPEN_RANGE:
				return true
	return false


func _apply_open() -> void:
	for index in _leaves.size():
		var side := -1.0 if index == 0 else 1.0
		_leaves[index].position.x = side * (WIDTH * .25 + _open * WIDTH * .48)
	# Colliders only while the leaves still stand in the doorway.
	for body in _bodies:
		for child in body.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = _open > .6
