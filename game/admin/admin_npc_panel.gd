class_name AdminNpcPanel
extends VBoxContainer

## The admin menu's NPCS page: spawn NPC teammates (◀ N ▶, a smartness, at the crosshair when that floor is
## walkable, else beside you), remove the nearest or all, and act on one NPC picked from the live list (name, state, distance):
## teleport to / go to / follow you, smartness, chat, freeze, hunters ignore or target it, down / revive / kill, remove, and spectate it.
## Every command goes through the route's admin path (InfiniteRouteTest._admin_world_action): the host applies it, a guest
## admin's is sent to the host, which checks the guest's admin rights first. Spectating is this screen's camera only.

const SMARTS := [30, 50, 70, 90]
const REFRESH := .5

var route: Node
var _count := 1
var _smart := 70
var _picked := 0                 # NPC id (0: none)
var _ids: Array = []
var _list: OptionButton
var _count_label: Label
var _info: Label
var _clock := 0.0


func _init(p_route: Node) -> void:
	route = p_route
	name = "AdminNpcPanel"
	add_theme_constant_override("separation", 2)


func _ready() -> void:
	add_child(_caption("SPAWN"))
	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_button("<", "NpcLess", func() -> void: _set_count(_count - 1)))
	_count_label = _caption("1")
	_count_label.custom_minimum_size = Vector2(20, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_count_label)
	row.add_child(_button(">", "NpcMore", func() -> void: _set_count(_count + 1)))
	var smart := OptionButton.new()
	smart.name = "NpcSmart"
	for value in SMARTS:
		smart.add_item("SMART %d" % value)
	smart.select(SMARTS.find(_smart))
	smart.item_selected.connect(func(i: int) -> void: _smart = int(SMARTS[i]))
	row.add_child(smart)
	add_child(_button("SPAWN NPC", "NpcSpawn", _spawn))
	var removes := HBoxContainer.new()
	add_child(removes)
	removes.add_child(_button("REMOVE NEAREST", "NpcRemoveNearest", func() -> void: _send({"op": "remove_nearest"})))
	removes.add_child(_button("REMOVE ALL", "NpcRemoveAll", func() -> void: _send({"op": "remove_all"})))
	add_child(_caption("NPC"))
	_list = OptionButton.new()
	_list.name = "NpcList"
	_list.item_selected.connect(func(i: int) -> void: _picked = int(_ids[i]) if i >= 0 and i < _ids.size() else 0)
	add_child(_list)
	_info = _caption("")
	add_child(_info)
	var grid := GridContainer.new()
	grid.columns = 3
	add_child(grid)
	for entry in [["TELEPORT TO ME", "teleport"], ["GO TO ME", "goto"], ["FOLLOW ME", "follow"], ["STOP FOLLOWING", "unfollow"],
			["FREEZE", "freeze"], ["RESUME", "resume"], ["HUNTERS IGNORE", "ignore"], ["HUNTERS TARGET", "target"],
			["CHAT ON", "chat_on"], ["CHAT OFF", "chat_off"], ["SMART = SPAWN SMART", "smart"], ["DOWN", "down"],
			["REVIVE", "revive"], ["KILL", "kill"], ["REMOVE", "remove"], ["CLEAR HUNTER FLAGS", "clear"]]:
		var op := String(entry[1])
		grid.add_child(_button(String(entry[0]), "Npc_" + op, func() -> void: _act(op)))
	grid.add_child(_button("SPECTATE", "Npc_spectate", _spectate))
	# ALL NPCS: the same ops on every NPC in the run (NpcTeammates.BULK_OPS); the host applies each and reports the count
	add_child(_caption("ALL NPCS"))
	var bulk := GridContainer.new()
	bulk.name = "NpcAllGrid"
	bulk.columns = 3
	add_child(bulk)
	for bulk_entry in [["ALL TO ME", "teleport"], ["ALL FOLLOW ME", "follow"], ["ALL STOP FOLLOW", "unfollow"],
			["ALL FREEZE", "freeze"], ["ALL RESUME", "resume"], ["ALL IGNORE", "ignore"], ["ALL TARGET", "target"],
			["ALL CLEAR", "clear"], ["ALL CHAT ON", "chat_on"], ["ALL CHAT OFF", "chat_off"], ["ALL SMART", "smart"]]:
		var all_op := String(bulk_entry[1])
		bulk.add_child(_button(String(bulk_entry[0]), "NpcAll_" + all_op, func() -> void: _act_all(all_op)))
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= REFRESH and is_visible_in_tree():
		_clock = 0.0
		_refresh()


## The NPCs every peer knows (their states), nearest first, with state and distance from you.
func rows() -> Array:
	var out := []
	var remotes: Node = route.get("_remotes")
	if remotes == null:
		return out
	var states: Dictionary = remotes.get("_states")
	var me: Vector3 = (route.get("player") as Node3D).global_position
	for id in states:
		if not RemotePlayers.is_npc(int(id)):
			continue
		var state: Dictionary = states[id]
		var at: Vector3 = state.get("at", me)
		var flags: Array = state.get("npc_admin", [2, 70, 0])
		var what := "DOWN" if bool(state.get("spectating", false)) else ("FROZEN" if int(flags[0]) & 1 else "OK")
		if bool(state.get("no_target", false)):
			what += " · IGNORED"
		elif bool(state.get("hunt_target", false)):
			what += " · TARGET"
		if int(flags[2]) != 0:
			what += " · FOLLOWING"
		out.append({"id": int(id), "name": String(state.get("display_name", "?")), "state": what,
			"dist": at.distance_to(me), "smart": int(flags[1]), "chat": int(flags[0]) & 2 != 0})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	return out


func _refresh() -> void:
	var found := rows()
	_ids = found.map(func(r: Dictionary) -> int: return int(r["id"]))
	_list.clear()
	for r in found:
		_list.add_item("%s  %s  %d M" % [r["name"], r["state"], roundi(float(r["dist"]))])
	if not _ids.has(_picked):
		_picked = int(_ids[0]) if not _ids.is_empty() else 0
	if _picked != 0:
		_list.select(_ids.find(_picked))
		var r: Dictionary = found[_ids.find(_picked)]
		_info.text = "SMART %d · CHAT %s" % [int(r["smart"]), "ON" if bool(r["chat"]) else "OFF"]
	else:
		_info.text = "NO NPCS"
	_count_label.text = str(_count)


func _set_count(value: int) -> void:
	# no upper limit: the stepper keeps counting, and a request is not capped, so the host applies whatever count is sent
	_count = maxi(value, 1)
	_count_label.text = str(_count)


## Spawn at the crosshair's floor point (sent along; the host keeps it only when it is walkable and near), else beside you.
func _spawn() -> void:
	var payload := {"op": "spawn", "count": _count, "smart": _smart}
	var point := crosshair_floor()
	if point != Vector3.INF:
		payload["at"] = point
	_send(payload)


func crosshair_floor() -> Vector3:
	var player: PlayerController3D = route.get("player")
	var camera := player.get_viewport().get_camera_3d() if player != null else null
	if camera == null:
		return Vector3.INF
	var from := camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from - camera.global_transform.basis.z * 30.0)
	ray.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or (hit["normal"] as Vector3).y < .7:
		return Vector3.INF   # a wall or the sky: no floor there
	return hit["position"]


func _act(op: String) -> void:
	if _picked == 0:
		return
	match op:
		"chat_on":
			_send({"op": "chat", "id": _picked, "value": 1})
		"chat_off":
			_send({"op": "chat", "id": _picked, "value": 0})
		"smart":
			_send({"op": "smart", "id": _picked, "smart": _smart})
		_:
			_send({"op": op, "id": _picked})


## ALL NPCS: no picked NPC needed. The host runs the op on every NPC (BULK_OPS) and refuses any other.
func _act_all(op: String) -> void:
	match op:
		"chat_on":
			_send({"op": "chat", "all": true, "value": 1})
		"chat_off":
			_send({"op": "chat", "all": true, "value": 0})
		"smart":
			_send({"op": "smart", "all": true, "smart": _smart})
		_:
			_send({"op": op, "all": true})


func _send(payload: Dictionary) -> void:
	route.call("_admin_world_action", "npc", payload)


## This screen's camera follows the picked NPC (the spectator camera); press again to come back.
func _spectate() -> void:
	route.call("_admin_spectate_npc", _picked)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Palette.MUTED)
	return label


func _button(text: String, node_name: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.add_theme_font_size_override("font_size", 7)
	button.focus_mode = Control.FOCUS_ALL
	Palette.style_button(button, false)
	button.pressed.connect(pressed)
	return button
