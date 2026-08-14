class_name GameConfig
extends RefCounted

## Shared values for the first migration slice. Replace content-heavy dictionaries
## with typed Resources as canonical data is moved from the browser project.

const INTERNAL_SIZE := Vector2i(480, 270)
const TILE_SIZE := 16

const PLAYER_WALK_SPEED := 64.0
const PLAYER_SPRINT_SPEED := 100.0
const PLAYER_CROUCH_SPEED := 36.0

const PLAYER_BOUNDS := Rect2(8.0, 8.0, 464.0, 254.0)

