extends RefCounted

## Hunters never camp a hiding spot. A runner hides in view of a hunter (torch on, aimed at her): within the mode's camp_limit she
## has either checked the spot (the scene's hide check) or left, and the total time she spends within 2 cells of the hider stays
## bounded (one visit at a time; a hunter who catches the hider, like Elise, has resolved it) -- including White Void, whose frozen-by-torch rule used to pin her to a hider's spot for good.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- camping

const STEP := 1.0 / 30.0
const HUNTERS := ["void_white", "void_red", "void_blue", "void_black", "void_green", "dovelle", "kathy", "elise", "xivvy"]

var _failures := 0


class Field:
	var safe_zones: Array = []
	var exit_cell := Vector2i(-1, -1)
	var rooms: Array = []
	var relays: Array = []
	var vents: Array = []
	var hiding_spots: Array = []

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return true

	func can_occupy(_x: float, _y: float, _radius: float = .23, _blocked_cells = null) -> bool:
		return true

	func nearest_open_position(x: float, y: float, _radius: float = 1.0, _blocked = null) -> Dictionary:
		return {"x": x, "y": y}

	func room_at(_x: float, _y: float) -> Dictionary:
		return {}

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		var result := [from]
		var cursor := from
		while cursor != to:
			if cursor.x != to.x:
				cursor.x += 1 if to.x > cursor.x else -1
			else:
				cursor.y += 1 if to.y > cursor.y else -1
			result.append(cursor)
		return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	await host.get_tree().process_frame
	var spot := Vector2(30.5, 30.5)
	for mode in ["standard", "hard", "nightmare"]:
		var limit := float(GameConfig.difficulty_profile(mode)["camp_limit"])
		for id in HUNTERS:
			var brain := HunterBrain.new(spot + Vector2(-1.5, 0), "CAMP-%s-%s" % [id, mode], id, mode)
			brain.activate_at(spot)
			brain.state = HunterBrain.State.CHASE
			brain.has_last_known = true
			brain.last_known = spot
			var stretch := 0.0
			var longest := 0.0
			var caught := false
			var clock := 0.0
			var field := Field.new()
			while clock < 90.0 and not caught:
				clock += STEP
				var target := {"peer_id": 1, "position": spot, "hidden": true, "hiding_spot": Vector2i(30, 30), "in_safe_zone": false,
					"noise": 0.0, "flashlight_on": true, "facing": Vector2(-1, 0), "meters": null}
				caught = brain.update(STEP, field, target, 1, 0)
				if brain.position.distance_to(spot) <= HunterBrain.CAMP_RADIUS:
					if brain.stun_timer <= 0.0:
						stretch += STEP
						longest = maxf(longest, stretch)
				else:
					stretch = 0.0
			_expect(caught or longest <= limit + 4.0, "%s on %s camped %.1f s in one visit within 2 cells of a hider (limit %.0f)" % [id, mode, longest, limit])
	# the limit scales with the mode
	_expect(float(GameConfig.difficulty_profile("standard")["camp_limit"]) < float(GameConfig.difficulty_profile("hard")["camp_limit"])
		and float(GameConfig.difficulty_profile("hard")["camp_limit"]) < float(GameConfig.difficulty_profile("nightmare")["camp_limit"]), "camp limit rises with the mode")
	# a torch inside the hiding spot does not freeze White Void
	var white := HunterBrain.new(spot + Vector2(-3, 0), "WHITE", "void_white", "hard")
	white.activate_at(spot)
	var target := {"peer_id": 1, "position": spot, "hidden": true, "in_safe_zone": false, "noise": 0.0, "flashlight_on": true,
		"facing": Vector2(-1, 0), "meters": null}
	white.update(STEP, Field.new(), target, 1, 0)
	_expect(not (white.gimmick as VoidWhiteGimmick).lit, "a hider's torch does not freeze White Void")
	var open_target := target.duplicate()
	open_target["hidden"] = false
	white.update(STEP, Field.new(), open_target, 1, 0)
	_expect((white.gimmick as VoidWhiteGimmick).lit, "an open-air torch still freezes White Void")

	if _failures == 0:
		print("  ok    camping: no hunter camps a hider beyond the mode's limit (standard / hard / nightmare), White Void included")
	return _failures
