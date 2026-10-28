extends Node

## Chase styles (HunterChaseStyle) contact sheet: every hunter mid-chase, running at the camera with the runner straight
## ahead, from the front and from three-quarters, labelled with her style. One hunter at a time on a dark floor.
##   godot --path . res://tools/look/chase_style_sheet.tscn -- OUT.png

const TILE := Vector2i(200, 250)
const COLUMNS := 6
const RUN_SPEED := 3.6

var _out := "user://chase_style_sheet.png"
var _ids: Array = []
var _sub: SubViewport
var _camera: Camera3D
var _label: Label
var _tiles: Array = []


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		_out = OS.get_cmdline_user_args()[0]
	_ids = HunterRoster.IMPLEMENTED_IDS + HunterRoster.SPECIAL_IDS + HunterRoster.VOID_IDS
	_sub = SubViewport.new()
	_sub.size = TILE
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.08, .08, .1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.7, .7, .75)
	_sub.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	_sub.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	floor_mesh.mesh = plane
	_sub.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_sub.add_child(_camera)
	_label = Label.new()
	_label.position = Vector2(6, 4)
	_label.add_theme_font_size_override("font_size", 14)
	_sub.add_child(_label)
	_run.call_deferred()


func _run() -> void:
	for id in _ids:
		var brain := HunterBrain.new(Vector2(0.5, 0.5), "CHASE-SHEET-%s" % id, id, "standard")
		brain.activate_at(brain.position)
		brain.state = HunterBrain.State.CHASE
		brain.direct_chase_visible = true
		brain.facing = Vector2(0, 1)
		var view := HunterView3D.new()
		view.brain = brain
		_sub.add_child(view)
		_label.text = "%s  %s" % [id, brain.chase_style]
		var clock := 0.0
		for angle in [0.0, 40.0]:
			while clock < (1.4 if angle == 0.0 else 2.0):
				var delta := get_process_delta_time() if get_process_delta_time() > 0.0 else 1.0 / 60.0
				clock += delta
				brain.position += brain.facing * RUN_SPEED * delta
				view.set_look_target(brain.position + brain.facing * 4.0)
				view.sync_from_brain()
				var at := Vector3(brain.position.x, 0.0, brain.position.y)
				var dir := Vector3(brain.facing.x, 0, brain.facing.y).rotated(Vector3.UP, deg_to_rad(angle))
				_camera.position = at + dir * 6.0 + Vector3(0, 1.5, 0)
				_camera.look_at(at + Vector3(0, 1.25, 0), Vector3.UP)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := _sub.get_texture().get_image()
			image.convert(Image.FORMAT_RGB8)
			_tiles.append(image)
		view.queue_free()
		await get_tree().process_frame
	var pairs := _ids.size()
	var rows := int(ceil(float(pairs) / COLUMNS))
	var sheet := Image.create(COLUMNS * TILE.x * 2, rows * TILE.y, false, Image.FORMAT_RGB8)
	for i in _tiles.size():
		var hunter := i / 2
		var x := (hunter % COLUMNS) * TILE.x * 2 + (i % 2) * TILE.x
		var y := (hunter / COLUMNS) * TILE.y
		sheet.blit_rect(_tiles[i], Rect2i(Vector2i.ZERO, TILE), Vector2i(x, y))
	sheet.save_png(_out)
	print("saved ", _out, " ", pairs, " hunters")
	get_tree().quit()
