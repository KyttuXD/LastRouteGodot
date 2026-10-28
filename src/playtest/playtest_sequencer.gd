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

## The shot's own camera track and stage, for authoring facing "toward the shot camera" once (never a live look-at of whatever camera renders).
static var _keys: Array = []
static var _stage: Dictionary = {}
static var _actors: Dictionary = {}
static var _scene: Node
static var _smooth := {}   # bone -> {last: Quaternion, max: float} over the shot's smoothness window
static var _smooth_window := Vector2(-1, -1)


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
	var authored_yaw := 0.0
	var head_cfg: Dictionary = {}
	var head_yaw := 0.0
	var head_pitch := 0.0
	var clock := 0.0
	var lean_deg := 0.0
	var blend_snap: Dictionary = {}   # bone -> [Quaternion, Vector3] at the moment a pose changed, eased into the new pose by hand
	var blend_t0 := -1.0
	var last_pose: Dictionary = {}   # the bones as the pose (and blend) left them last frame, before any flinch layer
	var blend_dur := .3
	var waist := Vector2.ZERO        # extra Belly / Chest roll (degrees, for a corner opening on the camera's right; mirrored otherwise)
	var waist_w := 0.0
	var rest_legs: Dictionary = {}   # leg bones at rest (straight, feet under the hips), blended in with the lean
	var waist_goal := 0.0
	var waist_rate := 1.0 / .8
	var react: Dictionary = {}   # {t0, dur, hold, release, away_yaw, arm, hunch}: a fast eased flinch layered on the pose


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
	var grid_corner := {}
	if bool(shot.get("corner_grid", false)):
		grid_corner = _grid_corner(PlaytestFlythrough.Sampler.new(generator, int(info.get("level", 0))), track, float(shot.get("camera_back", 6.5)))
		if grid_corner.is_empty():
			report["flythrough"] = {"area": shot_name, "available": false, "reason": "no corridor corner (two perpendicular corridors) near the %s route" % area}
			return {"scenario_failure": "no corridor corner found", "outcome": "error", "game_seconds": 0.0, "frames": 0}
		var cam2: Vector2 = grid_corner["camera"]
		origin_eye = Vector3(cam2.x, origin_eye.y, cam2.y)
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
	if not grid_corner.is_empty():
		var f2: Vector2 = grid_corner["F"]
		forward = Vector3(f2.x, 0.0, f2.y)
	if forward == Vector3.ZERO:
		forward = _longest_run(space, Vector3(origin_eye.x, floor_origin.y + 1.3, origin_eye.z), player, float(shot.get("min_run", 10.0)), track.yaw[0])
	var right := forward.cross(Vector3.UP)
	var stage := {"o": floor_origin, "f": forward, "r": right}
	if grid_corner.is_empty():
		stage["corner"] = _find_corner(space, stage, player)
	else:
		# a real corridor corner from the level grid: d/w place the wall-edge VERTEX in stage coordinates, s says which side corridor B opens
		var r2: Vector2 = grid_corner["R"]
		var r3 := Vector3(r2.x, 0.0, r2.y)
		var v2: Vector2 = _measured_edge(space, player, grid_corner, floor_origin.y + 1.2)
		info["edge_grid"] = [snappedf((grid_corner["vertex"] as Vector2).x, .01), snappedf((grid_corner["vertex"] as Vector2).y, .01)]
		info["edge_measured"] = [snappedf(v2.x, .01), snappedf(v2.y, .01)]
		var rel := Vector3(v2.x, floor_origin.y, v2.y) - floor_origin
		stage["corner"] = {"d": snappedf(rel.dot(forward), .01), "w": snappedf(rel.dot(r3), .01), "s": signf(r3.dot(right)), "a_far": grid_corner["a_far"],
			"grid": true, "vertex": [snappedf(v2.x, .01), snappedf(v2.y, .01)], "b_cells": grid_corner["b_cells"]}
	info["corner"] = stage["corner"]
	info["stage_forward"] = [snappedf(forward.x, .01), snappedf(forward.z, .01)]

	# actors
	var actors: Dictionary = {}
	_keys = shot.get("camera", [])
	_stage = stage
	_actors = actors
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
	if shot.has("corner_light") and (stage["corner"] as Dictionary).has("vertex"):
		# one dim practical light near the corner, so the peek reads in the dark before the flashlight
		var cl: Dictionary = shot["corner_light"]
		var vx: Array = stage["corner"]["vertex"]
		var corner_lamp := OmniLight3D.new()
		corner_lamp.light_energy = float(cl.get("energy", .6))
		corner_lamp.omni_range = float(cl.get("range", 4.0))
		corner_lamp.light_color = Color(cl.get("color", "#ffd9a8"))
		corner_lamp.shadow_enabled = true
		scene.add_child(corner_lamp)
		var off: Array = cl.get("at", [-0.6, -0.5, 2.3])
		corner_lamp.global_position = Vector3(float(vx[0]), floor_origin.y + float(off[2]), float(vx[1])) + forward * float(off[0]) + right * float((stage["corner"] as Dictionary)["s"]) * float(off[1])
	var torch_on := false
	var torch_level := 0.0
	var flicker_left := 0.0
	var flash_left := 0.0
	var clean := bool(opts.get("clean", true))
	var keep := String(opts.get("keep", "")).split(",", false)
	var camera_probe := SphereShape3D.new()
	camera_probe.radius = .2
	var camera_keys: Array = shot.get("camera", [])
	_keys = camera_keys
	_stage = stage
	_actors = actors
	var torch_keys: Array = shot.get("flashlight", [])
	var events: Array = (shot.get("events", []) as Array).duplicate()
	events.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var seconds := float(shot.get("seconds", 10.0))
	var total := int(round(seconds * fps))
	var preview := bool(opts.get("preview", false))
	var expect: Dictionary = shot.get("expect", {})
	var beats: Array = shot.get("expects", [expect] if not expect.is_empty() else [])
	beats.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var beat_index := 0
	var beat_reports: Array = []
	if preview and not beats.is_empty():
		total = int(ceil(float((beats[beats.size() - 1] as Dictionary)["t"]) * fps)) + 2
	var world_dim := float(shot.get("world_dim", 1.0))
	var steps: Array = []
	_scene = scene
	_smooth.clear()
	var sm: Dictionary = shot.get("smooth", {})
	_smooth_window = Vector2(float(sm.get("from", -1.0)), float(sm.get("to", -1.0))) if not sm.is_empty() else Vector2(-1, -1)
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
			if ev.has("game_torch"):
				# the game's own flashlight (same SpotLight and viewmodel-less beam as gameplay) with its click
				player.call("_set_flashlight", bool(ev["game_torch"]))
				Sound.light_switch(0.0, 1.0)
			if ev.has("steps"):
				var sp: Dictionary = ev["steps"]
				for n in int(sp.get("count", 10)):
					var fade := 1.0 - float(n) / float(maxi(int(sp.get("count", 10)), 1)) if bool(sp.get("fade", true)) else 1.0
					steps.append({"t": t + float(n) * float(sp.get("interval", .25)), "vol": float(sp.get("volume", .12)) * fade, "pan": float(sp.get("pan", 0.0))})
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
		# footsteps (the game's own hunter footstep sound), fading with distance
		while not steps.is_empty() and float((steps[0] as Dictionary)["t"]) <= t:
			var st: Dictionary = steps.pop_front()
			Sound.hunter_footstep(float(st["pan"]), float(st["vol"]), "")
		if world_dim < .999 and i % 20 == 0:
			_dim_world(scene, player, camera, [lamp, torch], world_dim)
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
		if preview and beat_index < beats.size() and t >= float((beats[beat_index] as Dictionary)["t"]):
			await RenderingServer.frame_post_draw
			var beat: Dictionary = beats[beat_index]
			var snap := scene.get_viewport().get_texture().get_image()
			var snap_dir := ProjectSettings.globalize_path("res://.playtest/preview")
			DirAccess.make_dir_recursive_absolute(snap_dir)
			var label := str(beat.get("label", str(beat_index)))
			snap.save_png("%s/%s_%s.png" % [snap_dir, shot_name, label])
			var one := _check(beat, actors, camera, player, space, stage, snap)
			if beat.has("pixels"):
				var px := await _pixel_check(scene, camera, actors.get(str(beat.get("actor", ""))) as Actor, beat["pixels"], "%s/%s_%s_mask.png" % [snap_dir, shot_name, label])
				(one["rows"] as Array).append_array(px)
				for row in px:
					one["pass"] = bool(one["pass"]) and bool(row["pass"])
			one["label"] = label
			beat_reports.append(one)
			beat_index += 1
		await tree.process_frame
		frames += 1
	if preview and not beat_reports.is_empty():
		var rows_all: Array = []
		var all_ok := true
		for one in beat_reports:
			all_ok = all_ok and bool(one["pass"])
			for row in one["rows"]:
				var r2: Dictionary = (row as Dictionary).duplicate()
				r2["name"] = "[%s] %s" % [one["label"], r2["name"]]
				rows_all.append(r2)
		info["checks"] = {"pass": all_ok, "rows": rows_all}
		info["available"] = true
		info["preview"] = true
		info["shot"] = shot_name
		info["seconds"] = 0.0
		report["flythrough"] = info
		return {"outcome": "recorded", "game_seconds": 0.0, "frames": frames, "scenario_failure": ""}
	if preview:
		await RenderingServer.frame_post_draw
		var result := _check(expect, actors, camera, player, space, stage, null)
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


## A real corridor corner from the level grid (1 m cells), near the walked route: corridor A runs straight along F for 10+ cells into a junction
## where corridor B leaves sideways along R. The cells of A's R-side wall run straight up to the junction, B's near wall continues 4 cells,
## so the block between them is a solid corner with one vertical edge. Returns that edge (the VERTEX, world xz), F, R, the camera cell in A
## `back` metres before the edge, and A's free width on the far side at the camera (for an off-centre camera that sees the edge at an angle).
static func _grid_corner(grid: PlaytestFlythrough.Sampler, track: PlaytestFlythrough.Track, back: float) -> Dictionary:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var seen := {}
	var best := {}
	var best_score := -1e9
	var k := 0
	while k < track.size():
		if int(track.ground[k]) != 1:
			k += 15
			continue
		var around := Vector2i(floori(track.pos[k].x), floori(track.pos[k].z))
		k += 15
		for dz in range(-8, 9):
			for dx in range(-8, 9):
				var j := around + Vector2i(dx, dz)
				if seen.has(j) or not grid.open(j.x, j.y):
					continue
				seen[j] = true
				for f in dirs:
					for r in [Vector2i(f.y, -f.x), Vector2i(-f.y, f.x)]:
						var found := _corner_at(grid, j, f, r, back)
						if found.is_empty():
							continue
						if float(found["score"]) > best_score:
							best_score = float(found["score"])
							best = found
		if not best.is_empty() and best_score > 0.0:
			break
	return best


## The grid says where the corner block's cells are; the wall faces themselves sit inside the cells (thin walls, pilasters). Rays find the two
## real faces next to the grid vertex: corridor A's wall face (cast toward R from inside A, just short of the junction) and corridor B's near
## wall face (cast toward -F from inside B, just past the edge). Their crossing is the true vertical edge.
static func _measured_edge(space: PhysicsDirectSpaceState3D, player: Node, corner: Dictionary, y: float) -> Vector2:
	var v: Vector2 = corner["vertex"]
	var f: Vector2 = corner["F"]
	var r: Vector2 = corner["R"]
	var exclude := [(player as CollisionObject3D).get_rid()]
	var a_lat := 0.0
	var b_fwd := 0.0
	var a_hits := 0
	var b_hits := 0
	# A's face: several rays from A's interior toward R, 0.15-0.45 m before the edge (the face right at the corner, not a pilaster further back)
	for back in [.15, .3, .45]:
		var from2: Vector2 = v - f * back - r * 1.2
		var q := PhysicsRayQueryParameters3D.create(Vector3(from2.x, y, from2.y), Vector3(from2.x + r.x * 2.4, y, from2.y + r.y * 2.4))
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			a_lat += (Vector2(hp.x, hp.z) - v).dot(r)
			a_hits += 1
	# B's near face: rays from B's interior toward -F, 0.15-0.45 m past the edge
	for over in [.15, .3, .45]:
		var from_b: Vector2 = v + r * over + f * 1.2
		var qb := PhysicsRayQueryParameters3D.create(Vector3(from_b.x, y, from_b.y), Vector3(from_b.x - f.x * 2.4, y, from_b.y - f.y * 2.4))
		qb.exclude = exclude
		var hb := space.intersect_ray(qb)
		if not hb.is_empty():
			var hpb: Vector3 = hb["position"]
			b_fwd += (Vector2(hpb.x, hpb.z) - v).dot(f)
			b_hits += 1
	var lat := a_lat / float(a_hits) if a_hits > 0 else 0.0
	var fwd := b_fwd / float(b_hits) if b_hits > 0 else 0.0
	return v + r * lat + f * fwd


static func _corner_at(grid: PlaytestFlythrough.Sampler, j: Vector2i, f: Vector2i, r: Vector2i, back: float) -> Dictionary:
	var cam_k := int(ceil(back))
	# A: a straight open centre line well past the camera
	for k in range(0, cam_k + 3):
		if not grid.open(j.x - f.x * k, j.y - f.y * k):
			return {}
	# A's R-side wall: the first closed cell beside the row just before the junction, half width at most 3 cells
	var w_r := 0
	for jj in range(1, 4):
		var c := j - f + r * jj
		if not grid.open(c.x, c.y):
			w_r = jj
			break
	if w_r == 0:
		return {}
	# that wall is straight for 5 rows back (open inside, closed at w_r): the occluding face
	for k in range(1, 6):
		for jj in range(0, w_r):
			var inside := j - f * k + r * jj
			if not grid.open(inside.x, inside.y):
				return {}
		var wall := j - f * k + r * w_r
		if grid.open(wall.x, wall.y):
			return {}
	# B: the junction row runs open 4+ cells past A's wall line
	for jj in range(0, w_r + 4):
		var b := j + r * jj
		if not grid.open(b.x, b.y):
			return {}
	# B's near wall continues 4 cells (a solid corner block, not a door jamb)
	for jj in range(w_r, w_r + 4):
		var nb := j - f + r * jj
		if grid.open(nb.x, nb.y):
			return {}
	# B is a corridor: its far wall within 3 rows (prefer narrow)
	var b_width := 0
	for kk in range(1, 4):
		var far := j + f * kk + r * (w_r + 2)
		if not grid.open(far.x, far.y):
			b_width = kk
			break
	if b_width == 0:
		return {}
	# camera row: A's free width on the far (-R) side
	var cam_cell := j - f * cam_k
	var a_far := 0.5
	for jj in range(1, 5):
		var fc := cam_cell - r * jj
		if not grid.open(fc.x, fc.y):
			a_far = float(jj) - .5
			break
	var fv := Vector2(f.x, f.y)
	var rv := Vector2(r.x, r.y)
	var block := j - f + r * w_r
	var vertex := Vector2(block.x + .5, block.y + .5) + fv * .5 - rv * .5
	var camera := Vector2(j.x + .5, j.y + .5) - fv * float(cam_k)
	var score := 10.0 - float(b_width) * 2.0 - float(w_r) + a_far
	return {"vertex": vertex, "F": fv, "R": rv, "camera": camera, "a_far": a_far - .35, "b_cells": b_width, "w_r": w_r, "junction": j, "score": score}


static func _stage_point(stage: Dictionary, at: Array) -> Vector3:
	if at.size() > 0 and at[0] is String and String(at[0]) == "N":
		# ["N", metres back from the corner edge, fraction of the way from A's centre line to the corner's own wall, height]: a camera on the
		# corner's side of corridor A, looking along that wall, so only what crosses the wall plane shows
		var cn: Dictionary = stage["corner"]
		at = [float(cn["d"]) - float(at[1]), float(cn["s"]) * float(cn["w"]) * float(at[2]), at[3] if at.size() > 3 else 0.0]
	elif at.size() > 0 and at[0] is String and String(at[0]) == "A":
		# ["A", metres back from the corner edge, fraction of corridor A's free width on the far side, height]: the camera spot in corridor A
		var ca: Dictionary = stage["corner"]
		at = [float(ca["d"]) - float(at[1]), float(ca["s"]) * -float(ca.get("a_far", 1.0)) * float(at[2]), at[3] if at.size() > 3 else 0.0]
	elif at.size() > 0 and at[0] is String:
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
	for bone in ["L-Thigh", "R-Thigh", "L-Calf", "R-Calf", "L-Foot", "R-Foot"]:
		var leg := model.find_child(bone, true, false) as Node3D
		if leg != null:
			actor.rest_legs[bone] = leg.quaternion
	var pelvis_node := model.find_child("Pelvis", true, false) as Node3D
	if pelvis_node != null:
		actor.rest_legs["@pelvis_pos"] = pelvis_node.position
	actor.height = 1.72 * HunterRoster.scale_for(actor.hunter_id)
	var at: Array = spec.get("at", [8, 0])
	actor.pos = _pt(stage, at, 0.0)
	actor.pos = _floor_at(space, actor.pos + Vector3.UP * 1.3, player, actor.pos.y)
	actor.face_mode = spec.get("face", "away")
	actor.yaw = 0.0
	actor.head_cfg = spec.get("head", {})
	actor.lean_deg = float(spec.get("lean_deg", 0.0))
	if actor.anim != null:
		actor.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_resolve_face(actor, 0.0)
	_play(actor, spec)
	if spec.has("tag"):
		_set_tag(actor, str(spec["tag"]))
	actor.root.visible = not bool(spec.get("hidden", false))
	return actor


## "camera" / "shot_camera": turn toward where the SHOT camera is at time t, decided once here from the shot file; the actor keeps that heading.
static func _resolve_face(actor: Actor, t: float) -> void:
	if actor.face_mode is String and (String(actor.face_mode) == "camera" or String(actor.face_mode) == "shot_camera") and not _keys.is_empty():
		var cam := _camera_at(_keys, t, _stage, _actors)
		var d: Vector3 = (cam["pos"] as Vector3) - actor.pos
		actor.face_mode = rad_to_deg(atan2(-d.x, -d.z))
	if actor.face_mode is float or actor.face_mode is int:
		actor.authored_yaw = deg_to_rad(float(actor.face_mode))


static func _play(actor: Actor, spec: Dictionary) -> void:
	if actor.anim == null:
		return
	if spec.has("pose") and str(spec["pose"]) == "peek_auto":
		# lean toward the open side: peek_right for a corner whose corridor B opens on the camera's right, peek_left for the mirror
		spec = spec.duplicate()
		spec["pose"] = "peek_right" if float((_stage.get("corner", {}) as Dictionary).get("s", 1.0)) > 0.0 else "peek_left"
	if spec.has("pose"):
		actor.posed = true
		_crossfade(actor, float(spec.get("blend", .3)))
		NightWatchPoses.play(actor.model, str(spec["pose"]), {"speed": float(spec.get("pose_speed", 1.0)), "blend": 0.0})
	elif spec.has("clip"):
		var clip := str(spec["clip"])
		if actor.anim.has_animation(clip):
			actor.posed = false
			_crossfade(actor, float(spec.get("blend", .25)))
			actor.anim.speed_scale = float(spec.get("clip_speed", 1.0))
			actor.anim.play(clip, 0.0)


## Every pose or clip change crossfades HERE, eased, from the exact bones as they stood last frame (the AnimationPlayer itself cuts):
## its own blend popped by up to 40 degrees in one frame when driven by manual advance().
static func _crossfade(actor: Actor, seconds: float) -> void:
	actor.blend_snap = actor.last_pose.duplicate()
	actor.blend_t0 = actor.clock
	actor.blend_dur = seconds


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
		_resolve_face(actor, float(ev.get("t", 0.0)))
	if ev.has("waist"):
		var wv: Array = ev["waist"]
		actor.waist = Vector2(float(wv[0]), float(wv[1]))
		actor.waist_goal = 1.0
		actor.waist_rate = 1.0 / maxf(float(ev.get("waist_in", .8)), .05)
	if ev.has("waist_off"):
		actor.waist_goal = 0.0
		actor.waist_rate = 1.0 / maxf(float(ev["waist_off"]), .05)
	if ev.has("react"):
		var r: Dictionary = (ev["react"] as Dictionary).duplicate()
		r["t0"] = actor.clock
		actor.react = r
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
			if str(actor.face_mode) == "heading":
				actor.yaw = lerp_angle(actor.yaw, atan2(-step.x, -step.z), clampf(dt * 10.0, 0.0, 1.0))
	if not (actor.face_mode is String and String(actor.face_mode) == "heading"):
		var want := actor.yaw
		var fm: Variant = actor.face_mode
		if fm is String and String(fm) == "away":
			want = actor.yaw
		elif fm is float or fm is int:
			want = deg_to_rad(float(fm))
		actor.yaw = lerp_angle(actor.yaw, want, clampf(dt * 8.0, 0.0, 1.0))
	var floor_hit := _floor_at(space, actor.pos + Vector3.UP * 1.0, player, actor.pos.y)
	actor.pos.y = floor_hit.y
	actor.root.global_position = actor.pos
	actor.root.rotation.y = actor.yaw
	if absf(actor.lean_deg) > .01 and _stage.has("corner"):
		var c: Dictionary = _stage["corner"]
		var open_dir: Vector3 = -(_stage["r"] as Vector3) * float(c["s"])
		actor.root.global_basis = Basis(Vector3.UP.cross(open_dir).normalized(), deg_to_rad(actor.lean_deg)) * Basis(Vector3.UP, actor.yaw)
	# travel clip speed from the stride table, only while a move runs without a pose
	if moving and actor.anim != null:
		var preferred := "sprint" if actor.speed > 4.2 else ("chase" if actor.speed > 2.4 else "walk")
		var pick := HunterStride.choose(actor.hunter_id, preferred, actor.speed)
		if not actor.posed and actor.anim.has_animation(String(pick["clip"])):
			if actor.anim.current_animation != String(pick["clip"]):
				_crossfade(actor, .2)
				actor.anim.play(String(pick["clip"]), 0.0)
			actor.anim.speed_scale = float(pick["scale"])
	if actor.anim != null:
		actor.anim.advance(dt)
	actor.clock += dt
	_apply_pose_blend(actor)
	for bone in NightWatchPoses.BONES:
		var pn := actor.model.find_child(bone, true, false) as Node3D
		if pn != null:
			actor.last_pose[bone] = [pn.quaternion, pn.position]
	_apply_waist(actor, dt)
	_apply_react(actor)
	_track_smooth(actor)
	if not actor.head_cfg.is_empty():
		var head := actor.model.find_child("Head", true, false) as Node3D
		if head != null:
			_apply_head(actor, head, dt, camera.global_position)
	if actor.tag != null:
		actor.tag_alpha = move_toward(actor.tag_alpha, actor.tag_goal, dt / .4)
		actor.tag.modulate.a = actor.tag_alpha


static func _apply_pose_blend(actor: Actor) -> void:
	if actor.blend_snap.is_empty() or actor.blend_t0 < 0.0:
		return
	var u := clampf((actor.clock - actor.blend_t0) / maxf(actor.blend_dur, .05), 0.0, 1.0)
	var w := u * u * (3.0 - 2.0 * u)
	for bone in actor.blend_snap:
		var node := actor.model.find_child(str(bone), true, false) as Node3D
		if node == null:
			continue
		var snap: Array = actor.blend_snap[bone]
		node.quaternion = (snap[0] as Quaternion).slerp(node.quaternion, w)
		node.position = (snap[1] as Vector3).lerp(node.position, w)
	if u >= 1.0:
		actor.blend_snap.clear()


## The lean out from behind the corner: a bend at the waist (Belly, then Chest), eased in and out, so the legs and hips stay planted behind the
## wall while the head and upper torso cross the edge. Mirrored with the corner side.
static func _apply_waist(actor: Actor, dt: float) -> void:
	actor.waist_w = move_toward(actor.waist_w, actor.waist_goal, dt * actor.waist_rate)
	if actor.waist_w <= 0.0 or actor.waist == Vector2.ZERO:
		return
	var w := actor.waist_w * actor.waist_w * (3.0 - 2.0 * actor.waist_w)
	var side := float((_stage.get("corner", {}) as Dictionary).get("s", 1.0))
	var belly := actor.model.find_child("Belly", true, false) as Node3D
	var chest := actor.model.find_child("Chest", true, false) as Node3D
	if belly != null:
		belly.quaternion = NightWatchPoses.key_quaternion(Vector3(0.0, 0.0, actor.waist.x * side) * w) * belly.quaternion
	if chest != null:
		chest.quaternion = NightWatchPoses.key_quaternion(Vector3(0.0, 0.0, actor.waist.y * side) * w) * chest.quaternion
	# planted: the legs straighten under the hips while she leans, so no foot slides out past the edge
	for bone in actor.rest_legs:
		if str(bone) == "@pelvis_pos":
			# the peek pose slides the hips toward the open side: keep them over the planted feet, behind the wall
			var pelvis := actor.model.find_child("Pelvis", true, false) as Node3D
			if pelvis != null:
				pelvis.position = pelvis.position.lerp(actor.rest_legs[bone] as Vector3, w)
			continue
		var leg := actor.model.find_child(str(bone), true, false) as Node3D
		if leg != null:
			leg.quaternion = leg.quaternion.slerp(actor.rest_legs[bone] as Quaternion, w)


## Eased weight 0..1 of the flinch: snaps in with an ease-out over `dur`, holds, then releases over `release`.
static func _react_weight(actor: Actor) -> float:
	if actor.react.is_empty():
		return 0.0
	var age := actor.clock - float(actor.react["t0"])
	var dur := maxf(float(actor.react.get("dur", .2)), .05)
	var hold := float(actor.react.get("hold", .3))
	var release := maxf(float(actor.react.get("release", .3)), .05)
	if age < 0.0:
		return 0.0
	if age < dur:
		var u := age / dur
		# half sine ease-out, half smoothstep: fast, but with no big first-frame step
		return .5 * sin(u * PI * .5) + .5 * (u * u * (3.0 - 2.0 * u))
	if age < dur + hold:
		return 1.0
	var v := clampf((age - dur - hold) / release, 0.0, 1.0)
	return 1.0 - (v * v * (3.0 - 2.0 * v))


## Arm(s) up over the face and a hunch, on top of the animated pose (local rotations, relative to what the pose just wrote).
static func _apply_react(actor: Actor) -> void:
	var w := _react_weight(actor)
	if w <= 0.0:
		return
	var side := str(actor.react.get("arm", "R"))
	if side == "auto":
		# the near arm: facing the camera from a corner on the camera's right, her right side is toward the edge
		side = "R" if float((_stage.get("corner", {}) as Dictionary).get("s", 1.0)) > 0.0 else "L"
	# the arm_z sign follows the arm, not the corner side
	var arm_sign := 1.0 if side == "R" else -1.0
	var arms := [side] if side != "both" else ["L", "R"]
	for a in arms:
		var sg := 1.0 if a == "R" else -1.0
		var arm := actor.model.find_child("%s-Arm" % a, true, false) as Node3D
		var fore := actor.model.find_child("%s-Forearm" % a, true, false) as Node3D
		if arm != null:
			arm.quaternion = NightWatchPoses.key_quaternion(Vector3(float(actor.react.get("arm_x", 110.0)), 0.0, float(actor.react.get("arm_z", 28.0)) * sg) * w) * arm.quaternion
		if fore != null:
			fore.quaternion = NightWatchPoses.key_quaternion(Vector3(float(actor.react.get("fore_x", 100.0)), 0.0, 0.0) * w) * fore.quaternion
	var chest := actor.model.find_child("Chest", true, false) as Node3D
	if chest != null:
		chest.quaternion = NightWatchPoses.key_quaternion(Vector3(float(actor.react.get("hunch", 14.0)), 0.0, 0.0) * w) * chest.quaternion


## Per-frame bone rotation deltas inside the shot's smoothness window (the self-check reports the worst single-frame step).
static func _track_smooth(actor: Actor) -> void:
	if _smooth_window.x < 0.0:
		return
	for bone in ["Head", "R-Arm", "R-Forearm", "L-Arm", "L-Forearm", "Chest"]:
		var node := actor.model.find_child(bone, true, false) as Node3D
		if node == null:
			continue
		var q := node.quaternion
		var entry: Dictionary = _smooth.get(bone, {"last": q, "max": 0.0})
		var step := rad_to_deg((entry["last"] as Quaternion).angle_to(q))
		if _smooth.has(bone) and actor.clock >= _smooth_window.x and actor.clock <= _smooth_window.y:
			if step > float(entry["max"]):
				entry["max"] = step
				entry["at"] = snappedf(actor.clock, .01)
		entry["last"] = q
		_smooth[bone] = entry


## Head only: calm (a breath, no wandering) and turned toward the SHOT camera within natural neck limits, eased. The body keeps its authored pose.
static func _apply_head(actor: Actor, head: Node3D, dt: float, cam_pos: Vector3) -> void:
	var cfg := actor.head_cfg
	var body_fwd := Vector3(-sin(actor.yaw), 0.0, -cos(actor.yaw))
	var to_cam := cam_pos - head.global_position
	var flat := Vector3(to_cam.x, 0.0, to_cam.z)
	var want_yaw := 0.0
	var want_pitch := 0.0
	if flat.length() > .1:
		want_yaw = clampf(body_fwd.signed_angle_to(flat.normalized(), Vector3.UP), -deg_to_rad(float(cfg.get("max_yaw", 60.0))), deg_to_rad(float(cfg.get("max_yaw", 60.0))))
		want_pitch = clampf(atan2(to_cam.y, flat.length()), -deg_to_rad(float(cfg.get("max_pitch", 30.0))), deg_to_rad(float(cfg.get("max_pitch", 30.0))))
	var k := clampf(dt * float(cfg.get("ease", 4.0)), 0.0, 1.0)
	actor.head_yaw = lerpf(actor.head_yaw, want_yaw, k)
	actor.head_pitch = lerpf(actor.head_pitch, want_pitch, k)
	var rw := _react_weight(actor)
	if rw > 0.0:
		# snap the face away from the light: the look-at gives way to the flinch, never a pop (the weight is eased)
		var away := deg_to_rad(float(actor.react.get("away_yaw", 55.0)) * float((_stage.get("corner", {}) as Dictionary).get("s", 1.0)))
		actor.head_yaw = lerpf(actor.head_yaw, away, rw)
		actor.head_pitch = lerpf(actor.head_pitch, deg_to_rad(float(actor.react.get("away_pitch", -12.0))), rw)
	var breath := sin(actor.clock * 1.7) * deg_to_rad(float(cfg.get("sway", 0.8)))
	var basis := Basis(Vector3.UP, actor.yaw + actor.head_yaw) * Basis(Vector3.RIGHT, actor.head_pitch + breath) * Basis(Vector3(0, 0, -1), deg_to_rad(float(cfg.get("tilt", 0.0))))
	head.global_basis = basis.scaled_local(head.global_basis.get_scale())


# ------------------------------------------------------------------------------------------------ camera
static func stage_r_sign(_stage: Dictionary) -> float:
	return 1.0


static func _resolve(spec: Variant, stage: Dictionary, actors: Dictionary, default_h: float) -> Vector3:
	if spec is String:
		var parts := String(spec).split(":")
		var actor := actors.get(parts[0]) as Actor
		if actor != null:
			if parts.size() > 1 and parts[1].begins_with("@"):
				return _bone_pos(actor, parts[1].substr(1))
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


static func _check(expect: Dictionary, actors: Dictionary, camera: Camera3D, player: Node, space: PhysicsDirectSpaceState3D, stage: Dictionary, image: Image) -> Dictionary:
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
	# 1b. the head faces the shot camera, the body keeps the authored heading (measured only: nothing here changes a pose)
	var head_node := actor.model.find_child("Head", true, false) as Node3D
	if expect.has("head_faces_camera_deg") and head_node != null:
		var head_fwd := -head_node.global_basis.z
		var head_deg := rad_to_deg(head_fwd.angle_to((cam_pos - head_node.global_position).normalized()))
		rows.append({"name": "head faces camera", "pass": head_deg <= float(expect["head_faces_camera_deg"]), "detail": "%.0f deg off (max %s)" % [head_deg, expect["head_faces_camera_deg"]]})
	if expect.has("body_authored"):
		var off := absf(rad_to_deg(wrapf(actor.yaw - actor.authored_yaw, -PI, PI)))
		rows.append({"name": "body keeps authored heading", "pass": off <= float(expect["body_authored"]), "detail": "%.1f deg off the shot file's heading" % off})
	# 2. lean toward the open side of the corner
	var corner: Dictionary = stage["corner"]
	var open_dir: Vector3 = -(stage["r"] as Vector3) * float(corner["s"])   # the hall side, away from the wall the corner turns into
	var head := _bone_pos(actor, "Head")
	var pelvis := _bone_pos(actor, "Pelvis")
	var lean := (head - pelvis).dot(open_dir)
	if bool(expect.get("lean_open_side", false)):
		rows.append({"name": "leans to the open side", "pass": lean > .06, "detail": "head %.2f m toward the open side of the pelvis (needs > 0.06)" % lean})
	# 3. visible parts and torso fraction
	var parts := {"head": ["Head"], "chest": ["Chest"], "hand": ["L-Hand", "R-Hand"], "legs": ["L-Calf", "R-Calf", "L-Foot", "R-Foot", "L-Thigh", "R-Thigh"], "hips": ["Pelvis", "Belly"]}
	var want: Dictionary = expect.get("visible_parts", {})
	var vis := {}
	for part in parts:
		var any := false
		for bone in parts[part]:
			var point := _bone_pos(actor, str(bone))
			if actor.root.visible and _seen(space, camera, player, point) and _on_screen(camera, point):
				any = true
		vis[part] = any
	for part in want:
		rows.append({"name": "%s %s" % [part, "visible" if bool(want[part]) else "hidden"], "pass": bool(vis.get(part, false)) == bool(want[part]), "detail": "seen=%s" % vis.get(part)})
	if expect.has("torso_visible"):
		# the torso as the camera sees it: from the hips up to the neck (the Head pivot), across her own shoulder width
		var neck := _bone_pos(actor, "Head")
		var across := actor.root.global_basis.x.normalized()
		var seen_count := 0
		var total := 0
		for a in 5:
			for b in 5:
				var point := pelvis.lerp(neck, .1 + .8 * float(a) / 4.0) + across * (float(b) / 4.0 - .5) * .44
				total += 1
				if _seen(space, camera, player, point) and _on_screen(camera, point):
					seen_count += 1
		var fraction := float(seen_count) / float(total)
		var range_: Array = expect["torso_visible"]
		rows.append({"name": "torso visible", "pass": fraction >= float(range_[0]) and fraction <= float(range_[1]), "detail": "%.0f%% (wanted %d-%d%%)" % [fraction * 100.0, int(float(range_[0]) * 100), int(float(range_[1]) * 100)]})
	# 4. no hunter mesh inside walls (body points, small spheres)
	if bool(expect.get("no_wall_intersection", false)) and actor.root.visible:
		var sphere := SphereShape3D.new()
		sphere.radius = .1
		var hand_sphere := SphereShape3D.new()
		hand_sphere.radius = .03   # a hand resting ON the wall edge is the point of the shot
		var bad: Array = []
		for bone in ["Head", "Chest", "Belly", "Pelvis", "L-Hand", "R-Hand", "L-Forearm", "R-Forearm", "L-Foot", "R-Foot", "L-Calf", "R-Calf"]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = hand_sphere if bone.ends_with("Hand") else sphere
			# a foot sphere is lifted off the floor collider: only walls count
			query.transform = Transform3D(Basis.IDENTITY, _bone_pos(actor, bone) + (Vector3.UP * .14 if bone.ends_with("Foot") else Vector3.ZERO))
			query.exclude = [(player as CollisionObject3D).get_rid()]
			if not space.intersect_shape(query, 1).is_empty():
				bad.append(bone)
		rows.append({"name": "no wall intersection", "pass": bad.is_empty(), "detail": "inside walls: %s" % [bad]})
	# 5. screen size of the visible subject (head to the lowest visible, on-screen sample), as a fraction of the frame height
	if expect.has("screen_fraction"):
		var top := camera.unproject_position(_bone_pos(actor, "Head") + Vector3.UP * .25).y
		var low := camera.unproject_position(_bone_pos(actor, "Head") - Vector3.UP * .2).y
		for bone in ["Chest", "Belly", "Pelvis", "L-Calf", "R-Calf", "L-Foot", "R-Foot"]:
			var point := _bone_pos(actor, bone)
			if _seen(space, camera, player, point) and _on_screen(camera, point):
				low = maxf(low, camera.unproject_position(point).y)
		var frac := (low - top) / camera.get_viewport().get_visible_rect().size.y
		var limits: Array = expect["screen_fraction"]
		rows.append({"name": "screen size", "pass": frac >= float(limits[0]) and frac <= float(limits[1]), "detail": "%.0f%% of frame height (wanted %d-%d%%)" % [frac * 100.0, int(float(limits[0]) * 100), int(float(limits[1]) * 100)]})
	if expect.has("aim_deg") and head_node != null:
		var aim := rad_to_deg((-camera.global_basis.z).angle_to((head_node.global_position - cam_pos).normalized()))
		rows.append({"name": "beam centred on her face", "pass": aim <= float(expect["aim_deg"]), "detail": "%.1f deg between the camera axis and her head (max %s)" % [aim, expect["aim_deg"]]})
	if expect.has("smooth_max_deg"):
		var worst := 0.0
		var worst_bone := ""
		for bone in _smooth:
			if float((_smooth[bone] as Dictionary)["max"]) > worst:
				worst = float((_smooth[bone] as Dictionary)["max"])
				worst_bone = "%s @%ss" % [bone, (_smooth[bone] as Dictionary).get("at", "?")]
		rows.append({"name": "animation smooth", "pass": worst <= float(expect["smooth_max_deg"]), "detail": "worst single-frame bone step %.1f deg (%s), max %s" % [worst, worst_bone, expect["smooth_max_deg"]]})
	# the occluder is the REAL corner: rays from the camera to her feet and hips must stop on the corner block, within 1.2 m of the edge
	var corner_info: Dictionary = stage.get("corner", {})
	if expect.has("occluded_by_corner") and corner_info.has("vertex") and actor.root.visible:
		var vx: Array = corner_info["vertex"]
		var vertex2 := Vector2(float(vx[0]), float(vx[1]))
		var bad_rays: Array = []
		var cf: Vector3 = stage["f"]
		var cr: Vector3 = (stage["r"] as Vector3) * float(corner_info.get("s", 1.0))
		var vertex3 := Vector3(vertex2.x, 0.0, vertex2.y)
		# bone centres (feet lifted off the floor): rays ignore her own body, so box corners behind her torso would read as "seen";
		# slivers at the edge are the pixel check's job
		var targets: Array = []
		for bone in expect["occluded_by_corner"]:
			targets.append([str(bone), _bone_pos(actor, str(bone)) + (Vector3.UP * .15 if str(bone).ends_with("Foot") else Vector3.ZERO)])
		for target in targets:
			var point: Vector3 = target[1]
			var ray := PhysicsRayQueryParameters3D.create(cam_pos, point)
			ray.exclude = [(player as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(ray)
			if hit.is_empty():
				if not _on_screen(camera, point):
					continue
				bad_rays.append("%s: seen" % target[0])
				continue
			var hp: Vector3 = hit["position"]
			var flat := Vector3(hp.x, 0.0, hp.z) - vertex3
			var on_a_face := absf(flat.dot(cr)) <= .3 and flat.dot(cf) <= .3 and flat.dot(cf) >= -4.0
			var on_b_face := absf(flat.dot(cf)) <= .3 and flat.dot(cr) >= -.3 and flat.dot(cr) <= 4.0
			if (hit["normal"] as Vector3).y > .7:
				continue   # a box corner at floor level, behind the floor's own edge: not visible either way
			if not (on_a_face or on_b_face):
				bad_rays.append("%s: hidden by something %.1f m from the corner" % [target[0], flat.length()])
		var unique := {}
		for b in bad_rays:
			unique[b] = true
		bad_rays = unique.keys()
		rows.append({"name": "feet/hips hidden by the corner wall", "pass": bad_rays.is_empty(), "detail": "ok" if bad_rays.is_empty() else ", ".join(bad_rays)})
	if expect.has("edge_max_m") and corner_info.has("vertex") and actor.root.visible:
		var vxe: Array = corner_info["vertex"]
		var v2 := Vector2(float(vxe[0]), float(vxe[1]))
		var nearest := 99.0
		var nearest_bone := ""
		for node in actor.model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if not mi.is_visible_in_tree() or mi.mesh == null:
				continue
			var box := mi.global_transform * mi.get_aabb()
			var qx := clampf(v2.x, box.position.x, box.end.x)
			var qz := clampf(v2.y, box.position.z, box.end.z)
			var dist := Vector2(qx, qz).distance_to(v2)
			if dist < nearest:
				nearest = dist
				nearest_bone = str(mi.get_parent().name) + "/" + str(mi.name)
		rows.append({"name": "hugging the wall edge", "pass": nearest <= float(expect["edge_max_m"]), "detail": "%s %.2f m from the edge (max %s)" % [nearest_bone, nearest, expect["edge_max_m"]]})
	if bool(expect.get("corner_is_grid", false)):
		rows.append({"name": "a real corridor corner", "pass": bool(corner_info.get("grid", false)), "detail": "grid corner at %s, corridor B %s cell(s) wide" % [corner_info.get("vertex"), corner_info.get("b_cells")]})
	# her whole BODY (every mesh part's box, shrunk 10%) against the level: no part pushed into a wall
	if bool(expect.get("no_mesh_in_wall", false)) and actor.root.visible:
		var parts_in: Array = []
		for node in actor.model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if not mi.is_visible_in_tree() or mi.mesh == null:
				continue
			var box_aabb := mi.get_aabb()
			var scale := mi.global_basis.get_scale()
			var box := BoxShape3D.new()
			box.size = (box_aabb.size * scale * .9).max(Vector3.ONE * .01)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = box
			query.transform = Transform3D(mi.global_basis.orthonormalized(), mi.global_transform * box_aabb.get_center() + Vector3.UP * .04)
			query.exclude = [(player as CollisionObject3D).get_rid()]
			for hit in space.intersect_shape(query, 4):
				var body := hit["collider"] as Node
				parts_in.append(str(mi.get_parent().name) + "/" + str(mi.name))
				break
		rows.append({"name": "body mesh clear of walls", "pass": parts_in.is_empty(), "detail": "in walls: %s" % [parts_in]})
	if bool(expect.get("no_labels", false)):
		var shown: Array = []
		for node in _scene.find_children("*", "Label3D", true, false):
			var label := node as Label3D
			# floating tags on or near any hunter in the shot (the level signage the world itself carries is not a hunter tag)
			var near_hunter := false
			for key in _actors:
				var other := _actors[key] as Actor
				if other.root.visible and (other.root.is_ancestor_of(label) or label.global_position.distance_to(other.pos + Vector3.UP * other.height) < 2.5):
					near_hunter = true
			if near_hunter and label.is_visible_in_tree() and label.modulate.a > .02:
				shown.append(str(label.text))
		rows.append({"name": "no name tags / Label3D on hunters", "pass": shown.is_empty(), "detail": "visible labels: %s" % [shown]})
	if expect.has("face_luma_min") and image != null and actor.root.visible:
		var hp := camera.unproject_position(_bone_pos(actor, "Head"))
		var vp := camera.get_viewport().get_visible_rect().size
		var sx := image.get_width() / vp.x
		var sy := image.get_height() / vp.y
		var total_luma := 0.0
		var count := 0
		for dx in range(-6, 7, 3):
			for dy in range(-6, 7, 3):
				var px := clampi(int((hp.x + dx) * sx), 0, image.get_width() - 1)
				var py := clampi(int((hp.y + dy) * sy), 0, image.get_height() - 1)
				total_luma += image.get_pixel(px, py).get_luminance()
				count += 1
		var luma := total_luma / float(count)
		rows.append({"name": "face readable (lit)", "pass": luma >= float(expect["face_luma_min"]), "detail": "luminance %.2f (min %s)" % [luma, expect["face_luma_min"]]})
	var ok := true
	for row in rows:
		ok = ok and bool(row["pass"])
	var names: Array = []
	for bone in ["Head", "Pelvis", "Chest", "L-Hand", "L-Foot"]:
		names.append("%s=%s" % [bone, actor.model.find_child(bone, true, false) != null])
	return {"pass": ok, "rows": rows, "bones": names}


## Dims the streamed world once per light (the capture rig's own lights are exempt) and the ambient: a dark shot, not a lit stage.
static func _dim_world(scene: Node, player: Node, camera: Camera3D, own: Array, factor: float) -> void:
	for node in scene.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if own.has(light) or player.is_ancestor_of(light) or light.has_meta("trailer_dimmed"):
			continue
		light.set_meta("trailer_dimmed", true)
		light.light_energy *= factor
	for node in scene.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env != null and not env.has_meta("trailer_dimmed"):
			env.set_meta("trailer_dimmed", true)
			env.ambient_light_energy *= factor


# ------------------------------------------------------------------------------------------------ pixel truth (what the camera really shows)
const PART_COLORS := {"legs": Color(1, 0, 1), "hips": Color(0, 1, 1), "torso": Color(1, 1, 0), "head": Color(0, 1, 0), "arms": Color(1, 0, 0)}


static func _part_group(mi: MeshInstance3D) -> String:
	var n := (str(mi.name) + " " + str(mi.get_parent().name)).to_lower()
	var own := str(mi.name).to_lower()
	for key in ["thigh", "calf", "foot"]:
		if own.contains(key):
			return "legs"
	for key in ["forearm", "hand", "-arm"]:
		if own.contains(key):
			return "arms"
	if own.contains("pelvis"):
		return "hips"
	if own.contains("chest") or own.contains("belly"):
		return "torso"
	if n.contains("head"):
		return "head"
	if n.contains("thigh") or n.contains("calf") or n.contains("foot"):
		return "legs"
	if n.contains("pelvis"):
		return "hips"
	if n.contains("chest") or n.contains("belly"):
		return "torso"
	if n.contains("arm") or n.contains("hand"):
		return "arms"
	return "head"


## Renders the SAME shot camera twice with her parts in flat colours: once depth-tested (what is really visible past the wall), once with only
## the torso drawn on top of everything (its full on-screen size). Counts pixels per part; rays can disagree with the rendered wall faces.
static func _pixel_check(scene: Node, camera: Camera3D, actor: Actor, want: Dictionary, mask_path: String) -> Array:
	var rows: Array = []
	if actor == null or not actor.root.visible:
		return [{"name": "pixel check", "pass": not bool(want.get("need_visible", false)), "detail": "actor hidden"}]
	var meshes: Array = actor.model.find_children("*", "MeshInstance3D", true, false)
	var saved_env := camera.environment
	var flat_env := Environment.new()
	flat_env.background_mode = Environment.BG_COLOR
	flat_env.background_color = Color.BLACK
	flat_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment = flat_env
	var counts_a := await _mask_render(scene, meshes, true, "", mask_path)
	var counts_b := await _mask_render(scene, meshes, false, "torso", "")
	# the torso's full on-screen silhouette (pass B) against what pass A shows inside it: any of HER pixels there (an arm across the
	# chest still means the torso is out past the wall); wall pixels there mean the wall hides it
	var sil: Image = counts_b["_image"]
	var shown: Image = counts_a["_image"]
	var inside := 0
	var out_past := 0
	for y in range(0, sil.get_height(), 2):
		for x in range(0, sil.get_width(), 2):
			if _pixel_part(sil.get_pixel(x, y)) != "torso":
				continue
			inside += 1
			if not _pixel_part(shown.get_pixel(x, y)).is_empty():
				out_past += 1
	counts_a["_torso_sil"] = inside
	counts_a["_torso_out"] = out_past
	camera.environment = saved_env
	for mi_value in meshes:
		var mi := mi_value as MeshInstance3D
		mi.material_override = null
		mi.visible = true
	var limits: Dictionary = want.get("max_px", {})
	for part in limits:
		rows.append({"name": "%s pixels past the wall" % part, "pass": int(counts_a.get(part, 0)) <= int(limits[part]), "detail": "%d px visible (max %s)" % [int(counts_a.get(part, 0)), limits[part]]})
	if want.has("min_px"):
		var mins: Dictionary = want["min_px"]
		for part in mins:
			rows.append({"name": "%s pixels visible" % part, "pass": int(counts_a.get(part, 0)) >= int(mins[part]), "detail": "%d px (min %s)" % [int(counts_a.get(part, 0)), mins[part]]})
	if want.has("torso_fraction"):
		var full := maxi(int(counts_a.get("_torso_sil", 0)), 1)
		var frac := float(counts_a.get("_torso_out", 0)) / float(full)
		var rng: Array = want["torso_fraction"]
		rows.append({"name": "torso showing past the wall (pixels)", "pass": frac >= float(rng[0]) and frac <= float(rng[1]), "detail": "%.0f%% of her torso silhouette is not behind the wall (wanted %d-%d%%)" % [frac * 100.0, int(float(rng[0]) * 100), int(float(rng[1]) * 100)]})
	if want.has("height_fraction"):
		var hf: float = float(counts_a.get("_height", 0)) / float(maxi(int(counts_a.get("_rows", 1)), 1))
		var hr: Array = want["height_fraction"]
		rows.append({"name": "visible figure height", "pass": hf >= float(hr[0]) and hf <= float(hr[1]), "detail": "%.0f%% of frame height (wanted %d-%d%%)" % [hf * 100.0, int(float(hr[0]) * 100), int(float(hr[1]) * 100)]})
	return rows


static func _mask_render(scene: Node, meshes: Array, depth_test: bool, only: String, save_path: String) -> Dictionary:
	for mi_value in meshes:
		var mi := mi_value as MeshInstance3D
		var group := _part_group(mi)
		mi.visible = only.is_empty() or group == only
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = PART_COLORS[group]
		mat.no_depth_test = not depth_test
		mat.render_priority = 10 if not depth_test else 0
		mi.material_override = mat
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := scene.get_viewport().get_texture().get_image()
	if not save_path.is_empty():
		image.save_png(save_path)
	var counts := {}
	var top := -1
	var bottom := -1
	var step := 2
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var part := _pixel_part(image.get_pixel(x, y))
			if part.is_empty():
				continue
			counts[part] = int(counts.get(part, 0)) + step * step
			if top < 0:
				top = y
			bottom = y
	counts["_height"] = 0 if top < 0 else bottom - top
	counts["_rows"] = image.get_height()
	counts["_image"] = image
	return counts


static func _pixel_part(c: Color) -> String:
	if c.r > .6 and c.b > .6 and c.g < .25:
		return "legs"
	if c.g > .6 and c.b > .6 and c.r < .25:
		return "hips"
	if c.r > .6 and c.g > .6 and c.b < .25:
		return "torso"
	if c.g > .6 and c.r < .25 and c.b < .25:
		return "head"
	if c.r > .6 and c.g < .25 and c.b < .25:
		return "arms"
	return ""
