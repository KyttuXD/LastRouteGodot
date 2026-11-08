class_name PlayerStateWire
extends RefCounted

## Wire shape of RemotePlayers' per-peer state (docs: COOP-PACKETS note, 2026-10-28).
##
## The 20 Hz unreliable sample was a 56-key Dictionary of ~2.2 KB: over ENet's ~1,392 B MTU, so it went out as two
## fragments (losing either lost the sample) and overflowed the relay tunnel's receive buffer ("Buffer full"). It is
## now split in two:
##   hot     [VERSION, seq, present_bits, bool_bits, values..., extras?] every tick, unreliable_ordered
##   profile identity / skin / inventory / admin flags, a Dictionary sent reliably only when it changes
## The receiver rebuilds the same long-key Dictionary (hot + last profile), so every reader of RemotePlayers._states
## is unchanged. Peers that have not shown they speak VERSION keep getting the old full Dictionary.
##
## Adding a field to RemotePlayers._local_state(): put its key in HOT_FIELDS (append only; bools also in BOOL_FIELDS)
## or PROFILE_FIELDS. An unlisted key still arrives (in the hot packet's extras, under its long name) but costs bytes,
## and validate_player_state_packet fails until it is classified.

const VERSION := 2
## Hard budget for the hot packet (var_to_bytes); ENet fragments unreliable packets above ~1,392 B.
const HOT_MAX_BYTES := 1000

## Order is the wire format: append only, never reorder or remove (a removed field becomes unused).
const HOT_FIELDS: Array[String] = [
	"at", "facing_y", "clip", "position", "depth", "hidden", "hiding_spot", "hiding_style", "asleep", "seat_at",
	"seat_top", "in_safe_zone", "noise", "flashlight_on", "aim_direction", "sprinting", "facing", "lamp_charge",
	"selected_item", "tool_swing_seq", "tool_swing_item", "tool_swing_hit", "selected_inventory_slot", "in_vent",
	"grab", "vent_time_in", "pesticide_active", "escape_active", "capture_immune", "game_over", "spectating",
	"visible", "exposure", "noise_meter", "temperature", "ambient", "heat_locked", "vr", "sent_ms", "syncing", "idle_s",
	"hide_slot", "duct", "stim_boost", "stim_crash",
]
## Hot fields carried as one bit when their value is a bool.
const BOOL_FIELDS: Array[String] = [
	"hidden", "asleep", "in_safe_zone", "flashlight_on", "sprinting", "tool_swing_hit", "in_vent", "pesticide_active",
	"escape_active", "capture_immune", "game_over", "spectating", "visible", "heat_locked", "syncing", "duct",
]
## Rarely-changing fields: sent reliably on change, merged into every hot sample on receipt.
const PROFILE_FIELDS: Array[String] = [
	"display_name", "account", "device", "player_hue", "player_skin", "skin", "skin_copy", "skin_slim",
	"owned_items", "item_durability", "inventory_order", "inventory_slot_durability", "inventory_free_slots",
	"inventory_capacity", "equipped_backpack", "no_target", "god_mode", "noclip",
]
## Not part of either half: the sequence has its own slot, the version tag is transport-only.
const TRANSPORT_FIELDS: Array[String] = ["seq", "wire"]


static func profile_of(state: Dictionary) -> Dictionary:
	var profile := {}
	for key in PROFILE_FIELDS:
		if state.has(key):
			profile[key] = state[key]
	return profile


static func encode_hot(state: Dictionary) -> Array:
	var present := 0
	var bools := 0
	var values := []
	for index in HOT_FIELDS.size():
		var key := HOT_FIELDS[index]
		if not state.has(key):
			continue
		var value = state[key]
		if key in BOOL_FIELDS:
			if not value is bool:
				continue   # an unexpected type rides in extras below, never as a wrong bit
			present |= 1 << index
			if value:
				bools |= 1 << index
		else:
			present |= 1 << index
			values.append(value)
	var packet: Array = [VERSION, int(state.get("seq", 0)), present, bools]
	packet.append_array(values)
	var extras := {}
	for key in state:
		var name := String(key)
		if name in TRANSPORT_FIELDS or name in PROFILE_FIELDS:
			continue
		var index := HOT_FIELDS.find(name)
		if index >= 0 and present & (1 << index):
			continue
		extras[name] = state[key]
	if not extras.is_empty():
		packet.append(extras)
	return packet


## The long-key Dictionary a hot packet stood for, or {} when it is not a valid packet of this VERSION.
static func decode_hot(packet: Array) -> Dictionary:
	if packet.size() < 4 or not packet[0] is int or int(packet[0]) != VERSION:
		return {}
	if not packet[1] is int or not packet[2] is int or not packet[3] is int:
		return {}
	var present := int(packet[2])
	var bools := int(packet[3])
	var state := {"seq": int(packet[1])}
	var cursor := 4
	for index in HOT_FIELDS.size():
		if not present & (1 << index):
			continue
		var key := HOT_FIELDS[index]
		if key in BOOL_FIELDS:
			state[key] = bool(bools & (1 << index))
			continue
		if cursor >= packet.size():
			return {}
		state[key] = packet[cursor]
		cursor += 1
	if cursor < packet.size():
		var extras = packet[cursor]
		if not extras is Dictionary or cursor + 1 != packet.size():
			return {}
		for key in extras:
			var name := String(key)
			if not state.has(name) and not name in PROFILE_FIELDS:
				state[name] = extras[key]
	return state


## Keys of `state` that are in none of the lists (they travel as extras).
static func unclassified(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in state:
		var name := String(key)
		if not name in HOT_FIELDS and not name in PROFILE_FIELDS and not name in TRANSPORT_FIELDS:
			result.append(name)
	return result


static func size_of(packet: Variant) -> int:
	return var_to_bytes(packet).size()
