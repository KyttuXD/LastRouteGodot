extends RefCounted

## Device quality tiers and the live governor (src/game/quality_tier.gd, src/look/quality_governor.gd):
##   - mocked machines land on the expected tier, and ULTRA is exactly the pre-tier desktop budget,
##   - a sustained missed frame target steps down one notch at a time, a sustained margin steps back up,
##   - frame times hovering at the threshold, or alternating fast/slow, do not make it flicker.
##
##   godot --headless --path . res://scenes/validate.tscn -- quality_tiers

const GB := 1_000_000_000

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _tiers() -> void:
	var machines := [
		{"name": "gaming desktop (RTX, 16 cores, 32 GB)", "specs": {"cores": 16, "ram_bytes": 32 * GB, "adapter": "NVIDIA GeForce RTX 4070", "refresh": 144.0}, "tier": QualityTier.Tier.ULTRA},
		{"name": "Mac mini M4 (10 cores, 16 GB)", "specs": {"cores": 10, "ram_bytes": 16 * GB, "adapter": "Apple M4", "refresh": 60.0}, "tier": QualityTier.Tier.ULTRA},
		{"name": "MacBook Air M1 (8 cores, 8 GB)", "specs": {"cores": 8, "ram_bytes": 8 * GB, "adapter": "Apple M1", "refresh": 60.0}, "tier": QualityTier.Tier.HIGH},
		{"name": "AMD APU laptop (16 threads, 16 GB)", "specs": {"cores": 16, "ram_bytes": 16 * GB, "adapter": "AMD Radeon(TM) Graphics", "refresh": 60.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "old Intel laptop (4 threads, 8 GB)", "specs": {"cores": 4, "ram_bytes": 8 * GB, "adapter": "Intel(R) UHD Graphics 620", "refresh": 60.0}, "tier": QualityTier.Tier.LOW},
		{"name": "iPhone 16 Pro (6 cores, 8 GB)", "specs": {"cores": 6, "ram_bytes": 8 * GB, "adapter": "Apple A18 Pro GPU", "phone": true, "refresh": 120.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "Galaxy S24 FE (8 cores, 8 GB)", "specs": {"cores": 8, "ram_bytes": 8 * GB, "adapter": "Mali-G715", "phone": true, "refresh": 120.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "budget phone (8 cores, 4 GB)", "specs": {"cores": 8, "ram_bytes": 4 * GB, "adapter": "Adreno (TM) 610", "phone": true}, "tier": QualityTier.Tier.LOW},
		{"name": "Quest 3S", "specs": {"cores": 6, "ram_bytes": 8 * GB, "adapter": "Adreno (TM) 740", "quest": true, "xr": true}, "tier": QualityTier.Tier.LOW},
		{"name": "GL renderer reporting discrete", "specs": {"cores": 8, "ram_bytes": 16 * GB, "adapter": "Some GPU", "discrete": true}, "tier": QualityTier.Tier.ULTRA},
	]
	for machine in machines:
		var got := QualityTier.score(machine["specs"])
		_expect(got == int(machine["tier"]), "%s scored %s, expected %s" % [machine["name"], QualityTier.name_of(got), QualityTier.name_of(machine["tier"])])
	var ultra := QualityTier.budgets(QualityTier.Tier.ULTRA, {"cores": 16, "ram_bytes": 32 * GB})
	_expect(int(ultra["lamp_pool"]) == 8 and float(ultra["camera_far"]) == 0.0 and bool(ultra["prebuild_linked_levels"])
		and bool(ultra["shadows"]) and float(ultra["prop_range_scale"]) == 1.0 and float(ultra["stream_budget_ms"]) == 4.0
		and float(ultra["stream_budget_max_ms"]) == 9.0, "ULTRA is not the pre-tier desktop budget: %s" % str(ultra))
	var quest := QualityTier.budgets(QualityTier.Tier.LOW, {"quest": true})
	_expect(float(quest["frame_target_hz"]) == 72.0 and float(quest["camera_far"]) == 60.0, "the Quest does not target a fixed 72 Hz with its 60 m far plane")
	_expect(float(QualityTier.budgets(QualityTier.Tier.ULTRA, {"refresh": 144.0})["frame_target_hz"]) == 60.0,
		"a 144 Hz desktop defends more than 60 fps (it would shed quality it does not need to)")
	# the flashlight's wall/prop shadows are core to the horror: on for every desktop tier but LOW, off on phones and the Quest
	for tier in [QualityTier.Tier.ULTRA, QualityTier.Tier.HIGH, QualityTier.Tier.MEDIUM]:
		_expect(bool(QualityTier.budgets(tier, {"cores": 8, "ram_bytes": 16 * GB})["shadows"]), "desktop %s drops the flashlight shadows" % QualityTier.name_of(tier))
	_expect(not bool(QualityTier.budgets(QualityTier.Tier.LOW, {})["shadows"]), "LOW keeps shadows")
	_expect(not bool(QualityTier.budgets(QualityTier.Tier.MEDIUM, {"phone": true})["shadows"]), "a phone keeps shadows")
	_expect(not bool(quest["shadows"]), "the Quest keeps shadows")
	var previous := -1.0
	for tier in [QualityTier.Tier.ULTRA, QualityTier.Tier.HIGH, QualityTier.Tier.MEDIUM, QualityTier.Tier.LOW]:
		var b := QualityTier.budgets(tier, {"cores": 8, "ram_bytes": 16 * GB})
		_expect(previous < 0.0 or float(b["stream_budget_ms"]) <= previous, "tier %s streams more per frame than the tier above" % QualityTier.name_of(tier))
		previous = float(b["stream_budget_ms"])


func _run(governor: QualityGovernor, ms: float, seconds: float) -> Array:
	var changes := []
	var t := 0.0
	while t < seconds:
		var change := governor.feed(ms)
		if change != 0:
			changes.append({"t": t, "change": change, "notch": governor.notch})
		t += ms / 1000.0
	return changes


func _governor() -> void:
	var gov := QualityGovernor.new()
	gov.target_ms = 1000.0 / 60.0
	# 30 fps for 20 s: steps down, one notch per cooldown, never past MAX_NOTCH
	var down := _run(gov, 33.3, 20.0)
	_expect(not down.is_empty() and down[0]["change"] == 1, "missing the target for 20 s did not step down")
	_expect(down.size() >= 2 and float(down[0]["t"]) >= QualityGovernor.MISS_SECONDS - .1, "stepped down before %.0f s of misses" % QualityGovernor.MISS_SECONDS)
	for i in range(1, down.size()):
		_expect(float(down[i]["t"]) - float(down[i - 1]["t"]) >= QualityGovernor.DOWN_COOLDOWN - .05, "two step-downs within the cooldown")
	_expect(gov.notch <= QualityGovernor.MAX_NOTCH, "notch past the maximum")
	var low_notch := gov.notch
	# then 120 fps: no step up during the hold, then one notch per sustained margin
	var up := _run(gov, 8.3, 80.0).filter(func(c: Dictionary) -> bool: return c["change"] == -1)
	_expect(not up.is_empty() and float(up[0]["t"]) >= QualityGovernor.MARGIN_SECONDS - .1, "stepped back up without a sustained margin")
	_expect(gov.notch < low_notch, "a sustained margin never stepped back up")
	# hovering just above the miss threshold and just below the margin threshold: no oscillation
	var steady := QualityGovernor.new()
	steady.target_ms = 1000.0 / 60.0
	var edge := _run(steady, 1000.0 / 60.0 * 1.05, 60.0)   # 5 % over target: inside the dead band
	_expect(edge.is_empty(), "frame times inside the dead band changed quality %d times" % edge.size())
	# alternating 2 s slow / 2 s fast for two minutes: at most one change per direction per hold, no flicker
	var flick := QualityGovernor.new()
	flick.target_ms = 1000.0 / 60.0
	var flips := 0
	var last_change := 0
	for cycle in 30:
		for change in _run(flick, 40.0, 2.0) + _run(flick, 8.0, 2.0):
			if last_change != 0 and change["change"] != last_change:
				flips += 1
			last_change = change["change"]
	_expect(flips <= 2, "alternating slow/fast frames flipped quality direction %d times in two minutes" % flips)
	var degraded := QualityGovernor.degrade(QualityTier.budgets(QualityTier.Tier.ULTRA, {}), 2)
	_expect(float(degraded["camera_far"]) > 0.0 and not bool(degraded["shadows"]), "the first notches are not draw distance then shadows")
	print("  quality_tiers  20 s at 30 fps -> notch %d in %d steps; margin brought it back to %d; dead band 0 changes; %d direction flips" % [
		low_notch, down.size(), gov.notch, flips])
	gov.free()
	steady.free()
	flick.free()


func run(_host: Node) -> int:
	_tiers()
	_governor()
	print("  quality_tiers  this machine: %s -> %s" % [QualityTier.describe(PlatformProfile.specs), PlatformProfile.tier_readout()])
	return _failures
