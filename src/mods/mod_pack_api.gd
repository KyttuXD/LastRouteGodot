class_name ModPackApi
extends RefCounted

## The seam between the mod UI (Settings -> MODS, the join confirm dialog) and the pack loader (DATA) / download backend (TOOLS).
## The UI only talks to this class; when the loader lands it sets `provider` to an object with
##
##   installed_packs() -> Array[Dictionary]     {pack_id, name, author, version, size, sha256, source}  source: "builtin"|"local"|"downloaded"
##   remove_downloaded() -> int                 deletes every downloaded pack, returns how many
##   download_packs(packs: Array, on_progress: Callable, on_done: Callable) -> void
##       on_progress(done_bytes: int, total_bytes: int, pack_name: String); on_done(ok: bool, reason: String)
##
## Until then the provider is null: the list is empty and a download fails with a clear message. Pack lists from the host use the same
## dictionary shape ({pack_id, version, name, author, size, sha256}).

const SOURCE_LABELS := {"builtin": "BUILT IN", "local": "LOCAL", "downloaded": "DOWNLOADED"}
const OWN_RISK_WARNING := "Mods are made by other players. They contain data and assets only, but Kyttu's Lab does not review them. Download at your own risk."
const AUTO_WARNING := "Missing mods download without asking when you join a private room. Mods are made by other players and are not reviewed. Leave this off unless you trust the people you play with."

static var provider: Object = null


static func installed() -> Array:
	if provider != null and provider.has_method("installed_packs"):
		return provider.installed_packs()
	return []


static func downloaded_count() -> int:
	var count := 0
	for pack in installed():
		if String(pack.get("source", "")) == "downloaded":
			count += 1
	return count


static func remove_downloaded() -> int:
	if provider != null and provider.has_method("remove_downloaded"):
		return int(provider.remove_downloaded())
	return 0


static func download(packs: Array, on_progress: Callable, on_done: Callable) -> void:
	if provider == null or not provider.has_method("download_packs"):
		on_done.call(false, "MOD LOADER IS NOT AVAILABLE IN THIS BUILD")
		return
	provider.download_packs(packs, on_progress, on_done)


static func format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / 1048576.0)


static func short_hash(sha: String) -> String:
	return sha.substr(0, 8) if sha.length() >= 8 else sha


## Compare the host's list with ours. Returns {missing, different, extra}: packs we lack, packs with another version or hash, and
## packs we have that the host does not (a guest with extra packs would generate another world, so those also refuse the join).
static func diff(host_packs: Array, local_packs: Array) -> Dictionary:
	var local := {}
	for pack in local_packs:
		local[String(pack.get("pack_id", ""))] = pack
	var host_ids := {}
	var missing := []
	var different := []
	for pack in host_packs:
		var id := String(pack.get("pack_id", ""))
		host_ids[id] = true
		if not local.has(id):
			missing.append(pack)
		elif String(local[id].get("sha256", "")) != String(pack.get("sha256", "")) \
				or String(local[id].get("version", "")) != String(pack.get("version", "")):
			different.append(pack)
	var extra := []
	for pack in local_packs:
		if not host_ids.has(String(pack.get("pack_id", ""))) and String(pack.get("source", "")) != "builtin":
			extra.append(pack)
	return {"missing": missing, "different": different, "extra": extra}
