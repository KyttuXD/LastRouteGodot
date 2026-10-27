class_name PlayerModels
extends RefCounted

## Which body every runner wears. The blocky wooden mannequin (the hunters' rig and Minecraft-skin layout, texture
## assets/hunters_blocky/player_mannequin) is the default. USE_BLOCKY false falls back to the faceted wooden mannequin
## (USE_WOODEN) or the old Minecraft-skin body (LEGACY); both keep working.

const USE_BLOCKY := true
const USE_WOODEN := true
const BLOCKY := "res://assets/hunters_blocky/player_mannequin/player_mannequin.tscn"
const WOODEN := "res://art/props-3d/characters/player.tscn"
const LEGACY := "res://art/props-3d/characters/player_legacy.tscn"
const SCENE := BLOCKY if USE_BLOCKY else (WOODEN if USE_WOODEN else LEGACY)
