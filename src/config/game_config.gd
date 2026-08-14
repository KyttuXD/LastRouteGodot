class_name GameConfig
extends RefCounted

## Shared values for the first migration slice. Replace content-heavy dictionaries
## with typed Resources as canonical data is moved from the browser project.

const INTERNAL_SIZE := Vector2i(480, 270)
const TILE_SIZE := 16

const PLAYER_WALK_SPEED := 64.0
const PLAYER_SPRINT_SPEED := 100.0
const PLAYER_CROUCH_SPEED := 36.0

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

## TUNING.safeRadius (2.5 tiles) from the original's game-config.js, converted
## to pixels — how close the player must be to a safe zone for the HUD's
## battery meter to read as "resting" (matches ui-controller.js's inSafeZone
## battery-color branch).
const SAFE_ZONE_RADIUS := 2.5 * TILE_SIZE

## Facility generation defaults, mirroring LastRoute's Standard MAP_SCALE_PROFILES
## entry (src/config/game-config.js) and the safeZoneAtSpawn/safeZoneCount
## a normal (non-Endless) Last Route floor requests in game.js's buildLevel().
const FACILITY_COLS := 45
const FACILITY_ROWS := 45
const FACILITY_RELAY_COUNT := 5
const FACILITY_BATTERY_COUNT := 7
const FACILITY_ROOM_COUNT := 9
const FACILITY_SAFE_ZONE_COUNT := 1
const FACILITY_SAFE_ZONE_AT_SPAWN := true
