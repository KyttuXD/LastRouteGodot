extends RefCounted

## Physical vents (KT 2026-10-28), headless on VentNetwork's duct data until REGIONS' layer view lands:
## VentCrawl climbs in at a grate, crawls only along duct cells and climbs out, never moving more than a crawl step a
## frame (no teleport); thumps make noise; VentNav routes through the ducts for Verrine always and for others only on
## Hard / Nightmare when much shorter; Verrine crawls to the grate beside a runner and climbs out there, never jumping;
## GuestGuard holds a guest in a duct to crawl speed.
##
##   godot --headless --path . res://scenes/validate.tscn -- vents

const STEP := 1.0 / 60.0
const SEEDS := ["VENTS-A", "VENTS-B", "KYTTU-LAB"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _network(seed_text: String) -> VentNetwork:
	var surface := StreamedRouteGenerator.new(seed_text)
	var mezz := MezzanineRouteGenerator.new(surface)
	var offices := OfficesRouteGenerator.new(mezz)
	var archive := ArchiveRouteGenerator.new(offices)
	return VentNetwork.new(surface, [mezz, offices, archive, AtticRouteGenerator.new(archive)])


## Two level-0 grates a few chunks apart, joined by the lattice.
func _grate_pair(network: VentNetwork) -> Array:
	var first: Dictionary = {}
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for link in network.chunk(Vector3i(dx, 0, dz))["links"]:
				if int(link["from_level"]) != 0:
					continue
				if first.is_empty():
					first = link
				elif VentCrawl.grate_centre(link).distance_to(VentCrawl.grate_centre(first)) > 20.0:
					return [first, link]
	return []


func run(_host: Node) -> int:
	_expect(VentNav.uses_vents("verrine", "relaxed") and VentNav.uses_vents("kathy", "hard")
		and VentNav.uses_vents("kathy", "nightmare") and not VentNav.uses_vents("kathy", "standard"),
		"who uses the vents: Verrine always, others on Hard / Nightmare")
	var walks := 0
	for seed_text in SEEDS:
		var network := _network(seed_text)
		var pair := _grate_pair(network)
		if pair.is_empty():
			_expect(false, "%s: no two level-0 grates 20+ cells apart near the origin" % seed_text)
			continue
		var a: Dictionary = pair[0]
		var b: Dictionary = pair[1]
		var nav := VentNav.new(network)
		var path := nav.duct_path(VentCrawl.grate_centre(a), VentCrawl.grate_centre(b))
		_expect(not path.is_empty(), "%s: two grates on the lattice do not connect" % seed_text)
		for i in range(1, path.size()):
			_expect(Vector2(path[i]).distance_to(path[i - 1]) <= 1.01, "%s: the duct path skips a cell" % seed_text)
		# a runner climbs in, crawls the path, climbs out: every frame a small step
		var crawl := VentCrawl.new(network)
		var start := VentCrawl.grate_centre(a) + Vector2(1.0, 0.0)
		_expect(crawl.enter(a, start), "%s: could not climb in at a grate" % seed_text)
		_expect(not crawl.enter(a, start), "%s: climbed in twice" % seed_text)
		var biggest := 0.0
		var thumps := 0
		var frames := 0
		var left := path.duplicate()
		while frames < 60 * 120:
			frames += 1
			var steer := Vector2.ZERO
			if crawl.phase == VentCrawl.Phase.DUCT:
				while not left.is_empty() and crawl.position.distance_to(left[0]) < .15:
					left.pop_front()
				if left.is_empty():
					break
				steer = (Vector2(left[0]) - crawl.position).normalized()
				_expect(crawl.is_duct(crawl.position), "%s: the crawler left the duct at %s" % [seed_text, crawl.position])
			var before := crawl.position
			var stepped := crawl.step(STEP, steer)
			biggest = maxf(biggest, crawl.position.distance_to(before))
			thumps += 1 if bool(stepped["thump"]) else 0
		_expect(crawl.phase == VentCrawl.Phase.DUCT and crawl.position.distance_to(VentCrawl.grate_centre(b)) <= VentCrawl.GRATE_REACH,
			"%s: the crawl did not reach the far grate (%s)" % [seed_text, crawl.position])
		_expect(thumps > 0, "%s: crawling the ducts made no sound" % seed_text)
		var onto := VentCrawl.grate_centre(b) + Vector2(0.0, 1.0)
		_expect(crawl.exit_at(b, onto), "%s: could not climb out at the far grate" % seed_text)
		for _i in 90:
			var before := crawl.position
			crawl.step(STEP, Vector2.ZERO)
			biggest = maxf(biggest, crawl.position.distance_to(before))
		_expect(crawl.phase == VentCrawl.Phase.OUT and crawl.position.distance_to(onto) < .01, "%s: the climb out did not land" % seed_text)
		var climb_step := VentCrawl.CLIMB_REACH / (VentCrawl.CLIMB_SECONDS * 60.0)
		_expect(biggest <= maxf(VentCrawl.CRAWL_SPEED * STEP, climb_step) + .001,
			"%s: a frame moved %.2f cells: that is a teleport" % [seed_text, biggest])
		# crawling straight into a duct wall goes nowhere
		var wall := VentCrawl.new(network)
		wall.phase = VentCrawl.Phase.DUCT
		wall.position = VentCrawl.grate_centre(a)
		var side := Vector2(1, 0) if not wall.is_duct(wall.position + Vector2(1, 0)) else Vector2(0, 1)
		if not wall.is_duct(wall.position + side):
			for _i in 120:
				wall.step(STEP, side)
			_expect(wall.is_duct(wall.position), "%s: crawled through a duct wall" % seed_text)
		# hunter routes: Verrine always takes it; Kathy on Hard only when much shorter; Standard never
		var from := VentCrawl.grate_centre(a) + Vector2(1, 0)
		var to := VentCrawl.grate_centre(b) + Vector2(1, 0)
		_expect(not nav.route(from, to, 0, INF, "verrine", "relaxed").is_empty(), "%s: Verrine does not route through the ducts" % seed_text)
		_expect(not nav.route(from, to, 0, 1000.0, "kathy", "hard").is_empty(), "%s: a Hard hunter skips a much shorter duct" % seed_text)
		_expect(nav.route(from, to, 0, from.distance_to(to) * 1.05, "kathy", "hard").is_empty(), "%s: a Hard hunter crawls when walking is as short" % seed_text)
		_expect(nav.route(from, to, 0, 1000.0, "kathy", "standard").is_empty(), "%s: a Standard hunter used the ducts" % seed_text)
		# Verrine: crawls to the grate beside a runner and climbs out there, no jumps
		var verrine := HunterBrain.new(VentCrawl.grate_centre(a), "%s:VERRINE" % seed_text, "verrine", "standard")
		var gimmick := verrine.gimmick as VerrineGimmick
		_expect(gimmick != null, "%s: Verrine has no VerrineGimmick" % seed_text)
		if gimmick == null:
			continue
		gimmick.vents = network
		gimmick.level = 0
		var runner := VentCrawl.grate_centre(b) + Vector2(2.0, 0.0)
		var target := {"position": runner, "depth": 0, "duct": false}
		var jump := 0.0
		var came_out := false
		# the first tick settles her into her duct (spawn placement); every tick after that is measured
		gimmick.before_perception(verrine, STEP, target, null)
		gimmick.after_perception(verrine, STEP, target, null)
		_expect(gimmick.crawl != null and gimmick.crawl.inside() and gimmick.crawl.is_duct(verrine.position),
			"%s: Verrine did not start in the ducts" % seed_text)
		for _i in 60 * 120:
			var before := verrine.position
			gimmick.before_perception(verrine, STEP, target, null)
			gimmick.after_perception(verrine, STEP, target, null)
			jump = maxf(jump, verrine.position.distance_to(before))
			if gimmick.crawl != null and gimmick.crawl.phase == VentCrawl.Phase.OUT:
				came_out = true
				break
		_expect(came_out, "%s: Verrine never climbed out beside the runner" % seed_text)
		_expect(verrine.position.distance_to(VentCrawl.grate_centre(b)) <= VentCrawl.CLIMB_REACH + .01,
			"%s: Verrine came out away from the grate nearest the runner (%s)" % [seed_text, verrine.position])
		_expect(jump <= maxf(VentCrawl.CRAWL_SPEED * STEP, climb_step) * 1.01 + .001, "%s: Verrine jumped %.2f cells in a frame" % [seed_text, jump])
		_expect(not gimmick.hidden_from_view(), "%s: Verrine is hidden in the physical vents" % seed_text)
		_expect(gimmick.use_vent("x", verrine, null, null).is_empty(), "%s: the grate-to-grate teleport still runs" % seed_text)
		walks += 1
	# GuestGuard: a guest in a duct is held to crawl speed
	var guard := GuestGuard.new()
	var t := 0.0
	var x := 0.0
	var flagged := {}
	guard.check(5, {"at": Vector3.ZERO, "depth": 0, "duct": true}, 0.0)
	while t < 3.0:
		t += .05
		x += VentCrawl.CRAWL_SPEED * .05
		flagged = guard.check(5, {"at": Vector3(x, 0, 0), "depth": 0, "duct": true}, t)
		if not flagged.is_empty():
			break
	_expect(flagged.is_empty(), "a crawling guest was flagged (%s)" % [flagged])
	var fast := GuestGuard.new()
	fast.check(6, {"at": Vector3.ZERO, "depth": 0, "duct": true}, 0.0)
	t = 0.0
	x = 0.0
	flagged = {}
	while t < 3.0 and flagged.is_empty():
		t += .05
		x += GuestGuard.max_speed * .05
		flagged = fast.check(6, {"at": Vector3(x, 0, 0), "depth": 0, "duct": true}, t)
	_expect(not flagged.is_empty(), "a guest sprinted through a duct unflagged")
	await _in_scene(_host)
	if _failures == 0:
		print("  ok    vents: crawl in / along / out on %d seeds, no frame jump, thumps, routes, Verrine out beside the runner, crawl speed held" % walks)
	return _failures


## The live route: the player climbs into the duct over a real storey-0 grate, crawls, and climbs back out; the old
## grate-to-grate vent fixtures are gone; a Hard hunter's brain takes a much shorter duct; Verrine gets the duct layer.
func _in_scene(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 8:
		await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
	_expect(player.vents is VentNetwork, "the scene did not hand the duct layer to the player")
	_expect(host.get_tree().get_nodes_in_group("streamed_vent").is_empty(), "old teleport vent fixtures still spawn")
	if not player.vents is VentNetwork:
		scene.queue_free()
		return
	var at := Vector2(player.global_position.x, player.global_position.z)
	var grates := VentNav.new(player.vents).grates_around(at, 0, 60.0)
	_expect(not grates.is_empty(), "no storey-0 grate within 60 cells of the spawn")
	if grates.is_empty():
		scene.queue_free()
		return
	var grate: Dictionary = grates[0]
	var under := VentCrawl.grate_centre(grate)
	player.global_position = Vector3(under.x, 0.05, under.y)
	player.velocity = Vector3.ZERO
	player.vent_level = 0
	_expect(player.get_interaction_prompt().contains("CLIMB INTO VENT"), "no CLIMB INTO VENT prompt under a hatch (%s)" % player.get_interaction_prompt())
	player._try_interact()
	_expect(player.in_vent and player.vent_crawl != null and player.vent_crawl.inside(), "[E] under the hatch did not start the climb")
	var top := 0.0
	var biggest := 0.0
	for _i in 120:
		var before := player.global_position
		await host.get_tree().physics_frame
		top = maxf(top, player.global_position.y)
		biggest = maxf(biggest, Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length())
	_expect(player.vent_crawl.phase == VentCrawl.Phase.DUCT and absf(player.global_position.y - float(grate["duct_y"])) < .05,
		"the climb did not end in the duct (y %.2f, duct %.2f)" % [player.global_position.y, float(grate["duct_y"])])
	# crawl along the duct with the move key, then climb out back at the grate
	Input.action_press("move_up")
	for _i in 60:
		var before := player.global_position
		await host.get_tree().physics_frame
		biggest = maxf(biggest, Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length())
		_expect(player.vent_crawl.is_duct(Vector2(player.global_position.x, player.global_position.z)), "the player crawled out of the duct cells")
	Input.action_release("move_up")
	_expect(biggest <= VentCrawl.CRAWL_SPEED / 30.0 + .01, "a frame moved the player %.2f m in the vents" % biggest)
	player.vent_crawl.position = VentCrawl.grate_centre(grate)
	player._try_interact()
	for _i in 120:
		await host.get_tree().physics_frame
	_expect(not player.in_vent and not player.vent_crawl.inside() and player.global_position.y < 1.0,
		"climbing out did not land on the floor (y %.2f)" % player.global_position.y)
	# a Hard hunter routes through a much shorter duct (the brain's own pursue path)
	var hunter := HunterBrain.new(under + Vector2(.5, 0), "VENTS:HARD", "kathy", "hard")
	hunter.vent_nav = VentNav.new(player.vents)
	var far := VentNav.new(player.vents).grates_around(under, 0, 60.0)
	_expect(far.size() > 1, "only one grate near the spawn")
	scene.queue_free()
	await host.get_tree().process_frame
