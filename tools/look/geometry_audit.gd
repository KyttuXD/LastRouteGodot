extends Node

## Full geometry overlap sweep with the ranked report (GeometryAudit). Writes <out>/geometry_audit.json (every finding) and
## prints the counts table plus the top findings.
##
##   godot --headless --path . res://tools/look/geometry_audit.tscn -- OUTDIR [SEEDS=6] [PER_BIOME=6] [TAG=before]
##
## docs/GEOMETRY_AUDIT.md holds the before/after numbers.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "build/geometry"
	var seed_count := int(args[1]) if args.size() > 1 else 6
	var per_biome := int(args[2]) if args.size() > 2 else 6
	var tag: String = args[3] if args.size() > 3 else "run"
	GeometryAudit.strict = args.size() > 4 and String(args[4]) == "strict"
	DirAccess.make_dir_recursive_absolute(out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out_dir))
	var seeds := ["ENDLESS-ROUTE", "CITY-LOOK"]
	for i in seed_count:
		seeds.append("GEOM-%d" % i)
	var findings: Array = []
	var lr := GeometryAudit.sweep_last_route(seeds, per_biome, findings)
	var offices := 0
	for mode_id in NightWatchModesData.MODES.map(func(m): return String(m["id"])):
		if not NightWatchOfficeRegistry.built(mode_id):
			continue
		var office := NightWatchOfficeRegistry.make(mode_id)
		add_child(office)
		await get_tree().process_frame
		GeometryAudit.audit_office(NightWatchOfficeRegistry.office_id(mode_id), office.props, findings)
		office.queue_free()
		await get_tree().process_frame
		offices += 1
	print("geometry audit [%s]: %d chunks (%d props, biomes %s), %d offices" % [tag, lr["chunks"], lr["props"], str(lr["biomes"]), offices])
	print(GeometryAudit.report_text(findings, 60))
	var ranked := GeometryAudit.rank(findings)
	var file := FileAccess.open((out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out_dir)).path_join("geometry_audit_%s.json" % tag), FileAccess.WRITE)
	file.store_string(JSON.stringify({"counts": GeometryAudit.counts(findings), "findings": ranked}, "\t", false, true))
	file.close()
	get_tree().quit(0)
