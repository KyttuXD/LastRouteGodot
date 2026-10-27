extends Node

## Bed z-fighting probe (windowed: run it on the mini). A bed (default gothicDoubleBed_0 plus the single/double/bunk beds) is lit like a room (a
## shadowed key light and a fill), seen with the game's camera (near 0.06, far 160, gl_compatibility) from two angles at 0.5, 2, 6 and 15 m from
## the mattress. At each distance the camera is shifted by 3 mm twice: z-fighting flips between the layers with the tiniest change, so the
## mean difference of the bed pixels between the shifted frames is the flicker measure (a stable surface differs by ~0).
##   mini-run.sh <dir> props-lane --scene res://tools/look/bed_zfight.tscn -- /tmp/bed_caps/after [model,model,...]

const DISTANCES := [0.5, 2.0, 6.0, 15.0]
const ANGLES := {"foot": Vector3(0.0, 0.0, 1.0), "side": Vector3(1.0, 0.0, 0.25)}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/bed_caps"
	var names: PackedStringArray = (args[1] if args.size() > 1 else "gothicDoubleBed_0,singleBed_0,doubleBed_9,bunkBed_0").split(",")
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(960, 600)
	var world := Node3D.new()
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 3, 0)
	fill.omni_range = 14.0
	fill.light_energy = 1.2
	world.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(60, .1, 60)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -.05
	world.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.near = 0.06
	camera.far = 160.0
	camera.fov = 78.0
	world.add_child(camera)
	camera.current = true
	for model_name in names:
		var model: Node3D = ModelSlot.instantiate_prop("res://art/props-3d/props/blocky/%s.glb" % model_name, model_name)
		if model == null:
			print("missing model %s" % model_name)
			continue
		world.add_child(model)
		var bounds := _bounds(model)
		var target := bounds.get_center() + Vector3(0, bounds.size.y * .25, 0)
		for angle_name in ANGLES:
			for distance in DISTANCES:
				var direction: Vector3 = (ANGLES[angle_name] as Vector3).normalized()
				var base: Vector3 = target + (direction * cos(deg_to_rad(35.0)) + Vector3.UP * sin(deg_to_rad(35.0))) * distance
				var images: Array[Image] = []
				for shift in [Vector3.ZERO, Vector3(.003, 0, 0), Vector3(0, 0, .003)]:
					camera.global_position = base + shift
					camera.look_at(target)
					for _i in 4:
						await get_tree().process_frame
					images.append(get_viewport().get_texture().get_image())
				images[0].save_png("%s/%s_%s_%.1fm.png" % [out, model_name, angle_name, distance])
				print("FLICKER %s %s %.1f m  %.3f" % [model_name, angle_name, distance, _difference(images)])
		model.queue_free()
		await get_tree().process_frame
	print("bed captures written to %s" % out)
	get_tree().quit()


func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			var part := mesh_node.global_transform * mesh_node.get_aabb()
			box = part if first else box.merge(part)
			first = false
	return box


## Mean per-channel difference of the pixels in the middle band of the frame (where the bed is), between the first and each shifted frame.
func _difference(images: Array[Image]) -> float:
	var width := images[0].get_width()
	var height := images[0].get_height()
	var total := 0.0
	var count := 0
	for other in range(1, images.size()):
		for y in range(height / 4, height * 3 / 4, 2):
			for x in range(width / 4, width * 3 / 4, 2):
				var a := images[0].get_pixel(x, y)
				var b := images[other].get_pixel(x, y)
				total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				count += 1
	return total / maxf(1.0, float(count)) * 100.0
