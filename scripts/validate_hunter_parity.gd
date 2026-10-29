extends RefCounted

## Mechanics ported from the 2D game's hunter files (see docs/HUNTER_PARITY.md): the Void powers, the capture gates
## (non-lethal, hiding breach), and the per-hunter fixes. Runs on a real streamed navigation window.

const STEP := 1.0 / 30.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var generator := StreamedRouteGenerator.new("PARITY")
	var navigation := StreamedHunterNavigation.new(generator, 0)
	var coords := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			coords.append(Vector3i(dx, 0, dz))
	navigation.refresh(0, coords)
	var cells := navigation.floor_cells()
	var spot := _straight_run(navigation, cells)
	_expect(not spot.is_empty(), "no straight open run to stage the Void tests on")
	if spot.is_empty():
		return _failures
	var origin: Vector2 = spot["origin"]
	var along: Vector2 = spot["along"]

	_void_powers(navigation, origin, along)
	_capture_gates(navigation, origin, along)
	_ilyra_delay()
	_ceryth_and_briselle_hooks()
	if _failures == 0:
		print("  hunter_parity  void powers, capture gates, Ilyra delay, Ceryth/Briselle hooks")
	return _failures


## An open cell with at least 16 open cells straight along +x or +y, so line-of-sight tests have room.
func _straight_run(navigation: StreamedHunterNavigation, cells: Array) -> Dictionary:
	for cell_value in cells:
		var cell: Vector2i = cell_value
		for dir in [Vector2(1, 0), Vector2(0, 1)]:
			var ok := true
			for i in range(0, 17):
				var p: Vector2 = Vector2(cell) + Vector2(.5, .5) + dir * float(i)
				if not navigation.can_occupy(p.x, p.y, 0.3):
					ok = false
					break
			if ok:
				return {"origin": Vector2(cell) + Vector2(.5, .5), "along": dir}
	return {}


func _brain(id: String, at: Vector2) -> HunterBrain:
	var brain := HunterBrain.new(at, "PARITY-%s" % id, id, "standard")
	brain.activate_at(at)
	return brain


func _target(at: Vector2, facing: Vector2, extra: Dictionary = {}) -> Dictionary:
	var target := {"position": at, "hidden": false, "in_safe_zone": false, "noise": 0.0, "flashlight_on": true,
		"facing": facing, "lamp_charge": 100.0, "sprinting": false}
	target.merge(extra, true)
	return target


func _void_powers(navigation: StreamedHunterNavigation, origin: Vector2, along: Vector2) -> void:
	var hunter_at := origin + along * 8.0
	# Black: frozen while looked at, fast otherwise
	var black := _brain("void_black", hunter_at)
	_expect(black.gimmick is VoidBlackGimmick, "void_black has no gimmick")
	black.update(STEP, navigation, _target(origin, along), 1, 0)
	_expect(black.gimmick.speed_scale(black) == 0.0, "Black Void is not frozen by the player's gaze")
	black.update(STEP, navigation, _target(origin, -along), 1, 0)
	_expect(is_equal_approx(black.gimmick.speed_scale(black), 1.5), "Black Void is not fast when unwatched")
	# White: frozen by a lit beam, 1.35 in the dark
	var white := _brain("void_white", hunter_at)
	white.update(STEP, navigation, _target(origin, along), 1, 0)
	_expect(white.gimmick.speed_scale(white) == 0.0, "White Void is not frozen by the torch")
	white.update(STEP, navigation, _target(origin, along, {"flashlight_on": false}), 1, 0)
	_expect(is_equal_approx(white.gimmick.speed_scale(white), 1.35), "White Void is not faster in the dark")
	# Blue: hidden until the beam shoves her back
	var blue := _brain("void_blue", hunter_at)
	blue.update(STEP, navigation, _target(origin, -along, {"flashlight_on": false}), 1, 0)
	_expect(blue.gimmick.hidden_from_view(), "Blue Void should be invisible until lit")
	blue.update(STEP, navigation, _target(origin, along), 1, 0)
	_expect(not blue.gimmick.hidden_from_view(), "Blue Void was not revealed by the beam")
	_expect(blue.position.distance_to(hunter_at) > 1.0, "Blue Void was not pushed back by the beam")
	# Red: hallway fast, room slow (hallways are the open straight run here only if outside every room)
	var red := _brain("void_red", hunter_at)
	red.update(STEP, navigation, _target(origin, along), 1, 0)
	var scale: float = red.gimmick.speed_scale(red)
	_expect(is_equal_approx(scale, 1.55) or is_equal_approx(scale, 0.78), "Red Void speed scale %s is neither 1.55 nor 0.78" % scale)
	# Yellow: speed grows while the map is open
	var yellow := _brain("void_yellow", hunter_at)
	for _i in 60:
		yellow.update(STEP, navigation, _target(origin, along, {"map_open": true}), 1, 0)
	_expect(yellow.gimmick.speed_scale(yellow) > 1.1, "Yellow Void did not speed up while the map was open")
	# Green: submerges after her interval when far enough away
	# she submerges only from 14+ cells away (VoidGreenGimmick.MINIMUM_DISTANCE), so start her clear of that
	var green := _brain("void_green", origin + along * 15.5)
	var seen_submerged := false
	var green_start := green.position
	for _i in int(23.0 / STEP):
		green.update(STEP, navigation, _target(origin, along, {"hidden": true}), 1, 0)
		# the brain wanders by its own rules (and the geometry); the power is what is under test, so she stays far away
		if green.position.distance_to(origin) < VoidGreenGimmick.MINIMUM_DISTANCE and not (green.gimmick as VoidGreenGimmick).submerged > 0.0:
			green.position = green_start
		seen_submerged = seen_submerged or (green.gimmick as VoidGreenGimmick).submerged > 0.0
		if seen_submerged:
			break
	_expect(seen_submerged, "Green Void never submerged")
	# Pink never grabs
	_expect(_brain("void_pink", hunter_at).gimmick.immune_to_capture(), "Pink Void can capture")


func _capture_gates(navigation: StreamedHunterNavigation, origin: Vector2, along: Vector2) -> void:
	for id in ["ceryth", "glyra", "ilyra", "loxelle"]:
		var brain := _brain(id, origin + along * 2.0)
		_expect(brain.gimmick != null and brain.gimmick.immune_to_capture(), "%s can still capture" % id)
	# Ysolde (KT's ruling, docs/YSOLDE.md): she flees, but a runner who reaches her is caught
	_expect(not _brain("ysolde", origin + along * 2.0).gimmick.immune_to_capture(), "ysolde can no longer catch a runner who reaches her")
	# Elise breaches hiding: a hidden player within reach is grabbed once she is on the last known point
	var elise := _brain("elise", origin + along * 2.0)
	var hidden_target := _target(origin + along * 2.2, along, {"hidden": true})
	elise.has_last_known = true
	elise.last_known = hidden_target["position"]
	var caught := elise.update(STEP, navigation, hidden_target, 1, 0)
	_expect(elise.gimmick.breaches_hiding() and caught, "Elise did not grab a hidden player next to her last known point")
	var dovelle := _brain("dovelle", origin + along * 2.0)
	_expect(not dovelle.update(STEP, navigation, hidden_target, 1, 0), "an ordinary hunter grabbed a hidden player")
	# Verrine idle: invisible and harmless
	var verrine := _brain("verrine", origin + along * 2.0)
	_expect(verrine.gimmick.immune_to_capture(), "an idle Verrine can capture")


func _ilyra_delay() -> void:
	_expect(GameConfig.ILYRA_POUNCE_DELAY == 15.0, "Ilyra's pounce delay is not the 2D 15 s")
	_expect(is_equal_approx(IlyraGimmick.new().sight_scale(null), GameConfig.ILYRA_SIGHT_SCALE), "Ilyra's sight scale is missing")


func _ceryth_and_briselle_hooks() -> void:
	var ceryth := CerythGimmick.new()
	_expect(GameConfig.CERYTH_RETREAT_SPEED == 6.4 and GameConfig.CERYTH_MINIMUM_RETREAT == 7.0, "Ceryth retreat constants drifted from 2D")
	_expect(ceryth.holds_position() == false, "an unplaced Ceryth must not report a held position")
	_expect(GameConfig.BRISELLE_HUNT_SECONDS == 12.0 and GameConfig.BRISELLE_SPEED_SCALE == 1.25, "Briselle relay-tracker constants drifted from 2D")
