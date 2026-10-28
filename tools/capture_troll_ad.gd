extends Node

## Renders one troll-mode ad pop-up (TrollAdOverlay) over a dark frame and saves captures/troll_ad_<mode>.png, then quits.
##   godot --path . --position 10000,10000 res://tools/capture_troll_ad.tscn -- annoying|gentle

func _ready() -> void:
	var root := get_tree().root
	var mode := "annoying"
	for arg in OS.get_cmdline_user_args():
		if arg in TrollAds.MODES:
			mode = arg
	root.size = Vector2i(1280, 720)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.07)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var overlay := TrollAdOverlay.new()
	add_child(overlay)
	var ads := TrollAds.new(3)
	ads.set_mode(mode, 0.0)
	var ad := TrollAds.render(TrollAds.all()[0])
	for candidate in TrollAds.all():
		if String(candidate.get("id", "")) == "sponsor_stand_still":
			ad = TrollAds.render(candidate)
	overlay.show_ad(ad, ads.profile())
	for _i in 12:
		await get_tree().process_frame
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var path := "res://captures/troll_ad_%s.png" % mode
	image.save_png(path)
	print("saved %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()
