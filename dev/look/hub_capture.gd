extends Node

## Screenshots the arrow carousel hub at every common window size (each a SubViewport with the real expand-stretch rule):
## 3 games with the middle one focused (both neighbours peek where they fit), and the real registry at 1280x720.
##   godot --path . res://dev/look/hub_capture.tscn -- OUTDIR
func _ready() -> void:
	Build.capture_rig = true
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	var sizes := {
		"1280x720": Vector2i(1280, 720), "1440x840": Vector2i(1440, 840), "1920x1080": Vector2i(1920, 1080),
		"2560x1440": Vector2i(2560, 1440), "ultrawide3440x1440": Vector2i(3440, 1440), "phone844x390": Vector2i(844, 390),
	}
	# the City is not registered on every branch: show it as a third card so the capture always has neighbours
	var real: Array = GameRegistry.GAMES.duplicate(true)
	var city := {"id": "city", "title": "KYTTU: THE CITY", "kicker": "DOME SEALED // NIGHT CITY",
		"tagline": "A walled city under an artificial sky. Cross the streets, enter the buildings, outlast what hunts them.",
		"scene": "res://game/menus/main_menu.tscn", "theme": "res://game/ui_common/theme_lastroute.tres", "locked": false, "locked_note": ""}
	if ResourceLoader.exists("res://game/ui_common/theme_city.tres"):
		city["theme"] = "res://game/ui_common/theme_city.tres"
	var three: Array = [real[0], city] + real.slice(1)
	for key in sizes:
		await _shot(out, "hub_carousel_%s" % key, sizes[key], three, "city")
	await _shot(out, "hub_carousel_real_1280x720", Vector2i(1280, 720), [], "")
	get_tree().quit()


func _shot(out: String, file: String, pixels: Vector2i, games: Array, focus_id: String) -> void:
	GameRegistry.test_games = games
	var old_last := Settings.hub_last_game
	Settings.hub_last_game = focus_id
	var holder := SubViewport.new()
	holder.size = pixels
	var units: Vector2 = load("res://tests/validate_admin_layout.gd").units_for(pixels)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(holder)
	var hub: Control = (load("res://game/menus/game_hub.tscn") as PackedScene).instantiate()
	holder.add_child(hub)
	for _i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	holder.get_texture().get_image().save_png("%s/%s.png" % [out, file])
	holder.queue_free()
	Settings.hub_last_game = old_last
	GameRegistry.test_games = []
	await get_tree().process_frame
