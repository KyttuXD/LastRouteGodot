extends Node

## Frame sequence of Porcelle's minimap ping (RadarPing) at 1280x720: through one ping, between pings, and reduced motion.
##   godot --path . res://dev/look/radar_capture.tscn -- OUTDIR   ->  radar_<n>_<label>.png
func _ready() -> void:
	Build.capture_rig = true
	Settings.reduced_motion = false   # the profile on a test machine may have it on
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var pixels := Vector2i(1280, 720)
	var holder := SubViewport.new()
	holder.size = pixels
	var units: Vector2 = load("res://tests/validate_admin_layout.gd").units_for(pixels)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(holder)
	var hud := (load("res://game/hud/hud.tscn") as PackedScene).instantiate() as HUD
	holder.add_child(hud)
	await get_tree().process_frame
	var generator := FacilityGenerator.new("RADAR-CAPTURE", RoomState.generator_options())
	var mark := {"at": Vector2(generator.cols * 0.7, generator.rows * 0.3), "active": true, "name": "PORCELLE",
		"hunter_id": "porcelle", "ghost": true}
	hud.update_minimap(generator, Vector2(generator.cols * 0.4, generator.rows * 0.6), Vector2.RIGHT, [mark])
	var frames := [[0.0, "start"], [0.12, "rising"], [0.3, "peak"], [0.45, "ring"], [0.62, "fading"], [3.0, "between"]]
	var n := 0
	for frame in frames:
		hud.minimap.radar_time = float(frame[0])
		await _save(holder, out, "radar_%d_%s" % [n, frame[1]])
		n += 1
	Settings.reduced_motion = true
	hud.minimap.radar_time = 3.0
	await _save(holder, out, "radar_%d_reduced_motion" % n)
	Settings.reduced_motion = false
	get_tree().quit()


func _save(holder: SubViewport, out: String, file: String) -> void:
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	holder.get_texture().get_image().save_png("%s/%s.png" % [out, file])
