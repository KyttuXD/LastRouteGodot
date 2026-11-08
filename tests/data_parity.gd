extends RefCounted

## Parity fingerprints for the data-driven pilots (docs/DATA_DRIVEN_CONTENT.md). Each one hashes what the game actually
## does with a table -- generated chunks, chosen model paths, hunter draws -- through public APIs only, so the same
## function runs on the commit before a migration and after it. The data_* suites print them; equal hashes on both
## sides of a migration commit are the "no visible change" proof.

const SEED := "DATA-PARITY"


static func sha(value) -> String:
	return var_to_str(value).sha256_text().substr(0, 16)


## Coordinates of the first `count` chunks of `region` on levels 0..2, scanning outward from the origin.
static func chunks_of(generator: StreamedRouteGenerator, region: String, count: int) -> Array:
	var out := []
	for level in 3:
		for radius in 14:
			for x in range(-radius, radius + 1):
				for z in range(-radius, radius + 1):
					if maxi(absi(x), absi(z)) != radius:
						continue
					var coord := Vector3i(x, level, z)
					if generator.region_for(coord) == region:
						out.append(coord)
						if out.size() >= count:
							return out
	return out


## Mall: full chunk data for the first six mall chunks.
static func region_hash(region: String = "mall") -> String:
	var generator := StreamedRouteGenerator.new(SEED)
	var parts := []
	for coord in chunks_of(generator, region, 6):
		parts.append([coord, generator.chunk(coord)])
	return sha(parts)


## Office family: every office prop in the first maze chunks with the model and finish the view would load for it.
static func props_hash(prefix: String = "office") -> String:
	var generator := StreamedRouteGenerator.new(SEED)
	var parts := []
	for coord in chunks_of(generator, "maze", 10):
		var data := generator.chunk(coord)
		for list in ["region_props", "fixtures"]:
			for prop in data.get(list, []):
				var type := String(prop.get("type", ""))
				if type.begins_with(prefix):
					var id := String(prop.get("id", ""))
					var room_id := String(prop.get("room_id", ""))
					# collider_model_path: the gameplay pick, which the original-model look (PREFER_ORIGINAL_PROPS) does not move
					parts.append([type, id, PropModelCatalog.collider_model_path(type, id, room_id),
						PropModelCatalog.variant_theme(type, id, room_id)])
	return sha(parts)


## Hunters: the whole profile table in its order, plus 300 floor draws on every difficulty.
static func hunters_hash() -> String:
	var parts := [HunterRoster.PROFILES]
	for difficulty in ["relaxed", "standard", "hard", "nightmare"]:
		for i in 300:
			parts.append(HunterRoster.pick_for_floor("%s-%d" % [SEED, i], 1 + i % 9, difficulty))
	return sha(parts)


## Loot (lr.loot/1, res://data/loot): every pickup (id, cell, kind, item) of a 5x5 block of chunks on the surface levels,
## the sewers and the inferno, solo and co-op, for two seeds. Same hash before and after the loot tables moved to data.
static func loot_hash() -> String:
	var parts := []
	for world_seed in [SEED, "LOOT-PARITY-2"]:
		for coop in [false, true]:
			var generator := StreamedRouteGenerator.new(world_seed)
			generator.coop = coop
			for level in [0, 1, 2, -1, -2, -3]:
				for x in range(-2, 3):
					for z in range(-2, 3):
						var coord := Vector3i(x, level, z)
						if not generator.is_chunk_allowed(coord):
							continue
						parts.append([world_seed, coop, coord, generator.chunk(coord).get("pickups", [])])
	return sha(parts)


## Night Watch (NIGHT-WATCH-DATA-PLAN.md): every table a mode reads (the *_data scripts' constants, by name), the shift board's modes and
## calls, and every office's spec. Behaviour parity stays with each mode's own goldens (the Mask golden, the rules ports); this is the
## "the data the engines read did not change" proof for each migration commit.
const NW_DATA_SCRIPTS := ["res://game/night_watch/night_watch_data.gd", "res://game/night_watch/night_watch_modes_data.gd",
	"res://game/night_watch/night_watch_calls_data.gd", "res://game/night_watch/bedroom/bedroom_data.gd", "res://game/night_watch/dayshift/dayshift_data.gd",
	"res://game/night_watch/descent/descent_data.gd", "res://game/night_watch/lure/lure_data.gd", "res://game/night_watch/mask/mask_data.gd",
	"res://game/night_watch/mixed/mixed_data.gd", "res://game/night_watch/openair/openair_data.gd", "res://game/night_watch/story/story_data.gd"]

## Tables that moved from a const to a static var read from res://data/night_watch (file -> names).
const NW_DATA_TABLES := {"night_watch_calls_data.gd": ["CALLS"], "night_watch_modes_data.gd": ["MODES"],
	"night_watch_data.gd": ["NIGHT_MS", "HOUR_MS", "TIME_SCALE", "CAST", "ROOMS", "GRAPH", "COMBOS", "HUNTERS", "NYXIE_LEVELS", "NIGHTS",
		"TUNED_NIGHTS", "KATHY_NIGHT", "KATHY", "KATHY_DIP_CYCLE_MS", "KATHY_DIPS", "KATHY_MEET_ROOMS", "KATHY_MISS_LOCK_MS", "T_CLOSED_MS",
		"DOOR_GRACE_MS", "NIGHT_PACE", "LIGHT_PUSH_MS", "DOOR_CAPACITY", "FOCUS", "POWER_BASE", "POWER_PER_DEVICE"],
	"openair_data.gd": ["WATCH_MS"]}


static func nw_hash() -> String:
	var parts := []
	for path in NW_DATA_SCRIPTS:
		var script := load(path) as Script
		var constants := script.get_script_constant_map()
		var names := Array(constants.keys()).map(func(n): return String(n))   # StringName keys sort by pointer, not by name
		for name in NW_DATA_TABLES.get(path.get_file(), []):   # a table that moved to data is a static var: hashed in the same place
			if not names.has(name):
				names.append(name)
		names.sort()
		for name in names:
			var value = constants[name] if constants.has(name) else script.get(name)
			if typeof(value) != TYPE_OBJECT:
				parts.append([path.get_file(), name, value])
	var modes := NightWatchOfficeRegistry.OFFICES.keys()
	modes.sort()
	for mode_id in modes:
		var spec := NightWatchOfficeRegistry.spec_for(String(mode_id))
		if spec != null:
			parts.append([mode_id, spec.id, spec.footprint, spec.spawn, spec.entrances, spec.required_stations, spec.has_monitor, spec.mood,
				spec.tone_cue, spec.controls, spec.rotation])
	return sha(parts)
