class_name RouteInteractable3D
extends Node3D

## 3D counterpart to src/game/interactable.gd — same kind/activate contract,
## rendered as a simple emissive marker mesh instead of a 2D _draw() glyph
## until real 3D props (see art/props-3d/) are wired in per kind.

enum Kind {
	RELAY,
	BATTERY,
	SAFE_ZONE,
	LIFT,
}

@export var kind: Kind = Kind.RELAY
@export var prompt_text := "INTERACT"
@export var accent_color := Color(0.35, 0.9, 0.8)

var completed := false

var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("interactable")
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.26
	mesh.height = 0.52
	mesh.radial_segments = 12
	mesh.rings = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0, 0.5, 0)

	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 0.8
	mesh_instance.material_override = _material
	add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.5, 0)
	light.light_energy = 0.4
	light.omni_range = 2.0
	light.light_color = accent_color
	add_child(light)

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
	if _material == null:
		return
	var color := accent_color.darkened(0.72) if completed else accent_color
	_material.albedo_color = color
	_material.emission = color
