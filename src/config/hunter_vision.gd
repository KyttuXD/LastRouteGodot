class_name HunterVision
extends RefCounted

## Per-hunter sight multipliers for the City's DAYTIME mode, in one table so they can be tuned in one place.
##
##   night   multiplies the hunter's night sight range (the normal flashlight / unlit rules). 1.0 = unchanged.
##   day     multiplies the hunter's daytime sight range outdoors (GameConfig.DAYLIGHT_SIGHT_SCALE x her sight profile).
##   notice  seconds of continuous daytime sight before she commits to a chase (0 = instantly, like at night).
##
## Daytime only changes outdoor sight; inside buildings the night rules (and `night`) apply, so interiors stay dim and
## dangerous. Hunters not listed use DEFAULT. Last Route never reads this table: its brains have day_mode off.

const DEFAULT := {"night": 1.0, "day": 1.0, "notice": 0.0}

const TABLE := {
	# Light-sensitive: the daytime glare shortens her range a lot and she is slow to commit; at night she is sharper.
	"nyxie": {"night": 1.2, "day": 0.45, "notice": 1.6},
	# Daylight hunters: they see further and commit at once in the sun, and are a little blunter in the dark.
	"kathy": {"night": 0.95, "day": 1.25, "notice": 0.0},
	"solyth": {"night": 0.9, "day": 1.3, "notice": 0.0},
	"xivvy": {"night": 0.95, "day": 1.15, "notice": 0.0},
	"ilyra": {"night": 1.0, "day": 1.1, "notice": 0.0},
	"thessine": {"night": 1.0, "day": 1.1, "notice": 0.0},
	"ravelle": {"night": 1.0, "day": 1.1, "notice": 0.0},
	# A little glare-shy: slower to commit in the sun.
	"ceryth": {"night": 1.05, "day": 0.9, "notice": 0.5},
	"umbriel": {"night": 1.1, "day": 0.85, "notice": 0.6},
	"mavrine": {"night": 1.0, "day": 0.95, "notice": 0.3},
	# The Void hunters belong to the dark: stronger at night, weaker and slower by day.
	"void_black": {"night": 1.15, "day": 0.7, "notice": 0.8},
	"void_blue": {"night": 1.15, "day": 0.7, "notice": 0.8},
	"void_brown": {"night": 1.15, "day": 0.7, "notice": 0.8},
	"void_cyan": {"night": 1.15, "day": 0.7, "notice": 0.8},
}


static func entry(hunter_id: String) -> Dictionary:
	var merged := DEFAULT.duplicate()
	var own: Dictionary = TABLE.get(hunter_id, {})
	for key in own:
		merged[key] = own[key]
	return merged


static func night_multiplier(hunter_id: String) -> float:
	return float(entry(hunter_id)["night"])


static func day_multiplier(hunter_id: String) -> float:
	return float(entry(hunter_id)["day"])


static func notice_seconds(hunter_id: String) -> float:
	return float(entry(hunter_id)["notice"])
