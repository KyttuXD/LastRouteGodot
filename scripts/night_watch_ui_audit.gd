class_name NightWatchUiAudit
extends RefCounted

## The checks every Night Watch screen must pass at every window size (scripts/validate_night_watch_ui.gd runs them over the whole game): no visible text control clipped by the window or by its scroll
## area, no two of them overlapping, text that is large and contrasty enough, every control reachable by keyboard/d-pad with a visible focus ring, a Night Watch theme (never the Last Route / City one) behind every
## control, and no hover that selects. Each function returns a list of failure strings; the caller prefixes the screen and size.

const NW_THEME := "res://src/ui/theme_nightwatch.tres"
const MIN_FONT := 5
const MIN_CONTRAST := 4.5
## large text (title logo, card headings: 14 units and up) needs 3:1 (WCAG)
const LARGE_CONTRAST := 3.0
const LARGE_FONT := 14
const BASE := Color(0.03, 0.03, 0.04)
## what is behind text that sits straight on the menu scene: the lit office under the menu's 60% dark tint
const MENU_SCENE := Color(0.16, 0.14, 0.12)

## Controls that are pointer-only ON PURPOSE: each has a key (and a d-pad button) that does the same thing, which the key hint names.
## (the Cam_<room> buttons of the minimap are the number keys 1-8; the hint line names them)
const POINTER_ONLY := ["PauseButton", "CamerasButton", "CloseCamerasButton", "CallMute", "MuteButton"]


static func _is_leaf(c: Control) -> bool:
	if c is Label:
		return not (c as Label).text.is_empty()
	return c is BaseButton or c is LineEdit or c is Slider or c is TextEdit or c is RichTextLabel or c is TabBar


static func _all_controls(node: Node, out: Array) -> void:
	if node is Control:
		if not (node as Control).visible:
			return
		out.append(node)
	if node is SubViewport:
		return
	for ch in node.get_children():
		_all_controls(ch, out)


## the rect of `c` that is actually on screen: clipped by every ScrollContainer above it and by the window
static func visible_rect(c: Control, view: Rect2) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer or (p is Control and (p as Control).clip_contents):
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


static func _luminance(col: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(col.r) + 0.7152 * f.call(col.g) + 0.0722 * f.call(col.b)


static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _flat_bg(box: StyleBox) -> Color:
	if box is StyleBoxFlat and (box as StyleBoxFlat).draw_center:
		return (box as StyleBoxFlat).bg_color
	return Color(0, 0, 0, 0)


## the colour behind a control's text: its own button face, else the nearest panel above it, else the dark scene
static func background_of(c: Control, scene := BASE) -> Color:
	var layers: Array[Color] = []
	var panelled := false
	if c is Label and (c as Label).has_theme_stylebox_override("normal"):
		layers.append(_flat_bg(c.get_theme_stylebox("normal")))
	if c is BaseButton:
		layers.append(_flat_bg(c.get_theme_stylebox("disabled" if (c as BaseButton).disabled else "normal")))
	var p: Node = c
	while p != null:
		if p is PanelContainer or p is Panel:
			layers.append(_flat_bg((p as Control).get_theme_stylebox("panel")))
			panelled = true
		elif p is ColorRect:
			layers.append((p as ColorRect).color)
		p = p.get_parent()
	var out := scene
	for i in range(layers.size() - 1, -1, -1):   # outermost first, nearest last
		var l := layers[i]
		out = out * (1.0 - l.a) + Color(l.r, l.g, l.b) * l.a
	return out


static func _font_color(c: Control) -> Color:
	var col := Color.WHITE
	if c is Label or c is BaseButton or c is LineEdit or c is TextEdit or c is RichTextLabel:
		col = c.get_theme_color("font_color")
	var alpha := col.a
	var n: Node = c
	while n is CanvasItem:
		alpha *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a
		n = n.get_parent()
	col.a = alpha
	return col


static func _theme_owner(c: Control) -> Theme:
	var n: Node = c
	while n != null:
		if n is Control and (n as Control).theme != null:
			return (n as Control).theme
		n = n.get_parent()
	return null


## Everything but focus: clipping, overlap, font size and contrast, the theme. `allow_overlap` lists name pairs that overlap by design.
static func layout(root: Node, design: Vector2i, window_scale: float, allow_overlap: Array = [], scene := BASE) -> Array:
	var fails := []
	var view := Rect2(Vector2.ZERO, Vector2(design))
	var all := []
	_all_controls(root, all)
	var leaves := []
	for c in all:
		var control := c as Control
		if not _is_leaf(control):
			continue
		var r := visible_rect(control, view)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue   # scrolled out of view
		leaves.append([control, r])
		# the window
		if not view.grow(0.6).encloses(r):
			fails.append("%s leaves the window: %s inside %s" % [control.name, r, view])
		# the text fits its box (a label that is narrower than its text clips it)
		if control is Label and not (control as Label).autowrap_mode != TextServer.AUTOWRAP_OFF and (control as Label).clip_text:
			var need := (control as Label).get_minimum_size()
			if need.x > control.size.x + 0.5:
				fails.append("%s clips its text: needs %.1f, has %.1f" % [control.name, need.x, control.size.x])
		# font size
		if control is Label or control is BaseButton or control is LineEdit:
			var fs := control.get_theme_font_size("font_size")
			if fs < MIN_FONT:
				fails.append("%s text is %d units: below the %d floor" % [control.name, fs, MIN_FONT])
			elif float(fs) * window_scale < 5.0:
				fails.append("%s text is %.1f px on screen" % [control.name, float(fs) * window_scale])
		# contrast
		if control is Label or control is BaseButton or control is LineEdit:
			if control is BaseButton and (control as BaseButton).disabled:
				pass   # a disabled control is allowed to be dim
			else:
				var fg := _font_color(control)
				var bg := background_of(control, scene)
				var fg_over := bg * (1.0 - fg.a) + Color(fg.r, fg.g, fg.b) * fg.a
				var ratio := contrast(fg_over, bg)
				var needs := LARGE_CONTRAST if control.get_theme_font_size("font_size") >= LARGE_FONT else MIN_CONTRAST
				if ratio < needs:
					fails.append("%s text contrast %.1f:1 (needs %.1f): %s on %s" % [control.name, ratio, needs, fg_over.to_html(false), bg.to_html(false)])
		# a Night Watch theme, never Last Route's
		var th := _theme_owner(control)
		if th == null or not th.has_meta("night_watch"):
			fails.append("%s is not under the Night Watch theme (%s)" % [control.name, "none: the project's Last Route theme" if th == null else "another theme"])
	# overlap
	for i in leaves.size():
		for j in range(i + 1, leaves.size()):
			var a := leaves[i][0] as Control
			var b := leaves[j][0] as Control
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ra: Rect2 = leaves[i][1]
			var rb: Rect2 = leaves[j][1]
			if ra.grow(-0.4).intersects(rb.grow(-0.4)):
				var pair := [String(a.name), String(b.name)]
				if allow_overlap.any(func(p): return (p[0] == pair[0] and p[1] == pair[1]) or (p[0] == pair[1] and p[1] == pair[0])):
					continue
				fails.append("%s overlaps %s: %s / %s" % [a.name, b.name, ra, rb])
	return fails


## Keyboard and d-pad: every enabled control is focusable (or listed POINTER_ONLY) and, walking the four directions from any of them, all of them are reached; the focus ring is drawn.
static func focus(root: Node, extra_pointer_only: Array = []) -> Array:
	var fails := []
	var all := []
	_all_controls(root, all)
	var focusable := []
	for c in all:
		var control := c as Control
		var interactive := control is BaseButton or control is LineEdit or control is Slider or control is TabBar
		if not interactive or (control is BaseButton and (control as BaseButton).disabled):
			continue
		if control.focus_mode == Control.FOCUS_NONE:
			if not POINTER_ONLY.has(String(control.name)) and not String(control.name).begins_with("Cam_") and not extra_pointer_only.has(String(control.name)):
				fails.append("%s cannot be focused: keyboard and gamepad cannot reach it" % control.name)
			continue
		focusable.append(control)
		var ring := control.get_theme_stylebox("focus")
		if control is BaseButton and (ring == null or ring is StyleBoxEmpty):
			fails.append("%s has no visible focus ring" % control.name)
	if focusable.size() > 1:
		var seen := {focusable[0]: true}
		var queue := [focusable[0]]
		while not queue.is_empty():
			var cur := queue.pop_front() as Control
			var nexts := [cur.find_next_valid_focus(), cur.find_prev_valid_focus()]
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				nexts.append(cur.find_valid_focus_neighbor(side))
			for n in nexts:
				if n != null and not seen.has(n):
					seen[n] = true
					queue.append(n)
		for c in focusable:
			if not seen.has(c):
				fails.append("%s is not reached by moving focus (Tab / arrows / d-pad) from %s" % [c.name, (focusable[0] as Control).name])
	return fails
