extends Node

## Bakes one dossier portrait per hunter: the in-game blocky model, head and shoulders, 3/4 view, one fixed light rig,
## transparent background (the dossier tints the tile and draws locked ones as a silhouette). Run at build time, never per frame:
##   godot --path . res://tools/look/hunter_portraits.tscn -- [res://assets/ui/hunter_portraits_3d] [id,id,...]
## The files are <id>.png; HunterDossier.portrait_path() finds them, so a new hunter only needs a re-bake.

const SIZE := 192
const YAW := 32.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "res://assets/ui/hunter_portraits_3d"
	var ids: Array = []
	if args.size() > 1:
		ids = Array(args[1].split(","))
	else:
		for id in HunterRoster.PROFILES:
			ids.append(String(id))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.56, 0.62)
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -40, 0)
	key.light_energy = 1.0
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 0.45
	viewport.add_child(rim)
	var floor_body := StaticBody3D.new()   # HunterView3D is a CharacterBody3D with gravity
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 0.2, 20)
	floor_shape.shape = floor_box
	floor_body.collision_layer = 1
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	viewport.add_child(floor_body)
	var cam := Camera3D.new()
	cam.fov = 30.0
	viewport.add_child(cam)
	cam.current = true
	var written := 0
	for id in ids:
		var brain := HunterBrain.new(Vector2.ZERO, "PORTRAIT", String(id), "standard")
		brain.activate_at(Vector2.ZERO)
		var view := HunterView3D.new()
		view.brain = brain
		viewport.add_child(view)
		view.sync_from_brain()
		for i in 12:
			await get_tree().process_frame
		var head := view.find_child("Head", true, false) as Node3D
		var focus := head.global_position if head != null else Vector3(0, 1.9, 0)
		focus.x = view.global_position.x
		focus.z = view.global_position.z
		focus.y -= 0.22
		var dist := 3.4 * HunterRoster.scale_for(String(id)) / HunterRoster.MODEL_SCALE
		var dir := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(YAW))
		cam.position = focus + dir * dist + Vector3(0, 0.12, 0)
		cam.look_at(focus)
		for i in 4:
			await get_tree().process_frame
		var image := viewport.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, id]
		if image.save_png(ProjectSettings.globalize_path(path)) == OK:
			written += 1
		else:
			push_error("could not write %s" % path)
		view.queue_free()
		await get_tree().process_frame
	print("PORTRAITS %d of %d written to %s" % [written, ids.size(), out_dir])
	get_tree().quit(0 if written == ids.size() else 1)
