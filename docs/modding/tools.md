# Validate and pack (starter kit)

The kit runs the game's own loader headless, so its answers are the game's answers. It needs Godot 4 and a checkout of
the game; set `GODOT_BIN` if Godot is not in the usual place.

## init

```
tools/modpack/modpack.sh init <pack id> [parent folder]
```

Copies `examples/mods/template` to `<parent>/<pack id>` (default: the game's mods folder) and renames its ids. The
template already validates: an override of the office water cooler with a copy of the shipped model, and a hunter
variant on Glyra's body. Replace the model, edit the JSON, validate.

## validate

```
tools/modpack/modpack.sh validate <pack folder>
```

Runs, in order:
1. every rule the loader enforces: allowed files only, sizes, `pack.json`, schemas and field types, id rules,
   declared overrides that exist, readable PNG/Ogg, glTF files with no extensions outside the allowed list;
2. checks across content: prop sets name known props;
3. every model loads the way the game loads it (scripts and non-mesh nodes stripped) and has a visible mesh;
4. prop sizes against the game's size table (person-scale range x 1.5 hunter scale), when the build has it.

Exit code 0 means the game will load the pack. Errors name the file and field.

## pack

```
tools/modpack/modpack.sh pack <pack folder>
```

Validates, then prints the pack's id, version, identity SHA-256 and the file list with sizes and hashes. The hash is
the one the room handshake and the pack index use. There is no archive step: packs are published as plain folders.

No preview yet: rendering a contact sheet needs a GPU, and the kit runs headless. Use a private room to look at your
pack.
