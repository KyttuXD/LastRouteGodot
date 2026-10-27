extends Node

## Screenshots the death moment (typed YTTU line and a Void caption) at 1280x720 and 1920x1080.
##   godot --path . res://tools/look/death_capture.tscn -- OUTDIR
func _ready() -> void:
	Build.capture_rig = true
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var cases := [["aki", "Aki", "typed"], ["void_red", "Red Void", "caption"]]
	for pixels in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for case in cases:
			var holder := SubViewport.new()
			holder.size = pixels
			var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
			holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
			holder.size_2d_override_stretch = true
			holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(holder)
			var backdrop := ColorRect.new()
			backdrop.color = Color(.10, .07, .12)
			backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
			holder.add_child(backdrop)
			var moment := DeathMoment.new()
			holder.add_child(moment)
			await get_tree().process_frame
			var picked := DeathLines.pick({"hunter_id": case[0], "via": "contact"}, "CAPTURE", 4, case[1], false)
			moment.play(case[1], picked, case[0] == "void_red")
			for _i in 90:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			holder.get_texture().get_image().save_png("%s/death_moment_%s_%dx%d.png" % [out, case[0], pixels.x, pixels.y])
			moment.dismiss()
			holder.queue_free()
			await get_tree().process_frame
	get_tree().quit()
