extends Node

## Multi-angle capture around spots of the City (geometry audit, docs/GEOMETRY_AUDIT.md): 8 compass headings x 2 elevations
## (street level and 14 m up) looking at each spot from 9 m away, plus a sweep of every City block (an oblique from each
## block's south-west corner looking at its middle, and one straight down). Written at 640 px wide to keep them small.
##
##   godot --path . res://tools/look/geometry_capture.tscn -- OUTDIR TAG SEED
##
## Environment: CAP_SPOTS="gx:gz,gx:gz" city cells to orbit (default: a few of the audit's flagged cells), CAP_SWEEP=1 adds
## the block sweep, CAP_ONLY=1 skips the orbits. The same file runs on the old and the new tree for before/after pairs.

const WIDTH := 640
var _out_dir := ""
var _tag := "geo"
var _scene: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else "build/geo"
	_tag = args[1] if args.size() > 1 else "geo"
	RoomState.create_local(RoomState.Mode.CITY)
	RoomState.seed_text = args[2] if args.size() > 2 else "CITY-LOOK"
	var abs_dir := _out_dir if _out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	_out_dir = abs_dir
	Backend.enable_offline_mode()
	_scene = load(RoomState.CITY_ROUTE_SCENE).instantiate()
	add_child(_scene)
	_run()


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
		var pause = _scene.get("pause_menu")
		if pause != null and pause.has_method("close") and pause.is_open():
			pause.close()
		get_tree().paused = false


static func _at(gx: float, gz: float, y: float) -> Vector3:
	return Vector3(gx - CityLayout.ORIGIN_OFFSET.x, y, gz - CityLayout.ORIGIN_OFFSET.y)


func _shot(name: String, player: PlayerController3D, facility: StreamedFacilityView3D, pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player._yaw = deg_to_rad(yaw)
	player._pitch = deg_to_rad(pitch)
	player._apply_look_rotation()
	facility.refresh_at_tracked_player()
	await _wait(26)
	var hide := OS.get_environment("CAP_HIDE")
	if hide != "":
		for pattern in hide.split(","):
			for node in facility.find_children(pattern, "Node3D", true, false):
				(node as Node3D).visible = false
		await _wait(2)
	var image := get_viewport().get_texture().get_image()
	image.resize(WIDTH, int(float(image.get_height()) * WIDTH / float(image.get_width())), Image.INTERPOLATE_BILINEAR)
	image.save_png("%s/%s_%s.png" % [_out_dir, _tag, name])


func _run() -> void:
	await _wait(40)
	var facility := _scene.get_node("%StreamedFacility") as StreamedFacilityView3D
	var player := _scene.get_node("%Player") as PlayerController3D
	_scene.get_node("%HUD").visible = false
	var layout := (facility.generator as CityRouteGenerator).layout
	var spots := []
	var env_spots := OS.get_environment("CAP_SPOTS")
	if env_spots != "":
		for part in env_spots.split(","):
			var xy := part.split(":")
			spots.append(Vector2i(int(xy[0]), int(xy[1])))
	else:
		spots = [Vector2i(135, 91), Vector2i(183, 44), Vector2i(160, 89), Vector2i(52, 44)]
	for spot_value in spots:
		var spot: Vector2i = spot_value
		for heading in 8:
			var yaw := heading * 45.0
			# forward = (-sin yaw, -cos yaw): stand 9 m behind the spot and look at it
			var forward := Vector2(-sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw)))
			var eye := Vector2(spot.x + .5, spot.y + .5) - forward * 9.0
			await _shot("c%d_%d_h%03d_street" % [spot.x, spot.y, int(yaw)], player, facility, _at(eye.x, eye.y, .05), yaw, 8.0)
			var near := Vector2(spot.x + .5, spot.y + .5) - forward * 5.0
			await _shot("c%d_%d_h%03d_up" % [spot.x, spot.y, int(yaw)], player, facility, _at(near.x, near.y, .05), yaw, float(OS.get_environment("CAP_PITCH")) if OS.get_environment("CAP_PITCH") != "" else 55.0)
			var high := Vector2(spot.x + .5, spot.y + .5) - forward * 14.0
			await _shot("c%d_%d_h%03d_high" % [spot.x, spot.y, int(yaw)], player, facility, _at(high.x, high.y, 14.0), yaw, -24.0)
		print("orbit %s done" % spot)
	if OS.get_environment("CAP_SWEEP") != "":
		var block_index := 0
		for zb in _bands(CityLayout.EW_STREETS, CityLayout.HEIGHT):
			for xb in _bands(CityLayout.NS_STREETS, CityLayout.WIDTH):
				var cx: float = (float(xb[0]) + float(xb[1])) * .5
				var cz: float = (float(zb[0]) + float(zb[1])) * .5
				if CityLayout.ellipse_r(int(cx), int(cz)) > CityLayout.BUILD_LIMIT:
					continue
				var name := "block%02d" % block_index
				block_index += 1
				await _shot(name + "_oblique", player, facility, _at(float(xb[0]) - 4.0, float(zb[1]) + 6.0, 16.0), -35.0, -22.0)
				await _shot(name + "_down", player, facility, _at(cx, cz + 1.0, 60.0), 0.0, -85.0)
		print("swept %d blocks" % block_index)
	get_tree().quit()


## [from, to) cell spans between the streets (the same split CityLayout._street_spans does).
func _bands(streets: Array, limit: int) -> Array:
	var out := []
	var cursor := 0
	for street in streets:
		var from: int = (street[0] as int) - (street[1] as int) / 2
		if from > cursor:
			out.append([cursor, from])
		cursor = from + (street[1] as int)
	if cursor < limit:
		out.append([cursor, limit])
	return out
