extends Node

## Admin hunter-reveal blips on a streamed floor, at minimap and full-map scale.
##   godot --path . res://dev/look/hunter_blip_capture.tscn -- OUTDIR  ->  hunter_blip_<surface>.png
func _ready() -> void:
	Build.capture_rig = true
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	var size := 16
	var walls := PackedByteArray()
	walls.resize(size * size)
	walls.fill(0)
	var chunks := {Vector3i(0, 0, 0): {"walls": walls}, Vector3i(1, 0, 0): {"walls": walls}}
	var marks := [
		{"at": Vector2(6.5, 6.5), "active": true, "name": "ADA", "level": 0, "hunter_id": "a"},
		{"at": Vector2(20.5, 9.5), "active": true, "name": "WYNELLE", "level": 0, "hunter_id": "w"},
		{"at": Vector2(12.5, 12.5), "active": true, "name": "MIRA", "level": 0, "hunter_id": "m"},
	]
	for surface in [["minimap", Vector2i(180, 180), 9], ["fullmap", Vector2i(640, 360), 0]]:
		var holder := SubViewport.new()
		holder.size = surface[1]
		holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(holder)
		var map := FacilityMap.new()
		map.size = Vector2(surface[1])
		map.interactive = int(surface[2]) == 0
		holder.add_child(map)
		map.show_streamed_state(chunks, 0, size, Vector2(10, 8), Vector2.RIGHT, marks,
			false, int(surface[2]))
		map.queue_redraw()
		for _i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		holder.get_texture().get_image().save_png("%s/hunter_blip_%s.png" % [out, surface[0]])
	get_tree().quit()
