extends Node

@onready var player: PlayerController = %Player
@onready var status_label: Label = %StatusLabel
@onready var pause_label: Label = %PauseLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.start_new_run()
	player.flashlight_changed.connect(_on_flashlight_changed)
	_update_status()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		get_tree().paused = not get_tree().paused
		pause_label.visible = get_tree().paused

	_update_status()


func _update_status() -> void:
	status_label.text = "DEPTH %02d   POS %03d,%03d   LAMP %s" % [
		GameState.depth,
		int(player.position.x),
		int(player.position.y),
		"ON" if player.flashlight_enabled else "OFF",
	]


func _on_flashlight_changed(_enabled: bool) -> void:
	_update_status()

