extends RefCounted

## Seating at hunter scale:
## - every sit type is hunter-sized: its measured seat pan is in its kind's range (a chair 0.55-0.85 m, 0.45 m x the
##   hunter factor; bar stools higher, sofas and benches lower), and each of
##   its sit points is wide and deep enough for a seated hunter;
## - multi-seats (waiting-room rows, benches, couches) give N separate sit points, each its own interactable, inside
##   the prop's footprint and clear of every other prop's collider;
## - the hunters' navigation lists every sit point as a seat, and HunterSeats sits idle hunters down (rarer by
##   difficulty, never Voids, never on Nightmare) and gets them up on a noise or a sighting;
## - the runner still sits on a hunter seat with her eye over the seat pan.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- seating

const SEEDS := ["SEAT-A", "SEAT-B"]
## Seat pan height ranges at hunter scale (person ranges x 1.5): chairs 0.45 m, bar stools 0.65 m, low seats (sofa
## cushions, benches, a beach lounger) 0.25-0.45 m.
const SEAT_PAN := {"chair": Vector2(.55, .85), "stool": Vector2(.85, 1.15), "low": Vector2(.3, .75)}


static func seat_kind(type: String) -> String:
	if type.contains("Stool"):
		return "stool"
	for word in ["Couch", "Sofa", "Bench", "beachChair"]:
		if type.contains(word):
			return "low"
	return "chair"
## A seated normal hunter: hips about 0.6 m across, thighs 0.6 m long (the blocky rig at 1.5x).
const HUNTER_SEAT_WIDTH := .6
const HUNTER_SEAT_DEPTH := .55

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _sit_types() -> Array:
	var out := []
	for type in PropColliderSizes.SIZES:
		if PropModelCatalog.interaction_for(String(type)) == "sit":
			out.append(String(type))
	return out


func run(host: Node) -> int:
	var types := _sit_types()
	_expect(types.size() >= 12, "only %d sit types" % types.size())
	var pans := {}
	for type in types:
		_expect(PropModelCatalog.hunter_scale(type) >= 1.4, "%s is not rescaled to hunter scale" % type)
		var path := PropModelCatalog.model_path(type, type)
		var model := ModelSlot.instantiate_prop(path, type)
		if model == null:
			_expect(false, "%s: no model" % type)
			continue
		host.add_child(model)
		var pan := StreamedFacilityView3D.seat_top(model, path, type)
		model.queue_free()
		pans[type] = snappedf(pan, .01)
		var band: Vector2 = SEAT_PAN[seat_kind(type)]
		_expect(pan >= band.x and pan <= band.y, "%s: %s seat pan %.2f m up, wants %.2f-%.2f (hunter scale)" % [type, seat_kind(type), pan, band.x, band.y])
		var size: Vector3 = PropColliderSizes.SIZES[type]
		var points := PropModelCatalog.seat_points(type, size)
		var seat_width := float((points[0] as Dictionary)["width"])
		var depth := size.z / float(PropModelCatalog.SEAT_ROWS.get(type, [0]).size()) * (.9 if PropModelCatalog.SEAT_ROWS.has(type) else 1.0)
		_expect(points.size() == PropModelCatalog.seat_count(type), "%s: %d sit points, wants %d" % [type, points.size(), PropModelCatalog.seat_count(type)])
		_expect(seat_width >= HUNTER_SEAT_WIDTH, "%s: %d seats of %.2f m, narrower than a seated hunter" % [type, points.size(), seat_width])
		_expect(depth >= HUNTER_SEAT_DEPTH * (.6 if PropModelCatalog.SEAT_ROWS.has(type) else 1.0), "%s: %.2f m deep per row, shallower than a seated hunter's thighs" % [type, depth])
	for type in PropModelCatalog.SEAT_COUNTS:
		_expect(PropModelCatalog.seat_count(String(type)) >= 2, "%s is listed as a multi-seat but is not a seat" % type)
		var offsets := PropModelCatalog.seat_offsets(String(type), 3.0)
		_expect(offsets.size() == int(PropModelCatalog.SEAT_COUNTS[type]), "%s: %d sit points" % [type, offsets.size()])
	_check_world()
	_check_hunters()
	await _check_occupancy(host)
	metrics["seat_pans"] = pans
	if _failures == 0:
		print("  seating  %d sit types, %s" % [types.size(), metrics])
	return _failures


## Generated rooms: each sit prop's sit points (as the view and the navigation lay them) are inside its own footprint and
## clear of every other solid prop's collider; the navigation lists them all.
func _check_world() -> void:
	var props_checked := 0
	var multi := 0
	var clipped := []
	var unreachable := []
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-5, 6):
			for dx in range(-5, 6):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				if bool(data.get("safe_room", false)):
					continue
				var nav := StreamedHunterNavigation.new(generator, 0)
				nav.refresh(0, [coord])
				var expected := 0
				var boxes := []
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					var type := String(prop.get("type", ""))
					if not PropColliderSizes.SIZES.has(type) or not bool(prop.get("solid", true)):
						continue
					boxes.append({"id": prop.get("id", ""), "type": type, "rects": _world_boxes(prop, type)})
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					var type := String(prop.get("type", ""))
					if PropModelCatalog.interaction_for(type) != "sit":
						continue
					expected += PropModelCatalog.seat_count(type)
				var origin := Vector2(coord.x, coord.z) * StreamedRouteGenerator.CHUNK_SIZE
				_expect(nav.seat_spots.size() == expected, "%s: navigation lists %d seats, wants %d" % [coord, nav.seat_spots.size(), expected])
				for spot_value in nav.seat_spots:
					var spot: Dictionary = spot_value
					var at: Vector2 = (spot["seat_at"] as Vector2) - origin
					props_checked += 1
					if PropModelCatalog.seat_count(String(spot["type"])) > 1:
						multi += 1
					var own := false
					for box in boxes:
						for r in box["rects"]:
							if (r as Rect2).has_point(at):
								if String(box["type"]) == String(spot["type"]):
									own = true
								elif PropModelCatalog.interaction_for(String(box["type"])) != "sit" \
										and not RoomCatalog.is_surface_prop(String(box["type"])) and String(box["type"]).find("Table") < 0 \
										and String(box["type"]).find("Desk") < 0:
									clipped.append("%s in %s" % [spot["id"], box["type"]])
					_expect(own, "%s: sit point %s is outside its own %s" % [coord, spot["id"], spot["type"]])
					# reachable: open, clear floor on some side of the seat (a dining chair is reached from beside, its table in front)
					var seat_size: Vector3 = PropColliderSizes.SIZES.get(String(spot["type"]), Vector3.ONE)
					var sides := [(spot["stand_at"] as Vector2) - origin]
					var yaw := float(spot["yaw"])
					var across := Vector2(cos(yaw), -sin(yaw))    # a booth seat's own yaw is turned, its across stays the bench line
					var width := float((PropModelCatalog.seat_points(String(spot["type"]), seat_size)[0] as Dictionary)["width"])
					sides.append(at + across * (width * .5 + .5))
					sides.append(at - across * (width * .5 + .5))
					var blocked := true
					for stand_value in sides:
						var stand: Vector2 = stand_value
						var clear := GeometryAudit.is_open_cell(data.get("grid", []), StreamedRouteGenerator.CHUNK_SIZE,
							Vector2i(floori(stand.x), floori(stand.y)))
						for box in boxes:
							for r in box["rects"]:
								if (r as Rect2).grow(-.05).has_point(stand) and PropModelCatalog.interaction_for(String(box["type"])) != "sit":
									clear = false
						if clear:
							blocked = false
					if blocked:
						unreachable.append("%s %s" % [coord, spot["id"]])
	_expect(props_checked > 50, "only %d sit points in the sample" % props_checked)
	_expect(multi > 5, "only %d multi-seat sit points in the sample" % multi)
	# a few seats tucked into a corner or against a table are expected; most must be reachable
	_expect(unreachable.size() * 20 <= props_checked, "%d of %d sit points have no open floor in front: %s" % [
		unreachable.size(), props_checked, unreachable.slice(0, 6)])
	metrics["unreachable"] = unreachable.size()
	_expect(clipped.is_empty(), "%d sit points inside another prop: %s" % [clipped.size(), clipped.slice(0, 6)])
	metrics["sit_points"] = props_checked
	metrics["multi_seat_points"] = multi


## A prop's collider boxes on the chunk plan (axis-aligned bounds of each turned box).
func _world_boxes(prop: Dictionary, type: String) -> Array:
	var size: Vector3 = PropColliderSizes.SIZES[type]
	var yaw := float(prop.get("yaw", 0.0))
	var centre := Vector2(prop.get("cell", Vector2i.ZERO)) + Vector2(.5, .5) + (prop.get("placement_offset", Vector2.ZERO) as Vector2)
	var out := []
	for box in PropColliderBoxes.boxes(type, size):
		var c: Vector2 = box["c"]
		var h: Vector2 = box["h"]
		var rect := Rect2()
		for corner in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(-h.x, h.y), Vector2(h.x, h.y)]:
			var local := Vector3(c.x + corner.x, 0.0, c.y + corner.y).rotated(Vector3.UP, yaw)
			var p := centre + Vector2(local.x, local.z)
			rect = Rect2(p, Vector2.ZERO) if rect.size == Vector2.ZERO and rect.position == Vector2.ZERO else rect.expand(p)
		out.append(rect)
	return out


func _check_hunters() -> void:
	_expect(not HunterSeats.can_sit("kathy", "nightmare"), "a hunter sat down on Nightmare")
	_expect(HunterSeats.can_sit("kathy", "relaxed"), "kathy never sits on Relaxed")
	_expect(float(HunterSeats.CHANCE_PER_SECOND["relaxed"]) > float(HunterSeats.CHANCE_PER_SECOND["standard"]) \
		and float(HunterSeats.CHANCE_PER_SECOND["standard"]) > float(HunterSeats.CHANCE_PER_SECOND["hard"]), "sitting is not rarer the harder it gets")
	for void_id in HunterRoster.VOID_IDS:
		_expect(not HunterSeats.can_sit(String(void_id), "relaxed"), "the void %s may sit" % void_id)
	_expect(NightWatchPoses.has_pose(HunterSeats.POSE), "no '%s' pose in the hunter pose library" % HunterSeats.POSE)
	var nav := StreamedHunterNavigation.new(StreamedRouteGenerator.new("SIT"), 0)
	nav.seat_spots = [
		{"id": "row#0", "type": "waitingChairs", "seat_at": Vector2(10.0, 10.5), "stand_at": Vector2(10.0, 11.6), "yaw": PI},
		{"id": "row#1", "type": "waitingChairs", "seat_at": Vector2(11.0, 10.5), "stand_at": Vector2(11.0, 11.6), "yaw": PI}]
	var seats := HunterSeats.new()
	var far := {"position": Vector2(60, 60), "noise": 0.0}
	var a := HunterBrain.new(Vector2(10.0, 16.0), "SIT", "kathy", "relaxed")
	a.active = true
	a.state = HunterBrain.State.WANDER
	seats.update("a", a, nav, far, .1, 0.0, "relaxed")
	_expect(seats.sitting.has("a") and a.wander_target == Vector2(10.0, 11.6), "a patrolling hunter did not head for a seat")
	var b := HunterBrain.new(Vector2(10.0, 16.0), "SIT", "kathy", "relaxed")
	b.active = true
	b.state = HunterBrain.State.WANDER
	seats.update("b", b, nav, far, .1, 0.0, "relaxed")
	_expect(String(seats.seat_of("b").get("id", "")) == "row#1", "two hunters went for the same seat of a row")
	a.position = Vector2(10.0, 11.6)
	seats.update("a", a, nav, far, .1, .5, "relaxed")
	_expect(seats.is_seated("a") and a.position == Vector2(10.0, 10.5), "the hunter did not sit on the seat")
	_expect(seats.update("a", a, nav, far, 1.0, .5, "relaxed"), "a far quiet runner got the seated hunter up")
	var loud := {"position": Vector2(18, 10.5), "noise": 4.0}
	seats.update("a", a, null, loud, .1, .5, "relaxed")
	_expect(not seats.is_seated("a") and a.state == HunterBrain.State.INVESTIGATE and a.position == Vector2(10.0, 11.6),
		"a noise did not get the hunter up to look")
	_expect(HunterSeats.gets_up_for(Vector2.ZERO, {"position": Vector2(6, 0), "noise": 0.0}, null), "a runner in sight does not get her up")
	_expect(not HunterSeats.gets_up_for(Vector2.ZERO, {"position": Vector2(6, 0), "hidden": true}, null), "a hidden runner got her up")
	var c := HunterBrain.new(Vector2(10.0, 16.0), "SIT", "kathy", "relaxed")
	c.active = true
	c.state = HunterBrain.State.WANDER
	_expect(not seats.update("c", c, nav, far, .1, .99, "relaxed") and not seats.sitting.has("c"), "a hunter sat with a failed roll")


## Three occupants on one waiting-room row: the local runner on seat 0, a remote runner on seat 1 (as their replicated
## seat_at fills SeatOccupancy), a hunter offered only seat 2; a taken seat offers no prompt and refuses the sit.
func _check_occupancy(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "SEATING"
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 30:
		await host.get_tree().physics_frame
	var player: PlayerController3D = route.player
	route.set_process(false)
	route.set_physics_process(false)
	player.set_physics_process(false)
	var type := "waitingChairs"
	var size: Vector3 = PropColliderSizes.SIZES[type]
	var base := player.global_position + Vector3(0, 0, -3)
	var seats := []
	for x in PropModelCatalog.seat_offsets(type, size.x):
		var furniture := RouteInteractable3D.new()
		furniture.kind = RouteInteractable3D.Kind.FURNITURE
		furniture.configure_furniture("sit")
		furniture.set_meta("rest_size", Vector3(size.x / 3.0, size.y, size.z))
		route.add_child(furniture)
		furniture.global_position = base + Vector3(float(x), .03, 0)
		seats.append(furniture)
	_expect(seats.size() == 3, "a waiting-room row has %d sit points" % seats.size())
	SeatOccupancy.rebuild([])
	for seat in seats:
		_expect((seat as RouteInteractable3D).get_prompt() == "SIT DOWN", "a free seat does not offer SIT DOWN")
	player.use_furniture(seats[0], "sit")
	_expect(player.resting_furniture == seats[0], "the runner did not sit on seat 0")
	var state: Dictionary = route._remotes._local_state() if route._remotes != null else {}
	_expect(state.get("seat_at") is Vector2 and (state["seat_at"] as Vector2).distance_to(SeatOccupancy.plan_of(seats[0])) < .01,
		"the runner's replicated state does not carry the seat (%s)" % [state.get("seat_at")])
	# a teammate on seat 1, as their state arrives
	SeatOccupancy.rebuild([SeatOccupancy.plan_of(seats[1])])
	_expect((seats[1] as RouteInteractable3D).get_prompt() == "", "a seat a teammate sits on still offers SIT DOWN")
	_expect((seats[2] as RouteInteractable3D).get_prompt() == "SIT DOWN", "the free seat next to two occupants is not offered")
	player.leave_furniture()
	for _i in 30:
		await host.get_tree().physics_frame
	var refused := (seats[1] as RouteInteractable3D).activate(player)
	_expect(player.resting_furniture != seats[1], "the runner sat on a teammate's seat (%s)" % refused)
	# a hunter wanting a seat on the same row gets only the free one
	var nav := StreamedHunterNavigation.new(StreamedRouteGenerator.new("SEATING"), 0)
	nav.seat_spots = []
	for i in seats.size():
		var at := SeatOccupancy.plan_of(seats[i])
		nav.seat_spots.append({"id": "row#%d" % i, "type": type, "seat_at": at, "stand_at": at + Vector2(0, 1.2), "yaw": 0.0})
	SeatOccupancy.rebuild([SeatOccupancy.plan_of(seats[0]), SeatOccupancy.plan_of(seats[1])])
	var hunters := HunterSeats.new()
	var brain := HunterBrain.new(SeatOccupancy.plan_of(seats[0]) + Vector2(0, 4), "SEATING", "kathy", "relaxed")
	brain.active = true
	brain.state = HunterBrain.State.WANDER
	hunters.update("h", brain, nav, {"position": Vector2(900, 900)}, .1, 0.0, "relaxed")
	_expect(String(hunters.seat_of("h").get("id", "")) == "row#2", "the hunter picked a taken seat (%s)" % hunters.seat_of("h").get("id", ""))
	metrics["occupancy"] = "3 on one row"
	SeatOccupancy.rebuild([])
	route.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
