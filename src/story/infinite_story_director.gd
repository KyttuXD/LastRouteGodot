class_name InfiniteStoryDirector
extends CanvasLayer

## Host-owned story presentation for Infinite Route. Content is local,
## deterministic JSON; only the compact current state crosses ENet. A story
## may describe an authored PNG stage, but ordinary discovery can never load
## one: map-bearing scenes must be admin_only and are rejected as triggers.

signal state_published(state: Dictionary)
signal active_changed(active: bool)

const CONTENT_PATH := "res://story/infinite_route_stories.json"
const MAX_TEXT_LENGTH := 1200
const MAX_CHOICES := 6

var _content := {}
var _scenes := {}
var _completed_triggers := {}
var _state := {"active": false}
var _authoritative := false
var _wait_remaining := 0.0

var _backdrop: ColorRect
var _panel: PanelContainer
var _speaker: Label
var _body: RichTextLabel
var _choices: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_build_overlay()


func configure(authoritative: bool) -> String:
	_authoritative = authoritative
	var loaded := load_and_validate(CONTENT_PATH)
	if not bool(loaded.get("ok", false)):
		return String(loaded.get("error", "story content is invalid"))
	_content = loaded.get("content", {})
	_scenes = _content.get("scenes", {})
	_render_state()
	return ""


func is_active() -> bool:
	return bool(_state.get("active", false))


func admin_scene_ids() -> Array:
	var result: Array = []
	for scene_id_value in _scenes:
		var scene: Dictionary = _scenes[scene_id_value]
		if bool(scene.get("admin_only", false)):
			result.append(String(scene_id_value))
	result.sort()
	return result


func admin_scene_labels() -> Dictionary:
	var result := {}
	for scene_id_value in admin_scene_ids():
		var scene_id := String(scene_id_value)
		var scene: Dictionary = _scenes.get(scene_id, {})
		result[scene_id] = String(scene.get("label",
			scene_id.replace("_", " ").to_upper()))
	return result


func snapshot() -> Dictionary:
	return {
		"active": is_active(),
		"scene_id": String(_state.get("scene_id", "")),
		"kind": String(_state.get("kind", "")),
		"step_index": int(_state.get("step_index", 0)),
		"dialog_scene_id": String(_state.get("dialog_scene_id", "")),
		"node_id": String(_state.get("node_id", "")),
		"wait_remaining": maxf(0.0, _wait_remaining),
		"completed_triggers": _completed_triggers.duplicate(true),
	}


func adopt_snapshot(value: Dictionary) -> bool:
	var candidate := value.duplicate(true)
	var completed = candidate.get("completed_triggers", {})
	if not completed is Dictionary:
		return false
	_completed_triggers = completed.duplicate(true)
	if not bool(candidate.get("active", false)):
		_set_state({"active": false}, false)
		return true
	var scene_id := String(candidate.get("scene_id", ""))
	var scene: Dictionary = _scenes.get(scene_id, {})
	if scene.is_empty():
		return false
	var dialog_scene_id := String(candidate.get("dialog_scene_id", ""))
	var node_id := String(candidate.get("node_id", ""))
	if not dialog_scene_id.is_empty():
		var dialog: Dictionary = _scenes.get(dialog_scene_id, {})
		if String(dialog.get("kind", "")) != "dialog" \
				or not (dialog.get("nodes", {}) as Dictionary).has(node_id):
			return false
	_wait_remaining = maxf(0.0, float(candidate.get("wait_remaining", 0.0)))
	_set_state(candidate, false)
	return true


func start_admin_scene(scene_id: String, admin_authorized: bool) -> bool:
	## This starts presentation only. If the scene names `custom_map`, the
	## caller must separately use the verified admin custom-map command; this
	## director deliberately has no URL/file loading capability.
	if not _authoritative or not admin_authorized:
		return false
	var scene: Dictionary = _scenes.get(scene_id, {})
	if scene.is_empty() or not bool(scene.get("admin_only", false)):
		return false
	_completed_triggers[scene_id] = true
	_start_scene(scene_id, true)
	return true


func stop_admin_scene(admin_authorized: bool) -> bool:
	if not _authoritative or not admin_authorized or not is_active():
		return false
	_finish_scene()
	return true


func reset_admin_story(admin_authorized: bool) -> bool:
	if not _authoritative or not admin_authorized:
		return false
	_completed_triggers.clear()
	_wait_remaining = 0.0
	_set_state({"active": false}, true)
	return true


func _process(delta: float) -> void:
	if not _authoritative or not is_active() or _wait_remaining <= 0.0:
		return
	_wait_remaining = maxf(0.0, _wait_remaining - delta)
	if _wait_remaining <= 0.0:
		_state["step_index"] = int(_state.get("step_index", 0)) + 1
		_advance_cutscene()


func _start_scene(scene_id: String, admin_request: bool) -> void:
	var scene: Dictionary = _scenes.get(scene_id, {})
	if scene.is_empty():
		return
	if bool(scene.get("admin_only", false)) and not admin_request:
		return
	_state = {"active": true, "scene_id": scene_id,
		"kind": String(scene.get("kind", "dialog")), "step_index": 0,
		"dialog_scene_id": "", "node_id": ""}
	_wait_remaining = 0.0
	if String(scene.get("kind", "")) == "dialog":
		_open_dialog(scene_id, String(scene.get("start", "")))
	else:
		_advance_cutscene()


func _advance_cutscene() -> void:
	var scene: Dictionary = _scenes.get(String(_state.get("scene_id", "")), {})
	var steps: Array = scene.get("steps", [])
	while int(_state.get("step_index", 0)) < steps.size():
		var step: Dictionary = steps[int(_state.get("step_index", 0))]
		var kind := String(step.get("type", ""))
		match kind:
			"wait":
				_wait_remaining = maxf(0.0, float(step.get("seconds", 0.0)))
				_publish()
				if _wait_remaining > 0.0:
					return
			"dialog":
				var dialog_id := String(step.get("scene", ""))
				var dialog: Dictionary = _scenes.get(dialog_id, {})
				_open_dialog(dialog_id, String(step.get("node", dialog.get("start", ""))))
				return
			_:
				# Camera and actor choreography are preserved in content and
				# validated, but deliberately skipped until the 3D rail/path
				# implementation can keep host and guests spatially identical.
				pass
		_state["step_index"] = int(_state.get("step_index", 0)) + 1
	_finish_scene()


func _open_dialog(scene_id: String, node_id: String) -> void:
	_state["dialog_scene_id"] = scene_id
	_state["node_id"] = node_id
	_wait_remaining = 0.0
	_publish()


func _choose(choice_index: int) -> void:
	if not _authoritative or not is_active():
		return
	var dialog: Dictionary = _scenes.get(String(_state.get("dialog_scene_id", "")), {})
	var nodes: Dictionary = dialog.get("nodes", {})
	var node: Dictionary = nodes.get(String(_state.get("node_id", "")), {})
	var choices: Array = node.get("choices", [])
	var next_id := ""
	if not choices.is_empty():
		if choice_index < 0 or choice_index >= choices.size():
			return
		next_id = String((choices[choice_index] as Dictionary).get("next", ""))
	else:
		next_id = String(node.get("next", ""))
	if not next_id.is_empty():
		_state["node_id"] = next_id
		_publish()
		return
	_state["dialog_scene_id"] = ""
	_state["node_id"] = ""
	if String(_state.get("kind", "")) == "cutscene":
		_state["step_index"] = int(_state.get("step_index", 0)) + 1
		_advance_cutscene()
	else:
		_finish_scene()


func _finish_scene() -> void:
	_wait_remaining = 0.0
	_set_state({"active": false}, true)


func _publish() -> void:
	_render_state()
	active_changed.emit(is_active())
	state_published.emit(snapshot())


func _set_state(value: Dictionary, publish: bool) -> void:
	_state = value.duplicate(true)
	_render_state()
	active_changed.emit(is_active())
	if publish:
		state_published.emit(snapshot())


func _render_state() -> void:
	if _backdrop == null:
		return
	var dialog_id := String(_state.get("dialog_scene_id", ""))
	var node_id := String(_state.get("node_id", ""))
	var dialog: Dictionary = _scenes.get(dialog_id, {})
	var node: Dictionary = (dialog.get("nodes", {}) as Dictionary).get(node_id, {})
	_backdrop.visible = is_active() and not node.is_empty()
	if not _backdrop.visible:
		return
	_speaker.text = String(node.get("speaker", "SIGNAL")).replace("_", " ").to_upper()
	_body.text = String(node.get("text", ""))
	for child in _choices.get_children():
		child.queue_free()
	var values: Array = node.get("choices", [])
	if values.is_empty():
		_add_choice_button("CONTINUE", 0)
	else:
		for index in values.size():
			_add_choice_button(String((values[index] as Dictionary).get("label", "...")), index)


func _add_choice_button(label_text: String, choice_index: int) -> void:
	var button := Button.new()
	button.text = label_text
	button.disabled = not _authoritative
	button.custom_minimum_size = Vector2(0, 38)
	Palette.style_button(button, choice_index == 0, true)
	button.pressed.connect(_choose.bind(choice_index))
	_choices.add_child(button)


func _build_overlay() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "StoryBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.015, 0.02, 0.025, 0.72)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 0.58
	_panel.anchor_bottom = 0.94
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = 0
	var style := StyleBoxFlat.new()
	style.bg_color = Color("120a10ee")
	style.border_color = Palette.AMBER
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	_backdrop.add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	_panel.add_child(layout)
	_speaker = Label.new()
	Palette.style_label(_speaker, Palette.AMBER, 18)
	layout.add_child(_speaker)
	_body = RichTextLabel.new()
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(0, 70)
	_body.add_theme_color_override("default_color", Palette.INK)
	_body.add_theme_font_size_override("normal_font_size", 18)
	layout.add_child(_body)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	layout.add_child(_choices)
	_backdrop.visible = false


static func load_and_validate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "story file is missing: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "story file cannot be read: %s" % path}
	var value = JSON.parse_string(file.get_as_text())
	file.close()
	if not value is Dictionary:
		return {"ok": false, "error": "story file must contain a JSON object"}
	var content: Dictionary = value
	if int(content.get("schema", 0)) != 1:
		return {"ok": false, "error": "story schema must be 1"}
	var scenes = content.get("scenes", {})
	var triggers = content.get("triggers", [])
	if not scenes is Dictionary or not triggers is Array:
		return {"ok": false, "error": "story scenes/triggers have invalid types"}
	if not triggers.is_empty():
		return {"ok": false, "error":
			"Infinite story triggers must be empty; playback is admin-only"}
	for scene_id_value in scenes:
		var scene_id := String(scene_id_value)
		var scene: Dictionary = scenes[scene_id_value]
		var error := _validate_scene(scene_id, scene, scenes)
		if not error.is_empty():
			return {"ok": false, "error": error}
	for trigger_value in triggers:
		if not trigger_value is Dictionary:
			return {"ok": false, "error": "story trigger must be an object"}
		var trigger: Dictionary = trigger_value
		var target: Dictionary = scenes.get(String(trigger.get("scene", "")), {})
		if String(trigger.get("id", "")).is_empty() or target.is_empty():
			return {"ok": false, "error": "story trigger id/scene is invalid"}
		if bool(target.get("admin_only", false)) or target.has("custom_map"):
			return {"ok": false, "error":
				"ordinary trigger cannot load admin story/custom map"}
	return {"ok": true, "content": content}


static func _validate_scene(scene_id: String, scene: Dictionary,
		scenes: Dictionary) -> String:
	var kind := String(scene.get("kind", ""))
	if scene.has("custom_map") and not bool(scene.get("admin_only", false)):
		return "%s: custom_map requires admin_only" % scene_id
	if kind == "dialog":
		var nodes = scene.get("nodes", {})
		var start := String(scene.get("start", ""))
		if not nodes is Dictionary or not nodes.has(start):
			return "%s: dialog start node is missing" % scene_id
		for node_id_value in nodes:
			var node: Dictionary = nodes[node_id_value]
			if String(node.get("text", "")).is_empty() \
					or String(node.get("text", "")).length() > MAX_TEXT_LENGTH:
				return "%s/%s: dialog text is invalid" % [scene_id, node_id_value]
			var next_ids := []
			if not String(node.get("next", "")).is_empty():
				next_ids.append(String(node.get("next", "")))
			var choices = node.get("choices", [])
			if not choices is Array or choices.size() > MAX_CHOICES:
				return "%s/%s: choices are invalid" % [scene_id, node_id_value]
			for choice_value in choices:
				if not choice_value is Dictionary:
					return "%s/%s: choice must be an object" % [scene_id, node_id_value]
				next_ids.append(String((choice_value as Dictionary).get("next", "")))
			for next_id in next_ids:
				if not nodes.has(next_id):
					return "%s/%s: missing next node %s" % [scene_id, node_id_value, next_id]
		return ""
	if kind == "cutscene":
		var steps = scene.get("steps", [])
		if not steps is Array or steps.is_empty():
			return "%s: cutscene has no steps" % scene_id
		for step_value in steps:
			if not step_value is Dictionary:
				return "%s: cutscene step must be an object" % scene_id
			var step: Dictionary = step_value
			var step_kind := String(step.get("type", ""))
			if step_kind not in ["wait", "dialog", "move_camera", "move_actor", "pose_actor"]:
				return "%s: unknown cutscene step %s" % [scene_id, step_kind]
			if step_kind == "dialog" \
					and String((scenes.get(String(step.get("scene", "")), {}) as Dictionary).get("kind", "")) != "dialog":
				return "%s: cutscene dialog reference is invalid" % scene_id
		return ""
	return "%s: scene kind must be dialog or cutscene" % scene_id
