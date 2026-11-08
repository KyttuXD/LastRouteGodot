extends "res://tests/validate_regions.gd"

## One shard of the regions suite: the mall region only (the parallel runner spreads the four shards).


func _init() -> void:
	regions = ["mall"]
