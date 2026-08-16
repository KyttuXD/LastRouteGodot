class_name Build
extends RefCounted

## Manually controlled release identifier. Keep this unchanged during unrelated
## work; only change it when the user explicitly asks to change or bump it.
const VERSION := "0.0.1.0"

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


## True in the editor and debug exports, false in every release export.
## Release builds deliberately have no command-line override: admin controls
## and spoiler views must stay unavailable even if a player knows the flags
## used during development.
static func tools_enabled() -> bool:
	return OS.is_debug_build()


## Whether to draw the frame counter and other always-on readouts.
static func show_diagnostics() -> bool:
	return tools_enabled()


## Whether debug views that would spoil a run -- hunter positions, the full
## facility layout, threat timers -- may be opened at all.
static func allow_spoiler_views() -> bool:
	return tools_enabled()


static func update_channel() -> String:
	return "debug" if tools_enabled() else "release"
