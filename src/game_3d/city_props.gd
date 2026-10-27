class_name CityProps
extends RefCounted

## Street furniture that belongs to the City only (the shared prop families stay in the route's catalog): plaza lights,
## banners, market stalls, a newsstand, phone booths and hydrants. Blocky boxes from the City atlas, drawn into the chunk's
## CitySurface like the rest of the street furniture. CityLayout.DECOR_COLLIDERS / DECOR_VISIBLE carry their footprints.

const TYPES := ["plaza_light", "banner", "market_stall", "newsstand", "phone_booth", "hydrant"]
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
		_:
			pass
