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
		panel.queue_free()
	GameHub.admin_override = -1
	HubAdminPanel.fetch_override = Callable()
	hub.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  adminpanel admins only; build, account/scopes, health, manifest per platform, public route, notices, toggles, skin removal; no secrets")
	return _failures
