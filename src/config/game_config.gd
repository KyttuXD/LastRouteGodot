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

## Hunter/perception/capture tuning, ported from the original's TUNING block
## and hunter-ai.js constants (game-config.js, hunter-ai.js). Unlike the
## pixel-space player movement constants above, everything here operates in
## the SAME grid-cell units as facility_generator.gd (1 unit = 1 cell) —
## hunter_brain.gd is presentation-agnostic and never touches pixels or
## meters directly; each presentation layer converts at its own boundary.
const PLAYER_RADIUS := 0.2
const HUNTER_RADIUS := 0.22
const MOVEMENT_STEP := 0.11

const HUNTER_SEARCH_TIME := 3.2
const HUNTER_REPATH_CHASE := 0.3
const HUNTER_REPATH_WANDER := 1.6
const HUNTER_STAMINA_MAX := 100.0
const HUNTER_STAMINA_CHASE_DRAIN := 14.0
const HUNTER_STAMINA_REGEN := 11.0
const HUNTER_STAMINA_RECOVER := 40.0
const HUNTER_WINDED_SPEED_SCALE := 0.62
const HUNTER_SPAWN_DISTANCE_MIN := 12.0
const HUNTER_LOST_SIGHT_GRACE := 0.45
const HUNTER_SENSE_INTERVAL := 0.14

## Reduces a hunter's effective sight range while the player's own flashlight
## is off — staying dark is a real stealth advantage (ui-controller.js/
## hunter-ai.js's unlitSightScale). Room-power (unpoweredSightScale) isn't
## ported — no breaker system exists yet.
const UNLIT_SIGHT_SCALE := 0.5

## Player noise emitted per frame by movement mode, consumed by hunter hearing.
const NOISE_CROUCH := 0.9
const NOISE_WALK := 4.2
const NOISE_SPRINT := 10.5
## Outer straight-line reject distance is HEARING_OUTER_SCALE * noise; the
## inner (real) hearing radius is walking distance <= noise, via pathfind().
const HEARING_OUTER_SCALE := 1.45

## Dovelle — the zero-gimmick baseline hunter (HUNTER_ABILITIES.dovelle = {}
## in the original). Consumed via HunterRoster, not referenced directly by
## hunter_brain.gd (see src/config/hunter_roster.gd).
const DOVELLE_BASE_SPEED := 0.8
const DOVELLE_CHASE_SPEED := 3.55
const DOVELLE_CHASE_PROGRESSION_SCALE := 0.18
const DOVELLE_SIGHT_RANGE := 8.0
const DOVELLE_HEARING_SCALE := 1.0

## Quirith — flashlight tracker (hunterAbilities.quirith.flashlightTracker in
## the original). Keeping the flashlight on for QUIRITH_FLASHLIGHT_LOCK_SECONDS
## straight earns a permanent chase lock; every flashlight on/off flick after
## that ramps her chase speed further, capped at QUIRITH_MAX_SPEED_SCALE after
## QUIRITH_SPEED_RAMP_ACTIVATIONS flicks. Nightmare's shorter 5s threshold
## isn't ported — no difficulty selection exists yet, matching every other
## Standard-only tuning value in this file.
const QUIRITH_BASE_SPEED := 0.81
const QUIRITH_CHASE_SPEED := 3.5
const QUIRITH_CHASE_PROGRESSION_SCALE := 0.17
const QUIRITH_SIGHT_RANGE := 8.1
const QUIRITH_HEARING_SCALE := 0.85
const QUIRITH_FLASHLIGHT_LOCK_SECONDS := 8.0
const QUIRITH_MAX_SPEED_SCALE := 1.45
const QUIRITH_SPEED_RAMP_ACTIVATIONS := 10

## Eirys — running-data ratchet (hunterAbilities.eirys.runningData). Time spent
## actually sprinting outside a safe zone accumulates and NEVER decays; at
## EIRYS_SECONDS_TO_FULL she locks into a permanent blind chase. Her
## `breachesHiding` flag isn't ported — hiding spots don't exist yet, so it
## would be a no-op either way.
const EIRYS_BASE_SPEED := 0.82
const EIRYS_CHASE_SPEED := 3.58
const EIRYS_CHASE_PROGRESSION_SCALE := 0.18
const EIRYS_SIGHT_RANGE := 8.1
const EIRYS_HEARING_SCALE := 1.05
const EIRYS_SECONDS_TO_FULL := 50.0

## Xivvy — chase accelerator (hunterAbilities.xivvy.chaseAccelerator). Locks on
## by pure proximity (no sight/hearing check), then her chase speed ramps the
## longer the chase runs. XIVVY_CLOSE_SCALE is the original's
## `.5 + exposure / 200` evaluated at exposure 0 — no exposure meter exists
## yet, so this is that formula's genuine rest value, not an invented number.
## Her `flight` flag isn't ported: nothing blocks movement that walking doesn't
## already block, so it's a no-op here.
const XIVVY_BASE_SPEED := 0.97
const XIVVY_CHASE_SPEED := 4.35
const XIVVY_CHASE_PROGRESSION_SCALE := 0.12
const XIVVY_SIGHT_RANGE := 6.72
const XIVVY_HEARING_SCALE := 0.84
const XIVVY_CLOSE_LOCK_RADIUS := 1.5
const XIVVY_CLOSE_SCALE := 0.5
const XIVVY_SPEED_PER_SECOND := 0.035
const XIVVY_MAX_SPEED_SCALE := 1.8

## Kathy — search beam (hunterAbilities.kathy.beamDetection). A cone along her
## own facing that spots the player well past ordinary sight range. Her second
## ability (affectedSummon) is deliberately not ported: it requires other
## already-active route hunters, which is impossible at one hunter per floor
## in both codebases, so it is permanently inert rather than skipped.
const KATHY_BASE_SPEED := 0.82
const KATHY_CHASE_SPEED := 4.15
const KATHY_CHASE_PROGRESSION_SCALE := 0.2
const KATHY_SIGHT_RANGE := 8.2
const KATHY_HEARING_SCALE := 1.0
const KATHY_BEAM_RANGE := 11.5
const KATHY_BEAM_HALF_ANGLE := 0.24

## Ravelle — tripwire trapper (hunterAbilities.ravelle.tripwireTrapper). Two
## invisible wires on doorway-shaped cells; crossing one locks a chase and
## PERMANENTLY adds to her speed. Her chase speed starts below the roster floor
## on purpose — the per-trigger bonus is what carries her past it. Her fake
## doorway is not ported: only the original's renderer reads it, no gameplay
## logic does.
const RAVELLE_BASE_SPEED := 0.81
const RAVELLE_CHASE_SPEED := 3.15
const RAVELLE_CHASE_PROGRESSION_SCALE := 0.18
const RAVELLE_SIGHT_RANGE := 7.7
const RAVELLE_HEARING_SCALE := 1.0
const RAVELLE_TRIPWIRE_REFRESH := 30.0
const RAVELLE_TRIPWIRE_COUNT := 2
const RAVELLE_TRIGGER_RADIUS := 0.8
const RAVELLE_SPEED_PER_TRIGGER := 0.08

## Mavrine — lattice mark (hunterAbilities.mavrine.latticeMark). Cycles
## cooldown -> survey (holds still) -> project (an armed frame somewhere on the
## floor) -> ping, pursuing if the player crosses the frame.
const MAVRINE_BASE_SPEED := 0.8
const MAVRINE_CHASE_SPEED := 3.5
const MAVRINE_CHASE_PROGRESSION_SCALE := 0.17
const MAVRINE_SIGHT_RANGE := 8.2
const MAVRINE_HEARING_SCALE := 0.95
const MAVRINE_SURVEY_DELAY := 6.2
const MAVRINE_SURVEY_DURATION := 0.9
const MAVRINE_PROJECTION_DURATION := 6.0
const MAVRINE_COOLDOWN_DURATION := 4.2
const MAVRINE_PING_DURATION := 0.45
const MAVRINE_MARK_TRIGGER_RADIUS := 0.62

## Umbriel — shapeshifter (hunterAbilities.umbriel.shapeshifter). Swaps her
## apparent identity every UMBRIEL_DISGUISE_INTERVAL seconds. On Standard this
## is purely cosmetic; attribute-copying is a Nightmare-only behaviour and no
## difficulty selection exists, so only the disguise is ported. Kathy is
## excluded from the pool, as in the original.
const UMBRIEL_BASE_SPEED := 0.82
const UMBRIEL_CHASE_SPEED := 3.46
const UMBRIEL_CHASE_PROGRESSION_SCALE := 0.18
const UMBRIEL_SIGHT_RANGE := 8.5
const UMBRIEL_HEARING_SCALE := 0.86
const UMBRIEL_DISGUISE_INTERVAL := 30.0
const UMBRIEL_DISGUISE_EXCLUDED := ["kathy"]

## hunterMovementSpeed()'s relay/depth chase-speed progression terms.
const HUNTER_RELAY_SPEED_BONUS := 0.1
const HUNTER_DEPTH_SPEED_BONUS_PER_LEVEL := 0.055
const HUNTER_DEPTH_SPEED_BONUS_MAX := 0.55

## Capture/escape struggle (hunter-ai.js's ESCAPE_* / triggerGameOver).
## captureDistance is a difficulty multiplier (standard = 1.0; no difficulty
## selection exists yet, so it's applied as a constant 1.0 here).
const CAPTURE_DISTANCE_SCALE := 1.0
const ESCAPE_DURATION := 3.2
const ESCAPE_PRESSES := 6
const ESCAPE_COOLDOWN := 16.0
const ESCAPE_GRACE := 1.5
const ESCAPE_STUN_DURATION := 3.0
const RESPAWN_STUN_DURATION := 4.0
const RESPAWN_LIVES_STANDARD := 2

## Relay index at which the (single, seeded) ordinary hunter activates —
## ROUTE_HUNTER_ACTIVATION_SPACING from the original: activationRelay =
## min((index+1)*spacing, relayCount), index 0 for the first/only hunter.
const HUNTER_ACTIVATION_SPACING := 3
