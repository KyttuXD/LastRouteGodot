class_name RouteInteractable
extends Node2D

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
## Which generated cell this came from, so activate() can mark that entry
## collected in the generator's own arrays.
var source_cell := Vector2i(-1, -1)
var generator: FacilityGenerator


func _ready() -> void:
	add_to_group("interactable")
	queue_redraw()


func get_prompt() -> String:
	if completed:
		return ""
	if kind == Kind.LIFT and GameState.relays_collected < GameState.relay_target:
		return "%s — NEED %d RELAY" % [prompt_text, GameState.relay_target]
	return prompt_text


func activate(player: PlayerController) -> String:
	if completed:
		return "Already collected."

	match kind:
		Kind.RELAY:
			completed = true
			_mark_collected_in_generator()
			GameState.relays_collected += 1
			GameState.score += 100
			queue_redraw()
			return "Signal relay recovered."
		Kind.BATTERY:
			completed = true
			_mark_collected_in_generator()
			player.restore_lamp(GameConfig.BATTERY_RECHARGE)
			queue_redraw()
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
	queue_redraw()


func _draw() -> void:
	var color := accent_color.darkened(0.72) if completed else accent_color
	draw_circle(Vector2.ZERO, 7.0, Color(color.r, color.g, color.b, 0.2))
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 24, color, 2.0)

	match kind:
		Kind.RELAY:
			draw_line(Vector2(0, -5), Vector2(0, 5), color, 2.0)
			draw_circle(Vector2(0, -4), 2.0, color)
		Kind.BATTERY:
			draw_rect(Rect2(-3, -5, 6, 10), color, false, 2.0)
		Kind.SAFE_ZONE:
			draw_line(Vector2(-4, 0), Vector2(4, 0), color, 2.0)
			draw_line(Vector2(0, -4), Vector2(0, 4), color, 2.0)
		Kind.LIFT:
			draw_rect(Rect2(-5, -5, 10, 10), color, false, 2.0)
