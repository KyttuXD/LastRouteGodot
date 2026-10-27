class_name VerrineGimmick
extends HunterGimmick

## Verrine's vent lurker (hunterAbilities.verrine.ventLurker). Ported from
## verrine.js's prepareVentLurker/useVent.
##
## She never patrols the floor at all -- she is invisible and holds
## position, wherever she last teleported to, until the PLAYER steps into
## the vent network (RouteInteractable3D.Kind.VENT, resolved through
## use_vent() below, the same indirection music_box_resolver/
## hiding_trap_resolver already use). From then on she is pinned to CHASE
## with her last-known position forced to the player's real one every frame
## -- not really "perceiving" the player at all, since she is usually
## nowhere near them -- and her speed ramps the longer the player stays
## inside, exactly like ordinary perception feeding _current_speed() but
## driven by target["vent_time_in"] instead of a real sight/hearing check.
##
## The vent list itself lives on FacilityGenerator (place_vents()), not
## here, so the physical grates (facility_view_3d.gd) and this gimmick's own
## teleport/transit math read the exact same positions -- the same reason
## place_hiding_spots() lives there for Ceryth/Javelle/Loxelle.

var _active_in_vent := false
var _speed_scale := 1.0
const PLAYER_EXIT_RADIUS := 0.27


func after_perception(brain: HunterBrain, _delta: float, target: Dictionary, _generator) -> void:
	_active_in_vent = bool(target.get("in_vent", false))
	if not _active_in_vent:
		# Overrides whatever ordinary perception just decided -- she is
		# invisible and inert while the player is not in the network, the
		# same reasoning Porcelle/Ilyra's banish already established for
		# "this hunter cannot actually be perceiving anyone right now."
		brain.state = HunterBrain.State.IDLE
		brain.has_last_known = false
		brain.lost_sight_timer = 0.0
		return

	var player_position: Vector2 = target["position"]
	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = player_position
	brain.lost_sight_timer = 0.0

	var duration: float = target.get("vent_time_in", 0.0)
	_speed_scale = clampf(
		GameConfig.VERRINE_INITIAL_SPEED_SCALE + duration * GameConfig.VERRINE_SPEED_PER_SECOND,
		0.0, GameConfig.VERRINE_MAX_SPEED_SCALE)


func speed_scale(_brain: HunterBrain) -> float:
	return _speed_scale


func holds_position() -> bool:
	return not _active_in_vent


func hidden_from_view() -> bool:
	return not _active_in_vent


func network_state() -> Dictionary:
	return {"active_in_vent": _active_in_vent, "speed_scale": _speed_scale}


func apply_network_state(state: Dictionary) -> void:
	_active_in_vent = bool(state.get("active_in_vent", _active_in_vent))
	_speed_scale = float(state.get("speed_scale", _speed_scale))


## A guest owns its own vent traversal, but the host owns Verrine. This is the
## one hunter-side consequence of a remote vent entry which cannot be inferred
## from the next movement packet: she jumps two stops ahead immediately.
func remote_vent_entered(vent_id: String, brain: HunterBrain,
		generator) -> void:
	var index := _index_of(generator.vents, vent_id)
	if index < 0 or generator.vents.is_empty():
		return
	var threat: Dictionary = generator.vents[(index + 2) % generator.vents.size()]
	brain.position = Vector2(float(threat["x"]) + 0.5, float(threat["y"]) + 0.5)


## Entry/transit/exit through the network. `vent_id` is whichever grate the
## player just pressed [E] at -- not necessarily the one they entered
## through, since walking the network is a chain of hops through whichever
## grates are reached next.
func use_vent(vent_id: String, brain: HunterBrain, player: PlayerController3D, generator) -> String:
	var vents: Array = generator.vents
	if vents.is_empty():
		return "The grate won't budge."
	var index := _index_of(vents, vent_id)
	if index < 0:
		return "The grate won't budge."
	var count: int = vents.size()

	if not player.in_vent:
		player.in_vent = true
		player.vent_entry_id = vent_id
		player.vent_time_in = 0.0
		# She teleports to a threat position two hops ahead of the entry --
		# already closing on wherever the player is about to travel to.
		var threat: Dictionary = vents[(index + 2) % count]
		brain.position = Vector2(float(threat["x"]) + 0.5, float(threat["y"]) + 0.5)

	var next: Dictionary = vents[(index + 1) % count]
	if String(next["id"]) == player.vent_entry_id:
		player.in_vent = false
		player.vent_entry_id = ""
		return "VENT NETWORK EXITED"

	var world := _safe_vent_exit(next, generator)
	player.global_position = Vector3(world.x, player.global_position.y, world.y)
	player.velocity = Vector3.ZERO
	return "VENT TRANSIT // %s" % String(next["id"]).to_upper()


## A grate occupies its own source cell. Emerge one cell into the room and
## validate the full player radius against structural walls/solid props. The
## nearest-open fallback also makes old finite-map vent records (which predate
## open_direction) safe without changing their saved format.
func _safe_vent_exit(vent: Dictionary, generator) -> Vector2:
	var vent_cell := Vector2i(int(vent.get("x", 0)), int(vent.get("y", 0)))
	var open_direction: Vector2i = vent.get("open_direction", Vector2i.ZERO)
	if open_direction == Vector2i.ZERO and vent.has("wall_dir"):
		open_direction = -(vent.get("wall_dir", Vector2i.ZERO) as Vector2i)
	var preferred := Vector2(vent_cell) + Vector2(.5, .5)
	if open_direction != Vector2i.ZERO:
		preferred += Vector2(open_direction)
	var occupied_vents := {}
	for entry_value in generator.vents:
		var entry: Dictionary = entry_value
		occupied_vents[Vector2i(int(entry.get("x", 0)),
			int(entry.get("y", 0)))] = true
	if generator.has_method("nearest_open_position"):
		var clear: Dictionary = generator.nearest_open_position(
			preferred.x, preferred.y, PLAYER_EXIT_RADIUS, occupied_vents)
		if not clear.is_empty():
			return Vector2(float(clear["x"]), float(clear["y"]))
	# Defensive legacy fallback: even if a custom navigation provider lacks the
	# clearance API, do not return the grate's occupied centre when its facing is
	# known.
	return preferred


func _index_of(vents: Array, vent_id: String) -> int:
	for entry in vents:
		if String(entry.get("id", "")) == vent_id:
			return int(entry["index"])
	return -1


## 2D: she can only attack a player who is inside the vent network; an idle, invisible Verrine grabs nobody.
func immune_to_capture() -> bool:
	return not _active_in_vent
