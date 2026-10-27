extends Node

## Prints the vertical extent of a pose on one hunter (forward kinematics, no window): highest point (head top), lowest
## hand / knee / foot, forward reach. HUNTER=verrine POSES=vent_crawl_verrine,vent_drop_verrine
##   godot --headless --path . res://tools/look/pose_probe.tscn

func _ready() -> void:
	var id := OS.get_environment("HUNTER") if OS.get_environment("HUNTER") != "" else "verrine"
	var poses: Array = OS.get_environment("POSES").split(",") if OS.get_environment("POSES") != "" else NightWatchPoses.pose_ids()
	var model := (load("res://assets/hunters_blocky/%s/%s.glb" % [id, id]) as PackedScene).instantiate() as Node3D
	add_child(model)
	var player := ModelSlot.find_animation_player(model)
	NightWatchPoses.install(model, player, id)
	var rest := {}
	HunterStride._collect_rest(model, model, rest)
	for pose_id in poses:
		var animation := player.get_animation(NightWatchPoses.clip_name(pose_id))
		var top := -9.0
		var hands := 9.0
		var knees := 9.0
		var feet := 9.0
		var front := -9.0
		var back := 9.0
		for i in 33:
			var pose := HunterStride.fk(model, rest, animation, animation.length * i / 32)
			var head: Transform3D = pose["Head"]
			top = maxf(top, (head * Vector3(0, .3, 0)).y)
			for bone in pose:
				top = maxf(top, (pose[bone] as Transform3D).origin.y)
			hands = minf(hands, minf((pose["L-Hand"] as Transform3D).origin.y, (pose["R-Hand"] as Transform3D).origin.y))
			knees = minf(knees, minf((pose["L-Calf"] as Transform3D).origin.y, (pose["R-Calf"] as Transform3D).origin.y))
			feet = minf(feet, minf((pose["L-Foot"] as Transform3D).origin.y, (pose["R-Foot"] as Transform3D).origin.y))
			front = maxf(front, -(head * Vector3(0, .3, 0)).z)
			back = minf(back, -(pose["L-Foot"] as Transform3D).origin.z)
		print("%s %s: top %.2f  hands %.2f  knees %.2f  feet %.2f  head forward %.2f  feet back %.2f" % [id, pose_id, top, hands, knees, feet, front, back])
	get_tree().quit()
