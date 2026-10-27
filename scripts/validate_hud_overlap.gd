extends RefCounted

## HUD panels never overlap each other or leave the window, at the smallest design window, a tall 4:3-ish window (the
## hotel screenshot), a plain 1024x768 and ultrawide. Run in the streamed route with the HUD up.
##
##   godot --headless --path . res://scenes/validate.tscn -- hud_overlap

const SIZES := [Vector2i(480, 270), Vector2i(926, 728), Vector2i(1024, 768), Vector2i(1440, 810), Vector2i(3440, 1440)]
const PANELS := ["ObjectivePanel", "MetersPanel", "HotbarPanel", "MinimapPanel", "CompactStaminaBar"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 10:
		await host.get_tree().process_frame
	var hud: Node = route.hud
	var window := host.get_tree().root
	var original := window.size
	for size in SIZES:
		window.size = size
		for _i in 4:
			await host.get_tree().process_frame
		var rects := {}
		for name in PANELS:
			var control := hud.get_node_or_null(name) as Control
			if control != null and control.is_visible_in_tree():
				rects[name] = control.get_global_rect()
		var view := window.get_visible_rect()
		for name in rects:
			_expect(view.grow(1.0).encloses(rects[name]), "%s leaves the %s window: %s inside %s" % [name, size, rects[name], view])
		var names := rects.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				if (rects[names[i]] as Rect2).intersects(rects[names[j]]):
					_expect(false, "%s overlaps %s at %s: %s vs %s" % [names[i], names[j], size, rects[names[i]], rects[names[j]]])
	window.size = original
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  hud       %d panels never overlap or leave the window at %d sizes" % [PANELS.size(), SIZES.size()])
	return _failures
