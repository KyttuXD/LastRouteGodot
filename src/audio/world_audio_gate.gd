class_name WorldAudioGate
extends RefCounted

## Silences the game world while a loading / sync screen is up (RouteLoadingScreen: route load, the co-op join sync gate, rejoin) and
## fades it back in over FADE_SECONDS when the player enters the world. UI sounds (the UI bus) are never touched.
##
## World sounds play on Master or SFX (ambience beds, positional players, hunters, music, footsteps, voices). While held, every such
## player is routed to a muted "gate" bus that feeds its original bus -- existing players, players added while held (node_added) and
## Sound's one-shots (route()) -- and the gate buses fade back up on release; afterwards the players go back to their own buses.

const GATED := {&"Master": &"WorldGateMaster", &"SFX": &"WorldGateSFX"}
const FADE_SECONDS := 0.5
const SILENT_DB := -80.0

static var active := false
static var _holders := {}
static var _moved := {}   # instance id -> {"node": WeakRef, "bus": StringName}
static var _tween: Tween


static func hold(reason: String) -> void:
	_holders[reason] = true
	if active:
		return
	active = true
	_ensure_buses()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for gate in GATED.values():
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(gate), SILENT_DB)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_route_tree(tree.root)
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)


static func release(reason: String) -> void:
	_holders.erase(reason)
	if not active or not _holders.is_empty():
		return
	active = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
	if tree == null:
		_finish_fade()
		return
	_tween = tree.create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_gate_db, SILENT_DB, 0.0, FADE_SECONDS)
	_tween.tween_callback(_finish_fade)


## The bus a one-shot should use right now (Sound): its gate bus while held, else the bus itself.
static func route(bus: StringName) -> StringName:
	return GATED.get(bus, bus) if active else bus


static func is_held() -> bool:
	return active


static func gate_db() -> float:
	var index := AudioServer.get_bus_index(GATED[&"SFX"])
	return AudioServer.get_bus_volume_db(index) if index >= 0 else 0.0


static func _set_gate_db(value: float) -> void:
	# a linear fade in amplitude, not in dB, so the last stretch is not a jump
	var db := linear_to_db(clampf(db_to_linear(SILENT_DB) + (1.0 - db_to_linear(SILENT_DB)) * inverse_lerp(SILENT_DB, 0.0, value), 0.0001, 1.0))
	for gate in GATED.values():
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(gate), db)


static func _finish_fade() -> void:
	if active:
		return
	for gate in GATED.values():
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(gate), 0.0)
	for id in _moved:
		var entry: Dictionary = _moved[id]
		var node = (entry["node"] as WeakRef).get_ref()
		if node != null and GATED.values().has(node.bus):
			node.bus = entry["bus"]
	_moved.clear()


static func _ensure_buses() -> void:
	for source in GATED:
		var gate: StringName = GATED[source]
		if AudioServer.get_bus_index(gate) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, gate)
		AudioServer.set_bus_send(index, source)


static func _route_tree(node: Node) -> void:
	_route(node)
	for child in node.get_children():
		_route_tree(child)


static func _on_node_added(node: Node) -> void:
	_route(node)


static func _route(node: Node) -> void:
	if not (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D):
		return
	var bus: StringName = node.bus
	if not GATED.has(bus):
		return
	_moved[node.get_instance_id()] = {"node": weakref(node), "bus": bus}
	node.bus = GATED[bus]
