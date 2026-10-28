class_name MusicBoxes
extends RefCounted

## The route's music boxes (random route items, two per 4x4-chunk region; see StreamedRouteGenerator._music_boxes).
## Every peer keeps one of these and ticks it: a wind is a stream event every peer applies, so the tune each player
## hears stays in step, and the host's copy is the one Glyra reads. Glyra's replicated gimmick state re-syncs a guest's
## copy of her own box. A box nobody has touched yet counts as freshly wound the first time anything asks about it.

enum Mood { PLAYING, WINDING_DOWN, STOPPED }

var difficulty_id := "standard"
var _left := {}


func wound_seconds() -> float:
	return float(GameConfig.MUSIC_BOX_WOUND_SECONDS.get(difficulty_id, GameConfig.MUSIC_BOX_WOUND_SECONDS["standard"]))


func seconds_left(id: String) -> float:
	if id.is_empty():
		return wound_seconds()
	if not _left.has(id):
		_left[id] = wound_seconds()
	return float(_left[id])


func mood(id: String) -> Mood:
	return mood_for(seconds_left(id))


static func mood_for(left: float) -> Mood:
	if left <= 0.0:
		return Mood.STOPPED
	if left <= GameConfig.MUSIC_BOX_WINDDOWN_SECONDS:
		return Mood.WINDING_DOWN
	return Mood.PLAYING


func wind(id: String) -> void:
	if not id.is_empty():
		_left[id] = wound_seconds()


## Guests adopt the host's clock for a box (Glyra's gimmick state carries it).
func set_seconds_left(id: String, left: float) -> void:
	if not id.is_empty():
		_left[id] = maxf(0.0, left)


func tick(delta: float) -> void:
	for id in _left:
		_left[id] = maxf(0.0, float(_left[id]) - delta)


func known_ids() -> Array:
	return _left.keys()
