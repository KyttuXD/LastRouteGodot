# Publishing

For now publishing is **owner-only**: Kyttu's Lab publishes packs. Player uploads come later.

## How a pack is published

1. The pack passes `modpack.sh validate`.
2. The owner runs `backend/deploy_mod_pack.mjs <pack folder>` (dry run first, then `--apply`). It hashes every file,
   checks the same rules, copies the folder to the file host (served from `<file-host>/<id>/<version>/`),
   re-hashes it there, and registers the pack in the index on the game server.
3. A published version never changes. Any change is a new version.

## How players get it

- A host switches packs on with **USE IN MY ROOMS** in **Settings -> MODS** (hand-installed packs only) and opens a
  private room.
- A joining player who is missing a pack sees each pack's name, author, size and hash with an own-risk warning, and
  chooses **DOWNLOAD & JOIN** or **CANCEL**. "Auto-download mods", off by default, skips the question.
- The game asks the index for the pack, downloads each file from the file host, checks every file's SHA-256 and size
  against the index, checks the whole pack's hash against the host's, and only then loads it. Any mismatch cancels
  the join and leaves nothing behind.
- Downloaded packs are cached. **Settings -> MODS -> REMOVE DOWNLOADED MODS** deletes them.

## Moderation

The owner can block a pack in the index. A blocked pack is not handed out, and players see "Removed by moderators".
