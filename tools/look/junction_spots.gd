extends Node

## Prints CAP_AT strings for one T and one cross junction of a biome (GeometryAudit.junction_spots).
##
##   godot --headless --path . res://tools/look/junction_spots.tscn -- SEED BIOME

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var generator := StreamedRouteGenerator.new(args[0] if args.size() > 0 else "ENDLESS-ROUTE")
	print("CAP_AT=" + ";".join(GeometryAudit.junction_spots(generator, args[1] if args.size() > 1 else "gothic")))
	get_tree().quit(0)
