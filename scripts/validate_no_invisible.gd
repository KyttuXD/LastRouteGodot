extends RefCounted

## No full invisibility (KT 2026-10-28): every hunter gimmick, awake and in the world, draws at least
## HunterView3D.MIN_VISIBLE_ALPHA of her model -- model visible, fade never past it, and the faded pixels survive the
## alpha test; dormant hunters are drawn whole in their dormant pose. Checked for every roster identity in its default state and with her gimmick forced into its hidden state.
##
##   godot --headless --path . res://scenes/validate.tscn -- no_invisible


class ForcedHidden:
	extends HunterGimmick
	func hidden_from_view() -> bool:
		return true


var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _alpha_of(view: HunterView3D) -> float:
	var model: Node = view._model
	if model == null or not (model as Node3D).visible:
		return 0.0
	var lowest := 1.0
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GeometryInstance3D and (node as GeometryInstance3D).visible:
			lowest = minf(lowest, 1.0 - (node as GeometryInstance3D).transparency)
		stack.append_array(node.get_children())
	return lowest if ModelSlot.fade_survives_alpha_test(model, 1.0 - lowest) else 0.0


func run(host: Node) -> int:
	_expect(HunterView3D.MIN_VISIBLE_ALPHA >= .2, "the stealth floor is below 20%")
	var ids: Array = HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS + HunterRoster.OFFICE_VOID_IDS
	var checked := 0
	for id_value in ids:
		var id := String(id_value)
		for forced in [false, true]:
			var brain := HunterBrain.new(Vector2(5, 5), "NOINV:%s" % id, id, "nightmare")
			brain.active = true
			if forced:
				brain.gimmick = ForcedHidden.new()
			var view := HunterView3D.new()
			view.brain = brain
			host.add_child(view)
			await host.get_tree().process_frame
			brain.active = true
			view.sync_from_brain()
			view._apply_visibility()
			var retired: bool = brain.gimmick is CerythGimmick and (brain.gimmick as CerythGimmick).dispersed
			if not retired:
				var alpha := _alpha_of(view)
				_expect(alpha >= HunterView3D.MIN_VISIBLE_ALPHA - .01,
					"%s%s is drawn at %.2f while awake (floor %.2f)" % [id, " (hidden)" if forced else "", alpha, HunterView3D.MIN_VISIBLE_ALPHA])
				_expect(HunterView3D.model_alpha(brain) >= HunterView3D.MIN_VISIBLE_ALPHA, "%s model_alpha is below the floor" % id)
				checked += 1
			view.queue_free()
	# dormant hunters (a route hunter before her relay, Nyxie / Solyth / Wynelle) are drawn whole, in the dormant pose
	for id in ["dovelle", "nyxie", "solyth", "wynelle"]:
		var sleeping := HunterBrain.new(Vector2(5, 5), "NOINV:SLEEP:%s" % id, id, "standard")
		sleeping.active = false
		var view := HunterView3D.new()
		view.brain = sleeping
		host.add_child(view)
		await host.get_tree().process_frame
		sleeping.active = false
		view.sync_from_brain()
		view._apply_visibility()
		view._update_animation()
		_expect(HunterView3D.model_alpha(sleeping) == 1.0 and _alpha_of(view) >= .99, "dormant %s is not drawn (%.2f)" % [id, _alpha_of(view)])
		if view._animation_player != null:
			_expect(view._animation_player.speed_scale <= HunterView3D.DORMANT_SPEED + .001, "dormant %s is not held still" % id)
		# waking plays the wake-up once
		sleeping.active = true
		view._update_animation()
		if view._animation_player != null and view._animation_player.has_animation("stun_recover"):
			_expect(view._recover_left > 0.0, "%s woke without the wake-up" % id)
		view.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  ok    no_invisible: %d awake hunter states drawn at >= %.0f%%" % [checked, HunterView3D.MIN_VISIBLE_ALPHA * 100.0])
	return _failures
