extends Node

## Neck-lift capture: first person through one lift (reach, rise, hold) and a side view of every lifter holding a runner the way a
## guest sees it (the lifted mannequin plus NeckLift.pose_nearest_hunter). Windowed:
##   Godot --path . res://tools/look/neck_lift.tscn -- /tmp/neck_lift_caps

const LIFTERS := ["kathy", "xivvy", "umbriel", "elise", "wynelle", "ravelle"]

var _guest_body: Node3D
var _remote_root: Node


func _init() -> void:
	process_priority = 100


func _process(_delta: float) -> void:
	if _guest_body != null and is_instance_valid(_guest_body) and _guest_body.visible:
		NeckLift.pose_nearest_hunter(_remote_root, _guest_body, true)


func _hunter(parent: Node, id: String, at: Vector3, facing: Vector3) -> HunterView3D:
	var brain := HunterBrain.new(Vector2(at.x, at.z), "NECK-LIFT", id, "standard")
	brain.activate_at(Vector2(at.x, at.z))
	brain.state = HunterBrain.State.WANDER
	var view := HunterView3D.new()
	view.brain = brain
	parent.add_child(view)
	view.global_position = at
	view.look_at(at + facing, Vector3.UP)
	return view


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/neck_lift_caps"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	add_child(scene)
	for _i in 20:
		await get_tree().process_frame
	var player: PlayerController3D = scene.player
	var lift: NeckLift = scene.neck_lift
	player.input_frozen = true
	player.look_frozen = true
	var fill := OmniLight3D.new()
	fill.light_energy = 2.5
	fill.omni_range = 6.0
	fill.position = Vector3(0, .6, -.6)
	player.active_camera().add_child(fill)
	var stand := player.global_position
	var facing := -player.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var side := facing.cross(Vector3.UP).normalized()

	# first person through Kathy's lift
	var view := _hunter(scene, "kathy", stand + facing * .75, -facing)
	for _i in 4:
		await get_tree().process_frame
	lift.play(player, view)
	var marks := [.15, .4, .7, 1.0, 1.6]
	var shot := 0
	while lift.playing and shot < marks.size():
		await get_tree().process_frame
		if lift.elapsed >= float(marks[shot]):
			await _shot(out, "fp_%d" % shot)
			shot += 1
	while lift.playing:
		await get_tree().process_frame
	await _shot(out, "fp_hold")
	lift.release()
	view.queue_free()
	await get_tree().process_frame

	# side view: each lifter holding a runner as a guest sees it
	var camera := Camera3D.new()
	scene.add_child(camera)
	var light := OmniLight3D.new()
	light.light_energy = 7.0
	light.omni_range = 9.0
	scene.add_child(light)
	_remote_root = scene
	_guest_body = ModelSlot.instantiate(PlayerModels.SCENE)
	scene.add_child(_guest_body)
	_guest_body.scale = Vector3.ONE * PlayerModels.SCALE
	ModelSlot.play_if_available(ModelSlot.find_animation_player(_guest_body), "fall")
	player.visible = false
	for id in LIFTERS:
		var hunter := _hunter(scene, id, stand + facing * .75, -facing)
		for _i in 4:
			await get_tree().process_frame
		var neck := NeckLift.grip_point(hunter, -facing)
		_guest_body.global_position = neck - facing * NeckLift.NECK_DEPTH + Vector3.DOWN * NeckLift.BODY_NECK
		_guest_body.look_at(_guest_body.global_position + facing, Vector3.UP, true)
		var middle := (hunter.global_position + _guest_body.global_position) * .5
		camera.global_position = middle + side * 3.0 - facing * .9 + Vector3.UP * 1.6
		camera.look_at(middle + Vector3.UP * 1.5, Vector3.UP)
		camera.current = true
		light.global_position = middle + side * 2.0 + Vector3.UP * 2.5
		for _i in 8:
			await get_tree().process_frame
		await _shot(out, "tp_%s" % id)
		hunter.queue_free()
		await get_tree().process_frame
	get_tree().quit()
