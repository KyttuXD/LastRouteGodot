class_name PlayerModels
extends RefCounted

## Which body every runner wears: the blocky wooden mannequin (the hunters' rig and Minecraft-skin layout, texture
## assets/hunters_blocky/player_mannequin). It is the only body; the older wooden and Minecraft-skin rigs are retired.

const BLOCKY := "res://assets/hunters_blocky/player_mannequin/player_mannequin.tscn"
## The Alex (slim, 3 px arms) variant: same rig, bones and clips, only the arm meshes differ (PlayerSkin.set_arms swaps them in).
const BLOCKY_SLIM := "res://assets/hunters_blocky/player_mannequin_slim/player_mannequin_slim.tscn"
const SCENE := BLOCKY
## The world is built at hunter scale (a normal hunter, 2.67 m, is the "human"); runners are slightly smaller (the
## 1.60 m runner looked far too small beside a hunter in the grabs; second ruling: 0.3 m smaller, head top at about a hunter's upper torso (shoulder line 1.83 m, neck 2.0 m of the 2.58 m hunter): 1.90 m, 0.74x). Every
## runner body, capsule, eye, crouch, step, reach and held item takes this: 1.78 m mannequin -> 1.90 m runner (docs/SCALE_FIT.md).
const SCALE := 1.067
