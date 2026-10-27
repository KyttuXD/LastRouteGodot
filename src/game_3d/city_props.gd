class_name CityProps
extends RefCounted

## Street furniture that belongs to the City only (the shared prop families stay in the route's catalog): plaza lights,
## banners, market stalls, a newsstand, phone booths and hydrants. Blocky boxes from the City atlas, drawn into the chunk's
## CitySurface like the rest of the street furniture. CityLayout.DECOR_COLLIDERS / DECOR_VISIBLE carry their footprints.

const TYPES := ["plaza_light", "banner", "market_stall", "newsstand", "phone_booth", "hydrant", "mailbox", "silo", "tractor", "hay_bale", "water_pump",
	"traffic_light", "bus_stop", "car_a", "car_b", "utility_pole", "billboard", "street_sign"]
const PLAZA_COLOR := Color(0.34, 0.92, 0.9)


static func handles(type: String) -> bool:
	return TYPES.has(type)


## Draws one prop at the cell's centre (cx, cz in chunk-local metres). Lights go into `lamps` (LampField entries).
static func add(type: String, surface: CitySurface, root: Node3D, lamps: Array, cx: float, cz: float, yaw: float) -> void:
	var pole := CityAtlas.tile("pole")
	var wide_along_x := absf(sin(yaw)) < .5
	match type:
		"plaza_light":
			surface.box(Vector3(cx - .45, 0, cz - .45), Vector3(.9, .35, .9), CityAtlas.tile("stone_dark"))
			surface.box(Vector3(cx - .09, .35, cz - .09), Vector3(.18, 4.0, .18), pole)
			surface.box(Vector3(cx - .24, 4.3, cz - .24), Vector3(.48, .3, .48), CityAtlas.tile("cyan_lamp"))
			surface.box(Vector3(cx - .3, 4.6, cz - .3), Vector3(.6, .06, .6), pole)
			lamps.append([root.position + Vector3(cx, 4.2, cz), PLAZA_COLOR, 0.0 if RoomState.is_day() else 1.3, 0, 10.0])
		"banner":
			var cloth := CityAtlas.tile("awning_red" if int(cx + cz) % 2 == 0 else "awning_teal")
			surface.box(Vector3(cx - .06, 0, cz - .06), Vector3(.12, 4.2, .12), pole)
			if wide_along_x:
				surface.box(Vector3(cx - .5, 1.8, cz - .02), Vector3(1.0, 2.2, .04), cloth)
				surface.box(Vector3(cx - .55, 4.0, cz - .05), Vector3(1.1, .08, .1), pole)
			else:
				surface.box(Vector3(cx - .02, 1.8, cz - .5), Vector3(.04, 2.2, 1.0), cloth)
				surface.box(Vector3(cx - .05, 4.0, cz - .55), Vector3(.1, .08, 1.1), pole)
		"market_stall":
			var wood := CityAtlas.tile("wood_bench")
			var awning := CityAtlas.tile("awning_teal" if int(cx * 3.0 + cz) % 2 == 0 else "awning_red")
			surface.box(Vector3(cx - .45, 0, cz - .45), Vector3(.9, 1.0, .9), wood, CityAtlas.tile("planter"))
			for corner in [Vector2(-.88, -.88), Vector2(.8, -.88), Vector2(-.88, .8), Vector2(.8, .8)]:
				surface.box(Vector3(cx + corner.x, 0, cz + corner.y), Vector3(.08, 2.4, .08), pole)
			surface.box(Vector3(cx - .95, 2.4, cz - .95), Vector3(1.9, .14, 1.9), awning, awning)
		"newsstand":
			surface.box(Vector3(cx - .45, 0, cz - .45), Vector3(.9, 1.1, .9), CityAtlas.tile("kiosk_wall"), CityAtlas.tile("kiosk_roof"))
			surface.box(Vector3(cx - .48, 1.1, cz - .48), Vector3(.96, .9, .96), CityAtlas.tile("plaster"))
			surface.box(Vector3(cx - .5, 2.0, cz - .5), Vector3(1.0, .25, 1.0), CityAtlas.tile("kiosk_roof"))
			surface.box(Vector3(cx - .4, 2.25, cz - .4), Vector3(.8, .3, .8), CityAtlas.tile("neon_sign"))
		"phone_booth":
			surface.box(Vector3(cx - .4, 0, cz - .4), Vector3(.8, 2.1, .8), CityAtlas.tile("fire_escape"), CityAtlas.tile("stone_dark"))
			surface.box(Vector3(cx - .3, .9, cz - .41), Vector3(.6, .8, .02), CityAtlas.tile("win_cyan_top"))
			surface.box(Vector3(cx - .42, 2.1, cz - .42), Vector3(.84, .16, .84), CityAtlas.tile("cyan_lamp"))
			lamps.append([root.position + Vector3(cx, 2.4, cz), PLAZA_COLOR, 0.0 if RoomState.is_day() else .6, 0, 4.5])
		"hydrant":
			surface.box(Vector3(cx - .13, 0, cz - .13), Vector3(.26, .5, .26), CityAtlas.tile("awning_red"))
			surface.box(Vector3(cx - .17, .5, cz - .17), Vector3(.34, .12, .34), CityAtlas.tile("awning_red"))
			surface.box(Vector3(cx - .2, .28, cz - .06), Vector3(.4, .1, .12), CityAtlas.tile("awning_red"))
		"mailbox":
			surface.box(Vector3(cx - .05, 0, cz - .05), Vector3(.1, .9, .1), pole)
			surface.box(Vector3(cx - .2, .9, cz - .15), Vector3(.4, .3, .3), CityAtlas.tile("awning_red"), CityAtlas.tile("stone_dark"))
		"silo":
			surface.box(Vector3(cx - .47, 0, cz - .47), Vector3(.94, 7.0, .94), CityAtlas.tile("silo"), CityAtlas.tile("stone_dark"))
			surface.box(Vector3(cx - .3, 7.0, cz - .3), Vector3(.6, .6, .6), CityAtlas.tile("silo"), CityAtlas.tile("stone_dark"))
			surface.box(Vector3(cx - .1, 7.6, cz - .1), Vector3(.2, .6, .2), pole)
		"tractor":
			var red := CityAtlas.tile("barn_red")
			surface.box(Vector3(cx - .45, .35, cz - .45), Vector3(.9, .5, .9), red, red)
			surface.box(Vector3(cx - .3, .85, cz - .1), Vector3(.6, .7, .5), CityAtlas.tile("fire_escape"), red)
			surface.box(Vector3(cx - .47, 0, cz - .47), Vector3(.2, .55, .2), pole)
			surface.box(Vector3(cx + .27, 0, cz - .47), Vector3(.2, .55, .2), pole)
			surface.box(Vector3(cx - .47, 0, cz + .22), Vector3(.25, .7, .25), pole)
			surface.box(Vector3(cx + .22, 0, cz + .22), Vector3(.25, .7, .25), pole)
			surface.box(Vector3(cx + .3, 1.55, cz - .3), Vector3(.08, .35, .08), pole)
		"hay_bale":
			surface.box(Vector3(cx - .45, 0, cz - .45), Vector3(.9, .9, .9), CityAtlas.tile("crop_b"), CityAtlas.tile("crop_b"))
		"water_pump":
			surface.box(Vector3(cx - .25, 0, cz - .25), Vector3(.5, .8, .5), CityAtlas.tile("stone_dark"))
			surface.box(Vector3(cx - .08, .8, cz - .08), Vector3(.16, .5, .16), pole)
			surface.box(Vector3(cx - .3, 1.2, cz - .05), Vector3(.6, .08, .1), pole)
		"traffic_light":
			surface.box(Vector3(cx - .1, 0, cz - .1), Vector3(.2, 3.0, .2), pole)
			surface.box(Vector3(cx - .18, 3.0, cz - .18), Vector3(.36, .8, .36), CityAtlas.tile("fire_escape"), pole)
			surface.box(Vector3(cx - .1, 3.55, cz - .2), Vector3(.2, .16, .04), CityAtlas.tile("awning_red"))
			surface.box(Vector3(cx - .1, 3.1, cz - .2), Vector3(.2, .16, .04), CityAtlas.tile("cyan_lamp"))
		"street_sign":
			surface.box(Vector3(cx - .05, 0, cz - .05), Vector3(.1, 2.2, .1), pole)
			surface.box(Vector3(cx - .3, 2.25, cz - .03), Vector3(.6, .2, .06), CityAtlas.tile("awning_teal"))
			surface.box(Vector3(cx - .03, 2.5, cz - .3), Vector3(.06, .2, .6), CityAtlas.tile("awning_teal"))
		"bus_stop":
			surface.box(Vector3(cx - .45, 0, cz - .45), Vector3(.06, 2.3, .06), pole)
			surface.box(Vector3(cx + .39, 0, cz - .45), Vector3(.06, 2.3, .06), pole)
			surface.box(Vector3(cx - .48, 2.3, cz - .48), Vector3(.96, .1, .96), CityAtlas.tile("kiosk_roof"))
			surface.box(Vector3(cx - .45, .4, cz - .45), Vector3(.9, .1, .3), CityAtlas.tile("wood_bench"))
			surface.box(Vector3(cx - .45, .6, cz - .47), Vector3(.9, 1.4, .04), CityAtlas.tile("win_cyan_top"))
		"car_a", "car_b":
			# half a parked car per cell (front / back), so the two halves line up into one 2 m car
			var paint := CityAtlas.tile("awning_red" if int(cx * 7.0 + cz) % 3 == 0 else ("awning_teal" if int(cx + cz) % 2 == 0 else "stone_dark"))
			surface.box(Vector3(cx - .46, .25, cz - .46), Vector3(.92, .55, .92), paint, paint)
			if type == "car_a":
				surface.box(Vector3(cx - .4, .8, cz - .4), Vector3(.8, .45, .8), CityAtlas.tile("win_dark_top"), paint)
			for corner in [Vector2(-.42, -.3), Vector2(.3, -.3), Vector2(-.42, .18), Vector2(.3, .18)]:
				surface.box(Vector3(cx + corner.x, 0, cz + corner.y), Vector3(.12, .3, .12), pole)
		"utility_pole":
			surface.box(Vector3(cx - .12, 0, cz - .12), Vector3(.24, 6.4, .24), CityAtlas.tile("trunk"))
			if wide_along_x:
				surface.box(Vector3(cx - .6, 6.2, cz - .06), Vector3(1.2, .12, .12), CityAtlas.tile("trunk"))
			else:
				surface.box(Vector3(cx - .06, 6.2, cz - .6), Vector3(.12, .12, 1.2), CityAtlas.tile("trunk"))
		"billboard":
			surface.box(Vector3(cx - .1, 0, cz - .1), Vector3(.2, 3.4, .2), pole)
			if wide_along_x:
				surface.box(Vector3(cx - 1.5, 3.4, cz - .1), Vector3(3.0, 3.0, .2), CityAtlas.tile("neon_sign"), pole)
			else:
				surface.box(Vector3(cx - .1, 3.4, cz - 1.5), Vector3(.2, 3.0, 3.0), CityAtlas.tile("neon_sign"), pole)
		_:
			pass
