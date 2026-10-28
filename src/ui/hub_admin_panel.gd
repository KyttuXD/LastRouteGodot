class_name HubAdminPanel
extends Control

## The games hub's ADMIN panel (only behind the admin-gated ADMIN button): read-only status for admins plus the existing safe
## actions. Sections: THIS BUILD (version, commit, build number, channel, platform tier), ACCOUNT (name, owner, scopes),
## SERVER (the server and channel, /api/health: instance, rooms, relay, uptime), UPDATES (the published manifest per
## platform), PUBLIC ROUTE (/api/public/status), SERVER NOTICES (system lines heard in chat), DEBUG TOGGLES (the admin
## preferences the run's admin menu uses), SKINS (owners: remove/block a skin by hash or username, /api/skins/remove) and
## where the route admin tools are. No secrets: tokens are never shown.

const PLATFORMS := ["macos", "windows", "phone", "quest"]
## Tests replace the network: Callable(path: String, body: Dictionary) -> Dictionary (the parsed JSON, {} on failure).
static var fetch_override := Callable()

var _sections := {}
var _column: VBoxContainer
var _skin_field: LineEdit
var _skin_status: Label
var _health := {}
var _manifests := {}
var _public := {}


func _ready() -> void:
	name = "HubAdminPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, .78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "AdminPanelFrame"
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Color(Palette.PANEL, 1.0), Palette.AMBER, 8))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 16
	panel.offset_top = 12
	panel.offset_right = -16
	panel.offset_bottom = -12
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.text = "ADMIN // STATUS"
	Palette.style_label(title, Palette.AMBER, 10)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var refresh := Button.new()
	refresh.name = "AdminRefreshButton"
	refresh.text = "REFRESH"
	Palette.style_button(refresh, false, true)
	refresh.pressed.connect(refresh_all)
	head.add_child(refresh)
	var close := Button.new()
	close.name = "AdminCloseButton"
	close.text = "CLOSE"
	Palette.style_button(close, false, true)
	close.pressed.connect(queue_free)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 3)
	scroll.add_child(_column)
	for section in ["THIS BUILD", "ACCOUNT", "SERVER", "UPDATES", "PUBLIC ROUTE", "SERVER NOTICES", "DEBUG TOGGLES", "SKINS", "MODERATION", "ROUTE TOOLS"]:
		_add_section(section)
	_build_toggles()
	_build_skins()
	_build_moderation()
	section_text("ROUTE TOOLS", "In a run: press 0 (or the right stick click) for the admin menu: items, hunters, map reveal, god mode,\nroom chat mute / kick, FULLBRIGHT (F7).")
	_fill_local()
	refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _add_section(title: String) -> void:
	var caption := Label.new()
	caption.text = Palette.track(title)
	Palette.style_label(caption, Palette.AMBER, 7)
	_column.add_child(caption)
	var body := Label.new()
	body.name = "Section_" + title.replace(" ", "_")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Palette.style_label(body, Palette.BODY, 7)
	_column.add_child(body)
	_sections[title] = body


func section_text(title: String, text: String) -> void:
	(_sections[title] as Label).text = text


func get_section(title: String) -> String:
	return (_sections[title] as Label).text


func _fill_local() -> void:
	section_text("THIS BUILD", "VERSION %s // BUILD %s (#%d) // CHANNEL %s\n%s" % [Build.VERSION, Build.short_revision().to_upper(),
		Build.build_number(), Build.update_channel().to_upper(), PlatformProfile.summary().to_upper()])
	var scopes := ", ".join(Backend.account_admin_permissions) if not Backend.account_admin_permissions.is_empty() else "NONE"
	section_text("ACCOUNT", "%s // %s // SCOPES %s" % [Backend.account_username if Backend.signed_in() else "NOT SIGNED IN",
		"OWNER" if Backend.admin_owner_authorized() else "ADMIN", scopes.to_upper()])
	var notices := []
	for entry_value in RoomChat.history:
		var entry: Dictionary = entry_value
		if bool(entry.get("system", false)):
			notices.append("// " + String(entry.get("text", "")))
	section_text("SERVER NOTICES", "\n".join(notices) if not notices.is_empty() else "NONE THIS SESSION")


func refresh_all() -> void:
	section_text("SERVER", ServerPrivacy.debug_line() + "\nCHECKING...")
	_health = await _fetch("/api/health", {})
	var lines := [ServerPrivacy.debug_line()]
	if _health.is_empty():
		lines.append(ServerPrivacy.FRIENDLY_UNREACHABLE)
	else:
		for key in ["instance", "service", "rooms", "webRooms", "relay", "runtime", "now"]:
			if _health.has(key):
				lines.append("%s: %s" % [String(key).to_upper(), _short(_health[key])])
	section_text("SERVER", "\n".join(lines))
	var manifest_lines := []
	for platform in PLATFORMS:
		var answer: Dictionary = await _fetch("/api/updates/%s/%s" % [Build.update_channel(), platform], {})
		var update: Dictionary = answer.get("update", {}) if answer.get("update") is Dictionary else {}
		_manifests[platform] = update
		manifest_lines.append("%s: %s" % [platform.to_upper(), "BUILD %d @ %s" % [int(update.get("build", 0)),
			String(update.get("revision", "")).left(8).to_upper()] if not update.is_empty() else "NONE PUBLISHED"])
	section_text("UPDATES", "\n".join(manifest_lines))
	_public = await _fetch("/api/public/status", {})
	section_text("PUBLIC ROUTE", _short(_public) if not _public.is_empty() else "NO ANSWER")
	await refresh_moderation()


static func _short(value) -> String:
	if value is Dictionary:
		var parts := []
		for key in value:
			if String(key).to_lower().contains("token") or String(key).to_lower().contains("secret") or String(key).to_lower().contains("password"):
				continue   # never secrets
			parts.append("%s %s" % [key, _short(value[key]) if not (value[key] is Dictionary or value[key] is Array) else str(value[key].size())])
		return ", ".join(parts)
	return str(value)


func _fetch(path: String, body: Dictionary) -> Dictionary:
	if fetch_override.is_valid():
		return fetch_override.call(path, body)
	var request := HTTPRequest.new()
	request.timeout = 6.0
	add_child(request)
	var url := Backend.base_url.trim_suffix("/") + path
	var error := request.request(url, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST if not body.is_empty() else HTTPClient.METHOD_GET, JSON.stringify(body) if not body.is_empty() else "")
	if error != OK:
		request.queue_free()
		return {}
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {}
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _build_toggles() -> void:
	var grid := GridContainer.new()
	grid.name = "AdminToggles"
	grid.columns = 4
	_column.add_child(grid)
	_column.move_child(grid, (_sections["DEBUG TOGGLES"] as Label).get_index() + 1)
	section_text("DEBUG TOGGLES", "Applied in the next run (the run's admin menu changes them live).")
	for key_value in Settings.ADMIN_PREFERENCE_DEFAULTS:
		var key := String(key_value)
		var button := Button.new()
		button.name = "Toggle_" + key
		button.toggle_mode = true
		Palette.style_state_toggle(button, key.replace("_", " ").to_upper(), Settings.admin_preference(key))
		button.set_pressed_no_signal(Settings.admin_preference(key))
		button.toggled.connect(func(enabled: bool) -> void:
			Settings.set_admin_preference(key, enabled)
			Palette.set_state_toggle(button, enabled))
		grid.add_child(button)


func _build_skins() -> void:
	var row := HBoxContainer.new()
	row.name = "SkinModeration"
	_column.add_child(row)
	_column.move_child(row, (_sections["SKINS"] as Label).get_index() + 1)
	_skin_field = LineEdit.new()
	_skin_field.name = "SkinTargetInput"
	_skin_field.placeholder_text = "SKIN HASH OR USERNAME"
	_skin_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Palette.style_line_edit(_skin_field)
	row.add_child(_skin_field)
	var remove := Button.new()
	remove.name = "SkinRemoveButton"
	remove.text = "REMOVE + BLOCK"
	Palette.style_button(remove, false, true)
	remove.pressed.connect(remove_skin)
	row.add_child(remove)
	_skin_status = Label.new()
	Palette.style_label(_skin_status, Palette.MUTED, 6)
	_column.add_child(_skin_status)
	_column.move_child(_skin_status, row.get_index() + 1)
	var owner := Backend.admin_owner_authorized()
	row.visible = owner
	section_text("SKINS", "Remove a player skin by its hash or the player's name; the hash is blocked from re-upload." if owner
		else "OWNERS ONLY")


## Owners: /api/skins/remove {sessionToken, hash|username}.
func remove_skin() -> void:
	var target := _skin_field.text.strip_edges()
	if target.is_empty() or not Backend.admin_owner_authorized():
		_skin_status.text = "ENTER A HASH OR USERNAME" if target.is_empty() else "OWNERS ONLY"
		return
	var body := {"sessionToken": Backend.account_session_token}
	if target.length() == 64 and target.is_valid_hex_number():
		body["hash"] = target.to_lower()
	else:
		body["username"] = target.to_upper()
	var answer: Dictionary = await _fetch("/api/skins/remove", body)
	_skin_status.text = "SKIN REMOVED AND BLOCKED" if bool(answer.get("ok", false)) else "COULD NOT REMOVE // %s" % String(answer.get("error", "NO ANSWER"))



# -- moderation (owners; WORLD lane's /api/admin/flags API) ----------------------------------------------------------
## Flagged / banned / troll accounts and blocked builds; actions: CLEAR, EXTEND 24H, BAN, UNBAN, TROLL ON, TROLL OFF on a
## username, and adding / removing a blocked build hash. Owners only (the server answers 403 ADMIN_OWNER_REQUIRED otherwise).
## Bans and flags are manual only (KT): the server only queues REVIEWS (a kick, kicks from 2+ hosts in 7 days, an unknown
## build); every action below closes the account's open reviews; DISMISS closes them without restricting anything.
const MODERATION_ACTIONS := [["FLAG 24H", "extend"], ["BAN", "ban"], ["TROLL ON", "troll_on"], ["DISMISS", "dismiss"],
	["CLEAR", "clear"], ["UNBAN", "unban"], ["TROLL OFF", "troll_off"]]
var _moderation_user: LineEdit
var _moderation_build: LineEdit
var _moderation_status: Label
var moderation := {}


func _build_moderation() -> void:
	var owner := Backend.admin_owner_authorized()
	var box := VBoxContainer.new()
	box.name = "ModerationTools"
	box.visible = owner
	_column.add_child(box)
	_column.move_child(box, (_sections["MODERATION"] as Label).get_index() + 1)
	var user_row := HBoxContainer.new()
	box.add_child(user_row)
	_moderation_user = LineEdit.new()
	_moderation_user.name = "ModerationUserInput"
	_moderation_user.placeholder_text = "USERNAME"
	_moderation_user.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Palette.style_line_edit(_moderation_user)
	user_row.add_child(_moderation_user)
	var actions := HFlowContainer.new()
	box.add_child(actions)
	for pair in MODERATION_ACTIONS:
		var button := Button.new()
		button.name = "Moderation_%s" % pair[1]
		button.text = String(pair[0])
		Palette.style_button(button, false, true)
		var action := String(pair[1])
		button.pressed.connect(func() -> void: moderate(_moderation_user.text, action))
		actions.add_child(button)
	var build_row := HBoxContainer.new()
	box.add_child(build_row)
	_moderation_build = LineEdit.new()
	_moderation_build.name = "ModerationBuildInput"
	_moderation_build.placeholder_text = "BUILD HASH TO BLOCK"
	_moderation_build.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Palette.style_line_edit(_moderation_build)
	build_row.add_child(_moderation_build)
	for pair in [["BLOCK BUILD", "add"], ["UNBLOCK", "remove"]]:
		var button := Button.new()
		button.name = "ModerationBuild_%s" % pair[1]
		button.text = String(pair[0])
		Palette.style_button(button, false, true)
		var which := String(pair[1])
		button.pressed.connect(func() -> void: block_build(_moderation_build.text, which == "add"))
		build_row.add_child(button)
	_moderation_status = Label.new()
	_moderation_status.name = "ModerationStatus"
	Palette.style_label(_moderation_status, Palette.MUTED, 6)
	box.add_child(_moderation_status)
	section_text("MODERATION", "LOADING..." if owner else "OWNERS ONLY")


func refresh_moderation() -> void:
	if not Backend.admin_owner_authorized():
		return
	moderation = await _fetch("/api/admin/flags", {"sessionToken": Backend.account_session_token})
	if not bool(moderation.get("ok", false)):
		section_text("MODERATION", "UNAVAILABLE // %s" % String(moderation.get("error", "NO ANSWER")))
		return
	var lines := []
	var open_reviews := 0
	for record_value in moderation.get("accounts", []):
		var record: Dictionary = record_value
		var open := int(record.get("reviewOpen", 0))
		open_reviews += open
		lines.append_array(format_account(record))
	lines.push_front("REVIEW QUEUE: %d OPEN" % open_reviews)
	var builds: Array = moderation.get("builds", [])
	lines.append("BLOCKED BUILDS: %s" % (", ".join(builds.map(func(b) -> String:
		return String(b.get("buildHash", b) if b is Dictionary else b).left(12).to_upper())) if not builds.is_empty() else "NONE"))
	section_text("MODERATION", "\n".join(lines) if not lines.is_empty() else "NO FLAGGED ACCOUNTS")


## One account's lines: name + state, then each OPEN review (reason, detail, when), its kicks and its build integrity.
static func format_account(record: Dictionary) -> Array:
	var state := []
	if bool(record.get("permanent", false)):
		state.append("BANNED")
	elif bool(record.get("flagged", false)):
		state.append("FLAGGED UNTIL %s" % str(record.get("flaggedUntil", "?")))
	if bool(record.get("troll", false)):
		state.append("TROLL")
	var open := int(record.get("reviewOpen", 0))
	var lines := ["%s%s: %s%s" % ["[REVIEW] " if open > 0 else "", String(record.get("username", "?")).to_upper(),
		" + ".join(state) if not state.is_empty() else "CLEAR",
		(" // " + String(record.get("reason", ""))) if not String(record.get("reason", "")).is_empty() else ""]]
	for review_value in record.get("reviews", []):
		var review: Dictionary = review_value
		if not bool(review.get("open", false)):
			continue
		var why: String = {"kick": "KICKED", "kicks": "KICKED BY 2+ HOSTS IN 7 DAYS", "integrity": "UNKNOWN BUILD"}.get(String(review.get("reason", "")), String(review.get("reason", "")).to_upper())
		lines.append("   %s // %s // %s" % [why, String(review.get("detail", "")), str(review.get("at", ""))])
	var kicks: Array = record.get("kicks", [])
	if not kicks.is_empty():
		lines.append("   KICKS: %s" % ", ".join(kicks.map(func(k) -> String:
			return ("%s @ %s" % [String(k.get("by", k.get("host", "?"))), str(k.get("at", ""))]) if k is Dictionary else str(k))))
	var integrity = record.get("integrity")
	if integrity is Dictionary and not (integrity as Dictionary).is_empty():
		lines.append("   BUILD %s @ %s%s" % [String(integrity.get("hash", "")).left(12).to_upper(), String(integrity.get("commit", "")).left(8).to_upper(),
			"" if bool(integrity.get("known", true)) else " (UNKNOWN)"])
	return lines


## /api/admin/flags/set {sessionToken, username, action, hours?}.
func moderate(username: String, action: String) -> void:
	var name := username.strip_edges().to_upper()
	if name.is_empty():
		_moderation_status.text = "ENTER A USERNAME"
		return
	var body := {"sessionToken": Backend.account_session_token, "username": name, "action": action}
	if action == "extend":
		body["hours"] = 24
	var answer: Dictionary = await _fetch("/api/admin/flags/set", body)
	_moderation_status.text = ("%s // %s" % [action.to_upper().replace("_", " "), name]) if bool(answer.get("ok", false)) \
		else "FAILED // %s" % String(answer.get("error", "NO ANSWER"))
	await refresh_moderation()


## /api/admin/builds/add | remove {sessionToken, buildHash}.
func block_build(build_hash: String, block: bool) -> void:
	var hash_value := build_hash.strip_edges().to_lower()
	if hash_value.is_empty():
		_moderation_status.text = "ENTER A BUILD HASH"
		return
	var answer: Dictionary = await _fetch("/api/admin/builds/%s" % ("add" if block else "remove"),
		{"sessionToken": Backend.account_session_token, "buildHash": hash_value})
	_moderation_status.text = ("BUILD %s" % ("BLOCKED" if block else "UNBLOCKED")) if bool(answer.get("ok", false)) \
		else "FAILED // %s" % String(answer.get("error", "NO ANSWER"))
	await refresh_moderation()
