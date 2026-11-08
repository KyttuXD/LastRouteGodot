extends RefCounted

## Guest hunter views (InfiniteRouteTest._apply_hunter_report): the host's hunter report covers every runner's window,
## so when a teammate walks into a new area a batch of hunters wakes there. A guest must not build those far hunters,
## must show a hunter beside it (same storey, within a chunk) at once, build the other near ones at most one per frame
## (nearest first), follow a restarted host (lower clock), and drop views that leave its range. Prints the
## main-thread cost of the packet that reports the batch.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- guest_hunters

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _state(entity_id: String, hunter_id: String, chunk: Vector3i, offset: Vector2) -> Dictionary:
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)
	return {"entity_id": entity_id, "hunter_id": hunter_id, "active": true, "level": chunk.y,
		"position": Vector2(chunk.x * size + 22.5, chunk.z * size + 22.5) + offset}


func run(host: Node) -> int:
	var was_online := RoomState.online
	var was_host := RoomState.is_host
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "GUESTHUNTERS"
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 30:
		await host.get_tree().process_frame
	# this process now plays a guest: the host's reports arrive, nothing is simulated here
	RoomState.online = true
	RoomState.is_host = false
	for entity_id in route._hunter_views.keys().duplicate():
		route._unload_hunter(String(entity_id), false)
	await host.get_tree().process_frame
	var facility: StreamedFacilityView3D = route.facility
	var own: Vector3i = facility.current_chunk_coord()
	var ids: Array = HunterRoster.A_Z_IDS
	var report: Array = []
	# a teammate six chunks away just woke eight hunters round them; three hunters are two chunks from this guest, and two
	# are right beside it (one in its chunk, one in the next chunk on the same storey)
	var teammate := own + Vector3i(6, 0, 0)
	for i in 8:
		report.append(_state("GUEST:FAR:%d" % i, String(ids[i]), teammate, Vector2(i * 2.0, 0)))
	for i in 3:
		report.append(_state("GUEST:NEAR:%d" % i, String(ids[8 + i]), own + Vector3i(2, 0, 0), Vector2(i * 3.0, 4.0)))
	report.append(_state("GUEST:BESIDE:0", String(ids[11]), own, Vector2(2.0, 2.0)))
	report.append(_state("GUEST:BESIDE:1", String(ids[12]), own + Vector3i(1, 0, 0), Vector2(-20.0, 0.0)))
	var t := Time.get_ticks_usec()
	route._apply_hunter_report(report)
	var packet_ms := (Time.get_ticks_usec() - t) / 1000.0
	var beside_views := 0
	for entity_id in route._hunter_views:
		if String(entity_id).begins_with("GUEST:BESIDE:") and (route._hunter_views[entity_id] as Node3D).visible:
			beside_views += 1
	var views_after_packet: int = route._hunter_views.size()
	var worst_frame_ms := 0.0
	var built_per_frame: Array = []
	for _i in 6:
		# the route's own _process builds queued views (a guest pumps one per frame)
		var before: int = route._hunter_views.size()
		var t0 := Time.get_ticks_usec()
		await host.get_tree().process_frame
		worst_frame_ms = maxf(worst_frame_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		built_per_frame.append(route._hunter_views.size() - before)
		route._apply_hunter_report(report)   # the host keeps reporting at its broadcast rate
	var far_views := 0
	var near_views := 0
	for entity_id in route._hunter_views:
		if String(entity_id).begins_with("GUEST:FAR:"):
			far_views += 1
		elif String(entity_id).begins_with("GUEST:NEAR:"):
			near_views += 1
	print("  guest_hunters  report of 8 far + 3 near + 2 beside: packet %.1f ms, %d views built in it (%d beside, visible); then %s per frame (worst %.1f ms); far views %d, near views %d" % [
		packet_ms, views_after_packet, beside_views, str(built_per_frame), worst_frame_ms, far_views, near_views])
	_expect(beside_views == 2, "%d of the 2 hunters beside this guest had a visible view right after the packet (want both, at once)" % beside_views)
	_expect(views_after_packet == 2, "the report packet built %d hunter views (only the 2 beside this guest are built at once)" % views_after_packet)
	_expect(far_views == 0, "%d hunters round a far teammate got views on this guest" % far_views)
	_expect(near_views == 3, "%d of the 3 near hunters got views" % near_views)
	# the host restarts (its clock starts again, lower): the hunter beside this guest must still follow the new reports
	for count in built_per_frame:
		_expect(int(count) <= 1, "a frame built %d queued hunter views (at most one)" % int(count))
	var others: Array = report.slice(0, 11) + report.slice(12)
	var moved: Dictionary = (report[11] as Dictionary).duplicate()
	moved["sent_ms"] = 900000
	route._apply_hunter_report([moved] + others)
	var restarted: Dictionary = moved.duplicate()
	restarted["sent_ms"] = 5
	restarted["position"] = (moved["position"] as Vector2) + Vector2(3.0, 0.0)
	route._apply_hunter_report([restarted] + others)
	for _i in 30:
		await host.get_tree().process_frame
	var follower := route._hunter_views.get("GUEST:BESIDE:0") as HunterView3D
	_expect(follower != null and follower.brain.position.distance_to(restarted["position"]) < .5,
		"after a host restart (lower clock) the hunter beside this guest stayed where it was")
	# the near hunters walk off past the drop radius: their views go
	var gone: Array = []
	for state_value in report:
		var state: Dictionary = (state_value as Dictionary).duplicate()
		if String(state["entity_id"]).begins_with("GUEST:NEAR:") or String(state["entity_id"]).begins_with("GUEST:BESIDE:"):
			state["position"] = (state["position"] as Vector2) + Vector2(StreamedRouteGenerator.CHUNK_SIZE * 5.0, 0)
		gone.append(state)
	route._apply_hunter_report(gone)
	var left := 0
	for entity_id in route._hunter_views:
		if String(entity_id).begins_with("GUEST:"):
			left += 1
	_expect(left == 0, "%d hunter views stayed after their hunters left this guest's range" % left)
	RoomState.online = was_online
	RoomState.is_host = was_host
	route.queue_free()
	await host.get_tree().process_frame
	return _failures
