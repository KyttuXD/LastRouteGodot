class_name PlaytestSequencer
extends RefCounted

## Trailer staging: plays one scripted SHOT (res://tools/playtest/shots/<name>.json, docs/FLYTHROUGH.md) in the real Last Route scene.
## A shot is DATA: a stage (an area preset from PlaytestFlythrough, its first hall), actors (hunter models with floor-snapped feet),
## a camera track, a flashlight track and timed events. Nothing here touches game rules: actors are bare hunter models driven by this
## script (no HunterBrain), the camera is the player's own camera moved like the flythrough does.
##
## Stage coordinates are [forward, right] metres from the stage origin (the first walkable point of the area, facing down its longest open
## run); a third number is height above the floor. Times are seconds from the clip start.
##
## {
##   "name": "nyxie_peek", "area": "hospital", "seconds": 11, "dark": 0.35,
##   "actors": {"nyxie": {"id": "nyxie", "at": [9, 0.7], "face": "camera", "pose": "peek_left", "tag": "NYXIE"}},
##   "camera": [{"t": 0, "at": [0, 0, 1.55], "look": "nyxie:1.3"}, {"t": 11, "at": [2.5, 0, 1.5], "look": "nyxie:1.3"}],
##   "flashlight": [{"t": 0, "on": false}, {"t": 6, "on": true}],
##   "events": [{"t": 6.2, "actor": "nyxie", "pose": "flinch"},
##              {"t": 7.0, "actor": "nyxie", "move": [16, 0.7], "speed": 3.2, "pose": "retreat"},
##              {"t": 3, "flicker": 0.5}, {"t": 9, "actor": "nyxie", "hide": true}]
## }
## look: "<actor>[:height]" or [f, r, h]. face: "camera", "away", an actor name or degrees. Event keys: pose (loop until replaced), clip
## (raw animation, e.g. "walk"), move + speed, hide / show, tag (text) / tag_off, flicker (seconds), flash (flashlight stutters).

const SHOT_DIR := "res://tools/playtest/shots/"
const EYE := 1.6


class Actor:
	extends RefCounted
	var key := ""
	var hunter_id := ""
	var root: Node3D
	var model: Node3D
	var anim: AnimationPlayer
	var pos := Vector3.ZERO     # stage-agnostic world position of the feet
	var yaw := 0.0
	var target := Vector3(NAN, NAN, NAN)
	var speed := 0.0
	var face_mode: Variant = "away"
	var tag: Label3D
	var tag_alpha := 0.0
	var tag_goal := 0.0
	var height := 1.7
	var posed := false


static func run(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var fps := maxi(int(opts.get("fps", 30)), 10)
	var shot_name := String(opts.get("shot", ""))
	var file := FileAccess.open(SHOT_DIR + shot_name + ".json", FileAccess.READ)
	if file == null:
		return {"scenario_failure": "no shot file %s%s.json" % [SHOT_DIR, shot_name], "outcome": "error", "game_seconds": 0.0, "frames": 0}
	var shot: Dictionary = JSON.parse_string(file.get_as_text())
	var area := String(shot.get("area", "hospital"))
	bridge.status = "shot %s: starting the run" % shot_name
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"], "bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	bridge.admin("god", {"on": true})
	bridge.admin("no_target", {"on": true})
	var scene := tree.current_scene
	var facility: Object = scene.get("facility")
	var generator := facility.get("generator") as StreamedRouteGenerator
	var player := scene.get("player") as PlayerController3D
	if generator == null or player == null:
		return {"scenario_failure": "no generator or player in the route scene", "outcome": "error", "game_seconds": 0.0, "frames": 0}
	var planned := PlaytestFlythrough.plan(generator, area, fps, 0.0, int(opts.get("variant", 0)), false)
	if not bool(planned.get("ok", false)):
		report["flythrough"] = {"area": shot_name, "available": false, "reason": planned.get("error", "?")}
		return {"scenario_failure": "", "outcome": "unavailable", "game_seconds": 0.0, "frames": 0}
	var track: PlaytestFlythrough.Track = planned["track"]
	var info: Dictionary = planned["info"]
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	if player.first_person_items != null:
		player.first_person_items.visible = false
	player.input_frozen = true
	player.look_frozen = true
	player.set_admin_noclip(true)
	# the stage starts where the flythrough first WALKS (frame 0 is the high establishing shot)
	var stage_frame := 0
	for k in track.size():
		if int(track.ground[k]) == 1:
			stage_frame = k
			break
	var corner_stage := _path_corner(track) if bool(shot.get("corner", false)) else {}
	if not corner_stage.is_empty():
		stage_frame = int(corner_stage["frame"])
	var origin_eye := track.pos[stage_frame]
	bridge.admin("teleport", {"x": origin_eye.x, "y": origin_eye.y - EYE, "z": origin_eye.z})
	var frames := 0
	for _i in 120:
		await tree.process_frame
		frames += 1
		if frames % 20 == 0:
			PlaytestFlythrough._clear_hunters(scene, false)
		scene.set("_relay_inactivity_seconds", 0.0)
		scene.set("_party_afk_seconds", 0.0)
	player.global_position = Vector3(origin_eye.x, origin_eye.y - EYE, origin_eye.z)
	await tree.process_frame
	var camera := player.active_camera()
	camera.near = .08
	var space := player.get_world_3d().direct_space_state
	# the stage: origin on the floor, forward along the longest open run
	var floor_origin := _floor_at(space, Vector3(origin_eye.x, origin_eye.y, origin_eye.z), player, origin_eye.y - EYE)
	var forward: Vector3 = corner_stage.get("forward", Vector3.ZERO)
	if forward == Vector3.ZERO:
		forward = _longest_run(space, Vector3(origin_eye.x, floor_origin.y + 1.3, origin_eye.z), player, float(shot.get("min_run", 10.0)), track.yaw[0])
	var right := forward.cross(Vector3.UP)
	var stage := {"o": floor_origin, "f": forward, "r": right}
	stage["corner"] = _find_corner(space, stage, player)
	info["corner"] = stage["corner"]
	info["stage_forward"] = [snappedf(forward.x, .01), snappedf(forward.z, .01)]

	# actors
	var actors: Dictionary = {}
	for key in (shot.get("actors", {}) as Dictionary):
		var spec: Dictionary = shot["actors"][key]
		var actor := _make_actor(scene, str(key), spec, stage, space, player)
		if actor == null:
			return {"scenario_failure": "could not build actor %s" % key, "outcome": "error", "game_seconds": 0.0, "frames": frames}
		actors[str(key)] = actor
	# lights: a dim fill so the set reads, a flashlight on the camera
	var dark := float(shot.get("dark", 1.0))
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = false
	lamp.light_energy = 1.1 * dark
	lamp.omni_range = 11.0
	lamp.light_color = Color(1.0, .95, .85)
	camera.add_child(lamp)
	var torch := SpotLight3D.new()
	torch.spot_range = 18.0
	torch.spot_angle = 24.0
	torch.spot_attenuation = .8
	torch.light_energy = 0.0
	torch.light_color = Color(1.0, .96, .86)
	torch.shadow_enabled = false
	camera.add_child(torch)
	var torch_peak := float(shot.get("torch_energy", 9.0))
	var torch_on := false
	var torch_level := 0.0
	var flicker_left := 0.0
	var flash_left := 0.0
	var clean := bool(opts.get("clean", true))
	var keep := String(opts.get("keep", "")).split(",", false)
	var camera_probe := SphereShape3D.new()
	camera_probe.radius = .2
	var camera_keys: Array = shot.get("camera", [])
	var torch_keys: Array = shot.get("flashlight", [])
	var events: Array = (shot.get("events", []) as Array).duplicate()
	events.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var seconds := float(shot.get("seconds", 10.0))
	var total := int(round(seconds * fps))
	var preview := bool(opts.get("preview", false))
	var expect: Dictionary = shot.get("expect", {})
	if preview:
		total = int(ceil(float(expect.get("t", seconds)) * fps)) + 1
	var inside_frames := 0
	var overlap_frames := 0
	var depth_min := 99.0
	var clip_start_frame := Engine.get_frames_drawn()
	var next_event := 0
	var dt := 1.0 / float(fps)
	for i in total:
		var t := float(i) * dt
		bridge.status = "shot %s: frame %d / %d" % [shot_name, i, total]
		# flashlight track (the last key at or before t)
		for key in torch_keys:
			if float(key["t"]) <= t:
				torch_on = bool(key.get("on", false))
		torch_level = move_toward(torch_level, 1.0 if torch_on else 0.0, dt / .18)
		# events
		while next_event < events.size() and float((events[next_event] as Dictionary)["t"]) <= t:
			var ev: Dictionary = events[next_event]
			next_event += 1
			if ev.has("flicker"):
				flicker_left = float(ev["flicker"])
			if ev.has("flash"):
				flash_left = float(ev["flash"])
			if ev.has("actor") and actors.has(str(ev["actor"])):
				_apply_event(actors[str(ev["actor"])] as Actor, ev, stage, actors, camera)
		# camera
		var cam := _camera_at(camera_keys, t, stage, actors)
		player.global_position = Vector3(cam["pos"].x, cam["pos"].y - EYE, cam["pos"].z)
		player.first_person_pivot.position.y = EYE
		player.velocity = Vector3.ZERO
		var dir: Vector3 = (cam["look"] as Vector3) - (cam["pos"] as Vector3)
		player._yaw = PlaytestFlythrough.yaw_for(dir.x, dir.z)
		player._pitch = PlaytestFlythrough.pitch_for(dir.normalized())
		player._apply_look_rotation()
		if cam.has("fov"):
			camera.fov = float(cam["fov"])
		# actors
		for key in actors:
			_step_actor(actors[key] as Actor, dt, space, player, camera)
		# lights
		var flick := 1.0
		if flicker_left > 0.0:
			flicker_left -= dt
			flick = 0.0 if (int(t * 18.0) % 3 != 0) else .7
		var torch_flick := 1.0
		if flash_left > 0.0:
			flash_left -= dt
			torch_flick = 0.0 if (int(t * 22.0) % 4 == 0) else 1.0
		lamp.light_energy = 1.1 * dark * flick
		torch.light_energy = torch_peak * torch_level * torch_flick
		if i % 45 == 0:
			PlaytestFlythrough._clear_hunters(scene, false)
		if clean and i % 30 == 0:
			PlaytestFlythrough._clean_scene(scene, keep)
		# inside-geometry gate (the camera sphere against everything but the actors, which have no collision)
		var overlap := PhysicsShapeQueryParameters3D.new()
		overlap.shape = camera_probe
		overlap.transform = Transform3D(Basis.IDENTITY, camera.global_position)
		overlap.exclude = [player.get_rid()]
		if not space.intersect_shape(overlap, 4).is_empty():
			inside_frames += 1
		var look := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 12.0)
		look.exclude = [player.get_rid()]
		var seen := space.intersect_ray(look)
		depth_min = minf(depth_min, 12.0 if seen.is_empty() else camera.global_position.distance_to(seen["position"] as Vector3))
		scene.set("_relay_inactivity_seconds", 0.0)
		scene.set("_party_afk_seconds", 0.0)
		await tree.process_frame
		frames += 1
	if preview:
		await RenderingServer.frame_post_draw
		var result := _check(expect, actors, camera, player, space, stage)
		var dir_path := ProjectSettings.globalize_path("res://.playtest/preview")
		DirAccess.make_dir_recursive_absolute(dir_path)
		var image := scene.get_viewport().get_texture().get_image()
		image.save_png("%s/%s.png" % [dir_path, shot_name])
		info["checks"] = result
		info["available"] = true
		info["preview"] = true
		info["shot"] = shot_name
		info["seconds"] = 0.0
		report["flythrough"] = info
		return {"outcome": "recorded", "game_seconds": 0.0, "frames": frames, "scenario_failure": ""}
	var clips := {}
	for key in actors:
		var a := actors[key] as Actor
		clips[key] = Array(a.anim.get_animation_list()) if a.anim != null else []
	info["actor_clips"] = clips
	info["inside_geometry_s"] = snappedf(float(inside_frames) / float(fps), .2)
	info["prop_overlap_s"] = snappedf(float(overlap_frames) / float(fps), .2)
	info["min_view_depth_m"] = snappedf(depth_min, .1)
	info["clip_frames"] = Engine.get_frames_drawn() - clip_start_frame
	info["clip_start_frame"] = clip_start_frame
	info["fps"] = fps
	info["seconds"] = snappedf(float(info["clip_frames"]) / float(fps), .1)
	info["available"] = true
	info["shot"] = shot_name
	report["flythrough"] = info
	return {"outcome": "recorded", "game_seconds": snappedf(float(frames) / float(fps), .1), "frames": frames, "scenario_failure": ""}


# ------------------------------------------------------------------------------------------------ stage
static func _floor_at(space: PhysicsDirectSpaceState3D, from: Vector3, player: Node, fallback_y: float) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0)
	ray.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(ray)
	return Vector3(from.x, (hit["position"] as Vector3).y if not hit.is_empty() else fallback_y, from.z)


static func _longest_run(space: PhysicsDirectSpaceState3D, from: Vector3, player: Node, min_run: float, hint_yaw: float) -> Vector3:
	var best := Vector3(0, 0, -1)
	var best_len := -1.0
	for k in 32:
		var angle := TAU * float(k) / 32.0
		var d := Vector3(sin(angle), 0, -cos(angle))
		var ray := PhysicsRayQueryParameters3D.create(from, from + d * 30.0)
		ray.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(ray)
		var length := 30.0 if hit.is_empty() else from.distance_to(hit["position"] as Vector3)
		if length > best_len + .01:
			best_len = length
			best = d
	return best


## First side opening along the stage run: {"d": distance of the corner's near wall edge, "s": +1 right / -1 left, "w": half hall width}.
## A numeric at-array may use "c" for forward: ["c", df, dr] = corner edge + df forward, side * (hall half width + dr) across.
static func _find_corner(space: PhysicsDirectSpaceState3D, stage: Dictionary, player: Node) -> Dictionary:
	var f: Vector3 = stage["f"]
	var r: Vector3 = stage["r"]
	var o: Vector3 = stage["o"] + Vector3.UP * 1.3
	var exclude := [(player as CollisionObject3D).get_rid()]
	var span := 0.0
	var ray := PhysicsRayQueryParameters3D.create(o, o + f * 40.0)
	ray.exclude = exclude
	var hit := space.intersect_ray(ray)
	span = 40.0 if hit.is_empty() else o.distance_to(hit["position"] as Vector3)
	for side in [1.0, -1.0]:
		var side_ray := PhysicsRayQueryParameters3D.create(o, o + r * side * 6.0)
		side_ray.exclude = exclude
		var side_hit := space.intersect_ray(side_ray)
		var w := 6.0 if side_hit.is_empty() else o.distance_to(side_hit["position"] as Vector3)
		if w > 3.5:
			continue
		var d := 4.0
		while d < span - 1.5:
			var p := o + f * d
			var q := PhysicsRayQueryParameters3D.create(p, p + r * side * (w + 3.0))
			q.exclude = exclude
			var qh := space.intersect_ray(q)
			var ql := w + 3.0 if qh.is_empty() else p.distance_to(qh["position"] as Vector3)
			if ql > w + 1.6:
				# refine the near edge backwards
				var edge := d
				while edge > d - .5:
					edge -= .05
					var pp := o + f * edge
					var qq := PhysicsRayQueryParameters3D.create(pp, pp + r * side * (w + 3.0))
					qq.exclude = exclude
					var qqh := space.intersect_ray(qq)
					if not qqh.is_empty() and pp.distance_to(qqh["position"] as Vector3) <= w + .4:
						break
				return {"d": snappedf(edge + .05, .01), "s": side, "w": snappedf(w, .01)}
			d += .25
	return {"d": span * .6, "s": 1.0, "w": 1.5, "fallback": true}


static func _pt(stage: Dictionary, arr: Array, height: float) -> Vector3:
	if arr.size() > 0 and arr[0] is String:
		return _stage_point(stage, [arr[0], arr[1], arr[2], arr[3] if arr.size() > 3 else height])
	return _stage_point(stage, [arr[0], arr[1], arr[2] if arr.size() > 2 else height])


## A walked corner of the flythrough route: a turn of 60+ degrees after a straight approach of 7+ m. Returns the frame 9 m before it and the
## approach direction, so the stage looks down the hall toward the corner.
static func _path_corner(track: PlaytestFlythrough.Track) -> Dictionary:
	var n := track.size()
	var k := 0
	while k < n - 1:
		if int(track.ground[k]) != 1:
			k += 1
			continue
		var back := k
		while back > 0 and int(track.ground[back]) == 1 and Vector2(track.pos[k].x - track.pos[back].x, track.pos[k].z - track.pos[back].z).length() < 9.0:
			back -= 1
		var ahead := k
		while ahead < n - 1 and int(track.ground[ahead]) == 1 and Vector2(track.pos[ahead].x - track.pos[k].x, track.pos[ahead].z - track.pos[k].z).length() < 3.0:
			ahead += 1
		var d_in := Vector2(track.pos[k].x - track.pos[back].x, track.pos[k].z - track.pos[back].z)
		var d_out := Vector2(track.pos[ahead].x - track.pos[k].x, track.pos[ahead].z - track.pos[k].z)
		if d_in.length() >= 7.0 and d_out.length() >= 2.0 and absf(rad_to_deg(d_in.angle_to(d_out))) >= 60.0:
			var fwd := Vector3(d_in.x, 0, d_in.y).normalized()
			return {"frame": back, "forward": fwd}
		k += 4
	return {}


static func _stage_point(stage: Dictionary, at: Array) -> Vector3:
	if at.size() > 0 and at[0] is String:
		var c: Dictionary = stage["corner"]
		at = [float(c["d"]) + float(at[1]), float(c["s"]) * (float(c["w"]) + float(at[2])) * (stage_r_sign(stage)), at[3] if at.size() > 3 else 0.0]
	var p: Vector3 = stage["o"] + (stage["f"] as Vector3) * float(at[0]) + (stage["r"] as Vector3) * float(at[1])
	p.y += float(at[2]) if at.size() > 2 else 0.0
	return p


# ------------------------------------------------------------------------------------------------ actors
static func _make_actor(scene: Node, key: String, spec: Dictionary, stage: Dictionary, space: PhysicsDirectSpaceState3D, player: Node) -> Actor:
	var actor := Actor.new()
	actor.key = key
	actor.hunter_id = String(spec.get("id", key))
	var identity := HunterRoster.get_identity(actor.hunter_id)
	var model := ModelSlot.instantiate_hunter(identity)
	if model == null:
		return null
	actor.root = Node3D.new()
	actor.root.name = "TrailerActor_" + key
	model.scale = Vector3.ONE * HunterRoster.scale_for(actor.hunter_id)
	actor.root.add_child(model)
	scene.add_child(actor.root)
	actor.model = model
	actor.anim = ModelSlot.find_animation_player(model)
	if actor.anim != null:
		NightWatchPoses.install(model, actor.anim, actor.hunter_id)
	actor.height = 1.72 * HunterRoster.scale_for(actor.hunter_id)
	var at: Array = spec.get("at", [8, 0])
	actor.pos = _pt(stage, at, 0.0)
	actor.pos = _floor_at(space, actor.pos + Vector3.UP * 1.3, player, actor.pos.y)
	actor.face_mode = spec.get("face", "away")
	actor.yaw = 0.0
	_play(actor, spec)
	if spec.has("tag"):
		_set_tag(actor, str(spec["tag"]))
	actor.root.visible = not bool(spec.get("hidden", false))
	return actor


static func _play(actor: Actor, spec: Dictionary) -> void:
	if actor.anim == null:
		return
	actor.posed = spec.has("pose")
	if spec.has("pose"):
		NightWatchPoses.play(actor.model, str(spec["pose"]), {"speed": float(spec.get("pose_speed", 1.0))})
	elif spec.has("clip"):
		var clip := str(spec["clip"])
		if actor.anim.has_animation(clip):
			actor.anim.speed_scale = float(spec.get("clip_speed", 1.0))
			actor.anim.play(clip, .2)


static func _set_tag(actor: Actor, text: String) -> void:
	if actor.tag == null:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = .0042
		label.font_size = 64
		label.outline_size = 14
		label.modulate = Color(.92, .92, .92, 0.0)
		label.outline_modulate = Color(0, 0, 0, 0.9)
		label.no_depth_test = true
		label.position = Vector3(0, actor.height + .32, 0)
		actor.root.add_child(label)
		actor.tag = label
	actor.tag.text = text
	actor.tag_goal = 1.0


static func _apply_event(actor: Actor, ev: Dictionary, stage: Dictionary, actors: Dictionary, camera: Camera3D) -> void:
	if bool(ev.get("hide", false)):
		actor.root.visible = false
	if bool(ev.get("show", false)):
		actor.root.visible = true
	if ev.has("face"):
		actor.face_mode = ev["face"]
	if ev.has("tag"):
		_set_tag(actor, str(ev["tag"]))
	if bool(ev.get("tag_off", false)):
		actor.tag_goal = 0.0
	if ev.has("move"):
		var to := _pt(stage, ev["move"], 0.0)
		actor.target = Vector3(to.x, actor.pos.y, to.z)
		actor.speed = float(ev.get("speed", 1.4))
		if not ev.has("face"):
			actor.face_mode = "heading"
	if ev.has("stop"):
		actor.target = Vector3(NAN, NAN, NAN)
		actor.speed = 0.0
	_play(actor, ev)


static func _step_actor(actor: Actor, dt: float, space: PhysicsDirectSpaceState3D, player: Node, camera: Camera3D) -> void:
	var moving := false
	if is_finite(actor.target.x):
		var to := Vector3(actor.target.x - actor.pos.x, 0, actor.target.z - actor.pos.z)
		if to.length() <= actor.speed * dt + .01:
			actor.pos.x = actor.target.x
			actor.pos.z = actor.target.z
			actor.target = Vector3(NAN, NAN, NAN)
			actor.speed = 0.0
		else:
			var step := to.normalized() * actor.speed * dt
			actor.pos.x += step.x
			actor.pos.z += step.z
			moving = true
			if String(actor.face_mode) == "heading":
				actor.yaw = lerp_angle(actor.yaw, atan2(-step.x, -step.z), clampf(dt * 10.0, 0.0, 1.0))
	if not (actor.face_mode is String and String(actor.face_mode) == "heading"):
		var want := actor.yaw
		var fm: Variant = actor.face_mode
		if fm is String and String(fm) == "camera":
			var d := camera.global_position - actor.pos
			want = atan2(-d.x, -d.z)
		elif fm is String and String(fm) == "away":
			want = actor.yaw
		elif fm is float or fm is int:
			want = deg_to_rad(float(fm))
		actor.yaw = lerp_angle(actor.yaw, want, clampf(dt * 8.0, 0.0, 1.0))
	var floor_hit := _floor_at(space, actor.pos + Vector3.UP * 1.0, player, actor.pos.y)
	actor.pos.y = floor_hit.y
	actor.root.global_position = actor.pos
	actor.root.rotation.y = actor.yaw
	# travel clip speed from the stride table, only while a move runs without a pose
	if moving and actor.anim != null:
		var preferred := "sprint" if actor.speed > 4.2 else ("chase" if actor.speed > 2.4 else "walk")
		var pick := HunterStride.choose(actor.hunter_id, preferred, actor.speed)
		if not actor.posed and actor.anim.has_animation(String(pick["clip"])):
			if actor.anim.current_animation != String(pick["clip"]):
				actor.anim.play(String(pick["clip"]), .15)
			actor.anim.speed_scale = float(pick["scale"])
	if actor.tag != null:
		actor.tag_alpha = move_toward(actor.tag_alpha, actor.tag_goal, dt / .4)
		actor.tag.modulate.a = actor.tag_alpha


# ------------------------------------------------------------------------------------------------ camera
static func stage_r_sign(_stage: Dictionary) -> float:
	return 1.0


static func _resolve(spec: Variant, stage: Dictionary, actors: Dictionary, default_h: float) -> Vector3:
	if spec is String:
		var parts := String(spec).split(":")
		var actor := actors.get(parts[0]) as Actor
		if actor != null:
			return actor.pos + Vector3.UP * (float(parts[1]) if parts.size() > 1 else actor.height * .8)
		return Vector3.ZERO
	var arr: Array = spec
	return _pt(stage, arr, default_h)


static func _camera_at(keys: Array, t: float, stage: Dictionary, actors: Dictionary) -> Dictionary:
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[keys.size() - 1]
	for k in keys.size():
		if float((keys[k] as Dictionary)["t"]) <= t:
			a = keys[k]
			b = keys[mini(k + 1, keys.size() - 1)]
	var span := float(b["t"]) - float(a["t"])
	var u := 0.0 if span <= 0.001 else clampf((t - float(a["t"])) / span, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) if String(b.get("ease", "smooth")) == "smooth" else u
	var pos := _resolve(a["at"], stage, actors, EYE).lerp(_resolve(b["at"], stage, actors, EYE), u)
	var look := _resolve(a["look"], stage, actors, EYE).lerp(_resolve(b["look"], stage, actors, EYE), u)
	var out := {"pos": pos, "look": look}
	if a.has("fov") or b.has("fov"):
		out["fov"] = lerpf(float(a.get("fov", b.get("fov", 75.0))), float(b.get("fov", a.get("fov", 75.0))), u)
	return out


# ------------------------------------------------------------------------------------------------ self-check (preview before the full render)
static func _bone_pos(actor: Actor, bone: String) -> Vector3:
	var node := actor.model.find_child(bone, true, false) as Node3D
	if node != null:
		return node.global_position
	for skel in actor.model.find_children("*", "Skeleton3D", true, false):
		var skeleton := skel as Skeleton3D
		var index := skeleton.find_bone(bone)
		if index >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
	return actor.pos + Vector3.UP * actor.height * .5


static func _seen(space: PhysicsDirectSpaceState3D, camera: Camera3D, player: Node, point: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, point)
	ray.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(ray)
	return hit.is_empty() or camera.global_position.distance_to(hit["position"] as Vector3) > camera.global_position.distance_to(point) - .08


static func _on_screen(camera: Camera3D, point: Vector3) -> bool:
	if camera.is_position_behind(point):
		return false
	var p := camera.unproject_position(point)
	var size := camera.get_viewport().get_visible_rect().size
	return p.x >= 0.0 and p.x <= size.x and p.y >= 0.0 and p.y <= size.y


static func _check(expect: Dictionary, actors: Dictionary, camera: Camera3D, player: Node, space: PhysicsDirectSpaceState3D, stage: Dictionary) -> Dictionary:
	var actor := actors.get(str(expect.get("actor", ""))) as Actor
	var rows: Array = []
	if actor == null:
		return {"pass": false, "rows": [{"name": "actor", "pass": false, "detail": "no such actor"}]}
	var cam_pos := camera.global_position
	# 1. faces the camera
	var forward := -actor.root.global_basis.z
	forward.y = 0.0
	var to_cam := cam_pos - actor.pos
	to_cam.y = 0.0
	var face_deg := rad_to_deg(forward.normalized().angle_to(to_cam.normalized()))
	if expect.has("face_camera_deg"):
		rows.append({"name": "faces camera", "pass": face_deg <= float(expect["face_camera_deg"]), "detail": "%.0f deg off (max %s)" % [face_deg, expect["face_camera_deg"]]})
	# 2. lean toward the open side of the corner
	var corner: Dictionary = stage["corner"]
	var open_dir: Vector3 = -(stage["r"] as Vector3) * float(corner["s"])   # the hall side, away from the wall the corner turns into
	var head := _bone_pos(actor, "Head")
	var pelvis := _bone_pos(actor, "Pelvis")
	var lean := (head - pelvis).dot(open_dir)
	if bool(expect.get("lean_open_side", false)):
		rows.append({"name": "leans to the open side", "pass": lean > .06, "detail": "head %.2f m toward the open side of the pelvis (needs > 0.06)" % lean})
	# 3. visible parts and torso fraction
	var parts := {"head": ["Head"], "chest": ["Chest"], "hand": ["L-Hand", "R-Hand"], "legs": ["L-Calf", "R-Calf", "L-Foot", "R-Foot"]}
	var want: Dictionary = expect.get("visible_parts", {})
	var vis := {}
	for part in parts:
		var any := false
		for bone in parts[part]:
			var point := _bone_pos(actor, str(bone))
			if _seen(space, camera, player, point) and _on_screen(camera, point):
				any = true
		vis[part] = any
	for part in want:
		rows.append({"name": "%s %s" % [part, "visible" if bool(want[part]) else "hidden"], "pass": bool(vis.get(part, false)) == bool(want[part]), "detail": "seen=%s" % vis.get(part)})
	if expect.has("torso_visible"):
		var chest := _bone_pos(actor, "Chest")
		var side := camera.global_basis.x
		var seen_count := 0
		var total := 0
		for a in 5:
			for b in 5:
				var point := pelvis.lerp(chest, float(a) / 4.0) + side * (float(b) / 4.0 - .5) * .5
				total += 1
				if _seen(space, camera, player, point) and _on_screen(camera, point):
					seen_count += 1
		var fraction := float(seen_count) / float(total)
		var range_: Array = expect["torso_visible"]
		rows.append({"name": "torso visible", "pass": fraction >= float(range_[0]) and fraction <= float(range_[1]), "detail": "%.0f%% (wanted %d-%d%%)" % [fraction * 100.0, int(float(range_[0]) * 100), int(float(range_[1]) * 100)]})
	# 4. no hunter mesh inside walls (body points, small spheres)
	if bool(expect.get("no_wall_intersection", false)):
		var sphere := SphereShape3D.new()
		sphere.radius = .1
		var hand_sphere := SphereShape3D.new()
		hand_sphere.radius = .03   # a hand resting ON the wall edge is the point of the shot
		var bad: Array = []
		for bone in ["Head", "Chest", "Belly", "Pelvis", "L-Hand", "R-Hand", "L-Forearm", "R-Forearm", "L-Foot", "R-Foot", "L-Calf", "R-Calf"]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = hand_sphere if bone.ends_with("Hand") else sphere
			query.transform = Transform3D(Basis.IDENTITY, _bone_pos(actor, bone))
			query.exclude = [(player as CollisionObject3D).get_rid()]
			if not space.intersect_shape(query, 1).is_empty():
				bad.append(bone)
		rows.append({"name": "no wall intersection", "pass": bad.is_empty(), "detail": "inside walls: %s" % [bad]})
	# 5. screen size of the visible subject (head to the lowest visible, on-screen sample), as a fraction of the frame height
	if expect.has("screen_fraction"):
		var top := camera.unproject_position(_bone_pos(actor, "Head") + Vector3.UP * .25).y
		var low := top
		for bone in ["Chest", "Belly", "Pelvis", "L-Calf", "R-Calf", "L-Foot", "R-Foot"]:
			var point := _bone_pos(actor, bone)
			if _seen(space, camera, player, point) and _on_screen(camera, point):
				low = maxf(low, camera.unproject_position(point).y)
		var frac := (low - top) / camera.get_viewport().get_visible_rect().size.y
		var limits: Array = expect["screen_fraction"]
		rows.append({"name": "screen size", "pass": frac >= float(limits[0]) and frac <= float(limits[1]), "detail": "%.0f%% of frame height (wanted %d-%d%%)" % [frac * 100.0, int(float(limits[0]) * 100), int(float(limits[1]) * 100)]})
	var ok := true
	for row in rows:
		ok = ok and bool(row["pass"])
	var names: Array = []
	for bone in ["Head", "Pelvis", "Chest", "L-Hand", "L-Foot"]:
		names.append("%s=%s" % [bone, actor.model.find_child(bone, true, false) != null])
	return {"pass": ok, "rows": rows, "bones": names}
