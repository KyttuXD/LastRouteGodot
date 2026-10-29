extends RefCounted

## Headless check on the hunter roster.
##
## The draw is the part that fails quietly. A weighted pick with a tier nobody
## has implemented, or a hunter listed but unreachable, produces a game that
## runs perfectly and just never shows you half its cast -- and the only symptom
## is a feeling that you keep meeting the same hunter.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- roster

const SEEDS := 600

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(_host: Node) -> int:
	_character_sources_have_stable_layers()
	_everyone_has_a_face()
	_everyone_has_a_dossier_entry()
	_everyone_actually_renders()
	_the_pool_is_real()
	_the_draw_is_replayable()
	_the_draw_reaches_everyone()
	_the_draw_respects_its_tiers()
	_umbriel_can_wear_the_roster()
	_thessine_emits_authoritative_mimics()
	if _failures == 0:
		print("roster OK")
	return _failures


func _character_sources_have_stable_layers() -> void:
	var directory := DirAccess.open("res://art/props-3d/characters")
	_expect(directory != null, "character source directory is unavailable")
	if directory == null:
		return
	var broken_uvs := []
	var duplicate_layers := []
	var textured_caps := []
	var broken_void_atlases := []
	var checked_sources := 0
	var checked_void_sources := 0
	for filename in directory.get_files():
		if not filename.ends_with(".bbmodel"):
			continue
		checked_sources += 1
		if filename.begins_with("void_"):
			checked_void_sources += 1
		var path := "res://art/props-3d/characters/%s" % filename
		var file := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
		if not parsed is Dictionary:
			broken_uvs.append(filename)
			continue
		var names := {}
		if filename.begins_with("void_"):
			var textures: Array = (parsed as Dictionary).get("textures", [])
			var texture: Dictionary = textures[0] if not textures.is_empty() else {}
			var atlas_path := path.trim_suffix(".bbmodel") + "_0.png"
			var atlas_texture := load(atlas_path) as Texture2D
			var atlas := atlas_texture.get_image() if atlas_texture != null else null
			if atlas == null or atlas.is_empty() \
					or atlas.get_width() != int(texture.get("uv_width", 0)) \
					or atlas.get_height() != int(texture.get("uv_height", 0)):
				broken_void_atlases.append("%s (%dx%d source, %sx%s UV)" % [
					filename, atlas.get_width() if atlas != null else 0,
					atlas.get_height() if atlas != null else 0,
					texture.get("uv_width", 0), texture.get("uv_height", 0)])
		for value in (parsed as Dictionary).get("elements", []):
			var element: Dictionary = value
			var name := String(element.get("name", ""))
			names[name] = int(names.get(name, 0)) + 1
			var faces: Dictionary = element.get("faces", {})
			if name == "R-Arm" and not _uv_x_matches(faces, "south", 51.0, 54.0):
				broken_uvs.append("%s:R-Arm.back" % filename)
			if name == "L-Arm" and not _uv_x_matches(faces, "south", 43.0, 46.0):
				broken_uvs.append("%s:L-Arm.back" % filename)
			if name in ["Chest-Overlay", "Belly-Overlay", "Pelvis-Overlay",
					"R-Arm-Overlay", "R-Forearm-Overlay", "R-Hand-Overlay",
					"L-Arm-Overlay", "L-Forearm-Overlay", "L-Hand-Overlay",
					"R-Thigh-Overlay", "R-Calf-Overlay",
					"L-Thigh-Overlay", "L-Calf-Overlay"]:
				for face in ["up", "down"]:
					if faces.has(face) and faces[face].get("texture") != null:
						textured_caps.append("%s:%s.%s" % [filename, name, face])
		for name_value in names:
			if int(names[name_value]) > 1:
				duplicate_layers.append("%s:%s" % [filename, name_value])
	_expect(broken_uvs.is_empty(),
		"character arm-back UVs still sample the transparent slim-skin gutter: %s" \
		% ", ".join(broken_uvs))
	_expect(duplicate_layers.is_empty(),
		"character sources contain duplicate/coplanar layers: %s" \
		% ", ".join(duplicate_layers))
	_expect(textured_caps.is_empty(),
		"garment shells retain overlapping internal cap faces: %s" \
		% ", ".join(textured_caps))
	_expect(broken_void_atlases.is_empty(),
		"Void editor atlases do not match their packed UV dimensions: %s" \
		% ", ".join(broken_void_atlases))
	_expect(checked_void_sources == HunterRoster.VOID_IDS.size(),
		"Void UV/layer audit covered %d sources for %d hunters" % [
			checked_void_sources, HunterRoster.VOID_IDS.size()])
	if broken_uvs.is_empty() and duplicate_layers.is_empty() \
			and textured_caps.is_empty() and broken_void_atlases.is_empty():
		print("  source UVs %d Blockbench models stable, including %d Void hunters" % [
			checked_sources, checked_void_sources])


func _uv_x_matches(faces: Dictionary, face: String, expected_start: float,
		expected_end: float) -> bool:
	if not faces.has(face):
		return false
	var uv: Array = faces[face].get("uv", [])
	return uv.size() == 4 and is_equal_approx(float(uv[0]), expected_start) \
		and is_equal_approx(float(uv[2]), expected_end)


func _everyone_has_a_face() -> void:
	var missing: Array[String] = []
	for id in HunterRoster.PROFILES:
		var identity := HunterRoster.get_identity(id)
		if not ResourceLoader.exists(identity["model_scene"]):
			missing.append(id)
		_expect(String(identity["display_name"]) != "",
			"%s has no display name" % id)
		_expect(float(identity["chase_speed"]) > float(identity["base_speed"]),
			"%s chases slower than she walks" % id)
	_expect(missing.is_empty(), "no model for: %s" % ", ".join(missing))
	print("  profiles  %d hunters, each with tuning and a model"
		% HunterRoster.PROFILES.size())


func _everyone_has_a_dossier_entry() -> void:
	var missing: Array[String] = []
	for id in HunterRoster.PROFILES:
		var entry := HunterDossier.entry(id)
		if entry.is_empty() or String(entry.get("behavior", "")).is_empty():
			missing.append(id)
	for id in HunterDossier.ENTRIES:
		_expect(HunterRoster.PROFILES.has(id),
			"dossier contains unknown hunter '%s'" % id)
	_expect(missing.is_empty(), "no complete dossier entry for: %s" % ", ".join(missing))
	# ENTRIES is the 26 A-Z texts. Void hunters are in the dossier UI through the gimmick chart
	# (HunterDossier.entry / category_ids("void")), not by duplicating that copy into ENTRIES.
	_expect(HunterDossier.ENTRIES.size() == HunterRoster.A_Z_IDS.size(),
		"dossier ENTRIES covers %d hunters for a %d-hunter A-Z roster" % [
			HunterDossier.ENTRIES.size(), HunterRoster.A_Z_IDS.size()])
	_expect(HunterDossier.category_ids("az").size() == HunterRoster.A_Z_IDS.size(),
		"dossier A-Z section lists %d of %d" % [
			HunterDossier.category_ids("az").size(), HunterRoster.A_Z_IDS.size()])
	_expect(HunterDossier.category_ids("void").size() == HunterRoster.VOID_IDS.size(),
		"dossier Void section lists %d of %d" % [
			HunterDossier.category_ids("void").size(), HunterRoster.VOID_IDS.size()])
	for id in HunterRoster.PROFILES:
		var shown := HunterDossier.entry(id)
		_expect(not shown.has("ability") and not shown.has("gimmick_title"), "%s dossier shows a role title" % id)
		_expect(HunterDossier.portrait(id) != null, "%s has no dossier portrait" % id)
	print("  dossier  %d A-Z entries + %d Void chart entries" % [
		HunterDossier.ENTRIES.size(), HunterDossier.category_ids("void").size()])


## The Blockbench -> glTF export pipeline writes pixel-art materials as MASK,
## which Godot imports as alpha scissor. This must remain authored: transparent
## overlay texels reveal the base torso, and transparent wing/hair padding cuts
## out the silhouette. The old runtime opacity override turned Elise/Quenelle's
## overlay padding into solid black boxes. Load through ModelSlot exactly as the
## game does and confirm the imported masking survives.
func _everyone_actually_renders() -> void:
	var broken: Array[String] = []
	var empty: Array[String] = []
	var broken_void_runtime_atlases: Array[String] = []
	var mip_broken: Array[String] = []
	var fade_broken: Array[String] = []
	var masked_surfaces := 0
	for id in HunterRoster.PROFILES:
		var identity := HunterRoster.get_identity(id)
		var model := ModelSlot.instantiate(String(identity["model_scene"]))
		if model == null:
			empty.append(id)
			continue
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			empty.append(id)
		for node in meshes:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0:
				var material := mesh_instance.get_active_material(surface)
				if not material is StandardMaterial3D:
					if not broken.has(id):
						broken.append(id)
					continue
				var transparency := (material as StandardMaterial3D).transparency
				if HunterRoster.VOID_IDS.has(id):
					var atlas := (material as StandardMaterial3D).albedo_texture
					# old Void models pack a 64x96 atlas; the blocky ones stay within 128x256 (see blocky suite)
					var blocky_void := String(identity["model_scene"]).begins_with(HunterRoster.BLOCKY_DIR)
					if atlas == null \
							or (blocky_void and (atlas.get_width() > 128 or atlas.get_height() > 256)) \
							or (not blocky_void and (atlas.get_width() != 64 or atlas.get_height() != 96)):
						if not broken_void_runtime_atlases.has(id):
							broken_void_runtime_atlases.append(id)
				if transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					masked_surfaces += 1
					if (material as StandardMaterial3D).texture_filter \
							!= BaseMaterial3D.TEXTURE_FILTER_NEAREST \
							and not mip_broken.has(id):
						mip_broken.append(id)
				elif transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and not broken.has(id):
					broken.append(id)
		# The stealth/crouch fade used to leave MASK materials in place. The
		# remaining 0.38 alpha then failed the default 0.5 scissor and the
		# hunter vanished. The helper must lift scissor for the fade and put
		# authored MASK back when the hunter is fully visible again.
		if not ModelSlot.fade_survives_alpha_test(model, 0.0) and not fade_broken.has(id):
			fade_broken.append(id)
		ModelSlot.set_character_fade(model, .62)
		if not ModelSlot.fade_survives_alpha_test(model, .62) and not fade_broken.has(id):
			fade_broken.append(id)
		ModelSlot.set_character_fade(model, 0.0)
		if not ModelSlot.fade_survives_alpha_test(model, 0.0) and not fade_broken.has(id):
			fade_broken.append(id)
		# These inspection instances were never added to SceneTree. Free them
		# synchronously: deferring 26 imported scenes until the next suite's
		# render frame made the dummy renderer inspect already-released material
		# state and print a misleading material-null engine error.
		model.free()
	_expect(empty.is_empty(), "no meshes at all for: %s" % ", ".join(empty))
	_expect(broken.is_empty(),
		"character meshes have missing/unexpected material modes: %s" % ", ".join(broken))
	_expect(mip_broken.is_empty(),
		"alpha-scissor hunters still use mipmaps that discard atlas padding: %s" \
		% ", ".join(mip_broken))
	_expect(fade_broken.is_empty(),
		"hunter fade is still discarded by ALPHA_SCISSOR: %s" % ", ".join(fade_broken))
	_expect(broken_void_runtime_atlases.is_empty(),
		"Void runtime materials do not use their packed atlas (64x96, or within 128x256 for blocky): %s" \
		% ", ".join(broken_void_runtime_atlases))
	_expect(masked_surfaces > 0,
		"no character surface retained authored alpha masking")
	print("  materials %d surfaces retain authored alpha masks" % masked_surfaces)


## An id in the pool with no profile falls back to Dovelle's numbers and her
## model, so she would be Dovelle wearing a different name -- silently.
func _the_pool_is_real() -> void:
	for id in HunterRoster.IMPLEMENTED_IDS + HunterRoster.SPECIAL_IDS:
		if not HunterRoster.PROFILES.has(id):
			_fail("'%s' is drawn but has no profile" % id)
	for id in HunterRoster.SPECIAL_IDS:
		_expect(not HunterRoster.IMPLEMENTED_IDS.has(id),
			"%s is a special and must never be in the ordinary draw" % id)
		_expect(HunterGimmick.for_id(id) != null,
			"%s is summoned by a rule but has no gimmick to decide it" % id)

	# Every drawn hunter resolves a gimmick, except the baseline whose difference
	# really is only tuning. Without this, a gimmick that fails to compile --
	# a new class_name before an import pass registers it -- leaves for_id()
	# returning null for everyone, and the whole roster quietly plays Dovelle.
	var tuning_only := ["dovelle"] + HunterRoster.VOID_IDS
	var missing: Array[String] = []
	for id in HunterRoster.IMPLEMENTED_IDS:
		var has_gimmick := HunterGimmick.for_id(id) != null
		if tuning_only.has(id):
			_expect(not has_gimmick,
				"%s is listed as tuning-only but resolves a gimmick" % id)
		elif not has_gimmick:
			missing.append(id)
	_expect(missing.is_empty(),
		"drawn but plays as Dovelle -- no gimmick resolved: %s" % ", ".join(missing))


func _the_draw_is_replayable() -> void:
	for depth in [1, 2, 7]:
		var once := HunterRoster.pick_for_floor("SEED-A", depth)
		_expect(once == HunterRoster.pick_for_floor("SEED-A", depth),
			"the draw is not stable for one seed at depth %d" % depth)
	var by_depth := {}
	for depth in range(1, 25):
		by_depth[HunterRoster.pick_for_floor("SEED-A", depth)] = true
	_expect(by_depth.size() > 1, "one seed draws the same hunter at every depth")


## Every implemented hunter has to be reachable. A tier whose weight rounds it
## out of the draw is the failure this catches.
func _the_draw_reaches_everyone() -> void:
	var seen := {}
	for i in SEEDS:
		seen[HunterRoster.pick_for_floor("SEED-%d" % i, 1 + i % 5)] = true
	var unreachable: Array[String] = []
	for id in HunterRoster.IMPLEMENTED_IDS:
		if not seen.has(id):
			unreachable.append(id)
	_expect(unreachable.is_empty(),
		"never drawn across %d seeds: %s" % [SEEDS, ", ".join(unreachable)])
	for id in seen:
		_expect(HunterRoster.IMPLEMENTED_IDS.has(id),
			"the draw returned '%s', who is not in the pool" % id)


## The weights are over tiers, and a tier with nobody in it drops out and the
## rest renormalise. Without that, "difficult" -- the smallest share in the
## original -- takes whatever an empty tier leaves behind.
func _the_draw_respects_its_tiers() -> void:
	var present := {}
	for id in HunterRoster.IMPLEMENTED_IDS:
		present[HunterRoster.PROFILES[id]["tier"]] = true
	var report: Array[String] = []
	for difficulty_id in ["relaxed", "standard", "hard"]:
		var weights: Dictionary = HunterRoster.TIER_WEIGHTS_BY_DIFFICULTY[
			difficulty_id]
		var total := 0.0
		for tier in present:
			total += float(weights.get(tier, 0.0))

		var counted := {}
		for i in SEEDS:
			var tier: String = HunterRoster.PROFILES[HunterRoster.pick_for_floor(
				"TIER-%d" % i, 1, difficulty_id)]["tier"]
			counted[tier] = int(counted.get(tier, 0)) + 1

		var parts: Array[String] = []
		for tier in present:
			var want: float = float(weights.get(tier, 0.0)) / total
			var got := float(counted.get(tier, 0)) / float(SEEDS)
			parts.append("%s %.0f%%" % [tier, got * 100.0])
			# Wide, because this is a check on the weighting being APPLIED, not on
			# the quality of the RNG. A tier landing at half or double its share is
			# a bug in the draw; a few points either way is a sample.
			_expect(absf(got - want) < 0.10,
				"%s/%s hunters draw at %.0f%%, not the %.0f%% tier weight"
					% [difficulty_id, tier, got * 100.0, want * 100.0])
		parts.sort()
		report.append("%s: %s" % [difficulty_id, ", ".join(parts)])
	report.sort()
	print("  draw      %s across %d seeds each" % [" | ".join(report), SEEDS])


func _umbriel_can_wear_the_roster() -> void:
	var pool := HunterRoster.disguise_ids(GameConfig.UMBRIEL_DISGUISE_EXCLUDED)
	_expect(not pool.has("umbriel"), "Umbriel can disguise as herself")
	for id in HunterRoster.SPECIAL_IDS:
		_expect(not pool.has(id), "Umbriel can wear %s, who is a special" % id)
	for id in GameConfig.UMBRIEL_DISGUISE_EXCLUDED:
		_expect(not pool.has(id), "Umbriel can wear %s, who is excluded" % id)
	# The roster is complete now (26 of 26): every face in PROFILES has a
	# gimmick, so "at least one unfinished face in her pool" -- the proof this
	# check leaned on while the roster was still partial, to show she draws
	# from PROFILES and not from whoever happened to be finished -- is no
	# longer a claim that CAN be true, and asserting it would just be
	# asserting the roster is incomplete. What still has to hold is the
	# pool's actual composition: every profiled hunter, minus herself, the
	# specials, and whatever GameConfig excludes, and nothing else.
	var expected_size := HunterRoster.PROFILES.size() - 1 - HunterRoster.SPECIAL_IDS.size() \
		- GameConfig.UMBRIEL_DISGUISE_EXCLUDED.size()
	_expect(pool.size() == expected_size,
		"Umbriel's disguise pool is %d faces, not the %d PROFILES-minus-herself/specials/exclusions implies"
			% [pool.size(), expected_size])
	for id in pool:
		_expect(HunterRoster.PROFILES.has(id), "Umbriel's pool contains '%s', who has no profile at all" % id)
	print("  disguise  %d faces Umbriel can wear" % pool.size())


func _thessine_emits_authoritative_mimics() -> void:
	var brain := HunterBrain.new(Vector2.ZERO, "VALIDATE-THESSINE", "thessine")
	var gimmick := brain.gimmick as ThessineGimmick
	_expect(gimmick != null, "Thessine has no live audio-mimic gimmick")
	if gimmick == null:
		return
	# Repeated exact intervals exercise the seeded 50% roll without waiting in
	# real time. This seed and sequence are stable through SeededRandom.
	for interval in 32:
		gimmick.before_perception(brain, GameConfig.THESSINE_MIMIC_INTERVAL, {}, null)
	_expect(not brain.world_events.is_empty(),
		"Thessine completed 32 mimic checks without emitting a false cue")
	for event in brain.world_events:
		_expect(String(event.get("what", "")) == "thessine_mimic",
			"Thessine emitted a non-mimic world event")
		_expect(float(event.get("choice", -1.0)) >= 0.0 \
			and float(event.get("choice", 2.0)) < 1.0,
			"Thessine emitted an invalid synchronized cue choice")
	print("  mimic     %d synchronized false cues across 32 checks"
		% brain.world_events.size())
