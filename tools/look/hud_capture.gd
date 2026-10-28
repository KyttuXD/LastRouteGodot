extends Node

## Screenshots the in-game HUD per window size in two states, each a SubViewport with the real expand-stretch rule:
## "route" (Last Route: minimap, BETA + ADMIN ACTIVE + public line in one bar, stats, co-op chat) and "city" (no map:
## the zone name takes the minimap's slot, no chat).
##   godot --path . res://tools/look/hud_capture.tscn -- OUTDIR [PREFIX]
func _ready() -> void:
	Build.capture_rig = true
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	var prefix := args[1] if args.size() > 1 else "hud"
	DirAccess.make_dir_recursive_absolute(out)
	var sizes := {
		"1280x720": Vector2i(1280, 720), "1920x1080": Vector2i(1920, 1080), "ultrawide3440x1440": Vector2i(3440, 1440),
		"phone844x390": Vector2i(844, 390),
	}
	for key in sizes:
		for state in ["route", "city"]:
			await _shot(out, "%s_%s_%s" % [prefix, state, key], sizes[key], state)
	get_tree().quit()


func _shot(out: String, file: String, pixels: Vector2i, state: String) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var holder := SubViewport.new()
	holder.size = pixels
	var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(holder)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.16, 0.2, 0.26)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(backdrop)
	var hud: HUD = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	holder.add_child(hud)
	var chat: RoomChat = null
	await get_tree().process_frame
	hud.status_bar.set_segment("env", "TEST SERVER", "env")
	hud.status_bar.set_segment("admin", "ADMIN ACTIVE // SOLO", "admin")
	hud.update_inventory("flashlight", 0.0)
	hud.update_objective(1, 0, 5)
	hud.update_infinite_status(3, 40, 35)
	if state == "route":
		hud.set_public_line("PUBLIC ROUTE // 3 ONLINE // 12 RELAYS")
		hud.update_minimap(FacilityGenerator.new("HUD-CAPTURE", RoomState.generator_options()), Vector2(10, 10), Vector2.RIGHT, [])
		chat = RoomChat.attach(holder, null)
		await get_tree().process_frame
		chat._on_chat_received(1, "Kyttu", "second relay is past the red door")
		chat._on_chat_received(2, "Guest", "on my way, bring a battery")
		hud.show_message("RELAY ONLINE")
	else:
		hud.minimap.generator = null
		hud.set_minimap_available(false)
		hud.set_zone_text("OLD TOWN  //  NIGHT MARKET")
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	holder.get_texture().get_image().save_png("%s/%s.png" % [out, file])
	holder.queue_free()
	await get_tree().process_frame
