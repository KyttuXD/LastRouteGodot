extends Node

## Render check that nothing hangs in the City sky (KT: dome ribs, rings, spokes and markers seen looking straight up).
## From three districts it looks straight up twice, with the city's chunks hidden: once as built and once with the
## CityDomeFrame hidden as well. Any dark sky-crossing geometry (a dome shell, cables, viaducts) shows up as pixels that
## the frame darkens; more than MAX_DARKER of them fails. Also saves the full straight-up view of each spot.
##
##   godot --path . res://tools/look/zenith_check.tscn -- OUTDIR TAG      (needs a renderer: not --headless)

const WIDTH := 640
const MAX_DARKER := .002
## Central Avenue, Main Street, Ring Road
const SPOTS := [Vector2i(112, 40), Vector2i(160, 67), Vector2i(200, 67)]

var _scene: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "build/zenith"
	var tag: String = args[1] if args.size() > 1 else "zenith"
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	RoomState.create_local(RoomState.Mode.CITY)
	RoomState.seed_text = "CITY-LOOK"
	Backend.enable_offline_mode()
	_scene = load(RoomState.CITY_ROUTE_SCENE).instantiate()
	add_child(_scene)
	await _wait(40)
	var facility := _scene.get_node("%StreamedFacility") as StreamedFacilityView3D
	var player := _scene.get_node("%Player") as PlayerController3D
	_scene.get_node("%HUD").visible = false
	var failures := 0
	for spot in SPOTS:
		player.global_position = Vector3(spot.x + .5 - CityLayout.ORIGIN_OFFSET.x, .05, spot.y + .5 - CityLayout.ORIGIN_OFFSET.y)
		player.velocity = Vector3.ZERO
		player._yaw = 0.0
		player._pitch = deg_to_rad(89.0)
		player._apply_look_rotation()
		facility.refresh_at_tracked_player()
		await _wait(30)
		var full := _grab()
		full.save_png("%s/%s_c%d_%d_up.png" % [out_dir, tag, spot.x, spot.y])
		var chunks := facility.find_children("Chunk_*", "Node3D", false, false)
		for chunk in chunks:
			(chunk as Node3D).visible = false
		var frame := facility.get_node_or_null("CityDomeFrame") as Node3D
		await _wait(3)
		var with_frame := _grab()
		if frame != null:
			frame.visible = false
		await _wait(2)
		var sky_only := _grab()
		if frame != null:
			frame.visible = true
		for chunk in chunks:
			(chunk as Node3D).visible = true
		# Only the disc around the zenith: the far skyline towers legitimately reach into the image corners from the
		# Ring Road, but a dome rib, ring or spoke crosses the middle of the sky.
		var darker := 0
		var counted := 0
		var middle := Vector2(with_frame.get_width(), with_frame.get_height()) * .5
		var radius := with_frame.get_height() * .42
		for y in with_frame.get_height():
			for x in with_frame.get_width():
				if Vector2(x, y).distance_to(middle) > radius:
					continue
				counted += 1
				if sky_only.get_pixel(x, y).get_luminance() - with_frame.get_pixel(x, y).get_luminance() > .08:
					darker += 1
		var share := float(darker) / float(counted)
		var ok := share <= MAX_DARKER
		print("  zenith %s %s: %.3f%% of the zenith disc darkened by the dome frame" % [spot, "ok" if ok else "FAIL", share * 100.0])
		if not ok:
			failures += 1
			with_frame.save_png("%s/%s_c%d_%d_frame_only.png" % [out_dir, tag, spot.x, spot.y])
	print("zenith check: %s" % ("all clear" if failures == 0 else "%d spot(s) with geometry across the sky" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _grab() -> Image:
	var image := get_viewport().get_texture().get_image()
	image.resize(WIDTH, int(float(image.get_height()) * WIDTH / float(image.get_width())), Image.INTERPOLATE_BILINEAR)
	return image


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
		var pause = _scene.get("pause_menu")
		if pause != null and pause.has_method("close") and pause.is_open():
			pause.close()
		get_tree().paused = false
