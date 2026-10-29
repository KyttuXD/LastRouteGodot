extends RefCounted

## The merry-go-round (CarouselRide3D, docs/CARNIVAL_BOOTHS.md): the shared rotation (host and guest show the same angle, a snapshot re-bases the clock, stop keeps the angle), the ride's parts (eight horses on poles
## that bob, bulbs, mirrors, the lever, a walkable ramp and platform, a column), riding (carried round without sliding or clipping, not carried off the platform or when stopped, facing turns with it), LOD (no work when
## far), the nav footprint of the column, and the route flow in a real carnival room (lever start and stop through the host, an invented id ignored, an idle stop).
##
##   godot --headless --path . res://scenes/validate.tscn -- carousel

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_check_state()
	await _check_ride(host)
	await _check_riding(host)
	await _check_route(host)
	_check_clearance()
	if _failures == 0:
		print("  carousel  shared rotation, the ride's parts, riding without sliding or clipping, LOD, the column's nav footprint and the lever through the host")
	return _failures


func _check_state() -> void:
	var host_state := StreamedWorldState.new()
	var t0 := 1_800_000_000.0
	_expect(not host_state.carousel_on("r") and host_state.carousel_angle("r", t0) == 0.0, "an unknown ride is stopped at angle 0")
	_expect(host_state.set_carousel("r", true, 1.0, t0), "starting a ride did not change the state")
	_expect(is_equal_approx(host_state.carousel_angle("r", t0 + 3.0), fposmod(1.0 + StreamedWorldState.CAROUSEL_SPEED * 3.0, TAU)), "the angle does not advance at the shared speed")
	host_state.set_carousel("r", false, host_state.carousel_angle("r", t0 + 3.0), t0 + 3.0)
	var stopped := host_state.carousel_angle("r", t0 + 3.0)
	_expect(is_equal_approx(host_state.carousel_angle("r", t0 + 30.0), stopped) and not host_state.carousel_on("r"), "a stopped ride keeps its angle")
	# a running ride in a snapshot: the guest re-bases to its own clock and shows the same angle to within the delay
	host_state.set_carousel("r", true, 2.0, Time.get_unix_time_from_system())
	var guest := StreamedWorldState.new()
	_expect(guest.adopt(host_state.snapshot()) and guest.carousel_on("r"), "a running ride did not survive a snapshot")
	var now := Time.get_unix_time_from_system()
	_expect(absf(angle_diff(guest.carousel_angle("r", now), host_state.carousel_angle("r", now))) < 0.05, "guest and host angles differ by %.3f rad after a snapshot" % absf(angle_diff(guest.carousel_angle("r", now), host_state.carousel_angle("r", now))))
	_expect(absf(angle_diff(guest.carousel_angle("r", now + 10.0), host_state.carousel_angle("r", now + 10.0))) < 0.05, "guest and host drift apart over ten seconds")
	var old := StreamedWorldState.new()
	var legacy := host_state.snapshot()
	legacy.erase("carousels")
	_expect(old.adopt(legacy) and old.carousels.is_empty(), "a snapshot without rides no longer loads")


func angle_diff(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


func _ride(host: Node, state: Dictionary, clock: Array) -> CarouselRide3D:
	var ride := CarouselRide3D.new()
	ride.manual = true
	ride.state_resolver = func() -> Dictionary: return state
	ride.now_resolver = func() -> float: return float(clock[0])
	ride.setup("0:0:0:carouselCenterpiece:8:8")
	host.add_child(ride)
	return ride


func _check_ride(host: Node) -> void:
	var state := {"on": false, "angle": 0.0}
	var clock := [0.0]
	var ride := _ride(host, state, clock)
	await host.get_tree().process_frame
	_expect(ride._horses.size() == CarouselRide3D.HORSES and ride._bulbs.size() == CarouselRide3D.BULBS, "the ride is missing horses or bulbs")
	_expect(ride.rotor_body != null and ride.rotor_body.get_child_count() >= CarouselRide3D.HORSES + 1 and ride.rotor.get_child_count() > 20, "the ride is missing its column and horse collision, or its mirrors")
	_expect(ride.find_child("PlatformFloor", true, false) != null and ride.find_child("LeverPanel", true, false) != null and ride.find_child("Tune", true, false) != null, "no ramp and platform, lever panel or tune")
	_expect(ride.prompt_text().begins_with("START") , "the lever of a stopped ride does not offer to start it")
	state["on"] = true
	ride._refresh()
	_expect(ride.prompt_text().begins_with("STOP"), "the lever of a running ride does not offer to stop it")
	# the horses bob: over a turn their heights vary and differ between horses
	var lo := 9.0
	var hi := -9.0
	var first_heights := []
	for step in 120:
		state["angle"] = float(step) * 0.05
		ride._refresh()
		for h in ride._horses:
			lo = minf(lo, h.position.y)
			hi = maxf(hi, h.position.y)
		if step == 7:
			for h in ride._horses:
				first_heights.append(snappedf(h.position.y, 0.01))
	_expect(hi - lo > 0.25, "the horses do not bob (range %.2f)" % (hi - lo))
	var distinct := {}
	for y in first_heights:
		distinct[y] = true
	_expect(distinct.size() >= 3, "all the horses bob in step (%d distinct heights)" % distinct.size())
	# the bulbs chase: not all the same at one instant
	var lit := 0
	for m in ride._bulb_mats:
		lit += int(m.emission_energy_multiplier > 1.0)
	_expect(lit > 0 and lit < ride._bulb_mats.size(), "the bulbs do not chase (%d of %d lit)" % [lit, ride._bulb_mats.size()])
	# LOD: far from every camera nothing animates
	ride.manual = false
	ride._near = false
	ride._check = 99.0
	var t_before := ride._t
	ride._process(1.0)
	_expect(is_equal_approx(ride._t, t_before), "a far ride still animates")
	ride._near = true
	ride._check = 99.0
	ride._process(0.5)
	_expect(ride._t > t_before, "a near ride does not animate")
	ride.queue_free()
	await host.get_tree().process_frame


func _check_riding(host: Node) -> void:
	var state := {"on": true, "angle": 0.0}
	var clock := [0.0]
	var ride := _ride(host, state, clock)
	ride.position = Vector3(10, 0, 10)
	await host.get_tree().process_frame
	var rider := Node3D.new()
	var off_platform := Node3D.new()
	var high := Node3D.new()
	for n in [rider, off_platform, high]:
		host.add_child(n)
	var top := ride.global_position.y + CarouselRide3D.PLATFORM_TOP
	rider.global_position = ride.global_position + Vector3(1.8, CarouselRide3D.PLATFORM_TOP + 0.05, 0)
	off_platform.global_position = ride.global_position + Vector3(CarouselRide3D.RADIUS + 0.8, CarouselRide3D.PLATFORM_TOP, 0)
	high.global_position = ride.global_position + Vector3(1.8, CarouselRide3D.PLATFORM_TOP + 3.0, 0)
	var off_start := off_platform.global_position
	var high_start := high.global_position
	var local_start := _local_of(ride, rider)
	var yaw_start := rider.rotation.y
	var total := 0.0
	var worst_radius_error := 0.0
	var min_r := 99.0
	var max_r := 0.0
	var seconds := 12.0
	var steps := int(seconds * 60.0)
	for i in steps:
		var before: float = state["angle"]
		state["angle"] = fposmod(before + StreamedWorldState.CAROUSEL_SPEED / 60.0, TAU)
		total += StreamedWorldState.CAROUSEL_SPEED / 60.0
		# carry the way the node does it (its group scan needs a real tree of players): the node's own function, with the angle it turns this frame
		ride.angle = state["angle"]
		ride._prev_angle = before
		var da := fposmod(ride.angle - ride._prev_angle + PI, TAU) - PI
		ride.carry_body(rider, da)
		ride.carry_body(off_platform, da)
		ride.carry_body(high, da)
		ride.rotor.rotation.y = ride.angle
		var r := Vector2(rider.global_position.x - ride.global_position.x, rider.global_position.z - ride.global_position.z).length()
		worst_radius_error = maxf(worst_radius_error, absf(r - 1.8))
		min_r = minf(min_r, r)
		max_r = maxf(max_r, r)
	var local_end := _local_of(ride, rider)
	_expect(local_start.distance_to(local_end) < 0.02, "a rider slid on the platform: %s -> %s in the ride's frame" % [local_start, local_end])
	_expect(worst_radius_error < 0.005 and min_r > CarouselRide3D.COLUMN_RADIUS and max_r < CarouselRide3D.RADIUS, "a rider left its circle or clipped the column (radius %.3f..%.3f)" % [min_r, max_r])
	_expect(absf(angle_diff(rider.rotation.y - yaw_start, total)) < 0.02, "the rider's facing did not turn with the platform (%.3f of %.3f)" % [angle_diff(rider.rotation.y - yaw_start, 0.0), total])
	_expect(off_platform.global_position.distance_to(off_start) < 0.001, "someone beside the platform was carried")
	_expect(high.global_position.distance_to(high_start) < 0.001, "someone far above the platform was carried")
	_expect(ride.riders_carried >= steps, "the rider was not carried every frame (%d of %d)" % [ride.riders_carried, steps])
	# nobody is carried while it is stopped
	state["on"] = false
	ride._refresh()
	var parked := rider.global_position
	ride.angle = 1.0
	ride._prev_angle = 1.0
	ride._refresh()
	_expect(rider.global_position.distance_to(parked) < 0.001, "a stopped ride moved its rider")
	ride.queue_free()
	for n in [rider, off_platform, high]:
		n.queue_free()
	await host.get_tree().process_frame


func _local_of(ride: CarouselRide3D, body: Node3D) -> Vector3:
	return ride.rotor.global_transform.affine_inverse() * body.global_position


func _check_route(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "CARNIVAL-VALIDATE"   # a fixed world, so the carnival is where the search looks
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 8:
		await host.get_tree().process_frame
	var found := {}
	for y in range(0, -6, -1):
		for x in range(-12, 13):
			for z in range(-12, 13):
				if not found.is_empty():
					break
				for value in route.facility.generator.chunk(Vector3i(x, y, z)).get("region_props", []):
					if String((value as Dictionary).get("type", "")) == "carouselCenterpiece":
						found = {"coord": Vector3i(x, y, z), "prop": value}
						break
	_expect(not found.is_empty(), "no merry-go-round room was generated within the search window")
	if found.is_empty():
		route.queue_free()
		await host.get_tree().process_frame
		return
	var coord: Vector3i = found["coord"]
	var prop: Dictionary = found["prop"]
	var cell: Vector2i = prop["cell"]
	var ride_id := "%d:%d:%d:carouselCenterpiece:%d:%d" % [coord.x, coord.y, coord.z, cell.x, cell.y]
	var info: Dictionary = route._carousel_info(ride_id)
	_expect(not info.is_empty(), "the host cannot re-derive the carousel from its id %s" % ride_id)
	_expect(route._carousel_info("9:9:9:carouselCenterpiece:1:1").is_empty() and route._carousel_info("junk").is_empty(), "the host accepts an invented ride id")
	# the nav footprint: a solid blocker as wide as the column, so hunters path round it
	var blocker: Vector3 = prop.get("blocker_size", Vector3.ZERO)
	_expect(bool(prop.get("solid", false)) and blocker.x >= CarouselRide3D.COLUMN_RADIUS * 2.0 and blocker.z >= CarouselRide3D.COLUMN_RADIUS * 2.0,
		"the carousel's nav blocker %s is narrower than its column" % blocker)
	var center: Vector2 = info["center"]
	route._admin_teleport_to(Vector3(center.x + CarouselRide3D.LEVER_RADIUS + 1.2, float(coord.y) * StreamedFacilityView3D.LEVEL_HEIGHT + 0.3, center.y))
	for _i in 20:
		await host.get_tree().process_frame
	var ride: CarouselRide3D = route.facility.carousel_node(ride_id)
	_expect(ride != null, "the carousel has no node once the player stands at it")
	if ride == null:
		route.queue_free()
		await host.get_tree().process_frame
		return
	_expect(not ride.on and not route.world_state.carousel_on(ride_id), "the ride starts running")
	route._request_carousel(route.player, ride_id)
	_expect(route.world_state.carousel_on(ride_id) and ride.on, "the lever did not start the ride")
	await host.get_tree().create_timer(0.4).timeout
	var a1: float = route.world_state.carousel_angle(ride_id, Time.get_unix_time_from_system())
	_expect(a1 > 0.0 and absf(angle_diff(ride.rotor.rotation.y, route.world_state.carousel_angle(ride_id, Time.get_unix_time_from_system()))) < 0.2, "the ride's drawn angle does not follow the shared state")
	route._request_carousel(route.player, ride_id)
	var stop_angle: float = route.world_state.carousel_angle(ride_id, Time.get_unix_time_from_system())
	_expect(not route.world_state.carousel_on(ride_id) and not ride.on, "the lever did not stop the ride")
	await host.get_tree().create_timer(0.3).timeout
	_expect(absf(angle_diff(route.world_state.carousel_angle(ride_id, Time.get_unix_time_from_system()), stop_angle)) < 0.001, "a stopped ride kept turning")
	# a stranger far away cannot work the lever; the host's idle stop does
	route._accept_carousel(7, {"carousel_id": ride_id})
	_expect(not route.world_state.carousel_on(ride_id), "a peer who is not at the ride started it")
	route._request_carousel(route.player, ride_id)
	route._accept_carousel(0, {"carousel_id": ride_id})
	_expect(not route.world_state.carousel_on(ride_id), "the host's idle stop did not stop the ride")
	route.queue_free()
	await host.get_tree().process_frame


## KT: "2-3 wide space between all sides of the merry go round, including the entryway". In every generated carnival room
## with a carousel, every cell within the ride's reach plus 2.5 cells is open floor not held by another solid prop, and the
## doorway into the room is three cells wide (no narrowing beside the ride).
func _check_clearance() -> void:
	var reach := CarouselRide3D.LEVER_RADIUS + 2.5
	var found := 0
	for seed_text in ["SOAKTEST", "ENDLESS-ROUTE", "KYTTU-LAB", "CARNIVAL-A", "CARNIVAL-B", "REAL-B", "BIOME-A"]:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-9, 10):
			for dx in range(-9, 10):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord) or generator.region_for(coord) != "carnival":
					continue
				var data := generator.chunk(coord)
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					if String(prop.get("type", "")) != "carouselCenterpiece":
						continue
					found += 1
					var where := "%s %s" % [seed_text, coord]
					var grid: Array = data["grid"]
					var centre := Vector2(prop["cell"] as Vector2i) + Vector2(.5, .5) + (prop.get("placement_offset", Vector2.ZERO) as Vector2)
					var own := {}
					for cell in prop.get("occupied_cells", [prop["cell"]]):
						own[cell] = true
					var blocked := {}
					for other_value in data["region_props"]:
						var other: Dictionary = other_value
						if other == prop or not bool(other.get("solid", true)) or bool(other.get("wall_mounted", false)):
							continue
						for cell in other.get("occupied_cells", []):
							blocked[cell] = true
					var radius := ceili(reach)
					for z in range(floori(centre.y) - radius, floori(centre.y) + radius + 1):
						for x in range(floori(centre.x) - radius, floori(centre.x) + radius + 1):
							var cell := Vector2i(x, z)
							if own.has(cell) or (Vector2(cell) + Vector2(.5, .5)).distance_to(centre) > reach:
								continue
							_expect(x >= 0 and z >= 0 and x < grid.size() and z < grid.size() and int(grid[z][x]) == 0 and not blocked.has(cell),
								"%s: the carousel's clearance ring is blocked at %s (%s)" % [where, cell, "wall" if int(grid[clampi(z, 0, grid.size() - 1)][clampi(x, 0, grid.size() - 1)]) != 0 else "prop"])
					# the entryway: the doorway cell and one either side along the wall are open
					for room_value in data["rooms"]:
						var room: Dictionary = room_value
						if not (room["rect"] as Rect2i).has_point(prop["cell"] as Vector2i):
							continue
						var door: Vector2i = room["doorway"]
						var rect: Rect2i = room["rect"]
						var along := Vector2i(0, 1) if door.x == rect.position.x or door.x == rect.end.x - 1 else Vector2i(1, 0)
						for step in range(-1, 2):
							var edge: Vector2i = door + along * step
							_expect(int(grid[edge.y][edge.x]) == 0, "%s: the carousel room's entryway is narrower than three cells at %s" % [where, edge])
	_expect(found >= 3, "only %d carousel rooms found to check the clearance of" % found)
