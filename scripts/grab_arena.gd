extends RefCounted

## Test spaces for hunter grabs (the grabs suite and tools/look/grabs.tscn), built high above the route so nothing else is near:
## "open" is a big room (4.2 m ceiling, walls 9 m away); "hallway" is a 2 m wide corridor with a 3 m ceiling and a wall 1.15 m
## behind the runner. Returns {"root", "stand" (the runner's feet), "facing" (runner to hunter)}.

const BASE := Vector3(400.0, 60.0, 400.0)


static func _box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	cube.material = material
	mesh.mesh = cube
	body.add_child(mesh)
	root.add_child(body)
	body.global_position = at


static func build(parent: Node, kind: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "GrabArena_%s" % kind
	parent.add_child(root)
	var floor_color := Color(.32, .3, .3)
	var wall_color := Color(.42, .38, .36)
	_box(root, Vector3(24.0, 1.0, 24.0), BASE + Vector3(0.0, -.5, 0.0), floor_color)
	var stand := BASE
	if kind == "hallway":
		var height := 3.0
		_box(root, Vector3(.4, height, 12.0), BASE + Vector3(-1.2, height * .5, -3.0), wall_color)
		_box(root, Vector3(.4, height, 12.0), BASE + Vector3(1.2, height * .5, -3.0), wall_color)
		_box(root, Vector3(2.8, .4, 12.0), BASE + Vector3(0.0, height + .2, -3.0), wall_color)
		_box(root, Vector3(2.8, height, .4), BASE + Vector3(0.0, height * .5, 1.35), wall_color)
	else:
		var height := 4.2
		for side in [-1.0, 1.0]:
			_box(root, Vector3(.4, height, 20.0), BASE + Vector3(9.0 * side, height * .5, 0.0), wall_color)
			_box(root, Vector3(20.0, height, .4), BASE + Vector3(0.0, height * .5, 9.0 * side), wall_color)
		_box(root, Vector3(20.0, .4, 20.0), BASE + Vector3(0.0, height + .2, 0.0), wall_color)
	for at in [Vector3(0.0, 2.6, -1.0), Vector3(0.0, 2.6, 1.0)]:
		var light := OmniLight3D.new()
		light.light_energy = 1.6
		light.omni_range = 7.0
		root.add_child(light)
		light.global_position = BASE + at
	return {"root": root, "stand": stand, "facing": Vector3.FORWARD}
