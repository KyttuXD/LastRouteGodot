extends Node

## Live end-to-end check of real-place City maps against the TEST server (needs the network; not part of validate_all):
##   godot --path . res://scenes/osm_city_live_test.tscn -- --backend=http://lastroute.kyttuslab.org:8205 \
##       [--osm-map=lower-manhattan] [--capture=/abs/shot.png]
## Signs up a throwaway account, checks that listing fails signed out, downloads and verifies a map, builds the
## OsmCityLayout and every chunk through CityRouteGenerator (shelter, gate, hunters, relays), then starts the run
## and, with --capture, saves a frame from inside it. Exit code 0 = pass.

var _failures := 0
var _map_id := "lower-manhattan"
var _capture := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--osm-map="):
			_map_id = arg.trim_prefix("--osm-map=")
		elif arg.begins_with("--capture="):
			_capture = arg.trim_prefix("--capture=")
	_run.call_deferred()


func _expect(ok: bool, what: String) -> void:
	print(("OSM OK   " if ok else "OSM FAIL ") + what)
	if not ok:
		_failures += 1


func _run() -> void:
	_expect(Backend.base_url.ends_with(":8205"), "talking to the TEST instance (%s)" % Backend.base_url)
	var map := OsmCityMap.new()
	add_child(map)
	map.fetch_list()
	var signed_out: Array = await map.listed
	_expect(not signed_out[0], "signed out: no list (%s)" % signed_out[2])
	Backend.account_register("osmlive%d" % (randi() % 1000000), "osm live test %d" % randi())
	await Backend.account_changed
	_expect(Backend.signed_in(), "throwaway account signed in")
	map.fetch_list()
	var listed: Array = await map.listed
	var entry := {}
	for item in listed[1]:
		if String(item["id"]) == _map_id:
			entry = item
	_expect(listed[0] and not entry.is_empty(), "list has %s (%d maps)" % [_map_id, (listed[1] as Array).size()])
	if entry.is_empty():
		return _finish()
	var started := Time.get_ticks_msec()
	map.download(_map_id, int(entry["version"]))
	var result: Array = await map.downloaded
	_expect(result[0], "downloaded + verified %s v%d in %d ms (%s)" % [_map_id, int(entry["version"]),
		Time.get_ticks_msec() - started, result[1]])
	if not result[0]:
		return _finish()
	_expect(not OsmCityMap.verify_manifest(map.files["manifest.json"] + PackedByteArray([32]), map.files["manifest.rsa.sig"]),
		"a changed manifest fails the signature check")
	started = Time.get_ticks_msec()
	var layout := OsmCityLayout.from_map(map, "OSM-LIVE")
	_expect(true, "layout built in %d ms, window %s, %d buildings (%d enterable)" % [Time.get_ticks_msec() - started,
		layout.window_origin, layout.buildings.size(), layout.buildings.filter(func(b): return not b["sealed"]).size()])
	_expect(layout.is_open(layout.spawn.x, layout.spawn.y), "spawn kiosk is open")
	_expect(layout.is_open(CityLayout.GATE_CELL.x, CityLayout.GATE_CELL.y), "gate apron is open and reachable")
	var generator := CityRouteGenerator.new("OSM-LIVE", layout)
	var chunks := 0
	var hunters := 0
	var fixtures := 0
	var pickups := 0
	var rooms := 0
	var has_gate := false
	for z in range(layout.chunk_min().y, layout.chunk_max().y + 1):
		for x in range(layout.chunk_min().x, layout.chunk_max().x + 1):
			var coord := Vector3i(x, 0, z)
			if not generator.is_chunk_allowed(coord):
				continue
			var data: Dictionary = generator.chunk(coord)
			chunks += 1
			hunters += (data["hunter_spawns"] as Array).size()
			fixtures += (data["fixtures"] as Array).size()
			pickups += (data["pickups"] as Array).size()
			rooms += (data["rooms"] as Array).size()
			for pickup in data["pickups"]:
				has_gate = has_gate or String(pickup.get("kind", "")) == "gate"
	_expect(generator.is_safe_room(Vector3i.ZERO), "chunk (0,0) is the spawn safe room")
	_expect(chunks >= 30, "%d playable chunks" % chunks)
	_expect(hunters > 0 and fixtures > 0, "%d hunter spawns, %d fixtures (relays etc.), %d pickups, %d rooms" % [hunters,
		fixtures, pickups, rooms])
	_expect(has_gate, "the dome gate pickup is placed")
	map.files = {}
	if _capture.is_empty():
		return _finish()
	# keep this checker alive across the scene change into the run
	var tree := get_tree()
	if tree.current_scene == self:
		tree.current_scene = null
	reparent(tree.root)
	OsmCityRun.start(tree, layout)
	await get_tree().create_timer(14.0).timeout
	var scene := get_tree().current_scene
	_expect(scene != null and scene.scene_file_path == OsmCityRun.CITY_SCENE, "the City scene is running the real place")
	var frames := Engine.get_frames_drawn()
	await get_tree().create_timer(4.0).timeout
	_expect(true, "%.1f fps in the run" % ((Engine.get_frames_drawn() - frames) / 4.0))
	get_viewport().get_texture().get_image().save_png(_capture)
	print("OSM capture saved to ", _capture)
	_finish()


func _finish() -> void:
	print("OSM LIVE TEST %s (%d failures)" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
