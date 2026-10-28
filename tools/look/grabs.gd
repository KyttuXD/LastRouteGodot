extends Node

## Hunter grab capture (KT's camera rules, docs/HUNTER_GRABS.md): every style in three places -- the route's spawn spot (the
## same spot as the earlier sheet, for before/after), an open room and a tight hallway (scripts/grab_arena.gd) -- at three
## moments in first person (start, hold, end) and once from the side the way another player sees it (a mannequin drawn from
## the runner's state packet). Styles the room rules out are marked, not forced. Windowed:
##   Godot --path . res://tools/look/grabs.tscn -- /tmp/grab_caps

const ARENA := preload("res://scripts/grab_arena.gd")
const STYLE_HUNTER := {
	"neck_lift": "kathy", "shoulder_grab": "dovelle", "tackle": "haelith", "wrist_yank": "aki", "wrap": "briselle",
	"leg_grab": "ceryth", "upside_down": "xivvy", "bear_hug": "glyra", "collar_drag": "javelle", "wall_pin": "opalie",
	"pounce_pin": SecretCreatures.IDS[0],
}
const MOMENTS := {"start": .3, "hold": 1.5}

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
	fill.light_energy = 1.5
	fill.omni_range = 5.0
	fill.position = Vector3(0, .4, .3)
	player.active_camera().add_child(fill)
	var camera := Camera3D.new()
	scene.add_child(camera)
	var light := OmniLight3D.new()
	light.light_energy = 6.0
	light.omni_range = 9.0
	scene.add_child(light)
	_guest = ModelSlot.instantiate(PlayerModels.SCENE)
	scene.add_child(_guest)
	_guest.scale = Vector3.ONE * PlayerModels.SCALE
	_guest.visible = false
	ModelSlot.play_if_available(ModelSlot.find_animation_player(_guest), "fall")
	var spawn := player.global_position
	var spawn_facing := -player.global_basis.z
	spawn_facing.y = 0.0
	for where in ["level", "open", "hallway"]:
		# one test space at a time: both are built in the same spot
		var place: Dictionary = {"stand": spawn, "facing": spawn_facing.normalized(), "root": null} if where == "level" \
			else ARENA.build(scene, where)
		var stand: Vector3 = place["stand"]
		var facing: Vector3 = place["facing"]
		var side := facing.cross(Vector3.UP).normalized()
		for style in STYLE_HUNTER:
			var id := String(STYLE_HUNTER[style])
			player.global_position = stand
			player._yaw = atan2(-facing.x, -facing.z)
			player._pitch = 0.0
			player._apply_look_rotation()
			player.active_camera().current = true
			var view := _hunter(scene, id, stand + facing * .8, -facing)
			for _i in 4:
				await get_tree().process_frame
			var room := HunterGrab.probe_room(player.get_world_3d().direct_space_state, stand, stand + facing * .8, -facing,
				[player.get_rid(), view.get_rid()], player.collision_mask)
			if where != "level" and not GrabStyles.fits(style, room):
				FileAccess.open("%s/%s_%s_ruled_out.txt" % [out, where, style], FileAccess.WRITE).store_string(str(room))
				view.queue_free()
				await get_tree().process_frame
				continue
			grab.play(player, view, id, .5, style)
			var shot_names := MOMENTS.keys()
			var next := 0
			var waited := 0.0
			while waited < GrabStyles.TOTAL_SECONDS + .6:
				await get_tree().process_frame
				waited += get_process_delta_time()
				if next < shot_names.size() and waited >= float(MOMENTS[shot_names[next]]):
					await _shot(out, "%s_%s_%s" % [where, style, shot_names[next]])
					next += 1
			await _shot(out, "%s_%s_end" % [where, style])
			# the same hold as another player draws it
			_packet = player.grab_state.duplicate()
			var held_at := player.global_position
			var yaw := GrabStyles.body_yaw(grab._along, float(grab.current["face"]))
			grab.release()
			player.global_position = stand + side * 30.0 + Vector3.UP * 30.0   # out of the way
			_guest.visible = true
			_guest.global_position = held_at + Vector3.UP * float(_packet[2])
			_guest.global_basis = Basis.from_euler(Vector3(float(_packet[3]), yaw, 0.0)) * Basis.from_scale(_guest.scale)
			# from the front three-quarters of the runner's face (KT), past the hunter's side, clear of the walls
			var front := Vector3(-sin(yaw), 0.0, -cos(yaw))
			for _i in 2:
				await get_tree().process_frame
			var chest := _guest.find_child("Chest", true, false) as Node3D
			var runner_head := chest.global_position + Vector3.UP * .25 if chest != null else held_at + Vector3.UP * 1.2
			var across := front.cross(Vector3.UP).normalized()
			# about 65 degrees off the runner's face: she stands right in front of them, so any closer to their front and her
			# back hides their face; far enough out that she is beside the line of sight, not in it; the
			# hallway has no room to the side, so from high up the corridor over her shoulder instead
			var spot := runner_head + (front * .45 + across).normalized() * 2.4 + Vector3.UP * .45
			if where == "hallway":
				spot = runner_head + front * 2.4 + across * .6 + Vector3.UP * .95
			if where == "hallway":
				spot.x = clampf(spot.x, ARENA.BASE.x - .75, ARENA.BASE.x + .75)
			camera.global_position = spot
			camera.look_at(runner_head + front * .4, Vector3.UP)
			var middle := (view.global_position + held_at) * .5
			camera.current = true
			light.global_position = middle + side * .6 + Vector3.UP * 2.4
			for _i in 6:
				await get_tree().process_frame
			await _shot(out, "%s_%s_tp" % [where, style])
			_guest.visible = false
			_packet = []
			HunterGrab.pose_hunter_body(view, facing, [0.0, 0.0, 0.0])
			view.queue_free()
			await get_tree().process_frame
		if place["root"] != null:
			(place["root"] as Node).queue_free()
			await get_tree().process_frame
	get_tree().quit()
