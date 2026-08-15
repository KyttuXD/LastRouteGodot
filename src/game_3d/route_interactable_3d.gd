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
}

const MODEL_SCENES := {
	Kind.RELAY: "res://art/props-3d/interactables/relay.tscn",
	Kind.BATTERY: "res://art/props-3d/interactables/battery.tscn",
	Kind.SAFE_ZONE: "res://art/props-3d/interactables/safe_zone.tscn",
	Kind.LIFT: "res://art/props-3d/interactables/lift.tscn",
}
const GLOW_COLORS := {
	Kind.RELAY: Color(0.26, 0.88, 0.92),
	Kind.BATTERY: Color(0.95, 0.82, 0.25),
	Kind.SAFE_ZONE: Color(0.35, 0.95, 0.52),
	Kind.LIFT: Color(0.76, 0.55, 0.96),
}

@export var kind: Kind = Kind.RELAY
@export var prompt_text := "INTERACT"

var completed := false

var _light: OmniLight3D


func _ready() -> void:
	add_to_group("interactable")

	var visual := ModelSlot.instantiate(MODEL_SCENES[kind])
	if visual:
		add_child(visual)

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.5, 0)
	_light.light_energy = 0.4
	_light.omni_range = 2.0
	_light.light_color = GLOW_COLORS[kind]
	add_child(_light)

	_refresh_visual()


func get_prompt() -> String:
	if completed:
		return ""
	if kind == Kind.LIFT and GameState.relays_collected < GameState.relay_target:
		return "%s — NEED %d RELAY" % [prompt_text, GameState.relay_target]
	return prompt_text


func activate(player: PlayerController3D) -> String:
	if completed:
		return "Already collected."

	match kind:
		Kind.RELAY:
			completed = true
			GameState.relays_collected += 1
			GameState.score += 100
			_refresh_visual()
			return "Signal relay recovered."
		Kind.BATTERY:
			completed = true
			player.restore_lamp(GameConfig.BATTERY_RECHARGE)
			_refresh_visual()
			return "Battery recovered: +%d%% lamp." % int(GameConfig.BATTERY_RECHARGE)
		Kind.SAFE_ZONE:
			player.restore_at_safe_zone()
			return "Safe zone: lamp and stamina restored."
		Kind.LIFT:
			if GameState.relays_collected < GameState.relay_target:
				return "The service lift has no route signal."
			GameState.descend()
			return "Descending to depth %d..." % GameState.depth

	return "Nothing happens."


func reset_for_floor() -> void:
	completed = false
	_refresh_visual()


func _refresh_visual() -> void:
	if _light:
		_light.visible = not completed
