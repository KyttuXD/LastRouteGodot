extends RefCounted

## "i said instantly meaning no delay before stamina regeneration". Stamina starts regenerating the frame sprinting
## stops, at the normal GameConfig.STAMINA_RECOVERY rate: no pause first and no jump to full.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- stamina_regen

const STEP := 1.0 / 60.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _sprint_to(player: PlayerController3D, target: float) -> void:
	player.stamina = GameConfig.MAX_STAMINA
	player.exhausted = false
	while player.stamina > target:
		player._update_stamina(STEP, true)


func run(_host: Node) -> int:
	var player := PlayerController3D.new()
	player.admin_god_mode = false
	_expect(GameConfig.STAMINA_RECOVERY_DELAY == 0.0, "a post-sprint regen delay is still set")
	for target in [50.0, 10.0]:
		_sprint_to(player, target)
		var before := player.stamina
		player._update_stamina(STEP, false)
		var gain := player.stamina - before
		_expect(gain > 0.0, "no regen on the first frame after sprinting at %.0f" % target)
		_expect(is_equal_approx(gain, GameConfig.STAMINA_RECOVERY * STEP),
			"first-frame regen at %.0f was %.3f, not the normal rate" % [target, gain])
		var last := player.stamina
		for i in 30:
			player._update_stamina(STEP, false)
			_expect(player.stamina - last <= GameConfig.STAMINA_RECOVERY * STEP + 0.0001,
				"stamina jumped from %.1f to %.1f" % [last, player.stamina])
			last = player.stamina
		_expect(player.stamina < GameConfig.MAX_STAMINA, "stamina was full half a second after stopping at %.0f" % target)
	_sprint_to(player, 0.0)
	_expect(player.exhausted, "draining to 0 did not exhaust")
	player._update_stamina(STEP, false)
	_expect(player.stamina > 0.0, "exhausted stamina did not start regenerating at once")
	player.free()
	if _failures == 0:
		print("  stamina_regen  ok")
	return _failures
