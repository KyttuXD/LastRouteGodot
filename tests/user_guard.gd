extends RefCounted

## Keeps the headless validators away from the real user data (user://).
##
## The suites call the same code the game does (PlayerSkin.apply_result, Settings setters, RunSaves.write, NightWatchSave...),
## and that code writes the real user://skin.png, settings.cfg, night_watch.cfg and route_saves. A validator run once left a
## 256-byte test skin as the player's own skin on a real machine. Two layers stop that:
##
##  1. REDIRECT (redirect_to_scratch): the paths that can be pointed elsewhere are pointed at a private scratch folder inside
##     user://.validate_guard/run-<pid>/scratch, seeded with copies of the real files. A suite then never opens the real file.
##  2. SNAPSHOT / RESTORE (begin / check / finish): every regular file under user:// is copied and hashed before the first suite.
##     After every suite the tree is compared; a changed or deleted file is restored byte for byte and a file the suite created is
##     removed, whatever it was (no list of names, so the next file someone adds is covered too). A run that is killed leaves its
##     manifest behind and the next run puts the files back (only files changed up to the dead run's last heartbeat, so the
##     player's own later changes are never undone).
##
## It only ever touches `root` (user:// by default). A user data folder that is already a throw-away one (an APPDATA/HOME under the
## OS temp folder, or VALIDATE_USER_ISOLATED=1, as tools/build/run_suites.py sets up) has nothing to protect: scratch_user_dir().
## VALIDATE_USER_GUARD=0 turns the whole thing off; VALIDATE_STRICT_USER=1 makes a leak fail the suite that caused it.

const GUARD_DIR := ".validate_guard"
## Engine-owned or log-like folders (top level of user:// only): changing them is not a leak.
const EXCLUDED_TOP := ["logs", "crash_queue", "shader_cache", "objectdb_snapshots", GUARD_DIR]
## Files up to this size are hashed and backed up; a bigger one is only compared by size and modified time and cannot be restored.
const FILE_LIMIT := 8 * 1024 * 1024
## Total bytes of backups; files past it are tracked but not restorable (reported in `unrestorable`).
const BACKUP_BUDGET := 256 * 1024 * 1024
## A file modified this recently (seconds) when it was snapshotted may change again without its size or time changing: always hash it.
const RACY_SECONDS := 3
## A dead run's files are put back only when modified before its last heartbeat plus this: later changes are the player's own.
const RECOVERY_SLACK := 120

var root := "user://"
## Seconds a heartbeat stays fresh. Another run with a fresher one is alive, so its folder is left alone.
var live_seconds := 300
var strict := false
## Number of leaked files seen (and put back) since begin().
var leak_count := 0
var unrestorable := PackedStringArray()
var run_dir := ""
var scratch := ""
var enabled := false
## True when another validator run was using user:// at the same time: its scratch folders and files would look like leaks, so file
## checks are off for this run (the redirects still keep the suites off the real skin, settings, saves and Night Watch save).
var shared := false
## True when the stored login was verified (signed in) when the run started; it is dropped for the run (see _sign_out_in_memory).
var was_signed_in := false
## What the last begin() put back from a run that died.
var recovered := PackedStringArray()

var _files := {}       # rel path -> {size, mtime, sha, backup, racy}
var _dirs := {}        # rel path -> true
var _begun := false
var _finished := false
var _backup_bytes := 0
var _memory := {}      # Settings script variable -> value at begin()
var _original := {}    # what redirect_to_scratch replaced
var _redirected := false


func _init(p_root: String = "user://") -> void:
	root = p_root


## True when the user data folder is a throw-away one and there is nothing real to protect.
static func scratch_user_dir() -> bool:
	if OS.get_environment("VALIDATE_USER_ISOLATED") == "1":
		return true
	var user_dir := OS.get_user_data_dir().replace("\\", "/").to_lower().trim_suffix("/")
	for variable in ["TEMP", "TMP", "TMPDIR"]:
		var temp := OS.get_environment(variable).replace("\\", "/").to_lower().trim_suffix("/")
		if not temp.is_empty() and (user_dir == temp or user_dir.begins_with(temp + "/")):
			return true
	return false


static func disabled_by_environment() -> bool:
	return OS.get_environment("VALIDATE_USER_GUARD") == "0"


# ------------------------------------------------------------------------------------------------ begin / check / finish

## Recovers after a run that died, then snapshots `root`. Returns false (and does nothing) when `root` is not under user://.
func begin() -> bool:
	if _begun:
		return enabled
	_begun = true
	if not root.begins_with("user://"):
		print("  guard: refusing to guard %s (only user:// is ever touched)" % root)
		return false
	strict = OS.get_environment("VALIDATE_STRICT_USER") == "1"
	DirAccess.make_dir_recursive_absolute(_guard_root())
	recovered = _recover_stale()
	shared = not _live_runs().is_empty()
	run_dir = _guard_root().path_join("run-%d-%d" % [OS.get_process_id(), get_instance_id()])   # unique even inside one process (the self-test)
	scratch = run_dir.path_join("scratch")
	DirAccess.make_dir_recursive_absolute(run_dir.path_join("files"))
	DirAccess.make_dir_recursive_absolute(scratch)
	if shared:
		heartbeat()
		enabled = true
		return true
	var found := _scan()
	var now := int(Time.get_unix_time_from_system())
	for rel in found["files"]:
		var entry: Dictionary = found["files"][rel]
		var size := int(entry["size"])
		var snapshot := {"size": size, "mtime": int(entry["mtime"]), "sha": "", "backup": false,
			"racy": now - int(entry["mtime"]) < RACY_SECONDS}
		if size <= FILE_LIMIT:
			snapshot["sha"] = FileAccess.get_sha256(_abs(rel))
			if _backup_bytes + size <= BACKUP_BUDGET and _copy(_abs(rel), _backup_path(run_dir, rel)):
				snapshot["backup"] = true
				_backup_bytes += size
		_files[rel] = snapshot
	_dirs = found["dirs"]
	_write_manifest()
	heartbeat()
	enabled = true
	return true


## Compares `root` with the snapshot, puts every change back and returns one line per leaked file.
func check() -> PackedStringArray:
	if not enabled or _finished or shared or not _live_runs().is_empty():
		return PackedStringArray()
	var lines := _reconcile(_files, _dirs, run_dir.path_join("files"), -1, true)
	leak_count += lines.size()
	heartbeat()
	return lines


## Final check, then removes the guard folder. Safe to call twice.
func finish() -> PackedStringArray:
	if not enabled or _finished:
		return PackedStringArray()
	var lines := check()
	_finished = true
	_remove_tree(run_dir)
	DirAccess.remove_absolute(_guard_root())   # only succeeds when no other run is using it
	return lines


## Other validator runs (not this one) whose heartbeat is fresh.
func _live_runs() -> PackedStringArray:
	var live := PackedStringArray()
	var now := int(Time.get_unix_time_from_system())
	for name in DirAccess.get_directories_at(_guard_root()):
		var dir := _guard_root().path_join(name)
		if not name.begins_with("run-") or dir == run_dir:
			continue
		var beat_file := dir.path_join("heartbeat")
		var beat := int(FileAccess.get_file_as_string(beat_file).strip_edges()) if FileAccess.file_exists(beat_file) else 0
		if beat > 0 and now - beat < live_seconds:
			live.append(name)
	return live


## Marks this run alive. Another process that finds the folder uses the age of this to tell a live run from a dead one.
func heartbeat() -> void:
	if run_dir.is_empty() or _finished:
		return
	var file := FileAccess.open(run_dir.path_join("heartbeat"), FileAccess.WRITE)
	if file != null:
		file.store_string(str(int(Time.get_unix_time_from_system())))


# ------------------------------------------------------------------------------------------------ redirects

## Points every runtime-assignable user:// path at a scratch copy. Call after begin(), before the first suite.
func redirect_to_scratch() -> void:
	if not enabled or _redirected:
		return
	_redirected = true
	_original = {
		"settings": Settings.SETTINGS_PATH,
		"skin": PlayerSkin.own_path,
		"account": Backend.account_config_path,
		"saves": RunSaves.save_dir,
		"cloud_disabled": RunSaves.cloud_disabled,
		"night_watch": NightWatchSave.path,
		"nw_home": NwLeakProbe.home,
	}
	_original["identity"] = {"username": Backend.account_username, "token": Backend.account_session_token,
		"verified": Backend.account_session_verified, "admin": Backend.account_admin, "owner": Backend.account_admin_owner,
		"permissions": Backend.account_admin_permissions.duplicate()}
	_seed_scratch()
	Settings.SETTINGS_PATH = scratch.path_join("settings.cfg")
	PlayerSkin.own_path = scratch.path_join("skin.png")
	Backend.account_config_path = scratch.path_join("account.cfg")
	RunSaves.save_dir = scratch.path_join("route_saves")
	RunSaves.cloud_disabled = true   # a suite must never touch the signed-in account's cloud save
	NightWatchSave.path = scratch.path_join("night_watch.cfg")
	NwLeakProbe.home = NightWatchSave.path
	was_signed_in = Backend.signed_in()
	_sign_out_in_memory()
	capture_memory()


## Back to the real paths. Call before finish().
func undo_redirect() -> void:
	if not _redirected:
		return
	_redirected = false
	restore_memory()
	Settings.SETTINGS_PATH = _original["settings"]
	PlayerSkin.own_path = _original["skin"]
	Backend.account_config_path = _original["account"]
	RunSaves.save_dir = _original["saves"]
	RunSaves.cloud_disabled = _original["cloud_disabled"]
	NightWatchSave.path = _original["night_watch"]
	NwLeakProbe.home = _original["nw_home"]
	_restore_identity()
	PlayerSkin._textures.erase("own")


## Between suites: the scratch files go back to the real files' state and the in-memory settings to their values at begin().
func reset_scratch() -> int:
	if not _redirected:
		return 0
	_seed_scratch()
	return restore_memory()


func _seed_scratch() -> void:
	_remove_tree(scratch)
	DirAccess.make_dir_recursive_absolute(scratch)
	DirAccess.make_dir_recursive_absolute(scratch.path_join("route_saves"))
	var sources := {"settings.cfg": String(_original["settings"]), "skin.png": String(_original["skin"]),
		"account.cfg": String(_original["account"])}
	for name in sources:
		var source: String = sources[name]
		if not FileAccess.file_exists(source):
			continue
		# the real file as it was at begin(), not as a suite may have left it
		var rel := source.trim_prefix(root).trim_prefix("/")
		var pristine := _backup_path(run_dir, rel)
		_copy(pristine if _files.has(rel) and bool(_files[rel]["backup"]) and FileAccess.file_exists(pristine) else source, scratch.path_join(name))


## A validator run is never signed in. The stored login is verified against the live server at boot, and while it is, a suite that
## applies a test skin uploads it to the real account (SkinSync.sync_own), another can overwrite the account's route checkpoint
## (Backend.account_save_progress) and the next start adopts the test skin on every machine that signs in (that is how a test
## skin reached a second computer). The in-memory login is dropped for the run and put back at the end; nothing is written.
func _sign_out_in_memory() -> void:
	if Backend._account_request != null:
		Backend._account_request.cancel_request()   # the boot-time session check must not sign the run in again when it answers
	Backend.account_busy = false
	Backend._account_operation = ""
	Backend.account_username = ""
	Backend.account_session_token = ""
	Backend.account_session_verified = false
	Backend.account_admin = false
	Backend.account_admin_owner = false
	Backend.account_admin_permissions = PackedStringArray()


func _restore_identity() -> void:
	var identity: Dictionary = _original["identity"]
	Backend.account_username = identity["username"]
	Backend.account_session_token = identity["token"]
	Backend.account_session_verified = identity["verified"]
	Backend.account_admin = identity["admin"]
	Backend.account_admin_owner = identity["owner"]
	Backend.account_admin_permissions = identity["permissions"]


# ------------------------------------------------------------------------------------------------ in-memory Settings

## Settings.gd keeps every value in memory and writes ALL of them at the next save, so a value a suite left changed on the
## autoload would reach a file later. Remember them now and put them back after each suite.
func capture_memory() -> void:
	_memory.clear()
	for prop in Settings.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := String(prop["name"])
		if name.begins_with("_") or name == "SETTINGS_PATH":
			continue
		var value: Variant = Settings.get(name)
		if value is Object or value is Callable or value is Signal or value is RID:
			continue
		_memory[name] = value.duplicate(true) if (value is Array or value is Dictionary) else value


## Returns how many values had to be put back.
func restore_memory() -> int:
	var changed := 0
	var volume := false
	for name in _memory:
		var now: Variant = Settings.get(name)
		var wanted: Variant = _memory[name]
		if typeof(now) == typeof(wanted) and now == wanted:
			continue
		Settings.set(name, wanted.duplicate(true) if (wanted is Array or wanted is Dictionary) else wanted)
		changed += 1
		volume = volume or String(name).contains("volume")
	if volume:
		Settings._apply_volume()
	PlayerSkin._textures.erase("own")
	return changed


# ------------------------------------------------------------------------------------------------ files

func _guard_root() -> String:
	return root.path_join(GUARD_DIR)


func _abs(rel: String) -> String:
	return root.path_join(rel) if not rel.is_empty() else root


func _backup_path(dir: String, rel: String) -> String:
	return dir.path_join("files").path_join(rel)


## {"files": {rel: {size, mtime}}, "dirs": {rel: true}} for everything under root except the engine-owned folders.
func _scan() -> Dictionary:
	var files := {}
	var dirs := {}
	_walk("", files, dirs)
	return {"files": files, "dirs": dirs}


func _walk(rel: String, files: Dictionary, dirs: Dictionary) -> void:
	var dir := DirAccess.open(_abs(rel))
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		if rel.is_empty() and EXCLUDED_TOP.has(sub):
			continue
		var sub_rel := sub if rel.is_empty() else rel.path_join(sub)
		dirs[sub_rel] = true
		_walk(sub_rel, files, dirs)
	for name in dir.get_files():
		var file_rel := name if rel.is_empty() else rel.path_join(name)
		var file := FileAccess.open(_abs(file_rel), FileAccess.READ)
		var size := 0
		if file != null:
			size = int(file.get_length())
			file.close()
		files[file_rel] = {"size": size, "mtime": int(FileAccess.get_modified_time(_abs(file_rel)))}


func _copy(from: String, to: String) -> bool:
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	return DirAccess.copy_absolute(from, to) == OK


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)


## True when `current` (size, mtime) still matches the snapshot entry `entry`.
func _unchanged(rel: String, entry: Dictionary, current: Dictionary, trust_stat: bool) -> bool:
	if int(entry["size"]) != int(current["size"]):
		return false
	var same_time := int(entry["mtime"]) == int(current["mtime"])
	if String(entry["sha"]).is_empty():   # too big to hash: size and time are all there is
		return same_time
	if trust_stat and same_time and not bool(entry["racy"]):
		return true
	return FileAccess.get_sha256(_abs(rel)) == String(entry["sha"])


## The one comparison, used after every suite (cutoff -1) and to recover a dead run (cutoff = last heartbeat + slack).
func _reconcile(files: Dictionary, dirs: Dictionary, backups: String, cutoff: int, trust_stat: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := _scan()
	var current_files: Dictionary = current["files"]
	var names := current_files.keys()
	names.sort()
	for rel in names:
		var seen: Dictionary = current_files[rel]
		if cutoff >= 0 and int(seen["mtime"]) > cutoff:
			continue
		if not files.has(rel):
			DirAccess.remove_absolute(_abs(rel))
			lines.append("created user://%s (removed)" % rel)
		elif not _unchanged(rel, files[rel], seen, trust_stat):
			lines.append("changed user://%s %s" % [rel, _put_back(rel, files[rel], backups)])
	var gone := files.keys()
	gone.sort()
	for rel in gone:
		if not current_files.has(rel):
			lines.append("deleted user://%s %s" % [rel, _put_back(rel, files[rel], backups)])
	var folders: Array = current["dirs"].keys()
	folders.sort()
	folders.reverse()
	for rel in folders:
		if not dirs.has(rel):
			DirAccess.remove_absolute(_abs(rel))   # fails (and is left) when something is still inside
	return lines


func _put_back(rel: String, entry: Dictionary, backups: String) -> String:
	var backup := backups.path_join(rel)
	if not bool(entry["backup"]) or not FileAccess.file_exists(backup):
		unrestorable.append(rel)
		return "(too large to restore)"
	if not _copy(backup, _abs(rel)):
		unrestorable.append(rel)
		return "(RESTORE FAILED)"
	entry["mtime"] = int(FileAccess.get_modified_time(_abs(rel)))
	entry["racy"] = true
	return "(restored)"


# ------------------------------------------------------------------------------------------------ recovery of a dead run

func _write_manifest() -> void:
	var file := FileAccess.open(run_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version": 1, "taken": int(Time.get_unix_time_from_system()), "files": _files, "dirs": _dirs.keys()}))


func _recover_stale() -> PackedStringArray:
	var lines := PackedStringArray()
	var now := int(Time.get_unix_time_from_system())
	for name in DirAccess.get_directories_at(_guard_root()):
		if name.begins_with("selftest-"):   # the guard's own test (tests/validate_user_guard.gd), left by a run that died
			if now - int(FileAccess.get_modified_time(_guard_root().path_join(name))) > live_seconds:
				_remove_tree(_guard_root().path_join(name))
			continue
		if not name.begins_with("run-"):
			continue
		var dir := _guard_root().path_join(name)
		var beat := int(FileAccess.get_file_as_string(dir.path_join("heartbeat")).strip_edges()) if FileAccess.file_exists(dir.path_join("heartbeat")) else 0
		if beat > 0 and now - beat < live_seconds:
			continue   # another validator run is using user:// right now
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json"))) if FileAccess.file_exists(dir.path_join("manifest.json")) else null
		if parsed is Dictionary and (parsed as Dictionary).has("files"):
			var manifest: Dictionary = parsed
			var dirs := {}
			for rel in manifest.get("dirs", []):
				dirs[String(rel)] = true
			var files := {}
			for rel in manifest["files"]:
				var entry: Dictionary = manifest["files"][rel]
				files[String(rel)] = {"size": int(entry["size"]), "mtime": int(entry["mtime"]), "sha": String(entry["sha"]),
					"backup": bool(entry["backup"]), "racy": true}
			var limit := (beat if beat > 0 else int(manifest.get("taken", now))) + RECOVERY_SLACK
			for line in _reconcile(files, dirs, dir.path_join("files"), limit, false):
				lines.append("recovered after an interrupted run: %s" % line)
		_remove_tree(dir)
	return lines
