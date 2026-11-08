class_name QualityTier
extends RefCounted

## Device quality tiers (LOW / MEDIUM / HIGH): hardware specs -> a tier -> the budgets PlatformProfile hands out.
## HIGH is exactly what the game did before tiers existed, so a strong desktop is unchanged. (The former ULTRA tier was
## folded into HIGH; the name is still accepted as an alias, see canonical().) Pure functions of the
## specs dictionary, so the validator scores mocked machines (tests/validate_quality_tiers.gd).
##
## Specs: {cores, ram_bytes, free_bytes, adapter, vendor, discrete (bool or null = unknown), renderer, screen (Vector2i),
## refresh (Hz), phone, xr, quest, fps_limit (the player's cap, 0 = none)}. QualityGovernor steps a running game
## down/up inside the tier's "notches".

enum Tier { LOW, MEDIUM, HIGH }
const NAMES := ["LOW", "MEDIUM", "HIGH"]
const GB := 1_000_000_000


static func name_of(tier: int) -> String:
	return NAMES[clampi(tier, 0, NAMES.size() - 1)]


## The one place a graphics choice is read: trims, upper-cases, maps the retired "ULTRA" onto "HIGH", and returns
## "AUTO" for "AUTO", an empty string or anything unknown. Settings (setter, saved config), the --graphics argument and
## PlatformProfile.set_graphics_quality all go through this.
static func canonical(text) -> String:
	var t := String(text).strip_edges().to_upper()
	if t == "ULTRA":
		t = "HIGH"
	return t if NAMES.has(t) else "AUTO"


## The tier a choice names, or -1 for AUTO (and anything canonical() turns into AUTO).
static func from_name(text: String) -> int:
	return NAMES.find(canonical(text))


## What this machine reports, read once at boot.
static func detect() -> Dictionary:
	var memory := OS.get_memory_info()
	var adapter := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var type := RenderingServer.get_video_adapter_type()
	var discrete = null   # the Compatibility (GL) renderer reports no adapter type: guess from the name
	if type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		discrete = true
	elif type in [RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU]:
		discrete = false
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	return {
		"cores": OS.get_processor_count(), "ram_bytes": int(memory.get("physical", 0)),
		"free_bytes": int(memory.get("free", 0)), "adapter": adapter, "vendor": vendor, "discrete": discrete,
		"renderer": RenderingServer.get_current_rendering_method(), "screen": screen,
		"refresh": DisplayServer.screen_get_refresh_rate() if DisplayServer.get_name() != "headless" else 60.0,
		"phone": PlatformProfile.is_phone, "xr": PlatformProfile.is_xr, "quest": PlatformProfile.is_quest,
	}


## Discrete GPU from the adapter name when the renderer does not say: integrated parts announce themselves.
static func guess_discrete(specs: Dictionary) -> bool:
	if specs.get("discrete") != null:
		return bool(specs["discrete"])
	var adapter := String(specs.get("adapter", "")).to_lower()
	for integrated in ["intel", "uhd", "iris", "radeon(tm) graphics", "radeon graphics", "vega", "adreno", "mali",
			"apple", "powervr", "llvmpipe", "swiftshader", "microsoft basic"]:
		if integrated in adapter:
			return false
	return adapter.contains("geforce") or adapter.contains("rtx") or adapter.contains("gtx") \
		or adapter.contains("radeon rx") or adapter.contains("arc a")


## Apple silicon (Macs, iPhones): integrated but strong, unified memory.
static func is_apple_silicon(specs: Dictionary) -> bool:
	var adapter := String(specs.get("adapter", "")).to_lower()
	return adapter.begins_with("apple") or adapter.contains("apple m") or adapter.contains("apple a")


## Older Intel integrated graphics (HD / Iris / UHD up to the 600 series: Haswell-era Macs and PCs, the 2013 MacBook
## Airs, the T480's UHD 620): LOW by default, whatever the CPU and RAM. Iris Xe and Arc are newer and score normally.
static func is_old_intel_igpu(specs: Dictionary) -> bool:
	var adapter := String(specs.get("adapter", "")).to_lower()
	if not adapter.contains("intel") and not adapter.contains("iris") and not adapter.contains("hd graphics"):
		return false
	return not (adapter.contains("iris xe") or adapter.contains(" arc") or adapter.contains("xe graphics"))


static func score(specs: Dictionary) -> int:
	var cores := int(specs.get("cores", 4))
	var ram := float(specs.get("ram_bytes", 8 * GB)) / GB
	if bool(specs.get("quest", false)) or bool(specs.get("xr", false)) and bool(specs.get("phone", false)):
		return Tier.LOW   # standalone headset: fixed 72 Hz, the tightest budget
	if bool(specs.get("phone", false)):
		# phones top out at MEDIUM; a flagship (8 GB+, 6+ cores, Apple A-series or a recent Adreno) gets it
		if ram >= 7.5 and cores >= 6:
			return Tier.MEDIUM
		return Tier.LOW
	var discrete := guess_discrete(specs)
	if not discrete and is_old_intel_igpu(specs):
		return Tier.LOW
	# HIGH is a discrete GPU with 12+ threads and 15+ GB, or Apple silicon with 6+ cores and 7.5+ GB. An 8-thread
	# ~16 GB desktop (GTX 1650 / RTX 3060 / RX 6600 class) is the common AUTO pick: MEDIUM.
	# (While ULTRA existed, the 15-24 GB discrete and the 6-9 core Apple machines scored HIGH with a 30 Hz minimap and
	# stream 8/12 ms. To restore those numbers, split these two rules again and re-add that row to budgets().)
	if discrete and cores >= 12 and ram >= 15.0:
		return Tier.HIGH
	if is_apple_silicon(specs) and cores >= 6 and ram >= 7.5:
		return Tier.HIGH
	if cores >= 6 and ram >= 7.5:
		return Tier.MEDIUM
	return Tier.LOW


## The budgets a tier sets (PlatformProfile applies them). HIGH = the pre-tier desktop values.
## Flashlight shadows are on for desktop HIGH only. MEDIUM and LOW leave them off, and AUTO
## follows the tier it picked, so a common desktop at MEDIUM has them off too.
static func budgets(tier: int, specs: Dictionary) -> Dictionary:
	var low_memory := float(specs.get("ram_bytes", 8 * GB)) <= 4.8 * GB
	var table := {
		Tier.HIGH: {"map_update_hz": 0.0, "stream_budget_ms": 4.0, "stream_budget_max_ms": 9.0, "stream_budget_burst_ms": 14.0, "prebuild_linked_levels": true,
			"lamp_pool": 8, "shadows": true, "camera_far": 0.0, "prop_range_scale": 1.0, "prerender_ambience": true},
		Tier.MEDIUM: {"map_update_hz": 20.0, "stream_budget_ms": 3.0, "stream_budget_max_ms": 6.0, "stream_budget_burst_ms": 12.0, "prebuild_linked_levels": not low_memory,
			"lamp_pool": 6, "shadows": false, "camera_far": 140.0, "prop_range_scale": .8, "prerender_ambience": true},
		Tier.LOW: {"map_update_hz": 15.0, "stream_budget_ms": 2.0, "stream_budget_max_ms": 4.0, "stream_budget_burst_ms": 16.0, "prebuild_linked_levels": false,
			"lamp_pool": 4, "shadows": false, "camera_far": 90.0, "prop_range_scale": .6, "prerender_ambience": true},
	}
	var out: Dictionary = (table[clampi(tier, Tier.LOW, Tier.HIGH)] as Dictionary).duplicate()
	if bool(specs.get("phone", false)) or bool(specs.get("quest", false)):
		out["stream_budget_burst_ms"] = out["stream_budget_max_ms"]   # no hop burst: a dropped frame shows on a phone or in a headset
	if bool(specs.get("phone", false)):
		out["shadows"] = false   # phones never cast flashlight shadows; desktop MEDIUM and LOW don't either
		out["lamp_pool"] = mini(int(out["lamp_pool"]), 4)
		out["camera_far"] = 140.0 if tier >= Tier.MEDIUM else 90.0
	if bool(specs.get("quest", false)):
		out["shadows"] = false
		out["lamp_pool"] = 4
		out["camera_far"] = 60.0
	out["render_scale"] = 1.0
	out["prop_density"] = 1.0 if tier >= Tier.MEDIUM else .55
	out["decor_density"] = 1.0 if tier >= Tier.MEDIUM else .4
	# The governor's one conditional last notch (QualityGovernor.degrade): a phone renders at a smaller scale; a desktop
	# that still casts flashlight shadows (HIGH) switches them off; MEDIUM, LOW and the Quest have no fourth notch.
	if bool(specs.get("phone", false)) and not bool(specs.get("quest", false)):
		out["last_notch"] = "render_scale"
	elif bool(out["shadows"]):
		out["last_notch"] = "shadows"
	else:
		out["last_notch"] = ""
	out["worker_threads"] = maxi(1, int(specs.get("cores", 4)) - 1)
	out["frame_target_hz"] = frame_target(specs, tier)
	return out


## The frame rate the governor defends, by device and tier. Desktops: LOW 40, MEDIUM 50, HIGH 60 (a slow machine on
## LOW holds a steady 40 instead of chasing 60 with resolution and caps that cost more than they save). Phones: LOW 40,
## otherwise 60. The Quest: its fixed 72. Everything but the Quest is capped by the display refresh (floored at 30), and
## everything by the player's FPS limit (specs["fps_limit"], 0 = none), so a 144 Hz monitor never makes the game shed
## quality and a capped game is not "missing" a rate it was told not to reach. Unmeasured on devices.
static func frame_target(specs: Dictionary, tier: int = Tier.HIGH) -> float:
	var quest := bool(specs.get("quest", false))
	var want := 72.0
	if not quest:
		if bool(specs.get("phone", false)):
			want = 40.0 if tier == Tier.LOW else 60.0
		else:
			want = [40.0, 50.0, 60.0][clampi(tier, Tier.LOW, Tier.HIGH)]
		var refresh := float(specs.get("refresh", 0.0))
		if refresh > 0.0:
			want = minf(want, maxf(30.0, refresh))
	var limit := float(specs.get("fps_limit", 0))
	if limit > 0.0:
		want = minf(want, limit)
	return want if quest else maxf(30.0, want)


static func describe(specs: Dictionary) -> String:
	return "%d cores, %.1f GB RAM, %s (%s), %s, %dx%d @ %.0f Hz" % [int(specs.get("cores", 0)),
		float(specs.get("ram_bytes", 0)) / GB, String(specs.get("adapter", "?")),
		"discrete" if guess_discrete(specs) else "integrated", String(specs.get("renderer", "?")),
		(specs.get("screen", Vector2i.ZERO) as Vector2i).x, (specs.get("screen", Vector2i.ZERO) as Vector2i).y,
		float(specs.get("refresh", 0.0))]
