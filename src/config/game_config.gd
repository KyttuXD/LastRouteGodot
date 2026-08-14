class_name GameConfig
extends RefCounted

## Shared values for the first migration slice. Replace content-heavy dictionaries
## with typed Resources as canonical data is moved from the browser project.

const INTERNAL_SIZE := Vector2i(480, 270)
const TILE_SIZE := 16

const PLAYER_WALK_SPEED := 64.0
const PLAYER_SPRINT_SPEED := 100.0
const PLAYER_CROUCH_SPEED := 36.0

const PLAYER_BOUNDS := Rect2(8.0, 8.0, 464.0, 254.0)

const MAX_STAMINA := 100.0
const STAMINA_SPRINT_DRAIN := 32.0
const STAMINA_RECOVERY := 21.0
const STAMINA_RECOVERY_DELAY := 0.65
const STAMINA_EXHAUSTED_RECOVERY := 25.0

const MAX_LAMP_CHARGE := 100.0
const LAMP_IDLE_DRAIN := 0.8
const LAMP_SPRINT_DRAIN := 0.35
const BATTERY_RECHARGE := 25.0

const INTERACTION_RANGE := 26.0
