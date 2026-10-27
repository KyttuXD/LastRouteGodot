extends RefCounted

## The four renamed hunters (old id -> lore-name id): the alias map is complete and correct, every load path migrates an old id, and
## no old id survives in the roster, the data tables or the asset folders. See docs/HUNTER_ID_ALIASES.md.
##
##   godot --headless --path . res://scenes/validate.tscn -- hunter_ids

const EXPECTED := {"eirys": "elise", "jyvra": "javelle", "quirith": "quenelle", "zephyra": "zellia"}
const GIMMICKS := {"elise": "EliseGimmick", "javelle": "JavelleGimmick", "quenelle": "QuenelleGimmick", "zellia": "ZelliaGimmick"}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	await host.get_tree().process_frame
	_expect(HunterIdAliases.ALIASES == EXPECTED, "the alias map must be exactly the four renames (%s)" % [HunterIdAliases.ALIASES])
	for old_id in EXPECTED:
		var new_id: String = EXPECTED[old_id]
		_expect(HunterIdAliases.canonical(old_id) == new_id and HunterIdAliases.canonical(new_id) == new_id, "%s -> %s" % [old_id, new_id])
		_expect(HunterRoster.PROFILES.has(new_id) and not HunterRoster.PROFILES.has(old_id), "the roster knows %s and not %s" % [new_id, old_id])
		_expect(HunterRoster.A_Z_IDS.has(new_id) and not HunterRoster.A_Z_IDS.has(old_id), "%s is in the A-Z list, %s is not" % [new_id, old_id])
		_expect(HunterRoster.get_identity(old_id) == HunterRoster.get_identity(new_id), "get_identity(%s) resolves to %s" % [old_id, new_id])
		_expect(HunterRoster.get_identity(old_id)["display_name"] == new_id.capitalize(), "%s shows as %s" % [new_id, new_id.capitalize()])
		# a brain built from an old id (an old snapshot or an older client) becomes the new hunter with the right gimmick
		var brain := HunterBrain.new(Vector2(5, 5), "ALIAS-%s" % old_id, old_id, "standard")
		_expect(brain.hunter_id == new_id, "a brain made from %s is %s" % [old_id, new_id])
		_expect(brain.gimmick != null and brain.gimmick.get_script().get_global_name() == GIMMICKS[new_id], "%s carries %s" % [new_id, GIMMICKS[new_id]])
		_expect(HunterGimmick.for_id(old_id) != null and HunterGimmick.for_id(old_id).get_script() == brain.gimmick.get_script(), "for_id(%s) is the same gimmick" % old_id)
		_expect(HunterDossier.entry(old_id) == HunterDossier.entry(new_id) and not HunterDossier.entry(new_id).is_empty(), "the dossier entry loads from %s" % old_id)
		_expect(DeathLines.file_id(old_id) == new_id, "death lines look up %s as %s" % [old_id, new_id])
		var lines: Dictionary = DeathLines.data().get("hunters", {})
		_expect(lines.is_empty() or (lines.has(new_id) and not lines.has(old_id)), "death_lines.json is keyed by %s" % new_id)
		# assets: current folder and model exist, the old ones are gone
		_expect(ResourceLoader.exists("res://assets/hunters_blocky/%s/%s.glb" % [new_id, new_id]), "the blocky model of %s exists" % new_id)
		_expect(not DirAccess.dir_exists_absolute("res://assets/hunters_blocky/%s" % old_id), "no %s model folder is left" % old_id)
		_expect(ResourceLoader.exists("res://art/props-3d/characters/%s.tscn" % new_id) and not ResourceLoader.exists("res://art/props-3d/characters/%s.tscn" % old_id), "the character scene is renamed for %s" % new_id)
		_expect(ResourceLoader.exists("res://assets/sprites/hunters/%s-front.png" % new_id), "the sprite of %s exists" % new_id)
	# lists and snapshots
	_expect(HunterIdAliases.canonical_list(["eirys", "kathy", "elise", "jyvra"]) == ["elise", "kathy", "javelle"], "canonical_list maps and de-duplicates (%s)" % [HunterIdAliases.canonical_list(["eirys", "kathy", "elise", "jyvra"])])
	var state := StreamedWorldState.new()
	var snapshot := {"schema": StreamedWorldState.SCHEMA, "hunters": {"a": {"hunter_id": "zephyra", "position": Vector2.ZERO}, "b": {"hunter_id": "kathy"}}}
	_expect(state.adopt(snapshot), "an old snapshot is adopted")
	_expect(String(state.hunters["a"]["hunter_id"]) == "zellia" and String(state.hunters["b"]["hunter_id"]) == "kathy", "the snapshot's stored hunter ids are migrated (%s)" % [state.hunters])
	# stride / emote / personality data use the new ids
	var table := HunterStride.table()
	for new_id in GIMMICKS:
		_expect(table.has(new_id) and not table.has(EXPECTED.keys()[EXPECTED.values().find(new_id)]), "the stride table is keyed by %s" % new_id)
	_expect(HunterEmotePersonality.weight("eirys", HunterEmoteCatalog.HUM) == 1.0 and HunterEmotePersonality.weight("elise", HunterEmoteCatalog.HUM) == 0.0, "the emote personality is keyed by the new id only")
	if _failures == 0:
		print("  ok    hunter_ids: four renames, alias map, every load path, no old ids in the roster, data or assets")
	return _failures
