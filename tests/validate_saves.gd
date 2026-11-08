extends RefCounted

## One automatic save per Last Route run (RunSaves): the route saves at a new level, a checkpoint, a relay and on quit;
## CONTINUE resumes it; an old 9-slot save migrates; a corrupt file or an interrupted write never loses the run or
## crashes; death clears it on every difficulty; a co-op guest never saves. Runs against a scratch save folder.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- saves

const SCRATCH := "user://validate_saves_scratch"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _frames(host: Node, count: int = 4) -> void:
	for _i in count:
		await host.get_tree().process_frame


func _payload(level: int = -1, elapsed: float = 60.0) -> Dictionary:
	return {
		"schema": RunSaves.PAYLOAD_SCHEMA,
		"kind": "infinite_route",
		"seed_text": "VALIDATION-SAVE-SEED",
		"run_seed": 987654,
		"difficulty": RoomState.Difficulty.STANDARD,
		"difficulty_id": "standard",
		"world_state": StreamedWorldState.new().snapshot(),
		"player": {
			"position": Vector3(12.5, StreamedFacilityView3D.LEVEL_HEIGHT * level, -8.5),
			"level": level,
			"inventory_order": ["flashlight", "battery", "", "", ""],
			"inventory_slot_durability": [77, 0, 0, 0, 0],
			"stamina": 40.0,
			"flashlight_enabled": true,
		},
		"statistics": {"elapsed_seconds": elapsed, "relays_collected": 4},
		"discovery": {"rooms": {"r1": true}},
	}


func _wipe(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for sub in directory.get_directories():
		_wipe(path.path_join(sub))
	for file_name in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _reset_scratch() -> void:
	_wipe(SCRATCH)
	RunSaves.set("_cloud_preservation_required", false)


func run(host: Node) -> int:
	var old_dir := RunSaves.save_dir
	var old_cloud := RunSaves.cloud_disabled
	var old_preservation: bool = RunSaves.get("_cloud_preservation_required")
	_reset_scratch()
	RunSaves.save_dir = SCRATCH
	RunSaves.cloud_disabled = true
	RunSaves.clear_pending()
	_check_store()
	_check_migration()
	_check_newer_format_preservation()
	_check_newer_legacy_preservation()
	_check_preservation_failures()
	_check_remote_preservation_race()
	_check_remote_marker_failure()
	_check_preservation_notice()
	_check_world_generation()
	_check_corrupt_and_interrupted()
	await _check_scan_memo(host)
	await _check_route(host)
	RunSaves.interrupt_before_swap = false
	RunSaves.clear_pending()
	_reset_scratch()
	RunSaves.save_dir = old_dir
	RunSaves.cloud_disabled = old_cloud
	RunSaves.set("_cloud_preservation_required", old_preservation)
	if _failures == 0:
		print("  store     one run: atomic write + backup, vectors survive, CONTINUE consumed once, cloud newer-wins; 404/offline/5xx keep it owed, never shown")
		print("  migrate   an old 9-slot .lrsave becomes the run; newer envelope/payload formats stay intact during recovery and cloud adoption")
		print("  safety    corrupt file -> backup or a clear message; an interrupted write keeps the run")
		print("  memo      write guards remember unchanged files yet notice any outside change (newer format, other generation, other folder); written bytes and cloud push body unchanged")
		print("  route     level/checkpoint/relay/quit autosave; solo death clears (every difficulty); co-op keeps it through one death and a host quit, wipe clears; guests never save")
		print("saves OK")
	return _failures


func _check_store() -> void:
	RunSaves.clear()
	_expect(not RunSaves.has_run() and String(RunSaves.summary().get("message", "x")).is_empty(),
		"an empty save folder reports a run or an error")
	var written := RunSaves.write(_payload(-2, 3723.0), "LEVEL -2")
	_expect(bool(written.get("ok", false)), "the run could not be saved: %s" % written)
	var loaded := RunSaves.load_run()
	var payload: Dictionary = loaded.get("payload", {})
	_expect(bool(loaded.get("ok", false)) and payload.get("player", {}).get("position") is Vector3 \
		and float(payload.get("player", {}).get("stamina", 0.0)) == 40.0,
		"the saved run lost the player's position type or stamina across disk")
	_expect(not (payload.get("world_state", {}) as Dictionary).has("hunters") \
		and not payload.has("anti_idle"), "the save keeps live hunters; the seed should rebuild them")
	var summary := RunSaves.summary()
	_expect(String(summary.get("status", "")).begins_with("RUN SAVED AT LEVEL -2, "),
		"pause/title status line is wrong: %s" % summary)
	RunSaves.write(_payload(-3), "LEVEL -3")
	_expect(FileAccess.file_exists(RunSaves.main_path() + ".bak") \
		and not FileAccess.file_exists(RunSaves.main_path() + ".tmp"),
		"a second save did not keep the previous one as the backup")
	var queued := RunSaves.queue_continue()
	var consumed := RunSaves.consume_pending()
	_expect(bool(queued.get("ok", false)) and String(consumed.get("place", "")) == "LEVEL -3" \
		and RunSaves.consume_pending().is_empty(), "CONTINUE was not consumed exactly once")
	# cloud: a newer account copy replaces the local run, an older one does not
	var record := {"format": RunSaves.FORMAT, "world_generation": RunSaves.WorldGenerationVersion.REVISION, "saved_at": int(Time.get_unix_time_from_system()) + 60,
		"place": "LEVEL -9", "payload": _payload(-9)}
	_expect(RunSaves.adopt_cloud(JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(record))))) \
		and String(RunSaves.load_run().get("place", "")) == "LEVEL -9", "a newer cloud run was not adopted")
	record["saved_at"] = 5
	record["place"] = "LEVEL -1"
	_expect(not RunSaves.adopt_cloud(record) and String(RunSaves.load_run().get("place", "")) == "LEVEL -9",
		"an older cloud run replaced the local one")
	RunSaves.clear()
	_expect(not RunSaves.has_run() and not FileAccess.file_exists(RunSaves.main_path() + ".bak"),
		"clearing the run left a copy behind")
	_check_cloud_failures()


## Offline, a 404 from a server without the route, 5xx, 401, 429 or a refused connection: the run stays playable, nothing is
## reported, and the save stays owed ("push" / "clear") for the next try. Only a 2xx settles it.
func _check_cloud_failures() -> void:
	RunSaves.clear()
	RunSaves.write(_payload(-2), "LEVEL -2")
	_expect(RunSaves.pending_sync() == "push", "a new save is not marked as owed to the cloud")
	var failures := [[HTTPRequest.RESULT_SUCCESS, 404], [HTTPRequest.RESULT_SUCCESS, 500], [HTTPRequest.RESULT_SUCCESS, 503],
		[HTTPRequest.RESULT_SUCCESS, 401], [HTTPRequest.RESULT_SUCCESS, 429], [HTTPRequest.RESULT_SUCCESS, 413],
		[HTTPRequest.RESULT_CANT_CONNECT, 0], [HTTPRequest.RESULT_TIMEOUT, 0]]
	for failure in failures:
		RunSaves.set("_cloud_operation", "push")
		RunSaves.call("_on_cloud_response", failure[0], failure[1], PackedStringArray(),
			"{\"ok\":false,\"code\":\"NOT_FOUND\"}".to_utf8_buffer())
		_expect(RunSaves.pending_sync() == "push" and String(RunSaves.load_run().get("place", "")) == "LEVEL -2" \
			and bool(RunSaves.summary().get("ok", false)),
			"a cloud failure (%s/%s) dropped the owed upload or touched the run" % failure)
	RunSaves.set("_cloud_operation", "pull")
	RunSaves.call("_on_cloud_response", HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), PackedByteArray())
	_expect(String(RunSaves.load_run().get("place", "")) == "LEVEL -2", "a 404 on pull changed the local run")
	RunSaves.set("_cloud_operation", "push")
	RunSaves.call("_on_cloud_response", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{\"ok\":true}".to_utf8_buffer())
	_expect(RunSaves.pending_sync().is_empty(), "a confirmed upload stayed owed")
	# death offline: the clear stays owed, and an older account copy can never bring the dead run back
	RunSaves.clear()
	_expect(RunSaves.pending_sync() == "clear", "an offline death did not leave the cloud clear owed")
	var record := {"format": RunSaves.FORMAT, "world_generation": RunSaves.WorldGenerationVersion.REVISION, "saved_at": int(Time.get_unix_time_from_system()) + 600,
		"place": "LEVEL -3", "payload": _payload(-3)}
	_expect(not RunSaves.adopt_cloud(record) and not RunSaves.has_run(), "a pull revived a run that died offline")
	RunSaves.set("_cloud_operation", "clear")
	RunSaves.call("_on_cloud_response", HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), PackedByteArray())
	_expect(RunSaves.pending_sync() == "clear", "a 404 settled the owed clear")
	RunSaves.set("_cloud_operation", "clear")
	RunSaves.call("_on_cloud_response", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray())
	_expect(RunSaves.pending_sync().is_empty(), "a confirmed clear stayed owed")
	RunSaves.set("_cloud_operation", "")


func _check_migration() -> void:
	RunSaves.clear()
	var legacy := {"save_schema": 1, "world_generation": RunSaves.WorldGenerationVersion.REVISION, "slot_id": "0123456789abcdef0123", "name": "Old Slot",
		"created_at": 100, "saved_at": 200, "payload": _payload(-1)}
	legacy["payload"]["world_state"]["hunters"] = {"H1": {"hunter_id": "x"}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH))
	var file := FileAccess.open(RunSaves.generation_dir().path_join("0123456789abcdef0123.lrsave"), FileAccess.WRITE)
	file.store_var(legacy, false)
	file.close()
	var loaded := RunSaves.load_run()
	_expect(bool(loaded.get("ok", false)) and String(loaded.get("place", "")) == "LEVEL -1" \
		and int(loaded.get("saved_at", 0)) == 200, "an old-format slot did not migrate into the run: %s" % loaded)
	_expect(not FileAccess.file_exists(RunSaves.generation_dir().path_join("0123456789abcdef0123.lrsave")) \
		and FileAccess.file_exists(RunSaves.generation_dir().path_join("legacy/0123456789abcdef0123.lrsave")),
		"the old slot file was not kept aside in legacy/")
	var future := {"format": RunSaves.FORMAT + 1, "saved_at": 1, "place": "", "payload": {}}
	_expect(String(RunSaves.migrate(future).get("error", "")).contains("NEWER BUILD"),
		"a save from a newer build is not refused with a clear message")
	RunSaves.clear()


func _preserved_bytes(name: String, bytes: PackedByteArray) -> bool:
	var root := RunSaves.generation_dir().path_join("preserved")
	var directory := DirAccess.open(root)
	if directory == null:
		return false
	for folder in directory.get_directories():
		var path := root.path_join(folder).path_join(name)
		if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes:
			return true
	return false


func _check_newer_format_preservation() -> void:
	for version_kind in ["format", "payload", "legacy"]:
		for suffix in ["", ".tmp", ".bak"]:
			for action in ["write", "clear"]:
				_reset_scratch()
				RunSaves.clear()
				RunSaves.write(_payload(-2), "LEVEL -2")
				RunSaves.write(_payload(-3), "LEVEL -3")
				var future := {"format": RunSaves.FORMAT, "world_generation": RunSaves.WorldGenerationVersion.REVISION,
					"saved_at": 500, "place": "LEVEL -8", "payload": _payload(-8)}
				if version_kind == "format":
					future["format"] = RunSaves.FORMAT + 1
				elif version_kind == "payload":
					future["payload"]["schema"] = RunSaves.PAYLOAD_SCHEMA + 1
				else:
					future.erase("format")
					future["save_schema"] = 2
				var path: String = RunSaves.main_path() + String(suffix)
				_write_text(path, JSON.stringify(JSON.from_native(future)))
				var original := FileAccess.get_file_as_bytes(path)
				var refused := RunSaves.queue_continue()
				_expect(not bool(refused.get("ok", true)) and String(refused.get("message", "")).contains("NEWER BUILD") \
					and RunSaves.consume_pending().is_empty(), "CONTINUE accepted a future save")
				_expect(FileAccess.get_file_as_bytes(path) == original, "CONTINUE changed future bytes")
				if action == "clear":
					RunSaves.clear() # same entry point used by solo death and party wipe
				for attempt in 2:
					var result := RunSaves.write(_payload(-4 - attempt), "LEVEL -4")
					_expect(bool(result.get("ok", false)) and String(result.get("message", "")).contains("PRESERVED"),
						"fresh run could not save after preserving future %s %s" % [version_kind, suffix])
				_expect(_preserved_bytes(path.get_file(), original), "write/clear lost unsupported save bytes")
				_expect(RunSaves.pending_sync() == "preserved" and RunSaves.cloud_preserved(),
					"write/clear queued cloud overwrite/deletion of an unsupported save")
				_expect(bool(RunSaves.load_run().get("ok", false)) \
					and String(RunSaves.summary().get("status", "")).contains("CLOUD SYNC PAUSED"),
					"fresh local run cannot resume or hides its cloud preservation status")
				RunSaves.clear()
				_expect(_preserved_bytes(path.get_file(), original) and RunSaves.pending_sync() == "preserved",
					"later death deleted the preserved copy or queued a cloud delete")
	_reset_scratch()
	RunSaves.clear()


func _check_newer_legacy_preservation() -> void:
	for future_payload in [false, true]:
		for action in ["write", "clear"]:
			_reset_scratch()
			RunSaves.clear()
			var path := RunSaves.generation_dir().path_join("future.lrsave")
			var record := {"save_schema": 1, "world_generation": RunSaves.WorldGenerationVersion.REVISION,
				"saved_at": 200, "payload": _payload()}
			if future_payload:
				record["payload"]["schema"] = RunSaves.PAYLOAD_SCHEMA + 1
			else:
				record["save_schema"] = 2
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_var(record, false)
			file.close()
			var original := FileAccess.get_file_as_bytes(path)
			_expect(String(RunSaves.load_run().get("message", "")).contains("NEWER BUILD"), "future legacy slot loaded")
			RunSaves._migrate_legacy_slots()
			_expect(FileAccess.get_file_as_bytes(path) == original, "legacy migration modified future slot")
			if action == "clear":
				RunSaves.clear()
			for attempt in 2:
				_expect(bool(RunSaves.write(_payload(), "LEVEL -1").get("ok", false)), "future legacy slot blocked new runs")
			_expect(_preserved_bytes(path.get_file(), original) and RunSaves.pending_sync() == "preserved",
				"future legacy bytes/cloud copy were not preserved")
	_reset_scratch()
	RunSaves.clear()


func _check_preservation_failures() -> void:
	for blocked in ["marker", "archive"]:
		_reset_scratch()
		RunSaves.clear()
		RunSaves.write(_payload(), "LEVEL -1")
		var future := {"format": RunSaves.FORMAT + 1, "world_generation": RunSaves.WorldGenerationVersion.REVISION,
			"saved_at": 100, "payload": _payload()}
		_write_text(RunSaves.main_path(), JSON.stringify(JSON.from_native(future)))
		var original := FileAccess.get_file_as_bytes(RunSaves.main_path())
		var barrier: String = RunSaves._cloud_preservation_marker() if blocked == "marker" \
			else RunSaves.generation_dir().path_join("preserved")
		if blocked == "marker":
			DirAccess.make_dir_absolute(ProjectSettings.globalize_path(barrier))
		else:
			_write_text(barrier, "test archive obstruction")
		_expect(not bool(RunSaves.write(_payload(-2), "LEVEL -2").get("ok", true)),
			"an archive/marker failure allowed a destructive write")
		RunSaves.clear()
		_expect(FileAccess.file_exists(RunSaves.main_path()) \
			and FileAccess.get_file_as_bytes(RunSaves.main_path()) == original,
			"archive/marker failure lost original bytes during clear")
		_expect(RunSaves.pending_sync() != "clear", "archive/marker failure queued a cloud delete")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(barrier))
		_expect(bool(RunSaves.write(_payload(-2), "LEVEL -2").get("ok", false)) \
			and _preserved_bytes("run.json", original), "saving did not recover after archive obstruction was removed")
	_reset_scratch()
	RunSaves.clear()


func _check_remote_preservation_race() -> void:
	for version_kind in ["format", "payload", "generation", "untagged", "compatible"]:
		_reset_scratch()
		RunSaves.clear()
		RunSaves.write(_payload(), "LEVEL -1")
		# A GET is already in flight when death clears the local run. Its queued
		# resync must not issue a null PUT if the GET discovers unsupported data.
		RunSaves.set("_cloud_operation", "pull")
		RunSaves.clear()
		RunSaves.set("_resync", true)
		var remote := {"format": RunSaves.FORMAT, "world_generation": RunSaves.WorldGenerationVersion.REVISION,
			"saved_at": 99999999999, "place": "LEVEL -8", "payload": _payload(-8)}
		if version_kind == "format":
			remote["format"] = RunSaves.FORMAT + 1
		elif version_kind == "payload":
			remote["payload"]["schema"] = RunSaves.PAYLOAD_SCHEMA + 1
		elif version_kind == "generation":
			remote["world_generation"] = RunSaves.WorldGenerationVersion.REVISION + 1
		elif version_kind == "untagged":
			remote.erase("world_generation")
		RunSaves._on_cloud_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
			JSON.stringify({"data": JSON.from_native(remote)}).to_utf8_buffer())
		if version_kind == "compatible":
			_expect(RunSaves.pending_sync() == "clear" and not RunSaves.cloud_preserved(),
				"a compatible cloud response bypassed the pending death clear")
		else:
			_expect(RunSaves.pending_sync() == "preserved" and RunSaves.cloud_preserved(),
				"a pending death clear could delete unsupported cloud %s" % version_kind)
		_expect(not FileAccess.file_exists(RunSaves.main_path()) and String(RunSaves.get("_cloud_operation")).is_empty(),
			"the late cloud response restored a dead run or queued a deletion")
	_reset_scratch()
	RunSaves.clear()


func _check_remote_marker_failure() -> void:
	_reset_scratch()
	RunSaves.clear()
	var barrier: String = RunSaves._cloud_preservation_marker()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(barrier))
	var future := {"format": RunSaves.FORMAT + 1, "world_generation": RunSaves.WorldGenerationVersion.REVISION,
		"saved_at": 99999999999, "payload": _payload()}
	_expect(not RunSaves.adopt_cloud(future) and RunSaves.cloud_preserved(),
		"remote-only unsupported save was not guarded after marker failure")
	_expect(bool(RunSaves.write(_payload(-2), "LEVEL -2").get("ok", false)) \
		and RunSaves.pending_sync() == "preserved", "marker failure queued upload over unsupported remote data")
	RunSaves.clear()
	_expect(RunSaves.pending_sync() == "preserved" and String(RunSaves.get("_cloud_operation")).is_empty(),
		"marker failure queued a cloud deletion")
	# The obstruction itself also keeps a restarted store fail closed.
	RunSaves.set("_cloud_preservation_required", false)
	_expect(RunSaves.cloud_preserved(), "marker directory obstruction lost protection after restart")
	RunSaves.set("_cloud_preservation_required", true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(barrier))
	_expect(RunSaves.cloud_preserved(), "memory guard vanished before marker retry")
	RunSaves.cloud_sync()
	_expect(FileAccess.file_exists(barrier) and RunSaves.pending_sync() == "preserved",
		"cloud sync did not persist the guard after the marker obstruction cleared")
	_reset_scratch()
	RunSaves.clear()


func _check_preservation_notice() -> void:
	for obstruct_marker in [false, true]:
		_reset_scratch()
		RunSaves.clear()
		RunSaves.write(_payload(), "LEVEL -1")
		var marker: String = RunSaves._cloud_preservation_marker()
		if obstruct_marker:
			DirAccess.make_dir_absolute(ProjectSettings.globalize_path(marker))
		var observed := {"count": 0, "status": ""}
		var listener := func() -> void:
			observed["count"] += 1
			observed["status"] = String(RunSaves.summary().get("status", ""))
			# A menu may retry from its change handler. Bound this fixture so a
			# regression fails an assertion rather than overflowing the test stack.
			if int(observed["count"]) < 3:
				RunSaves.cloud_sync()
		RunSaves.changed.connect(listener)
		var remote := {"format": RunSaves.FORMAT + 1,
			"world_generation": RunSaves.WorldGenerationVersion.REVISION, "payload": _payload()}
		_expect(not RunSaves.adopt_cloud(remote), "notice fixture adopted unsupported remote data")
		_expect(int(observed["count"]) == 1 and String(observed["status"]).contains("CLOUD SYNC PAUSED"),
			"remote preservation did not publish exactly one usable menu notice")
		RunSaves.adopt_cloud(remote)
		RunSaves.cloud_sync()
		_expect(int(observed["count"]) == 1, "unchanged preservation retry repeatedly emitted changed")
		if obstruct_marker:
			_expect(String(observed["status"]).contains("LOCAL GUARD NOT SAVED"), "marker failure was hidden from menu")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
			RunSaves.cloud_sync()
			_expect(int(observed["count"]) == 2 \
				and not String(observed["status"]).contains("LOCAL GUARD NOT SAVED"),
				"successful marker retry did not refresh the failed-persistence notice exactly once")
		RunSaves.changed.disconnect(listener)
	_reset_scratch()
	RunSaves.clear()


func _check_world_generation() -> void:
	RunSaves.clear()
	var old_path := SCRATCH.path_join("run.json")
	var old_record := {"format": RunSaves.FORMAT, "saved_at": 200,
		"place": "LEVEL -2", "payload": _payload(-2)}
	var legacy_path := SCRATCH.path_join("old-beta.lrsave")
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_var({"save_schema": 1, "saved_at": 100, "payload": _payload()}, false)
	legacy_file.close()
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
	var previous_path := SCRATCH.path_join("world-0/run.json")
	_write_text(previous_path, JSON.stringify(JSON.from_native(old_record)))
	var previous_bytes := FileAccess.get_file_as_bytes(previous_path)
	for revision in [null, 0, RunSaves.WorldGenerationVersion.REVISION + 1]:
		if revision == null:
			old_record.erase("world_generation")
		else:
			old_record["world_generation"] = revision
		_write_text(old_path, JSON.stringify(JSON.from_native(old_record)))
		var before := FileAccess.get_file_as_bytes(old_path)
		_expect(String(RunSaves.migrate(old_record.duplicate(true)).get("error", "")).contains("NEW RUN REQUIRED"),
			"an incompatible/untagged generation migrated silently")
		var loaded := RunSaves.queue_continue()
		_expect(not bool(loaded.get("ok", true)) and String(loaded.get("message", "")).contains("NEW RUN REQUIRED") \
			and RunSaves.consume_pending().is_empty(), "an old beta run was offered for CONTINUE")
		_expect(not RunSaves.adopt_cloud(old_record), "an incompatible cloud save was adopted")
		_expect(FileAccess.get_file_as_bytes(old_path) == before, "refusing an old beta run changed its bytes")
		_expect(bool(RunSaves.write(_payload(-3), "LEVEL -3").get("ok", false)),
			"a preserved old beta save prevented a fresh run from saving")
		var cloud_old := old_record.duplicate(true)
		cloud_old["saved_at"] = 99999999999
		_expect(not RunSaves.adopt_cloud(cloud_old), "a newer incompatible cloud copy replaced the fresh run")
		var saved: Dictionary = RunSaves._read(RunSaves.main_path())
		_expect(saved.get("world_generation") == RunSaves.WorldGenerationVersion.REVISION \
			and bool(RunSaves.load_run().get("ok", false)), "new save lost its revision or could not resume")
		RunSaves.write(_payload(-4), "LEVEL -4")
		RunSaves.clear()
		_expect(FileAccess.get_file_as_bytes(old_path) == before, "saving/clearing a fresh run changed the older generation")
	_expect(RunSaves._cloud_path().ends_with("/run-world-%d" % RunSaves.WorldGenerationVersion.REVISION),
		"the current cloud slot can overwrite an older generation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	_expect(String(RunSaves.load_run().get("message", "")).contains("NEW RUN REQUIRED"),
		"old legacy/generation directories were not detected")
	_expect(FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes \
		and FileAccess.get_file_as_bytes(previous_path) == previous_bytes,
		"fresh beta runs modified old legacy/generation saves")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(previous_path))
	# A mismatched record misplaced in the active directory cannot be recovered
	# over or trimmed. Normal previous generations remain in their own directories.
	RunSaves.write(_payload(), "LEVEL -1")
	RunSaves.write(_payload(-2), "LEVEL -2")
	_write_text(RunSaves.main_path(), JSON.stringify(JSON.from_native(old_record)))
	var misplaced := FileAccess.get_file_as_bytes(RunSaves.main_path())
	_expect(String(RunSaves.load_run().get("message", "")).contains("NEW RUN REQUIRED"),
		"a misplaced incompatible save fell back to a compatible backup")
	_expect(bool(RunSaves.write(_payload(), "LEVEL -1").get("ok", false)) \
		and _preserved_bytes("run.json", misplaced),
		"fresh run did not preserve an incompatible record in the active directory")
	RunSaves.clear()
	_expect(_preserved_bytes("run.json", misplaced),
		"clear deleted an incompatible generation misplaced in the active directory")
	_reset_scratch()
	RunSaves.clear()


func _check_corrupt_and_interrupted() -> void:
	# corrupt main, no backup: a message, never a crash
	RunSaves.clear()
	_write_text(RunSaves.main_path(), "{\"format\": 2, \"payl")
	var broken := RunSaves.load_run()
	_expect(not bool(broken.get("ok", true)) and String(broken.get("message", "")).contains("START A NEW RUN"),
		"a corrupt save did not report a clear message: %s" % broken)
	_expect(not bool(RunSaves.summary().get("ok", true)) and not String(RunSaves.summary().get("message", "")).is_empty(),
		"the title CONTINUE would not explain the corrupt save")
	_write_text(RunSaves.main_path(), "")
	_expect(not bool(RunSaves.load_run().get("ok", true)), "an empty save file loaded")
	# corrupt main with a good backup: the backup comes back
	RunSaves.clear()
	RunSaves.write(_payload(-4), "LEVEL -4")
	RunSaves.write(_payload(-5), "LEVEL -5")
	_write_text(RunSaves.main_path(), "garbage")
	var recovered := RunSaves.load_run()
	_expect(bool(recovered.get("ok", false)) and String(recovered.get("place", "")) == "LEVEL -4",
		"a corrupt save did not fall back to the backup: %s" % recovered)
	# killed mid-write: the complete temp file or the old run survives, never nothing
	RunSaves.clear()
	RunSaves.write(_payload(-6), "LEVEL -6")
	RunSaves.interrupt_before_swap = true
	var interrupted := RunSaves.write(_payload(-7), "LEVEL -7")
	RunSaves.interrupt_before_swap = false
	_expect(not bool(interrupted.get("ok", true)), "the interrupted-write hook did not interrupt")
	var after := RunSaves.load_run()
	_expect(bool(after.get("ok", false)) and String(after.get("place", "")) in ["LEVEL -6", "LEVEL -7"],
		"an interrupted write lost the run: %s" % after)
	_expect(not FileAccess.file_exists(RunSaves.main_path() + ".tmp"), "the leftover temp file was not tidied")
	RunSaves.write(_payload(-6), "LEVEL -6")
	_write_text(RunSaves.main_path() + ".tmp", "{\"format\": 2, \"saved_at\": 99999999999, \"pla")
	_expect(String(RunSaves.load_run().get("place", "")) == "LEVEL -6",
		"a half-written temp file replaced the good run")
	# main gone between the two renames: the temp file or backup still loads
	RunSaves.clear()
	RunSaves.write(_payload(-6), "LEVEL -6")
	RunSaves.write(_payload(-8), "LEVEL -8")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RunSaves.main_path()))
	_expect(bool(RunSaves.load_run().get("ok", false)), "losing the main file lost the run despite the backup")
	RunSaves.clear()


## An unsupported run.json of exactly `length` bytes ("format" ahead of this build, or another world generation).
func _unsupported_text(length: int, kind: String) -> String:
	var record := {"format": RunSaves.FORMAT + 1, "world_generation": RunSaves.WorldGenerationVersion.REVISION,
		"saved_at": 777, "place": "", "payload": _payload(-8)}
	if kind == "generation":
		record["format"] = RunSaves.FORMAT
		record["world_generation"] = RunSaves.WorldGenerationVersion.REVISION + 1
	var base := JSON.stringify(JSON.from_native(record)).to_utf8_buffer().size()
	record["place"] = "x".repeat(maxi(0, length - base))
	var text := JSON.stringify(JSON.from_native(record))
	_expect(text.to_utf8_buffer().size() == length, "memo fixture: unsupported text is %d bytes, wanted %d" % [text.to_utf8_buffer().size(), length])
	return text


func _padded_payload(level: int = -2) -> Dictionary:
	var payload := _payload(level)
	payload["pad"] = "p".repeat(4000)   # long enough that an unsupported fixture can match its byte length
	payload["extra"] = {"vec": Vector3(1.5, 2.25, -3.125), "tiny": Vector3(2.9004168e-11, -0.0, 1.69282549946064e-14), "big": 123456789012, "f": 0.1, "text": "café \"q\"",
		"list": [1, 2.5, "x", Vector2i(3, 4)], "cells": {Vector3i(1, -2, 3): [Vector2i(5, 6)]}}
	return payload


## The write guards remember a save file they have parsed (and a run.json this class just wrote) instead of reading it again
## for every guard of every autosave. The memo may only ever save work: any change to the file made by someone else must
## still be seen, and the bytes written must be exactly what they always were.
func _check_scan_memo(host: Node) -> void:
	_reset_scratch()
	RunSaves.clear()
	var main: String = RunSaves.main_path()
	# 1. the bytes on disk are the plain encoding of the trimmed record; the caller's payload is left alone
	var payload := _padded_payload()
	payload["anti_idle"] = {"afk_seconds": 1.0}
	payload["world_state"]["hunters"] = {"H1": {"hunter_id": "x"}}
	var snapshot := payload.duplicate(true)
	var written := RunSaves.write(payload, "  LEVEL -2  ")
	_expect(bool(written.get("ok", false)) and payload == snapshot, "write failed or changed the caller's payload: %s" % written)
	var disk_record: Dictionary = RunSaves._read(main)
	var reference := JSON.stringify(JSON.from_native({"format": RunSaves.FORMAT,
		"world_generation": RunSaves.WorldGenerationVersion.REVISION, "saved_at": int(disk_record.get("saved_at", 0)),
		"place": "LEVEL -2", "payload": RunSaves._trim(snapshot)}))
	_expect(FileAccess.get_file_as_string(main) == reference, "the saved bytes are not the plain encoding of the trimmed record")
	_expect(not (disk_record["payload"] as Dictionary).has("anti_idle") \
		and not ((disk_record["payload"] as Dictionary)["world_state"] as Dictionary).has("hunters"),
		"the shallow trim kept anti_idle or live hunters")
	# 2. the memo is really consulted for an unchanged file (white box: a doctored verdict is believed)
	var entry: Dictionary = RunSaves._scan_memo.get(main, {})
	_expect(not entry.is_empty(), "a just-written run.json was not remembered")
	entry["flags"] = 1
	_expect(RunSaves._has_newer_local_record(), "an unchanged remembered file was parsed again")
	entry["flags"] = 2
	_expect(RunSaves._has_incompatible_generation(), "verdict not used for a doctored entry")
	entry["flags"] = 0
	# 3. replaced from outside within the same second and with the same length: a stat match alone would be fooled
	for kind in ["format", "generation"]:
		_reset_scratch()
		RunSaves.clear()
		RunSaves.write(_padded_payload(), "LEVEL -2")
		RunSaves.write(_padded_payload(-3), "LEVEL -3")
		var length := FileAccess.get_file_as_bytes(main).size()
		_write_text(main, _unsupported_text(length, kind))
		var future := FileAccess.get_file_as_bytes(main)
		_expect(future.size() == length, "memo fixture: same-length replacement")
		_expect(RunSaves._has_newer_local_record() if kind == "format" else RunSaves._has_incompatible_generation(),
			"same-second same-length %s replacement was not noticed" % kind)
		var result := RunSaves.write(_payload(-4), "LEVEL -4")
		_expect(bool(result.get("ok", false)) and String(result.get("message", "")).contains("PRESERVED") \
			and _preserved_bytes("run.json", future), "a replaced %s record was overwritten instead of preserved" % kind)
		_expect(RunSaves.pending_sync() == "preserved" and String(RunSaves.load_run().get("place", "")) == "LEVEL -4",
			"the fresh run after preserving a replaced %s record cannot resume" % kind)
	# 4. another save folder is never judged by the old folder's memo
	_reset_scratch()
	RunSaves.clear()
	RunSaves.write(_padded_payload(), "LEVEL -2")
	var other := SCRATCH + "_other"
	_wipe(other)
	RunSaves.save_dir = other
	_write_text(RunSaves.main_path(), _unsupported_text(3000, "format"))
	_expect(RunSaves._has_newer_local_record(),
		"a changed save_dir reused the previous folder's verdict")
	RunSaves.save_dir = SCRATCH
	_expect(not RunSaves._has_newer_local_record() and bool(RunSaves.load_run().get("ok", false)),
		"switching back to the first save folder lost its run")
	_wipe(other)
	# 5. clear() forgets everything about the files it deletes
	RunSaves.write(_padded_payload(), "LEVEL -2")
	_expect(RunSaves._scan_memo.has(main), "fixture: nothing remembered before clear")
	RunSaves.clear()
	_expect(not RunSaves._scan_memo.has(main) and not RunSaves.has_run(),
		"clear() left a remembered run.json")
	# 6. after the racy window: parsed outside files are remembered by stat, own files keep working, a later change shows
	_reset_scratch()
	RunSaves.clear()
	RunSaves.write(_padded_payload(), "LEVEL -2")
	RunSaves.write(_padded_payload(-3), "LEVEL -3")
	var compatible := {"format": RunSaves.FORMAT, "world_generation": RunSaves.WorldGenerationVersion.REVISION,
		"saved_at": 5, "place": "LEVEL -1", "payload": _payload(-1)}
	_write_text(RunSaves._temp_path(), JSON.stringify(JSON.from_native(compatible)))
	await host.get_tree().create_timer(3.3).timeout
	_expect(not RunSaves._has_newer_local_record() and not RunSaves._has_incompatible_generation(), "a supported set was refused")
	for path in [main, RunSaves._backup_path(), RunSaves._temp_path()]:
		var old_entry: Dictionary = RunSaves._scan_memo.get(path, {})
		_expect(not old_entry.is_empty() and not bool(old_entry["racy"]), "%s was not remembered by stat once old enough" % path.get_file())
	var tmp_entry: Dictionary = RunSaves._scan_memo.get(RunSaves._temp_path(), {})
	tmp_entry["flags"] = 1
	_expect(RunSaves._has_newer_local_record(), "a remembered outside file was parsed again")
	tmp_entry["flags"] = 0
	var replaced_length := FileAccess.get_file_as_bytes(RunSaves._temp_path()).size() + 37
	var replacement := _unsupported_text(replaced_length, "format")
	_write_text(RunSaves._temp_path(), replacement)
	# pretend the replacement landed in the very second of the remembered modified time: only the length can tell them apart
	tmp_entry["mtime"] = FileAccess.get_modified_time(RunSaves._temp_path())
	_expect(RunSaves._has_newer_local_record(), "an old remembered temp file was replaced by a newer record unseen")
	var swapped := RunSaves.write(_payload(-6), "LEVEL -6")
	_expect(bool(swapped.get("ok", false)) and String(swapped.get("message", "")).contains("PRESERVED") \
		and _preserved_bytes("run.json.tmp", replacement.to_utf8_buffer()),
		"a newer temp file replaced after being remembered was not preserved")
	_reset_scratch()
	RunSaves.clear()


func _check_route(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RunSaves.clear()
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await _frames(host, 10)
	GameState.debug_run = false
	# relay
	RunSaves.clear()
	var world: StreamedWorldState = route.get("world_state")
	world.claimed_pickups["VALIDATE:PICKUP:RELAY:1"] = 1
	route.call("_sync_stream_progress")
	_expect(RunSaves.has_run() and String(route.get("_last_autosave_reason")) == "relay", "collecting a relay did not autosave")
	# checkpoint
	RunSaves.clear()
	route.call("_apply_stream_world_event", {"what": "stream_checkpoint", "checkpoint_id": "VALIDATE:CP", "winner_peer_id": 1})
	_expect(RunSaves.has_run() and String(route.get("_last_autosave_reason")) == "checkpoint", "a checkpoint did not autosave")
	# a new level
	RunSaves.clear()
	var stats: Dictionary = route.get("_run_statistics")
	(stats["visited_levels"] as Dictionary).clear()
	route.call("_update_run_statistics", 0.0)
	_expect(RunSaves.has_run() and String(route.get("_last_autosave_reason")) == "level", "reaching a new level did not autosave")
	RunSaves.clear()
	route.call("_update_run_statistics", 0.0)
	_expect(not RunSaves.has_run(), "staying on a visited level autosaved every frame")
	# quit from the pause menu saves before leaving (the scene change itself is not run here)
	var source := (route.get_script() as GDScript).source_code
	var leave := source.substr(source.find("func _leave_test()"), 200)
	_expect(leave.contains("autosave(\"quit\")"), "LEAVE ROUTE does not save the run first")
	# the saved run carries what CONTINUE needs and the pause line reads from it
	RunSaves.clear()
	route.call("autosave", "validate")
	var resumed := RunSaves.queue_continue()
	var payload: Dictionary = resumed.get("payload", {})
	_expect(bool(resumed.get("ok", false)) and String(payload.get("seed_text", "")) == RoomState.seed_text \
		and payload.get("player", {}).has("stamina") and payload.get("player", {}).has("flashlight_enabled") \
		and payload.get("discovery") is Dictionary and payload.get("statistics", {}).has("elapsed_seconds"),
		"the route save is missing seed, stamina, flashlight, discoveries or time")
	_expect(String(route.call("_save_status_line")).begins_with("RUN SAVED AT LEVEL "), "the pause line does not show the save")
	RunSaves.clear_pending()
	# solo: death clears the run on every difficulty, and a finished run cannot save again
	for difficulty in [RoomState.Difficulty.RELAXED, RoomState.Difficulty.STANDARD, RoomState.Difficulty.HARD]:
		RoomState.difficulty = difficulty
		route.set("_run_save_ended", false)
		route.call("autosave", "validate")
		route.call("_save_after_local_death")
		_expect(not RunSaves.has_run(), "a solo death left the save on difficulty %d" % difficulty)
	var capture := source.substr(source.find("func _resolve_capture_outcome("), 600)
	_expect(capture.contains("_save_after_local_death()"), "a capture does not reach the death save rule")
	_expect(not bool(route.call("autosave", "validate").get("ok", true)) and not RunSaves.has_run(),
		"a dead solo run saved again")
	route.set("_run_save_ended", false)
	GameState.game_over = true
	_expect(not bool(route.call("autosave", "validate").get("ok", true)), "a dead solo runner could still save")
	GameState.game_over = false
	var old := [RoomState.online, RoomState.is_host, RoomState.peers.duplicate(true)]
	RoomState.online = true
	RoomState.peers = {1: "HOST", 2: "GUEST"}
	# co-op: one runner down (the host here) keeps the run; the save goes on updating
	RoomState.is_host = true
	route.set("_test_party_alive", 1)
	RunSaves.write(_payload(-2), "LEVEL -2")
	GameState.game_over = true
	route.call("_save_after_local_death")
	_expect(RunSaves.has_run(), "one co-op death deleted the host's run save")
	_expect(bool(route.call("autosave", "relay").get("ok", false)), "the save stopped updating while the host waits for a revive")
	# co-op: the host quits mid-run while teammates are alive: the save stays for CONTINUE
	route.call("autosave", "quit")
	_expect(RunSaves.has_run(), "the host quitting with live teammates lost the save")
	# co-op: a full team wipe ends the run and its save
	route.set("_test_party_alive", 0)
	var wipe := source.substr(source.find("# Party wipe: the host was already spectating"), 400)
	_expect(wipe.contains("_end_run_save()"), "a party wipe does not end the run's save")
	route.call("_end_run_save")
	_expect(not RunSaves.has_run() and not bool(route.call("autosave", "relay").get("ok", true)),
		"a team wipe left the save or let the ended run save again")
	route.set("_run_save_ended", false)
	GameState.game_over = false
	# co-op: only the host saves
	RoomState.is_host = false
	_expect(not bool(route.call("autosave", "relay").get("ok", true)) and not RunSaves.has_run(), "a co-op guest saved the run")
	RunSaves.write(_payload(-2), "LEVEL -2")
	route.call("_save_after_local_death")
	route.call("_end_run_save")
	_expect(RunSaves.has_run(), "a guest's death touched the save on its machine")
	RunSaves.clear()
	RoomState.is_host = true
	route.set("_test_party_alive", 1)
	_expect(bool(route.call("autosave", "relay").get("ok", false)) and RunSaves.has_run(), "the co-op host could not save")
	route.set("_test_party_alive", -1)
	RoomState.online = old[0]
	RoomState.is_host = old[1]
	RoomState.peers = old[2]
	RunSaves.clear()
	route.queue_free()
	await _frames(host, 2)
