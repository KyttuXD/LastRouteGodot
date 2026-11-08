extends RefCounted

## The guard that keeps the validators away from the real user data (tests/user_guard.gd), tested on a fake user:// folder: a fake
## skin is written through PlayerSkin.apply_result (the call that once left a test skin as a player's own skin), and the original
## skin.png bytes, skin_hash, skin_slim, skin_arms and settings.cfg must be identical afterwards -- also when the suite that did it
## fails, when the run is cut short (finish), and when the process died without cleaning up (the next run's begin).
##
## When the runner's own guard is active, the redirects it installed are checked too, and a fake skin is written through them with
## the real user://skin.png and settings.cfg hashed before and after.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- user_guard

const UserGuard := preload("res://tests/user_guard.gd")

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _skin(base: Color, accent: Color) -> PackedByteArray:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(base)
	for y in 8:
		for x in 8:
			image.set_pixel(8 + x, 8 + y, accent)   # the head front, like the test skin
	return image.save_png_to_buffer()


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


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


## A fake user folder holding an own skin (slim, "slim" arms, pending upload off), settings.cfg, a Night Watch save and a run save.
func _build(fake: String) -> Dictionary:
	_remove_tree(fake)
	DirAccess.make_dir_recursive_absolute(fake)
	Settings.SETTINGS_PATH = fake.path_join("settings.cfg")
	PlayerSkin.own_path = fake.path_join("skin.png")
	Settings.skin_pending_upload = false
	var original := PlayerSkin.validate(_skin(Color(.8, .1, .7, 1.0), Color(.1, .1, .9, 1.0)))
	original["slim"] = true
	PlayerSkin.apply_result(original)
	Settings.set_skin_arms("slim")
	_write(fake.path_join("night_watch.cfg"), "[night_watch]\nstars=7\n".to_utf8_buffer())
	_write(fake.path_join("route_saves/world-1/run.json"), "{\"level\": 4}".to_utf8_buffer())
	_write(fake.path_join("device_id"), "0123456789abcdef".to_utf8_buffer())
	return {"skin": _bytes(fake.path_join("skin.png")), "settings": _bytes(fake.path_join("settings.cfg")),
		"hash": Settings.skin_hash, "slim": Settings.skin_slim, "arms": Settings.skin_arms, "pending": Settings.skin_pending_upload,
		"night_watch": _bytes(fake.path_join("night_watch.cfg")), "run": _bytes(fake.path_join("route_saves/world-1/run.json")),
		"device": _bytes(fake.path_join("device_id"))}


## What a validator did on a real machine: a grey test skin with a green square at the head front becomes the player's own.
func _leak(fake: String) -> void:
	var theirs := PlayerSkin.validate(_skin(Color(.4, .4, .4, 1.0), Color(.2, .9, .2, 1.0)))
	theirs["slim"] = false
	PlayerSkin.apply_result(theirs)
	Settings.set_skin_arms("classic")
	Settings.set_skin_pending_upload(true)
	_write(fake.path_join("skin_test/good.png"), PackedByteArray([1, 2, 3]))
	DirAccess.remove_absolute(fake.path_join("night_watch.cfg"))
	_write(fake.path_join("route_saves/world-1/run.json"), "{}".to_utf8_buffer())


func _leaked(fake: String, original: Dictionary) -> bool:
	return _bytes(fake.path_join("skin.png")) != original["skin"] and _bytes(fake.path_join("settings.cfg")) != original["settings"] \
		and Settings.skin_hash != original["hash"] and Settings.skin_slim != original["slim"]


func _identical(fake: String, original: Dictionary, label: String) -> void:
	_expect(_bytes(fake.path_join("skin.png")) == original["skin"], "%s: the original skin.png bytes were not restored" % label)
	_expect(_bytes(fake.path_join("settings.cfg")) == original["settings"], "%s: settings.cfg is not identical" % label)
	_expect(_bytes(fake.path_join("night_watch.cfg")) == original["night_watch"] and not original["night_watch"].is_empty(), "%s: a deleted night_watch.cfg was not restored" % label)
	_expect(_bytes(fake.path_join("route_saves/world-1/run.json")) == original["run"], "%s: the run save was not restored" % label)
	_expect(_bytes(fake.path_join("device_id")) == original["device"], "%s: device_id changed" % label)
	_expect(not FileAccess.file_exists(fake.path_join("skin_test/good.png")) and not DirAccess.dir_exists_absolute(fake.path_join("skin_test")),
		"%s: a file the suite created was left behind" % label)
	_expect(Settings.skin_hash == original["hash"] and Settings.skin_slim == original["slim"] and Settings.skin_arms == original["arms"]
		and Settings.skin_pending_upload == original["pending"], "%s: skin_hash / skin_slim / skin_arms / pending upload differ in memory" % label)


func _has(lines: PackedStringArray, part: String) -> bool:
	for line in lines:
		if line.contains(part):
			return true
	return false


func run(host: Node) -> int:
	await host.get_tree().process_frame
	var saved := {"settings_path": Settings.SETTINGS_PATH, "skin_path": PlayerSkin.own_path, "hash": Settings.skin_hash,
		"slim": Settings.skin_slim, "arms": Settings.skin_arms, "pending": Settings.skin_pending_upload}
	var base := "user://%s/selftest-%d" % [UserGuard.GUARD_DIR, OS.get_process_id()]
	var fake := base.path_join("user")

	# ---- a suite that passes but leaks: everything is reported and put back
	var original := _build(fake)
	var guard = UserGuard.new(fake)
	_expect(guard.begin() and guard.enabled, "the guard did not start on a user:// folder")
	guard.capture_memory()
	_leak(fake)
	_expect(_leaked(fake, original), "the test setup did not change what it should (the checks below would prove nothing)")
	var lines: PackedStringArray = guard.check()
	_expect(_has(lines, "changed user://skin.png") or _has(lines, "skin.png"), "the changed skin.png was not reported: %s" % str(lines))
	_expect(_has(lines, "settings.cfg"), "the changed settings.cfg was not reported: %s" % str(lines))
	_expect(_has(lines, "deleted") and _has(lines, "night_watch.cfg"), "the deleted night_watch.cfg was not reported: %s" % str(lines))
	_expect(_has(lines, "created") and _has(lines, "skin_test/good.png"), "the created file was not reported: %s" % str(lines))
	_expect(guard.leak_count == lines.size() and lines.size() >= 5, "leak_count is wrong (%d for %d lines)" % [guard.leak_count, lines.size()])
	_expect(guard.restore_memory() > 0, "the changed Settings values were not put back in memory")
	_identical(fake, original, "after a leaking suite")
	_expect(guard.check().is_empty(), "a second check found more to put back after the first restored everything")
	_expect(guard.unrestorable.is_empty(), "something could not be restored")

	# ---- a suite that FAILS (returns failures) goes through the same check
	var failing := _FailingSuite.new()
	failing.fake = fake
	failing.owner_suite = self
	var failures: int = failing.run(host)
	_expect(failures == 2 and _leaked(fake, original), "the failing stand-in suite did not fail and leak")
	lines = guard.check()
	guard.restore_memory()
	_expect(not lines.is_empty(), "a failing suite's leak was not reported")
	_identical(fake, original, "after a failing suite")

	# ---- the run is cut short (watchdog, broken suite): finish() puts everything back and removes the guard folder
	_leak(fake)
	var finished_dir: String = guard.run_dir
	lines = guard.finish()
	guard.restore_memory()
	_expect(not lines.is_empty(), "finish() did not report the leak")
	_identical(fake, original, "after finish()")
	_expect(not DirAccess.dir_exists_absolute(finished_dir), "finish() left its backup folder")
	_expect(guard.finish().is_empty(), "finish() twice reported something")

	# ---- the process died mid-suite (killed, power loss): the next run's begin() recovers from the manifest left behind
	original = _build(fake)
	var dying = UserGuard.new(fake)
	dying.begin()
	dying.capture_memory()
	_leak(fake)
	dying = null   # no finish(): the manifest and the backups stay on disk, exactly as after a kill
	var next = UserGuard.new(fake)
	next.live_seconds = 0   # the dead run's heartbeat counts as old
	_expect(next.begin(), "the next run did not start")
	_expect(not next.recovered.is_empty(), "the next run did not notice the interrupted one")
	# only the files; memory is the dead process's
	_expect(_bytes(fake.path_join("skin.png")) == original["skin"] and _bytes(fake.path_join("settings.cfg")) == original["settings"],
		"the interrupted run's skin.png / settings.cfg were not put back")
	_expect(_bytes(fake.path_join("night_watch.cfg")) == original["night_watch"] and not FileAccess.file_exists(fake.path_join("skin_test/good.png")),
		"the interrupted run's other changes were not undone")
	next.finish()

	# ---- a run that is alive is left alone, and a change made after a dead run's last heartbeat is the player's own
	original = _build(fake)
	var first = UserGuard.new(fake)
	first.begin()
	_leak(fake)   # mid-suite state of a live run
	var second = UserGuard.new(fake)   # default live_seconds: the first run's heartbeat is fresh
	second.begin()
	_expect(second.recovered.is_empty(), "a live run's files were 'recovered' by another run")
	_expect(second.shared and second.check().is_empty(), "a run that starts beside a live one still compares the shared folder (it would delete the other run's scratch files)")
	_expect(first.check().is_empty(), "a run kept checking while another was alive")
	_expect(DirAccess.dir_exists_absolute(first.run_dir), "a live run's guard folder was removed by another run")
	second.finish()
	first.finish()
	first.restore_memory()
	_build(fake)
	var late = UserGuard.new(fake)
	late.begin()
	late.capture_memory()
	var beat := FileAccess.open(late.run_dir.path_join("heartbeat"), FileAccess.WRITE)   # the dead run's last sign of life, long ago
	beat.store_string(str(int(Time.get_unix_time_from_system()) - 7200))
	beat.close()
	_write(fake.path_join("device_id"), "player-changed-this-later".to_utf8_buffer())   # modified after that heartbeat + slack
	late = null
	var after_death = UserGuard.new(fake)
	after_death.live_seconds = 0
	after_death.begin()
	_expect(_bytes(fake.path_join("device_id")) == "player-changed-this-later".to_utf8_buffer(), "a change made long after the dead run's last heartbeat was undone")
	after_death.finish()

	# ---- only user:// is ever touched
	var outside = UserGuard.new("res://tests")
	_expect(not outside.begin() and not outside.enabled, "the guard accepted a folder outside user://")
	_expect(outside.check().is_empty() and outside.finish().is_empty(), "a refused guard still did something")
	var isolated_before := OS.get_environment("VALIDATE_USER_ISOLATED")
	OS.set_environment("VALIDATE_USER_ISOLATED", "1")
	_expect(UserGuard.scratch_user_dir(), "VALIDATE_USER_ISOLATED=1 is not recognised as a throw-away user folder")
	OS.set_environment("VALIDATE_USER_ISOLATED", isolated_before)
	var turned_off := OS.get_environment("VALIDATE_USER_GUARD")
	OS.set_environment("VALIDATE_USER_GUARD", "0")
	_expect(UserGuard.disabled_by_environment(), "VALIDATE_USER_GUARD=0 is not recognised")
	OS.set_environment("VALIDATE_USER_GUARD", turned_off)

	_remove_tree(base)
	Settings.SETTINGS_PATH = saved["settings_path"]
	PlayerSkin.own_path = saved["skin_path"]
	Settings.skin_hash = saved["hash"]
	Settings.skin_slim = saved["slim"]
	Settings.skin_arms = saved["arms"]
	Settings.skin_pending_upload = saved["pending"]
	PlayerSkin._textures.erase("own")

	# ---- the real runner's guard: the redirects are installed, and a fake skin never reaches the real files
	if UserGuard.disabled_by_environment() or UserGuard.scratch_user_dir():
		print("  skip  runner guard checks: the guard is off or user:// is already a throw-away folder")
	else:
		var real_skin := "user://skin.png"
		var real_settings := RunProfile.path(Settings.SETTINGS_PATH_DEFAULT)
		_expect(PlayerSkin.own_path != PlayerSkin.OWN_PATH, "the runner did not move the own skin off user://skin.png")
		_expect(Settings.SETTINGS_PATH != real_settings, "the runner did not move settings.cfg")
		_expect(RunSaves.save_dir != RunSaves.DEFAULT_DIR and RunSaves.cloud_disabled, "the runner did not move the run saves / stop cloud sync")
		_expect(NightWatchSave.path != NightWatchSave.DEFAULT_PATH, "the runner did not move the Night Watch save")
		_expect(not Backend.signed_in(), "the run is still signed in: a suite could upload a test skin to, or overwrite a save of, the real account")
		if PlayerSkin.own_path != PlayerSkin.OWN_PATH and Settings.SETTINGS_PATH != real_settings:
			var skin_before := FileAccess.get_sha256(real_skin) if FileAccess.file_exists(real_skin) else ""
			var settings_before := FileAccess.get_sha256(real_settings) if FileAccess.file_exists(real_settings) else ""
			var kept := {"hash": Settings.skin_hash, "slim": Settings.skin_slim, "arms": Settings.skin_arms}
			var skin_result := PlayerSkin.validate(_skin(Color(.4, .4, .4, 1.0), Color(.2, .9, .2, 1.0)))
			PlayerSkin.apply_result(skin_result)
			Settings.set_skin_arms("slim")
			PlayerSkin.reset_active()
			PlayerSkin.apply_result(skin_result)
			_expect((FileAccess.get_sha256(real_skin) if FileAccess.file_exists(real_skin) else "") == skin_before, "a fake skin changed the real user://skin.png")
			_expect((FileAccess.get_sha256(real_settings) if FileAccess.file_exists(real_settings) else "") == settings_before, "a fake skin changed the real settings.cfg")
			PlayerSkin.reset_active()
			Settings.skin_hash = kept["hash"]
			Settings.skin_slim = kept["slim"]
			Settings.skin_arms = kept["arms"]

	if _failures == 0:
		print("  ok    user_guard: a fake skin written through apply_result leaves skin.png, settings.cfg, skin_hash/slim/arms identical (leaking suite, failing suite, cut-short run, killed run); live runs and later player changes are left alone; user:// only")
	return _failures


## Stands in for a suite that leaks and then fails.
class _FailingSuite extends RefCounted:
	var fake := ""
	var owner_suite: RefCounted

	func run(_host: Node) -> int:
		owner_suite._leak(fake)
		return 2
