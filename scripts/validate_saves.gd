extends RefCounted

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	RunSaves.clear_pending()
	var payload := {
		"schema": RunSaves.SAVE_SCHEMA,
		"kind": "infinite_route",
		"seed_text": "VALIDATION-SAVE-SEED",
		"run_seed": 987654,
		"difficulty": RoomState.Difficulty.STANDARD,
		"difficulty_id": "standard",
		"world_state": StreamedWorldState.new().snapshot(),
		"player": {
			"position": Vector3(12.5, StreamedFacilityView3D.LEVEL_HEIGHT, -8.5),
			"level": 1,
			"inventory_order": ["flashlight", "battery", "", "", ""],
			"inventory_slot_durability": [77, 0, 0, 0, 0],
		},
		"statistics": {"elapsed_seconds": 3723.0, "relays_collected": 4},
		"discovery": {"waypoints": [{"at": Vector2(4.5, 8.5), "level": 1}]},
	}
	var created := RunSaves.save_new("Validation Route", payload)
	_expect(bool(created.get("ok", false)), "named local save could not be created")
	var slot_id := String(created.get("slot_id", ""))
	var listed := RunSaves.list_slots()
	_expect(listed.any(func(slot: Dictionary) -> bool:
		return String(slot.get("slot_id", "")) == slot_id \
			and String(slot.get("name", "")) == "Validation Route" \
			and int(slot.get("level", 0)) == 1),
		"new local save was not listed with its metadata")
	var renamed := RunSaves.rename_slot(slot_id, "Renamed Validation")
	_expect(bool(renamed.get("ok", false)), "local save could not be renamed")
	var loaded := RunSaves.load_slot(slot_id)
	var restored: Dictionary = loaded.get("payload", {})
	_expect(bool(loaded.get("ok", false)) \
		and restored.get("player", {}).get("position") is Vector3 \
		and restored.get("discovery", {}).get("waypoints", [])[0].get("at") is Vector2,
		"save archive lost Godot vector types across disk round-trip")
	payload["statistics"] = {"elapsed_seconds": 9.0, "relays_collected": 8}
	var overwritten := RunSaves.overwrite(slot_id, payload)
	_expect(bool(overwritten.get("ok", false)) \
		and float((RunSaves.load_slot(slot_id).get("payload", {}) as Dictionary)
			.get("statistics", {}).get("elapsed_seconds", -1.0)) == 9.0,
		"overwriting a named save did not replace its route payload")
	var queued := RunSaves.queue_load(slot_id)
	var consumed := RunSaves.consume_pending()
	_expect(bool(queued.get("ok", false)) and bool(consumed.get("ok", false)) \
		and RunSaves.consume_pending().is_empty(),
		"queued restart load was not consumed exactly once")
	var deleted := RunSaves.delete_slot(slot_id)
	_expect(bool(deleted.get("ok", false)) \
		and not bool(RunSaves.load_slot(slot_id).get("ok", false)),
		"deleted save remained readable")

	var route_script := load("res://src/infinite_route_test.gd") as GDScript
	var route = route_script.new() if route_script != null else null
	var old_online := RoomState.online
	var old_host := RoomState.is_host
	var old_peers := RoomState.peers.duplicate(true)
	if route != null:
		RoomState.online = true
		RoomState.is_host = true
		RoomState.peers = {1: "HOST"}
		_expect(String(route.call("_save_write_denial")).is_empty() \
			and String(route.call("_save_load_denial")).is_empty(),
			"online solo host cannot save and load a route archive")
		RoomState.peers = {1: "HOST", 2: "GUEST"}
		_expect(String(route.call("_save_write_denial")).is_empty() \
			and not String(route.call("_save_load_denial")).is_empty(),
			"co-op host cannot snapshot shared progress or can replace a live party world")
		RoomState.is_host = false
		_expect(not String(route.call("_save_write_denial")).is_empty() \
			and not String(route.call("_save_load_denial")).is_empty(),
			"co-op guest received host save/load authority")
		route.free()
	else:
		_expect(false, "Infinite route save policy script did not compile")
	RoomState.online = old_online
	RoomState.is_host = old_host
	RoomState.peers = old_peers

	var pause := PauseMenu.new()
	var pause_operations := []
	pause.save_slots_source = func() -> Array:
		return [{"slot_id": "fixture", "name": "Fixture Route", "level": -1,
			"difficulty": "HARD", "elapsed_seconds": 269.0, "saved_at": 1}]
	pause.save_new_request = func(name: String) -> Dictionary:
		pause_operations.append(["new", name])
		return {"ok": true, "message": "NEW", "slot_id": "fixture"}
	pause.save_overwrite_request = func(id: String) -> Dictionary:
		pause_operations.append(["overwrite", id])
		return {"ok": true, "message": "OVERWRITE", "slot_id": id}
	pause.save_load_request = func(id: String) -> Dictionary:
		pause_operations.append(["load", id])
		return {"ok": true, "message": "LOAD", "slot_id": id}
	pause.save_rename_request = func(id: String, name: String) -> Dictionary:
		pause_operations.append(["rename", id, name])
		return {"ok": true, "message": "RENAME", "slot_id": id}
	pause.save_delete_request = func(id: String) -> Dictionary:
		pause_operations.append(["delete", id])
		return {"ok": true, "message": "DELETE", "slot_id": id}
	pause.statistics_source = func() -> Dictionary:
		return {"TIME SURVIVED": "01:02:03", "RELAYS COLLECTED": "4"}
	host.add_child(pause)
	pause.open()
	pause.call("_set_section", "saves")
	pause.call("_select_save", "fixture", "Fixture Route")
	await host.get_tree().process_frame
	var save_actions := pause.find_child("SaveSlotActions_fixture", true, false)
	var load_button := pause.find_child("SaveSlotLoad_fixture", true, false) as Button
	var delete_button := pause.find_child("SaveSlotDelete_fixture", true, false) as Button
	_expect(save_actions != null and load_button != null and delete_button != null \
		and load_button.get_parent() == save_actions \
		and save_actions.get_parent().find_child("SaveSlot_fixture", false, false) != null,
		"save actions remain detached from the selected save entry (%s)" % [
			pause.find_children("SaveSlot*", "", true, false).map(
				func(node: Node) -> String: return node.name)])
	if load_button != null:
		load_button.pressed.emit()
	_expect(pause_operations.has(["load", "fixture"]),
		"per-save LOAD did not target its owning archive")
	pause.call("_set_section", "statistics")
	_expect(pause.find_child("PauseSaves", true, false) != null \
		and pause.find_child("PauseStatistics", true, false) != null \
		and pause.find_child("PauseShare", true, false) != null \
		and pause.find_child("PauseCopyRoute", true, false) != null \
		and pause.find_child("PauseStatisticsGrid", true, false).get_child_count() == 4,
		"pause menu is missing save/statistics views or the route-share copy")
	pause.close()
	pause.queue_free()
	await host.get_tree().process_frame
	RunSaves.clear_pending()
	if _failures == 0:
		print("  archives   named create/overwrite/rename/delete and restart load survive disk")
		print("  authority online-solo host loads; co-op host snapshots; guests cannot replace")
		print("  pause      route saves and current-run statistics are reachable in-game")
		print("saves OK")
	return _failures
