extends RefCounted

## Custom player skins (PlayerSkin): PNG validation edge cases, the base layer forced opaque with overlay alpha kept, a stable
## hash, the cache and the active skin, the UV mapping round-trip on the real mannequin (every vertex lands inside the skin layout,
## overlay shells only in overlay regions), and the skin reaching the body, the first-person hand and the settings tab.
##
##   godot --headless --path . res://scenes/validate.tscn -- player_skin

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _png(width: int, height: int, color: Color = Color(.3, .5, .8, 1.0)) -> PackedByteArray:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image.save_png_to_buffer()


func run(host: Node) -> int:
	await host.get_tree().process_frame
	var saved_hash := Settings.skin_hash

	# ---- validation edge cases
	_expect(not PlayerSkin.validate(PackedByteArray())["ok"], "an empty file was accepted")
	var huge := PackedByteArray(PlayerSkin.PNG_MAGIC)
	huge.resize(PlayerSkin.MAX_BYTES + 1)
	_expect(not PlayerSkin.validate(huge)["ok"], "an oversized file was accepted")
	_expect(String(PlayerSkin.validate(huge)["reason"]).contains("limit"), "the size refusal does not name the limit")
	var jpeg := PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0])
	_expect(not PlayerSkin.validate(jpeg)["ok"], "a JPEG was accepted")
	_expect(not PlayerSkin.validate(PackedByteArray([1, 2, 3]))["ok"], "three bytes were accepted")
	var good := _png(64, 64)
	_expect(PlayerSkin.validate(good)["ok"], "a plain 64x64 PNG was refused")
	var truncated := good.slice(0, good.size() / 2)
	_expect(not PlayerSkin.validate(truncated)["ok"], "a truncated PNG was accepted")
	var corrupted := good.duplicate()
	for i in range(40, mini(corrupted.size(), 80)):
		corrupted[i] = 0xFF
	_expect(not PlayerSkin.validate(corrupted)["ok"], "a PNG with a corrupted body was accepted")
	for size in [Vector2i(32, 32), Vector2i(64, 32), Vector2i(128, 128), Vector2i(63, 64), Vector2i(64, 65), Vector2i(1, 1)]:
		var refusal := PlayerSkin.validate(_png(size.x, size.y))
		_expect(not refusal["ok"] and String(refusal["reason"]).contains("exactly"), "a %dx%d image was accepted" % [size.x, size.y])
	# the file itself is never trusted by name or text: a PNG signature followed by script text is just a bad PNG
	var script := PackedByteArray(PlayerSkin.PNG_MAGIC)
	script.append_array("extends Node\nfunc _ready(): OS.execute('x', [])".to_utf8_buffer())
	_expect(not PlayerSkin.validate(script)["ok"], "PNG-signed script text was accepted")
	# grayscale / palette PNGs decode and are normalised
	var gray := Image.create(64, 64, false, Image.FORMAT_L8)
	gray.fill(Color(.5, .5, .5))
	_expect(PlayerSkin.validate(gray.save_png_to_buffer())["ok"], "a grayscale 64x64 PNG was refused")

	# ---- the base layer is forced opaque; the overlay keeps its alpha
	var ghost := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	ghost.fill(Color(1, 0, 0, 0))   # a fully transparent upload: nobody goes invisible
	var ghost_result := PlayerSkin.validate(ghost.save_png_to_buffer())
	_expect(ghost_result["ok"], "a fully transparent skin was refused instead of normalised")
	var ghost_image: Image = ghost_result["image"]
	var invisible := 0
	for y in 64:
		for x in 64:
			if not PlayerSkin.is_overlay_pixel(x, y) and ghost_image.get_pixel(x, y).a < 1.0:
				invisible += 1
	_expect(invisible == 0, "%d base pixels stayed transparent" % invisible)
	_expect(ghost_image.get_pixel(40, 5).a < .01 and ghost_image.get_pixel(20, 40).a < .01, "overlay alpha was not kept")
	var half := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	half.fill(Color(.2, .6, .2, 1.0))
	half.set_pixel(40, 5, Color(1, 1, 1, .5))      # hat
	half.set_pixel(20, 40, Color(1, 1, 1, .5))     # jacket
	half.set_pixel(10, 20, Color(1, 1, 1, .5))     # right leg BASE: must be forced opaque
	var half_image: Image = PlayerSkin.validate(half.save_png_to_buffer())["image"]
	_expect(absf(half_image.get_pixel(40, 5).a - .5) < .02 and absf(half_image.get_pixel(20, 40).a - .5) < .02, "overlay half alpha changed")
	_expect(half_image.get_pixel(10, 20).a == 1.0, "a base pixel kept half alpha")

	# ---- the hash
	var a := PlayerSkin.validate(good)
	var b := PlayerSkin.validate(good)
	_expect(a["hash"] == b["hash"] and PlayerSkin.valid_hash(String(a["hash"])), "the hash is not stable")
	_expect(PlayerSkin.validate(_png(64, 64, Color(.31, .5, .8, 1.0)))["hash"] != a["hash"], "two different skins share a hash")
	_expect(PlayerSkin.validate(PlayerSkin.template_png())["ok"], "the template does not validate")
	_expect(PlayerSkin.validate(PlayerSkin.default_image().save_png_to_buffer())["ok"], "the default skin does not validate")
	_expect(PlayerSkin.valid_hash(a["hash"]) and not PlayerSkin.valid_hash("xyz") and not PlayerSkin.valid_hash("../" + "a".repeat(61)), "valid_hash is wrong")

	# ---- cache + active skin
	var imported := PlayerSkin.import_bytes(good)
	_expect(imported["ok"] and Settings.skin_hash == String(a["hash"]), "import did not make the skin active")
	_expect(PlayerSkin.is_cached(String(a["hash"])) and PlayerSkin.load_cached(String(a["hash"])) != null, "the skin was not cached by hash")
	_expect(PlayerSkin.texture_for(String(a["hash"])) != PlayerSkin.default_texture(), "the cached skin resolves to the default texture")
	var bad_import := PlayerSkin.import_bytes(_png(32, 32))
	_expect(not bad_import["ok"] and Settings.skin_hash == String(a["hash"]), "a refused import changed the active skin")
	var tampered_file := FileAccess.open(PlayerSkin.cache_path(String(a["hash"])), FileAccess.WRITE)
	tampered_file.store_buffer(_png(64, 64, Color(.9, .1, .1, 1.0)))
	tampered_file.close()
	_expect(PlayerSkin.load_cached(String(a["hash"])) == null, "a tampered cache file was trusted")
	PlayerSkin.reset_active()
	_expect(Settings.skin_hash.is_empty() and PlayerSkin.active_texture() == PlayerSkin.default_texture(), "reset did not return to the default")
	Settings.skin_hash = "not-a-hash"
	Settings.set_skin_hash("not-a-hash")
	_expect(Settings.skin_hash.is_empty(), "the setting accepted a malformed hash")

	# ---- UV mapping round-trip on the real mannequin
	var scene := load(PlayerModels.BLOCKY.replace(".tscn", ".glb")) as PackedScene
	_expect(scene != null, "the mannequin glb did not load")
	if scene != null:
		var root := scene.instantiate()
		host.add_child(root)
		var base_rects := [Rect2(0, 0, 32, 16), Rect2(16, 16, 24, 16), Rect2(40, 16, 16, 16), Rect2(0, 16, 16, 16),
			Rect2(16, 48, 16, 16), Rect2(32, 48, 16, 16)]
		var meshes := 0
		var off_layout := 0
		var shell_in_base := 0
		var overlay_vertices := 0
		var base_vertices := 0
		var offenders := {}
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null:
				continue
			var shell := false
			for tag in ["sleeve", "pants", "jacket", "hat"]:
				shell = shell or String(mesh_node.name).to_lower().contains(tag)
			var plug := String(mesh_node.name).to_lower().contains("plug")
			for surface in mesh_node.mesh.get_surface_count():
				var arrays := mesh_node.mesh.surface_get_arrays(surface)
				var uvs = arrays[Mesh.ARRAY_TEX_UV]
				if not uvs is PackedVector2Array:
					continue
				meshes += 1
				var in_base_count := 0
				var in_overlay_count := 0
				for uv in uvs:
					var at := Vector2(uv.x * 64.0, uv.y * 64.0)
					var in_base := false
					for rect in base_rects:
						in_base = in_base or (rect as Rect2).grow(.6).has_point(at)
					var in_overlay := false
					for rect in PlayerSkin.OVERLAY_RECTS:
						in_overlay = in_overlay or Rect2(rect).grow(.6).has_point(at)
					if not (in_base or in_overlay):
						off_layout += 1
					elif in_base and not in_overlay:
						in_base_count += 1
					elif in_overlay and not in_base:
						in_overlay_count += 1
				if shell and in_base_count > 0:
					shell_in_base += in_base_count
				overlay_vertices += in_overlay_count
				base_vertices += in_base_count
		_expect(meshes > 0, "no mannequin mesh carries UVs")
		_expect(off_layout == 0, "%d mannequin vertices sit outside the skin layout" % off_layout)
		_expect(shell_in_base == 0, "%d overlay-shell vertices map into base regions" % shell_in_base)
		_expect(base_vertices > 0 and overlay_vertices > 0, "the mannequin maps both the base (%d) and the overlay layer (%d)" % [base_vertices, overlay_vertices])
		# applying a skin changes every textured surface of the model to it, leaving the model's materials alone
		var marker := PlayerSkin.validate(_png(64, 64, Color(.1, .9, .2, 1.0)))
		var marker_texture := ImageTexture.create_from_image(marker["image"])
		PlayerSkin.apply(root, marker_texture)
		var carrying := 0
		var stray := 0
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null:
				continue
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface) as StandardMaterial3D
				if material != null and material.albedo_texture == marker_texture:
					carrying += 1
				elif material != null and material.albedo_texture != null:
					stray += 1
		_expect(carrying > 0 and stray == 0, "the skin reached %d surfaces, %d textured surfaces kept the old one" % [carrying, stray])
		root.queue_free()

	# ---- the player's body and first-person hand wear the active skin; the settings tab exists
	var imported_skin := PlayerSkin.import_bytes(_png(64, 64, Color(.8, .2, .6, 1.0)))
	var player := load("res://src/game_3d/player_controller_3d.gd")
	_expect(player != null, "the player controller does not load")
	var settings_scene := load("res://scenes/settings_overlay.tscn") as PackedScene
	if settings_scene != null:
		var panel := settings_scene.instantiate()
		host.add_child(panel)
		await host.get_tree().process_frame
		var tabs := panel.find_child("SettingsCategoryTabs", true, false) as TabBar
		_expect(tabs != null and tabs.tab_count == 4 and tabs.get_tab_title(3) == "SKIN", "the settings panel has no SKIN tab")
		var section := panel.find_child("SkinSection", true, false) as SkinPanel
		_expect(section != null, "the SKIN section is missing")
		if section != null and tabs != null:
			tabs.current_tab = 3
			await host.get_tree().process_frame
			_expect(section.visible, "the SKIN section is hidden on its tab")
			tabs.current_tab = 0
			await host.get_tree().process_frame
			_expect(not section.visible, "the SKIN section shows on other tabs")
			# picking a bad file reports why and applies nothing; a good one previews, then applies
			var temp_dir := "user://skin_test"
			DirAccess.make_dir_recursive_absolute(temp_dir)
			var bad_path := temp_dir + "/bad.png"
			var f := FileAccess.open(bad_path, FileAccess.WRITE)
			f.store_buffer(_png(40, 40))
			f.close()
			var before := Settings.skin_hash
			section.pick_path(bad_path)
			_expect(Settings.skin_hash == before and section.status_label.text.contains("exactly"), "a bad pick was not refused with its reason (%s)" % section.status_label.text)
			var good_path := temp_dir + "/good.png"
			f = FileAccess.open(good_path, FileAccess.WRITE)
			f.store_buffer(_png(64, 64, Color(.2, .3, .9, 1.0)))
			f.close()
			section.pick_path(good_path)
			_expect(Settings.skin_hash == before and section.status_label.text.contains("APPLY"), "a pick applied before APPLY was pressed")
			var template_path := temp_dir + "/template.png"
			_expect(section.write_template(template_path) and PlayerSkin.validate(PlayerSkin.read_file(template_path))["ok"], "the saved template is not a valid skin")
		panel.queue_free()
	PlayerSkin.reset_active()
	if not saved_hash.is_empty():
		Settings.set_skin_hash(saved_hash)
	_expect(imported_skin["ok"], "the final import failed")

	if _failures == 0:
		print("  ok    player_skin: PNG validation edge cases, opaque base / overlay alpha, hash + cache + active skin, UV round-trip on the mannequin, settings tab")
	return _failures
