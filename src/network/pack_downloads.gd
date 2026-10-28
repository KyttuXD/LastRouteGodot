class_name PackDownloads
extends Node

## The mod UI's provider (ModPackApi.provider, HUB lane): the installed pack list, removing downloaded packs, and
## downloading a room's missing packs. Files come from the VPS 2 file host named by the VPS 3 pack index
## (backend/README.md, "Mod packs"); nothing here names a host. Every file is checked against the index's sha256 and
## size, the finished folder against the host's pack sha256, before it is moved into user://mods/.cache/<sha256>.
## A failed or cancelled download leaves nothing behind.

const INDEX_PATH := "/api/mods/packs/%s?version=%s"
const API_SCRIPT := "res://src/mods/mod_pack_api.gd"
const REQUEST_TIMEOUT := 60.0

static var _instance: PackDownloads


## Make this the mod UI's provider when the UI is part of the build. Called once by RoomState._ready().
static func install(parent: Node) -> void:
	if _instance != null or not ResourceLoader.exists(API_SCRIPT):
		return
	_instance = PackDownloads.new()
	_instance.name = "PackDownloads"
	parent.add_child(_instance)
	load(API_SCRIPT).provider = _instance


## [{pack_id, name, author, version, size, sha256, source}] -- hand-installed packs ("local") and downloads
## ("downloaded"). Unreadable folders are left out.
func installed_packs() -> Array:
	var out := []
	for dir in ContentPacks.discover(RoomPacks.mods_root):
		_append_entry(out, dir, "local", true)
	var cache := _cache()
	if DirAccess.dir_exists_absolute(ContentPacks.os_path(cache)):
		for name in DirAccess.get_directories_at(ContentPacks.os_path(cache)):
			if not String(name).begins_with("."):
				_append_entry(out, cache.path_join(name), "downloaded", false)
	return out


## Delete every downloaded pack (hand-installed ones stay). Returns how many were removed.
func remove_downloaded() -> int:
	var cache := _cache()
	if not DirAccess.dir_exists_absolute(ContentPacks.os_path(cache)):
		return 0
	if ContentRegistry.loaded_packs().any(func(pack: Dictionary): return String(pack["dir"]).begins_with(cache)):
		ContentRegistry.unload_packs()
	var count := 0
	for name in DirAccess.get_directories_at(ContentPacks.os_path(cache)):
		if not String(name).begins_with("."):
			count += 1
	_wipe(cache)
	return count


## Fetch `packs` ([{pack_id, version, name, sha256}] from the host) that are not on this machine.
## on_progress(done_bytes, total_bytes, pack_name); on_done(ok, reason).
func download_packs(packs: Array, on_progress: Callable, on_done: Callable) -> void:
	var failure: String = await _download(packs, on_progress)
	on_done.call(failure.is_empty(), failure)


func _download(packs: Array, on_progress: Callable) -> String:
	if not Backend.configured():
		return "MOD DOWNLOADS NEED THE PRIMARY SERVER"
	var plans := []
	var total := 0
	for entry in packs:
		var id := String(entry.get("pack_id", ""))
		var version := String(entry.get("version", ""))
		var sha := String(entry.get("sha256", ""))
		var name := String(entry.get("name", id)).to_upper()
		if not RoomPacks.local_dir(id, sha).is_empty():
			continue
		var index: Dictionary = await _get_json(Backend.base_url + INDEX_PATH % [id.uri_encode(), version.uri_encode()])
		if index.is_empty():
			return "MOD INDEX UNAVAILABLE // %s" % name
		if bool(index.get("blocked", false)):
			return "REMOVED BY MODERATORS // %s" % name
		var base := String(index.get("downloadBase", ""))
		var files: Array = index.get("files", [])
		if not (base.begins_with("https://") or base.begins_with("http://")) or files.is_empty():
			return "MOD INDEX INCOMPLETE // %s" % name
		var bytes := 0
		for file in files:
			var size := int(file.get("size", -1))
			if size < 0 or size > int(ContentPacks.LIMITS["file_bytes"]) \
					or not ContentPacks._placement_problem(String(file.get("path", ""))).is_empty():
				return "MOD INDEX LISTS A FILE THIS GAME REFUSES // %s" % name
			bytes += size
		if bytes > int(ContentPacks.LIMITS["pack_bytes"]):
			return "%s IS LARGER THAN THE PACK LIMIT" % name
		if _identity(files) != sha:
			return "HOST'S %s IS NOT THE PUBLISHED VERSION" % name
		total += bytes
		plans.append({"id": id, "version": version, "sha": sha, "name": name, "base": base, "files": files})
	var done := 0
	for plan in plans:
		var staging := _cache().path_join(".download-" + String(plan["sha"]))
		_wipe(staging)
		for file in plan["files"]:
			var rel := String(file["path"])
			var url := "%s/%s/%s/%s" % [String(plan["base"]).trim_suffix("/"), String(plan["id"]).uri_encode(),
				String(plan["version"]).uri_encode(), "/".join(Array(rel.split("/")).map(func(part): return part.uri_encode()))]
			var body: PackedByteArray = await _get_bytes(url, int(file["size"]))
			if body.size() != int(file["size"]) or ContentPacks._sha256(body) != String(file["sha256"]):
				_wipe(staging)
				return "DOWNLOAD DID NOT MATCH THE MOD INDEX // %s" % plan["name"]
			DirAccess.make_dir_recursive_absolute(staging.path_join(rel).get_base_dir())
			var out := FileAccess.open(staging.path_join(rel), FileAccess.WRITE)
			out.store_buffer(body)
			out.close()
			done += body.size()
			on_progress.call(done, total, plan["name"])
		var pack := ContentPacks.read(staging, ContentPacks.LIMITS, false)
		if not pack["errors"].is_empty() or pack["sha256"] != plan["sha"]:
			_wipe(staging)
			return "%s FAILED THE PACK CHECK // %s" % [plan["name"],
				pack["errors"][0] if not pack["errors"].is_empty() else "contents differ from the host"]
		var target := _cache().path_join(String(plan["sha"]))
		_wipe(target)
		DirAccess.rename_absolute(ContentPacks.os_path(staging), ContentPacks.os_path(target))
	return ""


## Pack identity from an index file list: the same sha256 ContentPacks.read() computes over the folder.
static func _identity(files: Array) -> String:
	var sorted := files.duplicate()
	sorted.sort_custom(func(a, b): return String(a["path"]) < String(b["path"]))
	var lines := PackedStringArray()
	for file in sorted:
		lines.append("%s %s" % [file["sha256"], file["path"]])
	return ContentPacks._sha256("\n".join(lines).to_utf8_buffer())


func _get_json(url: String) -> Dictionary:
	var body: PackedByteArray = await _get_bytes(url, 1024 * 1024)
	var parsed = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	return parsed if parsed is Dictionary else {}


## The body of a 200 response, at most `limit` bytes; empty on any failure.
func _get_bytes(url: String, limit: int) -> PackedByteArray:
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT
	request.body_size_limit = limit
	add_child(request)
	if request.request(url) != OK:
		request.queue_free()
		return PackedByteArray()
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		return PackedByteArray()
	return result[3]


func _append_entry(out: Array, dir: String, source: String, folder_is_id: bool) -> void:
	var pack := ContentPacks.read(dir, ContentPacks.LIMITS, folder_is_id)
	if not pack["errors"].is_empty():
		return
	var size := 0
	for file in pack["files"]:
		size += int(file["bytes"])
	var manifest: Dictionary = pack["manifest"]
	out.append({"pack_id": manifest["id"], "name": manifest["name"], "author": manifest.get("author", ""),
		"version": manifest["version"], "size": size, "sha256": pack["sha256"], "source": source})


static func _cache() -> String:
	return RoomPacks.mods_root.path_join(".cache")


## Delete `dir` (inside user://mods/.cache only) and everything in it.
static func _wipe(dir: String) -> void:
	var path := ContentPacks.os_path(dir)
	if not path.contains("/.cache") or not DirAccess.dir_exists_absolute(path):
		return
	_remove_tree(path)


static func _remove_tree(path: String) -> void:
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
