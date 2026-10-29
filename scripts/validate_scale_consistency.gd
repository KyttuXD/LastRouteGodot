extends RefCounted

## Scale consistency: a hunter is HunterRoster.scale_for(id) (humanoids 1.5x, Voids about 3 m) and a runner is PlayerModels.SCALE
## (0.9, 1.60 m), in EVERY state, never a drifting body. Each sample measures the world scale of the body bones and the world
## length of the skeleton's segments against the authored rest pose times the reference scale; anything off by more than 2% is
## a failure. Upright states (idle, walk) also keep the world height (mesh bounds) and the head bone's height at the reference.
##
## Measured (see the table at the end of the run):
##   hunters   every clip in every library (idle, walk, chase, sprint, peek, locker lean, sit, nap, emotes, stun, climb,
##             Night Watch poses ...), the chase-style layer (all 8 styles, aimed and straight), asleep / seated / climbing /
##             stunned through the view, a model swap (disguise), and every grab style (the arm stretch may only lengthen the
##             upper arm and forearm, never the hand, the body or the hunter's size)
##   runners   both mannequins in every clip, the skin / arm-style changes and a settings save + load, the controller's own body,
##             a guest's copy (RemotePlayers._make_body), the first-person body (grab, ladder), a remote VR pose
##   previews  the SKIN tab's mannequin preview, the Night Watch camera preview, and the Night Watch hunters (NightWatchHunterScale, Last Route's scale)
##
##   godot --headless --path . res://scenes/validate.tscn -- scale_consistency

const TOLERANCE := 0.02
## The body bones whose world scale must equal the reference (arms are checked apart: they may lengthen in a grab).
const BODY := ["Pelvis", "Belly", "Chest", "Head", "L-Thigh", "L-Calf", "L-Foot", "R-Thigh", "R-Calf", "R-Foot", "L-Hand", "R-Hand"]
const SEGMENTS := [["Pelvis", "Chest"], ["Chest", "Head"], ["L-Thigh", "L-Calf"], ["L-Calf", "L-Foot"], ["R-Thigh", "R-Calf"],
	["R-Calf", "R-Foot"], ["L-Thigh", "R-Thigh"], ["L-Arm", "R-Arm"]]
const ARM_SEGMENTS := [["L-Arm", "L-Forearm"], ["L-Forearm", "L-Hand"], ["R-Arm", "R-Forearm"], ["R-Forearm", "R-Hand"]]
const UPRIGHT := ["idle", "scythe_idle", "walk", "scythe_walk"]
const SAMPLES := 4
## (Night Watch used to draw its hunters at the authored 1.0; KT ruled they match Last Route's: NightWatchHunterScale, checked at the end of _previews.)
## While a grab plays the hunter's body leans and twists with the hold; the shoulder span of a shy wrist-yank reaches 2.6% (GRAB lane to look at it).
const PLAYING_LIMIT := 0.03
## KT ruling 2026-10-28 (second): the runner is about 1.9 m, head top at a hunter's upper torso (shoulder line 1.83 m, neck 2.0 m of 2.58 m).
const RUNNER_HEIGHT := 1.9
const HUNTER_HEIGHT := 2.58
const SKIP_MESH := ["Beam", "Star", "Scythe", "Cue-", "Halo", "Glyph"]

var _failures := 0
var _refs := {}
var _rows := {}          # state label -> {"n", "scale", "seg", "top", "head", "arm", "who"}
var _printed := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		_printed += 1
		if _printed <= 60:
			print("  FAIL  %s" % message)


# ---- measuring ------------------------------------------------------------------------------------------------------------


func _bone(model: Node, bone_name: String) -> Node3D:
	return model.find_child(bone_name, true, false) as Node3D


func _top(model: Node3D) -> float:
	var top := -INF
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var skip := false
		for part in SKIP_MESH:
			if String(mesh.name).contains(part) or String(mesh.get_parent().name).contains(part):
				skip = true
		if skip:
			continue
		top = maxf(top, (mesh.global_transform * mesh.get_aabb()).end.y)
	return top


func _seg_lengths(model: Node3D, pairs: Array) -> Dictionary:
	var out := {}
	for pair in pairs:
		var a := _bone(model, pair[0])
		var b := _bone(model, pair[1])
		if a != null and b != null:
			out["%s>%s" % [pair[0], pair[1]]] = a.global_position.distance_to(b.global_position)
	return out


## Rest lengths of a model's skeleton (scale 1, no clip): the authored proportions every state is compared with.
func _reference(key: String, make: Callable, host: Node) -> Dictionary:
	if _refs.has(key):
		return _refs[key]
	var model: Node3D = make.call()
	host.add_child(model)
	var ref := {"seg": _seg_lengths(model, SEGMENTS), "arm": _seg_lengths(model, ARM_SEGMENTS)}
	var player := ModelSlot.find_animation_player(model)
	if player != null and player.has_animation("idle"):
		player.play("idle")
		player.seek(0.0, true)
	ref["top"] = _top(model)
	var head := _bone(model, "Head")
	ref["head"] = head.global_position.y if head != null else 0.0
	model.free()
	_refs[key] = ref
	return ref


## One sample: how far (fraction) the body bones' world scale, the skeleton's segment lengths, the world height and the head
## bone's height are from the reference at `scale_ref`. `ground` is the world y of the feet. `stretch` is how much longer the
## arms may be than at rest (1 outside a grab); a hand is never scaled.
func _measure(model: Node3D, ref: Dictionary, scale_ref: float, ground: float, stretch: float = 1.0) -> Dictionary:
	var out := {"scale": 0.0, "seg": 0.0, "arm": 0.0, "top": 0.0, "head": 0.0, "what": ""}
	for bone_name in BODY:
		var bone := _bone(model, bone_name)
		if bone == null:
			continue
		if bone.global_basis.determinant() < 0.0:     # a mirrored bone turns its faces inside out
			out["scale"] = 1.0
			out["what"] = "%s is mirrored (negative scale)" % bone_name
			continue
		var s := bone.global_basis.get_scale().abs()
		var dev := maxf(absf(s.x / scale_ref - 1.0), maxf(absf(s.y / scale_ref - 1.0), absf(s.z / scale_ref - 1.0)))
		if dev > out["scale"]:
			out["scale"] = dev
			out["what"] = "%s scale %.3f" % [bone_name, s.y / scale_ref]
	for arm_name in ["L-Arm", "R-Arm", "L-Forearm", "R-Forearm"]:   # width and depth stay; the length may stretch
		var bone := _bone(model, arm_name)
		if bone != null:
			var s := bone.global_basis.get_scale().abs()
			var dev := maxf(absf(s.x / scale_ref - 1.0), absf(s.z / scale_ref - 1.0))
			if dev > out["scale"]:
				out["scale"] = dev
				out["what"] = "%s width %.3f" % [arm_name, s.x / scale_ref]
	var now := _seg_lengths(model, SEGMENTS)
	for key in now:
		var rest: float = ref["seg"].get(key, 0.0)
		if rest > 0.001:
			var dev := absf(float(now[key]) / (rest * scale_ref) - 1.0)
			if dev > out["seg"]:
				out["seg"] = dev
				out["what"] = "%s length %.3f" % [key, float(now[key]) / (rest * scale_ref)]
	var arms := _seg_lengths(model, ARM_SEGMENTS)
	for key in arms:
		var rest: float = ref["arm"].get(key, 0.0)
		if rest > 0.001:
			var ratio := float(arms[key]) / (rest * scale_ref)
			var over := maxf(ratio - stretch, 1.0 - ratio)
			if over > out["arm"]:
				out["arm"] = over
				if over > TOLERANCE:
					out["what"] = "%s length %.3f (allowed 1-%.2f)" % [key, ratio, stretch]
	var top := _top(model)
	if is_finite(top) and float(ref["top"]) > 0.01:
		out["top"] = (top - ground) / (float(ref["top"]) * scale_ref) - 1.0
	var head := _bone(model, "Head")
	if head != null and float(ref["head"]) > 0.01:
		out["head"] = (head.global_position.y - ground) / (float(ref["head"]) * scale_ref) - 1.0
	return out


## Fold a sample into the table and fail when it is off by more than the tolerance.
func _record(state: String, who: String, m: Dictionary, upright: bool = false, limit: float = TOLERANCE) -> void:
	var row: Dictionary = _rows.get(state, {"n": 0, "scale": 0.0, "seg": 0.0, "top": 0.0, "head": 0.0, "arm": 0.0, "who": ""})
	row["n"] += 1
	for key in ["scale", "seg", "arm"]:
		if float(m[key]) > float(row[key]):
			row[key] = float(m[key])
			row["who"] = who
	if upright:
		for key in ["top", "head"]:
			if absf(float(m[key])) > absf(float(row[key])):
				row[key] = float(m[key])
				row["who"] = who
	_rows[state] = row
	_expect(float(m["scale"]) <= limit, "%s [%s]: body scale off by %.1f%% (%s)" % [who, state, float(m["scale"]) * 100.0, m["what"]])
	_expect(float(m["seg"]) <= limit, "%s [%s]: a skeleton segment is off by %.1f%% (%s)" % [who, state, float(m["seg"]) * 100.0, m["what"]])
	_expect(float(m["arm"]) <= limit, "%s [%s]: an arm is %.1f%% out of range (%s)" % [who, state, float(m["arm"]) * 100.0, m["what"]])
	if upright:
		_expect(absf(float(m["top"])) <= TOLERANCE, "%s [%s]: the height is off by %+.1f%%" % [who, state, float(m["top"]) * 100.0])
		_expect(absf(float(m["head"])) <= TOLERANCE, "%s [%s]: the head bone is off by %+.1f%%" % [who, state, float(m["head"]) * 100.0])


## Every clip of every library, SAMPLES points each.
func _sweep(model: Node3D, player: AnimationPlayer, ref: Dictionary, scale_ref: float, ground: float, who: String, group: String) -> void:
	if player == null:
		return
	for clip in player.get_animation_list():
		if String(clip) == "RESET":
			continue
		var length := maxf(player.get_animation(clip).length, .05)
		var family := String(clip).get_slice("/", 1) if String(clip).contains("/") else String(clip)
		var worst := {"scale": 0.0, "seg": 0.0, "arm": 0.0, "top": -INF, "head": -INF, "what": ""}
		var upright := UPRIGHT.has(String(clip))
		var samples := SAMPLES * 3 if upright else SAMPLES
		for k in samples:
			player.play(clip)
			player.seek(length * float(k) / float(samples), true)
			var m := _measure(model, ref, scale_ref, ground)
			for key in ["scale", "seg", "arm"]:
				if float(m[key]) > float(worst[key]):
					worst[key] = m[key]
					worst["what"] = m["what"]
			# a gait dips and bobs: the standing height is its HIGHEST point (mid-stance), which must be the reference height
			for key in ["top", "head"]:
				worst[key] = maxf(float(worst[key]), float(m[key]))
		_record("%s %s" % [group, "nw:" + family if String(clip).contains("/") else _state_of(family)], "%s/%s" % [who, clip], worst,
			UPRIGHT.has(String(clip)))


## Clip name -> the state it shows (the table's row).
func _state_of(clip: String) -> String:
	for prefix in ["emote_", "stun", "corner_peek", "locker", "sit", "nap", "sleep", "climb", "crouch", "crawl", "hide", "chase", "sprint",
			"walk", "idle", "scythe", "charge", "flight", "jump", "fall", "grab"]:
		if clip.begins_with(prefix):
			return prefix.trim_suffix("_")
	return "other"


func _hunter_view(host: Node, id: String) -> HunterView3D:
	var origin := Vector2(5.5, 5.5)
	var brain := HunterBrain.new(origin, "SCALE-%s" % id, id, "standard")
	brain.activate_at(origin)
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	return view


func _measure_view(view: HunterView3D, id: String, state: String, upright: bool = false, stretch: float = 1.0, limit: float = TOLERANCE) -> void:
	var scale_ref := HunterRoster.scale_for(id)
	var ref := _reference("hunter:" + id, func(): return ModelSlot.instantiate_hunter(HunterRoster.get_identity(id)), view)
	_record(state, id, _measure(view._model, ref, scale_ref, view.global_position.y, stretch), upright, limit)


# ---- hunters --------------------------------------------------------------------------------------------------------------


func _hunters(host: Node) -> void:
	var tree := host.get_tree()
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var lines := []
	for id_value in ids:
		var id := String(id_value)
		var view := _hunter_view(host, id)
		await tree.process_frame
		view.sync_from_brain()
		var model: Node3D = view._model
		if model == null:
			_expect(false, "%s has no model" % id)
			view.queue_free()
			continue
		var scale_ref := HunterRoster.scale_for(id)
		_expect(model.scale.is_equal_approx(Vector3.ONE * scale_ref), "%s: the model is drawn at %s, not %.2f" % [id, model.scale, scale_ref])
		var ref := _reference("hunter:" + id, func(): return ModelSlot.instantiate_hunter(HunterRoster.get_identity(id)), host)
		var player: AnimationPlayer = view._animation_player
		# Standing height: the reference is this hunter's own idle pose, drawn in the view at its reference scale (a bare instance has
		# no add-ons or libraries yet, and Voids rest in a hover pose until their idle plays), taken before any state is applied.
		# The sweep and every state below are measured against it; the numbers are printed (humanoids about 2.7 m, Voids about 3 m).
		if player != null and player.has_animation("idle"):
			player.play("idle")
			player.seek(0.0, true)
			var height := _top(model) - view.global_position.y
			ref["top"] = height / scale_ref
			var head := _bone(model, "Head")
			ref["head"] = (head.global_position.y - view.global_position.y) / scale_ref if head != null else 0.0
			lines.append("%s %.2f" % [id, height])
		_sweep(model, player, ref, scale_ref, view.global_position.y, id, "hunter")
		# the chase-style layer on top of the chase clip, straight and aimed
		if player != null and player.has_animation("chase"):
			for style in HunterChaseStyle.STYLES:
				for aim in [0.0, 0.5]:
					player.play("chase")
					player.seek(player.get_animation("chase").length * .3, true)
					for step in 5:
						view._chase.apply(style, true, .5, aim, float(step) * .4)
					_measure_view(view, id, "hunter chase style")
					view._chase.apply(style, false, 5.0, 0.0, 0.0)
		# states driven through the view
		view.set_asleep(true, 0.0, 2)
		await tree.process_frame
		_measure_view(view, id, "hunter view: asleep")
		view.set_asleep(false)
		view.set_seated(true, 0.0)
		for i in 3:
			await tree.process_frame
		_measure_view(view, id, "hunter view: seated")
		view.set_seated(false)
		view.set_climbing(true, 1.0, 0.0, "climb")
		for i in 3:
			await tree.process_frame
		_measure_view(view, id, "hunter view: climbing")
		view.set_climbing(false)
		view.brain.stun_timer = 1.0
		for i in 3:
			await tree.process_frame
		_measure_view(view, id, "hunter view: stunned")
		view.brain.stun_timer = 0.0
		# a model swap (a disguise, a roster change) draws the new model at the new reference, and back
		for other in ["aki", "void_black"]:
			view._apply_model(other)
			await tree.process_frame
			_measure_view(view, other, "hunter view: after a model swap")
		view._apply_model(id)
		await tree.process_frame
		_measure_view(view, id, "hunter view: swapped back")
		view.queue_free()
	print("  heights at idle (m): %s" % ", ".join(lines))


# ---- grabs (GRAB lane: res://src/config/grab_styles.gd, loaded by path so this suite also runs where the lane has not landed) ---


func _grabs(host: Node) -> void:
	if not ResourceLoader.exists("res://src/game_3d/hunter_grab.gd") or not ResourceLoader.exists("res://src/config/grab_styles.gd"):
		print("  grabs: not in this tree, skipped")
		return
	var grab_script: GDScript = load("res://src/game_3d/hunter_grab.gd")
	var styles_script: GDScript = load("res://src/config/grab_styles.gd")
	var tree := host.get_tree()
	var stretch_max: float = grab_script.get("arm_stretch")
	var ids: Array = HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS
	for id_value in ids:
		var id := String(id_value)
		var view := _hunter_view(host, id)
		await tree.process_frame
		view.sync_from_brain()
		if view._model == null or _bone(view._model, "L-Arm") == null:
			view.queue_free()
			continue
		var player: AnimationPlayer = view._animation_player
		# at full reach both arm segments really are `arm_stretch` times longer (the stretch happens), and nothing else changed
		if player != null and player.has_animation("idle"):
			player.play("idle")
			player.seek(0.0, true)
			var rest_arm := _seg_lengths(view._model, ARM_SEGMENTS)
			grab_script.call("stretch_arms", view, stretch_max)
			var long_arm := _seg_lengths(view._model, ARM_SEGMENTS)
			for key in ["L-Arm>L-Forearm", "L-Forearm>L-Hand", "R-Arm>R-Forearm", "R-Forearm>R-Hand"]:
				_expect(absf(float(long_arm[key]) / float(rest_arm[key]) / stretch_max - 1.0) <= TOLERANCE,
					"%s: %s is %.2fx at full reach, want %.2fx" % [id, key, float(long_arm[key]) / float(rest_arm[key]), stretch_max])
			grab_script.call("stretch_arms", view, 1.0)
		for style in styles_script.get("STYLES"):
			if bool((styles_script.get("STYLES")[style] as Dictionary).get("creature", false)):
				continue
			for clip in ["idle", "chase"]:
				if player == null or not player.has_animation(clip):
					continue
				for step in 4:
					var t := (grab_script.call("stretch_for", style, float(step) / 3.0 * float(styles_script.get("REACH_SECONDS"))) as float)
					player.play(clip)
					player.seek(player.get_animation(clip).length * float(step) / 4.0, true)
					grab_script.call("stretch_arms", view, t)
					_measure_view(view, id, "hunter grab %s (arm stretch)" % style, false, maxf(t, 1.0))
					# the hand keeps its size and shape: no scale, no shear (the body-bone scale check above includes both hands)
					_expect(t <= stretch_max + .001, "%s [grab %s]: stretched to %.2f, limit %.2f" % [id, style, t, stretch_max])
					grab_script.call("stretch_arms", view, 1.0)
		_measure_view(view, id, "hunter grab: arms put back")
		view.queue_free()
	# the real thing: the route's HunterGrab plays every style on a hunter and the runner's own body is measured through it
	var route: Node = load("res://scenes/main_3d.tscn").instantiate()
	tree.root.add_child(route)
	await tree.process_frame
	var runner := route.get("player") as PlayerController3D
	var grab: Node = route.get("grab")
	if runner != null and grab != null:
		runner.input_frozen = true
		runner.look_frozen = true
		var arena = load("res://scripts/grab_arena.gd").build(route, "open")
		var stand: Vector3 = arena["stand"]
		var facing: Vector3 = arena["facing"]
		var done := {}
		for id_value in ids:
			var id := String(id_value)
			var style: String = styles_script.call("main_style", id)
			runner.global_position = stand
			var hunter := _hunter_view(route, id)
			hunter.global_position = stand + facing * .8
			hunter.look_at(stand + facing * .8 + (-facing), Vector3.UP)
			await tree.process_frame
			if hunter._model == null or _bone(hunter._model, "L-Arm") == null:
				hunter.queue_free()
				continue
			grab.call("play", runner, hunter, id, .5, style)
			var waited := 0.0
			var own = runner.call("first_person_body")
			var own_ref := _reference("runner:" + PlayerModels.SCENE, func(): return ModelSlot.instantiate(PlayerModels.SCENE), route)
			while waited < float(styles_script.get("TOTAL_SECONDS")):
				await tree.process_frame
				waited += route.get_process_delta_time()
				var t: float = grab_script.call("stretch_for", style, waited)
				_measure_view(hunter, id, "hunter grab %s (playing)" % style, false, maxf(t, 1.0) + .001, PLAYING_LIMIT)
				if own != null and own.model != null:
					_record("runner first-person body in a grab", id, _measure(own.model, own_ref, PlayerModels.SCALE, own.model.global_position.y))
			grab.call("release")
			hunter.queue_free()
			await tree.process_frame
			done[id] = true
		print("  grab played on %d hunters (stretch limit %.2f)" % [done.size(), stretch_max])
	route.queue_free()
	await tree.process_frame


# ---- runners --------------------------------------------------------------------------------------------------------------


## Back to the standing frame (a sweep leaves the last clip's last pose).
func _stand(model: Node3D) -> void:
	var player := ModelSlot.find_animation_player(model)
	if player != null and player.has_animation("idle"):
		player.play("idle")
		player.seek(0.0, true)


func _runner_ref(host: Node, path: String) -> Dictionary:
	return _reference("runner:" + path, func(): return ModelSlot.instantiate(path), host)


func _runners(host: Node) -> void:
	var tree := host.get_tree()
	for path in [PlayerModels.BLOCKY, PlayerModels.BLOCKY_SLIM]:
		var label := String(path).get_file().get_basename()
		var ref := _runner_ref(host, path)
		var model: Node3D = ModelSlot.instantiate(path)
		model.scale = Vector3.ONE * PlayerModels.SCALE
		host.add_child(model)
		await tree.process_frame
		var player := ModelSlot.find_animation_player(model)
		_sweep(model, player, ref, PlayerModels.SCALE, 0.0, label, "runner")
		var idle_height := 0.0
		if player != null and player.has_animation("idle"):
			player.play("idle")
			player.seek(0.0, true)
			idle_height = _top(model)
		_expect(absf(idle_height - 1.78 * PlayerModels.SCALE) < 1.78 * PlayerModels.SCALE * TOLERANCE + .02,
			"%s: the standing runner is %.2f m, expected %.2f m" % [label, idle_height, 1.78 * PlayerModels.SCALE])
		_expect(absf(idle_height / RUNNER_HEIGHT - 1.0) <= TOLERANCE + .005, "%s: the standing runner is %.2f m, the ruling is %.1f m" % [label, idle_height, RUNNER_HEIGHT])
		_expect(idle_height / HUNTER_HEIGHT < .8 and idle_height / HUNTER_HEIGHT > .68, "%s: the runner is %.2fx of a hunter, want 0.68-0.8 (head top at her upper torso)" % [label, idle_height / HUNTER_HEIGHT])
		# skin and arm-style changes (PlayerSkin) and a repaint never rescale the body
		for slim in [true, false, true, false]:
			PlayerSkin.set_arms(model, slim)
			PlayerSkin.apply(model, PlayerSkin.active_texture())
			await tree.process_frame
			_stand(model)
			_record("runner after a skin / arm-style change", label, _measure(model, ref, PlayerModels.SCALE, 0.0), true)
		ModelSlot.apply_character_hue(model, 120.0)
		await tree.process_frame
		_stand(model)
		_record("runner after a skin / arm-style change", label, _measure(model, ref, PlayerModels.SCALE, 0.0), true)
		# a remote VR runner: the head turns and the arms swing to the tracked hands; nothing scales
		var pose := {"head": Transform3D(Basis.from_euler(Vector3(.3, .6, 0)), Vector3(0, 1.5, 0)),
			"left": Transform3D(Basis.IDENTITY, Vector3(-.5, 1.2, -.4)), "right": Transform3D(Basis.IDENTITY, Vector3(.5, 1.0, -.5)),
			"flags": VRPoseSync.FLAG_LEFT | VRPoseSync.FLAG_RIGHT}
		if player != null and player.has_animation("idle"):
			player.play("idle")
			player.seek(0.0, true)
		VRPoseSync.apply(model, pose)
		_record("runner remote VR pose", label, _measure(model, ref, PlayerModels.SCALE, 0.0, 3.0))
		model.queue_free()


func _controller_and_guest(host: Node) -> void:
	var tree := host.get_tree()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = load("res://scenes/main_3d.tscn").instantiate()
	tree.root.add_child(route)
	await tree.process_frame
	var player := route.get("player") as PlayerController3D
	if player == null or player._body_model == null:
		_expect(false, "the route has no player body")
		route.queue_free()
		return
	var ref := _runner_ref(host, PlayerModels.SCENE)
	var body: Node3D = player._body_model
	_record("runner own body (controller)", "player", _measure(body, ref, PlayerModels.SCALE, player.global_position.y), true)
	_expect(body.scale.is_equal_approx(Vector3.ONE * PlayerModels.SCALE), "the player's body is drawn at %s" % body.scale)
	# skin / arm style change through the settings, a settings save and load, and the visual refresh (what the SKIN tab does)
	var arms_before: String = Settings.skin_arms
	for mode in ["slim", "classic", "auto"]:
		Settings.set_skin_arms(mode)
		player._apply_visual_settings()
		await tree.process_frame
		_stand(player._body_model)
		_record("runner after a skin / arm-style change", "player/" + mode, _measure(player._body_model, ref, PlayerModels.SCALE, player.global_position.y), true)
	Settings.call("_load")
	player._apply_visual_settings()
	await tree.process_frame
	_stand(player._body_model)
	_record("runner after save and load", "player", _measure(player._body_model, ref, PlayerModels.SCALE, player.global_position.y), true)
	Settings.set_skin_arms(arms_before)
	# every state of the controller's body (the clips the controller picks), through the real animation player
	_sweep(player._body_model, player._animation_player, ref, PlayerModels.SCALE, player.global_position.y, "player", "runner (controller)")
	# the first-person body: grabs and ladders (GRAB lane; loaded dynamically so this suite also runs where it has not landed)
	if player.has_method("first_person_body"):
		var first_person = player.call("first_person_body")
		for clip in ["idle", "climb", "chase", "crawl"]:
			first_person.pose(player.global_position, Basis.IDENTITY, clip)
			await tree.process_frame
			_record("runner first-person body (grab, ladder)", clip, _measure(first_person.model, ref, PlayerModels.SCALE, player.global_position.y), clip == "idle")
		player.call("_end_first_person_body")
	# a guest's copy of the runner
	var remote := RemotePlayers.new()
	remote.local_player = player
	route.add_child(remote)
	var state := {"facing_y": .3, "player_hue": 0.0, "skin": "", "skin_slim": false, "display_name": "GUEST"}
	var copy: Node3D = remote._make_body(77, state, Vector3(2, 0, 2))
	_expect(copy != null, "no guest copy was made")
	if copy != null:
		await tree.process_frame
		_record("runner guest copy (RemotePlayers)", "guest", _measure(copy, ref, PlayerModels.SCALE, 0.0), true)
		_sweep(copy, ModelSlot.find_animation_player(copy), ref, PlayerModels.SCALE, 0.0, "guest", "runner (guest copy)")
		_expect(copy.global_basis.get_scale().abs().is_equal_approx(Vector3.ONE * PlayerModels.SCALE), "the guest copy is drawn at %s" % copy.global_basis.get_scale())
		remote._apply_peer_skin(77, copy, "", true)
		await tree.process_frame
		_stand(copy)
		_record("runner after a skin / arm-style change", "guest", _measure(copy, ref, PlayerModels.SCALE, 0.0), true)
	# the headset's hands are drawn with the same scale (xr_hands.gd: rig.basis from PlayerModels.SCALE)
	var hands_source := FileAccess.get_file_as_string("res://src/game_3d/xr_hands.gd")
	_expect(hands_source.contains("* PlayerModels.SCALE)"), "the VR hands are not scaled by PlayerModels.SCALE")
	route.queue_free()
	await tree.process_frame


# ---- previews -------------------------------------------------------------------------------------------------------------


func _previews(host: Node) -> void:
	var tree := host.get_tree()
	# SKIN tab: the mannequin preview is drawn at the runner's size (and framed for it)
	var panel := SkinPanel.new()
	host.add_child(panel)
	await tree.process_frame
	var preview: Node3D = panel._preview_model
	_expect(preview != null, "the SKIN tab has no preview model")
	if preview != null:
		_expect(preview.global_basis.get_scale().abs().is_equal_approx(Vector3.ONE * PlayerModels.SCALE),
			"the SKIN tab preview is drawn at %s, not the runner's %.2f" % [preview.global_basis.get_scale().abs(), PlayerModels.SCALE])
		_record("runner SKIN tab preview", "preview", _measure(preview, _runner_ref(host, PlayerModels.SCENE), PlayerModels.SCALE, preview.global_position.y), true)
	panel.queue_free()
	# Night Watch draws every hunter at its Last Route scale (KT's ruling): the one helper, in every mode, and the menu's camera preview matches it
	var offenders := []
	for dir_name in ["", "bedroom", "dayshift", "descent", "lure", "mask", "mixed", "openair", "story"]:
		var folder: String = ("res://src/night_watch/" + dir_name) if not dir_name.is_empty() else "res://src/night_watch"
		for file_name in DirAccess.get_files_at(folder):
			if not String(file_name).ends_with(".gd") or String(file_name) == "night_watch_hunter_scale.gd":
				continue
			var source := FileAccess.get_file_as_string("%s/%s" % [folder, file_name])
			if source.contains("ModelSlot.instantiate_hunter"):
				offenders.append("%s/%s" % [dir_name, file_name])
	_expect(offenders.is_empty(), "Night Watch scripts build hunters without NightWatchHunterScale (they would be drawn at 1.0): %s" % ", ".join(offenders))
	var tallest := 0.0
	var casts := {}
	for cast in [NightWatchData.CAST, DayshiftData.CAST, BedroomData.CAST, NightWatchDescentData.CAST, MaskData.CAST, NightWatchOpenAirData.CAST, LureData.CAST, StoryData.CAST]:
		for hunter_id in cast:
			casts[String(hunter_id)] = true
	_expect(casts.size() >= 20, "the Night Watch casts were not found (%d)" % casts.size())
	for hunter_id in casts:
		var identity := HunterRoster.get_identity(String(hunter_id))
		if identity.is_empty():
			continue
		var nw := NightWatchHunterScale.instantiate(identity)
		if nw == null:
			continue
		host.add_child(nw)
		await tree.process_frame
		var want := HunterRoster.scale_for(String(identity.get("id", hunter_id)))
		_expect(nw.global_basis.get_scale().is_equal_approx(Vector3.ONE * want), "Night Watch draws %s at %s, want its Last Route scale %.2f" % [hunter_id, nw.global_basis.get_scale(), want])
		tallest = maxf(tallest, _top(nw) - nw.global_position.y)
		nw.queue_free()
	# every Night Watch ceiling, door top and window top clears the tallest hunter (no head through a header or the ceiling)
	var heights := {"NightWatchOffice.HEIGHT": NightWatchOffice.HEIGHT, "NightWatchOffice.DOOR_H": NightWatchOffice.DOOR_H, "NightWatchBuilding.ROOM_H": NightWatchBuilding.ROOM_H,
		"NightWatchBuilding.DOOR_TOP": NightWatchBuilding.DOOR_TOP, "BedroomWing.HEIGHT": BedroomWing.HEIGHT, "BedroomWing.DOOR_TOP": BedroomWing.DOOR_TOP,
		"BedroomOffice.HEIGHT": BedroomOffice.HEIGHT, "Descent.HEIGHT": NightWatchDescentWorld.HEIGHT, "Descent.WINDOW_TOP": NightWatchDescentWorld.WINDOW_TOP,
		"LureWorld.HEIGHT": LureWorld.HEIGHT, "LureWorld.DOOR_TOP": LureWorld.DOOR_TOP, "StoryWorld.HEIGHT": StoryWorld.HEIGHT, "StoryWorld.DOOR_TOP": StoryWorld.DOOR_TOP,
		"ControlRoomOffice.HEIGHT": ControlRoomOffice.HEIGHT, "ControlRoomOffice.DOOR_TOP": ControlRoomOffice.DOOR_TOP, "MaskWorld.H": MaskWorld.H, "MaskOffice.HEIGHT": MaskOffice.HEIGHT}
	for key in heights:
		_expect(float(heights[key]) >= tallest + 0.1, "%s is %.2f m: a %.2f m Night Watch hunter would clip it" % [key, float(heights[key]), tallest])


func run(host: Node) -> int:
	await _hunters(host)
	await _grabs(host)
	await _runners(host)
	await _controller_and_guest(host)
	await _previews(host)
	var states := _rows.keys()
	states.sort()
	print("  %-46s %5s %7s %7s %7s %7s %7s  worst" % ["state", "n", "scale%", "seg%", "arm%", "top%", "head%"])
	for state in states:
		var row: Dictionary = _rows[state]
		print("  %-46s %5d %7.2f %7.2f %7.2f %+7.2f %+7.2f  %s" % [state, row["n"], float(row["scale"]) * 100.0, float(row["seg"]) * 100.0,
			float(row["arm"]) * 100.0, float(row["top"]) * 100.0, float(row["head"]) * 100.0, row["who"]])
	if _printed > 60:
		print("  ... and %d more failures" % (_printed - 60))
	if _failures == 0:
		print("  scale_consistency  %d states, every hunter and runner within %.0f%% of its reference" % [states.size(), TOLERANCE * 100.0])
	return _failures
