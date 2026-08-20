extends RefCounted

const STORY_SCRIPT := preload("res://src/story/infinite_story_director.gd")


func run(owner: Node) -> int:
	var failures := 0
	var loaded: Dictionary = STORY_SCRIPT.load_and_validate(
		"res://story/infinite_route_stories.json")
	failures += _check(bool(loaded.get("ok", false)),
		"schema", "Infinite story JSON and every graph reference validate")
	if not bool(loaded.get("ok", false)):
		print("    %s" % String(loaded.get("error", "unknown error")))
		return failures
	var content: Dictionary = loaded.get("content", {})
	var scenes: Dictionary = content.get("scenes", {})
	var admin_scene: Dictionary = scenes.get("admin_sample_tour", {})
	failures += _check(bool(admin_scene.get("admin_only", false)) \
		and admin_scene.has("custom_map"), "map gate",
		"PNG stages exist only on explicitly admin-only scenes")
	for trigger_value in content.get("triggers", []):
		var trigger: Dictionary = trigger_value
		var target: Dictionary = scenes.get(String(trigger.get("scene", "")), {})
		failures += _check(not bool(target.get("admin_only", false)) \
			and not target.has("custom_map"), "discovery gate",
			"ordinary Infinite discovery cannot load a custom PNG map")
	failures += _check((content.get("triggers", []) as Array).is_empty(),
		"manual only", "Infinite Route has no automatic story/cutscene triggers")

	var host = STORY_SCRIPT.new()
	owner.add_child(host)
	var configure_error: String = host.configure(true)
	failures += _check(configure_error.is_empty(), "runtime",
		"host story director loads the maintained content")
	failures += _check(not host.is_active(), "no autoplay",
		"a normal Infinite session starts with story presentation inactive")
	failures += _check(not host.start_admin_scene("first_signal", false),
		"admin gate", "host authority without admin authorization is rejected")
	failures += _check(host.start_admin_scene("first_signal", true),
		"admin start", "verified admin can start a listed cutscene")
	var started: Dictionary = host.snapshot()
	failures += _check(bool(started.get("active", false)) \
		and String(started.get("scene_id", "")) == "first_signal",
		"state", "admin-triggered scene enters authoritative state")
	host._process(1.0)
	var dialog: Dictionary = host.snapshot()
	failures += _check(String(dialog.get("dialog_scene_id", "")) == "ilyra_warning" \
		and String(dialog.get("node_id", "")) == "intro",
		"dialog", "cutscene wait advances into the branching dialog")

	var guest = STORY_SCRIPT.new()
	owner.add_child(guest)
	configure_error = guest.configure(false)
	failures += _check(configure_error.is_empty() and guest.adopt_snapshot(dialog) \
		and guest.is_active(), "late join", "guest adopts host story state read-only")
	failures += _check(not guest.start_admin_scene("admin_sample_tour", true),
		"guest gate", "guest cannot start an admin custom-map scene")
	failures += _check(host.stop_admin_scene(true) and not host.is_active(),
		"admin stop", "verified admin can stop active presentation")
	failures += _check(host.reset_admin_story(true), "admin reset",
		"verified admin can reset story state")
	host.queue_free()
	guest.queue_free()
	print("story OK" if failures == 0 else "story FAILED (%d)" % failures)
	return failures


func _check(condition: bool, label: String, detail: String) -> int:
	if condition:
		print("  %-10s %s" % [label, detail])
		return 0
	print("  FAIL %-5s %s" % [label, detail])
	return 1
