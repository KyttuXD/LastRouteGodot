class_name RoomPacks
extends RefCounted

## Which content packs a room plays with (docs/DATA_DRIVEN_CONTENT.md, "Multiplayer pack hash"). The host loads the
## packs it enabled (Settings.mods_enabled) when a private room goes online or starts; public routes are always vanilla.
## Guests receive announce() before the room itself and adopt() it: the same packs found locally by id and sha256,
## loaded, and checked against the host's hash before anything is generated. Leaving a room unloads every pack.

## Where packs are looked up; the validators point it at a scratch folder.
static var mods_root := ContentPacks.ROOT


## Host side. "" when the room's packs are loaded (none for a public route), else the reason the run cannot start.
static func host_load(public_route: bool) -> String:
	if public_route or Settings.mods_enabled.is_empty():
		ContentRegistry.unload_packs()
		return ""
	var dirs := []
	var missing := []
	var found := {}
	for dir in ContentPacks.discover(mods_root):
		found[dir.get_file()] = dir
	for id in Settings.mods_enabled:
		if found.has(String(id)):
			dirs.append(found[String(id)])
		else:
			missing.append(String(id))
	if not missing.is_empty():
		return "MODS NOT FOUND // %s" % ", ".join(missing).to_upper()
	dirs.sort()
	if _loaded_dirs() == dirs:
		return ""
	var report := ContentRegistry.load_packs(dirs)
	if not report["ok"]:
		return "MODS NOT LOADED // %s" % String(report["errors"][0])
	return ""


## What the host sends ahead of the room: the pack hash and [{pack_id, version, name, author, size, sha256}] (the
## shape ModPackApi and the mod UI use).
static func announce() -> Dictionary:
	var packs := []
	for pack in ContentRegistry.loaded_packs():
		packs.append({"pack_id": pack["id"], "version": pack["version"], "name": pack["name"], "author": pack["author"],
			"size": pack["size"], "sha256": pack["sha256"]})
	return {"hash": ContentRegistry.pack_hash(), "packs": packs}


## Guest side: load the host's packs from this machine. {"ok", "reason", "missing": [entry]}; on failure nothing that
## was loaded stays loaded, and `missing` lists the packs this guest does not have (step 10 downloads them).
static func adopt(host: Dictionary, public_route: bool) -> Dictionary:
	var host_hash := String(host.get("hash", ""))
	if public_route and host_hash != ContentRegistry.builtin_pack_hash():
		return {"ok": false, "reason": "PUBLIC ROUTES ARE UNMODDED // HOST DATA DIFFERS", "missing": []}
	if host_hash == ContentRegistry.pack_hash():
		return {"ok": true, "reason": "", "missing": []}
	var wanted: Array = host.get("packs", [])
	var dirs := []
	var missing := []
	for entry in wanted:
		var dir := local_dir(String(entry.get("pack_id", "")), String(entry.get("sha256", "")))
		if dir.is_empty():
			missing.append(entry)
		else:
			dirs.append(dir)
	if not missing.is_empty():
		return {"ok": false, "reason": "MODS DIFFER // MISSING %s" % _names(missing), "missing": missing}
	var report := ContentRegistry.load_packs(dirs) if not dirs.is_empty() else _unload()
	if not report["ok"]:
		return {"ok": false, "reason": "MODS NOT LOADED // %s" % String(report["errors"][0]), "missing": []}
	if ContentRegistry.pack_hash() != host_hash:
		ContentRegistry.unload_packs()
		return {"ok": false, "reason": "MODS DIFFER // GAME DATA DOES NOT MATCH THE HOST (UPDATE THE GAME)",
			"missing": []}
	return {"ok": true, "reason": "", "missing": []}


## A pack on this machine with exactly this id and content: hand-installed under user://mods/<id>, or downloaded under
## user://mods/.cache/<sha256>. "" when there is none.
static func local_dir(id: String, sha256: String) -> String:
	for dir in [mods_root.path_join(id), mods_root.path_join(".cache").path_join(sha256)]:
		if not FileAccess.file_exists(dir.path_join("pack.json")):
			continue
		var pack := ContentPacks.read(dir, ContentPacks.LIMITS, not dir.contains("/.cache/"))
		if pack["errors"].is_empty() and pack["sha256"] == sha256 and String(pack["manifest"].get("id", "")) == id:
			return dir
	return ""


## Leaving a room: back to the built-in game.
static func leave() -> void:
	ContentRegistry.unload_packs()


static func _loaded_dirs() -> Array:
	return ContentRegistry.loaded_packs().map(func(pack: Dictionary): return pack["dir"])


static func _unload() -> Dictionary:
	ContentRegistry.unload_packs()
	return {"ok": true, "errors": PackedStringArray()}


static func _names(entries: Array) -> String:
	return ", ".join(entries.map(func(entry: Dictionary): return "%s %s" % [entry.get("name", entry.get("pack_id", "?")),
		entry.get("version", "")])).to_upper()
