extends RefCounted

## Music wing props (docs/MUSIC_WING.md): every prop of the data family "music" is wired like any catalogued prop (models in
## res://data, loadable GLBs, footprint, template size, hunter scale 1.5, a collider when solid, the right mount list), the
## playable ones (MusicProps) prompt and play their cue, and with music_noise on they make a noise burst hunters hear; with
## it off they only sound. Dressing stays batchable, playable props are not.
##
##   godot --headless --path . res://scenes/validate.tscn -- music

const DRESSING_NOT_SOLID := ["deskMic", "studioMonitors", "cableCoil", "cableRun", "acousticPanel", "guitarWallHanger", "onAirSign"]
const WALL := ["acousticPanel", "guitarWallHanger", "onAirSign"]
const FLOOR_DRESSING := ["cableCoil", "cableRun"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


class FakePlayer extends Node:
	var bursts: Array = []

	func emit_noise_burst(level: float, seconds: float) -> void:
		bursts.append([level, seconds])


func run(host: Node) -> int:
	var ids: Array = ContentRegistry.family("music")
	_expect(ids.size() == 24, "the music family has %d props, expected 24" % ids.size())
	for id in ids:
		_check_prop(String(id))
	_check_playable(host)
	if _failures == 0:
		print("  music     %d music props wired from data (models, footprints, scale, colliders, mounts); %d playable with cues and hunter noise behind music_noise"
			% [ids.size(), MusicProps.PLAYABLE.size()])
	return _failures


func _check_prop(id: String) -> void:
	var paths: Array = PropModelCatalog.MODEL_PATHS.get(id, [])
	_expect(not paths.is_empty(), "%s has no models in PropModelCatalog.MODEL_PATHS" % id)
	_expect(paths == ContentRegistry.get_def("props", id).get("models", []), "%s models do not come from data/props/music.json" % id)
	for path in paths:
		_expect(ResourceLoader.exists(String(path)), "%s model %s is missing" % [id, path])
	_expect(RoomCatalog.FOOTPRINTS.has(id), "%s has no footprint" % id)
	_expect(StreamedRouteGenerator.TEMPLATE_PROP_SIZES.has(id), "%s has no template size" % id)
	_expect(is_equal_approx(PropModelCatalog.hunter_scale(id), 1.5), "%s is not at hunter scale 1.5" % id)
	var solid := RoomCatalog.is_solid(id)
	_expect(solid == not (id in DRESSING_NOT_SOLID), "%s solid is %s" % [id, solid])
	if solid:
		_expect(PropColliderSizes.SIZES.has(id), "%s is solid but has no collider size" % id)
	_expect(PropModelCatalog.is_wall_mounted(id) == (id in WALL), "%s wall mounting is wrong" % id)
	_expect(PropModelCatalog.is_floor_dressing(id) == (id in FLOOR_DRESSING), "%s floor dressing is wrong" % id)
	var playable := MusicProps.is_playable(id)
	_expect(PropModelCatalog.interaction_for(id) == ("music" if playable else ""), "%s interaction is \"%s\"" % [id, PropModelCatalog.interaction_for(id)])
	_expect(PropModelCatalog.is_batchable(id) == not playable, "%s batchable should be %s" % [id, not playable])


func _check_playable(host: Node) -> void:
	for type in MusicProps.PLAYABLE:
		_expect(ContentRegistry.has("props", type), "playable %s is not a music prop" % type)
		var cue := "music_" + String(MusicProps.PLAYABLE[type]["cue"])
		var stream := Sound.render_cue(cue)
		_expect(stream != null and stream.get_length() > 0.2, "%s cue %s is silent or too short" % [type, cue])
		var item := RouteInteractable3D.new()
		item.kind = RouteInteractable3D.Kind.FURNITURE
		item.configure_furniture("music")
		item.set_meta("prop_type", type)
		_expect(item.get_prompt() == MusicProps.prompt_for(type), "%s prompt is \"%s\"" % [type, item.get_prompt()])
		item.free()
	var player := FakePlayer.new()
	host.add_child(player)
	var saved := MusicProps.noise_enabled
	MusicProps.noise_enabled = true
	var level := MusicProps.play("drumKit", player)
	_expect(level > 0.0 and player.bursts.size() == 1, "music_noise on: the drum kit made no noise burst")
	MusicProps.noise_enabled = false
	_expect(MusicProps.play("drumKit", player) == 0.0 and player.bursts.size() == 1, "music_noise off: the drum kit still alerted hunters")
	MusicProps.noise_enabled = saved
	_expect(MusicProps.play("cableRun", player) == 0.0, "a dressing prop played a sound")
	player.free()
