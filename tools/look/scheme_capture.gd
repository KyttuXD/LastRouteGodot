extends Node

## Screenshots the shared screens under each game's colour scheme (Last Route vs the City), 1280x720 each:
## settings, pause, account, lobby, results/death, HUD. Files: OUT/scheme_<screen>_<scheme>.png
##   godot --path . res://tools/look/scheme_capture.tscn -- OUTDIR
func _ready() -> void:
	Build.capture_rig = true
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	for screen in ["settings", "pause", "account", "lobby", "results", "hud"]:
		for scheme in ["last_route", "city"]:
			await _shot(out, screen, scheme)
	GameRegistry.active_game_id = "last_route"
	get_tree().quit()


func _shot(out: String, screen: String, scheme: String) -> void:
	GameRegistry.active_game_id = scheme
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var pixels := Vector2i(1280, 720)
	var holder := SubViewport.new()
	holder.size = pixels
	var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(holder)
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(backdrop)
	# the root window carries the game's Theme in the real app; a SubViewport needs it on its content
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.theme = Palette.theme_for(scheme)
	holder.add_child(stage)
	var node: Node
	match screen:
		"settings":
			var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
			stage.add_child(menu)
			await get_tree().process_frame
			var overlay := menu.find_child("SettingsOverlay", true, false) as Control
			overlay.visible = true
			for sibling in menu.get_children():
				if sibling != overlay and sibling is CanvasItem:
					(sibling as CanvasItem).visible = false
			node = menu
		"pause":
			var pause := PauseMenu.new()
			stage.add_child(pause)
			await get_tree().process_frame
			pause.open()
			node = pause
		"account":
			node = AccountPanel.open(stage)
		"lobby":
			node = (load("res://scenes/room_lobby.tscn") as PackedScene).instantiate()
			stage.add_child(node)
		"results":
			node = (load("res://scenes/run_report.tscn") as PackedScene).instantiate()
			stage.add_child(node)
			await get_tree().process_frame
			(node as RunReport).open({"online": false, "respawn": true, "title": "YOU DIED", "reason": "CAUGHT BY AKI",
				"depth": 8, "score": 4200, "relays": 3, "relay_target": 6, "coins": 12, "difficulty": "HARD", "seed": "ROOM-REPORT-1234567890"})
		"hud":
			var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as HUD
			stage.add_child(hud)
			await get_tree().process_frame
			hud.update_infinite_status(3, 40, 35)
			hud.update_inventory("flashlight", 0.0)
			hud.status_bar.set_segment("env", "TEST SERVER", "env")
			hud.status_bar.set_segment("admin", "ADMIN ACTIVE // SOLO", "admin")
			hud.show_message("RELAY ONLINE")
			node = hud
	for _i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	holder.get_texture().get_image().save_png("%s/scheme_%s_%s.png" % [out, screen, scheme])
	if node is PauseMenu:
		(node as PauseMenu).close()
	holder.queue_free()
	await get_tree().process_frame
