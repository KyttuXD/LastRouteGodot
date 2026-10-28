extends RefCounted

## Region / district names are admin-only (RegionNames): as a player no visible UI text in the streamed route (HUD level line,
## zone panel, map region key, menus that are open) contains a region or district name, the level number stays; as an admin the
## HUD level line names the region again. Each peer decides locally.
##
##   godot --headless --path . res://scenes/validate.tscn -- region_names

const NAMES := ["MAZE", "MANSION", "HOTEL", "APARTMENT", "BEACH", "GOTHIC", "PRISON", "CARNIVAL", "INFERNO", "HOSPITAL",
	"LAB", "GREENHOUSE", "MALL", "SEWER", "SEALED"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _texts(root: Node) -> Array:
	var out := []
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		if control is Label:
			out.append([control.name, (control as Label).text])
		elif control is RichTextLabel:
			out.append([control.name, (control as RichTextLabel).get_parsed_text()])
		elif control is Button:
			out.append([control.name, (control as Button).text])
	return out


static func _leaks(text: String) -> String:
	var upper := text.to_upper()
	for name in NAMES:
		var regex := RegEx.create_from_string("\\b%s\\b" % name)
		if regex.search(upper) != null:
			return name
	return ""


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 8:
		await host.get_tree().process_frame
	var hud: Node = route.get("hud")
	var level: int = route.get("facility").call("current_level")
	# player
	RegionNames.override = 0
	route.call("_on_chunk_changed", Vector3i(0, level, 0), {"region": "sewer"})
	hud.call("set_zone_text", "OLD TOWN // NIGHT MARKET")
	await host.get_tree().process_frame
	var depth := hud.get("depth_label") as Label
	_expect(depth.text == "LEVEL %+d" % level, "the player's level line is '%s'" % depth.text)
	for entry in _texts(route):
		var leak := _leaks(String(entry[1]))
		_expect(leak.is_empty(), "player UI %s shows the region name %s: '%s'" % [entry[0], leak, entry[1]])
	_expect(not RegionNames.level_line(-1, "sewer").contains("SEWER"), "level_line leaks the name for a player")
	# admin
	RegionNames.override = 1
	route.call("_on_chunk_changed", Vector3i(0, level, 0), {"region": "sewer"})
	await host.get_tree().process_frame
	_expect(depth.text == "LEVEL %+d // SEWER" % level, "the admin level line is '%s'" % depth.text)
	_expect(RegionNames.level_line(-2, "hotel") == "LEVEL -2 // HOTEL", "level_line for an admin is wrong")
	hud.call("set_zone_text", "OLD TOWN")
	_expect((hud.get("_zone_label") as Label).text == "OLD TOWN", "the admin does not see the zone name")
	RegionNames.override = -1
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  regions   players see LEVEL n without region/district names anywhere in the route UI; admins see the names")
	return _failures
