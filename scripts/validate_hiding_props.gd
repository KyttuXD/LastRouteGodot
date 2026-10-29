extends RefCounted

## Room-purpose props and furniture you can hide in (docs/HIDING_PROPS.md):
## - the new prop types are placed by the room recipes they belong to (storage shelving and barrels, the reception desk,
##   the infirmary's hospital beds and IV stands, the archive globe, the bedroom mirror), with fitted colliders;
## - every bed and wardrobe a room recipe placed is an ordinary hiding_spot fixture with its style, and its hiding
##   position and exit are on open floor (nothing hides inside a wall);
## - in the streamed route: E slides under a bed / steps into a wardrobe and back out, with the limited view;
## - hunters only check a spot they tracked the runner to, with a tell every peer sees, and it pulls the runner out;
## - guests get the hidden state and spot in the replicated player state, and the tell as a stream event;
## - capacity (HideOccupancy): one runner per spot, two in a wardrobe (prop data hide_capacity), each in its own slot;
##   a full spot says SPOT TAKEN, the host puts an extra occupant back out, a hunter's check pulls the front one first.
##
##   godot --headless --path . res://scenes/validate.tscn -- hiding_props

const SEEDS := ["HIDE-A", "HIDE-B", "HIDE-C", "HIDE-D"]
const NEW_TYPES := ["hospitalBed", "ivStand", "medicalCart", "readingTable", "libraryGlobe", "storageBarrel",
	"storageShelving", "receptionDesk", "pottedPlant", "standingMirror"]
## recipe -> new types it must place somewhere in the sample
const RECIPE_TYPES := {
	"maze_storage": ["storageShelving", "storageBarrel"],
	"office_reception": ["receptionDesk", "pottedPlant"],
	"infirmary": ["hospitalBed", "ivStand", "medicalCart"],
	"gothic_archive": ["libraryGlobe", "readingTable"],
	"bedroom": ["standingMirror"],
}

## Fit (docs/HIDING_PROPS.md): a lying runner (about 0.3 m) needs this much clear space under a bed, a standing one
## this much room inside a wardrobe.
const BED_CLEARANCE := 0.36
const WARDROBE_INTERIOR := Vector3(0.6, 1.9, 0.55)

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _check_models() -> void:
	for type in NEW_TYPES:
		_expect(PropModelCatalog.has_model(type), "%s has no catalogue model" % type)
		_expect(BlockyPropModels.MODELS.has(type), "%s has no blocky model" % type)
		_expect(PropColliderSizes.SIZES.has(type), "%s has no fitted collider (regenerate prop_collider_sizes.gd)" % type)
		for path in BlockyPropModels.MODELS.get(type, []):
			_expect(load(String(path)) is PackedScene, "%s model %s does not load" % [type, path])


## Lowest face over the bed's middle (away from the legs) and any face low across its foot (the way in).
func _check_fit() -> void:
	for type in StreamedRouteGenerator.HIDING_PROP_STYLES:
		var style := String(StreamedRouteGenerator.HIDING_PROP_STYLES[type])
		for path in BlockyPropModels.MODELS.get(type, []) + BlockyPropModels.MODELS.get(type + "Mansion", []):
			var scene := load(String(path)) as PackedScene
			if scene == null:
				continue
			var node := scene.instantiate()
			var faces := PackedVector3Array()
			var box := AABB()
			var first := true
			for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
				var mi := mesh_node as MeshInstance3D
				var xf := _relative(node, mi)
				for f in mi.mesh.get_faces():
					faces.append(xf * f)
				var b := xf * mi.get_aabb()
				box = b if first else box.merge(b)
				first = false
			node.free()
			if style == "wardrobe":
				_expect(box.size.x >= WARDROBE_INTERIOR.x and box.size.y >= WARDROBE_INTERIOR.y and box.size.z >= WARDROBE_INTERIOR.z,
					"%s (%s) is too small to stand in: %s" % [type, path, box.size])
				continue
			var floor_y := box.position.y
			var lowest := INF
			var foot_blocked := false
			var inset_x := box.size.x * .14
			for i in range(0, faces.size(), 3):
				var c := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
				var y := c.y - floor_y
				if y < .01 or c.x < box.position.x + inset_x or c.x > box.end.x - inset_x:
					continue
				if c.z > box.position.z + box.size.z * .2 and c.z < box.end.z - box.size.z * .12:
					lowest = minf(lowest, minf(faces[i].y, minf(faces[i + 1].y, faces[i + 2].y)) - floor_y)
				if c.z > box.end.z - box.size.z * .1 and y < BED_CLEARANCE - .02:
					foot_blocked = true
			_expect(lowest >= BED_CLEARANCE, "%s (%s) has only %.2f m under it (a lying runner needs %.2f)" % [type, path, lowest, BED_CLEARANCE])
			_expect(not foot_blocked, "%s (%s) is closed at the foot below %.2f m, nothing can slide under" % [type, path, BED_CLEARANCE])


static func _relative(root: Node, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


func _scan_generator() -> void:
	var placed := {}         # recipe -> {type: count}
	var styled := {"bed": 0, "wardrobe": 0}
	var hideable := 0
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-7, 8):
			for dx in range(-7, 8):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				var grid: Array = data.get("grid", [])
				var fixtures_by_cell := {}
				for fixture_value in data.get("fixtures", []):
					var fixture: Dictionary = fixture_value
					var style := String(fixture.get("style", ""))
					if style.is_empty():
						continue
					styled[style] = int(styled.get(style, 0)) + 1
					fixtures_by_cell[fixture.get("prop_id", "")] = fixture
					_expect(_open(grid, fixture["cell"]), "%s is used from a blocked cell %s" % [fixture["id"], fixture["cell"]])
					_expect(String(fixture.get("kind", "")) == "hiding_spot", "styled fixture %s is not a hiding spot" % fixture["id"])
					_expect(int(fixture.get("capacity", 0)) == (2 if style == "wardrobe" else 1),
						"%s holds %s runners (beds 1, wardrobes 2)" % [fixture["id"], fixture.get("capacity")])
					var local: Vector2 = fixture.get("local_position", Vector2.ZERO)
					var inside := Vector2i(floori(local.x), floori(local.y))
					_expect(_open(grid, inside), "%s hides inside a wall at %s" % [fixture["id"], inside])
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					var type := String(prop.get("type", ""))
					var recipe := String(prop.get("room_template", ""))
					if not recipe.is_empty():
						var counts: Dictionary = placed.get(recipe, {})
						counts[type] = int(counts.get(type, 0)) + 1
						placed[recipe] = counts
					if StreamedRouteGenerator.HIDING_PROP_STYLES.has(type) and not recipe.is_empty() \
							and bool(prop.get("solid", true)) and not generator.is_safe_room(coord):
						hideable += 1
						var fixture: Dictionary = fixtures_by_cell.get(String(prop.get("id", "")), {})
						_expect(not fixture.is_empty(), "%s %s in %s is not a hiding spot" % [type, prop.get("id", ""), recipe])
						if not fixture.is_empty():
							_expect(String(fixture["style"]) == String(StreamedRouteGenerator.HIDING_PROP_STYLES[type]),
								"%s got hiding style %s" % [type, fixture["style"]])
	for recipe in RECIPE_TYPES:
		var counts: Dictionary = placed.get(recipe, {})
		_expect(not counts.is_empty(), "no %s room in the sample" % recipe)
		if counts.is_empty():
			continue
		for type in RECIPE_TYPES[recipe]:
			_expect(int(counts.get(type, 0)) > 0, "%s rooms never place %s (placed: %s)" % [recipe, type, counts.keys()])
	_expect(int(styled["bed"]) >= 5 and int(styled["wardrobe"]) >= 3,
		"too few furniture hiding spots in the sample (beds %d, wardrobes %d)" % [styled["bed"], styled["wardrobe"]])
	metrics = {"beds": styled["bed"], "wardrobes": styled["wardrobe"], "hideable_props": hideable,
		"recipes": placed.keys().size()}


static func _open(grid: Array, cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < grid.size() and cell.x >= 0 and cell.x < (grid[cell.y] as Array).size() \
		and int(grid[cell.y][cell.x]) == 0


func _check_search_rule() -> void:
	var spot := Vector2(10.5, 10.5)
	var chase := HunterBrain.State.CHASE
	_expect(HunterBrain.hide_check_triggers(chase, true, spot + Vector2(1.5, 0), spot + Vector2(1.0, 0), spot),
		"a hunter that chased you to the spot does not check it")
	_expect(not HunterBrain.hide_check_triggers(HunterBrain.State.WANDER, true, spot, spot, spot),
		"a wandering hunter checked a spot it never tracked you to")
	_expect(not HunterBrain.hide_check_triggers(chase, true, spot + Vector2(6, 0), spot, spot),
		"a hunter checked a spot far from where it last saw you")
	_expect(not HunterBrain.hide_check_triggers(chase, false, spot, spot, spot), "a hunter with no sighting checked a spot")
	_expect(not HunterBrain.hide_check_triggers(chase, true, spot, spot + Vector2(3, 0), spot),
		"a hunter checked a spot from across the room")
	_expect(GameConfig.HIDE_CHECK_TELL_SECONDS >= 1.2, "the search tell is shorter than a reaction (%.1fs)" % GameConfig.HIDE_CHECK_TELL_SECONDS)
	_expect(GameConfig.HIDE_CHECK_COOLDOWN_SECONDS >= 10.0, "a checked spot is searched again too soon")


func _spawn_spot(route: Node, player: PlayerController3D, style: String, size: Vector3, offset: Vector3) -> RouteInteractable3D:
	var spot := RouteInteractable3D.new()
	spot.kind = RouteInteractable3D.Kind.HIDING_SPOT
	spot.hide_style = style
	spot.hide_size = size
	spot.prompt_text = "HIDE UNDER BED" if style == "bed" else "HIDE IN WARDROBE"
	spot.add_to_group("streamed_hiding_spot")
	route.add_child(spot)
	spot.global_position = player.global_position + offset
	spot.rotation.y = PI    # its opening (-Z) faces the runner
	spot.source_cell = Vector2i(floori(spot.global_position.x), floori(spot.global_position.z))
	return spot


func _check_route(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "HIDE-ROUTE"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 30:
		await host.get_tree().physics_frame
	var player: PlayerController3D = route.player
	var standing := player.first_person_pivot.position.y
	var loaded := 0
	for node in host.get_tree().get_nodes_in_group("streamed_hiding_spot"):
		if node is RouteInteractable3D and not (node as RouteInteractable3D).hide_style.is_empty():
			loaded += 1
	metrics["loaded_furniture_spots"] = loaded
	for style in ["bed", "wardrobe"]:
		var size := Vector3(1.0, .75, 2.0) if style == "bed" else Vector3(1.2, 2.1, .62)
		var spot := _spawn_spot(route, player, style, size, Vector3(0, 0, -2.5))
		await host.get_tree().process_frame
		var before := player.global_position
		Sound.reset_test_counters()
		var message := spot.activate(player)
		_expect(player.hidden and player.hidden_spot == spot.source_cell, "E on the %s did not hide the runner (%s)" % [style, message])
		# the camera eases into the spot: 0.4-0.8 s, input locked, under a bed it stays below the frame
		_expect(player.hide_move_active(), "entering the %s cut straight to the inside view" % style)
		var frames := 0
		var inverse := spot.global_transform.affine_inverse()
		while player.hide_move_active() and frames < 120:
			player._physics_process(1.0 / 60.0)
			frames += 1
			_expect(player.input_frozen, "input was free during the %s move" % style)
			var local := inverse * player.first_person_pivot.global_position
			var inside_footprint := absf(local.x) < size.x * .5 - .05 and absf(local.z) < size.z * .5 - .05
			if style == "bed" and inside_footprint:
				_expect(local.y < BED_CLEARANCE, "the camera went through the bed frame (%.2f m) on the way under" % local.y)
		var seconds := float(frames) / 60.0
		_expect(seconds >= .4 and seconds <= .8, "the %s enter move took %.2f s (0.4-0.8)" % [style, seconds])
		metrics["%s_enter_s" % style] = seconds
		_expect(player.global_position.distance_to(spot.hiding_inside_position()) < .05, "the runner is not inside the %s" % style)
		var eye := player.first_person_pivot.position.y
		if style == "bed":
			_expect(eye < .3, "under the bed the view is still at %.2f m" % eye)
		else:
			_expect(absf(eye - standing) < .01, "the wardrobe changed the eye height")
		var seal := spot.get_node_or_null("HideSeal") as Node3D
		_expect(seal != null and seal.visible, "the %s gives no limited view (no seal)" % style)
		var state: Dictionary = route._remotes._local_state()
		_expect(bool(state.get("hidden", false)) and Vector2i(state.get("hiding_spot", Vector2i(-1, -1))) == spot.source_cell,
			"guests would not see the runner hidden in the %s" % style)
		# a hunter's check: the tell plays from the stream event (what every guest runs), then the host pulls them out
		route._apply_stream_world_event({"what": "stream_hide_check", "cell": spot.source_cell, "seconds": 1.6})
		_expect(spot.search_tell_active(), "the %s search tell did not start from the stream event" % style)
		_expect(int(Sound.play_counts.get("hide_search", 0)) >= 1, "the %s search tell is silent" % style)
		route._apply_player_event({"what": "hide_found", "at": Vector2(before.x, before.z)})
		_expect(not player.hidden, "a hunter's check did not pull the runner out of the %s" % style)
		_expect(absf(player.first_person_pivot.position.y - standing) < .01, "the view stayed low after the %s" % style)
		_expect(seal == null or not seal.visible, "the %s seal stayed up after leaving" % style)
		_expect(not player.hide_move_active(), "a hunter's pull out of the %s was animated instead of immediate" % style)
		# enter and leave with E again; leaving eases back out the same way
		spot.activate(player)
		_expect(player.hidden, "could not hide in the %s a second time" % style)
		for _i in 60:
			player._physics_process(1.0 / 60.0)
		player.leave_hiding()
		_expect(player.hide_move_active() and player.input_frozen, "leaving the %s cut instead of easing out" % style)
		for _i in 60:
			player._physics_process(1.0 / 60.0)
		_expect(not player.hide_move_active() and not player.input_frozen, "the %s exit move never finished" % style)
		_expect(not player.hidden and player.global_position.distance_to(before) < .3,
			"leaving the %s did not put the runner back where they entered" % style)
		spot.queue_free()
		await host.get_tree().process_frame
	await _check_capacity_route(route, player)
	route.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame


func _check_capacity_rules() -> void:
	_expect(PropModelCatalog.hide_capacity("bedroomWardrobe") == 2 and PropModelCatalog.hide_capacity("gothicWardrobe") == 2
		and PropModelCatalog.hide_capacity("bedroomWardrobeMansion") == 2,
		"wardrobes do not hold two (data/props hide_capacity)")
	for type in ["singleBed", "doubleBed", "gothicDoubleBed", "officeDesk"]:
		_expect(PropModelCatalog.hide_capacity(type) == 1, "%s holds %d, not 1" % [type, PropModelCatalog.hide_capacity(type)])
	_expect(ContentRegistry.PROP_FIELDS.has("hide_capacity"), "hide_capacity is not a lr.prop/1 field mods can set")
	var locker := RouteInteractable3D.new()
	_expect(locker.hide_capacity == 1, "a locker holds more than one")
	locker.free()
	_expect(PlayerStateWire.HOT_FIELDS.has("hide_slot"), "hide_slot is not on the wire")
	var cell := Vector2i(4, 4)
	HideOccupancy.rebuild([])
	_expect(HideOccupancy.free_slot(cell, 1) == 0 and HideOccupancy.free_slot(cell, 2) == 0, "an empty spot has no free slot")
	HideOccupancy.rebuild([{"cell": cell, "peer": 2, "slot": 0}])
	_expect(HideOccupancy.is_full(cell, 1) and HideOccupancy.free_slot(cell, 1) == -1, "a locker with one inside is not full")
	_expect(not HideOccupancy.is_full(cell, 2) and HideOccupancy.free_slot(cell, 2) == 1, "the second wardrobe slot is not free")
	HideOccupancy.rebuild([{"cell": cell, "peer": 2, "slot": 1}])
	_expect(HideOccupancy.free_slot(cell, 2) == 0, "the front slot is not offered when only the back one is taken")
	HideOccupancy.rebuild([{"cell": cell, "peer": 2, "slot": 0}, {"cell": cell, "peer": 3, "slot": 1}])
	_expect(HideOccupancy.is_full(cell, 2) and HideOccupancy.free_slot(cell, 2) == -1, "a wardrobe with two inside is not full")
	_expect(HideOccupancy.is_full(cell, 9), "a mod capacity above MAX is not clamped")
	# the host settling a same-frame race: the lowest peers keep the spot
	var one := func(_c: Vector2i) -> int: return 1
	var two := func(_c: Vector2i) -> int: return 2
	_expect(HideOccupancy.overflow([{"cell": cell, "peer": 5, "slot": 0}, {"cell": cell, "peer": 1, "slot": 0}], one) == [5],
		"two runners in a locker are not settled to one")
	_expect(HideOccupancy.overflow([{"cell": cell, "peer": 5, "slot": 0}, {"cell": cell, "peer": 1, "slot": 1}], two).is_empty(),
		"two runners in their own wardrobe slots are put out")
	_expect(HideOccupancy.overflow([{"cell": cell, "peer": 5, "slot": 0}, {"cell": cell, "peer": 1, "slot": 0}], two) == [5],
		"two runners on one wardrobe slot are not settled")
	_expect(HideOccupancy.overflow([{"cell": cell, "peer": 2, "slot": 0}, {"cell": cell, "peer": 3, "slot": 1},
		{"cell": cell, "peer": 4, "slot": 1}], two) == [4], "a third runner in a wardrobe is not put out")
	# a hunter's check: the front slot (nearest the door) first
	_expect(int(HideOccupancy.grab_order([{"peer": 2, "slot": 1}, {"peer": 7, "slot": 0}])[0]["peer"]) == 7,
		"the hunter does not pull out the runner nearest the door first")
	HideOccupancy.rebuild([])


## In the route: a full spot refuses (SPOT TAKEN, no hide), a wardrobe's two slots sit apart inside it.
func _check_capacity_route(route: Node, player: PlayerController3D) -> void:
	for style in ["bed", "wardrobe"]:
		var size := Vector3(1.0, .75, 2.0) if style == "bed" else Vector3(1.2, 2.1, .62)
		var spot := _spawn_spot(route, player, style, size, Vector3(0, 0, -2.5))
		spot.hide_capacity = 2 if style == "wardrobe" else 1
		await route.get_tree().process_frame
		HideOccupancy.rebuild([{"cell": spot.source_cell, "peer": 9, "slot": 0}])
		if style == "bed":
			_expect(spot.get_prompt() == "SPOT TAKEN", "a taken bed still offers %s" % spot.get_prompt())
			var message := spot.activate(player)
			_expect(not player.hidden and message == "SPOT TAKEN", "hid under a bed someone is under (%s)" % message)
		else:
			_expect(spot.get_prompt() != "SPOT TAKEN", "a wardrobe with one inside refuses the second")
			var a := spot.hiding_inside_position(0)
			var b := spot.hiding_inside_position(1)
			var inverse := spot.global_transform.affine_inverse()
			_expect(a.distance_to(b) >= .45, "the two wardrobe slots are only %.2f m apart (bodies overlap)" % a.distance_to(b))
			for p in [a, b]:
				var local: Vector3 = inverse * p
				_expect(absf(local.x) + .2 <= size.x * .5 and absf(local.z) + .2 <= size.z * .5 + .05,
					"a wardrobe slot pokes out of it at %s" % local)
			_expect((inverse * a).z < (inverse * b).z, "slot 0 is not the one nearer the door")
			spot.activate(player)
			_expect(player.hidden and player.hidden_slot == 1 and player.global_position.distance_to(b) < .05,
				"the second runner did not take the free back slot")
			_expect(int(route._remotes._local_state().get("hide_slot", -1)) == 1, "guests do not get the hide slot")
			player.leave_hiding(Vector2.ZERO, true)
			_expect(player.hidden_slot == 0, "the slot outlived the hide")
			HideOccupancy.rebuild([{"cell": spot.source_cell, "peer": 9, "slot": 0}, {"cell": spot.source_cell, "peer": 8, "slot": 1}])
			_expect(spot.get_prompt() == "SPOT TAKEN" and spot.activate(player) == "SPOT TAKEN" and not player.hidden,
				"a wardrobe with two inside let a third in")
		HideOccupancy.rebuild([])
		spot.queue_free()
		await route.get_tree().process_frame


func run(host: Node) -> int:
	_check_capacity_rules()
	_check_models()
	_check_fit()
	_scan_generator()
	_check_search_rule()
	await _check_route(host)
	if _failures == 0:
		print("  hiding_props  %s" % [metrics])
	return _failures
