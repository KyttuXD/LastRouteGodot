class_name PlayerModels
extends RefCounted

## Which body every runner wears. The wooden mannequin is the default; flip
## USE_WOODEN to false to compare against the old Minecraft-skin mannequin.

const USE_WOODEN := true
const WOODEN := "res://art/props-3d/characters/player.tscn"
const LEGACY := "res://art/props-3d/characters/player_legacy.tscn"
const SCENE := WOODEN if USE_WOODEN else LEGACY
