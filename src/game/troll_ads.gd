class_name TrollAds
extends RefCounted

## Troll-mode "advertisements" (docs/ANTI_CHEAT.md): in-universe joke/horror ads shown only to a player the host put in
## troll mode with ads on. Not real ads: the text is data (assets/data/troll_ads.json), with no brands, links,
## purchases or tracking. This is the schedule and the content; TrollAdOverlay draws the pop-up and the route swaps
## nearby shop signs.
##
## Cap: at most MAX_PER_WINDOW pop-ups per WINDOW_SECONDS, MIN_GAP_SECONDS apart, each COUNTDOWN_SECONDS long before
## its (moving) SKIP AD works. Never while `blocked` (caught, escaping, death screen, menus).

const PATH := "res://assets/data/troll_ads.json"
const COUNTDOWN_SECONDS := 5.0
const MIN_GAP_SECONDS := 40.0
const FIRST_DELAY_SECONDS := 12.0
const WINDOW_SECONDS := 600.0
const MAX_PER_WINDOW := 6
const BILLBOARD_SWAP_SECONDS := 8.0
const BILLBOARD_RANGE := 14.0

static var _ads: Array = []

var _shown_at: Array[float] = []
var _enabled := false
var _enabled_at := 0.0
var _rng := RandomNumberGenerator.new()


static func all() -> Array:
	if _ads.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and parsed.get("ads") is Array:
				_ads = parsed["ads"]
	return _ads


## One ad with its placeholders filled: {"id", "source", "title", "body", "footer"}.
static func render(ad: Dictionary) -> Dictionary:
	var hunter_id := String(ad.get("hunter", ""))
	var hunter := String(HunterRoster.get_identity(hunter_id).get("name", hunter_id)).to_upper() if not hunter_id.is_empty() else ""
	var shop := String(StreamedRouteGenerator.SHOP_NAMES.get(String(ad.get("shop", "")), ""))
	var out := {"id": String(ad.get("id", "")), "source": String(ad.get("source", ""))}
	for key in ["title", "body", "footer"]:
		out[key] = String(ad.get(key, "")).replace("{hunter}", hunter).replace("{shop}", shop)
	return out


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func pick() -> Dictionary:
	var ads := all()
	return render(ads[_rng.randi() % ads.size()]) if not ads.is_empty() else {}


## Call when ads turn on (or off: `on` false) so the first pop-up waits FIRST_DELAY_SECONDS.
func set_enabled(on: bool, now: float) -> void:
	_enabled = on
	_enabled_at = now


func enabled() -> bool:
	return _enabled


## Whether a pop-up may start now. `blocked`: caught / escaping / death screen / a menu open.
func due(now: float, blocked: bool) -> bool:
	if not enabled() or blocked or now - _enabled_at < FIRST_DELAY_SECONDS:
		return false
	while not _shown_at.is_empty() and now - _shown_at[0] > WINDOW_SECONDS:
		_shown_at.pop_front()
	if _shown_at.size() >= MAX_PER_WINDOW:
		return false
	return _shown_at.is_empty() or now - _shown_at[-1] >= MIN_GAP_SECONDS


func mark_shown(now: float) -> void:
	_shown_at.append(now)


func shown_in_window(now: float) -> int:
	return _shown_at.filter(func(at: float) -> bool: return now - at <= WINDOW_SECONDS).size()
