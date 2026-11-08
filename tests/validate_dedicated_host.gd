extends RefCounted

## Dedicated headless host (backend/README.md): `-- --dedicated-host CODE` options, the idle shutdown, and the
## route with no runner of its own -- never a hunter target, hidden from guests, no physics.
##
##   godot4 --headless res://tests/scenes/validate.tscn -- dedicated_host

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_options()
	_idle()
	await _parked_route(host)
	return _failures


func _options() -> void:
	_expect(RoomState.parse_dedicated_args(PackedStringArray(["--offline"])).is_empty(), "a normal run became a dedicated host")
	var options := RoomState.parse_dedicated_args(PackedStringArray(["--dedicated-host", "kathy", "--seed", "TEST SEED",
		"--difficulty", "2", "--port", "9100", "--idle-minutes", "3"]))
	_expect(String(options.get("code", "")) == "KATHY", "the room code was not read (%s)" % options)
	_expect(String(options.get("seed", "")) == "TEST SEED" and int(options.get("difficulty", -1)) == 2
		and int(options.get("port", 0)) == 9100 and is_equal_approx(float(options.get("idle_minutes", 0)), 3.0),
		"dedicated options were misread: %s" % options)
	_expect(RoomState.parse_dedicated_args(PackedStringArray(["--dedicated-host", "no!"])).is_empty(),
		"an invalid room code was accepted")
	_expect(RoomState.parse_dedicated_args(PackedStringArray(["--dedicated-host"])).is_empty(),
		"--dedicated-host without a code was accepted")
	_expect(int(RoomState.parse_dedicated_args(PackedStringArray(["--dedicated-host", "AKIRI"])).get("port", 0)) \
		== RoomState.DEFAULT_PORT, "the default port is not used")


func _idle() -> void:
	_expect(not RoomState.dedicated_should_exit(9 * 60.0, 10.0), "an empty dedicated host quit early")
	_expect(RoomState.dedicated_should_exit(10 * 60.0, 10.0), "an empty dedicated host never quits")


func _parked_route(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.dedicated = true
	var route: Node = load("res://game/infinite_route/infinite_route_test.tscn").instantiate()
	host.get_tree().root.add_child(route)
	for i in 10:
		await host.get_tree().process_frame
	var player := route.get("player") as PlayerController3D
	_expect(player != null and not player.visible and not player.is_physics_processing() and player.input_frozen,
		"the dedicated host's player node is not parked")
	_expect((route.call("_hunter_target", false) as Dictionary).is_empty(), "the dedicated host offered hunters a target")
	var overrides: Dictionary = route.call("_streamed_state_overrides")
	_expect(bool(overrides.get("syncing", false)), "guests would draw / target the dedicated host's runner")
	var remotes := route.get("_remotes") as RemotePlayers
	if remotes != null:
		_expect(remotes.target_states(route.call("_hunter_target", false)).is_empty(),
			"a dedicated host with no guests still has hunter targets")
	RoomState.dedicated = false
	route.queue_free()
	await host.get_tree().process_frame
	RoomState.create_local(RoomState.Mode.DEFAULT)
