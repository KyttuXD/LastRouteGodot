extends Node

## Debug: every mesh of the Masked Hours office whose box stands in the walk area (floor to head height).
func _ready() -> void:
	NightWatchSession.start_mode("mask", 2, {}, 5)
	var game := (load(NightWatchModeRegistry.scene_for("mask")) as PackedScene).instantiate()
	game.set("manual_clock", true)
	add_child(game)
	if game.has_method("start_shift"):
		game.call("start_shift", [])
	for i in 10:
		await get_tree().process_frame
	var office: Node3D = game.get("office")
	var area := AABB(Vector3(-MaskOffice.HALF_W + 0.3, 0.05, MaskOffice.FRONT_Z + 0.3), Vector3(MaskOffice.HALF_W * 2.0 - 0.6, 1.7, MaskOffice.BACK_Z - MaskOffice.FRONT_Z - 0.6))
	for n in office.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		if box.intersects(area):
			var mat := mi.get_active_material(0)
			print("SCAN %s path=%s size=%s pos=%s alpha=%s" % [mi.name, office.get_path_to(mi), box.size.snapped(Vector3.ONE * 0.01), box.get_center().snapped(Vector3.ONE * 0.01), (mat as BaseMaterial3D).transparency if mat is BaseMaterial3D else -1])
	get_tree().quit()
