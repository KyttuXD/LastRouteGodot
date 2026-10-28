extends RefCounted

## The other ways to pick a skin: an https URL, a Minecraft username (converted from the Minecraft layout), and copying another player's
## skin in co-op. Pure logic and fixtures only -- no network. All of them end in the same validated preview -> apply flow.
##
##   godot --headless --path . res://scenes/validate.tscn -- skin_sources

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _fill(image: Image, rect: Rect2i, color: Color) -> void:
	for y in rect.size.y:
		for x in rect.size.x:
			image.set_pixel(rect.position.x + x, rect.position.y + y, color)


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < .01 and absf(a.g - b.g) < .01 and absf(a.b - b.b) < .01 and absf(a.a - b.a) < .01


func _blank(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(.4, .4, .4, 1.0))
	return image


func run(host: Node) -> int:
	await host.get_tree().process_frame

	# ---- URL rejection cases
	for bad in ["http://example.com/skin.png", "ftp://example.com/a.png", "example.com/skin.png", "", "https://", "javascript:alert(1)",
			"https://user:pass@example.com/a.png", "https://localhost/a.png", "https://foo.localhost/a.png", "https://127.0.0.1/a.png",
			"https://192.168.1.5/a.png", "https://10.0.0.1/a.png", "https://[::1]/a.png", "https://example.com:8443/a.png", "https://intranet/a.png",
			"https://printer.local/a.png", "https://exa mple.com/a.png", "file:///etc/passwd", "https://" + "a".repeat(600) + ".com/x.png",
			"https://example.com@evil.com/a.png", "data:image/png;base64,AAAA"]:
		_expect(not PlayerSkin.check_url(bad).is_empty(), "accepted the address %s" % bad.left(60))
	for good in ["https://example.com/skin.png", "HTTPS://Example.COM/a/b.png?x=1", "https://cdn.example.co.uk:443/skin.png", "https://textures.minecraft.net/texture/abc"]:
		_expect(PlayerSkin.check_url(good).is_empty(), "refused the address %s: %s" % [good, PlayerSkin.check_url(good)])
	_expect(not PlayerSkin.check_url("https://example.com/a.png", ["textures.minecraft.net"]).is_empty(), "a host outside the allow-list was accepted")
	_expect(PlayerSkin.check_url("https://textures.minecraft.net/texture/abc", ["textures.minecraft.net"]).is_empty(), "an allowed host was refused")
	var sync := Backend.skin_sync
	var refused: Dictionary = await sync.skin_from_url("http://example.com/skin.png")
	_expect(not refused["ok"] and String(refused["reason"]).contains("https"), "an http URL was not refused with its reason (%s)" % str(refused.get("reason")))
	refused = await sync.skin_from_url("https://127.0.0.1/skin.png")
	_expect(not refused["ok"], "a loopback URL was fetched")
	# what comes back from a URL goes through the same validation as a picked file
	var wrong := Image.create(48, 48, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	_expect(not PlayerSkin.validate(wrong)["ok"], "a wrong-size download was accepted")
	_expect(not PlayerSkin.validate(PackedByteArray([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 0, 1, 0]))["ok"], "a non-PNG download was accepted")
	var oversized := PackedByteArray(PlayerSkin.PNG_MAGIC)
	oversized.resize(PlayerSkin.MAX_BYTES + 10)
	_expect(not PlayerSkin.validate(oversized)["ok"], "an oversized download was accepted")

	# ---- Mojang profile parsing
	var good_value := Marshalls.raw_to_base64(JSON.stringify({"textures": {"SKIN": {"url": "https://textures.minecraft.net/texture/abc123",
		"metadata": {"model": "slim"}}}}).to_utf8_buffer())
	var parsed := PlayerSkin.parse_textures({"properties": [{"name": "textures", "value": good_value}]})
	_expect(parsed.get("url", "") == "https://textures.minecraft.net/texture/abc123" and parsed.get("slim", false) == true, "a slim profile was not read")
	var classic := Marshalls.raw_to_base64(JSON.stringify({"textures": {"SKIN": {"url": "https://textures.minecraft.net/texture/def"}}}).to_utf8_buffer())
	_expect(PlayerSkin.parse_textures({"properties": [{"name": "textures", "value": classic}]}).get("slim", true) == false, "a classic profile was read as slim")
	for evil_url in ["http://textures.minecraft.net/texture/abc", "https://evil.example.com/texture/abc", "https://textures.minecraft.net.evil.com/x", "https://127.0.0.1/x"]:
		var evil := Marshalls.raw_to_base64(JSON.stringify({"textures": {"SKIN": {"url": evil_url}}}).to_utf8_buffer())
		_expect(PlayerSkin.parse_textures({"properties": [{"name": "textures", "value": evil}]}).is_empty(), "a profile pointing at %s was trusted" % evil_url)
	_expect(PlayerSkin.parse_textures({}).is_empty() and PlayerSkin.parse_textures({"properties": [{"name": "textures", "value": "!!!"}]}).is_empty(), "an empty / garbled profile was trusted")
	for name in ["Notch", "jeb_", "a", "Player_123", "ABCDEFGHIJKLMNOP"]:
		_expect(PlayerSkin.valid_minecraft_name(name), "refused the name %s" % name)
	for name in ["", "x".repeat(17), "bad name", "../x", "a/b", "ünï", "name\n"]:
		_expect(not PlayerSkin.valid_minecraft_name(name), "accepted the name %s" % name.left(20))

	# ---- Minecraft layout conversion round-trip on fixtures
	var modern := _blank(64, 64)
	_fill(modern, Rect2i(8, 8, 8, 8), Color(.9, .2, .2, 1.0))                 # head front
	_fill(modern, Rect2i(40, 32, 16, 16), Color(.1, .1, .9, .5))              # right sleeve overlay, half alpha
	var converted := PlayerSkin.from_minecraft(modern, false)
	_expect(converted["ok"], "a modern 64x64 Minecraft skin was refused")
	var converted_image: Image = converted["image"]
	_expect(_same(converted_image.get_pixel(10, 10), Color(.9, .2, .2, 1.0)), "the head moved in a straight conversion")
	_expect(absf(converted_image.get_pixel(44, 36).a - .5) < .02, "overlay alpha was lost in conversion")
	_expect(not PlayerSkin.from_minecraft(_blank(32, 32))["ok"] and not PlayerSkin.from_minecraft(_blank(128, 128))["ok"] and not PlayerSkin.from_minecraft(null)["ok"], "a wrong-size Minecraft image was converted")
	# old 64x32: the left limbs come from the right ones, mirrored
	var legacy := _blank(64, 32)
	for x in 4:
		legacy.set_pixel(4 + x, 20 + 5, Color(float(x) / 4.0, 1.0, 0.0, 1.0))    # right leg front, row 5, columns coloured by x
		legacy.set_pixel(44 + x, 20 + 5, Color(0.0, 1.0, float(x) / 4.0, 1.0))   # right arm front
	legacy.set_pixel(0, 20 + 2, Color(1.0, 0.0, 0.0, 1.0))                        # right leg, its right-hand side face
	var from_legacy: Dictionary = PlayerSkin.from_minecraft(legacy)
	_expect(from_legacy["ok"], "an old 64x32 skin was refused")
	var upgraded: Image = from_legacy["image"]
	for x in 4:
		_expect(_same(upgraded.get_pixel(20 + (3 - x), 52 + 5), Color(float(x) / 4.0, 1.0, 0.0, 1.0)), "left leg front column %d is not the mirrored right leg" % x)
		_expect(_same(upgraded.get_pixel(36 + (3 - x), 52 + 5), Color(0.0, 1.0, float(x) / 4.0, 1.0)), "left arm front column %d is not the mirrored right arm" % x)
	_expect(_same(upgraded.get_pixel(16 + 8 + 3, 52 + 2), Color(1.0, 0.0, 0.0, 1.0)), "the leg's side faces did not swap when mirrored")
	_expect(_same(upgraded.get_pixel(5, 21), legacy.get_pixel(5, 21)), "the right leg changed in the upgrade")
	# slim arms: 3 columns widen to 4 (repeating the first), sides keep their pixels
	var slim := _blank(64, 64)
	var palette := [Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1)]
	for x in 3:
		slim.set_pixel(44 + x, 20 + 3, palette[x])        # right arm front (3 wide): columns A B C
		slim.set_pixel(51 + x, 20 + 3, palette[x])        # right arm back (starts at 51 in the slim layout)
	slim.set_pixel(40, 22, Color(1, 1, 0, 1))             # right arm, outer side face
	slim.set_pixel(47, 22, Color(0, 1, 1, 1))             # right arm, inner side face (slim: starts at 47)
	var widened: Image = PlayerSkin.from_minecraft(slim, true)["image"]
	var expected := [palette[0], palette[0], palette[1], palette[2]]
	for x in 4:
		_expect(_same(widened.get_pixel(44 + x, 23), expected[x]), "slim front column %d is wrong after widening" % x)
		_expect(_same(widened.get_pixel(52 + x, 23), expected[x]), "slim back column %d is wrong after widening" % x)
	_expect(_same(widened.get_pixel(40, 22), Color(1, 1, 0, 1)) and _same(widened.get_pixel(48, 22), Color(0, 1, 1, 1)), "the slim arm's side faces moved wrongly")
	_expect(PlayerSkin.from_minecraft(slim, false)["ok"], "a classic-flagged skin was refused")

	# ---- copying another player's skin, from the memory cache
	var saved := Settings.skin_hash
	PlayerSkin.reset_active()
	PlayerSkin.clear_peer_cache()
	var theirs := _blank(64, 64)
	_fill(theirs, Rect2i(8, 8, 8, 8), Color(.2, .9, .2, 1.0))
	var theirs_validated := PlayerSkin.validate(theirs.save_png_to_buffer())
	var their_hash := String(theirs_validated["hash"])
	sync.accept_download(their_hash, true, theirs_validated["png"])
	PlayerSkin.note_peer(2, "FRIEND", their_hash, true)
	PlayerSkin.note_peer(3, "PRIVATE", their_hash, false)
	PlayerSkin.note_peer(4, "NOSKIN", "", true)
	var listed := PlayerSkin.copyable_peers()
	_expect(listed.size() == 1 and listed[0]["name"] == "FRIEND", "the copy list is wrong: %s" % str(listed))
	var copied := PlayerSkin.copy_peer(their_hash)
	_expect(copied["ok"] and Settings.skin_hash == their_hash, "copying a peer's skin did not make it yours")
	_expect(FileAccess.file_exists(PlayerSkin.OWN_PATH) and PlayerSkin.load_own() != null, "the copied skin was not kept as your own file")
	_expect(not PlayerSkin.copy_peer("0".repeat(64))["ok"], "copied a skin that is not loaded")
	PlayerSkin.clear_peer_cache()
	_expect(PlayerSkin.copyable_peers().is_empty(), "the copy list survived leaving the room")
	_expect(Settings.skin_hash == their_hash and PlayerSkin.load_own() != null, "a copied skin vanished when the room ended (it is yours now)")

	# ---- the SKIN tab: the new controls exist and feed the same preview
	var settings_scene := load("res://scenes/settings_overlay.tscn") as PackedScene
	if settings_scene != null:
		var panel := settings_scene.instantiate()
		host.add_child(panel)
		await host.get_tree().process_frame
		var section := panel.find_child("SkinSection", true, false) as SkinPanel
		_expect(section != null and section.url_edit != null and section.name_edit != null and section.peer_list != null, "the SKIN tab lacks the URL / name / copy controls")
		if section != null and section.url_edit != null:
			PlayerSkin.note_peer(2, "FRIEND", their_hash, true)
			PlayerSkin.accept_peer(their_hash, theirs_validated["image"])
			section._refresh_peers()
			_expect(not section.peer_list.disabled and section.peer_list.get_item_text(0) == "FRIEND", "the peer list does not show the player to copy")
			PlayerSkin.reset_active()
			var preview: Dictionary = section._copy_peer()
			_expect(preview["ok"] and Settings.skin_hash.is_empty(), "COPY SKIN applied before APPLY")
			section._apply()
			_expect(Settings.skin_hash == their_hash, "APPLY did not wear the copied skin")
			section.url_edit.text = "http://example.com/skin.png"
			await section._from_url()
			_expect(section.status_label.text.contains("https"), "the URL tab did not explain an http refusal (%s)" % section.status_label.text)
			section.name_edit.text = "../etc"
			await section._from_minecraft()
			_expect(section.status_label.text.contains("1-16"), "the name tab did not explain a bad name (%s)" % section.status_label.text)
			_expect(section.copyable_check.button_pressed == Settings.skin_copyable, "the copy-permission box does not match the setting")
		panel.queue_free()

	PlayerSkin.reset_active()
	PlayerSkin.clear_peer_cache()
	if not saved.is_empty():
		Settings.set_skin_hash(saved)
	if _failures == 0:
		print("  ok    skin_sources: URL rejections, Mojang profile parsing, Minecraft layout conversion (modern / old / slim), copy from a peer, SKIN tab")
	return _failures
