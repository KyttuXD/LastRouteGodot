extends RefCounted

## Headless check on the shared player body.
##
## This suite exists because the previous mannequin passed every check the
## project had and was still visibly broken in game: limbs floating apart, one
## flat tan colour over the whole figure. Nothing was asking the only questions
## that matter about a body -- is it person-shaped, is it the right size, and
## does it have the clips the game plays on it -- because those had always been
## "look at it" questions.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- body

## The capsule in main_3d.tscn: radius 0.25, height 1.7, centred at y=0.85.
const HEIGHT := 1.7
const RADIUS := 0.25
const CLIPS := ["idle", "walk", "sprint", "chase", "crouch"]

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	var body: Node3D = ModelSlot.instantiate("res://art/props-3d/characters/player.tscn")
	if body == null:
		_fail("the player body scene did not instantiate")
		return _failures
	host.get_tree().root.add_child(body)
	await host.get_tree().process_frame

	var parts := _parts(body)
	if parts.is_empty():
		_fail("the player body has no meshes -- players would be invisible")
		body.queue_free()
		return _failures

	_fits_the_capsule(parts)
	_is_one_figure(parts)
	_carries_its_clips(body)
	_wears_no_colliders(body)

	var whole: AABB = parts[0]["box"]
	for part in parts:
		whole = whole.merge(part["box"])
	print("  figure    %d parts, %.2f m tall, %.2f m across, feet at %.3f"
		% [parts.size(), whole.size.y, whole.size.x, whole.position.y])
	print("  clips     %s" % ", ".join(CLIPS))
	if _failures == 0:
		print("body OK")

	body.queue_free()
	return _failures


func _parts(body: Node3D) -> Array:
	var out := []
	for node in _walk(body):
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			out.append({"name": mesh.name, "box": mesh.global_transform * mesh.get_aabb()})
	return out


func _walk(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out += _walk(child)
	return out


## A body that does not match its own collider walks through walls its capsule
## stops at, or floats above the floor it stands on.
func _fits_the_capsule(parts: Array) -> void:
	var whole: AABB = parts[0]["box"]
	for part in parts:
		whole = whole.merge(part["box"])
	_expect(absf(whole.position.y) < 0.05,
		"the body's feet sit at y=%.3f instead of on the floor" % whole.position.y)
	_expect(absf(whole.size.y - HEIGHT) < 0.08,
		"the body is %.2f m tall; its capsule is %.2f m" % [whole.size.y, HEIGHT])
	# Arms out to the side are wider than the capsule and that is fine; a body
	# twice its own collider is not.
	_expect(whole.size.x < RADIUS * 4.0,
		"the body is %.2f m across, far wider than its %.2f m collider"
			% [whole.size.x, RADIUS * 2.0])


## Every part touches another part. The old mannequin's head, arms and legs
## hung in the air with daylight between them, which no flag anywhere recorded.
func _is_one_figure(parts: Array) -> void:
	for part in parts:
		var box: AABB = (part["box"] as AABB).grow(0.02)
		var touches := false
		for other in parts:
			if other["name"] == part["name"]:
				continue
			if box.intersects(other["box"]):
				touches = true
				break
		if not touches:
			_fail("'%s' floats free of the rest of the body" % part["name"])


## ModelSlot asks for these by name, and AnimationPlayer.has_animation is
## case-sensitive, so a renamed clip is a silently frozen player.
func _carries_its_clips(body: Node3D) -> void:
	var player := ModelSlot.find_animation_player(body)
	if player == null:
		_fail("the body has no AnimationPlayer, so remote players never move")
		return
	for clip in CLIPS:
		if not player.has_animation(clip):
			_fail("the body has no '%s' clip" % clip)
			continue
		var animation := player.get_animation(clip)
		_expect(animation.loop_mode != Animation.LOOP_NONE,
			"'%s' does not loop, so it plays once and the body freezes" % clip)


## A character's only collider is the CharacterBody3D's own shape. Exported
## "-colonly" meshes gave the first mannequin twenty-one static bodies of its
## own and dropped the player through the floor.
func _wears_no_colliders(body: Node3D) -> void:
	for node in _walk(body):
		if node is CollisionObject3D:
			_fail("the body carries its own collider '%s'" % node.name)
