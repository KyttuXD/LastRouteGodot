extends RefCounted

## Headless check on the office camera monitor's raise/lower.
##
## Raising it sets `can_move` false -- you cannot look around the office with
## a tablet in your face -- and that same flag also empties `_hovered`, which
## is what makes the physical Monitor desk key pickable at all. Put those two
## together and the key that raises the monitor becomes unclickable and
## unpickable the moment it goes up, with nothing else in its own UI to lower
## it again: a real soft lock, not a hypothetical one. Driven here through the
## real scene and a real simulated key press, because "monitor_open flips
## back to false" is exactly the kind of check that passes while the actual
## input path a player has -- [E] -- still does nothing.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- office_monitor

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	var scene: Node = load("res://scenes/office_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	var simulation: OfficeSimulation = scene.simulation
	var office_view: OfficeView3D = scene.office_view
	if simulation == null or office_view == null:
		_fail("office_3d.tscn did not wire up simulation/office_view")
		scene.queue_free()
		return _failures

	simulation.toggle_control("cameras")
	# One real frame, exactly as a player gets: main_office._process() is what
	# actually syncs office_view.can_move off simulation.monitor_open (see
	# _sync_monitor_visibility), so driving a frame here rather than poking
	# can_move by hand is what makes this the same path a player is on.
	await host.get_tree().process_frame
	_expect(simulation.monitor_open, "toggling the cameras control did not raise the monitor")
	_expect(not office_view.can_move,
		"the monitor is up but can_move is still true -- the rest of this check proves nothing")

	# The actual input path a player has: press [E], one real frame, release.
	Input.action_press("interact")
	await host.get_tree().process_frame
	Input.action_release("interact")
	await host.get_tree().process_frame

	_expect(not simulation.monitor_open, "[E] with the monitor up did not lower it")
	_expect(office_view.can_move, "the monitor is down but the player still cannot move")
	print("  monitor   [E] lowers a raised monitor -- no soft lock")
	if _failures == 0:
		print("office_monitor OK")

	scene.queue_free()
	return _failures
