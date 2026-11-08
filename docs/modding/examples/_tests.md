# Refused test packs (`examples/mods/_tests`)

Each folder is a deliberately broken pack. `data_packs` loads every one and requires a refusal that names the file and
the reason, with the game left unchanged. `modpack.sh validate` gives the same answers.

| pack | what is wrong | refusal contains |
|---|---|---|
| `test_script_in_model` | a `.glb` carrying an `EXT_script` extension with source code | `glTF extension "EXT_script" is not allowed in packs` |
| `test_unknown_kind` | a `gadgets/` folder | `not allowed in a pack` |
| `test_missing_file` | a hunter portrait that is not in `assets/` | `is not a .png under assets/ in this pack` |
| `test_interactive_prop` | a room recipe placing `dinerBooth` | `which is interactive` |
| `test_oversized_texture` | a 256x256 noise PNG (about 260 KB) | `per-file limit` (the validator lowers the limit to 64 KB; the real one is 16 MB) |
| `test_bad_schema` | `"speed": "fast"` | `"speed" must be float` |
| `test_duplicate_id` | two hunter files with the same id | `is also defined by` |
| `test_hash_mismatch` | `pack.json` lists a wrong sha256 and size | `size or sha256 differs from pack.json files` |

The pack loader limits files by size, not by pixel dimensions: a tiny PNG with huge dimensions is not refused today.
