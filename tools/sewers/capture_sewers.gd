extends Node3D

## Windowed review captures of the sewer (docs/SEWERS.md): a tunnel, the
## junction chamber, a utility room, a hunter mid-climb in a ladder shaft and
## the open manhole seen from the maze. Run on a test machine:
##
##   Claude-Setup/mini-run.sh . <lane> --scene "res://tools/sewers/capture_sewers.tscn -- OUTDIR"

const SEED := "SEWER-CAPTURE"
const CLIMBER := "umbriel"

var _view: StreamedFacilityView3D
var _player: PlayerController3D
var _camera: Camera3D
var _out := "user://sewer_captures"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	add_child(env)
	RefLook.install(self, env)
	_view = StreamedFacilityView3D.new()
	add_child(_view)
	_player = (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	add_child(_player)
	_player.visible = false
	_player.flashlight_enabled = false
	_camera = Camera3D.new()
	_camera.fov = 72.0
	add_child(_camera)
	_camera.current = true
	# the runner's flashlight, so the dark sewer reads the way a player sees it
	var torch := SpotLight3D.new()
	torch.spot_range = 16.0
	torch.spot_angle = 30.0
	torch.light_energy = 2.2
	torch.light_color = Color("fff1d6")
	_camera.add_child(torch)
	_run.call_deferred()


func _run() -> void:
	var level_y := float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	var c := SewerRouteGenerator.CENTER
	var half := SewerRouteGenerator.TUNNEL_HALF
	_player.global_position = Vector3(c - half + .5, level_y + .04, c + .5)
	_view.begin(SEED, _player)
	await _settle()
	# 1: down the east-west tunnel from the north walkway
	await _shot("sewer_tunnel", Vector3(c + 12.5, level_y + 1.6, c - half + 1.2), Vector3(c - 6.0, level_y + .4, c + .5))
	# 1b: looking up at the vault over the tunnel (what decorates the ceiling)
	await _shot("sewer_ceiling", Vector3(c + 8.5, level_y + 1.6, c - half + 1.5), Vector3(c - 2.0, level_y + 3.1, c + .5))
	# 2: across the junction chamber
	await _shot("sewer_junction", Vector3(c - 5.5, level_y + 2.2, c - 5.5), Vector3(c + 3.0, level_y, c + 3.0))
	# 3: a utility room nearby
	var room := _find_room(["pump_room", "valve_room", "overflow_chamber"])
	if not room.is_empty():
		var rect: Rect2i = room["rect"]
		var chunk: Vector3i = room["coord"]
		var origin := Vector3(chunk.x * StreamedRouteGenerator.CHUNK_SIZE, level_y, chunk.z * StreamedRouteGenerator.CHUNK_SIZE)
		_player.global_position = origin + Vector3(rect.get_center().x, .04, rect.get_center().y)
		_view.refresh_at_tracked_player()
		await _settle()
		await _shot("sewer_%s" % room["room_type"], origin + Vector3(rect.end.x - .6, 2.4, rect.end.y - .6),
			origin + Vector3(rect.position.x + 1.0, .3, rect.position.y + 1.0))
	# 4 + 5: the origin chunk's ladder: a hunter mid-climb from the shaft chamber, then the manhole from the maze
	# a ladder away from the origin chunk (its spawn marker would crowd the shot)
	var link := {}
	for coord in [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 1)]:
		var links: Array = _view.generator.sewer().links_for(coord)
		if not links.is_empty():
			link = links[0]
			break
	var foot := LadderTraffic.ladder_point(link, SewerRouteGenerator.LEVEL)
	var wall: Vector2i = link.get("wall", Vector2i(0, -1))
	var away := Vector3(-wall.x, 0, -wall.y)
	_player.global_position = Vector3(foot.x, level_y + .04, foot.y)
	_view.refresh_at_tracked_player()
	await _settle()
	var climber := _climbing_hunter(Vector3(foot.x, level_y + 1.4, foot.y) - away * .32, wall)
	await _shot("sewer_hunter_climbing", Vector3(foot.x, level_y + 1.1, foot.y) + away * 2.3 + Vector3(.6, 0, .6),
		Vector3(foot.x, level_y + 2.3, foot.y))
	climber.global_position.y = -3.1   # climbing up the shaft, her head just under the open lid
	_player.global_position = Vector3(foot.x, .04, foot.y)
	_view.refresh_at_tracked_player()
	await _settle()
	await _shot("maze_manhole", Vector3(foot.x, 1.9, foot.y) + away * 1.6, Vector3(foot.x, -1.2, foot.y))
	# 6: down a ramp tunnel from the first sewer to the collector, from its top landing
	for upper in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
		var ramp := {}
		var column := Vector2i.ZERO
		for cz in range(-2, 3):
			for cx in range(-2, 3):
				if ramp.is_empty():
					ramp = _view.generator.sewer().ramp_between(cx, cz, upper)
					column = Vector2i(cx, cz)
		if ramp.is_empty():
			continue
		var size := StreamedRouteGenerator.CHUNK_SIZE
		var base := Vector2(column * size)
		var top := base + Vector2(ramp["link"]["from_cell"]) + Vector2(.5, .5)
		var bottom := base + Vector2(ramp["link"]["to_cell"]) + Vector2(.5, .5)
		var upper_y := float(upper) * StreamedFacilityView3D.LEVEL_HEIGHT
		_player.global_position = Vector3(top.x, upper_y + .04, top.y)
		_view.refresh_at_tracked_player()
		await _settle()
		var back := (top - bottom).normalized()
		await _shot("ramp_from_%d" % upper, Vector3(top.x + back.x * 1.2, upper_y + 1.7, top.y + back.y * 1.2),
			Vector3(bottom.x, upper_y - 3.2, bottom.y))
	# 7: the Inferno, the deepest level, along its central hall
	var inferno_y := float(StreamedRouteGenerator.INFERNO_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	_player.global_position = Vector3(c + 4.5, inferno_y + .04, c + .5)
	_view.refresh_at_tracked_player()
	await _settle()
	await _shot("inferno_hall", Vector3(c + 9.5, inferno_y + 1.7, c + .5), Vector3(c - 6.0, inferno_y + 1.0, c + .5))
	print("SEWER CAPTURES -> %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()


func _settle() -> void:
	for _frame in 40:
		await get_tree().process_frame


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	_camera.global_position = eye
	_camera.look_at(look, Vector3.UP)
	for _frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("captured ", name)


func _find_room(kinds: Array) -> Dictionary:
	for radius in 3:
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var coord := Vector3i(x, SewerRouteGenerator.LEVEL, z)
				for room in _view.generator.chunk(coord).get("rooms", []):
					if kinds.has(String(room["room_type"])):
						var found: Dictionary = room.duplicate()
						found["coord"] = coord
						return found
	return {}


## The hunter's own rig on the rungs, facing the wall, frozen partway through her climb clip.
func _climbing_hunter(at: Vector3, wall: Vector2i) -> Node3D:
	var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(CLIMBER))
	add_child(model)
	model.global_position = at
	model.rotation.y = atan2(-float(wall.x), -float(wall.y))
	model.scale = Vector3.ONE * HunterRoster.scale_for(CLIMBER)
	var animation := ModelSlot.find_animation_player(model)
	if animation != null and animation.has_animation("climb"):
		animation.play("climb")
		animation.seek(.3, true)
		animation.pause()
	return model
