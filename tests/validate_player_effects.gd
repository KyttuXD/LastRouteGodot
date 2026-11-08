extends RefCounted

## Headless check on the generic hunter-facing flashlight flicker.
##
## Run with:
##   godot4 --headless res://tests/scenes/validate.tscn -- player_effects

const STEP := 1.0 / 60.0

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	await _flicker_seizes_and_releases(host)
	await _thermal_warnings_replace_meter(host)
	if _failures == 0:
		print("player_effects OK")
	return _failures


func _flicker_seizes_and_releases(host: Node) -> void:
	var scene: Node = load("res://game/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
	player.grant_inventory_item("flashlight")
	player._set_flashlight(true)
	var was_on := player.flashlight_enabled

	player.force_flashlight_flicker(1.0, 0.02, 0.02)
	_expect(player.flashlight_seized(), "forcing a flicker did not seize the flashlight")

	# [F], for real, through the actual input path -- not an assertion about
	# flashlight_seized() in isolation, which would just be re-stating the
	# guard rather than proving it holds.
	var before_manual := player.flashlight_enabled
	Input.action_press("flashlight")
	player._physics_process(STEP)
	Input.action_release("flashlight")
	_expect(player.flashlight_enabled == before_manual,
		"[F] changed the player's real flashlight preference while a hunter had it seized")

	var toggled := false
	var initial_visible := player.flashlight.visible
	for i in 90:  # 1.5s at 60fps -- past the 1.0s flicker duration
		player._update_flashlight_flicker(STEP)
		if player.flashlight.visible != initial_visible:
			toggled = true
	_expect(toggled, "a flickering flashlight never actually changed visibility")
	_expect(not player.flashlight_seized(), "the flicker never released the flashlight")
	_expect(player.flashlight.visible == was_on,
		"releasing the flicker left the beam somewhere other than its real state")

	print("  flicker   seizes the beam, forces it to change, releases back to the real state")
	scene.queue_free()
	await host.get_tree().process_frame


func _thermal_warnings_replace_meter(host: Node) -> void:
	var scene: Node = load("res://game/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var hud: HUD = scene.hud
	var meters := PlayerMeters.new()
	meters.temperature = 60.0
	hud.update_meters(meters, .82, 0.0)
	var strengths := hud.thermal_effect_strengths()
	_expect(absf(strengths.x - .82) < .01 and strengths.y < .01,
		"Solyth proximity did not render the warm-yellow heat warning")
	hud.update_meters(meters, 0.0, .76)
	strengths = hud.thermal_effect_strengths()
	_expect(strengths.x < .01 and absf(strengths.y - .76) < .01,
		"Wynelle proximity did not render the white frost warning")
	_expect(hud.find_child("TemperatureMeter", true, false) == null,
		"the obsolete temperature bar is still present beside the screen effects")
	print("  thermal   restrained yellow heat and white frost replace the temperature bar")
	scene.queue_free()
	await host.get_tree().process_frame
