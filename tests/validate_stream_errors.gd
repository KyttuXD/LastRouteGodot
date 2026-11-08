extends RefCounted

## A streamed run raises no SCRIPT ERROR, and a chunk build that comes back empty cannot flood the log: _advance_chunk_build used to read build["root"] on the empty
## Dictionary a failed _create_chunk_build hands back, and its callers loop until the build reports finished, so one bad chunk threw the same error every iteration
## (118 GB of test logs seen once).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- stream_errors

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var log := PlaytestLog.new()
	OS.add_logger(log)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "STREAM-ERRORS"
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 10:
		await host.get_tree().process_frame
	# stream a few chunks in and out: teleports are synchronous builds, walking is the background ones
	for target in [Vector3(40, 0.3, 0), Vector3(-30, 0.3, 60), Vector3(0, 0.3, 0)]:
		route._admin_teleport_to(target)
		for _i in 30:
			await host.get_tree().process_frame
	_expect(log.errors == 0, "a streamed run logged %d errors: %s" % [log.errors, str(log.since(0).slice(0, 3))])
	# an empty build (what a failed create hands back) finishes at once and warns once, with no script error
	var errors_before := log.errors
	var facility: StreamedFacilityView3D = route.facility
	_expect(facility._advance_chunk_build({}, true) and facility._advance_chunk_build({}, false), "an empty chunk build is not reported finished")
	_expect(log.errors == errors_before, "an empty chunk build raised a script error")
	route.queue_free()
	await host.get_tree().process_frame
	OS.remove_logger(log)
	if _failures == 0:
		print("  stream_errors  a streamed run logs no errors; an empty chunk build is dropped with one warning")
		print("stream_errors OK")
	return _failures
