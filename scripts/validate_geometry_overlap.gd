extends RefCounted

## Geometry overlap audit (GeometryAudit, docs/GEOMETRY_AUDIT.md): solid-into-solid interpenetration, floating pieces, slivers
## and ceiling pokes across Last Route (every biome, several seeds), the City master plan and the Night Watch offices.
## RATCHET holds the findings that still exist per rule; a rule may only go down. Tool for the full ranked list with
## coordinates: tools/look/geometry_audit.tscn.
##
##   godot --headless --path . res://scenes/validate.tscn -- geometry_overlap

const SEEDS := ["GEOM-AUDIT-A", "GEOM-AUDIT-B", "ENDLESS-ROUTE"]
const PER_BIOME := 3
## game -> rule -> allowed count in this sweep
const RATCHET := {}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var findings: Array = []
	var lr := GeometryAudit.sweep_last_route(SEEDS, PER_BIOME, findings)
	var sewer := GeometryAudit.sweep_sewers(SEEDS, 4, findings)
	var offices := await _audit_offices(host, findings)
	_expect(int(lr["chunks"]) > 20, "only %d Last Route chunks swept" % int(lr["chunks"]))
	var table := GeometryAudit.counts(findings)
	for game in table:
		for rule in (table[game] as Dictionary):
			var allowed := int((RATCHET.get(game, {}) as Dictionary).get(rule, 0))
			_expect(int(table[game][rule]) <= allowed, "%s/%s: %d findings (allowed %d)" % [game, rule, table[game][rule], allowed])
	if _failures > 0:
		print(GeometryAudit.report_text(findings, 25))
	else:
		print("  geometry_overlap  %d chunks / %d props, %d offices: %d findings (ratchet %s)" % [
			lr["chunks"], lr["props"], offices, findings.size(), str(RATCHET)])
	return _failures


func _audit_offices(host: Node, findings: Array) -> int:
	var built := 0
	for mode_id in NightWatchModesData.MODES.map(func(m): return String(m["id"])):
		if not NightWatchOfficeRegistry.built(mode_id):
			continue
		var office := NightWatchOfficeRegistry.make(mode_id)
		host.add_child(office)
		await host.get_tree().process_frame
		GeometryAudit.audit_office(NightWatchOfficeRegistry.office_id(mode_id), office.props, findings)
		office.queue_free()
		await host.get_tree().process_frame
		built += 1
	return built
