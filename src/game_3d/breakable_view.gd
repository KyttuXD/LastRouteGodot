class_name BreakableView
extends RefCounted

## What a breakable (Breach spec) looks like, built from boxes: a seal across a tunnel (chained gate, cracked furnace wall,
## locked furnace door, boarded doorway, vent grate), a loose board barricade, a pipe. build() returns the visual root, its
## pieces (hidden from the last to the first as hit points fall, so a hit visibly breaks something) and a solid body to
## stand in the way until the thing opens.
## Local frame: x runs across the gate (its width), -z is the way the tunnel runs, y is up; the interactable is placed at
## the gate's centre and turned to the tunnel's direction.

const HEIGHT := 3.0
const THICKNESS := .5

static var _materials := {}


## The width a gate spans: its cells projected across the tunnel direction.
static func gate_width(spec: Dictionary) -> float:
	var extras: Dictionary = spec.get("extras", {})
	var dir: Vector2 = extras.get("dir", Vector2(0, 1))
	var perp := Vector2(-dir.y, dir.x)
	var lo := 1.0e9
	var hi := -1.0e9
	for cell_value in extras.get("cells", []):
		var cell: Vector2i = cell_value
		var v := Vector2(cell.x + .5, cell.y + .5) - (extras.get("centre", Vector2.ZERO) as Vector2)
		lo = minf(lo, v.dot(perp))
		hi = maxf(hi, v.dot(perp))
	return maxf(2.0, hi - lo + 1.0)


static func yaw_of(spec: Dictionary) -> float:
	var dir: Vector2 = (spec.get("extras", {}) as Dictionary).get("dir", Vector2(0, 1))
	return atan2(-dir.x, -dir.y)


static func build(spec: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "BreakableVisual"
	var width := gate_width(spec) if (spec.get("extras", {}) as Dictionary).has("cells") else float((spec.get("extras", {}) as Dictionary).get("width", 2.0))
	var pieces: Array = []
	match String(spec.get("variant", "")):
		"chainedGate":
			_chained_gate(root, pieces, width)
		"crackedFurnaceWall":
			_cracked_wall(root, pieces, width)
		"lockedFurnaceDoor":
			_furnace_door(root, pieces, width)
		"pipe":
			_pipe(root, pieces, width)
		_:
			_boards(root, pieces, width)
	var body := StaticBody3D.new()
	body.name = "BreakableBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, HEIGHT, THICKNESS)
	shape.shape = box
	shape.position = Vector3(0, HEIGHT * .5, 0)
	body.add_child(shape)
	root.add_child(body)
	return {"root": root, "pieces": pieces, "body": body, "width": width}


static func _mat(key: String, color: Color, emission: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	if emission != Color(0, 0, 0):
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.6
	_materials[key] = material
	return material


static func _box(parent: Node3D, pieces: Array, size: Vector3, at: Vector3, material: Material, piece: bool = true, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.rotation = rot
	parent.add_child(node)
	if piece:
		pieces.append(node)
	return node


## Vertical iron bars with two rails and a chain looped through them, a heavy lock in the middle.
static func _chained_gate(root: Node3D, pieces: Array, width: float) -> void:
	var iron := _mat("gate_iron", Color(.14, .12, .12))
	var rust := _mat("gate_rust", Color(.32, .17, .1))
	_box(root, pieces, Vector3(width, .12, .16), Vector3(0, HEIGHT - .3, 0), iron, false)
	_box(root, pieces, Vector3(width, .12, .16), Vector3(0, .35, 0), iron, false)
	var count := maxi(4, int(width / .42))
	for i in count:
		var x := -width * .5 + (i + .5) * width / count
		_box(root, pieces, Vector3(.07, HEIGHT - .5, .07), Vector3(x, HEIGHT * .5, 0), iron)
	# two chains slung across, and the lock
	for k in 2:
		var y := 1.1 + k * .8
		for i in count:
			var x := -width * .5 + (i + .5) * width / count
			_box(root, pieces, Vector3(width / count * .9, .05, .1), Vector3(x, y - (.08 if i % 2 == 0 else 0.0), .08), rust)
	_box(root, pieces, Vector3(.32, .4, .2), Vector3(0, 1.5, .12), _mat("gate_lock", Color(.5, .38, .16)))


## A slab of basalt blocks with ember light in the cracks between them.
static func _cracked_wall(root: Node3D, pieces: Array, width: float) -> void:
	var rock := _mat("wall_rock", Color(.2, .16, .17))
	var dark := _mat("wall_rock_dark", Color(.12, .09, .1))
	var glow := _mat("wall_glow", Color(.9, .3, .08), Color(1.0, .35, .06))
	var rows := 5
	var cols := maxi(3, int(width / .9))
	for r in rows:
		for c in cols:
			var size := Vector3(width / cols - .04, HEIGHT / rows - .04, THICKNESS * (.8 + .2 * float((r + c) % 2)))
			var x := -width * .5 + (c + .5) * width / cols
			var y := (r + .5) * HEIGHT / rows
			_box(root, pieces, size, Vector3(x, y, 0), rock if (r + c) % 2 == 0 else dark)
	# glowing seams
	for i in 6:
		var x := -width * .5 + (i + .7) * width / 6.5
		_box(root, pieces, Vector3(.05, HEIGHT * .55, .04), Vector3(x, 1.0 + (i % 3) * .5, THICKNESS * .5 + .01), glow, true, Vector3(0, 0, .3 * (1 if i % 2 == 0 else -1)))


## Two iron leaves with a big lock bar across them.
static func _furnace_door(root: Node3D, pieces: Array, width: float) -> void:
	var iron := _mat("door_iron", Color(.16, .14, .14))
	var plate := _mat("door_plate", Color(.24, .2, .18))
	var glow := _mat("door_glow", Color(.9, .3, .08), Color(1.0, .35, .06))
	for side in [-1.0, 1.0]:
		_box(root, pieces, Vector3(width * .5 - .03, HEIGHT - .1, .22), Vector3(side * width * .25, HEIGHT * .5, 0), plate)
		for k in 3:
			_box(root, pieces, Vector3(width * .5 - .15, .1, .26), Vector3(side * width * .25, .6 + k * .9, 0), iron, false)
	_box(root, pieces, Vector3(width * .8, .18, .3), Vector3(0, 1.4, .2), iron)
	_box(root, pieces, Vector3(.3, .5, .34), Vector3(0, 1.4, .3), _mat("door_lock", Color(.55, .4, .15)))
	_box(root, pieces, Vector3(width * .8, .03, .02), Vector3(0, 2.4, .12), glow, false)


## A pipe lying across the gate, with a dent and rust.
static func _pipe(root: Node3D, pieces: Array, width: float) -> void:
	var pipe := _mat("pipe", Color(.3, .26, .22))
	var rust := _mat("pipe_rust", Color(.4, .2, .1))
	var count := 3
	for i in count:
		var x := -width * .5 + (i + .5) * width / count
		_box(root, pieces, Vector3(width / count - .04, .34, .34), Vector3(x, 1.0, 0), pipe if i % 2 == 0 else rust)
	_box(root, pieces, Vector3(.2, .46, .46), Vector3(0, 1.0, 0), _mat("pipe_flange", Color(.18, .16, .14)), false)


## Boards nailed across the opening.
static func _boards(root: Node3D, pieces: Array, width: float) -> void:
	var wood := _mat("boards", Color(.45, .31, .18))
	var count := 6
	for i in count:
		var y := .3 + i * (HEIGHT - .6) / (count - 1)
		_box(root, pieces, Vector3(width * .96, .22, .08), Vector3(0, y, .0), wood, true, Vector3(0, 0, .04 * (1 if i % 2 == 0 else -1)))
