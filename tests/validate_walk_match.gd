extends RefCounted

## Walk match: the walk and sprint clips of the runner's mannequin and two hunters (elise, aki) must keep the planted foot
## within 15 % of the real speed. The runner walks at PLAYER_WALK_SPEED and sprints at PLAYER_SPRINT_SPEED (px/s at TILE_SIZE
## px per metre); a hunter walks at her base speed and chases at her chase speed (depth 1, standard difficulty), and at depth 4,
## where her depth bonus raises both. Each speed is played the way the game plays it: PlayerStride.pick for the runner,
## HunterStride.choose for hunters. A clamped pick is not exempt, so a scale that the clamp pins away from the real pace fails
## here. Each stored reference must also match a fresh measure of its GLB at the size the game draws it, so a stale table fails too.
## The speed_scale the runner's own body and its remote copy actually get are checked as well: the test drives
## PlayerController3D._drive_travel_pace and RemotePlayers._drive_remote_pace (the calls the game makes each frame) at the real
## speeds until the ease settles, then measures the planted foot at the speed_scale they left on the body.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- walk_match

const MAX_ERROR := .15
const STALE := .02
const HUNTERS := ["elise", "aki"]
const DEPTHS := [1, 4]
const RUNNER_MODEL := "res://assets/hunters_blocky/player_mannequin/player_mannequin.glb"
## 2 s at 60 fps: the ease in the controller's and the remote copy's pace settles well inside this.
const SETTLE_FRAMES := 120
const FRAME := 1.0 / 60.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame
	var table := HunterStride.table()
	_expect(table.has(PlayerStride.TABLE_ID), "stride_table.json has no %s entry (run dev/look/stride_table.tscn)" % PlayerStride.TABLE_ID)

	# the runner: its own mannequin at PlayerModels.SCALE, walking and sprinting at the controller's real speeds
	var runner_plays := [
		["walk", GameConfig.PLAYER_WALK_SPEED / GameConfig.TILE_SIZE, ""],
		["sprint", GameConfig.PLAYER_SPRINT_SPEED / GameConfig.TILE_SIZE, ""],
	]
	_check(host, "runner", PlayerStride.TABLE_ID, RUNNER_MODEL, PlayerModels.SCALE, true, runner_plays)
	# the speed_scale the runner's own body gets from the controller, and the one a teammate's copy gets from RemotePlayers
	_check_body(host, "runner body", true)
	_check_body(host, "remote copy", false)

	# two hunters: the walk and the chase at depth 1 (her base and chase speeds), then the same walk and chase at each depth
	for id in HUNTERS:
		var identity := HunterRoster.get_identity(id)
		var hunter_plays := [
			["walk", float(identity["base_speed"]), "depth 1"],
			["chase", float(identity["chase_speed"]), "depth 1"],
		]
		for depth in DEPTHS:
			hunter_plays.append(["walk", _hunter_speed(id, HunterBrain.State.WANDER, depth), "depth %d" % depth])
			hunter_plays.append(["chase", _hunter_speed(id, HunterBrain.State.CHASE, depth), "depth %d" % depth])
		_check(host, id, id, "res://assets/hunters_blocky/%s/%s.glb" % [id, id], HunterStride.model_scale(id), false, hunter_plays)

	if _failures == 0:
		print("  ok    walk_match: the runner's, its remote copy's and two hunters' walk and sprint clips plant their feet within 15 % of the real speed (hunters at depths 1 and 4)")
	return _failures


## The speed the game gives a hunter in `state` at `depth` (no relays): HunterBrain._current_speed, the pace she walks or chases at.
func _hunter_speed(hunter_id: String, state: HunterBrain.State, depth: int) -> float:
	var brain := HunterBrain.new(Vector2(5, 5), "MATCH-TEST", hunter_id, "standard")
	brain.activate_at(Vector2(5, 5))
	brain.state = state
	return brain._current_speed(depth, 0)


## Measures the model's travel clips fresh, then checks the clip each real speed plays against that speed.
func _check(host: Node, label: String, table_id: String, path: String, scale: float, runner: bool, plays: Array) -> void:
	var table := HunterStride.table()
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * scale
	host.add_child(model)
	var player := ModelSlot.find_animation_player(model)
	var measured := {}
	for clip in ["walk", "chase", "sprint"]:
		if player == null or not player.has_animation(clip) or not table.get(table_id, {}).has(clip):
			continue
		var m := HunterStride.measure(model, player.get_animation(clip), HunterStride.HUMANOID_FEET, true, model.scale.y)
		measured[clip] = m
		var stored := float(table[table_id][clip]["ref"]) * HunterStride.model_scale(table_id)
		_expect(absf(stored - float(m["ref"])) <= STALE * maxf(stored, .5) + .004,
			"%s/%s: stride table is stale (%.3f stored, %.3f measured)" % [label, clip, stored, m["ref"]])
	for play in plays:
		var state := String(play[0])
		var speed := float(play[1])
		var where := "%s %s" % [label, state] if String(play[2]).is_empty() else "%s %s (%s)" % [label, state, play[2]]
		var pick: Dictionary = PlayerStride.pick(state, speed) if runner \
			else HunterStride.choose(table_id, state, speed)
		var clip := String(pick["clip"])
		if not measured.has(clip):
			_expect(false, "%s: no measured %s clip for a %s pace" % [label, clip, state])
			continue
		var foot := float(measured[clip]["ref"]) * absf(float(pick["scale"]))
		var error := (foot - speed) / speed
		print("  walk_match: %s at %.2f m/s plays %s x%.3f, planted foot %.2f m/s (%+.1f %%)"
			% [where, speed, clip, float(pick["scale"]), foot, error * 100.0])
		_expect(absf(error) <= MAX_ERROR,
			"%s at %.2f m/s plays %s x%.3f: planted foot %.2f m/s, %+.0f %% off the real speed" % [where, speed, clip, float(pick["scale"]), foot, error * 100.0])
	model.queue_free()


## The runner's body at its real walk and sprint speeds, driven the way the game drives it. `controller` true: the walk or sprint
## speed_scale PlayerController3D._drive_travel_pace sets on the body each physics frame. False: a teammate's copy, whose speed_scale
## RemotePlayers._drive_remote_pace sets from how far the copy moved that frame. Once the ease has settled, the clip that is playing
## must be the one PlayerStride picks, and its planted foot must sit within MAX_ERROR of the real speed.
func _check_body(host: Node, label: String, controller: bool) -> void:
	var plays := [["walk", GameConfig.PLAYER_WALK_SPEED / GameConfig.TILE_SIZE], ["sprint", GameConfig.PLAYER_SPRINT_SPEED / GameConfig.TILE_SIZE]]
	for play in plays:
		var state := String(play[0])
		var speed := float(play[1])
		var model := (load(RUNNER_MODEL) as PackedScene).instantiate() as Node3D
		model.scale = Vector3.ONE * PlayerModels.SCALE
		host.add_child(model)
		var player := ModelSlot.find_animation_player(model)
		var pick: Dictionary = PlayerStride.pick(state, speed)
		var clip := String(pick["clip"])
		if player == null or not player.has_animation(clip):
			_expect(false, "%s: the runner model has no %s clip" % [label, clip])
			model.queue_free()
			continue
		if controller:
			var body := PlayerController3D.new()
			body._animation_player = player
			body._clip = state
			body._pace_speed = speed
			for _i in SETTLE_FRAMES:
				body._drive_travel_pace(FRAME)
			body.free()
		else:
			var remotes := RemotePlayers.new()
			var copy := Node3D.new()
			host.add_child(copy)
			copy.set_meta("movement_clip", state)
			remotes._players[1] = player
			for _i in SETTLE_FRAMES:
				var previous := copy.global_position
				copy.global_position += Vector3(speed * FRAME, 0.0, 0.0)
				remotes._drive_remote_pace(1, copy, previous, FRAME)
			copy.queue_free()
			remotes.free()
		var m := HunterStride.measure(model, player.get_animation(clip), HunterStride.HUMANOID_FEET, true, model.scale.y)
		var played := String(player.assigned_animation)
		var foot := float(m["ref"]) * absf(player.speed_scale)
		var error := (foot - speed) / speed
		print("  walk_match: %s %s at %.2f m/s plays %s (%s), speed_scale %.3f, planted foot %.2f m/s (%+.1f %%)"
			% [label, state, speed, played, clip, player.speed_scale, foot, error * 100.0])
		_expect(played == clip, "%s %s at %.2f m/s plays %s, not %s" % [label, state, speed, played, clip])
		_expect(absf(error) <= MAX_ERROR,
			"%s %s at %.2f m/s plays %s with speed_scale %.3f: planted foot %.2f m/s, %+.0f %% off the real speed"
			% [label, state, speed, clip, player.speed_scale, foot, error * 100.0])
		model.queue_free()
