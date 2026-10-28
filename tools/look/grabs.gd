extends Node

## Hunter grab capture: every style once, first person mid-grab and at the hold, then the same grab from the side the way
## another player sees it (a mannequin drawn from the runner's state packet, HunterGrab.pose_nearest_hunter). Windowed:
##   Godot --path . res://tools/look/grabs.tscn -- /tmp/grab_caps

const STYLE_HUNTER := {
	"neck_lift": "kathy", "shoulder_grab": "dovelle", "tackle": "haelith", "wrist_yank": "aki", "wrap": "briselle",
	"leg_grab": "ceryth", "upside_down": "xivvy", "bear_hug": "glyra", "collar_drag": "javelle", "wall_pin": "opalie",
	"pounce_pin": SecretCreatures.IDS[0],
}

var _guest: Node3D
var _packet := []
var _root: Node


func _init() -> void:
	process_priority = 100


func _process(_delta: float) -> void:
	if _guest != null and is_instance_valid(_guest) and _guest.visible and not _packet.is_empty():
		HunterGrab.pose_nearest_hunter(_root, _guest, _packet)


func _hunter(parent: Node, id: String, at: Vector3, facing: Vector3) -> HunterView3D:
	var brain := HunterBrain.new(Vector2(at.x, at.z), "GRAB-LOOK", id, "standard")
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
	var out := args[0] if args.size() > 0 else "/tmp/grab_caps"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	add_child(scene)
	for _i in 20:
		await get_tree().process_frame
	_root = scene
	var player: PlayerController3D = scene.player
	var grab: HunterGrab = scene.grab
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
	var camera := Camera3D.new()
	scene.add_child(camera)
	var light := OmniLight3D.new()
	light.light_energy = 7.0
	light.omni_range = 9.0
	scene.add_child(light)
	_guest = ModelSlot.instantiate(PlayerModels.SCENE)
	scene.add_child(_guest)
	_guest.scale = Vector3.ONE * PlayerModels.SCALE
	_guest.visible = false
	ModelSlot.play_if_available(ModelSlot.find_animation_player(_guest), "fall")
	for style in STYLE_HUNTER:
		var id := String(STYLE_HUNTER[style])
		player.global_position = stand
		player.active_camera().current = true
		var view := _hunter(scene, id, stand + facing * .8, -facing)
		for _i in 4:
			await get_tree().process_frame
		grab.play(player, view, id, .5, style)
		var mid := false
		while grab.playing:
			await get_tree().process_frame
			if not mid and grab.elapsed > GrabStyles.REACH_SECONDS + GrabStyles.ACT_SECONDS * .5:
				mid = true
				await _shot(out, "%s_fp_mid" % style)
		await _shot(out, "%s_fp_hold" % style)
		# the same hold as another player draws it
		_packet = player.grab_state.duplicate()
		var held_at := player.global_position
		var yaw := GrabStyles.body_yaw(grab._along, float(grab.current["face"]))
		grab.release()
		player.global_position = stand + side * 6.0   # out of the way
		_guest.visible = true
		_guest.global_position = held_at + Vector3.UP * float(_packet[2])
		_guest.global_basis = Basis.from_euler(Vector3(float(_packet[3]), yaw, 0.0)) * Basis.from_scale(_guest.scale)
		var middle := (view.global_position + held_at) * .5
		camera.global_position = middle + side * 3.2 - facing * .8 + Vector3.UP * 1.5
		camera.look_at(middle + Vector3.UP * 1.0, Vector3.UP)
		camera.current = true
		light.global_position = middle + side * 2.0 + Vector3.UP * 2.5
		for _i in 6:
			await get_tree().process_frame
		await _shot(out, "%s_tp" % style)
		_guest.visible = false
		_packet = []
		HunterGrab.pose_hunter_body(view, facing, [0.0, 0.0, 0.0])
		view.queue_free()
		await get_tree().process_frame
	get_tree().quit()
