extends RefCounted

## Co-op teammates on the minimap and the full map: RemotePlayers.remote_player_marks (same-floor, other-floor and spectating flags,
## stale peers dropped), FacilityMap.teammate_layout (arrow in view, edge-clamped pointer off the map, up/down marker for another
## storey, hollow marker for a downed/spectating teammate), both maps receiving the marks, and the HUD hiding them in the death flow.
##
##   godot --headless --path . res://scenes/validate.tscn -- minimap_teammates

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_check_marks()
	await _check_layout(host)
	await _check_hud(host)
	if _failures == 0:
		print("minimap_teammates OK")
	return _failures


func _state(depth: int, at: Vector2, extra: Dictionary = {}) -> Dictionary:
	var state := {"position": at, "depth": depth, "facing": Vector2.RIGHT, "display_name": "Teammate",
		"received_usec": Time.get_ticks_usec()}
	state.merge(extra, true)
	return state


func _check_marks() -> void:
	var source := RemotePlayers.new()
	source.set("_states", {
		2: _state(3, Vector2(5, 5)),
		3: _state(4, Vector2(6, 6)),
		4: _state(3, Vector2(7, 7), {"spectating": true}),
		5: _state(3, Vector2(8, 8), {"received_usec": Time.get_ticks_usec() - 600_000_000}),
		6: _state(3, Vector2(9, 9), {"received_usec": Time.get_ticks_usec() - 10_000_000}),
	})
	var same := source.remote_player_marks(3)
	_expect(same.size() == 3, "default marks should be the 2 fresh + 1 stale same-floor peers, not %d" % same.size())
	var stale := same.filter(func(m: Dictionary) -> bool: return bool(m.get("stale", false)))
	_expect(stale.size() == 1 and int(stale[0]["peer_id"]) == 6, "a peer quiet for 10 s should stay as a stale last-known mark")
	var all := source.remote_player_marks(3, true)
	_expect(all.size() == 4, "include_other_floors should add the other-floor peer (the 10-minute-old one still dropped), got %d" % all.size())
	var other := all.filter(func(m: Dictionary) -> bool: return bool(m.get("other_floor", false)))
	_expect(other.size() == 1 and int(other[0]["level"]) == -4, "the other-floor mark should carry its own level -4 (%s)" % [other])
	var downed := all.filter(func(m: Dictionary) -> bool: return bool(m.get("spectating", false)))
	_expect(downed.size() == 1 and int(downed[0]["peer_id"]) == 4, "the spectating peer is not flagged")
	source.free()


func _check_layout(host: Node) -> void:
	var map := FacilityMap.new()
	map.size = Vector2(100, 82)
	map.streamed_level = -3
	host.add_child(map)
	var inside := map.teammate_layout(Vector2(50, 41), 3.0, {"level": -3})
	_expect(inside["kind"] == "arrow" and not inside["off_view"] and inside["shown"] == Vector2(50, 41), "a teammate in view should be a plain arrow in place")
	var far := map.teammate_layout(Vector2(900, 41), 3.0, {"level": -3})
	_expect(far["off_view"] and far["kind"] == "arrow", "a far teammate should be an off-view pointer")
	var shown: Vector2 = far["shown"]
	_expect(shown.x > 80.0 and shown.x < 100.0 and absf(shown.y - 41.0) < 1.0, "the pointer is not clamped to the right edge (%s)" % shown)
	_expect((far["outward"] as Vector2).x > .99, "the pointer does not point outward")
	for corner in [Vector2(-500, -500), Vector2(900, 900), Vector2(-40, 300), Vector2(300, -9)]:
		var edge: Vector2 = map.teammate_layout(corner, 3.0, {})["shown"]
		_expect(Rect2(Vector2.ZERO, map.size).has_point(edge), "an edge pointer left the map for %s -> %s" % [corner, edge])
	var up := map.teammate_layout(Vector2(20, 20), 3.0, {"other_floor": true, "level": -1})
	var down := map.teammate_layout(Vector2(20, 20), 3.0, {"other_floor": true, "level": -5})
	_expect(up["kind"] == "updown" and up["up"] and down["kind"] == "updown" and not down["up"], "up/down markers do not follow the floor order")
	var gone := map.teammate_layout(Vector2(20, 20), 3.0, {"spectating": true})
	_expect(gone["kind"] == "downed", "a spectating teammate should get the downed icon")
	# the maps keep other-floor marks and drop other-floor marks that are not flagged
	var marks := [{"at": Vector2(5, 5), "level": -3, "name": "A"},
		{"at": Vector2(6, 6), "level": -4, "name": "B", "other_floor": true},
		{"at": Vector2(7, 7), "level": -9, "name": "C"}]
	map.show_streamed_state({}, -3, 16, Vector2.ZERO, Vector2.DOWN, [], false, 0, marks)
	_expect(map.players.size() == 2, "the map should hold the same-floor and the flagged other-floor teammate, not %d" % map.players.size())
	# drawing every variant must not error (nothing to assert beyond not crashing)
	map.show_streamed_state({}, -3, 16, Vector2.ZERO, Vector2.DOWN, [], false, 0, [
		{"at": Vector2(5, 5), "level": -3, "name": "A", "facing": Vector2.UP},
		{"at": Vector2(900, 5), "level": -3, "name": "B", "spectating": true},
		{"at": Vector2(6, 6), "level": -4, "name": "C", "other_floor": true}])
	map.interactive = true
	map.queue_redraw()
	await host.get_tree().process_frame
	map.queue_free()
	await host.get_tree().process_frame


func _check_hud(host: Node) -> void:
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as HUD
	host.add_child(hud)
	await host.get_tree().process_frame
	var marks := [{"at": Vector2(5, 5), "level": 0, "name": "Ana", "facing": Vector2.UP},
		{"at": Vector2(6, 6), "level": -1, "name": "Bo", "other_floor": true}]
	hud.update_streamed_minimap({}, 0, 16, Vector2.ZERO, Vector2.DOWN, [], marks)
	hud.update_streamed_map({}, 0, 16, Vector2.ZERO, Vector2.DOWN, [], marks)
	_expect(hud.minimap.players.size() == 2, "the minimap did not receive the teammates (%d)" % hud.minimap.players.size())
	_expect(hud.plan.players.size() == 2, "the full map did not receive the teammates (%d)" % hud.plan.players.size())
	hud.set_death_flow(true)
	await host.get_tree().process_frame
	_expect(not hud.minimap.is_visible_in_tree(), "the minimap (and its teammates) must hide during the death flow")
	hud.set_death_flow(false)
	hud.queue_free()
	await host.get_tree().process_frame
