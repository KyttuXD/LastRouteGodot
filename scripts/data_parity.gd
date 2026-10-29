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
					parts.append([type, id, PropModelCatalog.model_path(type, id, room_id),
						PropModelCatalog.variant_theme(type, id, room_id)])
	return sha(parts)


## Hunters: the whole profile table in its order, plus 300 floor draws on every difficulty.
static func hunters_hash() -> String:
	var parts := [HunterRoster.PROFILES]
	for difficulty in ["relaxed", "standard", "hard", "nightmare"]:
		for i in 300:
			parts.append(HunterRoster.pick_for_floor("%s-%d" % [SEED, i], 1 + i % 9, difficulty))
	return sha(parts)


## Night Watch (NIGHT-WATCH-DATA-PLAN.md): every table a mode reads (the *_data scripts' constants, by name), the shift board's modes and
## calls, and every office's spec. Behaviour parity stays with each mode's own goldens (the Mask golden, the rules ports); this is the
## "the data the engines read did not change" proof for each migration commit.
const NW_DATA_SCRIPTS := ["res://src/night_watch/night_watch_data.gd", "res://src/night_watch/night_watch_modes_data.gd",
	"res://src/night_watch/night_watch_calls_data.gd", "res://src/night_watch/bedroom/bedroom_data.gd", "res://src/night_watch/dayshift/dayshift_data.gd",
	"res://src/night_watch/descent/descent_data.gd", "res://src/night_watch/lure/lure_data.gd", "res://src/night_watch/mask/mask_data.gd",
	"res://src/night_watch/mixed/mixed_data.gd", "res://src/night_watch/openair/openair_data.gd", "res://src/night_watch/story/story_data.gd"]


static func nw_hash() -> String:
	var parts := []
	for path in NW_DATA_SCRIPTS:
		var constants := (load(path) as Script).get_script_constant_map()
		var names := constants.keys()
		names.sort()
		for name in names:
			if typeof(constants[name]) != TYPE_OBJECT:
				parts.append([path.get_file(), name, constants[name]])
	var modes := NightWatchOfficeRegistry.OFFICES.keys()
	modes.sort()
	for mode_id in modes:
		var spec := NightWatchOfficeRegistry.spec_for(String(mode_id))
		if spec != null:
			parts.append([mode_id, spec.id, spec.footprint, spec.spawn, spec.entrances, spec.required_stations, spec.has_monitor, spec.mood,
				spec.tone_cue, spec.controls, spec.rotation])
	return sha(parts)
