extends RefCounted

## The hub's ADMIN button is only for owners, scoped admins and dev-tools builds: hidden for guests, offline players and normal
## accounts (no gap left in the ACCOUNT / SETTINGS / QUIT row), shown for admins, and it follows sign-in / sign-out live.
##
##   godot --headless --path . res://scenes/validate.tscn -- admin_entry

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	GameHub.admin_override = 0
	var hub := (load("res://scenes/game_hub.tscn") as PackedScene).instantiate() as GameHub
	host.add_child(hub)
	for _i in 4:
		await host.get_tree().process_frame
	var admin := hub.find_child("AdminButton", true, false) as Button
	_expect(admin != null and not admin.visible, "a guest / normal account sees ADMIN")
	var row: Array = []
	for child in admin.get_parent().get_children():
		if child is Button and (child as Button).visible:
			row.append(child)
	for i in range(1, row.size()):
		var gap := (row[i] as Control).position.x - ((row[i - 1] as Control).position.x + (row[i - 1] as Control).size.x)
		_expect(gap <= 6.5, "the footer row leaves a %.0f-unit gap where ADMIN was" % gap)
	# signing in as an admin shows it at once (Backend.account_changed -> _refresh_signed_in)
	GameHub.admin_override = 1
	hub._refresh_signed_in()
	_expect(admin.visible and not admin.disabled, "an owner / scoped admin does not see ADMIN")
	GameHub.admin_override = 0
	hub._refresh_signed_in()
	_expect(not admin.visible, "signing out did not hide ADMIN")
	_expect(not Backend.signed_in() or Build.tools_enabled() or not GameHub.admin_entry_visible(), "gate mismatch")
	GameHub.admin_override = -1
	hub.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  adminbtn  ADMIN hidden for guests/normal accounts (row closes up), shown for admins, follows sign-in live")
	return _failures
