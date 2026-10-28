extends RefCounted

## The hub ADMIN panel: opens only for admins (the gated ADMIN button), shows this build, the account and its scopes, the
## server health, the published update per platform, the public route and server notices, the debug toggles and (owners) skin
## removal; never a session token or other secret.
##
##   godot --headless --path . res://scenes/validate.tscn -- admin_panel

var _failures := 0
var _calls: Array = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _fake(path: String, body: Dictionary) -> Dictionary:
	_calls.append([path, body])
	if path == "/api/health":
		return {"ok": true, "instance": "prod-a", "rooms": 3, "webRooms": 1, "relay": {"enabled": true, "sessions": 2},
			"runtime": {"uptimeSeconds": 4200}, "secretKey": "never-show"}
	if path.begins_with("/api/updates/"):
		return {"ok": true, "update": {"build": 783, "revision": "117a18a8725fa9e0e8e0cd2dbe1c8343bd204388"}}
	if path == "/api/public/status":
		return {"ok": true, "online": 4, "route": "PUBLIC"}
	if path == "/api/skins/remove":
		return {"ok": true}
	if path == "/api/admin/flags":
		return {"ok": true, "reviews": ["suspect"], "accounts": [
			{"username": "suspect", "reviewOpen": 2, "reviews": [
				{"at": "2026-10-28T09:00", "reason": "kicks", "detail": "HOST A, HOST B", "open": true},
				{"at": "2026-10-28T10:00", "reason": "integrity", "detail": "build not in list", "open": true},
				{"at": "2026-10-20T10:00", "reason": "kick", "detail": "old", "open": false, "closedBy": "KYTTU"}],
				"kicks": [{"at": "2026-10-27", "room": "ABCDE", "host": "1a2b3c4d5e6f7a8b", "reason": "griefing", "strikes": 1}, {"at": "2026-10-28", "room": "FGHIJ", "host": "9f8e7d6c5b4a3f2e", "reason": "spam", "strikes": 2}],
				"integrity": {"commit": "117a18a8", "hash": "cafebabe00112233", "known": false}},
			{"username": "griefer", "flagged": true, "flaggedUntil": "2026-11-01", "troll": true, "ads": false, "reason": "spam"},
			{"username": "old", "permanent": true}], "builds": [{"buildHash": "deadbeef0123456789"}]}
	if path in ["/api/admin/flags/set", "/api/admin/builds/add", "/api/admin/builds/remove"]:
		return {"ok": true}
	return {}


func run(host: Node) -> int:
	HubAdminPanel.fetch_override = _fake
	# not an admin: no button, no panel
	GameHub.admin_override = 0
	var hub := (load("res://scenes/game_hub.tscn") as PackedScene).instantiate() as GameHub
	host.add_child(hub)
	await host.get_tree().process_frame
	hub._on_admin()
	_expect(hub.find_child("HubAdminPanel", true, false) == null, "a non-admin opened the admin panel")
	GameHub.admin_override = 1
	# act as the owner for the owner-only sections (restored below; nothing is saved)
	var saved := [Backend.account_username, Backend.account_session_token, Backend.account_session_verified, Backend.account_admin,
		Backend.account_admin_owner, Backend.account_admin_permissions]
	Backend.account_username = "KYTTU"
	Backend.account_session_token = "validation-token"
	Backend.account_session_verified = true
	Backend.account_admin = true
	Backend.account_admin_owner = true
	Backend.account_admin_permissions = PackedStringArray(["world", "visual"])
	_expect(Backend.admin_owner_authorized(), "could not act as the owner for the test")
	hub._on_admin()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var panel := hub.find_child("HubAdminPanel", true, false) as HubAdminPanel
	_expect(panel != null, "the ADMIN button does not open the admin panel")
	if panel != null:
		_expect(panel.get_section("THIS BUILD").contains("VERSION") and panel.get_section("THIS BUILD").contains("CHANNEL"), "no build info")
		_expect(panel.get_section("ACCOUNT").contains("SCOPES"), "no account/scopes")
		var server := panel.get_section("SERVER")
		_expect(server.contains("INSTANCE: prod-a") and server.contains("ROOMS: 3") and server.contains("RELAY"), "health not shown: %s" % server)
		_expect(not server.contains("never-show"), "a secret field reached the panel")
		var updates := panel.get_section("UPDATES")
		_expect(updates.contains("MACOS: BUILD 783 @ 117A18A8") and updates.contains("QUEST: BUILD 783"), "manifest per platform not shown: %s" % updates)
		_expect(panel.get_section("PUBLIC ROUTE").contains("online 4"), "public route status not shown")
		_expect(panel.find_child("AdminToggles", true, false) != null and panel.find_child("Toggle_god_mode", true, false) != null, "no debug toggles")
		var token := String(Backend.account_session_token)
		for node in panel.find_children("*", "Label", true, false):
			_expect(token.is_empty() or not (node as Label).text.contains(token), "the session token is shown")
		# owners: skin removal posts the hash
		if Backend.admin_owner_authorized():
			(panel.find_child("SkinTargetInput", true, false) as LineEdit).text = "a".repeat(64)
			await panel.remove_skin()
			var last: Array = _calls[-1]
			_expect(last[0] == "/api/skins/remove" and String((last[1] as Dictionary).get("hash", "")) == "a".repeat(64), "skin removal did not post the hash")
		if Backend.admin_owner_authorized():
			var mod := panel.get_section("MODERATION")
			_expect(mod.contains("GRIEFER: FLAGGED UNTIL") and mod.contains("TROLL") and mod.contains("OLD: BANNED") and mod.contains("DEADBEEF0123"),
				"moderation list not shown: %s" % mod)
			_expect(mod.contains("REVIEW QUEUE: 2 OPEN") and mod.contains("[REVIEW] SUSPECT") and mod.contains("KICKED BY 2+ HOSTS IN 7 DAYS // HOST A, HOST B")
				and mod.contains("UNKNOWN BUILD") and mod.contains("KICKS: ABCDE (1a2b3c4d5e6f7a8b) @ 2026-10-27 // GRIEFING, 1 STRIKE, FGHIJ (9f8e7d6c5b4a3f2e) @ 2026-10-28 // SPAM, 2 STRIKES") and mod.contains("BUILD CAFEBABE0011 @ 117A18A8 (UNKNOWN)")
				and not mod.contains("// old //"), "review queue not shown right: %s" % mod.replace("\n", " | "))
			_expect(panel.find_child("Moderation_dismiss", true, false) != null, "no DISMISS button")
			_expect(panel.find_child("Moderation_ads_on", true, false) != null and panel.find_child("Moderation_ads_off", true, false) != null, "no ADS ON / OFF buttons")
			_expect(mod.contains("TROLL (ADS OFF)"), "the ads state is not shown")
			await panel.moderate("griefer", "ads_off")
			var ads: Dictionary = (_calls.filter(func(c: Array) -> bool: return c[0] == "/api/admin/flags/set")[-1] as Array)[1]
			_expect(ads.get("action") == "ads_off", "ADS OFF did not post")
			await panel.moderate("suspect", "dismiss")
			var dismissed: Dictionary = (_calls.filter(func(c: Array) -> bool: return c[0] == "/api/admin/flags/set")[-1] as Array)[1]
			_expect(dismissed.get("action") == "dismiss" and dismissed.get("username") == "SUSPECT", "DISMISS did not post: %s" % dismissed)
			await panel.moderate("griefer", "extend")
			var sent: Dictionary = (_calls.filter(func(c: Array) -> bool: return c[0] == "/api/admin/flags/set")[-1] as Array)[1]
			_expect(sent.get("username") == "GRIEFER" and sent.get("action") == "extend" and int(sent.get("hours", 0)) == 24, "EXTEND did not post the right body: %s" % sent)
			await panel.block_build("ABCDEF", true)
			_expect((_calls[-2] as Array)[0] == "/api/admin/builds/add" or _calls.any(func(c: Array) -> bool: return c[0] == "/api/admin/builds/add"), "BLOCK BUILD did not post")
		panel.queue_free()
	Backend.account_username = saved[0]
	Backend.account_session_token = saved[1]
	Backend.account_session_verified = saved[2]
	Backend.account_admin = saved[3]
	Backend.account_admin_owner = saved[4]
	Backend.account_admin_permissions = saved[5]
	GameHub.admin_override = -1
	HubAdminPanel.fetch_override = Callable()
	hub.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  adminpanel admins only; build, account/scopes, health, manifest per platform, public route, notices, toggles, skin removal; no secrets")
	return _failures
