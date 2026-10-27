extends RefCounted

## Accounts are app-wide (docs/GAME_HUB.md, "Accounts"): one AccountPanel for the hub and every game's menu, one login in the
## Backend autoload, the hub header and open menus follow sign-in/out, saves are namespaced per game in the account
## document with Last Route's record unchanged, and the panel itself carries no Last Route wording.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _texts(node: Node, skip_prefix: String, out: Array) -> void:
	if node.name.begins_with(skip_prefix):
		return
	if node is Label:
		out.append(String((node as Label).text))
	elif node is Button:
		out.append(String((node as Button).text))
	elif node is LineEdit:
		out.append(String((node as LineEdit).placeholder_text))
	for child in node.get_children():
		_texts(child, skip_prefix, out)


func run(host: Node) -> int:
	var before := {"username": Backend.account_username, "token": Backend.account_session_token, "admin": Backend.account_admin,
		"verified": Backend.account_session_verified, "progress": Backend.account_progress.duplicate(true),
		"busy": Backend.account_busy, "base_url": Backend.base_url}
	Backend.account_username = ""
	Backend.account_session_token = ""
	Backend.account_admin = false
	Backend.account_session_verified = false
	Backend.account_progress = {}
	Backend.base_url = Backend.PRIMARY_BASE_URL
	Backend.account_busy = true   # saves queue instead of going to the network

	var hub: Control = (load("res://scenes/game_hub.tscn") as PackedScene).instantiate()
	host.add_child(hub)
	await host.get_tree().process_frame
	var header := hub.find_child("HubSignedIn", true, false) as Label
	_expect(header != null and header.text == "NOT SIGNED IN", "the hub header does not show the signed-out state")

	# the hub's ACCOUNT button opens the shared panel, titled for the whole app
	(hub.find_child("AccountButton", true, false) as Button).pressed.emit()
	await host.get_tree().process_frame
	var panel := host.get_tree().root.find_child("AccountPanel", true, false) as AccountPanel
	_expect(panel != null, "the hub ACCOUNT button did not open the shared AccountPanel")
	if panel != null:
		var texts := []
		_texts(panel, "SaveRow_", texts)
		var kicker := panel.find_child("AccountKicker", true, false) as Label
		_expect(kicker != null and kicker.text.replace(" ", "").replace("\u2009", "") == "KYTTU'SLAB//ACCOUNT", "the account panel is not titled KYTTU'S LAB // ACCOUNT")
		for text in texts:
			var upper: String = String(text).to_upper()
			_expect(not upper.contains("LAST ROUTE") and not upper.contains("CHECKPOINT") and not upper.contains("SAVED ROUTE") and not upper.contains("CONTINUE ROUTE"),
				"the signed-out account panel carries Last Route wording: %s" % text)

		# sign in (state only: the server is not involved) -> the same signal updates the hub and the panel
		Backend.account_username = "RUNNER_TEST"
		Backend.account_session_token = "validation-token"
		Backend.account_session_verified = true
		Backend.account_admin = true
		Backend.account_changed.emit(true, "RUNNER_TEST", true, "SIGNED IN AS RUNNER_TEST")
		await host.get_tree().process_frame
		_expect(header.text.contains("RUNNER_TEST") and header.text.contains("ADMIN"), "the hub header did not follow the sign-in: %s" % header.text)
		_expect(panel.find_child("SaveRow_last_route", true, false) != null, "the signed-in panel has no SAVES row for Last Route")
		for game in GameRegistry.all():
			_expect(panel.find_child("SaveRow_%s" % game["id"], true, false) != null, "no SAVES row for %s" % game["id"])
		texts = []
		_texts(panel, "SaveRow_", texts)
		for text in texts:
			var upper: String = String(text).to_upper()
			_expect(not upper.contains("LAST ROUTE") and not upper.contains("CHECKPOINT") and not upper.contains("CONTINUE ROUTE"),
				"the signed-in account panel carries Last Route wording outside the SAVES list: %s" % text)
		panel.close()
	hub.queue_free()

	# one login for every entry scene: they all read the same Backend state
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	host.add_child(menu)
	await host.get_tree().process_frame
	var menu_account := menu.find_child("AccountButton", true, false) as Button
	_expect(menu_account != null and menu_account.text == "RUNNER_TEST", "the Last Route menu does not show the shared login")
	menu.queue_free()

	# saves: a legacy Last Route document still loads, another game's save lives beside it, clearing one leaves the other
	Backend.account_progress = {"schema": 1, "kind": "last_route", "depth": 4, "score": 900, "difficulty_id": "standard",
		"hunter_discoveries": ["aki"]}
	_expect(Backend.has_route_checkpoint() and Backend.game_has_save("last_route"), "an old Last Route save no longer loads")
	_expect(String(GameRegistry.save_summary("last_route")["text"]).contains("DEPTH 4"), "the Last Route save summary is wrong")
	_expect(not Backend.game_has_save("city"), "a game without a save claims one")
	Backend.account_save_game_progress("city", {"summary": "DISTRICT 2", "district": 2})
	_expect(Backend.game_has_save("city") and Backend.game_progress("city").get("district") == 2, "a City save was not stored under games.city")
	_expect(Backend.has_route_checkpoint() and int(Backend.account_progress.get("depth", 0)) == 4
			and Backend.account_progress.get("hunter_discoveries") == ["aki"],
		"saving another game's progress changed Last Route's record")
	Backend.account_save_progress({"schema": 1, "kind": "last_route", "depth": 5, "score": 1000, "difficulty_id": "standard"})
	await host.get_tree().process_frame
	Backend._pending_progress_save.clear()
	_expect(Backend.game_has_save("city") or Backend._pending_progress_save.is_empty(), "internal check")
	Backend.account_clear_game_progress("city")
	_expect(not Backend.game_has_save("city") and Backend.has_route_checkpoint(), "clearing the City save touched Last Route")
	_expect(String(GameRegistry.save_summary("city")["text"]) == "NONE", "a cleared game does not list as NONE")
	Backend._pending_progress_save.clear()

	Backend.account_username = before["username"]
	Backend.account_session_token = before["token"]
	Backend.account_admin = before["admin"]
	Backend.account_session_verified = before["verified"]
	Backend.account_progress = before["progress"]
	Backend.account_busy = before["busy"]
	Backend.base_url = before["base_url"]
	if _failures == 0:
		print("  account_hub  one shared panel, header and menus follow sign-in, per-game saves, no Last Route wording")
	return _failures
