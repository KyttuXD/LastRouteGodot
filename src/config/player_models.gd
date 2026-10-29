class_name PlayerModels
extends RefCounted

## Which body every runner wears. The blocky wooden mannequin (the hunters' rig and Minecraft-skin layout, texture
## assets/hunters_blocky/player_mannequin) is the default. USE_BLOCKY false falls back to the faceted wooden mannequin
## (USE_WOODEN) or the old Minecraft-skin body (LEGACY); both keep working.

const USE_BLOCKY := true
const USE_WOODEN := true
const BLOCKY := "res://assets/hunters_blocky/player_mannequin/player_mannequin.tscn"
## The Alex (slim, 3 px arms) variant: same rig, bones and clips, only the arm meshes differ (PlayerSkin.set_arms swaps them in).
const BLOCKY_SLIM := "res://assets/hunters_blocky/player_mannequin_slim/player_mannequin_slim.tscn"
const WOODEN := "res://art/props-3d/characters/player.tscn"
const LEGACY := "res://art/props-3d/characters/player_legacy.tscn"
const SCENE := BLOCKY if USE_BLOCKY else (WOODEN if USE_WOODEN else LEGACY)
## The world is built at hunter scale (a normal hunter, 2.67 m, is the "human"); runners are slightly smaller (KT, 2026-10-28:
## the 1.60 m runner looked far too small beside a hunter in the grabs; ruling: about 2.2 m, 0.85x of the 2.58 m hunter). Every
## runner body, capsule, eye, crouch, step, reach and held item takes this: 1.78 m mannequin -> 2.2 m runner (docs/SCALE_FIT.md).
const SCALE := 1.236
