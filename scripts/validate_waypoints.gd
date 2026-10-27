extends RefCounted

## Waypoints (docs/WAYPOINTS.md): one per player, replace/clear/arrival, per-player independence and replication through the
## world-state snapshot (late joiners), the legacy multi-waypoint save migration, the screen-edge clamp at the common window
## sizes, the controls registration (no key conflicts), and the settings round trip.
##
##   godot --headless --path . res://scenes/validate.tscn -- waypoints

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_check_single_waypoint()
	_check_players_are_independent()
	_check_replication_and_late_join()
	_check_legacy_migration()
	_check_edge_clamp()
	_check_controls()
	_check_settings()
	if _failures == 0:
		print("  waypoints  one per player (place twice -> one, also in the City), replace/clear/arrival, snapshots and legacy saves, edge clamp at 3 sizes, B/V bindings, settings round trip")
	return _failures


func _check_single_waypoint() -> void:
	var state := WaypointState.new()
	state.place(1, Vector2(10.2, 4.7), 0)
	state.place(1, Vector2(30.8, 9.1), 0)
	_expect(state.by_peer.size() == 1, "placing twice left %d waypoints" % state.by_peer.size())
	_expect((state.get_for(1)["at"] as Vector2).is_equal_approx(Vector2(30.5, 9.5)), "the second waypoint did not replace the first / snap to the cell centre")
	_expect(state.place(1, Vector2(1, 1), 0)["replaced"], "place did not report that it replaced a waypoint")
	_expect(state.clear(1) and state.by_peer.is_empty() and not state.clear(1), "clear should remove it once")
	state.place(1, Vector2(10.5, 10.5), 2)
	_expect(not state.reached(1, Vector2(10.5, 10.5), 0), "arrival counted on another level")
	_expect(state.reached(1, Vector2(10.5 + WaypointState.ARRIVAL_RADIUS - .1, 10.5), 2), "inside the arrival radius did not count")
	_expect(not state.reached(1, Vector2(10.5 + WaypointState.ARRIVAL_RADIUS + .5, 10.5), 2), "outside the arrival radius counted")
	for _i in 50:
		state.place(1, Vector2(randf() * 100.0, randf() * 100.0), 0)
	_expect(state.by_peer.size() == 1, "repeated placing grew the set to %d" % state.by_peer.size())


func _check_players_are_independent() -> void:
	var state := WaypointState.new()
	state.place(1, Vector2(5, 5), 0)
	state.place(7, Vector2(50, 50), 0)
	state.place(9, Vector2(60, 60), 1)
	_expect(state.by_peer.size() == 3, "three players should hold three waypoints")
	state.place(7, Vector2(70, 70), 0)
	_expect(state.by_peer.size() == 3 and (state.get_for(1)["at"] as Vector2).is_equal_approx(Vector2(5.5, 5.5)),
		"one player's waypoint changed another's")
	var on_zero := state.on_level(0, 1)
	_expect(on_zero.size() == 2, "level filter returned %d" % on_zero.size())
	var mine := 0
	for entry in on_zero:
		mine += 1 if bool(entry["mine"]) else 0
	_expect(mine == 1, "exactly one pin is mine, got %d" % mine)


func _check_replication_and_late_join() -> void:
	var host := StreamedWorldState.new()
	var guest := StreamedWorldState.new()
	# the host's decisions arrive on the guest as apply() events
	host.waypoints.apply(1, {"at": Vector2(4.5, 4.5), "level": 0})
	guest.waypoints.apply(1, {"at": Vector2(4.5, 4.5), "level": 0})
	host.waypoints.apply(3, {"at": Vector2(9.5, 9.5), "level": 0})
	guest.waypoints.apply(3, {"at": Vector2(9.5, 9.5), "level": 0})
	host.waypoints.apply(3, {"at": Vector2(12.5, 9.5), "level": 0})   # peer 3 moves their pin
	guest.waypoints.apply(3, {"at": Vector2(12.5, 9.5), "level": 0})
	_expect(guest.waypoints.snapshot() == host.waypoints.snapshot(), "guest waypoints diverged from the host's")
	_expect(guest.waypoints.by_peer.size() == 2, "the moved pin was duplicated on the guest")
	# a late joiner adopts the host snapshot and sees exactly the same pins; the stunned owner of nothing else is touched
	var late := StreamedWorldState.new()
	_expect(late.adopt(host.snapshot()), "late joiner could not adopt the snapshot")
	_expect(late.waypoints.snapshot() == host.waypoints.snapshot(), "late joiner sees different pins")
	_expect(host.waypoints.apply(3, {}) and not host.waypoints.has_for(3) and host.waypoints.has_for(1), "an empty broadcast must clear only that peer's pin")


func _check_legacy_migration() -> void:
	var legacy := [
		{"at": Vector2(1.5, 1.5), "level": 0, "source_peer_id": 1},
		{"at": Vector2(8.5, 3.5), "level": 0, "source_peer_id": 2},
		{"at": Vector2(20.5, 7.5), "level": 1, "source_peer_id": 1},
	]
	var state := WaypointState.new()
	state.adopt_legacy(legacy, 1)
	_expect(state.by_peer.size() == 1 and (state.get_for(1)["at"] as Vector2).is_equal_approx(Vector2(20.5, 7.5)) \
		and int(state.get_for(1)["level"]) == 1, "the most recent legacy waypoint should be the one kept")
	var snapshot := StreamedWorldState.new().snapshot()
	snapshot.erase("waypoints")
	snapshot["shared_waypoints"] = legacy.duplicate(true)
	var restored := StreamedWorldState.new()
	_expect(restored.adopt(snapshot) and restored.waypoints.by_peer.size() == 1, "a legacy world-state snapshot did not migrate to one waypoint")
	var malformed := WaypointState.new()
	malformed.adopt({1: {"at": "nope"}, 2: 5, 3: {"at": Vector2(2.5, 2.5), "level": 0}})
	_expect(malformed.by_peer.size() == 1 and malformed.has_for(3), "malformed entries were not dropped")


func _check_edge_clamp() -> void:
	for size: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(3440, 1440)]:
		var margin := WaypointOverlay.EDGE_MARGIN
		var rect := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
		# on screen stays where it is
		var centre := size * .5 + Vector2(40, 25)
		var inside := WaypointState.screen_marker(centre, false, size, margin)
		_expect(not bool(inside["edge"]) and (inside["position"] as Vector2).is_equal_approx(centre), "an on-screen pin moved at %s" % size)
		# far off to every side, and behind the camera: clamped onto the safe rectangle edge
		for projected in [Vector2(-5000, 300), Vector2(size.x + 9000, 200), Vector2(400, -7000), Vector2(900, size.y + 4000),
				Vector2(-300, -300), Vector2(size.x + 300, size.y + 300)]:
			for behind in [false, true]:
				var marker := WaypointState.screen_marker(projected, behind, size, margin)
				var at: Vector2 = marker["position"]
				_expect(bool(marker["edge"]) and rect.grow(.5).has_point(at),
					"edge arrow left the screen at %s for %s behind=%s -> %s" % [size, projected, behind, at])
		var degenerate := WaypointState.screen_marker(size * .5, true, size, margin)
		_expect(rect.grow(.5).has_point(degenerate["position"]), "a pin straight behind the camera is not clamped at %s" % size)


func _check_controls() -> void:
	for action in ["waypoint", "waypoint_clear"]:
		_expect(InputMap.has_action(action), "%s is not in the input map" % action)
		_expect(Settings.REBINDABLE_ACTIONS.has(action), "%s is not rebindable" % action)
	var actions_tab: Array = []
	for tab in ControlsRegistry.tabs_for("last_route"):
		if String(tab["title"]) == "ACTIONS":
			actions_tab = tab["actions"]
	_expect(actions_tab.has("waypoint") and actions_tab.has("waypoint_clear"), "the waypoint keys are not on the Last Route ACTIONS tab")
	# no key conflicts with any other Last Route (non-office) action
	var signatures := {}
	for action in Settings.REBINDABLE_ACTIONS:
		if String(action).begins_with("office_") or not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			var signature := ""
			if event is InputEventKey:
				signature = "K%d" % int((event as InputEventKey).physical_keycode)
			elif event is InputEventMouseButton:
				signature = "M%d" % int((event as InputEventMouseButton).button_index)
			elif event is InputEventJoypadButton:
				signature = "J%d" % int((event as InputEventJoypadButton).button_index)
			if signature.is_empty():
				continue
			if signatures.has(signature) and (action in ["waypoint", "waypoint_clear"] or signatures[signature] in ["waypoint", "waypoint_clear"]):
				_expect(false, "waypoint key %s conflicts: %s vs %s" % [signature, action, signatures[signature]])
			signatures[signature] = action


func _check_settings() -> void:
	var before := [Settings.waypoint_guidance, Settings.waypoint_show_distance, Settings.waypoint_scale, Settings.waypoint_opacity, Settings.waypoint_arrival_chime]
	Settings.set_waypoint_guidance("path")
	Settings.set_waypoint_guidance("bogus")
	_expect(Settings.waypoint_guidance == "arrow", "an unknown guidance mode should fall back to arrow")
	Settings.set_waypoint_scale(99.0)
	_expect(is_equal_approx(Settings.waypoint_scale, 1.6), "pin scale is not clamped")
	Settings.set_waypoint_opacity(0.0)
	_expect(is_equal_approx(Settings.waypoint_opacity, .3), "pin opacity is not clamped")
	Settings.set_waypoint_guidance(before[0])
	Settings.set_waypoint_show_distance(before[1])
	Settings.set_waypoint_scale(before[2])
	Settings.set_waypoint_opacity(before[3])
	Settings.set_waypoint_arrival_chime(before[4])


