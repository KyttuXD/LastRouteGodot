class_name RouteInteractable3D
extends Node3D

## 3D counterpart to src/game/interactable.gd — same kind/activate contract.
## Its visual is instanced from art/props-3d/interactables/<kind>.tscn (see
## ModelSlot.instantiate) rather than any hardcoded geometry, so swapping
## that scene's contents for a real model needs no code change here. The
## completed/not-completed state is shown by toggling a glow light rather
## than recoloring the model — a real imported model can be as structurally
## complex as it needs to be (multiple meshes, a skeleton) with nothing here
## assuming otherwise.

enum Kind {
	RELAY,
	BATTERY,
	SAFE_ZONE,
	LIFT,
	HEATER_STATION,
	HIDING_SPOT,
	MUSIC_BOX,
	VENT,
}

## The facility's single heater station, and Wynelle's counterplay. Three
## states, mirroring the original's interactionState: FROZEN (useless),
## UNFROZEN (dematerialises her but doesn't stop the cold building again),
## POWERED (holds her progress at zero and warms the facility).
enum HeaterState {
	FROZEN,
	UNFROZEN,
	POWERED,
}

const MODEL_SCENES := {
	Kind.RELAY: "res://art/props-3d/interactables/relay.tscn",
	Kind.BATTERY: "res://art/props-3d/interactables/battery.tscn",
	Kind.SAFE_ZONE: "res://art/props-3d/interactables/safe_zone.tscn",
	Kind.LIFT: "res://art/props-3d/interactables/lift.tscn",
	Kind.HEATER_STATION: "res://art/props-3d/interactables/heater_station.tscn",
	Kind.HIDING_SPOT: "res://art/props-3d/interactables/hiding_spot.tscn",
	Kind.MUSIC_BOX: "res://art/props-3d/interactables/music_box.tscn",
	Kind.VENT: "res://art/props-3d/interactables/vent.tscn",
}
const GLOW_COLORS := {
	Kind.RELAY: Color(0.26, 0.88, 0.92),
	Kind.BATTERY: Color(0.95, 0.82, 0.25),
	Kind.SAFE_ZONE: Color(0.35, 0.95, 0.52),
	Kind.LIFT: Color(0.76, 0.55, 0.96),
	Kind.HEATER_STATION: Color(0.98, 0.55, 0.25),
	Kind.HIDING_SPOT: Color(0.45, 0.60, 0.70),
	Kind.MUSIC_BOX: Color(0.85, 0.65, 0.35),
	Kind.VENT: Color(0.30, 0.70, 0.55),
}

## Something happened here that the rest of the room has to know about. Carries
## the cell rather than this node, because the peer receiving it has its own
## node standing on that cell.
signal changed(event: Dictionary)

@export var kind: Kind = Kind.RELAY
@export var prompt_text := "INTERACT"

var completed := false
## Which generated cell this came from, so activate() can mark that entry
## collected in the generator's own arrays.
var source_cell := Vector2i(-1, -1)
var generator: FacilityGenerator
## Heater station only.
var heater_state: HeaterState = HeaterState.FROZEN
## Vent only -- which entry in FacilityGenerator.vents this node stands on.
var vent_id := ""

var _light: OmniLight3D
## The model itself, kept so a collected pickup can actually leave.
var _visual: Node3D


func _ready() -> void:
	add_to_group("interactable")

	_visual = ModelSlot.instantiate(MODEL_SCENES[kind])
	if _visual:
		add_child(_visual)

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.5, 0)
	_light.light_energy = 0.4
	_light.omni_range = 2.0
	_light.light_color = GLOW_COLORS[kind]
	add_child(_light)

	_refresh_visual()


func get_prompt() -> String:
	if kind == Kind.RELAY and sabotaged:
		return "[ HOLD E ] RESTORE SABOTAGED RELAY"
	if completed or disabled:
		return ""
	if kind == Kind.LIFT:
		if GameState.relays_collected < GameState.relay_target:
			return "%s — NEED %d RELAY" % [prompt_text, GameState.relay_target]
		if GameState.relays_sabotaged > 0:
			return "%s — SIGNAL LOST // %d RELAY OFFLINE" % [prompt_text, GameState.relays_sabotaged]
	return prompt_text


func activate(player: PlayerController3D) -> String:
	if completed:
		return "Already collected."

	match kind:
		Kind.RELAY:
			_take()
			changed.emit({"what": "pickup", "cell": source_cell, "kind": kind})
			return "Signal relay recovered."
		Kind.BATTERY:
			_take()
			# The charge is the one part that is NOT shared: the battery leaves
			# the floor for everyone, but it goes in the lamp of whoever walked
			# to it.
			player.restore_lamp(GameConfig.BATTERY_RECHARGE)
			changed.emit({"what": "pickup", "cell": source_cell, "kind": kind})
			return "Battery recovered: +%d%% lamp." % int(GameConfig.BATTERY_RECHARGE)
		Kind.SAFE_ZONE:
			player.restore_at_safe_zone()
			return "Safe zone: lamp and stamina restored."
		Kind.HIDING_SPOT:
			# A locker is a toggle, not a pickup: the same key gets you in and
			# back out, and it never completes.
			if player.hidden_spot == source_cell:
				return player.leave_hiding()
			return player.enter_hiding(source_cell)
		Kind.MUSIC_BOX:
			# Never completes either -- winding it is a thing you keep doing,
			# not a thing you finish. Resolved by whoever owns Glyra's gimmick
			# (main_3d), the same indirection Ceryth's riddle uses, since a
			# plain interactable has no business knowing what a hunter is.
			if player.music_box_resolver.is_valid():
				return String(player.music_box_resolver.call())
			return "Nothing happens."
		Kind.VENT:
			# Never completes, and the prompt stays the same coming or going --
			# a simplification of the original's context-sensitive text, which
			# knew whether Verrine herself was inside. Resolved the same
			# indirection as the music box, since a plain interactable has no
			# business knowing what a hunter is.
			if player.vent_resolver.is_valid():
				return String(player.vent_resolver.call(vent_id))
			return "Nothing happens."
		Kind.LIFT:
			if GameState.relays_collected < GameState.relay_target:
				return "The service lift has no route signal."
			if GameState.relays_sabotaged > 0:
				return "The service lift has no route signal — a relay is offline."
			GameState.descend()
			# The lift takes the whole shift down, not just the person who
			# pressed the button -- a floor half the room has left is not a
			# floor anyone can finish.
			changed.emit({"what": "descend", "depth": GameState.depth})
			return "Descending to depth %d..." % GameState.depth
		Kind.HEATER_STATION:
			# Two-step: thaw it, then power it. Thawing alone is enough to
			# dematerialise Wynelle; only powering it holds her off for good.
			var message := ""
			match heater_state:
				HeaterState.FROZEN:
					heater_state = HeaterState.UNFROZEN
					message = "Heater station thawed. Power it to hold the cold off."
				HeaterState.UNFROZEN:
					heater_state = HeaterState.POWERED
					message = "Heater station powered. The facility is warming."
				HeaterState.POWERED:
					heater_state = HeaterState.UNFROZEN
					message = "Heater station powered down."
			_refresh_visual()
			# One station warms one building. Wynelle reads its state, so a room
			# that disagreed about it would have her dematerialised in one
			# window and hunting in another.
			changed.emit({"what": "heater", "state": heater_state})
			return message

	return "Nothing happens."


## Briselle's counter (RELAY only). Sabotaged is not "uncollected" -- the
## relay stays completed=true (GameState.relays_collected never decreases,
## same split the original makes) but goes offline and blocks the lift until
## someone holds [E] here to bring it back.
var sabotaged := false


## The part of a pickup that is true for everyone in the room, kept in one place
## so the peer that walked to it and the peers that heard about it cannot end up
## in different states.
func _take() -> void:
	completed = true
	_mark_collected_in_generator()
	if kind == Kind.RELAY:
		GameState.relays_collected += 1
		GameState.score += 100
	_refresh_visual()


## Called after RESECURE_SECONDS held near a sabotaged relay -- see
## PlayerController3D's hold tracking. The one direct-action entry point:
## Briselle's OWN sabotage never calls this -- her gimmick raises a
## world_event the same way Ysolde's theft does, applied here (and on every
## other peer) through adopt() below, so the host is not treated as a
## special case. This one emits `changed`, for the room to hear about it;
## adopt() shares the mutation but must not re-emit, or a peer receiving the
## event would immediately re-broadcast it back out.
func set_sabotaged(value: bool) -> String:
	var message := _apply_sabotage(value)
	if not message.is_empty():
		changed.emit({"what": "sabotage", "cell": source_cell, "sabotaged": value})
	return message


func _apply_sabotage(value: bool) -> String:
	if kind != Kind.RELAY or sabotaged == value:
		return ""
	sabotaged = value
	GameState.relays_sabotaged = maxi(0, GameState.relays_sabotaged + (1 if value else -1))
	_refresh_visual()
	return "SIGNAL LOST // RELAY OFFLINE" if value else "RELAY BACK ONLINE"


## Apply what another peer did here. Same effects as activate(), minus anything
## personal to the player who triggered it, and without re-broadcasting.
func adopt(event: Dictionary) -> void:
	match String(event.get("what", "")):
		"pickup":
			if not completed:
				_take()
		"heater":
			heater_state = event.get("state", heater_state) as HeaterState
			_refresh_visual()
		"sabotage":
			# _apply_sabotage(), not set_sabotaged() -- this event ALREADY
			# happened elsewhere; re-emitting `changed` here would broadcast it
			# straight back out and every peer would echo it forever. Still
			# goes through the shared mutation, not a direct field write, so
			# GameState.relays_sabotaged stays right on every peer, not just
			# whichever one caused it.
			_apply_sabotage(bool(event.get("sabotaged", false)))


## Keeps the generator's own relay/battery data in step with what the player
## has actually picked up, so hunter gimmicks that read it see the truth.
func _mark_collected_in_generator() -> void:
	if generator == null:
		return
	match kind:
		Kind.RELAY:
			generator.mark_collected(generator.relays, source_cell)
		Kind.BATTERY:
			generator.mark_collected(generator.batteries, source_cell)


func reset_for_floor() -> void:
	completed = false
	_refresh_visual()


## Things you PICK UP leave when picked up. Only the light was being hidden, so
## a recovered relay sat there looking exactly like an uncollected one with the
## glow off -- which reads as the interaction having failed, not as a pickup.
##
## Fixtures are the other case and stay put: a safe zone, the lift and the
## heater station are part of the building, and the heater in particular has to
## remain visible because its three states are the whole of Wynelle's
## counterplay.
const PICKUPS := [Kind.RELAY, Kind.BATTERY]


## Loxelle's incinerator only, and distinct from `completed`: a broken hiding
## spot is not gone forever the way a collected relay is, it comes back after a
## regeneration window. Kept as its own flag so that window cannot be confused
## with the pickup/fixture split _refresh_visual otherwise draws.
var disabled := false


func set_disabled(value: bool) -> void:
	disabled = value
	_refresh_visual()


func _refresh_visual() -> void:
	# A sabotaged relay is completed (never un-collected) but goes back on
	# display -- it is not a pickup waiting to be taken again, it is a fixture
	# with a problem, the same reason the heater station stays visible.
	var taken := (completed and PICKUPS.has(kind) and not sabotaged) \
		or (kind == Kind.HIDING_SPOT and disabled)
	if _visual:
		_visual.visible = not taken
	if _light:
		_light.visible = not completed or sabotaged
		if kind == Kind.RELAY:
			_light.light_color = Color(0.95, 0.25, 0.25) if sabotaged else GLOW_COLORS[kind]
	# Collision goes with it, so a collected relay is not still something the
	# player bumps into on an empty tile -- restored while sabotaged, since
	# there is something there to walk up to again.
	for child in get_children():
		if child is CollisionObject3D:
			(child as CollisionObject3D).process_mode = \
				Node.PROCESS_MODE_DISABLED if taken else Node.PROCESS_MODE_INHERIT
