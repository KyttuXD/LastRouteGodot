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
| **Grabs** (how a hunter takes hold of a caught runner) | yes: any hunter's pool of grab styles | yes: give your own hunters a pool |
| **Sounds** (cues and ambience beds) | yes: replace a sound effect or a region's background bed with your own recordings | no: only built-in sounds are played |
| **Surfaces** (floor and wall textures) | yes: replace any floor or wall pattern with your own image | no: regions name the built-in kinds |

Not yet moddable: hunter abilities and AI, new grab animations, footstep sounds, ceiling textures, player skins (they
have their own sharing system), levels and room furniture recipes. Those are planned as further pack types.

## Quick start

```
tools/modpack/modpack.sh init mypack          # copies the template to the game's mods folder
tools/modpack/modpack.sh validate <folder>    # the game's own checks
tools/modpack/modpack.sh pack <folder>        # identity hash and file list
```

To use a pack in your own rooms, open **Settings -> MODS** and switch on **USE IN MY ROOMS** on its row, then start a
private room. (Only packs you installed yourself can be hosted; downloaded packs are for joining. The switch is stored
as `[mods] enabled=["mypack"]` in `settings.cfg`, next to the `mods` folder.)

## Pages

- [Pack format](pack-format.md): folder layout, `pack.json`, ids, overrides, the pack hash
- [Content types](content-types.md): every field of props, hunters and regions
- [Walkthrough: the Ember pack](ember-walkthrough.md)
- [Validate and pack](tools.md): the starter kit
- [Publishing](publishing.md): how packs reach other players
- [Rules and limits](rules.md)
