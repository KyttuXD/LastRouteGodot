extends RefCounted

## Headless check on the generic hunter-facing player effects: forced
## flashlight flicker and the TV-static overlay. Neither is wired to a
## specific hunter yet -- this is the infrastructure, checked on its own.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- player_effects

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
	_static_overlay_fades()
	if _failures == 0:
		print("player_effects OK")
	return _failures


func _flicker_seizes_and_releases(host: Node) -> void:
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
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


func _static_overlay_fades() -> void:
	var overlay := StaticOverlay.new()
	# _ready() needs a tree to run in for @onready-style setup; StaticOverlay
	# has none, so it works standalone -- confirmed by using it that way here
	# rather than assuming.
	overlay._ready()
	_expect(overlay._material != null, "the overlay never built its shader material")
	overlay.trigger(1.0, 0.8)
	_expect(overlay.visible, "triggering static did not show the overlay")

	# What headless CAN actually verify: the envelope's own bookkeeping
	# (_remaining counting down, visibility clearing on schedule), not the
	# shader uniform it drives -- a dummy renderer with no GPU behind it
	# doesn't compile shaders, so reading the parameter back would be
	# checking Godot's rendering server, not this code.
	for i in 30:  # 0.5s -- comfortably mid-effect
		overlay._process(STEP)
	_expect(overlay.visible and overlay._remaining > 0.0,
		"static cleared itself well before its 1s duration was up")
	for i in 40:  # past the 1.0s duration
		overlay._process(STEP)
	_expect(not overlay.visible, "static stayed visible after its duration ran out")
	print("  static    triggers, runs its full duration, and clears itself on schedule")
	overlay.free()
