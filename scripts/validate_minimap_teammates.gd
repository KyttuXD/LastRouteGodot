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
	await _check_waypoints(host)
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
	# a revive window: same floor in place, another floor as the up/down marker, off the map clamped to the edge, always kept by the map
	var down_here := FacilityMap.down_map_mark({"peer": 4, "at": Vector3(12.0, 0.0, 7.0), "depth": 3, "name": "Cy", "left": 17.5}, -3)
	var down_below := FacilityMap.down_map_mark({"peer": 5, "at": Vector3(1.0, 0.0, 2.0), "depth": 4, "name": "Di", "left": 9.0}, -3)
	_expect(not down_here["other_floor"] and down_here["at"] == Vector2(12, 7) and is_equal_approx(down_here["down_left"], 17.5), "a revive window on this floor is mapped wrongly (%s)" % [down_here])
	_expect(down_below["other_floor"] and down_below["level"] == -4, "a revive window on another floor should be flagged and carry its level")
	map.show_streamed_state({}, -3, 16, Vector2.ZERO, Vector2.DOWN, [], false, 0, [down_here, down_below])
	_expect(map.players.size() == 2, "the map should keep both revive windows, not %d" % map.players.size())
	var down_far := map.teammate_layout(Vector2(900, 41), 3.4, down_here)
	_expect(down_far["off_view"] and Rect2(Vector2.ZERO, map.size).has_point(down_far["shown"]), "a revive window off the map is not clamped to the edge")
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
	# the admin room-proof lines show once per room, not on every ticket renewal; rejections always show
	hud.show_message("ADMIN ROOM PROOF READY")
	_expect(hud.message_label.visible and hud.message_label.text == "ADMIN ROOM PROOF READY", "the first admin proof notice did not show")
	hud.message_label.visible = false
	hud.show_message("ADMIN ROOM PROOF READY")
	_expect(not hud.message_label.visible, "the admin proof notice showed a second time")
	hud.show_message("ADMIN ROOM PROOF VERIFIED")
	_expect(hud.message_label.visible, "a different admin proof line should still show once")
	hud.message_label.visible = false
	hud.show_message("ADMIN REQUEST REJECTED // PERMISSION REQUIRED")
	_expect(hud.message_label.visible, "an admin rejection must always show")
	hud.message_label.visible = false
	hud.show_message("ADMIN REQUEST REJECTED // PERMISSION REQUIRED")
	_expect(hud.message_label.visible, "a repeated admin rejection must still show")
	hud.set_death_flow(true)
	await host.get_tree().process_frame
	_expect(not hud.minimap.is_visible_in_tree(), "the minimap (and its teammates) must hide during the death flow")
	hud.set_death_flow(false)
	hud.queue_free()
	await host.get_tree().process_frame


## HUD teammate waypoints: projection and edge clamping, other floor, stale dimming, DOWN/CAUGHT labels, the setting and the HUD hide.
func _check_waypoints(host: Node) -> void:
	var area := Vector2(480, 270)
	var inside := TeammateWaypoints.layout_for(Vector2(240, 135), Vector2.ZERO, false, area, 14.0)
	_expect(not inside["clamped"] and inside["at"] == Vector2(240, 135), "an on-screen teammate should stay where it projects")
	var right := TeammateWaypoints.layout_for(Vector2(900, 135), Vector2(1, 0), false, area, 14.0)
	_expect(right["clamped"] and absf((right["at"] as Vector2).x - 466.0) < 0.5 and absf((right["at"] as Vector2).y - 135.0) < 1.0, "an off-screen teammate is not clamped to the right edge (%s)" % [right])
	var behind := TeammateWaypoints.layout_for(Vector2(240, 135), Vector2(-1, 0), true, area, 14.0)
	_expect(behind["clamped"] and (behind["at"] as Vector2).x < 20.0, "a teammate behind you should clamp to the side they are on (%s)" % [behind])
	var straight_behind := TeammateWaypoints.layout_for(Vector2(240, 135), Vector2.ZERO, true, area, 14.0)
	_expect(straight_behind["clamped"] and Rect2(Vector2.ZERO, area).has_point(straight_behind["at"]), "a teammate straight behind has no edge marker")

	var camera := Camera3D.new()
	host.add_child(camera)
	camera.global_position = Vector3(0, 1.7, 0)
	camera.current = true
	var waypoints := TeammateWaypoints.new()
	host.add_child(waypoints)
	waypoints.size = host.get_viewport().get_visible_rect().size
	await host.get_tree().process_frame
	var saved := Settings.teammate_waypoints
	Settings.teammate_waypoints = true
	var marks := [
		{"peer_id": 2, "at": Vector2(0, -10), "level": 0, "name": "Ana", "age_ms": 100},
		{"peer_id": 3, "at": Vector2(0, 10), "level": 0, "name": "Bo", "age_ms": 100},
		{"peer_id": 4, "at": Vector2(3, -6), "level": 1, "name": "Cy", "other_floor": true, "age_ms": 100},
		{"peer_id": 5, "at": Vector2(-2, -8), "level": 0, "name": "Di", "age_ms": 5000},
		{"peer_id": 6, "at": Vector2(2, -8), "level": 0, "name": "Ed", "spectating": true, "age_ms": 100},
		{"peer_id": 7, "at": Vector2(4, -9), "level": 0, "name": "Fay", "caught": true, "age_ms": 100},
		{"peer_id": 8, "at": Vector2(900, 0), "level": 0, "name": "Gus", "age_ms": 100},   # far beyond any chunk range
	]
	waypoints.update_marks(camera, Vector3(0, 1.7, 0), marks)
	var entries: Array = waypoints.entries()
	_expect(entries.size() == 7, "every teammate in the room needs a waypoint, got %d" % entries.size())
	if entries.size() == 7:
		_expect(not entries[0]["clamped"] and entries[0]["distance"] == 10, "a teammate 10 m ahead should be an on-screen marker at 10 M (%s)" % [entries[0]])
		_expect(entries[1]["clamped"], "a teammate behind you should be an edge arrow")
		_expect(entries[2]["other_floor"] and entries[2]["above"] and entries[2]["level"] == 1, "another floor needs the up marker with its level")
		_expect(entries[3]["stale"] and not entries[0]["stale"], "only the teammate quiet for more than 3 s is dimmed")
		_expect(entries[4]["state"] == "DOWN" and entries[5]["state"] == "CAUGHT" and entries[0]["state"] == "", "DOWN and CAUGHT are not labelled")
		_expect(entries[6]["clamped"] and entries[6]["distance"] == 900, "a teammate 900 m away (beyond chunk range) should still get an edge arrow with the distance")
	waypoints.queue_redraw()
	await host.get_tree().process_frame
	Settings.teammate_waypoints = false
	waypoints.update_marks(camera, Vector3(0, 1.7, 0), marks)
	_expect(waypoints.entry_count() == 0 and not waypoints.visible, "the setting off should remove the waypoints")
	Settings.teammate_waypoints = saved
	waypoints.queue_free()
	camera.queue_free()

	# the setting exists in Settings -> DISPLAY and the HUD hides the markers with the rest of the gameplay HUD
	var overlay := (load("res://scenes/settings_overlay.tscn") as PackedScene).instantiate()
	host.add_child(overlay)
	await host.get_tree().process_frame
	var toggle := overlay.find_child("TeammateWaypointsButton", true, false) as Button
	_expect(toggle != null and toggle.get_parent().name == "TeammateWaypointsRow", "Settings has no TEAMMATE WAYPOINTS toggle")
	if toggle != null:
		toggle.button_pressed = not Settings.teammate_waypoints
		_expect(Settings.teammate_waypoints == toggle.button_pressed, "the toggle did not change the setting")
		toggle.button_pressed = saved
		_expect(Settings.teammate_waypoints == saved, "the toggle did not restore the setting")
	overlay.queue_free()
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as HUD
	host.add_child(hud)
	await host.get_tree().process_frame
	_expect(hud.teammate_waypoints != null and hud.teammate_waypoints.get_parent() == hud, "the HUD has no teammate waypoints layer")
	hud.set_death_flow(true)
	await host.get_tree().process_frame
	_expect(hud.teammate_waypoints.modulate.a == 0.0, "the teammate markers stay up under the death flow")
	hud.set_death_flow(false)
	hud.queue_free()
	await host.get_tree().process_frame
