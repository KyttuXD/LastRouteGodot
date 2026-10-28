# Modding Last Route

Last Route can load **content packs**: folders of data and assets that change or add props, hunters and regions.
Packs never contain code. The game reads them with the same loader it uses for its own content, so a pack can only do
what the data formats allow.

Packs are played in **private rooms only**. Public routes are always the unmodded game.

## What you can mod today

| | change a built-in one | add a new one |
|---|---|---|
| **Props** (furniture, dressing) | yes: replace its model everywhere the game places it | yes, but it only appears where a region's prop set places it (see [content types](content-types.md#props)) |
| **Hunters** | yes: retune any hunter | yes: a new hunter joins the seeded draw with the default chase behaviour and a shipped or custom body |
| **Regions** | yes: floors, doors, shop names, room roles, dressing | loads and validates, but no level places a new region yet |

Not yet moddable: hunter abilities and AI, sounds and music, textures and skins outside models, levels and room
furniture recipes. Those are planned as further pack types.

## Quick start

```
tools/modpack/modpack.sh init mypack          # copies the template to the game's mods folder
tools/modpack/modpack.sh validate <folder>    # the game's own checks
tools/modpack/modpack.sh pack <folder>        # identity hash and file list
```

To use a pack in your own rooms, turn it on in the game's `settings.cfg` (next to the `mods` folder):

```
[mods]
enabled=["mypack"]
```

A switch for this in **Settings -> MODS** is on the way. Then start a private room.

## Pages

- [Pack format](pack-format.md): folder layout, `pack.json`, ids, overrides, the pack hash
- [Content types](content-types.md): every field of props, hunters and regions
- [Walkthrough: the Ember pack](ember-walkthrough.md)
- [Validate and pack](tools.md): the starter kit
- [Publishing](publishing.md): how packs reach other players
- [Rules and limits](rules.md)
