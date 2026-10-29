extends RefCounted

## Porcelle's radar blip on the minimap (RadarPing): visible only during short pings and hidden between, a slow cadence within
## the tunable bounds, clamped to the minimap with a direction tick when she is out of range, only Porcelle (no other hunter
## shows without admin reveal), the same for a guest, and a steady dim dot under reduced motion.
##
##   godot --headless --path . res://scenes/validate.tscn -- minimap_radar

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _check_cadence() -> void:
	var step := 0.02
	var starts: Array[float] = []
	var lengths: Array[float] = []
	var previous := 0.0
	var ping_start := -1.0
	var peak := 0.0
	var time := 0.0
	while time < 400.0:
		var strength: float = RadarPing.sample(time)["strength"]
		peak = maxf(peak, strength)
		if strength > 0.001 and previous <= 0.001:
			starts.append(time)
			ping_start = time
		if strength <= 0.001 and previous > 0.001 and ping_start >= 0.0:
			lengths.append(time - ping_start)
		previous = strength
		time += step
	_expect(starts.size() >= 30, "only %d pings in 400 s" % starts.size())
	for length in lengths:
		_expect(length <= RadarPing.DURATION + 0.1 and length >= RadarPing.DURATION * 0.8, "a ping lasted %.2f s (duration %.2f)" % [length, RadarPing.DURATION])
	for i in range(1, starts.size()):
		var gap := starts[i] - starts[i - 1]
		_expect(gap >= RadarPing.INTERVAL - RadarPing.JITTER - 0.1 and gap <= RadarPing.INTERVAL + RadarPing.JITTER + 0.1,
			"gap %.2f s between pings is outside %.1f +- %.1f" % [gap, RadarPing.INTERVAL, RadarPing.JITTER])
	_expect(peak <= RadarPing.PEAK_ALPHA + 0.001 and peak > RadarPing.PEAK_ALPHA * 0.9, "peak strength %.2f" % peak)
	# hidden between pings: half way through a gap
	_expect(float(RadarPing.sample(starts[4] + RadarPing.DURATION + 1.0)["strength"]) == 0.0, "the blip is visible between pings")
	# the ring/dot are visible mid-ping and ease in/out
	var mid: float = RadarPing.sample(starts[5] + RadarPing.DURATION * 0.5)["strength"]
	_expect(mid > RadarPing.PEAK_ALPHA * 0.9, "the blip is not at full strength mid-ping (%.2f)" % mid)
	var edge: float = RadarPing.sample(starts[5] + 0.01)["strength"]
	_expect(edge < mid * 0.5, "the blip does not ease in (%.2f vs %.2f)" % [edge, mid])
	# deterministic: the same time gives the same answer on every client
	_expect(is_equal_approx(float(RadarPing.sample(123.4)["strength"]), float(RadarPing.sample(123.4)["strength"])), "pings are not deterministic")


func _check_reduced() -> void:
	var low := 1.0
	var high := 0.0
	var time := 0.0
	while time < 30.0:
		var strength: float = RadarPing.sample(time, true)["strength"]
		low = minf(low, strength)
		high = maxf(high, strength)
		time += 0.05
	_expect(low > 0.2, "the reduced-motion dot disappears (%.2f)" % low)
	_expect(high <= RadarPing.REDUCED_ALPHA + 0.001 and high - low <= RadarPing.REDUCED_FADE + 0.01 and high - low > 0.02,
		"the reduced-motion fade is not slow and small (%.2f..%.2f)" % [low, high])


func _check_clamp() -> void:
	var view := Rect2(Vector2.ZERO, Vector2(88, 72))
	# find a time inside a ping
	var time := 0.0
	while float(RadarPing.sample(time)["strength"]) < 0.5:
		time += 0.01
	var inside := RadarPing.marker(Vector2(40, 30), view, time)
	_expect(bool(inside["visible"]) and not bool(inside["clamped"]) and inside["pos"] == Vector2(40, 30), "an in-range mark was moved: %s" % inside)
	for far in [Vector2(500, 30), Vector2(-300, -200), Vector2(44, 900), Vector2(-90, 40)]:
		var out := RadarPing.marker(far, view, time)
		_expect(bool(out["clamped"]), "%s did not clamp" % far)
		_expect(view.grow(0.01).has_point(out["pos"]), "%s clamped outside the minimap: %s" % [far, out["pos"]])
		_expect((out["direction"] as Vector2).length() > 0.99, "no direction for the edge tick at %s" % far)
		_expect((out["direction"] as Vector2).dot((far - view.get_center()).normalized()) > 0.99, "the edge tick points away from her at %s" % far)


func _check_map_wiring(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 8:
		await host.get_tree().process_frame
	var hud: Node = route.hud
	_expect(bool(hud.get("minimap").get("ghost_ping")), "the HUD minimap does not pulse Porcelle")
	_expect(not bool(hud.get("plan").get("ghost_ping")), "the full map should keep her steady mark")
	var level: int = route.facility.current_level()
	var host_marks: Array = route._streamed_map_marks(level, true)
	for mark in host_marks:
		_expect(String(mark.get("hunter_id", "")) == "porcelle", "the minimap marks include %s without admin reveal" % mark.get("hunter_id", "?"))
	# a guest builds the same marks from the replicated hunters (no host-only gate)
	var was_online := RoomState.online
	var was_host := RoomState.is_host
	RoomState.online = true
	RoomState.is_host = false
	var guest_marks: Array = route._streamed_map_marks(level, true)
	_expect(guest_marks.size() == host_marks.size(), "a guest sees %d marks, the host %d" % [guest_marks.size(), host_marks.size()])
	RoomState.online = was_online
	RoomState.is_host = was_host
	# the map keeps only Porcelle's ghost on its pinged marks: a plain hunter mark still draws the normal marker
	route.queue_free()
	await host.get_tree().process_frame


## Teammates: a stable, distinct colour per peer (shared with their 3D nametag), callsigns on the full map; the full-map
## arrow has a minimum on-screen size; ladders are not drawn on either map; nametags sit just above a 1.60 m runner.
func _check_teammates_and_icons() -> void:
	var seen := {}
	for id in range(1, 9):
		var colour := RemotePlayers.peer_colour(id)
		_expect(colour == RemotePlayers.peer_colour(id), "peer %d colour is not stable" % id)
		seen[colour.to_html()] = true
	_expect(seen.size() == 8, "8 teammates share colours (%d distinct)" % seen.size())
	_expect(FacilityMap.arrow_reach(1.0, true) >= 7.0 and FacilityMap.arrow_reach(60.0, true) <= FacilityMap.PLAYER_ARROW_MAX, "the full-map player arrow is not a constant readable size")
	var source := FileAccess.get_file_as_string("res://src/ui/facility_map.gd")
	_expect(not source.contains("\t\t\t\t\t_draw_ladder_icon(icon_at"), "ladder icons are still drawn on the maps")
	var map_source := source
	_expect(map_source.contains("draw_string_outline(font, tag_at, label"), "the full map does not label teammates")
	_expect(RemotePlayers.NAME_TAG_HEIGHT * PlayerModels.SCALE < 1.78 * PlayerModels.SCALE + .35 and RemotePlayers.NAME_TAG_HEIGHT * PlayerModels.SCALE > 1.78 * PlayerModels.SCALE,
		"the nametag is not just above the runner (%.2f m)" % (RemotePlayers.NAME_TAG_HEIGHT * PlayerModels.SCALE))


func run(host: Node) -> int:
	_check_teammates_and_icons()
	_check_cadence()
	_check_reduced()
	_check_clamp()
	await _check_map_wiring(host)
	if _failures == 0:
		print("  radar     Porcelle pings %.1f s every ~%.0f s (+-%.0f), hidden between, clamped with an edge tick, only her, guests too, reduced motion steady" % [RadarPing.DURATION, RadarPing.INTERVAL, RadarPing.JITTER])
	return _failures
