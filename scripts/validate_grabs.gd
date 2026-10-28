extends RefCounted

## Hunter grabs (GrabStyles, HunterGrab, docs/HUNTER_GRABS.md): every hunter has a valid weighted pool in res://data/grabs, the
## pick is seeded and respects the room, and every style plays: the runner's body, eye and skinned hands, the hunter's hands on
## the right body point, the state other players draw it from, and a clean release.
##   godot --headless --path . res://scenes/validate.tscn -- grabs

const NECK_LIFTERS := ["kathy", "xivvy", "umbriel", "elise", "wynelle", "ravelle"]
## A hunter whose model has arms, for each style (the creature rig for its own).
const STYLE_HUNTER := {
	"neck_lift": "kathy", "shoulder_grab": "dovelle", "tackle": "haelith", "wrist_yank": "aki", "wrap": "briselle",
	"leg_grab": "ceryth", "upside_down": "xivvy", "bear_hug": "kathy", "collar_drag": "javelle", "wall_pin": "opalie",
	"pounce_pin": SecretCreatures.IDS[0],
}
const LIFTED := ["neck_lift", "bear_hug", "upside_down"]
const FLOORED := ["tackle", "leg_grab", "pounce_pin"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _expect_pools() -> void:
	_expect(GrabStyles.errors().is_empty(), "res://data/grabs has errors: %s" % ", ".join(GrabStyles.errors()))
	var every: Array = HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS + SecretCreatures.IDS
	for id in every:
		var pool := GrabStyles.pool_for(String(id))
		var file := "%s/%s.json" % [GrabStyles.ROOT, id]
		_expect(FileAccess.file_exists(file), "%s has no grab pool file" % id)
		_expect(not pool.is_empty(), "%s has an empty grab pool" % id)
		var creature := GrabStyles.is_creature(String(id))
		_expect(pool.size() <= 4 and (pool.size() >= 2 or creature), "%s has %d grab styles (want 2-4)" % [id, pool.size()])
		var main := GrabStyles.main_style(String(id))
		for style in pool:
			_expect(GrabStyles.STYLES.has(style), "%s uses unknown style %s" % [id, style])
			_expect(bool(GrabStyles.STYLES[style].get("creature", false)) == creature, "%s: %s does not fit its body" % [id, style])
			if style != main:
				_expect(float(pool[style]) < float(pool[main]), "%s: %s weighs as much as the main style %s" % [id, style, main])
		_expect(NECK_LIFTERS.has(id) == (main == GrabStyles.NECK_LIFT), "%s: main style is %s" % [id, main])
		if String(id).begins_with("void_"):
			_expect(not pool.has(GrabStyles.NECK_LIFT), "%s neck-lifts (KT: Void stay out of it)" % id)
	for file_name in DirAccess.get_files_at(GrabStyles.ROOT):
		_expect(every.has(String(file_name).get_basename()), "data/grabs/%s is not a hunter" % file_name)
	# strict like ContentRegistry: unknown keys, styles and bad weights are errors
	_expect(not GrabStyles.parse_def({"schema": GrabStyles.SCHEMA, "id": "x", "pool": {"neck_lift": 1}, "extra": 1}, "t")["errors"].is_empty(),
		"an unknown key was accepted")
	_expect(not GrabStyles.parse_def({"schema": GrabStyles.SCHEMA, "id": "x", "pool": {"noogie": 1}}, "t")["errors"].is_empty(),
		"an unknown style was accepted")
	_expect(not GrabStyles.parse_def({"schema": GrabStyles.SCHEMA, "id": "x", "pool": {"wrap": 0}}, "t")["errors"].is_empty(),
		"a zero weight was accepted")
	_expect(not GrabStyles.parse_def({"schema": GrabStyles.SCHEMA, "id": "x", "pool": {}}, "t")["errors"].is_empty(),
		"an empty pool was accepted")


func _expect_picks() -> void:
	var open := {"ceiling": 4.0, "back": 3.0, "hunter_back": 3.0}
	_expect(GrabStyles.roll_for("SEED", 2, 1) == GrabStyles.roll_for("SEED", 2, 1), "the roll is not repeatable")
	_expect(GrabStyles.roll_for("SEED", 2, 1) != GrabStyles.roll_for("SEED", 2, 2), "two catches roll the same")
	for id in HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS:
		var seen := {}
		for i in 400:
			var roll := GrabStyles.roll_for("POOL-TEST", 1, i)
			var picked := GrabStyles.pick(String(id), roll, open)
			_expect(picked == GrabStyles.pick(String(id), roll, open), "%s: the same roll picked two styles" % id)
			seen[picked] = int(seen.get(picked, 0)) + 1
		var pool := GrabStyles.pool_for(String(id))
		for style in pool:
			if style == GrabStyles.WALL_PIN:
				continue   # needs a wall
			_expect(seen.has(style), "%s never picked %s in open space" % [id, style])
		var main := GrabStyles.main_style(String(id))
		if main != GrabStyles.WALL_PIN:
			for style in seen:
				_expect(int(seen[main]) >= int(seen[style]), "%s picked %s more often than its main style" % [id, style])
	# the room rules them out
	var low := {"ceiling": 2.1, "back": 3.0, "hunter_back": 3.0}
	for i in 200:
		var roll := GrabStyles.roll_for("LOW", 1, i)
		for id in NECK_LIFTERS:
			var picked := GrabStyles.pick(String(id), roll, low)
			_expect(not picked in [GrabStyles.NECK_LIFT, GrabStyles.UPSIDE_DOWN, GrabStyles.BEAR_HUG],
				"%s lifts under a 2.1 m ceiling (%s)" % [id, picked])
		var walled := GrabStyles.pick("opalie", roll, {"ceiling": 4.0, "back": .9, "hunter_back": 3.0})
		_expect(walled in [GrabStyles.SHOULDER_GRAB, GrabStyles.WALL_PIN], "opalie picked %s by a wall" % walled)
		_expect(GrabStyles.pick("opalie", roll, open) != GrabStyles.WALL_PIN, "a wall pin with no wall")
		_expect(GrabStyles.pick("haelith", roll, {"ceiling": 4.0, "back": .9, "hunter_back": 3.0}) != GrabStyles.TACKLE,
			"a tackle into a wall")
	_expect(GrabStyles.pick("elise", .5, {"ceiling": 2.0, "back": .1, "hunter_back": 0.0}) == GrabStyles.FALLBACK,
		"no fitting style did not fall back to the shoulder grab")
	_expect(GrabStyles.pick(SecretCreatures.IDS[0], .5, {"ceiling": 2.0, "back": .1}) == GrabStyles.POUNCE_PIN,
		"a creature rig fell back to a humanoid grab")


func _hunter(parent: Node, id: String, at: Vector3, facing: Vector3) -> HunterView3D:
	var brain := HunterBrain.new(Vector2(at.x, at.z), "GRAB-TEST", id, "standard")
	brain.activate_at(Vector2(at.x, at.z))
	var view := HunterView3D.new()
	view.brain = brain
	parent.add_child(view)
	view.global_position = at
	view.look_at(at + facing, Vector3.UP)
	return view


func _expect_skinned(hands: Node3D, label: String) -> void:
	_expect(hands != null and hands.visible, "%s: the grab hands are not shown" % label)
	if hands == null:
		return
	for node in hands.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		_expect(not mesh_node.mesh is BoxMesh, "%s: a grab hand is a placeholder box" % label)
		var material := mesh_node.get_active_material(0)
		if material is StandardMaterial3D:
			_expect((material as StandardMaterial3D).albedo_texture != null, "%s: a grab hand is not skin-textured" % label)
	var left := hands.get_node("L").get_child(0) as Node3D
	var right := hands.get_node("R").get_child(0) as Node3D
	_expect(left.scale.x * right.scale.x < 0.0, "%s: the left grab hand is not mirrored" % label)


func _expect_style(route: Node, player: PlayerController3D, grab: HunterGrab, style: String, stand: Vector3, facing: Vector3) -> void:
	var id := String(STYLE_HUNTER[style])
	player.global_position = stand
	var view := _hunter(route, id, stand + facing * .8, -facing)
	await route.get_tree().process_frame
	var model := view.get("_model") as Node3D
	var rest := model.transform if model != null else Transform3D.IDENTITY
	await grab.play(player, view, id, .5, style)
	await route.get_tree().process_frame
	_expect(grab.style == style, "%s played %s" % [style, grab.style])
	_expect(player.grab_active, "%s: the runner is not held" % style)
	var state: Array = player.grab_state
	_expect(state.size() == 7 and String(state[0]) == style, "%s: the state other players get is %s" % [style, state])
	var pose := grab.current
	var lift := float(state[2]) if state.size() == 7 else 0.0
	var eye := player.active_camera().global_position.y - stand.y
	if style in LIFTED:
		_expect(lift > .2, "%s: the runner's feet are only %.2f m off the floor" % [style, lift])
	if style in FLOORED:
		_expect(eye < .8, "%s: the eye is %.2f m up, not down on the floor" % [style, eye])
	if style == "upside_down":
		_expect(absf(absf(player.grab_roll) - PI) < .3, "upside_down: the view is not inverted (roll %.2f)" % player.grab_roll)
	if style == "leg_grab":
		var ahead := Vector2(-sin(GrabStyles.body_yaw(grab._along, -1.0)), -cos(GrabStyles.body_yaw(grab._along, -1.0)))
		_expect(float(pose["face"]) < 0.0, "%s: the body faces the hunter" % style)
		_expect(ahead.dot(Vector2(facing.x, facing.z)) < -.5, "%s: the runner does not face away from the hunter" % style)
	_expect(player.current_clip() == String(pose["clip"]), "%s: the body plays %s" % [style, player.current_clip()])
	_expect_skinned(player._grab_hands, style)
	# the hunter's hands are on the body point the style names
	var feet := player.global_position + Vector3.UP * lift
	var basis := GrabStyles.body_basis(grab._along, float(pose["face"]), float(pose["tilt"]))
	for entry in pose["arms"]:
		var hand := view.find_child("%s-Hand" % entry[0], true, false) as Node3D
		var target := feet + basis * (GrabStyles.BODY_POINTS[String(entry[1])] as Vector3)
		_expect(hand != null and hand.global_position.distance_to(target) < .5,
			"%s: the hunter's %s hand is %.2f m from the runner's %s" % [style, entry[0],
				hand.global_position.distance_to(target) if hand else -1.0, entry[1]])
	# other players: the runner's own state carries it, and their copy of the body is taken the same way
	var remote := RemotePlayers.new()
	remote.local_player = player
	route.add_child(remote)
	var sent := RemotePlayers._grab_packet(remote._local_state())
	_expect(sent.size() == 7 and String(sent[0]) == style, "%s: the runner's state does not carry the grab" % style)
	if not (pose["arms"] as Array).is_empty() and sent.size() == 7:
		var body := ModelSlot.instantiate(PlayerModels.SCENE)
		route.add_child(body)
		body.scale = Vector3.ONE * PlayerModels.SCALE
		body.global_position = player.global_position + Vector3.UP * float(sent[2])
		body.global_basis = Basis.from_euler(Vector3(float(sent[3]), GrabStyles.body_yaw(grab._along, float(pose["face"])), 0.0)) * Basis.from_scale(body.scale)
		HunterGrab.pose_nearest_hunter(remote, body, sent)
		var entry: Array = (pose["arms"] as Array)[0]
		var hand := view.find_child("%s-Hand" % entry[0], true, false) as Node3D
		var target := body.global_position + body.global_basis.orthonormalized() * (GrabStyles.BODY_POINTS[String(entry[1])] as Vector3)
		_expect(hand.global_position.distance_to(target) < .5, "%s: a guest sees the hunter's hand %.2f m from the %s" % [style,
			hand.global_position.distance_to(target), entry[1]])
		body.queue_free()
	remote.queue_free()
	grab.release()
	_expect(not player.grab_active and player.grab_state.is_empty() and not player._grab_hands.visible, "%s: release left the runner held" % style)
	_expect(absf(player.first_person_pivot.rotation.z) < .001, "%s: the view stays rolled after release" % style)
	if model != null:
		_expect(model.transform.is_equal_approx(rest), "%s: the hunter's model was not put back" % style)
	view.queue_free()
	await route.get_tree().process_frame


func run(host: Node) -> int:
	_expect_pools()
	_expect_picks()
	var route: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	var player := route.get("player") as PlayerController3D
	var grab := route.get("grab") as HunterGrab
	_expect(grab != null, "the route has no HunterGrab")
	if player != null and grab != null:
		player.input_frozen = true
		player.look_frozen = true
		var stand := player.global_position
		var facing := -player.global_basis.z
		facing.y = 0.0
		facing = facing.normalized()
		for style in GrabStyles.STYLES:
			await _expect_style(route, player, grab, String(style), stand, facing)
		player.global_position = stand
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  grabs     %d styles, %d pools, seeded room-aware pick, skinned hands, guest view" % [GrabStyles.STYLES.size(),
			HunterRoster.A_Z_IDS.size() + HunterRoster.VOID_IDS.size() + SecretCreatures.IDS.size()])
		print("grabs: all checks OK")
	return _failures
