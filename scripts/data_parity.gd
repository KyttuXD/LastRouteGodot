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
