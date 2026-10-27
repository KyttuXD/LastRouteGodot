extends RefCounted

## Geometry overlap audit (GeometryAudit, docs/GEOMETRY_AUDIT.md): solid-into-solid interpenetration, floating pieces, slivers
## and ceiling pokes across Last Route (every biome, several seeds), the City master plan and the Night Watch offices.
## RATCHET holds the findings that still exist per rule; a rule may only go down. Tool for the full ranked list with
## coordinates: tools/look/geometry_audit.tscn.
##
##   godot --headless --path . res://scenes/validate.tscn -- geometry_overlap

const SEEDS := ["GEOM-AUDIT-A", "GEOM-AUDIT-B", "ENDLESS-ROUTE"]
const CITY_SEEDS := ["CITY-LOOK", "GEOM-AUDIT-A", "GEOM-AUDIT-B", "GEOM-AUDIT-C"]
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
	var city := GeometryAudit.sweep_city(CITY_SEEDS, findings)
	var offices := await _audit_offices(host, findings)
	_audit_city_sky(host)
	_expect(int(lr["chunks"]) > 20, "only %d Last Route chunks swept" % int(lr["chunks"]))
	_expect(int(city["buildings"]) > 60, "only %d City buildings swept" % int(city["buildings"]))
	var table := GeometryAudit.counts(findings)
	for game in table:
		for rule in (table[game] as Dictionary):
			var allowed := int((RATCHET.get(game, {}) as Dictionary).get(rule, 0))
			_expect(int(table[game][rule]) <= allowed, "%s/%s: %d findings (allowed %d)" % [game, rule, table[game][rule], allowed])
	if _failures > 0:
		print(GeometryAudit.report_text(findings, 25))
	else:
		print("  geometry_overlap  %d chunks / %d props, %d cities / %d buildings / %d furniture, %d offices: %d findings (ratchet %s)" % [
			lr["chunks"], lr["props"], city["cities"], city["buildings"], city["decor"], offices, findings.size(), str(RATCHET)])
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


## Looking up in the City (KT's Ring Road report): the far skyline must be towers with windows ON them (no glowing quads
## in the air), there is no dome shell overhead, and a raised CitySurface box (tree canopy) is closed from below.
func _audit_city_sky(host: Node) -> void:
	var frame := CityDomeFrame.new()
	host.add_child(frame)
	var meshes := frame.find_children("*", "MeshInstance3D", true, false)
	_expect(meshes.size() == 2, "CityDomeFrame builds %d meshes (expected towers + windows, no dome shell)" % meshes.size())
	if meshes.size() == 2:
		var towers := _boxes((meshes[0] as MeshInstance3D).mesh)
		var floating := 0
		for window_box in _boxes((meshes[1] as MeshInstance3D).mesh):
			var centre: Vector3 = (window_box as AABB).get_center()
			var on_face := false
			for tower in towers:
				var grown := (tower as AABB).grow(.75)
				if grown.has_point(centre) and not (tower as AABB).grow(-.1).has_point(centre):
					on_face = true
					break
			if not on_face:
				floating += 1
		_expect(floating == 0, "%d skyline windows float off their tower" % floating)
	frame.queue_free()
	var surface := CitySurface.new()
	surface.box(Vector3(0, 2.5, 0), Vector3(1.7, .9, 1.7), 0)
	var normals: PackedVector3Array = surface.build().surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var underside := false
	for normal in normals:
		underside = underside or normal.y < -.99   # normals come back compressed, never exactly DOWN
	_expect(underside, "a raised CitySurface box has no underside")


## CityDomeFrame._Beams writes 5 quads (20 vertices) per box.
func _boxes(mesh: Mesh) -> Array:
	var out := []
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for start in range(0, vertices.size(), 20):
		var box := AABB(vertices[start], Vector3.ZERO)
		for index in range(start, mini(start + 20, vertices.size())):
			box = box.expand(vertices[index])
		out.append(box)
	return out
