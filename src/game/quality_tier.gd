class_name QualityTier
extends RefCounted

## Device quality tiers (LOW / MEDIUM / HIGH / ULTRA): hardware specs -> a tier -> the budgets PlatformProfile hands out.
## ULTRA is exactly what the game did before tiers existed, so a strong desktop is unchanged. Pure functions of the
## specs dictionary, so the validator scores mocked machines (scripts/validate_quality_tiers.gd).
##
## Specs: {cores, ram_bytes, free_bytes, adapter, vendor, discrete (bool or null = unknown), renderer, screen (Vector2i),
## refresh (Hz), phone, xr, quest}. QualityGovernor steps a running game down/up inside the tier's "notches".

enum Tier { LOW, MEDIUM, HIGH, ULTRA }
const NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA"]
const GB := 1_000_000_000


static func name_of(tier: int) -> String:
	return NAMES[clampi(tier, 0, NAMES.size() - 1)]


static func from_name(text: String) -> int:
	return NAMES.find(text.to_upper())


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
	if discrete and cores >= 8 and ram >= 15.0:
		return Tier.ULTRA
	if (discrete or is_apple_silicon(specs)) and cores >= 6 and ram >= 7.5:
		return Tier.HIGH if not (is_apple_silicon(specs) and cores >= 10 and ram >= 15.0) else Tier.ULTRA
	if cores >= 6 and ram >= 7.5:
		return Tier.MEDIUM
	return Tier.LOW


## The budgets a tier sets (PlatformProfile applies them). ULTRA = the pre-tier desktop values.
static func budgets(tier: int, specs: Dictionary) -> Dictionary:
	var low_memory := float(specs.get("ram_bytes", 8 * GB)) <= 4.8 * GB
	var table := {
		Tier.ULTRA: {"map_update_hz": 0.0, "stream_budget_ms": 4.0, "stream_budget_max_ms": 9.0, "prebuild_linked_levels": true,
			"lamp_pool": 8, "shadows": true, "camera_far": 0.0, "prop_range_scale": 1.0, "prerender_ambience": true},
		Tier.HIGH: {"map_update_hz": 30.0, "stream_budget_ms": 4.0, "stream_budget_max_ms": 8.0, "prebuild_linked_levels": true,
			"lamp_pool": 8, "shadows": true, "camera_far": 0.0, "prop_range_scale": 1.0, "prerender_ambience": true},
		Tier.MEDIUM: {"map_update_hz": 20.0, "stream_budget_ms": 3.0, "stream_budget_max_ms": 6.0, "prebuild_linked_levels": not low_memory,
			"lamp_pool": 6, "shadows": true, "camera_far": 140.0, "prop_range_scale": .8, "prerender_ambience": true},
		Tier.LOW: {"map_update_hz": 15.0, "stream_budget_ms": 2.0, "stream_budget_max_ms": 4.0, "prebuild_linked_levels": false,
			"lamp_pool": 4, "shadows": false, "camera_far": 90.0, "prop_range_scale": .6, "prerender_ambience": true},
	}
	var out: Dictionary = (table[clampi(tier, Tier.LOW, Tier.ULTRA)] as Dictionary).duplicate()
	if bool(specs.get("phone", false)):
		out["shadows"] = false   # the flashlight's shadows stay on every desktop tier but LOW; phones and the Quest drop them
		out["lamp_pool"] = mini(int(out["lamp_pool"]), 4)
		out["camera_far"] = 140.0 if tier >= Tier.MEDIUM else 90.0
	if bool(specs.get("quest", false)):
		out["shadows"] = false
		out["lamp_pool"] = 4
		out["camera_far"] = 60.0
	out["render_scale"] = 1.0
	out["prop_density"] = 1.0 if tier >= Tier.MEDIUM else .55
	out["decor_density"] = 1.0 if tier >= Tier.MEDIUM else .4
	out["keep_shadows"] = bool(out["shadows"])
	out["worker_threads"] = maxi(1, int(specs.get("cores", 4)) - 1)
	out["frame_target_hz"] = frame_target(specs)
	return out


## The frame rate the governor defends: the Quest's fixed 72, phones 60, desktops their refresh rate capped at 60
## (above 60 the game is fine; a 144 Hz monitor must not make it shed quality).
static func frame_target(specs: Dictionary) -> float:
	if bool(specs.get("quest", false)):
		return 72.0
	return minf(60.0, maxf(30.0, float(specs.get("refresh", 60.0)))) if float(specs.get("refresh", 60.0)) > 0.0 else 60.0


static func describe(specs: Dictionary) -> String:
	return "%d cores, %.1f GB RAM, %s (%s), %s, %dx%d @ %.0f Hz" % [int(specs.get("cores", 0)),
		float(specs.get("ram_bytes", 0)) / GB, String(specs.get("adapter", "?")),
		"discrete" if guess_discrete(specs) else "integrated", String(specs.get("renderer", "?")),
		(specs.get("screen", Vector2i.ZERO) as Vector2i).x, (specs.get("screen", Vector2i.ZERO) as Vector2i).y,
		float(specs.get("refresh", 0.0))]
