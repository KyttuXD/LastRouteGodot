class_name GameConfig
extends RefCounted

## Shared values for the first migration slice. Replace content-heavy dictionaries
## with typed Resources as canonical data is moved from the browser project.

const INTERNAL_SIZE := Vector2i(480, 270)
const TILE_SIZE := 16

const PLAYER_WALK_SPEED := 64.0
const PLAYER_SPRINT_SPEED := 100.0
const PLAYER_CROUCH_SPEED := 36.0

## Difficulty profiles are multipliers over the Standard baseline, matching
## the original web build's difficulty/core.js contract. Hard is the exact
## midpoint between Standard and Nightmare; Nightmare (selectable) is the original's top profile. A completed Zellia trade rolls
## ZELLIA_DEATH_CHANCE (relaxed 2%, standard 5%, hard 7.5%, nightmare 12%).
const DIFFICULTY_PROFILES := {
	"relaxed": {
		"player_speed": 1.08, "crouch_speed": 1.06, "sprint_speed": 1.08,
		"lamp_drain": 0.70, "sprint_drain": 0.80,
		"hunter_speed": 0.82, "hunter_sight": 0.86, "hunter_hearing": 0.86,
		"capture_distance": 0.90,
		"search_time": 3.2, "lost_sight_grace": 3.0, "stamina_drain": 14.0, "hide_tell": 1.6, "hide_trail": 3.0, "hide_cooldown": 20.0, "hide_random": 0.0,
		"taser_stun": 2.8, "taser_slow_factor": 0.5, "taser_slow_seconds": 3.0, "taser_cooldown": 8.0, "escape_stun": 3.0, "crowbar_stun": 4.5, "axe_stun": 6.0, "spawn_distance": 12.0, "emote_chase_scale": 1.0, "emote_spot_p": 0.30,
		"relay_alert_radius": 0.0, "relay_alert_chance": 0.0,
		"camp_limit": 6.0,
	},
	"standard": {
		"player_speed": 1.0, "crouch_speed": 1.0, "sprint_speed": 1.0,
		"lamp_drain": 1.0, "sprint_drain": 1.0,
		"hunter_speed": 1.0, "hunter_sight": 1.02, "hunter_hearing": 1.03,
		"capture_distance": 1.0,
		"search_time": 3.4, "lost_sight_grace": 3.2, "stamina_drain": 13.5, "hide_tell": 1.5, "hide_trail": 3.2, "hide_cooldown": 19.0, "hide_random": 0.05,
		"taser_stun": 2.7, "taser_slow_factor": 0.5, "taser_slow_seconds": 3.0, "taser_cooldown": 8.5, "escape_stun": 2.9, "crowbar_stun": 4.35, "axe_stun": 5.8, "spawn_distance": 12.0, "emote_chase_scale": 0.9, "emote_spot_p": 0.27,
		"relay_alert_radius": 8.0, "relay_alert_chance": 0.25,
		"camp_limit": 9.0,
	},
	"hard": {
		"player_speed": 0.97, "crouch_speed": 0.97, "sprint_speed": 0.98,
		"lamp_drain": 1.175, "sprint_drain": 1.10,
		"hunter_speed": 1.085, "hunter_sight": 1.1, "hunter_hearing": 1.12,
		"capture_distance": 1.04,
		"search_time": 4.0, "lost_sight_grace": 3.6, "stamina_drain": 12.0, "hide_tell": 1.3, "hide_trail": 3.5, "hide_cooldown": 16.0, "hide_random": 0.25,
		"taser_stun": 2.4, "taser_slow_factor": 0.5, "taser_slow_seconds": 3.0, "taser_cooldown": 9.0, "escape_stun": 2.6, "crowbar_stun": 3.9, "axe_stun": 5.2, "spawn_distance": 11.0, "emote_chase_scale": 0.5, "emote_spot_p": 0.15,
		"relay_alert_radius": 18.0, "relay_alert_chance": 1.0,
		"camp_limit": 12.0,
	},
	"nightmare": {
		"player_speed": 0.94, "crouch_speed": 0.94, "sprint_speed": 0.96,
		"lamp_drain": 1.35, "sprint_drain": 1.20,
		"hunter_speed": 1.17, "hunter_sight": 1.22, "hunter_hearing": 1.25,
		"capture_distance": 1.08,
		"search_time": 5.0, "lost_sight_grace": 4.5, "stamina_drain": 10.0, "hide_tell": 1.0, "hide_trail": 4.0, "hide_cooldown": 12.0, "hide_random": 0.45,
		"taser_stun": 2.0, "taser_slow_factor": 0.5, "taser_slow_seconds": 3.0, "taser_cooldown": 10.0, "escape_stun": 2.2, "crowbar_stun": 3.3, "axe_stun": 4.4, "spawn_distance": 10.0, "emote_chase_scale": 0.25, "emote_spot_p": 0.08,
		"relay_alert_radius": 30.0, "relay_alert_chance": 1.0,
		"camp_limit": 15.0,
	},
}

const SAFE_ZONE_LIMITS_BY_DIFFICULTY := {
	"relaxed": 3, "standard": 2, "hard": 1, "nightmare": 0,
}

const MAX_STAMINA := 100.0
const STAMINA_SPRINT_DRAIN := 32.0
const STAMINA_RECOVERY := 21.0
## "no delay before stamina regeneration": regen starts the frame sprinting stops, at the normal rate.
const STAMINA_RECOVERY_DELAY := 0.0
const STAMINA_EXHAUSTED_RECOVERY := 25.0
## Stim Pack (docs/REVIVE.md): a STIM_INJECT_SECONDS jab, then a full tank and STIM_BOOST_SECONDS of
## faster sprinting at a lower drain; then STIM_CRASH_SECONDS of slower regen with a heartbeat hunters can hear.
const STIM_INJECT_SECONDS := .6
const STIM_BOOST_SECONDS := 6.0
const STIM_SPEED_SCALE := 1.2
const STIM_DRAIN_SCALE := .5
const STIM_CRASH_SECONDS := 10.0
const STIM_CRASH_REGEN_SCALE := .5
const STIM_HEARTBEAT_SECONDS := .8
const STIM_HEARTBEAT_NOISE := 3.0
## Revive Kit (docs/REVIVE.md): a caught co-op runner can be revived at the spot they went down for REVIVE_WINDOW_SECONDS,
## by a teammate holding [E] there for REVIVE_HOLD_SECONDS with a kit (used up). Solo it is a one-time second wind.
const REVIVE_WINDOW_SECONDS := 90.0
const REVIVE_HOLD_SECONDS := 3.0
const REVIVE_RANGE := 1.6
const REVIVE_BREAK_DISTANCE := .5
const REVIVE_NOISE := 6.0
const REVIVE_STAMINA := 25.0
const REVIVE_GRACE_SECONDS := 3.5
## Per-chunk spawn chances (Stim Pack .18, Revive Kit .03 solo / .06 co-op) are the `aid` of res://data/loot/route.json.
## Troll mode for caught / flagged cheaters (docs/ANTI_CHEAT.md).
const TROLL_HUNTER_SPEED_SCALE := 1.15
const TROLL_STAMINA_DRAIN_SCALE := 1.6
const TROLL_SCARE_SCALE := 2.5
const TROLL_FAKE_STEP_SECONDS := Vector2(2.5, 6.0)

## A modest first-person hop rather than a platforming jump. These produce a
## theoretical 0.375 m apex and roughly half a second of air time; enough to
## clear a small lip without letting players vault the maze walls or props.
const PLAYER_GRAVITY := 12.0
const PLAYER_JUMP_VELOCITY := 3.15   # a little more than the 3.0 of the 1.60 m runner (hop 0.48 m, inside the restrained 0.24-0.50 m arc)
const LADDER_CLIMB_SPEED := 2.15
## Ordinary room-height drops and imperfect stair transitions remain playable.
## Only a near-full-level fall crosses this threshold, and even severe falls
## produce a short recovery rather than the old multi-second input lock.
const PLAYER_FALL_STUN_SPEED := 8.25
const PLAYER_FALL_STUN_FULL_SPEED := 14.0
const PLAYER_FALL_STUN_MIN_SECONDS := 0.4
const PLAYER_FALL_STUN_MAX_SECONDS := 1.4

## Handheld taser. The firing player predicts only the first-person recoil;
## the room host owns hit testing and the resulting hunter stun in co-op.
const TASER_RANGE := 5.0
const TASER_HALF_ANGLE := 0.35
const TASER_STUN_SECONDS := 2.8
const TASER_COOLDOWN_SECONDS := 8.0

## Hand tools are deliberately shorter-ranged than the taser. A swing always
## spends durability once it starts—even if it only clips another runner—and
## co-op runners never receive damage from it. A crowbar or axe swing at a hunter
## in reach does stun her (MELEE_STRIKE_RANGE below, host-validated).
const TOOL_USE_RANGE := 2.1
## A crowbar or rescue axe swing at a hunter in front (no breach or cut-free target): the host stuns her for the profile's
## crowbar_stun / axe_stun (both longer than taser_stun and escape_stun). Reach is the hand reach plus the hunter's radius.
## A taser-immune hunter is not stunned by the taser; she is slowed: taser_slow_factor of her movement speed for taser_slow_seconds.
const MELEE_STRIKE_RANGE := 2.45
const MELEE_STRIKE_HALF_ANGLE := 0.9
const MELEE_STRIKE_COOLDOWN_SECONDS := 1.0
const LOCKED_RELAY_CACHE_RATIO := 0.42
const BOARDED_PATH_COUNT := 2

const MAX_LAMP_CHARGE := 100.0
const LAMP_IDLE_DRAIN := 0.8
const LAMP_SPRINT_DRAIN := 0.35
const BATTERY_RECHARGE := 25.0

## World reach remains aim- and wall-checked by PlayerController3D. The old
## 26px value was under one 3D cell, forcing runners to press against lockers
## and pickup models before their focus point became usable.
const INTERACTION_RANGE := 72.0
## The local controller uses the narrower camera-relative angle for the
## crosshair target and also checks line of sight. The wider planar angle is
## retained as the host's inexpensive validation envelope for a remote guest:
## it rejects behind-the-player requests without requiring clients to publish
## camera pitch or asking the host to trust a claimed ray hit.
const INTERACTION_AIM_HALF_ANGLE := 0.42
const INTERACTION_FACING_HALF_ANGLE := 0.7

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
const PLAYER_RADIUS := 0.24   # 0.74x of the hunter's 0.33 (the runner is 1.9 m beside a 2.58 m hunter)
## Brain footprint: 0.22 m at the old size, times HunterRoster.MODEL_SCALE (1.5). Still inside one cell, so cell walkability is unchanged.
const HUNTER_RADIUS := 0.33
## Capture reach ("hunters need to be super close to grab"): the bodies touching
## (PLAYER_RADIUS + HUNTER_RADIUS = 0.57) plus the hunter's arm, HUNTER_GRAB_REACH, x the profile's capture_distance:
## Relaxed 1.32, Standard 1.47, Hard 1.53, Nightmare 1.59. The old pre-rescale footprint (0.20 + 0.22 = 0.42) sat inside
## the 0.57 the two collision bodies keep apart, so a hunter only caught a runner after squeezing into them.
const HUNTER_GRAB_REACH := 0.9
const MOVEMENT_STEP := 0.11

const HUNTER_SEARCH_TIME := 3.2
const HUNTER_REPATH_CHASE := 0.24
const HUNTER_REPATH_WANDER := 1.6
const HUNTER_STAMINA_MAX := 100.0
const HUNTER_STAMINA_CHASE_DRAIN := 14.0
const HUNTER_STAMINA_REGEN := 11.0
const HUNTER_STAMINA_RECOVER := 40.0
const HUNTER_WINDED_SPEED_SCALE := 0.62
const HUNTER_SPAWN_DISTANCE_MIN := 12.0
const HUNTER_LOST_SIGHT_GRACE := 3.0
const HUNTER_SENSE_INTERVAL := 0.10
## A hunter with an unobstructed live sighting steers directly at the current
## runner sample and gains enough pressure to beat ordinary walking, while a
## sprint can still create distance at the cost of finite stamina.
const HUNTER_VISIBLE_CHASE_SPEED_SCALE := 1.20

## Reduces a hunter's effective sight range while the player's own flashlight
## is off — staying dark is a real stealth advantage (ui-controller.js/
## hunter-ai.js's unlitSightScale). Room-power (unpoweredSightScale) isn't
## ported — no breaker system exists yet.
const UNLIT_SIGHT_SCALE := 0.5
## A lit flashlight is an emission source, not merely an absence of darkness.
## Hunters can acquire its owner down a long unobstructed hall, while the
## normal per-hunter sight profile still differentiates the roster.
const FLASHLIGHT_SIGHT_SCALE := 3.0
const FLASHLIGHT_SIGHT_MIN := 24.0
## City DAYTIME: outdoors a hunter sees `sight x this` metres whether or not the runner carries a light (about 19 m for an
## 8 m profile), which is also how far the runner is seen. Per-hunter tuning lives in HunterVision.
const DAYLIGHT_SIGHT_SCALE := 2.4
## Daytime thins the streamed hunter population a little (scaled, never below one once hunters are active).
const DAY_POPULATION_SCALE := 0.8

## Player noise emitted per frame by movement mode, consumed by hunter hearing.
const NOISE_CROUCH := 0.9
const NOISE_WALK := 4.2
const NOISE_SPRINT := 10.5
## Outer straight-line reject distance is HEARING_OUTER_SCALE * noise; the
## inner (real) hearing radius is walking distance <= noise, via pathfind().
const HEARING_OUTER_SCALE := 1.45
## In an open line of sight, sound does not have to travel the longer A* route
## around room edges. This small boost is evaluated by the same throttled
## perception ray and avoids an extra path search when the runner is exposed.
const HEARING_OPEN_AIR_SCALE := 1.25

## Exposure meter (0-100): how detectable the runner is right now, eased
## toward a target computed from flashlight, movement noise and cover. Pure
## simulation — hunter mechanics push it via PlayerMeters.add_exposure()
## (Aki's phantom burst). From the original's TUNING block.
const EXPOSURE_BASE := 18.0
const EXPOSURE_FLASHLIGHT := 55.0
const EXPOSURE_NOISE_SCALE := 40.0
const EXPOSURE_CROUCH_SCALE := 0.55
const EXPOSURE_EASE := 1.8

## Noise meter (0-100, facility-wide): accumulated racket. Rises with the
## runner's own gait plus per-frame contributions banked by props/hunters via
## PlayerMeters.add_noise() (Glyra's music box, Ferryn's flash scream), and
## decays steadily toward quiet.
const NOISE_METER_PLAYER_RATE := 8.0
const NOISE_METER_DECAY := 5.0

## Temperature (0-100). The player's body eases toward the facility's ambient,
## which drifts upward on a shortening interval; a safe zone pulls hard back
## toward neutral. Both extremes have real costs, and 100 latches Solyth
## permanently (see SOLYTH_* below).
##
## Per-room climate profiles from the original are NOT ported: its rooms carry
## a `region` that drives a per-room target, and this port's rooms are still
## geometric-only (`type: "generic"`) pending the deferred room-content
## milestone. A single facility-wide ambient is the honest equivalent for now.
const TEMPERATURE_START := 60.0
const TEMPERATURE_NEUTRAL := 60.0
const BODY_TEMPERATURE_RESPONSE := 1.6
const TEMPERATURE_AMBIENT_DRIFT := 0.85
const TEMPERATURE_OVERHEAT := 90.0
const TEMPERATURE_FREEZE := 10.0
const TEMPERATURE_FREEZE_SLOW := 0.72
const TEMPERATURE_OVERHEAT_DRAIN := 1.35
const TEMPERATURE_SAFE_ZONE_PULL := 14.0
const TEMPERATURE_HEATER_WARM := 3.0
## Ordinary route hunters move faster at either extreme; rule-summoned
## specials (Nyxie/Solyth) keep their own tuning and are exempt.
const NORMAL_HUNTER_EXTREME_SPEED_SCALE := 1.3

## Dovelle — the zero-gimmick baseline hunter (HUNTER_ABILITIES.dovelle = {}
## in the original). Consumed via HunterRoster, not referenced directly by
## hunter_brain.gd (see game/config/hunter_roster.gd).

## Quenelle — flashlight tracker (hunterAbilities.quenelle.flashlightTracker in
## the original). Keeping the flashlight on for QUENELLE_FLASHLIGHT_LOCK_SECONDS
## straight earns a permanent chase lock; every flashlight on/off flick after
## that ramps her chase speed further, capped at QUENELLE_MAX_SPEED_SCALE after
## QUENELLE_SPEED_RAMP_ACTIVATIONS flicks. Hard keeps this Standard behaviour; Nightmare locks on after 5 s.
const QUENELLE_FLASHLIGHT_LOCK_SECONDS := 8.0
const QUENELLE_NIGHTMARE_LOCK_SECONDS := 5.0
const QUENELLE_MAX_SPEED_SCALE := 1.45
const QUENELLE_SPEED_RAMP_ACTIVATIONS := 10

## Thessine's original soundMimic plan: one authoritative check every ten
## seconds, with a one-in-two false cue and a small rare-audio pool.
const THESSINE_MIMIC_INTERVAL := 10.0
const THESSINE_MIMIC_CHANCE := 0.5
const THESSINE_MIMIC_RARE_CHANCE := 0.08

## Elise — running-data ratchet (hunterAbilities.elise.runningData). Time spent
## actually sprinting outside a safe zone accumulates and NEVER decays; at
## ELISE_SECONDS_TO_FULL she locks into a permanent blind chase. Her
## `breachesHiding` flag isn't ported — hiding spots don't exist yet, so it
## would be a no-op either way.
const ELISE_SECONDS_TO_FULL := 50.0

## Xivvy — chase accelerator (hunterAbilities.xivvy.chaseAccelerator). Locks on
## by pure proximity (no sight/hearing check), then her chase speed ramps the
## longer the chase runs. XIVVY_CLOSE_SCALE is the original's
## `.5 + exposure / 200` evaluated at exposure 0 — no exposure meter exists
## yet, so this is that formula's genuine rest value, not an invented number.
## Her `flight` flag isn't ported: nothing blocks movement that walking doesn't
## already block, so it's a no-op here.
const XIVVY_CLOSE_LOCK_RADIUS := 1.5
const XIVVY_CLOSE_SCALE := 0.5
const XIVVY_SPEED_PER_SECOND := 0.035
const XIVVY_MAX_SPEED_SCALE := 1.8
const XIVVY_TAKEOFF_SECONDS := 0.65
const XIVVY_FLIGHT_HEIGHT := 0.48

## Kathy — search beam (hunterAbilities.kathy.beamDetection). A cone along her
## own facing that spots the player well past ordinary sight range. Her second
## ability (affectedSummon) is deliberately not ported: it requires other
## already-active route hunters, which is impossible at one hunter per floor
## in both codebases, so it is permanently inert rather than skipped.
const KATHY_BEAM_RANGE := 11.5
const KATHY_BEAM_HALF_ANGLE := 0.24

## Ravelle — tripwire trapper (hunterAbilities.ravelle.tripwireTrapper). Two
## invisible wires on doorway-shaped cells; crossing one locks a chase and
## PERMANENTLY adds to her speed. Her chase speed starts below the roster floor
## on purpose — the per-trigger bonus is what carries her past it. Her fake
## doorway is not ported: only the original's renderer reads it, no gameplay
## logic does.
const RAVELLE_TRIPWIRE_REFRESH := 30.0
const RAVELLE_TRIPWIRE_COUNT := 2
const RAVELLE_TRIGGER_RADIUS := 0.8
const RAVELLE_SPEED_PER_TRIGGER := 0.08
## Walking into one of her wires stuns the runner this long (same stun as Ilyra's pounce: movement locked).
const RAVELLE_TRAP_STUN := 1.6
## Holding INTERACT this long within reach of a wire cuts it (noisy).
const RAVELLE_CUT_SECONDS := 1.2
const RAVELLE_CUT_REACH := 1.3

## Mavrine — lattice mark (hunterAbilities.mavrine.latticeMark). Cycles
## cooldown -> survey (holds still) -> project (an armed frame somewhere on the
## floor) -> ping, pursuing if the player crosses the frame.
const MAVRINE_SURVEY_DELAY := 6.2
const MAVRINE_SURVEY_DURATION := 0.9
const MAVRINE_PROJECTION_DURATION := 6.0
const MAVRINE_COOLDOWN_DURATION := 4.2
const MAVRINE_PING_DURATION := 0.45
const MAVRINE_MARK_TRIGGER_RADIUS := 0.62

## Umbriel — shapeshifter (hunterAbilities.umbriel.shapeshifter). Swaps her
## apparent identity every UMBRIEL_DISGUISE_INTERVAL seconds. On Standard and
## Hard this is purely cosmetic; attribute-copying stays reserved for the
## unselectable Nightmare mode. Kathy is excluded from the pool, as originally.
const UMBRIEL_DISGUISE_INTERVAL := 30.0
const UMBRIEL_DISGUISE_EXCLUDED := ["kathy"]

## Nyxie — darkness stalker (hunterAbilities.nyxie.darknessStalker). A special:
## always present, never in the random draw, woken by sustained darkness rather
## than the relay schedule. Two wake modes — a plain flashlight-off timer, and
## a dead lamp held NYXIE_EMPTY_DELAY seconds, which is an *inescapable*
## capture (the original calls triggerGameOver directly, skipping the
## struggle). A timer wake is dispelled by shining the beam at her.
## Her hearing scale is 0 in the original: she does not hear at all.
const NYXIE_TIMER_DELAY := 120.0
const NYXIE_EMPTY_DELAY := 10.0
const NYXIE_DESPAWN_RANGE := 7.0
const NYXIE_DISPEL_HALF_ANGLE := 0.33
const NYXIE_SPAWN_DISTANCE := 10.0

## Solyth — heat-summoned pursuer (hunterAbilities.solyth.heatManifest). The
## other special. Temperature reaching 100 latches her PERMANENTLY for the rest
## of the run (PlayerMeters.heat_locked), which also pins temperature to a 90F
## floor so cooling can never send her away again. While locked in she burns an
## uncollected battery every SOLYTH_BATTERY_BURN_INTERVAL seconds. Her
## hiding-spot burn isn't ported — no hiding spots exist yet.
const SOLYTH_BATTERY_BURN_INTERVAL := 30.0
const SOLYTH_SPAWN_DISTANCE := 12.0

## Wynelle — cold materializer (hunterAbilities.wynelle.coldMaterializer).
## Unlike the two specials she IS drawn normally; she just starts dormant and
## activates on cold rather than on the relay count. Cold below the warm
## threshold builds a hidden meter; at 100 she materialises directly on the
## player and opens a freeze-grace window. The facility heater station is the
## counterplay — powering it zeroes her progress, unfreezing it dematerialises
## her outright.
const WYNELLE_WARM_THRESHOLD := 60.0
const WYNELLE_DEEP_COLD_THRESHOLD := 30.0
const WYNELLE_PER_DEGREE_RATE := 0.5
const WYNELLE_DEEP_COLD_RATE := 1.0
const WYNELLE_DEATH_GRACE_SECONDS := 10.0
## 2D Zellia deathChance per trade (relaxed .02, normal .05, hard .075, nightmare .12).
const ZELLIA_DEATH_CHANCE := {"relaxed": 0.02, "standard": 0.05, "hard": 0.075, "nightmare": 0.12}
const WYNELLE_DEMATERIALIZE_RESET_PROGRESS := 50.0

## hunterMovementSpeed()'s relay/depth chase-speed progression terms.
const HUNTER_RELAY_SPEED_BONUS := 0.1
const HUNTER_DEPTH_SPEED_BONUS_PER_LEVEL := 0.055
const HUNTER_DEPTH_SPEED_BONUS_MAX := 0.55

## Capture/escape struggle (hunter-ai.js's ESCAPE_* / triggerGameOver).
## CAPTURE_DISTANCE_SCALE is the shared base; the selected profile multiplies
## it inside HunterBrain.
const CAPTURE_DISTANCE_SCALE := 1.0
const ESCAPE_DURATION := 3.2
const ESCAPE_PRESSES := 6
const ESCAPE_COOLDOWN := 16.0
const ESCAPE_GRACE := 1.5
const ESCAPE_STUN_DURATION := 3.0
## Restarting after a death (hunter-ai.js RESPAWN_STUN_DURATION): every active hunter is calmed and held this long, so
## nothing parked by the checkpoint grabs the runner again the moment the restart grace (3.5 s) ends.
const RESPAWN_STUN_DURATION := 4.0

## Relay gate for the first ordinary hunter. Hard begins under pressure,
## Standard wakes on the first recovered signal, and Relaxed gives the player
## time to learn the floor before the third relay wakes her.
const HUNTER_ACTIVATION_RELAYS := {
	"relaxed": 3,
	"standard": 1,
	"hard": 0,
	"nightmare": 0,
}

## Infinite survival adds pressure gradually instead of waking every generated
## hunter at the first activation relay. One hunter arrives at the ordinary
## activation threshold, then additional hunters join at a difficulty-specific
## relay cadence. The desired population has no fixed ceiling: distant bodies
## still stream out, but continued relay recovery can keep adding pursuers.
## Nightmare's larger active lineup: this many hunters are awake at the activation relay instead of one.
const STREAMED_HUNTER_BASE := {"nightmare": 2}
const STREAMED_HUNTER_RELAY_STEP := {
	"relaxed": 3,
	"standard": 2,
	"hard": 1,
	"nightmare": 1,
}

## Infinite-route pressure handled by Gray Void. The longer relay timer catches
## active parties that avoid the objective; the shorter AFK timer catches a
## party which remains stationary. A successful pressure spawn restarts both.
## ANTI_AFK_WARNING_SECONDS is a readable slice of that same AFK window, not
## extra delay: HUD/heartbeat telegraph before Gray Void still wakes on time.
const ANTI_IDLE_HUNTER_SECONDS := {
	"relaxed": 360.0,
	"standard": 255.0,
	"hard": 135.0,
	"nightmare": 105.0,
}
const ANTI_AFK_HUNTER_SECONDS := {
	"relaxed": 240.0,
	"standard": 142.0,
	"hard": 80.0,
	"nightmare": 60.0,
}
const ANTI_AFK_WARNING_SECONDS := 8.0


## Haelith — relay pursuer (hunterAbilities.haelith.relayPursuer). Her only
## numbers in the original are the audio ones (AUDIBLE_RANGE 9,
## FOOTSTEP_INTERVAL 0.4), which have nothing to attach to until there is
## sound, so she has none here.

## Ysolde — battery thief (hunterAbilities.ysolde.batteryThief). torchRange 7
## is deliberately absent: it gates a retaliation that fires on a player torch
## ability this port does not have.
const YSOLDE_STEAL_RANGE := 0.8

## Opalie — relay guardian (hunterAbilities.opalie.relayGuardian). While she
## holds station, nothing within the suppression radius can be interacted with.
## The arrival distance is opalie.js's own 0.75 threshold for "close enough to
## settle", not a tuning choice.
const OPALIE_SUPPRESSION_RADIUS := 1.5
const OPALIE_GUARD_ARRIVAL := 0.75


## Player beam attention, from TUNING.beamAttentionTime / beamAttentionDecay.
## How long the player must hold a torch on a hunter before it registers as a
## deliberate flash, and how fast that dwell bleeds off when the beam moves
## away. Range and cone are the flashlight's own reach.
const BEAM_ATTENTION_TIME := 0.35
const BEAM_ATTENTION_DECAY := 1.6
const BEAM_ATTENTION_RANGE := 12.0
const BEAM_ATTENTION_HALF_ANGLE := 0.28

## Aki — phantom exposure (hunterAbilities.aki.phantomExposure). Flashing her
## starts a fuse, then she spikes exposure to full three times, five seconds
## apart. The burst amount is aki.js's own addExposure(100).
const AKI_INITIAL_DELAY := 10.0
const AKI_BURST_INTERVAL := 5.0
const AKI_BURST_COUNT := 3
const AKI_BURST_EXPOSURE := 100.0


## Javelle — hiding timeout (hunterAbilities.javelle.hidingTimeout). The reach is
## javelle.js's own `plan.reach || 2`, and the stall is its ejectStall fallback:
## the ejection is non-lethal, so she is left briefly winded rather than
## capturing the player she just pulled into the open.
const JAVELLE_HIDING_SECONDS := 8.0
const JAVELLE_REACH := 2.0
const JAVELLE_EJECT_STALL := 2.2


## Loxelle — passive incinerator (hunterAbilities.loxelle.passiveIncinerator /
## breaksHiding). Relaxed, Standard and Hard retain the Standard/easy regen
## rate; Nightmare's slower branch stays reserved with Nightmare itself.
const LOXELLE_INTERVAL := 5.0
const LOXELLE_CHANCE := 0.25
const LOXELLE_REGEN_SECONDS := 30.0
const LOXELLE_BREAK_STALL := 10.0
## 2D breaksHiding: the runner she exposes gets +30 temperature and makes 11 noise.
const LOXELLE_BREAK_TEMPERATURE := 30.0
const LOXELLE_BREAK_NOISE := 11.0
const LOXELLE_CHARGE_WINDUP := 0.42
const LOXELLE_CHARGE_SECONDS := 0.70
## Any hunter checking a hiding spot (docs/HIDING_PROPS.md). It only checks a spot it tracked you to (its last sighting
## within HIDE_CHECK_TRAIL cells of the spot), stands at it for HIDE_CHECK_TELL_SECONDS while the furniture rattles and
## creaks (time to bolt), then pulls the spot open; a checked spot is left alone for HIDE_CHECK_COOLDOWN_SECONDS.
const HIDE_CHECK_REACH := 1.8
const HIDE_CHECK_TRAIL := 3.0
const HIDE_CHECK_TELL_SECONDS := 1.6
const HIDE_CHECK_COOLDOWN_SECONDS := 20.0
const LOXELLE_CHARGE_SPEED := 6.8
const LOXELLE_CHARGE_START_DISTANCE := 0.95
const LOXELLE_CHARGE_IMPACT_DISTANCE := 0.20


## Ceryth — hiding trap (hunterAbilities.ceryth.hidingTrap). lockSeconds is her
## own plan's fallback of 30.
const CERYTH_LOCK_SECONDS := 30.0
## 2D hidingTrap: she sprints to a new spot at 6.4, at least 7 cells away.
const CERYTH_RETREAT_SPEED := 6.4
const CERYTH_MINIMUM_RETREAT := 7.0

## Briselle — room-entry relay sabotage (hunterAbilities.briselle.saboteur).
## dwell is her plan's own value; RELAY_RESECURE_SECONDS is TUNING's
## relayResecureSeconds fallback (2.6), the hold time to bring one back online.
## 2D relayTracker: huntSeconds 12, speedScale 1.25, flashStunSeconds 3.
const BRISELLE_HUNT_SECONDS := 12.0
const BRISELLE_SPEED_SCALE := 1.25
const BRISELLE_FLASH_STUN_SECONDS := 3.0
const BRISELLE_ROOM_CHANCE := 0.5
const BRISELLE_SABOTAGE_DWELL := 5.0
const RELAY_RESECURE_SECONDS := 2.6

## Ferryn — persistent stalk (hunterAbilities.ferryn.roundStalker). flashNoise
## is her plan's own value.
const FERRYN_FLASH_NOISE := 100.0

## Glyra and the music boxes (GlyraGimmick, MusicBoxes). A wound box plays for MUSIC_BOX_WOUND_SECONDS
## (by difficulty); its last MUSIC_BOX_WINDDOWN_SECONDS go off-key. Glyra is calm while her nearest box plays, restless
## while it winds down, and hunts fast once it stops. Winding is a hold of MUSIC_BOX_WIND_HOLD seconds.
const MUSIC_BOX_WOUND_SECONDS := {"standard": 45.0, "hard": 35.0, "nightmare": 25.0}
const MUSIC_BOX_WINDDOWN_SECONDS := 15.0
const MUSIC_BOX_WIND_HOLD := 1.5
const MUSIC_BOXES_PER_REGION := 2
const GLYRA_CALM_SPEED_SCALE := 0.6
const GLYRA_CALM_SIGHT := 4.0          # calm, she only chases a runner this close
const GLYRA_CALM_LEASH := 8.0          # calm, she wanders back toward her box beyond this
const GLYRA_HUNT_SPEED_SCALE := {"standard": 1.3, "hard": 1.3, "nightmare": 1.5}
const GLYRA_HUNT_HEARING_SCALE := 1.5
const GLYRA_CALM_AFTER_WIND := 3.0     # a rewind settles her within this, unless she can see who she is chasing

## Ilyra — corner observer (hunterAbilities.ilyra.cornerObserver). Relaxed,
## Standard and Hard use the counterable Standard values; Nightmare's
## zero-delay pounce stays reserved with the unselectable mode.
## 2D config pounceDelay (Nightmare: 0).
const ILYRA_POUNCE_DELAY := 15.0
const ILYRA_SIGHT_SCALE := 1.8
const ILYRA_STUN_SECONDS := 5.0
const ILYRA_BANISH_SECONDS := 30.0

## Verrine — vent lurker (hunterAbilities.verrine.ventLurker):
## {count:4, initialSpeedScale:.4, speedPerSecond:.025, maximumSpeedScale:2.4}.
const VERRINE_VENT_COUNT := 4
const VERRINE_INITIAL_SPEED_SCALE := 0.4
const VERRINE_SPEED_PER_SECOND := 0.025
const VERRINE_MAX_SPEED_SCALE := 2.4

## Zellia — merchant. Pesticide lasts ZELLIA_PESTICIDE_SECONDS (60). Offer costs
## are cool 2, warm 2, repair 3, pesticide 4. A completed trade rolls
## ZELLIA_DEATH_CHANCE (relaxed 0.02, standard 0.05, hard 0.075, nightmare 0.12).
const ZELLIA_SHOP_RANGE := 1.35
const ZELLIA_PESTICIDE_SECONDS := 60.0
const ZELLIA_COOL_COST := 2
const ZELLIA_WARM_COST := 2
const ZELLIA_REPAIR_COST := 3
const ZELLIA_PESTICIDE_COST := 4
const ZELLIA_TEMPERATURE_STEP := 15.0
const ZELLIA_LAMP_REPAIR := 25.0

## Coin pickups, scattered on the floor the same way relays/batteries are.
## The original places a variable-value coin scatter (`maze.coins`); this
## port simplifies to a fixed count worth a fixed amount each, the same
## honest-simplification shape as the vent prompt's static text.
const COIN_PICKUP_COUNT := 5
const COIN_PICKUP_VALUE := 2


static func difficulty_profile(id: String) -> Dictionary:
	return DIFFICULTY_PROFILES.get(id, DIFFICULTY_PROFILES["standard"])


## One number of a difficulty profile (the per-mode tweaks: search time, hide checks, taser, ...), falling back to Relaxed's value.
static func profile_value(id: String, key: String) -> float:
	var profile: Dictionary = difficulty_profile(id)
	if profile.has(key):
		return float(profile[key])
	return float((DIFFICULTY_PROFILES["relaxed"] as Dictionary).get(key, 0.0))


static func hunter_activation_relay_count(id: String) -> int:
	return int(HUNTER_ACTIVATION_RELAYS.get(id,
		HUNTER_ACTIVATION_RELAYS["standard"]))


static func streamed_hunter_population(id: String, relays_collected: int) -> int:
	var difficulty := id if STREAMED_HUNTER_RELAY_STEP.has(id) else "standard"
	var activation := hunter_activation_relay_count(difficulty)
	if relays_collected < activation:
		return 0
	var step := maxi(1, int(STREAMED_HUNTER_RELAY_STEP[difficulty]))
	return int(STREAMED_HUNTER_BASE.get(difficulty, 1)) + (relays_collected - activation) / step


static func anti_idle_hunter_seconds(id: String) -> float:
	return float(ANTI_IDLE_HUNTER_SECONDS.get(id,
		ANTI_IDLE_HUNTER_SECONDS["standard"]))


static func anti_afk_hunter_seconds(id: String) -> float:
	return float(ANTI_AFK_HUNTER_SECONDS.get(id,
		ANTI_AFK_HUNTER_SECONDS["standard"]))


static func anti_afk_warning_seconds() -> float:
	return ANTI_AFK_WARNING_SECONDS


static func safe_zone_limit_for(id: String) -> int:
	return int(SAFE_ZONE_LIMITS_BY_DIFFICULTY.get(id,
		SAFE_ZONE_LIMITS_BY_DIFFICULTY["standard"]))
