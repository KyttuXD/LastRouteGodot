extends Node

## The capture jumpscare for a few hunters, shot late in the lunge, before the final red flash covers it.
##   JUMP_IDS=kathy,void_red godot --path . res://tools/look/jumpscare_check.tscn -- OUT.png (writes OUT_<id>.png)

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/jumpscare.png"
	var ids := (OS.get_environment("JUMP_IDS") if OS.get_environment("JUMP_IDS") != "" else "kathy,void_red").split(",")
	for id in ids:
		var camera := Camera3D.new()
		add_child(camera)
		camera.current = true
		var jumpscare := HunterJumpscare.new()
		add_child(jumpscare)
		jumpscare.play(camera, id)
		await get_tree().create_timer(.33).timeout
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "_%s.png" % id))
		await get_tree().create_timer(.8).timeout
		jumpscare.queue_free()
		camera.queue_free()
		await get_tree().process_frame
	get_tree().quit()
