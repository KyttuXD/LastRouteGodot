extends RefCounted

## Headless check for the hunter presentation (the 2D billboard cutouts are retired; the suite name
## "sprites" is kept so validate_runner.gd stays unchanged).
##
## Every A-Z and Void hunter must present its blocky 3D model, and the Kathy scythe roll must be
## deterministic per spawn seed.
##
## Run with:
##   godot4 --headless res://tests/scenes/validate.tscn -- sprites

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	# What the game actually shows: the blocky 3D model for every A-Z and Void hunter.
	var shown := []
	shown.append_array(HunterRoster.A_Z_IDS)
	shown.append_array(HunterRoster.VOID_IDS)
	for id in shown:
		var identity := HunterRoster.get_identity(id)
		var presented := ModelSlot.instantiate_hunter(identity)
		if presented == null:
			_fail("%s produced no presentation" % id)
			continue
		if not String(identity["model_scene"]).begins_with(HunterRoster.BLOCKY_DIR):
			_fail("%s does not use its blocky model: %s" % [id, identity["model_scene"]])
		presented.queue_free()
	# Scythe carrying is a rare, deterministic roll per spawn seed (same answer on every peer).
	var armed := 0
	for i in 800:
		var seed_text := "SCYTHE-CHECK:%d" % i
		var first := HunterRoster.carries_scythe(seed_text)
		if first != HunterRoster.carries_scythe(seed_text):
			_fail("scythe roll for %s is not deterministic" % seed_text)
		if first:
			armed += 1
	if armed < 60 or armed > 150:
		_fail("%d of 800 Kathys carry the scythe; expected about %d" % [armed, int(800 * HunterRoster.SCYTHE_CARRY_CHANCE)])
	if HunterRoster.carries_scythe(""):
		_fail("an unseeded hunter should never carry the scythe")
	print("  %d A-Z hunters checked; scythe on %d/800 seeds" % [HunterRoster.A_Z_IDS.size(), armed])
	return _failures
