extends RefCounted

## "I fell through the map underneath the inferno region." Nothing exists under the Inferno (level -3 is the lowest storey, the
## view clamps its level there, and the runner had no kill plane), so any cell she can step into that has no ground is a fall with
## no end. The cell was the pocket under every collector ramp's slope on the Inferno storey: the grid keeps the slope solid, the
## view built no floor and no wall collider there (the only collider is the slab on the level -2 chunk, and the walls
## _close_ramp_sides draws are paint), and cave tunnels run along the slope's sides and head.
##
## This suite pins the three layers of the fix:
##   1. the scan (tests/validate_inferno_floor.gd, two seeds, 7x7 chunks, plus its dormant check): every Inferno ramp pocket is
##      closed (no cell a runner can slide into has no ground) and the ramp slab stays in the physics world while parked;
##   2. WorldBottomNet, the bookkeeping behind the safety net: remembers the last floor, fires only under the lowest floor, never
##      for noclip / spectating, debounced, falls back to the spawn when she never stood anywhere;
##   3. the net in the real route: remove the floor under a standing Inferno runner (the chunk is unloaded, the stream never
##      rebuilds an unchanged chunk) and she is set back on her feet, with the route's message, instead of falling for good.
##
## Needs res://tests/validate_inferno_floor.gd (the pocket scan, kept as its own file so it can also run wider by hand).

const FloorScan := preload("res://tests/validate_inferno_floor.gd")
const NET_PATH := "res://game/world/streaming/world_bottom_net.gd"
const SEEDS := ["STREAM-BENCH", "REFLOOK"]
const SCAN_RADIUS := 3
const FLOOR_Y := -12.0

var _failures := 0
var _recovered: Array = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var scan = FloorScan.new()
	for seed_text in SEEDS:
		await scan._scan_seed(host, seed_text, StreamedRouteGenerator.INFERNO_LEVEL, SCAN_RADIUS)
	await scan._dormant_check(host, SEEDS[0])
	_failures += int(scan._failures)
	_net_bookkeeping()
	await _net_in_route(host, SEEDS[0])
	if _failures == 0:
		print("inferno_ramp OK")
	return _failures


## ------------------------------------------------------------------ WorldBottomNet

func _net_bookkeeping() -> void:
	if not ResourceLoader.exists(NET_PATH):
		_expect(false, "no world-bottom net (%s): a runner who loses her ground under the Inferno falls for good" % NET_PATH)
		return
	var net = load(NET_PATH).new()
	var bottom: float = net.bottom_y()
	_expect(is_equal_approx(bottom, -15.0), "the bottom is the Inferno floor (-12) minus the margin, got %.2f" % bottom)
	var here := Vector3(10, -12, 20)
	# standing: remembered after the refresh interval, never fires
	var fired := false
	for _i in 30:
		fired = fired or net.tick(1.0 / 60.0, here, true, true, false)
	_expect(not fired, "the net fired on a runner standing on the Inferno floor")
	_expect(net.last_safe.is_equal_approx(here), "the standing place was not remembered: %s" % net.last_safe)
	# in the air, on an unbuilt chunk: not a safe place
	net.tick(1.0, Vector3(99, -12, 99), false, true, false)
	net.tick(1.0, Vector3(98, -12, 98), true, false, false)
	_expect(net.last_safe.is_equal_approx(here), "an airborne or unbuilt-chunk spot was remembered as safe")
	# falling: debounced, then fires once, naming the last floor
	var fall := Vector3(10, bottom + .5, 20)
	_expect(not net.tick(.1, fall, false, true, false), "above the bottom must not count")
	fall.y = bottom - 1.0
	_expect(not net.tick(.1, fall, false, false, false), "one short step under the bottom fired at once (no debounce)")
	_expect(net.tick(.3, fall, false, false, false), "a runner under the bottom for the hold time was not caught")
	_expect(net.recoveries == 1, "recoveries not counted")
	_expect(not net.tick(.1, fall, false, false, false), "the net fired again straight after acting")
	# coming back above resets the debounce
	net.tick(.2, fall, false, false, false)
	net.tick(.05, Vector3(10, -12, 20), true, true, false)
	_expect(not net.tick(.2, fall, false, false, false), "the debounce survived a trip back above the bottom")
	# exempt (noclip / spectator): never
	var exempt_fired := false
	for _i in 120:
		exempt_fired = exempt_fired or net.tick(.1, fall, false, false, true)
	_expect(not exempt_fired, "the net fought a noclip / spectating camera under the world")
	# never stood anywhere: still fires (the caller falls back to the spawn), last_safe stays unset
	var fresh = load(NET_PATH).new()
	_expect(fresh.tick(.5, Vector3(0, -40, 0), false, false, false), "a runner who never stood anywhere is not caught")
	_expect(not fresh.last_safe.is_finite(), "last_safe should be unset for a runner who never stood anywhere")
	# real floors are all above the bottom (no legitimate position trips it)
	_expect(float(StreamedRouteGenerator.INFERNO_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT - SewerRouteGenerator.CHANNEL_DEPTH > bottom,
		"a sewer channel trench is below the bottom")


## ------------------------------------------------------------------ the net, in the real route

func _on_recovered(at: Vector3, fell_from: float) -> void:
	_recovered.append([at, fell_from])


func _net_in_route(host: Node, seed_text: String) -> void:
	if not ResourceLoader.exists(NET_PATH):
		_expect(false, "no world-bottom net: nothing catches a runner who falls out of the Inferno (route check skipped)")
		return
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = seed_text
	var scene: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	var facility: StreamedFacilityView3D = scene.get_node("%StreamedFacility")
	var player: PlayerController3D = scene.get_node("%Player")
	for _i in 900:
		await host.get_tree().physics_frame
		if scene.get("_start_gate") == null:
			break
	if scene.get("_start_gate") != null:
		_expect(false, "the route's start gate never opened")
		scene.queue_free()
		return
	player.admin_god_mode = true
	facility.connect("runner_recovered", Callable(self, "_on_recovered"))
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var spot := InfernoCaverns.landing(facility.generator.chunk(Vector3i(0, StreamedRouteGenerator.INFERNO_LEVEL, 0)))
	# stand on plain Inferno floor a few cells off the landing pile, wait for the stream and the settle
	var stood := false
	for step in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
		scene._admin_teleport_to(Vector3(spot.x + step.x + .5, FLOOR_Y + .05, spot.y + step.y + .5))
		for _i in 3000:
			await host.get_tree().physics_frame
			if not facility.is_streaming():
				break
		for _i in 90:    # long enough for the net to remember the place (0.25 s)
			await host.get_tree().physics_frame
		if player.is_on_floor() and absf(player.global_position.y - FLOOR_Y) < .2:
			stood = true
			break
	_expect(stood, "could not stand the runner on the Inferno floor to test the net (y %.2f)" % player.global_position.y)
	if stood:
		var standing := player.global_position
		var under := Vector3i(floori(standing.x / size), StreamedRouteGenerator.INFERNO_LEVEL, floori(standing.z / size))
		_recovered.clear()
		# the floor goes: unloaded, and the stream never rebuilds a chunk it believes is current
		facility._unload_chunk(under)
		if facility._dormant.has(under):
			facility._free_dormant(under)
		var lowest := standing.y
		for _i in 400:
			await host.get_tree().physics_frame
			lowest = minf(lowest, player.global_position.y)
		print("  inferno_ramp net: floor removed at %s, lowest y %.2f, now y %.2f, on floor %s, recovered %s" % [
			standing, lowest, player.global_position.y, player.is_on_floor(), _recovered.size()])
		_expect(_recovered.size() == 1, "the net acted %d times (want once)" % _recovered.size())
		_expect(player.is_on_floor() and absf(player.global_position.y - FLOOR_Y) < .3,
			"the runner is not back on the Inferno floor: y %.2f, on floor %s (fell to %.2f)" % [player.global_position.y, player.is_on_floor(), lowest])
		_expect(lowest > -30.0, "she fell %.1f m under the Inferno floor before anything caught her" % (FLOOR_Y - lowest))
		_expect(Vector2(player.global_position.x - standing.x, player.global_position.z - standing.z).length() < 1.0,
			"she was set back %.1f m from where she stood" % Vector2(player.global_position.x - standing.x, player.global_position.z - standing.z).length())
	scene.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
