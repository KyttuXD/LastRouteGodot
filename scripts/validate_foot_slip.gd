extends RefCounted

## Foot slip: the planted foot must stay on the ground while a hunter travels. For every model (38 hunters, tall variants,
## the mannequin, both spiders) this re-measures the walk/chase/sprint clips by forward kinematics, checks the stored
## stride table is not stale, that no clip strides backwards (moonwalk), and that at every pace a hunter really moves
## (base speed, chase speed, the visible-chase speed and the Night Watch pace range 1.2-6.0 m/s) the clip HunterStride
## picks keeps the net slip of a planted foot below 10 % of the speed. A real HunterView3D then walks 10 m at a few
## speeds and must pick the same clip and scale, face along its travel, and stand (not tread) when stopped.
##
##   godot --headless --path . res://scenes/validate.tscn -- foot_slip

const MAX_SLIP := .10
const STALE := .02
const PACES := [1.2, 2.4, 4.0, 6.0]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _models() -> Array:
	var out: Array = []
	for dir in DirAccess.get_directories_at("res://assets/hunters_blocky"):
		if ResourceLoader.exists("res://assets/hunters_blocky/%s/%s.glb" % [dir, dir]):
			out.append({"id": dir, "path": "res://assets/hunters_blocky/%s/%s.glb" % [dir, dir], "humanoid": true})
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	for id in SecretCreatures.IDS:
		out.append({"id": id, "path": String(SecretCreatures.PROFILES[id]["model"]), "humanoid": false})
	return out


func _speeds(id: String) -> Array:
	var speeds := PACES.duplicate()
	if HunterRoster.A_Z_IDS.has(id) or HunterRoster.VOID_IDS.has(id):
		var identity := HunterRoster.get_identity(id)
		speeds.append(float(identity["base_speed"]))
		speeds.append(float(identity["chase_speed"]))
		speeds.append(float(identity["chase_speed"]) * GameConfig.HUNTER_VISIBLE_CHASE_SPEED_SCALE)
	return speeds


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame
	var table := HunterStride.table()
	_expect(not table.is_empty(), "stride_table.json did not load (run tools/look/stride_table.tscn)")
	var worst_slip := 0.0
	var worst_who := ""
	var checked := 0
	for entry in _models():
		var id: String = entry["id"]
		var model := (load(entry["path"]) as PackedScene).instantiate() as Node3D
		host.add_child(model)
		var player := ModelSlot.find_animation_player(model)
		var feet: Array = HunterStride.HUMANOID_FEET
		if not entry["humanoid"]:
			feet = []
			for node in model.find_children("*oot*", "Node3D", true, false):
				feet.append(String(node.name))
		var measured := {}
		for clip in ["walk", "chase", "sprint", "scythe_walk", "sprint"]:
			if player == null or not player.has_animation(clip) or not table.get(id, {}).has(clip):
				continue
			var m := HunterStride.measure(model, player.get_animation(clip), feet, entry["humanoid"], model.scale.y)
			measured[clip] = m
			_expect(float(m["ref"]) > .3, "%s/%s has no stride (planted foot speed %.2f)" % [id, clip, m["ref"]])
			_expect(bool(m["forward_ok"]) != bool(m["reverse"]) or bool(m["forward_ok"]), "%s/%s moonwalks" % [id, clip])
			_expect(bool(table[id][clip].get("reverse", false)) == bool(m["reverse"]), "%s/%s: the table's reverse flag is stale" % [id, clip])
			if entry["humanoid"]:
				_expect(bool(m["forward_ok"]) and not bool(m["reverse"]), "%s/%s moonwalks: the planted foot moves FORWARD relative to the body" % [id, clip])
			var stored := float(table[id][clip]["ref"])
			_expect(absf(stored - float(m["ref"])) <= STALE * maxf(stored, .5) + .004, "%s/%s: stride table is stale (%.3f stored, %.3f measured)" % [id, clip, stored, m["ref"]])
		for required in ["walk", "sprint"] if not entry["humanoid"] else ["walk", "chase"]:
			_expect(measured.has(required), "%s: no measured %s clip" % [id, required])
		# net slip of a planted foot at each pace with the clip/scale the view would choose
		var candidates: Array = HunterStride.TRAVEL_CLIPS if entry["humanoid"] else ["walk", "sprint"]
		for speed in _speeds(id):
			var preferred := "walk" if speed < 3.0 else ("chase" if speed < 5.0 or not measured.has("sprint") else "sprint")
			if not measured.has(preferred):
				preferred = "walk"
			var pick := HunterStride.choose(id, preferred, speed, candidates)
			var clip: String = pick["clip"]
			if not measured.has(clip):
				continue
			var foot_speed: float = float(measured[clip]["ref"]) * absf(float(pick["scale"]))
			var slip: float = absf(foot_speed - speed) / speed
			var clamped: bool = absf(float(pick["scale"])) <= HunterStride.HARD_MIN + .001 or absf(float(pick["scale"])) >= HunterStride.HARD_MAX - .001
			checked += 1
			if not clamped and slip > worst_slip:
				worst_slip = slip
				worst_who = "%s %s @ %.1f m/s" % [id, clip, speed]
			if not clamped:
				_expect(slip <= MAX_SLIP, "%s: %s at %.1f m/s slips %.0f %% of the speed" % [id, clip, speed, slip * 100.0])
		model.queue_free()
	print("  foot_slip: %d pace checks, worst planted-foot slip %.1f %% (%s)" % [checked, worst_slip * 100.0, worst_who])

	# ---- a real view walking 10 m
	for hunter_id in ["dovelle", "glyra_tall" if false else "aki_tall", "kathy"]:
		for speed in [1.4, 3.6]:
			var brain := HunterBrain.new(Vector2(5.5, 5.5), "SLIP-TEST", hunter_id, "standard")
			brain.activate_at(Vector2(5.5, 5.5))
			brain.state = HunterBrain.State.CHASE if speed > 3.0 else HunterBrain.State.WANDER
			var view := HunterView3D.new()
			view.brain = brain
			host.add_child(view)
			await tree.process_frame
			view.sync_from_brain()
			var travelled := 0.0
			var frames := 0
			while travelled < 10.0 and frames < 2400:
				await tree.process_frame
				var delta := maxf(host.get_process_delta_time(), 1.0 / 240.0)
				brain.position += Vector2(1, 0) * speed * delta
				travelled += speed * delta
				brain.facing = Vector2(1, 0)
				view.sync_from_brain()
				frames += 1
				if travelled > 4.0 and not (view._animation_player.current_animation in ["idle"]):
					pass
			var pick := HunterStride.choose(hunter_id, "chase" if speed > 3.0 else "walk", speed)
			var player: AnimationPlayer = view._animation_player
			var want_clip := String(pick["clip"])
			var playing := String(player.current_animation)
			_expect(playing == want_clip or (hunter_id == "kathy" and playing.begins_with("scythe")), "%s at %.1f m/s should play %s, plays %s" % [hunter_id, speed, want_clip, playing])
			_expect(absf(player.speed_scale - float(pick["scale"])) < .25 * float(pick["scale"]) + .05 or playing.begins_with("scythe"), "%s at %.1f m/s: speed_scale %.2f, expected about %.2f" % [hunter_id, speed, player.speed_scale, pick["scale"]])
			var off := absf(wrapf(view.rotation.y - atan2(-1.0, 0.0), -PI, PI))
			_expect(off < deg_to_rad(15.0), "%s walks sideways to her facing (%.0f deg off)" % [hunter_id, rad_to_deg(off)])
			for i in 80:
				await tree.process_frame
				view.sync_from_brain()
			_expect(view._animation_player.current_animation == "idle" or view._animation_player.current_animation == "scythe_idle", "%s should stand when stopped, plays %s" % [hunter_id, view._animation_player.current_animation])
			view.queue_free()

	if _failures == 0:
		print("  ok    foot_slip: stride table current, no moonwalk, planted-foot slip under 10 %, the view follows the table")
	return _failures
