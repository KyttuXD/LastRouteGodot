extends SceneTree

## Room-vs-props capacity per room type (RoomCapacity): fill share of open floor, reach from the door, signature props.
##   godot --headless --path . -s dev/look/room_capacity_report.gd   (SEEDS="A,B" RING=4 to change the sample)

func _init() -> void:
	var seeds := (OS.get_environment("SEEDS") if OS.get_environment("SEEDS") != "" else "CAP-A,CAP-B,CAP-C").split(",")
	var ring := int(OS.get_environment("RING")) if OS.get_environment("RING") != "" else 4
	var result := RoomCapacity.survey(Array(seeds), ring)
	print(RoomCapacity.table(result))
	print("rooms %d  over fill %d  under reach %d" % [result["rooms"], result["over_fill"].size(), result["under_reach"].size()])
	for line in (result["over_fill"] as Array).slice(0, 15) + (result["under_reach"] as Array).slice(0, 25):
		print("  ", line)
	quit()
