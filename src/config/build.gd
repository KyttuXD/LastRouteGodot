class_name Build
extends RefCounted

const VERSION := "0.1.0"

## What this build is allowed to show the player.
##
## The web version carries developer instrumentation -- an FPS readout, the
## memory-map overlay, the radar -- that is genuinely useful while building the
## game and has no business in a normal one: it hands out hunter positions and
## tells the player things the mode is built around not knowing.
##
## The rule is that developer UI is opt-IN and defaults to off, rather than
## something to remember to strip before shipping. An exported release build
## reports false here whatever anyone forgot, and the editor reports true, so
## the tools are there while working and gone when not.
##
## Anything that reveals state the player is supposed to be uncertain about
## goes behind `tools_enabled()`. Ordinary features that happen to be handy
## (the maze's own memory map, which is an item the player earns) do not --
## those are gameplay.


## True in the editor and in debug exports, false in a release export.
##
## `--tools` forces it on for a release build, so a tester can be handed one
## without a separate build; there is deliberately no way to force it on from
## inside the game.
static func tools_enabled() -> bool:
	return OS.is_debug_build() or OS.get_cmdline_user_args().has("--tools")


## Whether to draw the frame counter and other always-on readouts.
static func show_diagnostics() -> bool:
	return tools_enabled()


## Whether debug views that would spoil a run -- hunter positions, the full
## facility layout, threat timers -- may be opened at all.
static func allow_spoiler_views() -> bool:
	return tools_enabled()


## Whether staging may expose an arbitrary ENet address and port. Production
## players use the built-in room directory exclusively; editor/debug builds
## keep direct-connect available for local and alternate-server testing.
static func allow_custom_hosts() -> bool:
	return tools_enabled()


static func update_channel() -> String:
	return "debug" if tools_enabled() else "release"
