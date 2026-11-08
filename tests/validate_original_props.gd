extends RefCounted

## PropModelCatalog.PREFER_ORIGINAL_PROPS (docs/ORIGINAL_PROPS.md): the detailed original prop models are DRAWN where a type has
## one and it passes the screen; gameplay keeps reading the blocky models. This suite locks:
##   - the switch: on/off, the const is the default, off is exactly the old all-blocky pick;
##   - determinism: the choice depends only on (type, id, room, finish), never on call order or earlier calls;
##   - every chosen path exists, instantiates, has a mesh, and merges to a handful of draws; room doors always stay blocky;
##   - the deny list is honoured, has a valid reason on every row, and the rows that say "fit" or "heavy" are still true
##     (and every type that is drawn original still passes the same screen) -- tools/props/original_fit_report.gd;
##   - hiding props, VARIANT_BOXES types, multi-seat furniture and interactive anchors can never be drawn original;
##   - finishes and coordinated sets: a region finish keeps its blocky finished set and the coordinated families, and the
##     original members of one family share one finish index inside a room;
##   - model choice is presentation only: for every type and for generated worlds, the generated chunks, the colliders
##     (PropColliderBoxes.for_prop, CollisionWorld, the 3D view's own box lookup) are identical with the switch on and off.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- original_props

const Report := preload("res://tools/props/original_fit_report.gd")
const SEEDS := ["ORIG-A", "ORIG-B"]
## draws (mesh surfaces) a drawn original may need after PropMeshMerge; the screen keeps only models that merge flat
const MAX_ORIGINAL_SURFACES := 3
const BLOCKY_DIR := "res://assets/props/blocky/"
## sample room ids per coordinated family check
const ROOMS := 160

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _dual_types() -> Array:
	var out := []
	for type in PropModelCatalog.MODEL_PATHS:
		if not PropModelCatalog.original_paths(type).is_empty() and BlockyPropModels.MODELS.has(type):
			out.append(String(type))
	out.sort()
	return out


func _drawn_original() -> Array:
	var out := []
	for type in _dual_types():
		if PropModelCatalog.prefers_original(type):
			out.append(type)
	return out


func _ids_for(type: String) -> Array:
	var out := []
	for i in 24:
		out.append({"id": "chunk-%d-0-%d-prop-%d-%s" % [i % 5 - 2, i / 5, i, type], "room": "room-%d-%s" % [i * 7, type[0]]})
	out.append({"id": "chunk-0-0-0-prop-9-%s" % type, "room": ""})
	return out


## The pick PropModelCatalog.model_path made before the switch existed, rebuilt from the tables.
func _legacy_path(type: String, id: String, room: String, finish: String) -> String:
	var paths: Array = PropModelCatalog.MODEL_PATHS.get(type, [])
	if paths.is_empty():
		return ""
	if not ContentRegistry.pack_of("props", type).is_empty():
		return String(paths[PropModelCatalog._variant_index(type, id, room, paths.size())])
	if not finish.is_empty() and BlockyPropModels.MODELS.has(type + finish):
		var finished: Array = BlockyPropModels.MODELS[type + finish]
		return String(finished[PropModelCatalog._variant_index(type, id, room, finished.size())])
	if BlockyPropModels.MODELS.has(type):
		var blocky: Array = BlockyPropModels.MODELS[type]
		return String(blocky[PropModelCatalog._variant_index(type, id, room, blocky.size())])
	return String(paths[PropModelCatalog._variant_index(type, id, room, paths.size())])


func _check_switch() -> void:
	_expect(PropModelCatalog.PREFER_ORIGINAL_PROPS, "PREFER_ORIGINAL_PROPS is meant to ship on")
	_expect(PropModelCatalog.prefer_original_props == PropModelCatalog.PREFER_ORIGINAL_PROPS, "the run-time switch does not start at the const")
	_expect(PropModelCatalog.MAX_ORIGINAL_TRIS > 0, "no triangle cap")
	var dual := _dual_types()
	var drawn := _drawn_original()
	_expect(dual.size() > 150, "too few types have both an original and a blocky model (%d)" % dual.size())
	_expect(drawn.size() > 80, "too few types draw the original (%d of %d): the preference does nothing" % [drawn.size(), dual.size()])
	metrics["dual"] = dual.size()
	metrics["drawn_original"] = drawn.size()
	var checked := 0
	var sample := 0
	for type in PropModelCatalog.MODEL_PATHS:
		for entry in _ids_for(type):
			var id := String(entry["id"])
			var room := String(entry["room"])
			for finish in ["", "Mansion"]:
				PropModelCatalog.prefer_original_props = false
				var off := PropModelCatalog.model_path(type, id, room, finish)
				var collider := PropModelCatalog.collider_model_path(type, id, room, finish)
				PropModelCatalog.prefer_original_props = true
				var on := PropModelCatalog.model_path(type, id, room, finish)
				var legacy := _legacy_path(type, id, room, finish)
				checked += 1
				if off != legacy or collider != legacy:
					_expect(false, "%s %s/%s: switch off or the collider pick is not the old pick (%s / %s vs %s)" % [type, id, finish, off, collider, legacy])
					return
				if on != collider:
					sample += 1
					# a changed pick is the original of a type that draws it, outside a coordinated family's finished region
					_expect(PropModelCatalog.prefers_original(type, finish) and PropModelCatalog.original_paths(type).has(on),
						"%s: the pick changed to %s but the type does not draw the original" % [type, on])
	PropModelCatalog.prefer_original_props = true
	metrics["picks_checked"] = checked
	metrics["picks_changed"] = sample
	_expect(sample > 1000, "the switch changed only %d picks" % sample)


func _check_determinism() -> void:
	var drawn := _drawn_original()
	var first := {}
	for type in drawn:
		for entry in _ids_for(type):
			first["%s|%s|%s" % [type, entry["id"], entry["room"]]] = PropModelCatalog.model_path(type, String(entry["id"]), String(entry["room"]))
	# again in the opposite order, with unrelated calls in between: same answers
	var keys := first.keys()
	keys.reverse()
	for key in keys:
		var parts := String(key).split("|")
		PropModelCatalog.model_path("woodenChair", "noise-%s" % parts[1], parts[2])
		PropModelCatalog.collider_model_path(parts[0], "noise2", parts[2])
		_expect(PropModelCatalog.model_path(parts[0], parts[1], parts[2]) == first[key], "%s: the pick changed between calls" % key)
	# the pick spreads over the variants (it is a hash of the room/id, not constant)
	var flat := []
	for type in drawn:
		if PropModelCatalog.original_paths(type).size() < 3:
			continue
		var seen := {}
		for entry in _ids_for(type):
			seen[PropModelCatalog.model_path(type, String(entry["id"]), String(entry["room"]))] = true
		if seen.size() < 2:
			flat.append(type)
	_expect(flat.is_empty(), "originals with 3+ variants that never vary with the room: %s" % [flat])


func _check_paths_exist() -> void:
	var paths := {}
	for type in _drawn_original():
		for path in PropModelCatalog.original_paths(type):
			paths[String(path)] = type
	var meshless := []
	var heavy_draws := []
	var missing := []
	var draws_max := 0
	var nodes_before := 0
	for path in paths:
		var type: String = paths[path]
		if not ResourceLoader.exists(String(path)):
			missing.append(path)
			continue
		var visual := ModelSlot.instantiate_prop(String(path), type)
		if visual == null:
			missing.append(path)
			continue
		var meshes := visual.find_children("*", "MeshInstance3D", true, false)
		nodes_before += meshes.size()
		if meshes.is_empty():
			meshless.append(path)
		PropMeshMerge.merge(visual, type, String(path))
		var surfaces := 0
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh != null and mesh_node.visible:
				surfaces += mesh_node.mesh.get_surface_count()
		draws_max = maxi(draws_max, surfaces)
		if surfaces > MAX_ORIGINAL_SURFACES and not PropModelCatalog.is_room_door(type):
			heavy_draws.append("%s (%d draws)" % [String(path).get_file(), surfaces])
		visual.free()
	metrics["original_models_drawn"] = paths.size()
	metrics["original_draws_max"] = draws_max
	_expect(missing.is_empty(), "drawn originals that do not load: %s" % [missing.slice(0, 6)])
	_expect(meshless.is_empty(), "drawn originals without a mesh: %s" % [meshless.slice(0, 6)])
	_expect(heavy_draws.is_empty(), "drawn originals that need more than %d draws after the merge: %s" % [MAX_ORIGINAL_SURFACES, heavy_draws.slice(0, 6)])
	# the blocky twin of every type (the fallback, the colliders' source) loads too
	for type in BlockyPropModels.MODELS:
		var list: Array = BlockyPropModels.MODELS[type]
		_expect(not list.is_empty() and ResourceLoader.exists(String(list[0])), "%s: blocky model missing" % type)


func _check_doors() -> void:
	# room doors stay blocky: the header walls, the widened double doors and the hunters' doorway clearance read the frame
	var doors := 0
	for type in PropModelCatalog.MODEL_PATHS:
		if PropModelCatalog.is_room_door(type) and BlockyPropModels.MODELS.has(type):
			doors += 1
			_expect(String(PropModelCatalog.ORIGINAL_DENY.get(type, "")) == "door_frames", "room door %s must be denied as 'door_frames'" % type)
			_expect(not PropModelCatalog.prefers_original(type), "room door %s draws an original" % type)
	_expect(doors >= 6, "expected the six room doors, found %d" % doors)
	metrics["room_doors_blocky"] = doors


func _check_deny_list() -> void:
	var reasons: Dictionary = PropModelCatalog.ORIGINAL_DENY_REASONS
	var by_reason := {}
	for type in PropModelCatalog.ORIGINAL_DENY:
		var code := String(PropModelCatalog.ORIGINAL_DENY[type])
		_expect(reasons.has(code), "%s: unknown deny reason %s" % [type, code])
		_expect(PropModelCatalog.MODEL_PATHS.has(type), "%s is on the deny list but is not a prop type" % type)
		by_reason[code] = int(by_reason.get(code, 0)) + 1
		_expect(not PropModelCatalog.prefers_original(type), "%s is denied but prefers the original" % type)
		_expect(not PropModelCatalog.original_paths(type).is_empty() and BlockyPropModels.MODELS.has(type),
			"%s is denied but has no original/blocky pair (the row does nothing)" % type)
		for entry in _ids_for(type):
			var id := String(entry["id"])
			_expect(PropModelCatalog.model_path(type, id, String(entry["room"])) == PropModelCatalog.collider_model_path(type, id, String(entry["room"])),
				"%s: a denied type draws something other than its blocky model" % type)
			break
	metrics["deny_by_reason"] = by_reason
	# hard exclusions, from the code that depends on the blocky model
	for type in StreamedRouteGenerator.HIDING_PROP_STYLES:
		if BlockyPropModels.MODELS.has(type) and not PropModelCatalog.original_paths(type).is_empty():
			_expect(String(PropModelCatalog.ORIGINAL_DENY.get(type, "")) == "hiding", "hiding prop %s must be denied as 'hiding'" % type)
	for type in PropColliderSizes.VARIANT_BOXES:
		_expect(not PropModelCatalog.prefers_original(type), "%s has per-variant collider boxes, so it must stay blocky" % type)
		_expect(PropModelCatalog.ORIGINAL_DENY.has(type), "%s (VARIANT_BOXES) is not on the deny list" % type)
	for type in PropModelCatalog.SEAT_COUNTS:
		if int(PropModelCatalog.SEAT_COUNTS[type]) > 1:
			_expect(not PropModelCatalog.prefers_original(type), "multi-seat %s must stay blocky" % type)
	for type in PropModelCatalog.SEAT_ROWS:
		_expect(not PropModelCatalog.prefers_original(type), "seat-row %s must stay blocky" % type)
	for type in _drawn_original():
		var act := PropModelCatalog.interaction_for(type)
		_expect(not (act in ["play", "ride", "use", "music", "lay"]), "%s (%s) draws an original" % [type, act])
		_expect(not PropColliderSizes.VARIANT_BOXES.has(type), "%s draws an original but has per-variant boxes" % type)
	# a type with no blocky twin, a pack prop and the original-only types are untouched by the switch
	for type in PropModelCatalog.MODEL_PATHS:
		if not BlockyPropModels.MODELS.has(type):
			_expect(not PropModelCatalog.prefers_original(type), "%s has no blocky twin; nothing to prefer" % type)
	_expect(not PropModelCatalog.prefers_original("noSuchType"), "an unknown type prefers the original")


## Every drawn original passes the screen, and every "fit"/"heavy" row is still true.
func _check_screen() -> void:
	var drawn := 0
	var tris_o := 0.0
	var tris_b := 0.0
	var fit_worst := 0.0
	for type in _dual_types():
		var row := Report.row(type)
		_expect(not row.is_empty(), "%s: could not be measured" % type)
		if row.is_empty():
			continue
		var verdict := Report.verdict(row)
		var code := String(PropModelCatalog.ORIGINAL_DENY.get(type, ""))
		if PropModelCatalog.prefers_original(type):
			drawn += 1
			_expect(verdict == "", "%s draws its original but fails the screen (%s): footprint dev %.2f m, top %+.2f m, %d tris vs %.0f blocky" % [
				type, verdict, row["dev"], row["dtopb"], row["o_max"], row["b_mean"]])
			var mean_o := 0.0
			for t in row["o_tris"]:
				mean_o += float(t) / (row["o_tris"] as Array).size()
			tris_o += mean_o
			tris_b += float(row["b_mean"])
			fit_worst = maxf(fit_worst, float(row["dev"]))
			_expect(int(row["o_max"]) <= PropModelCatalog.MAX_ORIGINAL_TRIS or float(row["o_max"]) <= float(row["b_mean"]),
				"%s: %d triangles is over the cap" % [type, row["o_max"]])
		elif code == "fit" or code == "heavy":
			_expect(verdict == code, "%s is denied as '%s' but now measures '%s': update ORIGINAL_DENY" % [type, code, verdict])
	_expect(drawn > 80, "only %d types pass the screen" % drawn)
	metrics["screen_drawn"] = drawn
	metrics["mean_tris_original"] = snappedf(tris_o / maxf(1.0, drawn), 1.0)
	metrics["mean_tris_blocky"] = snappedf(tris_b / maxf(1.0, drawn), 1.0)
	metrics["worst_fit_m"] = snappedf(fit_worst, 0.01)
	# the originals that are drawn average no more than 3x the blocky triangle count (ratchet; measured 2.95x per type, the whole catalogue is ~3.2x)
	_expect(tris_o <= tris_b * 3.0, "drawn originals average %.0f triangles against %.0f blocky" % [tris_o / drawn, tris_b / drawn])


func _check_coordinated_sets() -> void:
	# families = types sharing one ordered VARIANT_THEMES array
	var families := {}
	for type in PropModelCatalog.COORDINATED_SET_TYPES:
		if not PropModelCatalog.VARIANT_THEMES.has(type):
			continue
		var family_key := var_to_str(PropModelCatalog.VARIANT_THEMES[type])
		families[family_key] = families.get(family_key, []) + [type]
	var rooms_checked := 0
	var families_with_originals := 0
	for key in families:
		var members: Array = families[key]
		var drawn := members.filter(func(t): return PropModelCatalog.prefers_original(String(t)))
		if drawn.size() >= 2:
			families_with_originals += 1
		for r in ROOMS:
			var room := "room-%d-%s" % [r * 13, key.hash()]
			var labels := {}
			for type in drawn:
				var paths := PropModelCatalog.original_paths(type)
				var themes: Array = PropModelCatalog.VARIANT_THEMES[type]
				_expect(paths.size() == themes.size(), "%s: %d originals but %d theme labels" % [type, paths.size(), themes.size()])
				for id in ["chunk-1-1-%d-prop-%d-%s" % [r, 3, type], "chunk-2-0-%d-prop-%d-%s" % [r, 11, type]]:
					var path := PropModelCatalog.model_path(type, id, room)
					var index := paths.find(path)
					_expect(index >= 0, "%s: %s is not one of the originals" % [type, path])
					if index >= 0 and index < themes.size():
						labels[themes[index]] = true
						_expect(String(themes[index]) == PropModelCatalog.variant_theme(type, id, room), "%s: drawn finish %s is not variant_theme %s" % [type, themes[index], PropModelCatalog.variant_theme(type, id, room)])
				# same pick whether the room is known or the prop id carries it (coordinated set rule)
				var by_id := PropModelCatalog.model_path(type, "chunk-%d-prop-%d" % [r, 4])
				_expect(paths.has(by_id), "%s: a room-less pick left the originals" % type)
			_expect(labels.size() <= 1, "room %s: coordinated originals mix finishes %s" % [room, labels.keys()])
			rooms_checked += 1
	metrics["family_rooms_checked"] = rooms_checked
	_expect(families_with_originals >= 2, "fewer than two coordinated families draw their originals together (%d)" % families_with_originals)
	# in a region with a finish, the finished blocky sets and the coordinated families keep the room's one palette
	for region in PropModelCatalog.REGION_FINISHES:
		var finish := PropModelCatalog.region_finish(region)
		for type in PropModelCatalog.MODEL_PATHS:
			if BlockyPropModels.MODELS.has(type + finish) or PropModelCatalog.COORDINATED_SET_TYPES.has(type):
				_expect(not PropModelCatalog.prefers_original(type, finish), "%s must stay blocky in the %s region (finish %s)" % [type, region, finish])
				for entry in _ids_for(type).slice(0, 4):
					_expect(PropModelCatalog.model_path(type, String(entry["id"]), String(entry["room"]), finish) \
						== PropModelCatalog.collider_model_path(type, String(entry["id"]), String(entry["room"]), finish),
						"%s: the %s finish changed with the original preference" % [type, finish])
	var save := PropModelCatalog.use_region_finishes
	PropModelCatalog.use_region_finishes = false
	for type in _drawn_original():
		if PropModelCatalog.COORDINATED_SET_TYPES.has(type):
			_expect(PropModelCatalog.prefers_original(type, "Mansion"), "%s with finishes off should draw the original" % type)
			break
	PropModelCatalog.use_region_finishes = save


## The generated world and every collider are identical with the preference on and off.
func _check_gameplay_invariance() -> void:
	# 1. per type and variant, synthetic ids: variant_of / boxes do not follow the drawn model, and the 3D view's own lookup
	#    (variant_paths(type).find(drawn path)) gives the same boxes as CollisionWorld's
	var types_checked := 0
	var view_lookups_that_differ := 0
	for type in PropModelCatalog.MODEL_PATHS:
		var size: Vector3 = PropColliderSizes.SIZES.get(type, Vector3(1, 1, 1))
		for entry in _ids_for(type):
			var prop := {"type": type, "id": entry["id"], "room_id": entry["room"], "collider_size": size}
			PropModelCatalog.prefer_original_props = false
			var off_variant := PropColliderBoxes.variant_of(prop)
			var off_boxes := var_to_str(PropColliderBoxes.for_prop(prop))
			var off_paths := var_to_str(PropColliderBoxes.variant_paths(type))
			PropModelCatalog.prefer_original_props = true
			var on_variant := PropColliderBoxes.variant_of(prop)
			var on_boxes := var_to_str(PropColliderBoxes.for_prop(prop))
			_expect(off_variant == on_variant, "%s: collider variant follows the switch (%d vs %d)" % [type, off_variant, on_variant])
			_expect(off_boxes == on_boxes, "%s: collider boxes follow the switch" % type)
			_expect(off_paths == var_to_str(PropColliderBoxes.variant_paths(type)), "%s: variant_paths follows the switch" % type)
			# the 3D view's own lookup (streamed_facility_view_3d: variant_paths(type).find(drawn path)) with the switch on, against
			# what it did with it off, and against CollisionWorld's
			var drawn := PropModelCatalog.model_path(type, String(entry["id"]), String(entry["room"]))
			var view := var_to_str(PropColliderBoxes.boxes(type, size, PropColliderBoxes.variant_paths(type).find(drawn)))
			var drawn_off := PropModelCatalog.collider_model_path(type, String(entry["id"]), String(entry["room"]))
			var view_off := var_to_str(PropColliderBoxes.boxes(type, size, PropColliderBoxes.variant_paths(type).find(drawn_off)))
			_expect(view == view_off, "%s: the 3D view's collider boxes change with the switch (drawn %s)" % [type, drawn.get_file()])
			if view != on_boxes:
				view_lookups_that_differ += 1
				_expect(false, "%s: the 3D view's box lookup differs from CollisionWorld's (drawn %s)" % [type, drawn.get_file()])
				break
		types_checked += 1
	PropModelCatalog.prefer_original_props = true
	metrics["collider_types_checked"] = types_checked
	# 2. generated worlds: the chunk dictionaries (grid, props, ids, yaw, cells, footprints, collider sizes) are byte-identical
	var chunks := 0
	var props := 0
	var solid := 0
	var differing := 0
	var preexisting := 0
	for seed_text in SEEDS:
		var on_gen := StreamedRouteGenerator.new(String(seed_text))
		var off_gen := StreamedRouteGenerator.new(String(seed_text))
		var per_region := {}
		for z in range(-9, 10):
			for x in range(-9, 10):
				var coord := Vector3i(x, 0, z)
				var region := on_gen.region_for(coord)
				if int(per_region.get(region, 0)) >= 2 or not on_gen.is_chunk_allowed(coord):
					continue
				per_region[region] = int(per_region.get(region, 0)) + 1
				PropModelCatalog.prefer_original_props = true
				var data_on := on_gen.chunk(coord)
				PropModelCatalog.prefer_original_props = false
				var data_off := off_gen.chunk(coord)
				PropModelCatalog.prefer_original_props = true
				chunks += 1
				if var_to_str(data_on) != var_to_str(data_off):
					differing += 1
					_expect(false, "chunk %s of %s differs with the preference on and off" % [coord, seed_text])
					continue
				var finish := PropModelCatalog.region_finish(String(data_on.get("region", region)))
				for prop_value in data_on.get("region_props", []):
					var prop: Dictionary = prop_value
					props += 1
					var type := String(prop.get("type", ""))
					if not bool(prop.get("solid", true)):
						continue
					solid += 1
					PropModelCatalog.prefer_original_props = false
					var off_boxes := var_to_str(PropColliderBoxes.for_prop(prop))
					PropModelCatalog.prefer_original_props = true
					var on_boxes := var_to_str(PropColliderBoxes.for_prop(prop))
					_expect(off_boxes == on_boxes, "%s %s: collider boxes follow the switch" % [type, prop.get("id", "")])
					# the view's own lookup, with the path it really draws (finish included)
					var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
					var drawn := PropModelCatalog.model_path(type, String(prop.get("id", "")), String(prop.get("room_id", "")), finish)
					var view := var_to_str(PropColliderBoxes.boxes(type, size, PropColliderBoxes.variant_paths(type).find(drawn)))
					var drawn_off := PropModelCatalog.collider_model_path(type, String(prop.get("id", "")), String(prop.get("room_id", "")), finish)
					var view_off := var_to_str(PropColliderBoxes.boxes(type, size, PropColliderBoxes.variant_paths(type).find(drawn_off)))
					_expect(view == view_off, "%s %s: the 3D view would build different collider boxes with the switch on (%s)" % [type, prop.get("id", ""), drawn.get_file()])
					if view_off != on_boxes:
						# not caused by the switch: a region finish draws "<type>Mansion", which is not in variant_paths(), so the view's
						# lookup gives -1 (the union box) where CollisionWorld uses the variant's own (VARIANT_BOXES types only)
						preexisting += 1
	PropModelCatalog.prefer_original_props = true
	metrics["view_vs_world_preexisting"] = preexisting
	metrics["chunks_compared"] = chunks
	metrics["props_compared"] = props
	metrics["solid_props_compared"] = solid
	_expect(chunks >= 20 and solid > 200, "too small a sample (%d chunks, %d solid props)" % [chunks, solid])
	# 3. has_model, the placement gate, does not look at the look
	for type in PropModelCatalog.MODEL_PATHS:
		PropModelCatalog.prefer_original_props = false
		var off := PropModelCatalog.has_model(type)
		PropModelCatalog.prefer_original_props = true
		_expect(off == PropModelCatalog.has_model(type), "%s: has_model follows the switch" % type)
	PropModelCatalog.prefer_original_props = true


func run(_host: Node) -> int:
	_check_switch()
	_check_determinism()
	_check_deny_list()
	_check_screen()
	_check_coordinated_sets()
	_check_paths_exist()
	_check_doors()
	_check_gameplay_invariance()
	PropModelCatalog.prefer_original_props = PropModelCatalog.PREFER_ORIGINAL_PROPS
	if _failures == 0:
		print("  original_props  %s" % [metrics])
	return _failures
