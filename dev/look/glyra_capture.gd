extends Node

## Glyra and her music box (GlyraGimmick), for a clip with sound: record with the Movie Maker so the tune, her hum,
## the off-key wind-down and the silence are in it.
##   godot --path . --write-movie OUT.avi --fixed-fps 30 res://dev/look/glyra_capture.tscn
## Timeline (the box clock runs faster than real time so it fits): PLAYING ~4 s (she hums near the box and ignores the
## runner), WINDING_DOWN ~5 s (the tune slows and wobbles, she gets restless), STOPPED (silence, she hunts the runner
## fast). The caption names the stage for the viewer; the game itself shows no HUD for it.

const Field := preload("res://tests/validate_glyra_music.gd").Field
const BOX := Vector2(20.5, 20.5)
const RUNNER := Vector2(20.5, 30.5)
const STEP := 1.0 / 30.0

var _field
var _boxes := MusicBoxes.new()
var _view: HunterView3D
var _caption: Label
var _clock := 0.0


func _ready() -> void:
	_field = Field.new()
	_field.rooms = [{"id": "a", "center": Vector2i(16, 18)}, {"id": "b", "center": Vector2i(25, 18)},
		{"id": "c", "center": Vector2i(16, 25)}, {"id": "d", "center": Vector2i(25, 25)}]   # wander spots around the box
	_boxes.set_seconds_left("TEST:music_box", GameConfig.MUSIC_BOX_WINDDOWN_SECONDS + 4.0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.04, .04, .06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.45, .45, .52)
	add_child(env)
	for spot in [Vector3(20.5, 2.6, 21.5), Vector3(20.5, 2.6, 27.5)]:
		var lamp := OmniLight3D.new()
		lamp.position = spot
		lamp.omni_range = 8.0
		lamp.light_energy = 1.4
		add_child(lamp)
	_box(Vector3(14, -.2, 16), Vector3(13, .2, 17), Color(.3, .29, .3))
	_box(Vector3(14, 0, 16), Vector3(13, 3, .3), Color(.5, .48, .45))
	_box(Vector3(14, 0, 16), Vector3(.3, 3, 17), Color(.5, .48, .45))
	_box(Vector3(26.7, 0, 16), Vector3(.3, 3, 17), Color(.5, .48, .45))
	var music_box := RouteInteractable3D.new()
	music_box.kind = RouteInteractable3D.Kind.MUSIC_BOX
	music_box.music_box_id = "TEST:music_box"
	music_box.music_boxes = _boxes
	music_box.position = Vector3(BOX.x, .04, BOX.y)
	add_child(music_box)
	var brain := HunterBrain.new(BOX + Vector2(2, 1), "GLYRA-CAPTURE", "glyra", "standard")
	(brain.gimmick as GlyraGimmick).boxes = _boxes
	brain.activate_at(BOX + Vector2(2, 1))
	brain.state = HunterBrain.State.IDLE
	brain.idle_timer = .5
	_view = HunterView3D.new()
	_view.brain = brain
	add_child(_view)
	var camera := Camera3D.new()
	camera.fov = 62.0
	camera.position = Vector3(RUNNER.x, 1.6, RUNNER.y)
	add_child(camera)
	camera.look_at(Vector3(BOX.x, 1.0, BOX.y), Vector3.UP)
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 28)
	layer.add_child(_caption)


func _box(origin: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = origin + size * .5
	add_child(mesh)


func _process(_delta: float) -> void:
	_clock += STEP
	var brain := _view.brain
	var glyra := brain.gimmick as GlyraGimmick
	# 1x while it plays, 3x through the wind-down so 15 s of spring fit in 5
	_boxes.tick(STEP * (3.0 if glyra.mood == MusicBoxes.Mood.WINDING_DOWN else 1.0))
	var hunting := glyra.mood == MusicBoxes.Mood.STOPPED
	var target := {"peer_id": 1, "position": RUNNER, "hidden": not hunting, "in_safe_zone": false, "noise": .4,
		"flashlight_on": true, "sprinting": false, "facing": Vector2(0, -1), "lamp_charge": 100.0, "meters": null,
		"heater_unfrozen": false, "heater_powered": false}
	var caught := brain.update(STEP, _field, target, 1, 0)
	_view.set_look_target(RUNNER if hunting else null)
	_view.sync_from_brain()
	_caption.text = ["MUSIC PLAYING  (calm, humming)", "MUSIC WINDING DOWN  (restless)", "MUSIC STOPPED  (hunting)"][int(glyra.mood)]
	if caught or brain.position.distance_to(RUNNER) < 1.0 or _clock > 20.0:
		print("done t=%.1f mood=%d caught=%s" % [_clock, glyra.mood, caught])
		get_tree().quit()
