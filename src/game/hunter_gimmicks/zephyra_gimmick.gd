class_name ZephyraGimmick
extends HunterGimmick

## Zephyra's coin exchange (hunterAbilities.zephyra.merchant). Ported from
## zephyra.js's prepareMerchant/useMerchant/chooseMerchantOffer.
##
## She is not a hunter in any real sense: on first activation she teleports
## once to whichever room sits closest to the facility's center and never
## moves or reacts to the player again -- immune to capture (see
## HunterGimmick.immune_to_capture, a new hook this hunter needed, since the
## player stands right next to her on every single trade). Walking within
## ZEPHYRA_SHOP_RANGE and pressing [E] opens her menu; a digit key 1-4
## chooses an offer while it's open (see PlayerController3D's
## shop_resolver/_unhandled_input -- this port has no hotbar to borrow keys
## from the way the original does, so raw digit presses are used directly).
##
## Nightmare's 1-in-10 instant-death roll on opening her shop is NOT ported:
## no difficulty selection exists in this port, the same reasoning Ilyra's
## Nightmare-only zero pounce delay and Loxelle's Nightmare regen split use.

const OFFERS := [
	{"id": "cool", "label": "COOL"},
	{"id": "warm", "label": "WARM"},
	{"id": "repair", "label": "REPAIR"},
	{"id": "pesticide", "label": "PESTICIDE"},
]

var shop_open := false
var _settled := false


func after_perception(brain: HunterBrain, _delta: float, target: Dictionary, generator: FacilityGenerator) -> void:
	if not _settled:
		_settle(brain, generator)
		_settled = true

	# Overrides whatever ordinary perception just decided -- she never reacts
	# to the player at all, the same forced-inert shape Verrine's non-network
	# branch uses. idle_timer is reset alongside state for the same reason:
	# left alone it counts down inside THIS SAME update() call (movement runs
	# right after this hook) and flips her to WANDER the moment it expires --
	# harmless to her actual position since holds_position() still freezes
	# movement, but not the permanently-idle state the original's `state:
	# "idle"` assignment actually means.
	brain.state = HunterBrain.State.IDLE
	brain.idle_timer = 999.0
	brain.has_last_known = false
	brain.lost_sight_timer = 0.0

	# Walking out of range closes the shop from underneath any open menu.
	var player_position: Vector2 = target["position"]
	if shop_open and player_position.distance_to(brain.position) > GameConfig.ZEPHYRA_SHOP_RANGE + 0.25:
		shop_open = false


func holds_position() -> bool:
	return true


func immune_to_capture() -> bool:
	return true


func in_range(player_position: Vector2, brain_position: Vector2) -> bool:
	return player_position.distance_to(brain_position) <= GameConfig.ZEPHYRA_SHOP_RANGE


func offer_menu_text() -> String:
	var parts: Array[String] = []
	for i in OFFERS.size():
		var offer: Dictionary = OFFERS[i]
		parts.append("[%d] %s -%d" % [i + 1, String(offer["label"]), _cost(String(offer["id"]))])
	return "ZYTTU SHOP // %s // WALK AWAY TO LEAVE" % " // ".join(parts)


## Opens (or re-toasts) the menu. `brain_position` is Zephyra's own spot on
## the floor, since the gimmick has no HunterBrain reference of its own.
func open_shop(player_position: Vector2, brain_position: Vector2) -> String:
	if not in_range(player_position, brain_position):
		return ""
	shop_open = true
	return offer_menu_text()


func choose_offer(index: int, player: PlayerController3D, facility_view: FacilityView3D) -> String:
	if not shop_open:
		return ""
	if index < 1 or index > OFFERS.size():
		return ""
	var offer: Dictionary = OFFERS[index - 1]
	var offer_id := String(offer["id"])
	var cost := _cost(offer_id)
	if GameState.coins < cost:
		return "ZYTTU // NOT ENOUGH COINS FOR %s (%d)" % [String(offer["label"]), cost]

	GameState.coins -= cost
	match offer_id:
		"cool":
			player.meters.temperature = clampf(
				player.meters.temperature - GameConfig.ZEPHYRA_TEMPERATURE_STEP, 0.0, 100.0)
		"warm":
			player.meters.temperature = clampf(
				player.meters.temperature + GameConfig.ZEPHYRA_TEMPERATURE_STEP, 0.0, 100.0)
		"repair":
			var relay := facility_view.find_sabotaged_relay()
			if relay:
				relay.set_sabotaged(false)
			else:
				player.restore_lamp(GameConfig.ZEPHYRA_LAMP_REPAIR)
		"pesticide":
			player.pesticide_timer = maxf(player.pesticide_timer, GameConfig.ZEPHYRA_PESTICIDE_SECONDS)
	shop_open = false
	return "ZYTTU TRADE COMPLETE // %s // -%d COINS" % [String(offer["label"]), cost]


func _cost(offer_id: String) -> int:
	match offer_id:
		"cool":
			return GameConfig.ZEPHYRA_COOL_COST
		"warm":
			return GameConfig.ZEPHYRA_WARM_COST
		"repair":
			return GameConfig.ZEPHYRA_REPAIR_COST
		"pesticide":
			return GameConfig.ZEPHYRA_PESTICIDE_COST
	return 0


func _settle(brain: HunterBrain, generator: FacilityGenerator) -> void:
	if generator.rooms.is_empty():
		return
	var facility_center := Vector2(generator.cols / 2.0, generator.rows / 2.0)
	var best: Dictionary = generator.rooms[0]
	var best_distance := INF
	for room in generator.rooms:
		var room_center: Vector2i = room["center"]
		var distance := Vector2(room_center).distance_to(facility_center)
		if distance < best_distance:
			best_distance = distance
			best = room
	var center: Vector2i = best["center"]
	var open := generator.nearest_open_position(center.x + 0.5, center.y + 0.5, brain.radius)
	brain.position = Vector2(open["x"], open["y"]) if not open.is_empty() else Vector2(center) + Vector2(0.5, 0.5)
