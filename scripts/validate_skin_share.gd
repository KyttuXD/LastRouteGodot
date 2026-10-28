extends RefCounted

## Sharing player skins in co-op: peers' skins are downloaded by hash into MEMORY only (nothing under user:// but your own skin),
## verified against their hash and validated before use, shown on the right co-op body, freed when a peer leaves, and gone when
## the room ends. Guests and offline players publish no hash (local-only skins).
##
##   godot --headless --path . res://scenes/validate.tscn -- skin_share

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _png(color: Color) -> PackedByteArray:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return PlayerSkin.validate(image.save_png_to_buffer())["png"]


## Every file under user:// (recursive), as relative paths.
func _files(path: String = "user://") -> Array:
	var found: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				found.append_array(_files(path.path_join(entry)))
		else:
			found.append(path.path_join(entry))
		entry = dir.get_next()
	return found


func _carries(body: Node, texture: Texture2D) -> bool:
	var seen := 0
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				if material.albedo_texture != texture:
					return false
				seen += 1
	return seen > 0


func run(host: Node) -> int:
	await host.get_tree().process_frame
	var sync := Backend.skin_sync
	_expect(sync != null, "the backend has no skin sync")
	if sync == null:
		return 1
	var saved := Settings.skin_hash
	PlayerSkin.reset_active()
	PlayerSkin.clear_peer_cache()
	var before := _files()

	# ---- downloads: hash-checked, validated, memory only
	var red := _png(Color(.9, .1, .1, 1.0))
	var blue := _png(Color(.1, .1, .9, 1.0))
	var red_hash := PlayerSkin.hash_of(red)
	var blue_hash := PlayerSkin.hash_of(blue)
	_expect(sync.accept_download(red_hash, true, red), "a good download was refused")
	_expect(sync.accept_download(blue_hash, true, blue), "a second good download was refused")
	_expect(PlayerSkin.peer_cache_size() == 2, "two downloads should be cached (%d)" % PlayerSkin.peer_cache_size())
	_expect(not sync.accept_download(red_hash, true, blue), "bytes that do not match their hash were accepted")
	var junk := PackedByteArray([1, 2, 3, 4])
	_expect(not sync.accept_download(PlayerSkin.hash_of(junk), true, junk), "a non-PNG download was accepted")
	var small := Image.create(32, 32, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	_expect(not sync.accept_download(PlayerSkin.hash_of(small), true, small), "a wrong-size download was accepted")
	_expect(not sync.accept_download(red_hash, false, PackedByteArray()), "a failed request was accepted")
	_expect(PlayerSkin.peer_cache_size() == 2, "refused downloads changed the cache (%d)" % PlayerSkin.peer_cache_size())
	var after := _files()
	_expect(after == before, "downloading peers' skins wrote files under user://: %s" % str(after.filter(func(p): return not before.has(p))))
	_expect(not DirAccess.dir_exists_absolute("user://skins") or _files("user://skins").is_empty(), "a skins cache folder exists")
	var fetched: Array = []
	sync.fetched.connect(func(h: String) -> void: fetched.append(h))
	var green := _png(Color(.1, .9, .1, 1.0))
	sync.accept_download(PlayerSkin.hash_of(green), true, green)
	_expect(fetched == [PlayerSkin.hash_of(green)], "the fetched signal did not fire for a new skin")
	PlayerSkin.clear_peer_cache()

	# ---- co-op bodies show the right skin and free it when the peer leaves
	sync.accept_download(red_hash, true, red)
	sync.accept_download(blue_hash, true, blue)
	var players := RemotePlayers.new()
	host.add_child(players)
	var bodies := {}
	for id in [2, 3, 4]:
		var body := ModelSlot.instantiate(PlayerModels.SCENE)
		host.add_child(body)
		bodies[id] = body
		players._bodies[id] = body
	players._apply_peer_skin(2, bodies[2], red_hash)
	players._apply_peer_skin(3, bodies[3], blue_hash)
	players._apply_peer_skin(4, bodies[4], "")
	_expect(_carries(bodies[2], PlayerSkin.peer_texture(red_hash)), "peer 2 does not wear their skin")
	_expect(_carries(bodies[3], PlayerSkin.peer_texture(blue_hash)), "peer 3 does not wear their skin")
	_expect(_carries(bodies[2], PlayerSkin.peer_texture(red_hash)) and not _carries(bodies[3], PlayerSkin.peer_texture(red_hash)), "peers share a skin")
	_expect(String(players._peer_skin[4]).is_empty(), "a peer without a skin was given one")
	players._apply_peer_skin(3, bodies[3], "not-a-hash")
	_expect(String(players._peer_skin[3]).is_empty(), "a malformed hash was kept")
	sync.accept_download(blue_hash, true, blue)   # peer 3 cleared their skin, so it was freed; it comes back with the next one
	players._apply_peer_skin(3, bodies[3], blue_hash)
	players._drop(2)
	_expect(PlayerSkin.peer_texture(red_hash) == null, "a peer who left kept their skin in memory")
	_expect(PlayerSkin.peer_texture(blue_hash) != null, "another peer's skin was freed too early")
	# an unknown hash waits for the download instead of showing anything wrong
	var unknown := PlayerSkin.hash_of(PackedByteArray([9, 9, 9]))
	players._apply_peer_skin(4, bodies[4], unknown)
	_expect(_carries(bodies[4], PlayerSkin.default_texture()) or not _carries(bodies[4], PlayerSkin.peer_texture(blue_hash)), "a peer waiting on a download shows someone else's skin")
	_expect(PlayerSkin.peer_texture(unknown) == null, "an undownloaded skin is in the cache")

	# ---- the room ends: the cache is empty
	players.queue_free()
	await host.get_tree().process_frame
	_expect(PlayerSkin.peer_cache_size() == 0, "the cache survived the room scene (%d)" % PlayerSkin.peer_cache_size())
	sync.accept_download(red_hash, true, red)
	sync.clear_cache()
	_expect(PlayerSkin.peer_cache_size() == 0, "leaving the room left %d skins in memory" % PlayerSkin.peer_cache_size())
	for body in bodies.values():
		if is_instance_valid(body):
			(body as Node).queue_free()

	# ---- XR: the hands on the controllers are the mannequin's skinned hand parts, in the same skin as flat mode; a remote rig too
	PlayerSkin.import_bytes(_png(Color(.8, .3, .8, 1.0)))
	var own := PlayerSkin.active_texture()
	var left_controller := XRController3D.new()
	var right_controller := XRController3D.new()
	var origin := XROrigin3D.new()
	host.add_child(origin)
	origin.add_child(left_controller)
	origin.add_child(right_controller)
	var xr_hands := XRHands.new()
	host.add_child(xr_hands)
	xr_hands.setup(Node3D.new(), origin, left_controller, right_controller)
	for controller in [left_controller, right_controller]:
		var rig := controller.find_child("SkinnedHand", true, false) as Node3D
		_expect(rig != null, "an XR controller has no mannequin hand")
		if rig != null:
			_expect(_carries(rig, own), "an XR hand does not wear the flat-mode skin")
	PlayerSkin.import_bytes(_png(Color(.2, .8, .8, 1.0)))   # changing the skin updates the XR hands live
	var changed := PlayerSkin.active_texture()
	_expect(changed != own and _carries(left_controller.find_child("SkinnedHand", true, false), changed), "an XR hand did not follow a skin change")
	# the remote VR rig is the same mannequin through the same apply: it shows a peer's skin like any co-op body
	var remote_rig := ModelSlot.instantiate(PlayerModels.SCENE)
	host.add_child(remote_rig)
	PlayerSkin.apply(remote_rig, changed)
	_expect(_carries(remote_rig, changed), "a remote VR rig does not show the skin")
	remote_rig.queue_free()
	xr_hands.queue_free()
	origin.queue_free()
	PlayerSkin.reset_active()

	# ---- publishing: only when signed in and the server holds the skin
	PlayerSkin.import_bytes(_png(Color(.5, .5, .1, 1.0)))
	sync.uploaded_hash = ""
	_expect(sync.shared_hash().is_empty(), "a skin the server does not hold was published to the room")
	sync.uploaded_hash = Settings.skin_hash
	_expect(sync.shared_hash() == Settings.skin_hash, "an uploaded skin was not published")
	PlayerSkin.reset_active()
	_expect(sync.shared_hash().is_empty(), "no skin still published a hash")
	sync.uploaded_hash = ""
	var leftover := _files().filter(func(p: String) -> bool: return not before.has(p) and p != "user://settings.cfg")
	_expect(leftover.is_empty() and not FileAccess.file_exists(PlayerSkin.OWN_PATH), "skin files remain after reset: %s" % str(leftover))
	if not saved.is_empty():
		Settings.set_skin_hash(saved)

	if _failures == 0:
		print("  ok    skin_share: peers' skins by hash, memory only (no files), right body, freed on leave and when the room ends, local-only guests")
	return _failures
