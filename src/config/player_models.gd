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
## The world is built at hunter scale (a normal hunter, 2.67 m, is the "human"); runners are smaller (KT, 2026-10-28:
## "think of the hunters like humans and the players as ants"). Every runner body, capsule, eye, crouch, step, reach
## and held item takes this: 1.78 m mannequin -> 1.60 m runner, 0.6x a hunter (docs/SCALE_FIT.md).
const SCALE := 0.9
