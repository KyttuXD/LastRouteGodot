extends Node3D

## Windowed review captures of the falls (docs/SEWERS.md): the first sewer's spur and lip seen from the tunnel walkway
## and the overlook, then the cistern on the collector, for the first few sites near the origin. Run on a test machine:
##
##   godot --path . res://tools/sewers/capture_falls.tscn -- OUTDIR [SEED]

const SITES := 2

var _view: StreamedFacilityView3D
var _player: PlayerController3D
var _camera: Camera3D
var _out := "user://falls_captures"
var _seed := "SEWER-CAPTURE"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	if args.size() > 1:
		_seed = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	add_child(env)
	RefLook.install(self, env)
	_view = StreamedFacilityView3D.new()
	add_child(_view)
	_player = (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	add_child(_player)
	_player.visible = false
	_player.flashlight_enabled = false
	_camera = Camera3D.new()
	_camera.fov = 72.0
	add_child(_camera)
	_camera.current = true
	var torch := SpotLight3D.new()
	torch.spot_range = 16.0
	torch.spot_angle = 30.0
	torch.light_energy = 2.2
	_camera.add_child(torch)
	_run.call_deferred()


func _run() -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var level_y := float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	var low_y := float(SewerRouteGenerator.LOWER_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	var c := SewerRouteGenerator.CENTER
	_player.global_position = Vector3(c + .5, level_y + .04, c + .5)
	_view.begin(_seed, _player)
	var found := 0
	for cz in range(-4, 5):
		for cx in range(-4, 5):
			var site: Dictionary = _view.generator.sewer().falls_between(cx, cz)
			if site.is_empty() or found >= SITES:
				continue
			found += 1
			var base := Vector3(cx * size, 0.0, cz * size)
			var lip := base + Vector3(float(site["edge_x0"]) + 1.5, 0.0, float(site["edge_z"]))
			var toward := 1.0 if bool(site["north"]) else -1.0
			var deck: Rect2i = site["spur_deck"]
			var tag := "%d_%d" % [cx, cz]
			_player.global_position = base + Vector3(deck.position.x + 1.5, level_y + .04, deck.position.y + 1.5)
			_view.refresh_at_tracked_player()
			await _settle()
			# from the tunnel walkway, down the spur to the lip (what a runner in the hall sees)
			await _shot("falls_%s_hall" % tag, base + Vector3(deck.position.x + 3.5, level_y + 1.7, deck.position.y + 1.5),
				lip + Vector3(0, level_y - 1.0, 0))
			await _shot("falls_%s_spur" % tag, base + Vector3(deck.position.x + 1.5, level_y + 1.9, deck.position.y + 1.5 - toward * 1.0),
				lip + Vector3(0, level_y - 2.0, -toward * 1.0))
			await _shot("falls_%s_lip" % tag, lip + Vector3(1.6, level_y + 1.7, toward * 2.5), lip + Vector3(0, level_y - 1.5, -toward * .5))
			var overlook: Rect2i = site["overlook"]
			await _shot("falls_%s_overlook" % tag, base + Vector3(overlook.position.x + 1.5, level_y + 1.7, float(site["edge_z"]) + toward * 1.0),
				lip + Vector3(0, level_y - 2.0, -toward * 1.5))
			await _shot("falls_%s_above" % tag, lip + Vector3(5.0, level_y + 3.4, toward * 2.0), lip + Vector3(0, low_y + .5, -toward * 1.0))
			var chamber: Rect2i = site["chamber"]
			_player.global_position = base + Vector3(chamber.position.x + 1.5, low_y + .04, chamber.get_center().y)
			_view.refresh_at_tracked_player()
			await _settle()
			await _shot("falls_%s_cistern" % tag, base + Vector3(chamber.position.x + 1.5, low_y + 1.6, chamber.get_center().y - toward * 3.5),
				lip + Vector3(0, low_y + 1.0, 0))
	print("falls sites captured: %d" % found)
	get_tree().quit()


func _settle() -> void:
	for _frame in 60:
		await get_tree().process_frame


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	_camera.global_position = eye
	_camera.look_at(look, Vector3.UP)
	for _frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("captured ", name)
