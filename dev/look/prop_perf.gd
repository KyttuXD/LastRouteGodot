extends Node

## Props performance probe (DONE16): frame time, draw calls and render objects in real generated rooms, windowed (needs a GPU:
## run it with `godot --path . res://dev/look/prop_perf.tscn -- OUTDIR TAG SEED [ONLY] [MAX] [list|-] [MODE]`).
## ONLY is a comma list of substrings of the "region_roomtype" picks (hotel, prison, apartment, office, mansion, maze), MAX the number
## of rooms (default 8); every room is measured at three headings. It wraps dev/look/capture.gd in its CAP_FPS mode.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	OS.set_environment("CAP_FPS", "1")
	OS.set_environment("CAP_YAWS", "0,120,240")
	if args.size() > 3 and args[3] != "" and args[3] != "-":
		OS.set_environment("CAP_ONLY", args[3])
	OS.set_environment("CAP_MAX", args[4] if args.size() > 4 else "8")
	if args.size() > 5 and args[5] == "list":
		OS.set_environment("CAP_LIST", "1")
	# args[6]: "base" (neither optimisation), "share" (shared materials only), "range" (visibility ranges only), default both
	var mode := args[6] if args.size() > 6 else "both"
	ModelSlot.share_blocky_materials = mode in ["share", "both"]
	StreamedFacilityView3D.limit_prop_visibility = mode in ["range", "both"]
	add_child((load("res://dev/look/capture.tscn") as PackedScene).instantiate())
