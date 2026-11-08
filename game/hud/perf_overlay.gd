class_name PerfOverlay
extends CanvasLayer

## admin/debug live FPS + spike flash. Reuses PerfLog (SPIKE_MS 33.3).
## Off by default — toggle from admin VISUAL TOOLS. Not shown in release without tools.

const REFRESH_SEC := 0.2


static func install(root: Node) -> PerfOverlay:
	var existing := root.get_node_or_null("PerfOverlay") as PerfOverlay
	if existing != null:
		return existing
	var overlay := PerfOverlay.new()
	overlay.name = "PerfOverlay"
	root.add_child.call_deferred(overlay)
	return overlay


var _label: Label
var _refresh_left := 0.0


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.name = "PerfOverlayLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 8)
	_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_label.offset_left = 6
	_label.offset_top = 28
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	var show := Build.tools_enabled() and Settings.admin_preference("perf_overlay")
	if not show:
		_label.visible = false
		return
	_refresh_left -= delta
	if _refresh_left > 0.0 and _label.visible:
		# Still tick flash colour while holding text.
		_paint(PerfLog.instance())
		return
	_refresh_left = REFRESH_SEC
	var perf := PerfLog.instance()
	if perf == null:
		perf = PerfLog.ensure(get_tree().root)
	_label.visible = true
	_paint(perf)


func _paint(perf: PerfLog) -> void:
	if perf == null:
		_label.text = "FPS -- | waiting PerfLog"
		_label.add_theme_color_override("font_color", Palette.MUTED)
		return
	var fps := perf.live_fps()
	var ms := perf.last_frame_ms()
	var line := "FPS %.0f | %.1f ms" % [fps, ms]
	var spike := perf.last_spike()
	if not spike.is_empty():
		line += " | SPIKE %.1f ms %s (n=%d)" % [
			float(spike.get("ms", 0.0)), String(spike.get("tag", "?")), perf.spike_count()]
	_label.text = line
	if perf.spike_flash_left() > 0.0:
		_label.add_theme_color_override("font_color", Palette.ALERT)
	else:
		_label.add_theme_color_override("font_color", Palette.AMBER if ms > PerfLog.SPIKE_MS * 0.75 else Palette.BODY)
