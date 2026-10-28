extends Node

## The room-lobby hunter dossier with a few hunters discovered, saved as a PNG.
##   godot --path . res://tools/look/dossier_shot.tscn -- OUT.png [index]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/dossier.png"
	Backend.account_username = "SHOT"
	Backend.account_session_token = "t"
	Backend.account_session_verified = true
	Backend.account_progress = {"schema": 1, "kind": "profile",
		"hunter_discoveries": ["aki", "ferryn", "kathy", "elise", "void_red"]}
	var scene := (load("res://scenes/room_lobby.tscn") as PackedScene).instantiate()
	add_child(scene)
	for i in 4:
		await get_tree().process_frame
	scene.call("_on_dossier_pressed")
	for i in 6:
		await get_tree().process_frame
	var roster := scene.find_child("DossierRoster", true, false) as ItemList
	if args.size() > 1 and roster != null:
		roster.select(int(args[1]))
		roster.item_selected.emit(int(args[1]))
		for i in 3:
			await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
