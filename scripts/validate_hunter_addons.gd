extends RefCounted

## Runtime rig add-ons (HunterAddons): the data loads and every entry attaches to an existing or declared bone, the proof-of-concept tail
## (Dovelle) and lantern (Aki) are mounted from data and nothing else changes, the tail's runtime bones animate (secondary motion and a bone
## pose), parts are visual only and invisible to the bounds helpers, the build is cached, and removing an entry leaves the model exactly as the
## .glb ships it.
##
##   godot --headless --path . res://scenes/validate.tscn -- hunter_addons

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _fingerprint(node: Node, out: Array, prefix: String = "") -> Array:
	for child in node.get_children():
		var line := "%s/%s:%s" % [prefix, child.name, child.get_class()]
		if child is Node3D:
			line += ":%s" % [(child as Node3D).transform]
		out.append(line)
		_fingerprint(child, out, "%s/%s" % [prefix, child.name])
	return out


func _model(id: String, with_addons: bool = true) -> Node3D:
	var was := HunterAddons.enabled
	HunterAddons.enabled = with_addons
	var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(id))
	HunterAddons.enabled = was
	return model


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame
	# the proof of concept lives in a TEST-ONLY fixture: no live hunter wears a tail or a lantern
	HunterAddons.reset()
	var live := HunterAddons.data()
	_expect((live.get("hunters", {}) as Dictionary).is_empty() and (live.get("shared", []) as Array).is_empty(), "the shipped addons.json must not assign any add-on to a hunter")
	for id in HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS:
		_expect(not HunterAddons.has_addons(id), "%s wears an add-on in the shipped data" % id)
	HunterAddons.reset(JSON.parse_string(FileAccess.get_file_as_string("res://scripts/fixtures/addons/hunter_addons_fixture.json")) as Dictionary)
	var data := HunterAddons.data()
	_expect(not data.is_empty() and data.has("kits") and data.has("hunters"), "addons.json did not load")
	_expect(HunterRoster.get_identity("dovelle")["id"] == "dovelle", "the roster identity carries the hunter id the mount keys on")

	# ---- the data: every entry of every kit resolves on every hunter that wears it
	for hunter_id in (data["hunters"] as Dictionary).keys() + data.get("shared", []):
		var model := _model(hunter_id)
		host.add_child(model)
		var rig := HunterAddons.rig_of(model)
		_expect(rig != null, "%s has add-ons in the data but none were mounted" % hunter_id)
		if rig != null:
			_expect(rig.errors.is_empty(), "%s: add-on errors %s" % [hunter_id, rig.errors])
			var plan := HunterAddons.plan(hunter_id)
			for part in plan["parts"]:
				_expect(rig.parts.has(String(part["id"])), "%s: part %s is not mounted" % [hunter_id, part["id"]])
				var node := rig.parts[String(part["id"])] as Node3D
				_expect(node != null and node.get_parent() != null and (node.get_parent() == rig.bones.get(String(part["bone"]), model.find_child(String(part["bone"]), true, false))), "%s: part %s hangs off %s" % [hunter_id, part["id"], part["bone"]])
				_expect(node.find_children("*", "CollisionObject3D", true, false).is_empty() and node.find_children("*", "CollisionShape3D", true, false).is_empty(), "%s: part %s must be visual only" % [hunter_id, part["id"]])
			for bone in plan["bones"]:
				_expect(rig.bones.has(String(bone["name"])), "%s: bone %s is not created" % [hunter_id, bone["name"]])
		model.queue_free()
	await tree.process_frame

	# ---- the proof of concept: Dovelle's tail chain and Aki's lantern
	var dovelle := _model("dovelle")
	host.add_child(dovelle)
	var parent_of_tail := dovelle.find_child("TestTail1", true, false)
	_expect(parent_of_tail != null and parent_of_tail.get_parent().name == "Pelvis", "Dovelle's tail hangs off Pelvis")
	for i in range(2, 5):
		var seg := dovelle.find_child("TestTail%d" % i, true, false)
		_expect(seg != null and seg.get_parent().name == "TestTail%d" % (i - 1), "TestTail%d chains off TestTail%d" % [i, i - 1])
	var aki := _model("aki")
	host.add_child(aki)
	var lantern := aki.find_child("Addon_test_lantern", true, false)
	_expect(lantern != null and lantern.get_parent().name == "TestLanternHang" and lantern.get_parent().get_parent().name == "R-HandProp", "Aki holds a lantern in the right hand")
	_expect(dovelle.find_child("TestLanternHang", true, false) == null and aki.find_child("TestTail1", true, false) == null, "each add-on appears only on its own hunter")

	# ---- nobody else changes: every other hunter is node-for-node the model the .glb ships
	for other in ["kathy", "ferryn", "verrine", "glyra", "void_red"]:
		var plain := _model(other, false)
		var mounted := _model(other, true)
		_expect(_fingerprint(plain, []) == _fingerprint(mounted, []) and HunterAddons.rig_of(mounted) == null, "%s must be untouched (no add-ons in the data)" % other)
		plain.free()
		mounted.free()

	# ---- removing an entry leaves the model exactly as shipped
	var shipped := _model("dovelle", false)
	var without_line := ModelSlot.instantiate(String(HunterRoster.get_identity("dovelle")["model_scene"]))
	var rig_without := HunterAddons.mount(without_line, "dovelle", {"version": 1, "kits": {"test_tail": {}}, "hunters": {"dovelle": ["test_tail"]}})
	_expect(rig_without == null and _fingerprint(without_line, []) == _fingerprint(shipped, []), "a kit with the line removed leaves the model untouched")
	var data_without: Dictionary = (data.duplicate(true))
	(data_without["hunters"] as Dictionary).erase("dovelle")
	var removed := ModelSlot.instantiate(String(HunterRoster.get_identity("dovelle")["model_scene"]))
	HunterAddons.mount(removed, "dovelle", data_without)
	_expect(_fingerprint(removed, []) == _fingerprint(shipped, []), "deleting Dovelle's line from 'hunters' removes the tail")
	shipped.free()
	without_line.free()
	removed.free()

	# ---- visual only: the camera / interaction fit helpers do not see add-ons
	var plain_dovelle := _model("dovelle", false)
	var bounds_plain := ModelSlot.combined_local_bounds(plain_dovelle)
	var bounds_mounted := ModelSlot.combined_local_bounds(dovelle)
	_expect(bounds_plain.is_equal_approx(bounds_mounted), "add-ons must not change the model's bounds (plain %s vs mounted %s)" % [bounds_plain, bounds_mounted])
	plain_dovelle.free()
	_expect(HunterAddons.addon_nodes(dovelle).size() == 4 + 4 and HunterAddons.addon_nodes(aki).size() >= 1 + 1, "add-on nodes are tagged for removal / inspection")

	# ---- the build is cached: parts share meshes and materials across instances
	var second := _model("dovelle")
	host.add_child(second)
	var a := dovelle.find_child("Addon_test_tail_1", true, false) as MeshInstance3D
	var b := second.find_child("Addon_test_tail_1", true, false) as MeshInstance3D
	_expect(a != null and b != null and a.mesh == b.mesh and a.material_override == b.material_override, "meshes and materials are built once and shared")
	_expect(HunterAddons.plan("dovelle") == HunterAddons.plan("dovelle"), "the plan is cached per hunter")
	second.queue_free()

	# ---- the new bones animate: secondary motion (self-ticking) and a bone pose
	var tail := dovelle.find_child("TestTail2", true, false) as Node3D
	var rest := tail.quaternion
	var seen := 0.0
	var player := ModelSlot.find_animation_player(dovelle)
	player.play("walk")
	for i in 90:
		await tree.process_frame
		seen = maxf(seen, rest.angle_to(tail.quaternion))
	_expect(seen > deg_to_rad(4.0), "the tail sways over the walk clip by itself (peak %.1f deg)" % rad_to_deg(seen))
	player.play("idle")
	var idle_seen := 0.0
	for i in 90:
		await tree.process_frame
		idle_seen = maxf(idle_seen, rest.angle_to(tail.quaternion))
	_expect(idle_seen > deg_to_rad(1.0) and idle_seen < seen, "the idle sway is smaller than the walk sway (%.1f vs %.1f deg)" % [rad_to_deg(idle_seen), rad_to_deg(seen)])
	NightWatchPoses.install(dovelle, player, "dovelle")
	_expect(player.has_animation("nw/test_tail_flick"), "the tail pose is a clip on this hunter")
	var clip := player.get_animation("nw/test_tail_flick")
	var tail_tracks := 0
	for track in clip.get_track_count():
		var node := player.get_node(player.root_node).get_node_or_null(NodePath(String(clip.track_get_path(track))))
		if node != null and String(node.name).begins_with("TestTail"):
			tail_tracks += 1
	_expect(tail_tracks == 4, "the tail pose keys all four runtime bones (%d tracks resolve)" % tail_tracks)
	player.play("nw/test_tail_flick")
	var flicked := 0.0
	for i in 40:
		await tree.process_frame
		flicked = maxf(flicked, rest.angle_to(tail.quaternion))
	_expect(flicked > deg_to_rad(15.0), "playing the tail pose swings the tail (peak %.1f deg)" % rad_to_deg(flicked))
	var plain_player := ModelSlot.find_animation_player(aki)
	NightWatchPoses.install(aki, plain_player, "aki")
	_expect(not plain_player.has_animation("nw/test_tail_flick"), "another hunter does not get the tail pose")
	# the lantern swings too
	var hang := aki.find_child("TestLanternHang", true, false) as Node3D
	var hang_rest := hang.quaternion
	var swung := 0.0
	plain_player.play("walk")
	for i in 90:
		await tree.process_frame
		swung = maxf(swung, hang_rest.angle_to(hang.quaternion))
	_expect(swung > deg_to_rad(3.0), "the held lantern swings (%.1f deg)" % rad_to_deg(swung))
	dovelle.queue_free()
	aki.queue_free()

	# ---- bad data is reported, not fatal
	var broken := ModelSlot.instantiate(String(HunterRoster.get_identity("kathy")["model_scene"]))
	host.add_child(broken)
	var bad := {"kits": {"bad": {"bones": [{"name": "Orphan", "parent": "NoSuchBone"}, {"name": "Pelvis", "parent": "Chest"}],
		"parts": [{"id": "lost", "bone": "NoSuchBone", "shape": {"box": [.1, .1, .1]}}], "motions": [{"id": "m", "bone": "NoSuchBone", "rot": [1, 0, 0]}]}}, "hunters": {"kathy": ["bad"]}}
	var bad_rig := HunterAddons.mount(broken, "kathy", bad)
	_expect(bad_rig != null and bad_rig.errors.size() == 4, "a missing parent / bone and a name collision are reported as errors, nothing crashes (%s)" % [bad_rig.errors if bad_rig != null else "no rig"])
	broken.queue_free()
	HunterAddons.reset()   # back to the shipped data
	HunterAddons.enabled = true

	if _failures == 0:
		print("  ok    hunter_addons: parts and bones from data, the tail animates, a held lantern, visual only, cached, removable")
	return _failures
