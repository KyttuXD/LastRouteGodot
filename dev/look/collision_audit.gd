extends SceneTree

## godot --headless --path . -s dev/look/collision_audit.gd -- [SEEDS_CSV] [CHUNKS_PER_REGION]
func _init() -> void:
	var seeds := ["COL-A", "COL-B"]
	var limit := 6
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = Array(args[0].split(","))
	if args.size() > 1:
		limit = int(args[1])
	var report := CollisionAudit.run(seeds, limit)
	print("COLLISION AUDIT ", report["totals"])
	for key in report["samples"]:
		print("  ", key, ": ", report["samples"][key])
	quit()
