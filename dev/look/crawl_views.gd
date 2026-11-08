extends Node

## Side and front views of Verrine's vent crawl (and the drop into it): a filmstrip of the loop, a vent-height line at 0.8 m.
##   godot --path . res://dev/look/crawl_views.tscn -- OUT_PREFIX     (writes OUT_PREFIX_side.png and OUT_PREFIX_front.png)

const FRAMES := 6
const TILE_W := 420
const TILE_H := 300
var _sub: SubViewport
var _model: Node3D
var _player: AnimationPlayer


func _ready() -> void:
	var prefix := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://crawl"
	var id := OS.get_environment("HUNTER") if OS.get_environment("HUNTER") != "" else "verrine"
	_sub = SubViewport.new()
	_sub.size = Vector2i(TILE_W, TILE_H)
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.16, .15, .19)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.85, .82, .86)
	_sub.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	_sub.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40, .05, 6)
	floor_mesh.mesh = box
	floor_mesh.position.y = -.025
	_sub.add_child(floor_mesh)
	var vent := MeshInstance3D.new()      # the 0.8 m ceiling of the shaft, a thin red bar the whole way across
	var bar := BoxMesh.new()
	bar.size = Vector3(40, .02, .02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, .2, .2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material = mat
	vent.mesh = bar
	vent.position = Vector3(0, .8, -.5)
	_sub.add_child(vent)
	_model = (load("res://assets/hunters_blocky/%s/%s.glb" % [id, id]) as PackedScene).instantiate() as Node3D
	_sub.add_child(_model)
	_player = ModelSlot.find_animation_player(_model)
	NightWatchPoses.install(_model, _player, id)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.5
	_sub.add_child(cam)
	cam.current = true
	for view in ["side", "front"]:
		if view == "side":
			cam.position = Vector3(6, .6, 0)
			cam.rotation_degrees = Vector3(0, 90, 0)
		else:
			cam.position = Vector3(0, .6, -6)
			cam.rotation_degrees = Vector3(0, 180, 0)
		_model.rotation.y = 0.0
		var sheet := Image.create(FRAMES * TILE_W, TILE_H * 2, false, Image.FORMAT_RGB8)
		for row in 2:
			var clip := "vent_drop_verrine" if row == 0 else "vent_crawl_verrine"
			for i in FRAMES:
				_player.play(NightWatchPoses.clip_name(clip))
				var t := _player.get_animation(NightWatchPoses.clip_name(clip)).length * (i + (1 if row == 0 else 0)) / float(FRAMES + (1 if row == 0 else 0))
				_player.seek(t, true)
				_player.pause()
				# keep each frame centred on the model's own hips so the loop reads in place
				await get_tree().process_frame
				await get_tree().process_frame
				await get_tree().process_frame
				var image := _sub.get_texture().get_image()
				image.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(image, Rect2i(0, 0, TILE_W, TILE_H), Vector2i(i * TILE_W, row * TILE_H))
		sheet.save_png("%s_%s.png" % [prefix, view])
		print("saved ", prefix, "_", view)
	get_tree().quit()
