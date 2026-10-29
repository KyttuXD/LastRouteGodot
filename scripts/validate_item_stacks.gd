extends RefCounted

## Stackable consumables (PlayerController3D.STACK_MAX, KT 2026-10-28: battery 5, stim pack 3, revive kit 2): pickups
## merge into the first stack with room, then an empty slot, all or nothing; tools never stack; using one takes one;
## the drop key drops one (a tap) or the whole stack (held); the HUD shows "xN"; saves keep the count and a pre-stack
## battery (0) loads as one; the host refuses claims past the cap and GuestGuard strikes an over-full slot.
##
##   godot --headless --path . res://scenes/validate.tscn -- item_stacks

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _empty(player: PlayerController3D) -> void:
	for slot in player.inventory_order.size():
		player.inventory_order[slot] = "flashlight" if slot == 0 else ""
		player.inventory_slot_durability[slot] = 100 if slot == 0 else 0
	player._sync_owned_inventory_items()
	player.select_inventory_slot(0)


func run(host: Node) -> int:
	_expect(PlayerController3D.STACK_MAX == {"battery": 5, "stim_pack": 3, "revive_kit": 2},
		"the stack sizes are not KT's (battery 5, stim 3, revive 2): %s" % PlayerController3D.STACK_MAX)
	for tool in PlayerController3D.TOOL_ITEMS:
		_expect(PlayerController3D.stack_max(tool) == 1, "%s stacks" % tool)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 8:
		await host.get_tree().process_frame
	var player: PlayerController3D = scene.player

	# tools: one per slot
	_empty(player)
	player.grant_inventory_item("crowbar")
	player.grant_inventory_item("crowbar")
	_expect(player.inventory_order.count("crowbar") == 2, "two crowbars share a slot")

	# batteries merge up to five, then a new slot
	_empty(player)
	for i in 7:
		_expect(player.grant_inventory_item("battery"), "battery %d was refused with room" % (i + 1))
	var first := player.inventory_order.find("battery")
	_expect(player.inventory_order.count("battery") == 2 and player.stack_count_at(first) == 5 \
		and player.item_count("battery") == 7, "seven batteries are not a stack of 5 and one of 2 (%s %s)" % [
		player.inventory_order, player.inventory_slot_durability])
	# the HUD badge
	player.select_inventory_slot(first)
	for _i in 3:
		await host.get_tree().process_frame
	var hud: HUD = scene.hud
	var badge := hud._inventory_slots[first].get_node_or_null("StackCount") as Label
	_expect(badge != null and badge.visible and badge.text == "x5", "the hotbar slot does not show x5 (%s)" % (badge.text if badge else "none"))
	# all or nothing: a dropped stack of 4 needs room for all 4
	_empty(player)
	for i in 3:
		player.grant_inventory_item("crowbar")
	player.grant_inventory_item("battery", 4)   # the last free slot: a stack of 4, one short of full
	_expect(player.stack_count_at(player.inventory_order.find("battery")) == 4, "a dropped stack of 4 did not land as 4")
	_expect(not player.grant_inventory_item("battery", 2), "two batteries were taken with room for one")
	_expect(player.item_count("battery") == 4, "a refused pickup changed the stack")
	_expect(player.grant_inventory_item("battery"), "the fifth battery was refused")
	_expect(not player.grant_inventory_item("battery"), "a sixth battery went past the cap")
	_expect(not PlayerController3D.can_accept_item(player.inventory_order, player.inventory_slot_durability, "battery"),
		"can_accept_item says a full stack has room")
	_expect(not player.grant_inventory_item("stim_pack"), "a stim fit a full inventory")

	# using one takes one
	_empty(player)
	player.grant_inventory_item("battery", 3)
	player.select_inventory_slot(player.inventory_order.find("battery"))
	player.lamp_charge = 10.0
	player._use_battery()
	_expect(player.item_count("battery") == 2, "using a battery did not take exactly one (%d left)" % player.item_count("battery"))

	# the drop key: a tap drops one, held drops all; the dropped record carries the count and merges back
	# (the route's own handler is connected too: each request really drops, solo, through the host path)
	var drops := []
	var watch := func(item_id: String, count: int, slot: int) -> void: drops.append([item_id, count, slot])
	player.item_drop_requested.connect(watch)
	player.request_drop_selected_item(false)
	_expect(player.item_count("battery") == 1, "a tap dropped more than one (%d left of 2)" % player.item_count("battery"))
	player.grant_inventory_item("battery", 2)
	player.select_inventory_slot(player.inventory_order.find("battery"))
	player.request_drop_selected_item(true)
	player.item_drop_requested.disconnect(watch)
	_expect(drops.size() == 2 and int(drops[0][1]) == 1 and int(drops[1][1]) == 3,
		"tap/hold drop did not ask for 1 then the whole stack of 3: %s" % [drops])
	_expect(player.item_count("battery") == 0, "dropping the whole stack left %d" % player.item_count("battery"))
	var counts := []
	var three := ""
	for id in scene.world_state.dropped_items:
		var record: Dictionary = scene.world_state.dropped_items[id]
		if String(record["item"]) == "battery":
			counts.append(int(record["durability"]))
			if int(record["durability"]) == 3:
				three = String(id)
	counts.sort()
	_expect(counts == [1, 3], "the dropped battery records are not a 1 and a 3: %s" % [counts])
	if not three.is_empty():
		scene._accept_stream_drop(1, {"action": "claim", "drop_id": three})
		_expect(player.item_count("battery") == 3 and player.inventory_order.count("battery") == 1,
			"picking the stack of 3 back up did not give one stack of 3")
	var two: Dictionary = scene.world_state.create_drop("stim_pack", 9, player.global_position, 0, 1)
	_expect(int(two["durability"]) == 3, "a dropped stack past the cap was not clamped to 3 (%d)" % int(two["durability"]))

	# saves: the count round-trips; a pre-stack battery (0) loads as one; an over-full save is clamped
	_empty(player)
	player.grant_inventory_item("revive_kit", 2)
	player.grant_inventory_item("battery", 4)
	var saved: Dictionary = player.run_save_snapshot()
	_empty(player)
	_expect(player.restore_run_save(saved) and player.item_count("battery") == 4 and player.item_count("revive_kit") == 2,
		"a save did not bring back 4 batteries and 2 revive kits")
	var legacy: Dictionary = saved.duplicate(true)
	var legacy_slot: int = (legacy["inventory_order"] as Array).find("battery")
	legacy["inventory_slot_durability"][legacy_slot] = 0
	legacy["inventory_slot_durability"][(legacy["inventory_order"] as Array).find("revive_kit")] = 9
	_expect(player.restore_run_save(legacy) and player.stack_count_at(legacy_slot) == 1 and player.item_count("revive_kit") == 2,
		"a pre-stack battery did not load as 1, or an over-full stack was not clamped")

	# host: claims past the cap are refused
	var target := {"inventory_order": ["flashlight", "battery", "crowbar"], "inventory_slot_durability": [100, 5, 40]}
	_expect(not scene._target_can_take(target, "battery", 1), "the host let a full stack take a battery")
	target["inventory_slot_durability"] = [100, 3, 40]
	_expect(scene._target_can_take(target, "battery", 2) and not scene._target_can_take(target, "battery", 3),
		"the host's stack room is wrong")
	_expect(not scene._target_can_take(target, "crowbar", 1), "the host gave a tool a full inventory")

	# GuestGuard: an over-full slot is a strike; batteries count across stacks
	var guard := GuestGuard.new()
	var state := {"at": Vector3.ZERO, "position": Vector2.ZERO, "depth": 0, "lamp_charge": 50.0,
		"inventory_order": ["flashlight", "battery", "battery"], "inventory_slot_durability": [50, 5, 2]}
	_expect(GuestGuard._batteries(state) == 7, "GuestGuard counts %d batteries, not 7" % GuestGuard._batteries(state))
	guard.check(9, state, 0.0)
	_expect(guard.check(9, state, .05).is_empty(), "a legit pair of stacks was flagged")
	var over := state.duplicate(true)
	over["inventory_slot_durability"] = [50, 6, 2]
	_expect(String(guard.check(9, over, .1).get("reason", "")) == "stack", "a slot of 6 batteries was not flagged")
	await _per_item_cooldowns(host, scene, player)
	scene.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  item_stacks  ok")
	return _failures


## KT 2026-10-28: "make only the used taser/item have a cooldown or usage hit". Cooldowns live per slot and move with the
## item; firing one taser leaves a second ready (HUD too); picking up or dropping another taser does not reset it; the host
## times each taser slot on its own; a tool swing or a battery only touches its own slot.
func _per_item_cooldowns(host: Node, scene: Node, player: PlayerController3D) -> void:
	_empty(player)
	player.grant_inventory_item("taser")
	player.grant_inventory_item("taser")
	player.grant_inventory_item("crowbar")
	player.grant_inventory_item("crowbar")
	var first := player.inventory_order.find("taser")
	var second := player.inventory_order.rfind("taser")
	player.select_inventory_slot(first)
	player.input_frozen = false
	player.stun_timer = 0.0
	player._fire_taser()
	_expect(player.slot_cooldown(first) > 0.0 and player.slot_cooldown(second) == 0.0 and player.last_taser_slot == first,
		"firing one taser put the other on cooldown too (%s)" % [player.slot_cooldowns])
	for slot in player.inventory_order.size():
		if slot != first:
			_expect(player.slot_cooldown(slot) == 0.0, "firing a taser put slot %d (%s) on cooldown" % [slot, player.inventory_order[slot]])
	# the HUD: only the fired taser's bar is draining
	for _i in 2:
		await host.get_tree().process_frame
	var hud: HUD = scene.hud
	if second < hud._inventory_bars.size() and first < hud._inventory_bars.size():
		_expect(hud._inventory_bars[first].value < 50.0 and is_equal_approx(hud._inventory_bars[second].value, 100.0),
			"the hotbar shows the cooldown on both tasers (%.0f / %.0f)" % [hud._inventory_bars[first].value, hud._inventory_bars[second].value])
	# the second taser fires while the first recharges
	player._fire_taser()
	_expect(player.last_taser_slot == second and player.slot_cooldown(second) > 0.0, "the second taser would not fire while the first recharged")
	player._fire_taser()
	_expect(player.last_taser_slot == second, "a taser fired with both on cooldown")
	# a swap carries the cooldown with the item
	player.slot_cooldowns[second] = 0.0
	var spent := player.slot_cooldown(first)
	player.move_inventory_slot(first, second)
	_expect(is_equal_approx(player.slot_cooldown(second), spent) and player.slot_cooldown(first) == 0.0, "the cooldown stayed on the row, not the taser")
	# dropping or picking up another taser leaves this one's cooldown alone
	player.remove_inventory_item("taser", first)
	_expect(is_equal_approx(player.slot_cooldown(second), spent), "dropping the other taser reset this one's cooldown")
	player.grant_inventory_item("taser")
	_expect(is_equal_approx(player.slot_cooldown(second), spent) and player.slot_cooldown(player.inventory_order.find("taser")) == 0.0,
		"picking up a taser reset the other one's cooldown, or arrived on cooldown")
	# tools: a swing only wears the crowbar that swung
	var bars := []
	for slot in player.inventory_order.size():
		if player.inventory_order[slot] == "crowbar":
			bars.append(slot)
	player.select_inventory_slot(bars[1])
	var before := [player.inventory_slot_durability[bars[0]], player.inventory_slot_durability[bars[1]]]
	player.consume_item_durability("crowbar")
	_expect(player.inventory_slot_durability[bars[0]] == before[0] and player.inventory_slot_durability[bars[1]] == before[1] - 1,
		"using one crowbar wore the other (%s -> %s)" % [before, [player.inventory_slot_durability[bars[0]], player.inventory_slot_durability[bars[1]]]])
	# batteries: using one takes from the selected stack only
	_empty(player)
	player.grant_inventory_item("battery", 5)
	player.grant_inventory_item("battery", 2)
	var full := player.inventory_order.find("battery")
	var small := player.inventory_order.rfind("battery")
	player.select_inventory_slot(small)
	player.lamp_charge = 10.0
	player._use_battery()
	_expect(player.stack_count_at(full) == 5 and player.stack_count_at(small) == 1, "a battery came off the wrong stack")
	# host: each taser slot has its own timer (keyed peer:slot)
	scene._taser_ready_usec_by_peer.clear()
	scene._resolve_taser(1, 3)
	var keys: Array = scene._taser_ready_usec_by_peer.keys()
	_expect(keys.size() == 1 and String(keys[0]).begins_with("1:"), "the host keeps no per-slot taser timer (%s)" % [keys])
	# resetting the taser cooldown clears every taser, nothing else
	player.grant_inventory_item("taser")
	player.grant_inventory_item("taser")
	player._fire_taser()
	player._fire_taser()
	player.taser_cooldown = 0.0
	for slot in player.inventory_order.size():
		if player.inventory_order[slot] == "taser":
			_expect(player.slot_cooldown(slot) == 0.0, "resetting the taser cooldown missed slot %d" % slot)
