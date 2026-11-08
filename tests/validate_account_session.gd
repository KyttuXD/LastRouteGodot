extends RefCounted

## A login survives restarts, server switches and a server that is down: sessions are stored per server in the account file,
## a failed/unreachable session check keeps the token (only a rejected one clears it), the debug TEST instance accepts
## accounts, and `--profile` files are separate. Uses a throwaway config file, never the real one.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- account_session

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var backend := Backend
	var saved := {"path": backend.account_config_path, "url": backend.base_url, "test": backend.test_server_active,
		"user": backend.account_username, "token": backend.account_session_token,
		"verified": backend.account_session_verified}
	var temp := "user://validate_account_session.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	backend.account_config_path = temp
	var primary: String = backend.PRIMARY_BASE_URL
	var test_url := "http://127.0.0.1:8205"
	# main server login survives a "restart"
	backend.base_url = primary
	backend.test_server_active = false
	backend.account_username = "KYTTU"
	backend.account_session_token = "main-token"
	backend._save_account_session()
	backend.account_username = ""
	backend.account_session_token = ""
	backend.reload_account_session()
	_expect(backend.account_username == "KYTTU" and backend.account_session_token == "main-token",
		"the main-server login did not survive a reload")
	# the test instance has its own login and does not touch the main one
	backend.base_url = test_url
	backend.test_server_active = true
	backend.reload_account_session()
	_expect(backend.account_session_token.is_empty() or backend.account_session_token != "main-token",
		"the test server picked up the main server's token")
	backend.account_username = "TESTER"
	backend.account_session_token = "test-token"
	backend._save_account_session()
	backend.base_url = primary
	backend.test_server_active = false
	backend.reload_account_session()
	_expect(backend.account_session_token == "main-token", "signing in to the test server replaced the main login")
	backend.base_url = test_url
	backend.test_server_active = true
	backend.reload_account_session()
	_expect(backend.account_session_token == "test-token", "the test server login was not remembered")
	_expect(backend.accounts_available() or not OS.is_debug_build(), "a debug build cannot sign in to the test instance")
	# an unreachable server or a 5xx keeps the token; a rejected session clears only this server's
	backend.account_session_verified = true
	backend._account_operation = "session"
	backend._on_account_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), "{}".to_utf8_buffer())
	_expect(backend.account_session_token == "test-token" and not backend.account_session_verified,
		"an unreachable server cleared the stored login")
	backend._account_operation = "session"
	backend._on_account_response(HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), "{}".to_utf8_buffer())
	_expect(backend.account_session_token == "test-token", "a 5xx cleared the stored login")
	backend._account_operation = "session"
	backend._on_account_response(HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), "{}".to_utf8_buffer())
	_expect(backend.account_session_token.is_empty(), "a rejected session was kept")
	backend.base_url = primary
	backend.test_server_active = false
	backend.reload_account_session()
	_expect(backend.account_session_token == "main-token", "clearing the test login also cleared the main one")
	# profiles
	_expect(RunProfile.path("user://settings.cfg") == "user://settings.cfg" or not RunProfile.name().is_empty(),
		"no profile must leave the path alone")
	# restore
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	backend.account_config_path = saved["path"]
	backend.base_url = saved["url"]
	backend.test_server_active = saved["test"]
	backend.account_username = saved["user"]
	backend.account_session_token = saved["token"]
	backend.account_session_verified = saved["verified"]
	if _failures == 0:
		print("  account   per-server sessions, kept on network errors, cleared only when rejected, test instance allowed in debug")
	return _failures
