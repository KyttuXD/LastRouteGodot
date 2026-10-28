# Walkthrough: the Ember pack

Ember is the example pack shipped in `examples/mods/ember` and published on the pack index (version 1.0.0). It does
two things: every office printer turns ember orange, and a new hunter, Ember, can be drawn.

## 1. The manifest

```json
{
	"schema": "lr.pack/1",
	"id": "ember",
	"name": "Ember",
	"version": "1.0.0",
	"author": "Kyttu's Lab (example)",
	"description": "Example pack: every office printer in ember orange, and Ember, a faster Aki variant.",
	"overrides": ["props/officePrinter"]
}
```

It overrides one built-in prop, so `props/officePrinter` is listed under `overrides`.

## 2. The prop override (`props/office.json`)

```json
{"schema": "lr.prop/1", "family": "office", "props": [
	{"id": "officePrinter", "models": ["assets/office_printer_ember.glb"], "themes": ["ember"]}
]}
```

`assets/office_printer_ember.glb` is the shipped printer model with its material tinted orange. Wherever the game
places an office printer, players in the room see this one. `themes` has one label because there is one model.

## 3. The new hunter (`hunters/ember.json`)

```json
{"schema": "lr.hunter/1", "id": "ember_aki", "name": "Ember", "tier": "intermediate",
 "speed": 0.86, "chase": 3.8, "prog": 0.19, "sight": 8.4, "hearing": 1.05, "spawn": 12,
 "model": "res://assets/hunters_blocky/aki/aki.glb", "portrait": "res://assets/ui/hunter_portraits/aki.png"}
```

The id starts with the pack id. Ember wears Aki's shipped body and portrait, joins the intermediate tier of the
seeded draw, and chases with the default behaviour on her own numbers (a little faster than Aki).

## 4. Check it

```
tools/modpack/modpack.sh validate examples/mods/ember
OK ember 1.0.0: 4 files, 20027 bytes, { "props": 1, "regions": 0, "hunters": 1 }, sha256 35c0b6ee...
```

## 5. Play it

Copy the folder to the game's `mods/ember/`, switch on **USE IN MY ROOMS** for Ember in **Settings -> MODS**, and
start a private room.
Players who join without it are offered the download (see [publishing](publishing.md)).
