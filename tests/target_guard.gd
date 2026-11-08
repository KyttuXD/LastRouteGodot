class_name TargetGuard
extends RefCounted

## Safety net for the headless network tests: they must never silently run against
## production. `problem()` returns "" when the target is acceptable, otherwise why not:
##  - a `--backend=URL` the client refused (it keeps the production origin when a
##    URL is not on its allowlist) would otherwise fall back to production unnoticed;
##  - production itself needs an explicit `--i-know-this-is-production`.

static func problem() -> String:
	var requested := ""
	var acknowledged := false
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--backend="):
			requested = text.trim_prefix("--backend=").trim_suffix("/").to_lower()
		elif text == "--i-know-this-is-production":
			acknowledged = true
	var actual := Backend.base_url.trim_suffix("/").to_lower()
	if not requested.is_empty() and requested != actual:
		return "refusing: --backend=%s was not accepted by the client (it would use %s)" % [requested, actual]
	if actual == Backend.PRIMARY_BASE_URL.to_lower() and not acknowledged:
		return "refusing: the target is PRODUCTION (%s). Use the test instance, or pass --i-know-this-is-production" % actual
	return ""
