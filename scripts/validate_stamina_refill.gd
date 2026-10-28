extends RefCounted

## KT: "if stamina doesnt fully run out or super low it regenerates instantly". Stop sprinting above
## GameConfig.STAMINA_QUICK_THRESHOLD and stamina is full again within STAMINA_QUICK_REFILL_TIME; stop at or below it (or
## exhausted) and the slow delayed regen applies. The HUD bar and wrist read player.stamina, so they follow.
##
##   godot --headless --path . res://scenes/validate.tscn -- stamina_refill

const STEP := 1.0 / 60.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _sprint_to(player: PlayerController3D, target: float) -> void:
	player.stamina = GameConfig.MAX_STAMINA
	player.exhausted = false
	player.stamina_quick_refill = false
	while player.stamina > target:
		player._update_stamina(STEP, true)


func _rest(player: PlayerController3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		player._update_stamina(STEP, false)
		t += STEP


func run(_host: Node) -> int:
	var player := PlayerController3D.new()
	player.admin_god_mode = false
	_sprint_to(player, 50.0)
	_rest(player, GameConfig.STAMINA_QUICK_REFILL_TIME + STEP)
	_expect(is_equal_approx(player.stamina, GameConfig.MAX_STAMINA),
		"stopping at 50%% left stamina at %.1f after the quick refill" % player.stamina)
	_sprint_to(player, GameConfig.STAMINA_QUICK_THRESHOLD + 2.0)
	_rest(player, GameConfig.STAMINA_QUICK_REFILL_TIME + STEP)
	_expect(is_equal_approx(player.stamina, GameConfig.MAX_STAMINA), "stopping just above the threshold did not refill")
	_sprint_to(player, GameConfig.STAMINA_QUICK_THRESHOLD - 2.0)
	var low := player.stamina
	_rest(player, 1.0)
	_expect(player.stamina < 40.0 and player.stamina >= low,
		"stopping at %.1f refilled fast (%.1f after 1 s)" % [low, player.stamina])
	_rest(player, 6.0)
	_expect(is_equal_approx(player.stamina, GameConfig.MAX_STAMINA), "low stamina never recovered")
	_sprint_to(player, 0.0)
	_expect(player.exhausted, "draining to 0 did not exhaust")
	_rest(player, 1.0)
	_expect(player.exhausted and player.stamina < GameConfig.STAMINA_EXHAUSTED_RECOVERY,
		"an exhausted player refilled fast (%.1f)" % player.stamina)
	player.free()
	if _failures == 0:
		print("  stamina_refill  ok")
	return _failures
