extends RefCounted

## KT: "when a player runs out of flashlight, the light doesnt break" and "remove the extra flashlight item collectables".
## An empty flashlight goes dark, stays in slot 1 at 0 charge, clicks when toggled, and a battery brings it back; the
## world never spawns flashlight pickups.
##
##   godot --headless --path . res://scenes/validate.tscn -- flashlight_empty

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_expect(not StreamedRouteGenerator.PICKUP_TYPES.has("flashlight"), "flashlights are still a world pickup type")
	var flashlight_pickups := 0
	var generator := StreamedRouteGenerator.new("FLASH-EMPTY")
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var coord := Vector3i(dx, 0, dz)
			if not generator.is_chunk_allowed(coord):
				continue
			for pickup in generator.chunk(coord).get("pickups", []):
				if String((pickup as Dictionary).get("item", "")) == "flashlight":
					flashlight_pickups += 1
	_expect(flashlight_pickups == 0, "%d flashlight pickups spawned" % flashlight_pickups)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 3:
		await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
	player.select_inventory_slot(player.inventory_order.find("flashlight"))
	player._set_flashlight(true)
	player.lamp_charge = .2
	Sound.reset_test_counters()
	player._update_lamp(5.0, false)
	_expect(player.owns_inventory_item("flashlight") and player.inventory_order[0] == "flashlight",
		"the empty flashlight left the hotbar")
	_expect(not player.flashlight_enabled and player.lamp_charge == 0.0, "the empty flashlight is still lit")
	_expect(int(Sound.play_counts.get("tool_break", 0)) == 0, "the flashlight played the break sound")
	_expect(int(Sound.play_counts.get("light_switch", 0)) >= 1, "the flashlight did not click off")
	player._set_flashlight(true)
	_expect(not player.flashlight_enabled, "an empty flashlight turned on")
	player.grant_inventory_item("battery")
	player.select_inventory_slot(player.inventory_order.find("battery"))
	player._use_battery()
	_expect(player.lamp_charge > 0.0, "a battery did not recharge the empty flashlight")
	player.select_inventory_slot(player.inventory_order.find("flashlight"))
	player._set_flashlight(true)
	_expect(player.flashlight_enabled, "the recharged flashlight does not turn on")
	scene.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  flashlight_empty  ok")
	return _failures
