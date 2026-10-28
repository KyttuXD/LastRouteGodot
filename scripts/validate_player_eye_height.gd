extends RefCounted

## The player body's eyes against the first-person camera, per pose (KT: the camera's eye height is the reference, the model follows it).
## The mannequin is drawn at PlayerModels.SCALE; the camera is _align_camera_to_model_eyes (standing) and the controller's crouch / sit
## eye heights. For each clip the mean eye-bone height over the clip is compared with the camera height of that pose; standing-height
## poses must agree within 2 cm. Poses whose clip does not reach the camera's height yet are listed in GAPS with today's measured
## difference (metres, model minus camera) and fail if that drifts by more than 1.5 cm either way, so a clip change that fixes one has to
## remove it from the list.
##   godot --headless --path . res://scenes/validate.tscn -- player_eye_height

const TOLERANCE := 0.02
const GAP_DRIFT := 0.015
## pose clip -> camera eye height of that pose
const STANDING := ["idle", "tpose", "jump", "fall"]
const GAPS := {"crouch": 0.25, "sit": -0.10, "walk": -0.04, "chase": -0.06, "sprint": -0.08, "climb": -0.06}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _camera_eye(clip: String, standing: float) -> float:
	if clip == "crouch":
		return minf(standing * PlayerController3D.CROUCH_EYE_RATIO,
			PlayerController3D.CROUCH_COLLISION_HEIGHT - PlayerController3D.CROUCH_EYE_TOP_CLEARANCE)
	if clip == "sit":
		return PlayerController3D.SIT_EYE
	return standing


func run(host: Node) -> int:
	for path in [PlayerModels.BLOCKY, PlayerModels.BLOCKY_SLIM]:
		var model := ModelSlot.instantiate(path)
		model.scale = Vector3.ONE * PlayerModels.SCALE
		host.add_child(model)
		var player := ModelSlot.find_animation_player(model)
		await host.get_tree().process_frame
		var standing := 0.0
		for n in ["L-Eye-Attachment", "R-Eye-Attachment"]:
			standing += (model.find_child(n, true, false) as Node3D).global_position.y * 0.5
		standing = clampf(standing, PlayerController3D.CAMERA_HEIGHT_MIN, PlayerController3D.CAMERA_HEIGHT_MAX)
		var report := []
		for clip in STANDING + GAPS.keys():
			if player == null or not player.has_animation(clip):
				_expect(false, "%s: no %s clip" % [path.get_file(), clip])
				continue
			var mean := 0.0
			for s in 12:
				player.play(clip)
				player.seek(player.get_animation(clip).length * float(s) / 12.0, true)
				for n in ["L-Eye-Attachment", "R-Eye-Attachment"]:
					mean += (model.find_child(n, true, false) as Node3D).global_position.y * 0.5 / 12.0
			var diff := mean - _camera_eye(clip, standing)
			report.append("%s %+.0f" % [clip, diff * 100.0])
			if STANDING.has(clip):
				_expect(absf(diff) <= TOLERANCE, "%s %s: eyes %.1f cm off the camera (limit 2)" % [path.get_file(), clip, diff * 100.0])
			else:
				_expect(absf(diff - float(GAPS[clip])) <= GAP_DRIFT, "%s %s: eye gap %.1f cm, listed %.1f cm" % [
					path.get_file(), clip, diff * 100.0, float(GAPS[clip]) * 100.0])
		print("  %s standing camera %.3f m; eyes minus camera (cm): %s" % [path.get_file(), standing, ", ".join(report)])
		model.queue_free()
	return _failures
