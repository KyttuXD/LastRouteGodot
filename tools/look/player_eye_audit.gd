extends Node

## Eye height of the player mannequin per clip, at PlayerModels.SCALE, next to the camera heights the controller uses.
##   godot --headless --path . res://tools/look/player_eye_audit.tscn

func _ready() -> void:
	for path in [PlayerModels.BLOCKY, PlayerModels.BLOCKY_SLIM]:
		var model := ModelSlot.instantiate(path)
		model.scale = Vector3.ONE * PlayerModels.SCALE
		add_child(model)
		var player := ModelSlot.find_animation_player(model)
		await get_tree().process_frame
		print("== %s scale %.3f" % [path.get_file(), PlayerModels.SCALE])
		var names: Array = []
		if player != null:
			names = Array(player.get_animation_list())
		names.sort()
		for clip in names:
			if player.get_animation(clip).length <= 0.0:
				continue
			var lows := 1e9
			var eyes := 0.0
			var head := 0.0
			for s in 8:
				player.play(clip)
				player.seek(player.get_animation(clip).length * float(s) / 8.0, true)
				var e := 0.0
				for n in ["L-Eye-Attachment", "R-Eye-Attachment"]:
					e += (model.find_child(n, true, false) as Node3D).global_position.y * 0.5
				if s == 0:
					eyes = e
					head = (model.find_child("Head", true, false) as Node3D).global_position.y
			print("  %-16s eye y %.3f  head pivot y %.3f" % [clip, eyes, head])
		print("  camera: standing %.3f (fallback) min %.3f max %.3f, crouch eye = min(standing*%.2f, %.3f)" % [
			PlayerController3D.CAMERA_HEIGHT, PlayerController3D.CAMERA_HEIGHT_MIN, PlayerController3D.CAMERA_HEIGHT_MAX,
			PlayerController3D.CROUCH_EYE_RATIO, PlayerController3D.CROUCH_COLLISION_HEIGHT - PlayerController3D.CROUCH_EYE_TOP_CLEARANCE])
		print("  capsule standing %.3f crouch %.3f" % [PlayerController3D.STANDING_COLLISION_HEIGHT, PlayerController3D.CROUCH_COLLISION_HEIGHT])
		model.queue_free()
	get_tree().quit()
