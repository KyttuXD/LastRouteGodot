class_name NightWatchOpenAirOffice
extends NightWatchOfficeBase

## Open Air's office (the OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md): `watch_post`, the outdoor guard post of the three watches. `watch` (0 ROOFTOP,
## 1 BUS STOP, 2 CAMPFIRE) is set before the office enters the tree and picks the set NightWatchOpenAirWorld builds (the stair-door / hatch roof, the
## shelter beside the road, the clearing round the fire); the spec follows it (footprint, spawn, entrances at the hunters' last waypoints, stations,
## mood). No monitor. `make_spec()` without an argument is the rooftop's (the registry validator's view).

var watch := 0
var world: NightWatchOpenAirWorld


func _make_spec() -> NightWatchOfficeSpec:
	return make_spec()


static func make_spec(watch_index := 0) -> NightWatchOfficeSpec:
	var base := {"id": "watch_post", "title": "Watch post", "mode_ids": ["extra"], "has_monitor": false,
		"references": {"2d_screenshot": "docs/night_watch_offices/watch_post_2d.png"}}
	match watch_index:
		1:
			base.merge({
				"footprint": Rect2(-13.0, 0.4, 26.0, 6.2), "spawn": Vector3(0.0, 0.0, 1.2),
				"entrances": [{"id": "road", "kind": "opening", "position": Vector3(-3.2, 0.0, -1.3), "outward": Vector3(0, 0, -1), "sim_room": "W4", "blockable": false}],
				"required_stations": ["lamp", "can0", "can1", "can2"],
				"mood": {"kind": "night_outdoor", "ambient": Color(0.3, 0.34, 0.5), "lamp": Color(1.0, 0.6, 0.3), "accent": Color(0.5, 0.65, 0.95)},
				"tone_cue": "breath", "controls": ["nw_lamp"],
			}, true)
		2:
			base.merge({
				"footprint": Rect2(-9.5, -9.0, 19.0, 17.0), "spawn": Vector3(1.4, 0.0, 2.6),
				"entrances": [
					{"id": "treesL", "kind": "opening", "position": Vector3(-5.2, 0.0, -0.8), "outward": Vector3(-0.9, 0, -0.4), "sim_room": "V0", "blockable": false},
					{"id": "treesR", "kind": "opening", "position": Vector3(5.2, 0.0, -0.8), "outward": Vector3(0.9, 0, -0.4), "sim_room": "Q0", "blockable": false},
					{"id": "logs", "kind": "opening", "position": Vector3(2.6, 0.0, -2.4), "outward": Vector3(0, 0, -1), "sim_room": "Y0", "blockable": false},
				],
				"required_stations": ["fire", "wood", "torchL", "torchR", "tent"],
				"mood": {"kind": "night_outdoor", "ambient": Color(0.3, 0.34, 0.5), "lamp": Color(1.0, 0.62, 0.3), "accent": Color(0.96, 0.72, 0.28)},
				"tone_cue": "breath", "controls": ["nw_light_left", "nw_light_right", "nw_lamp", "nw_oa_relight", "nw_oa_tent"],
			}, true)
		_:
			base.merge({
				"footprint": Rect2(-6.0, -4.5, 12.0, 9.0), "spawn": Vector3(0.0, 0.0, 1.6),
				"entrances": [
					{"id": "stairdoor", "kind": "door_slab", "position": Vector3(-7.5, 0.0, 0.0), "outward": Vector3(-1, 0, 0), "sim_room": "L0", "blockable": true},
					{"id": "hatch", "kind": "hatch", "position": Vector3(7.5, 0.0, 0.0), "outward": Vector3(1, 0, 0), "sim_room": "R0", "blockable": true},
				],
				"required_stations": ["barL", "barR", "torchL", "torchR", "lantern"],
				"mood": {"kind": "night_outdoor", "ambient": Color(0.3, 0.34, 0.5), "lamp": Color(1.0, 0.8, 0.5), "accent": Color(0.96, 0.72, 0.28)},
				"tone_cue": "breath", "controls": ["nw_door_left", "nw_door_right", "nw_light_left", "nw_light_right", "nw_oa_relight"],
			}, true)
	return NightWatchOfficeSpec.make(base)


func build() -> void:
	spec = make_spec(watch)
	world = NightWatchOpenAirWorld.new()
	world.name = "World"
	add_child(world)
	world.build(watch)
	props = world.props
	stations = world.stations
