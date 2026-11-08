extends RefCounted

## Graphics presets and the live governor (game/look/quality_tier.gd, game/look/quality_governor.gd, the Settings
## GRAPHICS choice and its panel hint):
##   - mocked machines land on the expected tier; HIGH is exactly the pre-tier desktop budget; "ULTRA" reads as HIGH,
##   - frame targets by tier / device / refresh / FPS limit, and the notch ladder (no fps cap, no lamp-pool step),
##   - the governor core (real feed()): a machine at its tier's rate does not step down, a sustained miss steps down one
##     notch at a time, a long clean stretch steps back up, a bounce holds further steps with 60/120/240/480 s,
##   - the live PlatformProfile / Settings / panel wiring. The live parts touch the real autoloads, so they run between
##     _snapshot() and _restore() and never call a saving setter (nothing here writes settings.cfg).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- quality_tiers

const GB := 1_000_000_000

var _failures := 0
var _overlay: Node


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


# ---------------------------------------------------------------------------------------------------- pure: tiers

func _tiers() -> void:
	var machines := [
		{"name": "gaming desktop (RTX, 16 cores, 32 GB)", "specs": {"cores": 16, "ram_bytes": 32 * GB, "adapter": "NVIDIA GeForce RTX 4070", "refresh": 144.0}, "tier": QualityTier.Tier.HIGH},
		{"name": "Mac mini M4 (10 cores, 16 GB)", "specs": {"cores": 10, "ram_bytes": 16 * GB, "adapter": "Apple M4", "refresh": 60.0}, "tier": QualityTier.Tier.HIGH},
		{"name": "MacBook Air M1 (8 cores, 8 GB)", "specs": {"cores": 8, "ram_bytes": 8 * GB, "adapter": "Apple M1", "refresh": 60.0}, "tier": QualityTier.Tier.HIGH},
		{"name": "AMD APU laptop (16 threads, 16 GB)", "specs": {"cores": 16, "ram_bytes": 16 * GB, "adapter": "AMD Radeon(TM) Graphics", "refresh": 60.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "old Intel laptop (4 threads, 8 GB)", "specs": {"cores": 4, "ram_bytes": 8 * GB, "adapter": "Intel(R) UHD Graphics 620", "refresh": 60.0}, "tier": QualityTier.Tier.LOW},
		{"name": "2015 MacBook Pro (i7-4770HQ, Iris Pro, 16 GB)", "specs": {"cores": 8, "ram_bytes": 16 * GB, "adapter": "Intel Iris Pro OpenGL Engine", "refresh": 60.0}, "tier": QualityTier.Tier.LOW},
		{"name": "2013 MacBook Air (HD 5000, 8 GB)", "specs": {"cores": 4, "ram_bytes": 8 * GB, "adapter": "Intel HD Graphics 5000 OpenGL Engine", "refresh": 60.0}, "tier": QualityTier.Tier.LOW},
		{"name": "T480 (8 threads, 16 GB, UHD 620)", "specs": {"cores": 8, "ram_bytes": 16 * GB, "adapter": "Mesa Intel(R) UHD Graphics 620 (KBL GT2)", "refresh": 60.0}, "tier": QualityTier.Tier.LOW},
		{"name": "Iris Xe laptop (12 threads, 16 GB)", "specs": {"cores": 12, "ram_bytes": 16 * GB, "adapter": "Intel(R) Iris(R) Xe Graphics", "refresh": 60.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "iPhone 16 Pro (6 cores, 8 GB)", "specs": {"cores": 6, "ram_bytes": 8 * GB, "adapter": "Apple A18 Pro GPU", "phone": true, "refresh": 120.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "Galaxy S24 FE (8 cores, 8 GB)", "specs": {"cores": 8, "ram_bytes": 8 * GB, "adapter": "Mali-G715", "phone": true, "refresh": 120.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "budget phone (8 cores, 4 GB)", "specs": {"cores": 8, "ram_bytes": 4 * GB, "adapter": "Adreno (TM) 610", "phone": true}, "tier": QualityTier.Tier.LOW},
		{"name": "Quest 3S", "specs": {"cores": 6, "ram_bytes": 8 * GB, "adapter": "Adreno (TM) 740", "quest": true, "xr": true}, "tier": QualityTier.Tier.LOW},
		{"name": "GL renderer reporting discrete", "specs": {"cores": 8, "ram_bytes": 16 * GB, "adapter": "Some GPU", "discrete": true}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "GTX 1650 desktop (8 threads, 16 GB)", "specs": {"cores": 8, "ram_bytes": 16 * GB, "adapter": "NVIDIA GeForce GTX 1650", "refresh": 60.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "RTX 3060 desktop (8 threads, 16 GB)", "specs": {"cores": 8, "ram_bytes": 16 * GB, "adapter": "NVIDIA GeForce RTX 3060", "refresh": 60.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "RX 6600 desktop (8 threads, 16 GB)", "specs": {"cores": 8, "ram_bytes": 16 * GB, "adapter": "AMD Radeon RX 6600", "refresh": 60.0}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "8-thread discrete (32 GB)", "specs": {"cores": 8, "ram_bytes": 32 * GB, "adapter": "NVIDIA GeForce RTX 3060", "discrete": true}, "tier": QualityTier.Tier.MEDIUM},
		{"name": "12-thread discrete (16 GB)", "specs": {"cores": 12, "ram_bytes": 16 * GB, "adapter": "NVIDIA GeForce RTX 4070", "discrete": true}, "tier": QualityTier.Tier.HIGH},
		{"name": "12-thread discrete (32 GB)", "specs": {"cores": 12, "ram_bytes": 32 * GB, "adapter": "NVIDIA GeForce RTX 4070", "discrete": true}, "tier": QualityTier.Tier.HIGH},
	]
	for machine in machines:
		var got := QualityTier.score(machine["specs"])
		_expect(got == int(machine["tier"]), "%s scored %s, expected %s" % [machine["name"], QualityTier.name_of(got), QualityTier.name_of(machine["tier"])])
	_expect(QualityTier.NAMES.size() == 3 and not QualityTier.NAMES.has("ULTRA"), "the tier list still has an ULTRA entry")
	var high := QualityTier.budgets(QualityTier.Tier.HIGH, {"cores": 16, "ram_bytes": 32 * GB})
	_expect(int(high["lamp_pool"]) == 8 and float(high["camera_far"]) == 0.0 and bool(high["prebuild_linked_levels"])
		and bool(high["shadows"]) and float(high["prop_range_scale"]) == 1.0 and float(high["stream_budget_ms"]) == 4.0
		and float(high["stream_budget_max_ms"]) == 9.0 and float(high["stream_budget_burst_ms"]) == 14.0
		and float(high["map_update_hz"]) == 0.0, "HIGH is not the pre-tier desktop budget: %s" % str(high))
	var quest := QualityTier.budgets(QualityTier.Tier.LOW, {"quest": true})
	_expect(float(quest["frame_target_hz"]) == 72.0 and float(quest["camera_far"]) == 60.0, "the Quest does not target a fixed 72 Hz with its 60 m far plane")
	# Flashlight shadows: desktop HIGH only. MEDIUM, LOW, phones, and the Quest leave them off.
	var desktop := {"cores": 8, "ram_bytes": 16 * GB}
	var desktop_high := QualityTier.budgets(QualityTier.Tier.HIGH, desktop)
	_expect(bool(desktop_high["shadows"]), "desktop HIGH drops the flashlight shadows")
	var medium := QualityTier.budgets(QualityTier.Tier.MEDIUM, desktop)
	_expect(not bool(medium["shadows"]), "desktop MEDIUM keeps flashlight shadows")
	_expect(not bool(QualityGovernor.degrade(medium, QualityGovernor.MAX_NOTCH)["shadows"]), "a stepped-down MEDIUM desktop turned flashlight shadows on")
	_expect(not bool(QualityTier.budgets(QualityTier.Tier.LOW, {})["shadows"]), "LOW keeps shadows")
	_expect(not bool(QualityTier.budgets(QualityTier.Tier.MEDIUM, {"phone": true})["shadows"]), "a phone keeps shadows")
	_expect(not bool(quest["shadows"]), "the Quest keeps shadows")
	_expect(not desktop_high.has("keep_shadows") and not desktop_high.has("fps_cap"), "a retired budget key is back")
	_monotonic(desktop)


## Down the presets (HIGH -> MEDIUM -> LOW) the visual budgets only shrink. Only the budgets that are a pure
## "how much is drawn" ordering are compared (camera_far 0 = unlimited).
func _monotonic(specs: Dictionary) -> void:
	var prev: Dictionary = {}
	for tier in [QualityTier.Tier.HIGH, QualityTier.Tier.MEDIUM, QualityTier.Tier.LOW]:
		var b := QualityTier.budgets(tier, specs)
		var far := float(b["camera_far"])
		var now := {"camera_far": INF if far <= 0.0 else far, "prop_range_scale": float(b["prop_range_scale"]),
			"lamp_pool": float(b["lamp_pool"]), "prop_density": float(b["prop_density"]), "decor_density": float(b["decor_density"]),
			"stream_budget_ms": float(b["stream_budget_ms"]), "stream_budget_max_ms": float(b["stream_budget_max_ms"])}
		for key in now:
			_expect(prev.is_empty() or float(now[key]) <= float(prev[key]), "preset %s has a larger %s than the preset above it" % [QualityTier.name_of(tier), key])
		prev = now


func _names() -> void:
	var cases := {"ULTRA": "HIGH", "ultra": "HIGH", "Ultra": "HIGH", " high ": "HIGH", "": "AUTO", "garbage": "AUTO", "AUTO": "AUTO",
		"low": "LOW", "Medium": "MEDIUM"}
	for text in cases:
		_expect(Settings.parse_graphics_value(text) == cases[text],
			"parse_graphics_value('%s') = '%s', expected '%s'" % [text, Settings.parse_graphics_value(text), cases[text]])
		_expect(QualityTier.canonical(text) == cases[text], "QualityTier.canonical('%s') = '%s'" % [text, QualityTier.canonical(text)])
	_expect(QualityTier.from_name("ULTRA") == QualityTier.Tier.HIGH, "from_name('ULTRA') is not HIGH")
	_expect(QualityTier.from_name("AUTO") == -1 and QualityTier.from_name("nonsense") == -1 and QualityTier.from_name("low") == QualityTier.Tier.LOW,
		"from_name does not map AUTO and unknown names to -1")
	_expect(not Settings.GRAPHICS_CHOICES.has("ULTRA") and Settings.GRAPHICS_CHOICES == ["AUTO", "LOW", "MEDIUM", "HIGH"],
		"Settings.GRAPHICS_CHOICES is %s" % str(Settings.GRAPHICS_CHOICES))


func _targets() -> void:
	var desktop := {"cores": 8, "ram_bytes": 16 * GB, "refresh": 60.0}
	_expect(_target(QualityTier.Tier.LOW, desktop) == 40.0 and _target(QualityTier.Tier.MEDIUM, desktop) == 50.0
		and _target(QualityTier.Tier.HIGH, desktop) == 60.0, "desktop targets are not 40 / 50 / 60")
	var phone := {"phone": true, "cores": 8, "ram_bytes": 8 * GB, "refresh": 120.0}
	_expect(_target(QualityTier.Tier.LOW, phone) == 40.0 and _target(QualityTier.Tier.MEDIUM, phone) == 60.0, "phone targets are not LOW 40 / otherwise 60")
	_expect(_target(QualityTier.Tier.LOW, {"quest": true, "xr": true, "refresh": 60.0}) == 72.0, "the Quest does not defend its fixed 72 whatever the refresh says")
	_expect(_target(QualityTier.Tier.HIGH, {"refresh": 45.0}) == 45.0, "a 45 Hz display is not the target ceiling")
	_expect(_target(QualityTier.Tier.HIGH, {"refresh": 144.0}) == 60.0, "a 144 Hz desktop defends more than 60 fps")
	_expect(_target(QualityTier.Tier.HIGH, {"refresh": 20.0}) == 30.0, "the refresh cap goes below 30 fps")
	_expect(_target(QualityTier.Tier.HIGH, {"refresh": -1.0}) == 60.0 and _target(QualityTier.Tier.HIGH, {}) == 60.0, "an unknown refresh changes the target")
	_expect(_target(QualityTier.Tier.HIGH, {"refresh": 60.0, "fps_limit": 30}) == 30.0, "an FPS limit of 30 does not cap the target")
	_expect(_target(QualityTier.Tier.HIGH, {"refresh": 60.0, "fps_limit": 0}) == 60.0, "an FPS limit of 0 (none) changed the target")
	_expect(_target(QualityTier.Tier.LOW, {"refresh": 60.0, "fps_limit": 90}) == 40.0, "a high FPS limit raised the LOW target")


func _target(tier: int, specs: Dictionary) -> float:
	return float(QualityTier.budgets(tier, specs)["frame_target_hz"])


func _ladder() -> void:
	var desktop := {"cores": 8, "ram_bytes": 16 * GB}
	var high := QualityTier.budgets(QualityTier.Tier.HIGH, desktop)
	_expect(QualityGovernor.notches_for(high) == 4, "desktop HIGH has %d notches, expected 4" % QualityGovernor.notches_for(high))
	var n1 := QualityGovernor.degrade(high, 1)
	_expect(float(n1["camera_far"]) > 0.0 and float(n1["map_update_hz"]) == 30.0 and bool(n1["shadows"]), "notch 1 is not the far plane + minimap rate")
	var n2 := QualityGovernor.degrade(high, 2)
	_expect(float(n2["stream_budget_ms"]) < float(high["stream_budget_ms"]) and float(n2["stream_budget_max_ms"]) < float(high["stream_budget_max_ms"]),
		"notch 2 does not lower the stream budgets")
	var n3 := QualityGovernor.degrade(high, 3)
	_expect(is_equal_approx(float(n3["prop_range_scale"]), .75) and bool(n3["shadows"]), "notch 3 is not prop range x0.75 with shadows still on")
	var n4 := QualityGovernor.degrade(high, 4)
	_expect(not bool(n4["shadows"]) and float(n4["render_scale"]) == 1.0, "desktop HIGH's last notch is not shadows off (no render scale)")
	for n in range(0, 5):
		var d := QualityGovernor.degrade(high, n)
		_expect(int(d["lamp_pool"]) == int(high["lamp_pool"]), "notch %d changed the lamp pool" % n)
		_expect(not d.has("fps_cap"), "notch %d sets an fps cap" % n)
	for tier in [QualityTier.Tier.MEDIUM, QualityTier.Tier.LOW]:
		var b := QualityTier.budgets(tier, desktop)
		_expect(QualityGovernor.notches_for(b) == 3, "desktop %s has %d notches, expected 3" % [QualityTier.name_of(tier), QualityGovernor.notches_for(b)])
		_expect(float(QualityGovernor.degrade(b, 4)["render_scale"]) == 1.0 and not bool(QualityGovernor.degrade(b, 4)["shadows"]), "desktop %s has a fourth notch" % QualityTier.name_of(tier))
	_expect(QualityGovernor.notches_for(quest_budgets()) == 3, "the Quest has more than 3 notches")
	for tier in [QualityTier.Tier.MEDIUM, QualityTier.Tier.LOW]:
		var phone := QualityTier.budgets(tier, {"phone": true, "cores": 8, "ram_bytes": 8 * GB})
		_expect(QualityGovernor.notches_for(phone) == 4, "a phone %s has %d notches, expected 4" % [QualityTier.name_of(tier), QualityGovernor.notches_for(phone)])
		_expect(is_equal_approx(float(QualityGovernor.degrade(phone, 3)["render_scale"]), 1.0)
			and is_equal_approx(float(QualityGovernor.degrade(phone, 4)["render_scale"]), .85), "a phone's last notch is not render scale 0.85")
		_expect(int(QualityGovernor.degrade(phone, 4)["lamp_pool"]) == int(phone["lamp_pool"]), "a phone notch changed the lamp pool")
		_expect(not QualityGovernor.degrade(phone, 4).has("fps_cap"), "a phone notch sets an fps cap")


func quest_budgets() -> Dictionary:
	return QualityTier.budgets(QualityTier.Tier.LOW, {"quest": true, "xr": true, "cores": 6, "ram_bytes": 8 * GB})


# ------------------------------------------------------------------------------------------- pure: the governor

## Feeds `seconds` of frames of `ms` each; returns [{t, change, notch}, ...] (t relative to this call).
func _run(governor: QualityGovernor, ms: float, seconds: float) -> Array:
	var changes := []
	var t := 0.0
	while t < seconds:
		var change := governor.feed(ms)
		if change != 0:
			changes.append({"t": t, "change": change, "notch": governor.notch})
		t += ms / 1000.0
	return changes


func _new_governor(target_hz: float) -> QualityGovernor:
	var gov := QualityGovernor.new()
	gov.target_ms = 1000.0 / target_hz
	return gov


func _governor() -> void:
	var gov := _new_governor(60.0)
	# 30 fps for 20 s: steps down, one notch per cooldown, never past the maximum
	var down := _run(gov, 33.3, 20.0)
	_expect(not down.is_empty() and down[0]["change"] == 1, "missing the target for 20 s did not step down")
	_expect(down.size() >= 2 and float(down[0]["t"]) >= QualityGovernor.MISS_SECONDS - .1, "stepped down before %.0f s of misses" % QualityGovernor.MISS_SECONDS)
	for i in range(1, down.size()):
		_expect(float(down[i]["t"]) - float(down[i - 1]["t"]) >= QualityGovernor.DOWN_COOLDOWN - .05, "two step-downs within the cooldown")
	_expect(gov.notch == gov.max_notch, "a sustained miss stopped at notch %d of %d" % [gov.notch, gov.max_notch])
	_run(gov, 33.3, 60.0)
	_expect(gov.notch <= gov.max_notch, "notch past the maximum")
	_expect(gov._bounces == 0, "cascaded step-downs counted as bounces")
	var low_notch := gov.notch
	# then 120 fps: the first step up needs a clean UP_SECONDS (there is no hold before the first bounce)
	var up := _run(gov, 8.3, 120.0).filter(func(c: Dictionary) -> bool: return c["change"] == -1)
	_expect(not up.is_empty() and float(up[0]["t"]) >= QualityGovernor.UP_SECONDS - .1, "stepped back up before %.0f s clean" % QualityGovernor.UP_SECONDS)
	_expect(not up.is_empty() and float(up[0]["t"]) <= QualityGovernor.UP_SECONDS + 3.0, "the first step up waited %.1f s (no hold applies before a bounce)" % (float(up[0]["t"]) if not up.is_empty() else -1.0))
	_expect(gov.notch < low_notch, "a long clean stretch never stepped back up")
	gov.free()

	# a machine at its tier's rate: the 2015 Air at ~19.7 ms is fine for a LOW desktop (target 40 fps = 25 ms), not for 60
	var air := _new_governor(40.0)
	var air_changes := _run(air, 19.7, 300.0)
	_expect(air_changes.is_empty(), "the Air-like 19.7 ms at a 25 ms target changed quality %d times" % air_changes.size())
	var air60 := _new_governor(60.0)
	_expect(not _run(air60, 19.7, 30.0).is_empty(), "19.7 ms against a 60 fps target no longer steps down (the old behaviour this change avoids)")
	air.free()
	air60.free()

	# a Quest or any 3-notch tier stops at its own maximum
	var headset := _new_governor(72.0)
	headset.max_notch = QualityGovernor.notches_for(quest_budgets())
	_run(headset, 25.0, 60.0)
	_expect(headset.notch == 3 and headset.max_notch == 3, "a steady miss on the Quest ended at notch %d (max %d)" % [headset.notch, headset.max_notch])
	headset.free()

	# hovering inside the dead band (5 % over target): no change either way
	var steady := _new_governor(60.0)
	var edge := _run(steady, 1000.0 / 60.0 * 1.05, 60.0)
	_expect(edge.is_empty(), "frame times inside the dead band changed quality %d times" % edge.size())
	steady.free()

	# a brief spike: back at notch 0 well within 40 s
	var spike := _new_governor(60.0)
	_run(spike, 25.0, 4.0)
	_run(spike, 16.0, 36.0)
	_expect(spike.notch == 0, "a 4 s spike left the game %d notch(es) down after 36 s of clean frames" % spike.notch)
	spike.free()

	# alternating 2 s slow / 2 s fast for two minutes: no flicker
	var flick := _new_governor(60.0)
	var flips := 0
	var last_change := 0
	for cycle in 30:
		for change in _run(flick, 40.0, 2.0) + _run(flick, 8.0, 2.0):
			if last_change != 0 and change["change"] != last_change:
				flips += 1
			last_change = change["change"]
	_expect(flips <= 2, "alternating slow/fast frames flipped quality direction %d times in two minutes" % flips)
	flick.free()

	_bounces()
	_edge_machine()
	print("  quality_tiers  20 s at 30 fps -> notch %d of %d; clean 120 fps brought it back to %d; Air-like 19.7 ms at 25 ms target: %d changes; %d direction flips" % [
		low_notch, QualityGovernor.MAX_NOTCH, low_notch - up.size(), air_changes.size(), flips])


## Bounce bookkeeping: one bounce holds the next step up for BOUNCE_HOLD; a step up that survives STABLE_FORGET clears it;
## reset() forgets everything.
func _bounces() -> void:
	var gov := _new_governor(60.0)
	gov.notch = 1
	_run(gov, 16.0, 25.0)
	_expect(gov.notch == 0 and gov._last_was_up, "a clean stretch did not step up")
	_run(gov, 33.0, 6.0)   # it comes straight back down: a bounce
	_expect(gov.notch >= 1 and gov._bounces == 1, "a step down right after a step up was not counted as a bounce (bounces %d)" % gov._bounces)
	_expect(gov._hold_left > QualityGovernor.BOUNCE_HOLD - 8.0 and gov._hold_left <= QualityGovernor.BOUNCE_HOLD, "the first hold is %.1f s, expected about %.0f" % [gov._hold_left, QualityGovernor.BOUNCE_HOLD])
	var before := gov.notch
	# clean again: no step up until the hold has run out, then one at once (the clean time has already accrued)
	var held := _run(gov, 16.0, QualityGovernor.BOUNCE_HOLD - 10.0)
	_expect(held.is_empty() and gov.notch == before, "stepped up inside the bounce hold")
	var resumed := _run(gov, 16.0, 30.0)
	_expect(not resumed.is_empty() and resumed[0]["change"] == -1, "never stepped up after the hold expired")
	# that step up survives STABLE_FORGET: the escalation is forgotten
	_run(gov, 16.0, QualityGovernor.STABLE_FORGET + 5.0)
	_expect(gov._bounces == 0, "a step up that survived %.0f s did not clear the escalation (bounces %d)" % [QualityGovernor.STABLE_FORGET, gov._bounces])
	# reset() after a bounce: no hold, no history; a clean 20 s then steps up
	gov.reset()
	gov.notch = 1
	_run(gov, 16.0, 22.0)
	var again := gov.notch
	_run(gov, 33.0, 6.0)
	_expect(gov._bounces >= 1 and gov._hold_left > 0.0, "setup: expected a bounce before reset()")
	gov.reset()
	_expect(gov.notch == 0 and gov._hold_left == 0.0 and gov._bounces == 0 and not gov._last_was_up, "reset() left state behind (notch %d, hold %.1f, bounces %d)" % [gov.notch, gov._hold_left, gov._bounces])
	gov.notch = 1
	var after_reset := _run(gov, 16.0, QualityGovernor.UP_SECONDS + 3.0)
	_expect(not after_reset.is_empty() and after_reset[0]["change"] == -1 and again == 0, "a clean %.0f s after reset() did not step up" % QualityGovernor.UP_SECONDS)
	gov.free()


## A machine that is slow at notch 0 (22 ms) and fine one notch down (17 ms) at a 60 fps target bounces forever. The
## escalation 60/120/240/480 s must hold at its cap, not restart: few step-ups in 1200 s, each gap no shorter than its hold.
func _edge_machine() -> void:
	var gov := _new_governor(60.0)
	var ups: Array = []
	var last_bounces := 0
	var bounces_never_fell := true
	var max_hold := 0.0
	var t := 0.0
	while t < 1200.0:
		var ms := 22.0 if gov.notch == 0 else 17.0
		var change := gov.feed(ms)
		t += ms / 1000.0
		max_hold = maxf(max_hold, gov._hold_left)
		if gov._bounces < last_bounces:
			bounces_never_fell = false
		last_bounces = gov._bounces
		if change == -1:
			ups.append(t)
	_expect(ups.size() >= 3 and ups.size() <= 5, "the edge machine stepped up %d times in 1200 s (expected 3 to 5)" % ups.size())
	for i in range(1, ups.size()):
		var minimum: float = QualityGovernor.BOUNCE_HOLD * pow(2.0, minf(i - 1, QualityGovernor.BOUNCE_MAX - 1))
		_expect(float(ups[i]) - float(ups[i - 1]) >= minimum - 1.0, "edge machine step-up gap %d was %.0f s, shorter than its %.0f s hold" % [i, float(ups[i]) - float(ups[i - 1]), minimum])
	_expect(bounces_never_fell, "the escalation was forgotten while the machine kept bouncing")
	_expect(max_hold >= QualityGovernor.BOUNCE_HOLD * pow(2.0, QualityGovernor.BOUNCE_MAX - 1) - 1.0, "the hold never reached its %.0f s cap (max %.0f)" % [
		QualityGovernor.BOUNCE_HOLD * pow(2.0, QualityGovernor.BOUNCE_MAX - 1), max_hold])
	print("  quality_tiers  edge machine (22 ms at notch 0, 17 ms below): %d step-ups in 1200 s at %s s, max hold %.0f s" % [ups.size(), str(ups.map(func(u: float) -> int: return roundi(u))), max_hold])
	gov.free()


# --------------------------------------------------------------------------------------------- live autoloads

func _snapshot() -> Dictionary:
	var governor := PlatformProfile.governor
	return {"quality": Settings.graphics_quality, "fps_limit": Settings.fps_limit, "max_fps": Engine.max_fps,
		"auto": PlatformProfile.graphics_auto, "tier": PlatformProfile.tier, "notch": PlatformProfile.notch,
		"refresh": float(PlatformProfile.specs.get("refresh", 0.0)), "has_refresh": PlatformProfile.specs.has("refresh"),
		"governor_notch": governor.notch if governor != null else 0}


## Puts the live autoloads back. Assigns fields directly and calls PlatformProfile.set_graphics_quality (which never
## saves), so no path here writes settings.cfg.
func _restore(snap: Dictionary) -> void:
	Settings.graphics_quality = String(snap["quality"])
	Settings.fps_limit = int(snap["fps_limit"])
	if bool(snap["has_refresh"]):
		PlatformProfile.specs["refresh"] = float(snap["refresh"])
	PlatformProfile._refresh_seen = 0.0
	PlatformProfile.set_graphics_quality("AUTO" if bool(snap["auto"]) else QualityTier.name_of(int(snap["tier"])))
	PlatformProfile.notch = int(snap["notch"])
	if PlatformProfile.governor != null:
		PlatformProfile.governor.notch = int(snap["governor_notch"])
	PlatformProfile.apply_budgets()
	Engine.max_fps = int(snap["max_fps"])


func _live_refresh() -> void:
	var p := PlatformProfile
	if p.specs.is_empty():
		return
	Settings.fps_limit = 0
	p.specs["refresh"] = 60.0
	p._refresh_seen = 0.0
	p.set_graphics_quality("HIGH")
	_expect(is_equal_approx(p.frame_target_hz, 60.0) and is_equal_approx(p.governor.target_ms, 1000.0 / 60.0), "HIGH on 60 Hz does not target 60 (%.1f)" % p.frame_target_hz)
	p.set_display_refresh(30.0)
	_expect(is_equal_approx(p.frame_target_hz, 60.0), "one refresh poll changed the target")
	p.set_display_refresh(30.0)
	_expect(is_equal_approx(p.frame_target_hz, 30.0) and is_equal_approx(p.governor.target_ms, 1000.0 / 30.0), "two equal polls of 30 Hz did not retarget (%.1f)" % p.frame_target_hz)
	p.set_display_refresh(0.0)
	p.set_display_refresh(-1.0)
	_expect(is_equal_approx(float(p.specs["refresh"]), 30.0) and is_equal_approx(p.frame_target_hz, 30.0), "an unknown refresh (0 / -1) changed the target")
	p.set_display_refresh(90.0)
	_expect(is_equal_approx(float(p.specs["refresh"]), 30.0), "a single 90 Hz poll after an unknown one was accepted")
	p.set_display_refresh(90.0)
	_expect(is_equal_approx(p.frame_target_hz, 60.0), "two polls of 90 Hz did not return HIGH to 60 (%.1f)" % p.frame_target_hz)
	# the player's FPS limit caps the target
	Settings.fps_limit = 45
	p.apply_budgets()
	_expect(is_equal_approx(p.governor.target_ms, 1000.0 / 45.0), "an FPS limit of 45 gives a %.1f ms target" % p.governor.target_ms)
	Settings.fps_limit = 0
	p.apply_budgets()
	_expect(is_equal_approx(p.governor.target_ms, 1000.0 / 60.0), "clearing the FPS limit did not restore the target")
	# a preset change resets the governor and re-applies target and notch count
	p.governor.notch = 3
	p.governor.max_notch = 1
	p.governor.target_ms = 99.0
	p.set_graphics_quality("MEDIUM")
	_expect(p.governor.notch == 0 and not p.governor.enabled and is_equal_approx(p.governor.target_ms, 20.0) and p.governor.max_notch == 3,
		"changing the preset left governor state (notch %d, target %.1f, max %d)" % [p.governor.notch, p.governor.target_ms, p.governor.max_notch])
	p.set_graphics_quality("HIGH")
	_expect(p.governor.max_notch == 4, "desktop HIGH did not get its fourth notch (max %d)" % p.governor.max_notch)


func _live_loaded() -> void:
	var p := PlatformProfile
	Settings._apply_loaded_graphics("ULTRA")
	_expect(Settings.graphics_quality == "HIGH" and p.tier == QualityTier.Tier.HIGH and not p.graphics_auto, "a saved ULTRA did not load as HIGH (%s / %s)" % [Settings.graphics_quality, p.tier_readout()])
	Settings._apply_loaded_graphics("garbage")
	_expect(Settings.graphics_quality == "AUTO", "a garbage saved value did not load as AUTO")
	p.set_graphics_quality("AUTO")
	_expect(p.graphics_auto and p.governor.enabled, "AUTO does not enable the governor")
	# a saved AUTO leaves the live preset on AUTO and re-applies target and notch count
	p.governor.target_ms = 99.0
	p.governor.max_notch = 1
	Settings._apply_loaded_graphics("AUTO")
	_expect(p.graphics_auto and p.governor.enabled and Settings.graphics_quality == "AUTO", "loading AUTO changed the governor")
	_expect(is_equal_approx(p.governor.target_ms, 1000.0 / p.frame_target_hz) and p.governor.max_notch >= 3, "loading AUTO did not re-apply the governor target / notch count")
	# the --graphics argument goes through the same reading: ULTRA = HIGH, case and spaces ignored
	p.set_graphics_quality("ultra")
	_expect(p.tier == QualityTier.Tier.HIGH and not p.graphics_auto, "set_graphics_quality('ultra') is not HIGH")
	p.set_graphics_quality(" low ")
	_expect(p.tier == QualityTier.Tier.LOW and not p.graphics_auto, "set_graphics_quality(' low ') is not LOW")
	p.set_graphics_quality("???")
	_expect(p.graphics_auto, "set_graphics_quality('???') is not AUTO")


func _live_panel(host: Node) -> void:
	var cfg_time := FileAccess.get_modified_time(Settings.SETTINGS_PATH) if FileAccess.file_exists(Settings.SETTINGS_PATH) else 0
	Settings.graphics_quality = "AUTO"
	PlatformProfile.set_graphics_quality("AUTO")
	_overlay = (load("res://game/menus/settings_overlay.tscn") as PackedScene).instantiate()
	host.add_child(_overlay)
	var panel := _overlay as SettingsPanel
	var button := _overlay.find_child("GraphicsQualityButton", true, false) as Button
	var hint := _overlay.get_node_or_null("GraphicsQualityHint") as Label
	_expect(panel != null and button != null and hint != null, "the settings panel has no quality button / GraphicsQualityHint")
	if panel == null or button == null or hint == null:
		return
	var wired := false
	for connection in button.pressed.get_connections():
		if (connection["callable"] as Callable).get_method() == &"_on_graphics_pressed":
			wired = true
	_expect(wired, "GraphicsQualityButton.pressed is not connected to _on_graphics_pressed")
	var seen: Array[String] = []
	for i in 4:
		panel._on_graphics_pressed(false)   # the real handler, without writing settings.cfg
		seen.append(Settings.graphics_quality)
		_expect(not button.text.contains("ULTRA") and not button.tooltip_text.contains("ULTRA") and not hint.text.contains("ULTRA"),
			"the quality button, tooltip or hint mentions ULTRA after choice %s" % Settings.graphics_quality)
		_expect(hint.text == SettingsPanel.preset_hint(Settings.graphics_quality, PlatformProfile.is_phone, PlatformProfile.is_quest), "the hint does not describe %s" % Settings.graphics_quality)
	_expect(seen == ["LOW", "MEDIUM", "HIGH", "AUTO"], "the quality button cycled %s, expected LOW, MEDIUM, HIGH, AUTO" % str(seen))
	_expect(button.tooltip_text.contains("AUTO, LOW, MEDIUM, HIGH."), "the tooltip does not list the presets")
	# DISPLAY tab only, inside the band between the FOV and SENSITIVITY rows, clear of every other DISPLAY row
	panel._show_settings_category(0)
	_expect(not hint.visible, "the preset hint shows on the AUDIO tab")
	panel._show_settings_category(1)
	_expect(hint.visible, "the preset hint is hidden on the DISPLAY tab")
	var fov := _overlay.get_node("FovRow") as Control
	var sensitivity := _overlay.get_node("SensitivityRow") as Control
	_expect(hint.offset_top >= fov.offset_bottom and hint.offset_bottom <= sensitivity.offset_top, "the hint (%d..%d) is not between the FOV row (..%d) and the sensitivity row (%d..)" % [
		hint.offset_top, hint.offset_bottom, fov.offset_bottom, sensitivity.offset_top])
	_expect(hint.offset_left >= 20.0 and hint.offset_right <= 420.0, "the hint leaves the 20..420 band")
	var hint_rect := Rect2(hint.offset_left, hint.offset_top, hint.offset_right - hint.offset_left, hint.offset_bottom - hint.offset_top)
	for row_name in ["DisplayRow", "VsyncRow", "FpsLimitRow", "FovRow", "SensitivityRow", "FocusPauseRow", "TeammateWaypointsRow"]:
		var row := _overlay.get_node(row_name) as Control
		var row_rect := Rect2(row.offset_left, row.offset_top, row.offset_right - row.offset_left, maxf(row.offset_bottom - row.offset_top, row.get_combined_minimum_size().y))
		_expect(not hint_rect.intersects(row_rect), "the preset hint overlaps %s (%s vs %s)" % [row_name, hint_rect, row_rect])
	# every hint fits the 400 px band on the design canvas (phone and Quest panels scale this canvas as a whole), measured
	# with the label's own font and a 20 px margin; and no phone / Quest wording mentions a PC
	var font := hint.get_theme_font("font")
	var font_size := hint.get_theme_font_size("font_size")
	for choice in Settings.GRAPHICS_CHOICES:
		for platform in [[false, false], [true, false], [false, true]]:
			var text := SettingsPanel.preset_hint(choice, platform[0], platform[1])
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			_expect(width <= 380.0, "the %s hint is %.0f px wide at size %d (limit 380): %s" % [choice, width, font_size, text])
			_expect(text.length() <= SettingsPanel.PRESET_HINT_MAX_CHARS and not text.contains("ULTRA"), "the %s hint is too long or mentions ULTRA: %s" % [choice, text])
			if platform[0] or platform[1]:
				_expect(not text.contains("PC"), "the %s hint for a phone / Quest says PC: %s" % [choice, text])
	var cfg_after := FileAccess.get_modified_time(Settings.SETTINGS_PATH) if FileAccess.file_exists(Settings.SETTINGS_PATH) else 0
	_expect(cfg_after == cfg_time, "the panel test wrote settings.cfg")


func _free_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.free()
	_overlay = null


func run(host: Node) -> int:
	var snap := _snapshot()
	_tiers()
	_names()
	_targets()
	_ladder()
	_governor()
	# Each live part runs between a snapshot and a restore; none has an early exit that skips the restore below, and a
	# script error aborts only the function it happens in.
	_live_refresh()
	_restore(snap)
	_live_loaded()
	_restore(snap)
	_live_panel(host)
	_free_overlay()
	_restore(snap)
	print("  quality_tiers  this machine: %s -> %s" % [QualityTier.describe(PlatformProfile.specs), PlatformProfile.tier_readout()])
	return _failures
