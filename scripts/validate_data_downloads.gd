extends RefCounted

## Pack downloads (docs/DATA_DRIVEN_CONTENT.md, "Auto-download"): against a local stand-in for the VPS 3 index and the
## VPS 2 file host, a room's missing pack downloads, verifies and lands in user://mods/.cache/<sha256> where the
## handshake finds it; a tampered file, a blocked pack, a host pack that is not the published version and an index
## path that escapes the pack are all refused with nothing left behind; REMOVE DOWNLOADED MODS removes it again.
##
##   godot --headless --path . res://scenes/validate.tscn -- data_downloads

const ROOT := "user://data_downloads_test"
const SOURCE := "user://data_downloads_src/dlpack"
const PRINTER := "res://art/props-3d/props/maze/office_printer.glb"
const PORT := 18441


## A one-route-table HTTP/1.1 server: GET path (with query) -> body bytes, anything else 404.
class FakeHost extends Node:
	var server := TCPServer.new()
	var routes := {}
	var requests := 0
	var _peers: Array = []

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			_peers.append({"conn": server.take_connection(), "buf": PackedByteArray(), "done": false})
		for peer in _peers.duplicate():
			var conn: StreamPeerTCP = peer["conn"]
			conn.poll()
			if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_peers.erase(peer)
				continue
			if peer["done"]:
				continue
			var available := conn.get_available_bytes()
			if available > 0:
				peer["buf"].append_array(conn.get_data(available)[1])
			var text: String = peer["buf"].get_string_from_ascii()
			if not text.contains("\r\n\r\n"):
				continue
			requests += 1
			var path := text.split(" ")[1]
			var body: PackedByteArray = routes.get(path, PackedByteArray())
			var head := "HTTP/1.1 %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
				"200 OK" if routes.has(path) else "404 Not Found", body.size()]
			conn.put_data(head.to_ascii_buffer())
			conn.put_data(body)
			peer["done"] = true


var _failures := 0
var _host: FakeHost
var _provider: PackDownloads


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var saved_root := RoomPacks.mods_root
	var saved_base := Backend.base_url
	RoomPacks.mods_root = ROOT
	_wipe(ROOT)
	_wipe(SOURCE.get_base_dir())
	_host = FakeHost.new()
	if _host.server.listen(PORT, "127.0.0.1") != OK:
		_expect(false, "could not listen on %d" % PORT)
		return _failures
	host.add_child(_host)
	_provider = PackDownloads.new()
	host.add_child(_provider)
	Backend.use_test_base_url("http://127.0.0.1:%d" % PORT)

	var pack := _source_pack()
	var sha := String(pack["sha256"])
	var entry := {"pack_id": "dlpack", "version": "1.0.0", "name": "Download Pack", "sha256": sha}
	_publish(pack, {})
	var progress := []
	var result: Array = await _download([entry], func(done, total, name): progress.append([done, total, name]))
	_expect(result[0], "download failed: %s" % result[1])
	_expect(not progress.is_empty() and progress.back()[0] == progress.back()[1], "progress never reached the total")
	_expect(RoomPacks.local_dir("dlpack", sha) == ROOT.path_join(".cache").path_join(sha), "downloaded pack not found")
	_expect(_installed("downloaded").size() == 1, "downloaded pack not listed as downloaded")
	_expect(ContentRegistry.load_packs([ROOT.path_join(".cache").path_join(sha)], ContentPacks.LIMITS, false)["ok"],
		"downloaded pack does not load")
	ContentRegistry.unload_packs()
	var before := _host.requests
	result = await _download([entry], func(_d, _t, _n): pass)
	_expect(result[0] and _host.requests == before, "a pack already on disk was downloaded again")

	_expect(_provider.remove_downloaded() == 1 and _installed("downloaded").is_empty(), "remove_downloaded left packs")
	var stranger := entry.duplicate()
	stranger["sha256"] = "0".repeat(64)
	await _refused(stranger, pack, {}, "NOT THE PUBLISHED VERSION")
	await _refused(entry, pack, {"escape": true}, "REFUSES")
	await _refused(entry, pack, {"tamper": true}, "DID NOT MATCH")
	await _refused(entry, pack, {"blocked": true}, "REMOVED BY MODERATORS")

	Backend.use_test_base_url(saved_base)
	RoomPacks.mods_root = saved_root
	_host.server.stop()
	_host.queue_free()
	_provider.queue_free()
	_wipe(ROOT)
	_wipe(SOURCE.get_base_dir())
	if _failures == 0:
		print("  data_downloads OK")
	return _failures


func _refused(entry: Dictionary, pack: Dictionary, how: Dictionary, reason: String) -> void:
	_publish(pack, how)
	var result: Array = await _download([entry], func(_d, _t, _n): pass)
	_expect(not result[0] and String(result[1]).contains(reason), "%s: expected a refusal with \"%s\", got %s" % [how,
		reason, result])
	var cache := ROOT.path_join(".cache")
	var left := DirAccess.get_directories_at(cache) if DirAccess.dir_exists_absolute(cache) else PackedStringArray()
	_expect(left.is_empty(), "%s: a refused download left %s behind" % [how, left])


func _download(packs: Array, on_progress: Callable) -> Array:
	var outcome := []
	_provider.download_packs(packs, on_progress, func(ok: bool, reason: String): outcome.append_array([ok, reason]))
	var deadline := Time.get_ticks_msec() + 20000
	while outcome.is_empty() and Time.get_ticks_msec() < deadline:
		await _host.get_tree().process_frame
	return outcome if not outcome.is_empty() else [false, "timed out"]


## Put the pack on the fake index and file host, optionally broken in one way.
func _publish(pack: Dictionary, how: Dictionary) -> void:
	_host.routes.clear()
	var files := []
	for file in pack["files"]:
		var bytes := FileAccess.get_file_as_bytes(SOURCE.path_join(file["path"]))
		if how.get("tamper", false) and String(file["path"]).ends_with(".glb"):
			bytes[100] = bytes[100] ^ 0xFF
		_host.routes["/files/dlpack/1.0.0/" + String(file["path"])] = bytes
		files.append({"path": file["path"], "sha256": file["sha256"], "size": file["bytes"]})
	if how.get("escape", false):
		files.append({"path": "../escape.json", "sha256": "0".repeat(64), "size": 2})
	var index := {"id": "dlpack", "name": "Download Pack", "version": "1.0.0", "files": files,
		"downloadBase": "http://127.0.0.1:%d/files" % PORT, "blocked": how.get("blocked", false)}
	_host.routes["/api/mods/packs/dlpack?version=1.0.0"] = JSON.stringify(index).to_utf8_buffer()


func _installed(source: String) -> Array:
	return _provider.installed_packs().filter(func(p: Dictionary): return p["source"] == source)


func _source_pack() -> Dictionary:
	_write(SOURCE.path_join("pack.json"), JSON.stringify({"schema": "lr.pack/1", "id": "dlpack",
		"name": "Download Pack", "version": "1.0.0", "author": "validator"}))
	_write(SOURCE.path_join("props/lamp.json"), JSON.stringify({"schema": "lr.prop/1", "family": "lamps",
		"props": [{"id": "dlpack_lamp", "models": ["assets/lamp.glb"]}]}))
	_write(SOURCE.path_join("assets/lamp.glb"), FileAccess.get_file_as_bytes(PRINTER))
	var pack := ContentPacks.read(SOURCE)
	_expect(pack["errors"].is_empty(), "source pack is invalid: %s" % [pack["errors"]])
	return pack


func _write(path: String, content) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if content is PackedByteArray:
		file.store_buffer(content)
	else:
		file.store_string(String(content))
	file.close()


## Delete `dir` and everything in it. Only test folders (their name carries "data_downloads_") are ever touched, and the walk
## uses absolute paths (ContentPacks.os_path) so a user data dir containing "//" cannot point it at the project.
func _wipe(dir: String) -> void:
	var path := ContentPacks.os_path(dir)
	if not path.contains("data_downloads_") or not DirAccess.dir_exists_absolute(path):
		return
	_remove_tree(path)


func _remove_tree(path: String) -> void:
	var access := DirAccess.open(path)
	if access == null:
		return
	access.include_hidden = true
	for name in access.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in access.get_directories():
		if access.is_link(name):
			DirAccess.remove_absolute(path.path_join(name))
		else:
			_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
