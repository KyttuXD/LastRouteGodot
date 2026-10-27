class_name HunterIdAliases
extends RefCounted

## Four hunters were renamed to their lore names and their internal ids followed (ids, files, classes, constants, data keys). Anything
## that outlives a build (saves, account data, snapshots, replicated state from an older client, room settings) can still carry an OLD id,
## so every place that LOADS an id runs it through canonical() first. This map is the only place the old ids still live
## (see docs/HUNTER_ID_ALIASES.md; the Node side has the same map in backend/hunter_id_aliases.mjs). Covered by suite `hunter_ids`.
const ALIASES := {
	"eirys": "elise",
	"jyvra": "javelle",
	"quirith": "quenelle",
	"zephyra": "zellia",
}


## The current id for `id` (anything that is not an old id comes back unchanged).
static func canonical(id: String) -> String:
	return String(ALIASES.get(id, id))


## A list of ids with every old id replaced (order kept, duplicates removed).
static func canonical_list(ids: Array) -> Array:
	var result: Array = []
	for value in ids:
		var id := canonical(String(value))
		if not result.has(id):
			result.append(id)
	return result


## `hunters` snapshot dictionaries ({entity id: {"hunter_id": ...}}): the stored ids are migrated in place.
static func migrate_hunter_entries(entries: Dictionary) -> void:
	for key in entries:
		var entry = entries[key]
		if entry is Dictionary and (entry as Dictionary).has("hunter_id"):
			(entry as Dictionary)["hunter_id"] = canonical(String(entry["hunter_id"]))
