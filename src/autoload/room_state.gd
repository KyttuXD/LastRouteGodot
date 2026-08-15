extends Node

## The room a session belongs to.
##
## Singleplayer is not a separate path here -- it is a room with one player in
## it, hosted locally, with no transport attached. That is the whole point of
## introducing this before there is any networking: every entry into the game
## already goes through a room, so adding multiplayer later means giving the
## room a transport rather than rewriting how runs start.
##
## Concretely, the things a run needs -- which mode, which seed, how big the
## map, how hard -- live on the room, not on whoever pressed the button. When
## PLAY and OFFICE MODE become CREATE ROOM and JOIN ROOM, nothing downstream of
## this file has to change: a joined room fills these same fields from the host
## instead of from `create_local`.
##
## Mirrors the web build's staging screen, including its vocabulary (route
## seed, signals, staging) and its offline rule: without a backend you get the
## modes that do not need anyone else.

signal changed

enum Mode { DEFAULT, HIDE_SEEK, OFFICE }
enum Scale { SMALL, STANDARD, LARGE, SPRAWLING, CAVERNOUS, ENDLESS }
enum Difficulty { RELAXED, STANDARD, NIGHTMARE }

## The web build calls a slot a "signal" and seats sixteen of them.
const MAX_PLAYERS := 16

## Room codes are read aloud and typed in, so the alphabet drops the glyphs
## that get confused doing either: I/1, O/0, and lowercase entirely.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5

const MODE_LABELS := {
	Mode.DEFAULT: "DEFAULT", Mode.HIDE_SEEK: "HIDE & SEEK", Mode.OFFICE: "OFFICE",
}
const SCALE_LABELS := {
	Scale.SMALL: "SMALL", Scale.STANDARD: "STANDARD", Scale.LARGE: "LARGE",
	Scale.SPRAWLING: "SPRAWLING", Scale.CAVERNOUS: "CAVERNOUS",
	Scale.ENDLESS: "ENDLESS",
}
const DIFFICULTY_LABELS := {
	Difficulty.RELAXED: "RELAXED", Difficulty.STANDARD: "STANDARD",
	Difficulty.NIGHTMARE: "NIGHTMARE",
}

## Which scene each mode opens. OFFICE is its own self-contained shift and
## shares no state with a Last Route run.
const MODE_SCENES := {
	Mode.DEFAULT: "res://scenes/main_3d.tscn",
	Mode.HIDE_SEEK: "res://scenes/main_3d.tscn",
	Mode.OFFICE: "res://scenes/office_3d.tscn",
}

var code := ""
## The full route seed, shown on the staging screen and the in-run HUD so two
## players can confirm they are on the same route.
var seed_text := ""
var mode: Mode = Mode.DEFAULT
var map_scale: Scale = Scale.STANDARD
var difficulty: Difficulty = Difficulty.STANDARD
## Display names, host first. One entry while offline.
var players: PackedStringArray = []
## False until there is a backend. Everything that would need one asks this.
var online := false
var is_host := true


func _ready() -> void:
	# A room always exists, so nothing has to null-check it. Landing straight
	# in a mode from the editor gets a valid singleplayer room.
	if code.is_empty():
		create_local(Mode.DEFAULT)


## Open a room on this machine with one player in it.
##
## This IS singleplayer. There is no second code path to keep in step, which is
## the reason to do it now rather than after the networking exists.
func create_local(for_mode: Mode) -> void:
	code = _make_code()
	mode = for_mode
	map_scale = Scale.STANDARD
	difficulty = Difficulty.STANDARD
	online = false
	is_host = true
	players = PackedStringArray([_make_callsign()])
	reroll_seed()
	changed.emit()


## A fresh route for the same room. The web build regenerates the facility from
## the seed, so changing it is how you get a different building without leaving
## staging.
func reroll_seed() -> void:
	var stamp := "%d%d" % [Time.get_ticks_usec(), randi()]
	seed_text = "ROOM-%s-%s" % [code, stamp.md5_text().substr(0, 20).to_upper()]
	changed.emit()


## The seed as GameState wants it. Derived from the text rather than stored
## separately, so the string on screen and the facility on the floor cannot
## disagree about which route this is.
func run_seed() -> int:
	return abs(int(seed_text.hash()))


## Whether a mode can be picked in this room's current state.
##
## HIDE & SEEK needs someone to hide from, so it is unavailable offline. That
## is a property of the room rather than a disabled button in the menu, so the
## rule holds wherever a mode gets chosen.
func mode_available(candidate: Mode) -> bool:
	if candidate == Mode.HIDE_SEEK:
		return online and players.size() > 1
	return true


func mode_unavailable_reason(candidate: Mode) -> String:
	if candidate == Mode.HIDE_SEEK and not online:
		return "NEEDS A SECOND SIGNAL // NO BACKEND YET"
	if candidate == Mode.HIDE_SEEK:
		return "NEEDS A SECOND SIGNAL IN THE ROOM"
	return ""


## What the button that leaves staging should say, in the web build's words.
func start_label() -> String:
	return "START OFFICE SHIFT" if mode == Mode.OFFICE else "ENTER ROUTE"


func mode_label() -> String:
	return String(MODE_LABELS.get(mode, "?"))


## Office Mode is singleplayer by design -- the mode is a lone night shift, and
## its whole premise is that there is nobody else to call. It seats one however
## the room was opened.
func seats() -> int:
	return 1 if mode == Mode.OFFICE else MAX_PLAYERS


func set_mode(value: Mode) -> void:
	if mode == value or not mode_available(value):
		return
	mode = value
	changed.emit()


func set_map_scale(value: Scale) -> void:
	if map_scale == value:
		return
	map_scale = value
	changed.emit()


func set_difficulty(value: Difficulty) -> void:
	if difficulty == value:
		return
	difficulty = value
	changed.emit()


## Leave staging and start the run this room describes.
##
## The room seeds GameState rather than the mode scene seeding itself, so two
## players entering the same room get the same building -- which is the part
## that has to be true before any networking is worth writing.
func enter(tree: SceneTree) -> void:
	if mode != Mode.OFFICE:
		GameState.start_new_run(run_seed())
	tree.change_scene_to_file(String(MODE_SCENES.get(mode, MODE_SCENES[Mode.DEFAULT])))


static func _make_code() -> String:
	var out := ""
	for i in CODE_LENGTH:
		out += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return out


## A callsign in the web build's shape -- QUIET-EYE-307. Anonymous on purpose:
## a room is joined by code, and nobody has an account yet.
static func _make_callsign() -> String:
	const FIRST := ["QUIET", "LOW", "DIM", "COLD", "LONG", "THIN", "FAINT", "LAST"]
	const SECOND := ["EYE", "STEP", "LAMP", "WIRE", "ROUTE", "DOOR", "SIGNAL", "WATCH"]
	return "%s-%s-%d" % [FIRST[randi() % FIRST.size()],
		SECOND[randi() % SECOND.size()], 100 + randi() % 900]
