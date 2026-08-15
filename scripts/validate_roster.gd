extends RefCounted

## Headless check on the hunter roster.
##
## The draw is the part that fails quietly. A weighted pick with a tier nobody
## has implemented, or a hunter listed but unreachable, produces a game that
## runs perfectly and just never shows you half its cast -- and the only symptom
## is a feeling that you keep meeting the same hunter.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- roster

const SEEDS := 600

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(_host: Node) -> int:
	_everyone_has_a_face()
	_the_pool_is_real()
	_the_draw_is_replayable()
	_the_draw_reaches_everyone()
	_the_draw_respects_its_tiers()
	_umbriel_can_wear_the_roster()
	if _failures == 0:
		print("roster OK")
	return _failures


func _everyone_has_a_face() -> void:
	var missing: Array[String] = []
	for id in HunterRoster.PROFILES:
		var identity := HunterRoster.get_identity(id)
		if not ResourceLoader.exists(identity["model_scene"]):
			missing.append(id)
		_expect(String(identity["display_name"]) != "",
			"%s has no display name" % id)
		_expect(float(identity["chase_speed"]) > float(identity["base_speed"]),
			"%s chases slower than she walks" % id)
	_expect(missing.is_empty(), "no model for: %s" % ", ".join(missing))
	print("  profiles  %d hunters, each with tuning and a model"
		% HunterRoster.PROFILES.size())


## An id in the pool with no profile falls back to Dovelle's numbers and her
## model, so she would be Dovelle wearing a different name -- silently.
func _the_pool_is_real() -> void:
	for id in HunterRoster.IMPLEMENTED_IDS + HunterRoster.SPECIAL_IDS:
		if not HunterRoster.PROFILES.has(id):
			_fail("'%s' is drawn but has no profile" % id)
	for id in HunterRoster.SPECIAL_IDS:
		_expect(not HunterRoster.IMPLEMENTED_IDS.has(id),
			"%s is a special and must never be in the ordinary draw" % id)
		_expect(HunterGimmick.for_id(id) != null,
			"%s is summoned by a rule but has no gimmick to decide it" % id)

	# Every drawn hunter resolves a gimmick, except the two whose difference
	# really is only tuning. Without this, a gimmick that fails to compile --
	# a new class_name before an import pass registers it -- leaves for_id()
	# returning null for everyone, and the whole roster quietly plays Dovelle.
	const TUNING_ONLY := ["dovelle", "thessine"]
	var missing: Array[String] = []
	for id in HunterRoster.IMPLEMENTED_IDS:
		var has_gimmick := HunterGimmick.for_id(id) != null
		if TUNING_ONLY.has(id):
			_expect(not has_gimmick,
				"%s is listed as tuning-only but resolves a gimmick" % id)
		elif not has_gimmick:
			missing.append(id)
	_expect(missing.is_empty(),
		"drawn but plays as Dovelle -- no gimmick resolved: %s" % ", ".join(missing))


func _the_draw_is_replayable() -> void:
	for depth in [1, 2, 7]:
		var once := HunterRoster.pick_for_floor("SEED-A", depth)
		_expect(once == HunterRoster.pick_for_floor("SEED-A", depth),
			"the draw is not stable for one seed at depth %d" % depth)
	var by_depth := {}
	for depth in range(1, 25):
		by_depth[HunterRoster.pick_for_floor("SEED-A", depth)] = true
	_expect(by_depth.size() > 1, "one seed draws the same hunter at every depth")


## Every implemented hunter has to be reachable. A tier whose weight rounds it
## out of the draw is the failure this catches.
func _the_draw_reaches_everyone() -> void:
	var seen := {}
	for i in SEEDS:
		seen[HunterRoster.pick_for_floor("SEED-%d" % i, 1 + i % 5)] = true
	var unreachable: Array[String] = []
	for id in HunterRoster.IMPLEMENTED_IDS:
		if not seen.has(id):
			unreachable.append(id)
	_expect(unreachable.is_empty(),
		"never drawn across %d seeds: %s" % [SEEDS, ", ".join(unreachable)])
	for id in seen:
		_expect(HunterRoster.IMPLEMENTED_IDS.has(id),
			"the draw returned '%s', who is not in the pool" % id)


## The weights are over tiers, and a tier with nobody in it drops out and the
## rest renormalise. Without that, "difficult" -- the smallest share in the
## original -- takes whatever an empty tier leaves behind.
func _the_draw_respects_its_tiers() -> void:
	var present := {}
	for id in HunterRoster.IMPLEMENTED_IDS:
		present[HunterRoster.PROFILES[id]["tier"]] = true
	var total := 0.0
	for tier in present:
		total += float(HunterRoster.TIER_WEIGHTS.get(tier, 0.0))

	var counted := {}
	for i in SEEDS:
		var tier: String = HunterRoster.PROFILES[
			HunterRoster.pick_for_floor("TIER-%d" % i, 1)]["tier"]
		counted[tier] = int(counted.get(tier, 0)) + 1

	var report: Array[String] = []
	for tier in present:
		var want: float = float(HunterRoster.TIER_WEIGHTS.get(tier, 0.0)) / total
		var got := float(counted.get(tier, 0)) / float(SEEDS)
		report.append("%s %.0f%%" % [tier, got * 100.0])
		# Wide, because this is a check on the weighting being APPLIED, not on
		# the quality of the RNG. A tier landing at half or double its share is
		# a bug in the draw; a few points either way is a sample.
		_expect(absf(got - want) < 0.10,
			"%s hunters are drawn %.0f%% of the time, not the %.0f%% their tier weight asks for"
				% [tier, got * 100.0, want * 100.0])
	report.sort()
	print("  draw      %s across %d seeds" % [", ".join(report), SEEDS])


func _umbriel_can_wear_the_roster() -> void:
	var pool := HunterRoster.disguise_ids(GameConfig.UMBRIEL_DISGUISE_EXCLUDED)
	_expect(not pool.has("umbriel"), "Umbriel can disguise as herself")
	for id in HunterRoster.SPECIAL_IDS:
		_expect(not pool.has(id), "Umbriel can wear %s, who is a special" % id)
	for id in GameConfig.UMBRIEL_DISGUISE_EXCLUDED:
		_expect(not pool.has(id), "Umbriel can wear %s, who is excluded" % id)
	# The point of drawing from the roster rather than the implemented pool.
	_expect(pool.size() > HunterRoster.IMPLEMENTED_IDS.size(),
		"Umbriel's disguises (%d) are no wider than the implemented pool (%d), so she is a progress bar"
			% [pool.size(), HunterRoster.IMPLEMENTED_IDS.size()])
	print("  disguise  %d faces Umbriel can wear" % pool.size())
