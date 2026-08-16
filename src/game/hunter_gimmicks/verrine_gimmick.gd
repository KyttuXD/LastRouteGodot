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
## place_hiding_spots() lives there for Ceryth/Jyvra/Loxelle.

var _active_in_vent := false
var _speed_scale := 1.0


func after_perception(brain: HunterBrain, _delta: float, target: Dictionary, _generator: FacilityGenerator) -> void:
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


## Entry/transit/exit through the network. `vent_id` is whichever grate the
## player just pressed [E] at -- not necessarily the one they entered
## through, since walking the network is a chain of hops through whichever
## grates are reached next.
func use_vent(vent_id: String, brain: HunterBrain, player: PlayerController3D, generator: FacilityGenerator) -> String:
	var vents := generator.vents
	if vents.is_empty():
		return "The grate won't budge."
	var index := _index_of(vents, vent_id)
	if index < 0:
		return "The grate won't budge."
	var count := vents.size()

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

	var world := Vector2(float(next["x"]) + 0.5, float(next["y"]) + 0.5)
	player.global_position = Vector3(world.x, player.global_position.y, world.y)
	return "VENT TRANSIT // %s" % String(next["id"]).to_upper()


func _index_of(vents: Array, vent_id: String) -> int:
	for entry in vents:
		if String(entry.get("id", "")) == vent_id:
			return int(entry["index"])
	return -1
