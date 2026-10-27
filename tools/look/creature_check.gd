extends Node

## The secret creature's glb as the game loads it (ModelSlot), every clip at two poses, at 3 m and 8 m, 3/4 and side view.
##   godot --path . res://tools/look/creature_check.tscn -- OUTDIR [ID]
## Prints the node/clip inventory and where the head sits (forward check), then writes OUTDIR/<clip>_<pose>_<dist>m_<view>.png.

const CLIPS := ["idle", "walk", "sprint", "bark", "attack", "death"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 else "user://creature_check"
	var id := String(args[1]) if args.size() > 1 else SecretCreatures.WHITE_WOLF_SPIDER
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.07, .06, .09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.6, .56, .62)
	env.environment.ambient_light_energy = .75
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = .8
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(60, .1, 60)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -.05
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(.22, .2, .24)
	plane.material = floor_material
	world.add_child(floor_mesh)
	var identity := SecretCreatures.identity(id)
	var model := ModelSlot.instantiate(String(identity["model_scene"]))
	world.add_child(model)
	var player := ModelSlot.find_animation_player(model)
	print("CREATURE %s clips=%s" % [id, player.get_animation_list() if player != null else "NO ANIMATION PLAYER"])
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		print("  CLIP %s length=%.2f loop=%s tracks=%d" % [clip, animation.length, animation.loop_mode, animation.get_track_count()])
	var head := model.find_child("head", true, false) as Node3D
	var tail := (model.find_child("abdomen", true, false) if model.find_child("abdomen", true, false) != null else model.find_child("body", true, false)) as Node3D
	if head != null and tail != null:
		print("FORWARD head.z=%.2f abdomen.z=%.2f -> the head is on the %s side (Godot forward is -Z)" % [
			head.global_position.z, tail.global_position.z, "-Z (forward, correct)" if head.global_position.z < tail.global_position.z else "+Z (BACKWARD)"])
	var aabb := _bounds(model)
	print("BOUNDS size=%s position=%s" % [aabb.size, aabb.position])
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 45.0
	for clip in CLIPS:
		if not player.has_animation(clip):
			continue
		for pose in [0, 1]:
			player.play(clip)
			player.seek(player.get_animation(clip).length * (0.0 if pose == 0 else 0.45), true)
			player.pause()
			for dist in [3.0, 8.0]:
				for view in ["front34", "side"]:
					var at := Vector3(0, 1.0, 0)
					cam.position = at + (Vector3(dist * .5, dist * .12, -dist * .85) if view == "front34" else Vector3(dist * .98, dist * .08, 0))
					cam.look_at(at)
					for _i in 3:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png("%s/%s_p%d_%dm_%s.png" % [out, clip, pose, int(dist), view])
	get_tree().quit()


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var b := mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
