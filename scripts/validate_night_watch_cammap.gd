extends RefCounted

## The camera screen's minimap (NightWatchCamMap), for every mode that supplies a layout with cameras (NightWatchMapRegistry), plus a synthetic crowded layout: every camera appears
## on the map exactly once with a CAM n button, every map room is reachable from the entrances, the map and its buttons fit the screen at 480x270, 1280x720 and 1920x1080, buttons do
## not overlap each other, the map does not cover the picture's labels or the close strip, the active camera's highlight follows the selection (set_cam), pressing a button selects its
## camera, and the room names reach the feed label.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _stress_layout() -> Dictionary:
	var rooms := {}
	var cams := []
	var labels := {}
	for i in 12:
		var id := "r%d" % i
		rooms[id] = Vector3(float(i % 4) * 2.0 + (0.3 if i % 2 == 0 else 0.0), 0.0, float(i / 4) * 1.5)   # crowded: rooms close together
		cams.append(id)
		labels[id] = "ROOM %d" % i
	rooms["vent"] = Vector3(3.0, 0.0, 0.7)
	var edges := []
	for i in 11:
		edges.append(["r%d" % i, "r%d" % (i + 1)])
	edges.append(["r5", "vent"])
	return {"rooms": rooms, "edges": edges, "entrances": ["r8", "r11"], "cams": cams, "labels": labels, "vents": ["vent"], "theme": "stress"}


func run(host: Node) -> int:
	var layouts := {"classic": NightWatchMapRegistry.classic_layout(), "stress": _stress_layout()}
	for mode_id in NightWatchMapRegistry.MAPS:
		if mode_id == "classic":
			continue
		var layout := NightWatchMapRegistry.layout_for(String(mode_id))
		if not layout.is_empty() and layout.has("cams"):
			layouts[mode_id] = layout
		elif not layout.is_empty() and NightWatchOfficeRegistry.spec_for(String(mode_id)).has_monitor:
			_expect(false, "%s has a camera monitor but its layout gives no cams / labels" % mode_id)
	for name in layouts:
		await _check_layout(host, String(name), layouts[name])
	if _failures == 0:
		print("  night_watch_cammap  minimap for %s: each camera once, reachable, fits at three sizes, no overlaps, highlight follows, buttons select" % ", ".join(PackedStringArray(layouts.keys())))
	return _failures


func _check_layout(host: Node, name: String, layout: Dictionary) -> void:
	var rooms: Dictionary = layout["rooms"]
	var cams: Array = layout["cams"]
	var labels: Dictionary = layout.get("labels", {})
	var tag := "[%s] " % name
	# data: every camera is a room, once; every room is reachable from the entrances; vents exist; every camera has a label
	var seen := {}
	for c in cams:
		_expect(rooms.has(c) and not seen.has(c), tag + "camera %s is not a room or is listed twice" % c)
		seen[c] = true
		_expect(labels.has(c) and not String(labels[c]).is_empty(), tag + "camera %s has no label" % c)
	for v in layout.get("vents", []):
		_expect(rooms.has(v), tag + "vent %s is not a room" % v)
	var adj := {}
	for e in layout["edges"]:
		adj[e[0]] = adj.get(e[0], []) + [e[1]]
		adj[e[1]] = adj.get(e[1], []) + [e[0]]
	var reach := {}
	var queue: Array = (layout["entrances"] as Array).duplicate()
	for q in queue:
		reach[q] = true
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for n in adj.get(cur, []):
			if not reach.has(n):
				reach[n] = true
				queue.append(n)
	_expect(reach.size() == rooms.size(), tag + "only %d of %d map rooms are reachable from the entrances" % [reach.size(), rooms.size()])
	for size in [Vector2i(480, 270), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = true
		host.add_child(vp)
		var hud := NightWatchHud.new()
		vp.add_child(hud)
		await host.get_tree().process_frame
		hud.set_cam_layout(layout)
		hud.set_monitor_guide(NightWatchControls.hint_line(true), NightWatchControls.key_text(NightWatchControls.MONITOR))
		hud.show_monitor(true)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var t := "%s[%s] " % [tag, str(size)]
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		var map := hud.cam_map.get_global_rect()
		_expect(hud.cam_map.buttons.size() == cams.size(), t + "%d CAM buttons for %d cameras" % [hud.cam_map.buttons.size(), cams.size()])
		_expect(screen.encloses(map), t + "the map leaves the screen")
		var rects := []
		for room in hud.cam_map.buttons:
			var r := ((hud.cam_map.buttons[room] as Button).get_parent() as Control).get_global_rect()
			_expect(map.grow(0.5).encloses(r), t + "the CAM button of %s leaves the map: button %s map %s" % [room, str(r), str(map)])
			rects.append(r)
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				_expect(not (rects[i] as Rect2).intersects(rects[j]), t + "two CAM buttons overlap")
		_expect(not map.intersects(hud.cam_label.get_global_rect()) and not map.intersects(hud.rec_label.get_global_rect()), t + "the map covers the camera labels")
		_expect(not map.intersects(hud.close_button.get_global_rect()) and not map.intersects(hud.monitor_guide.get_global_rect()), t + "the map covers the close strip")
		# the active highlight follows the selection, the label shows the room's own name
		var first := String(cams[0])
		var last := String(cams[cams.size() - 1])
		for room in [first, last]:
			hud.set_cam(room, Transform3D.IDENTITY)
			for r in hud.cam_map.buttons:
				var lit := (hud.cam_map.buttons[r] as Button).modulate == NightWatchCamMap.AMBER
				_expect(lit == (r == room), t + "highlight on %s while %s is selected" % [r, room])
			_expect(hud.cam_label.text.contains(String(labels[room])) and hud.cam_label.text.contains("CAM %d" % (cams.find(room) + 1)), t + "the feed label '%s' lacks the camera's number or name" % hud.cam_label.text)
		var picked := [""]
		hud.camera_selected.connect(func(room: String): picked[0] = room)
		(hud.cam_map.buttons[last] as Button).pressed.emit()
		_expect(picked[0] == last, t + "pressing the last CAM button did not select its camera")
		vp.queue_free()
		await host.get_tree().process_frame
