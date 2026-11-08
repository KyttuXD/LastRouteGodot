// Pre-compress a Godot web export with brotli so the site can serve `<file>.br` to browsers that accept it
// (the .pck is not compressed by CDNs because its type is unknown to them). Originals are kept.
//   node tools/build/compress_web.mjs builds/web
import { readdir, readFile, writeFile, stat } from "node:fs/promises";
import { brotliCompress, constants } from "node:zlib";
import { promisify } from "node:util";
import { join, extname } from "node:path";

const compress = promisify(brotliCompress);
const EXTENSIONS = new Set([".wasm", ".pck", ".js", ".html", ".json", ".css", ".svg"]);
const directory = process.argv[2];
if (!directory) { console.error("usage: node tools/build/compress_web.mjs <web export folder>"); process.exit(2); }

let before = 0, after = 0;
for (const name of (await readdir(directory)).sort()) {
  if (name.startsWith(".") || !EXTENSIONS.has(extname(name)) || name.endsWith(".br")) continue;
  const path = join(directory, name);
  const info = await stat(path);
  if (!info.isFile() || info.size < 1024) continue;
  const data = await readFile(path);
  const packed = await compress(data, { params: {
    [constants.BROTLI_PARAM_QUALITY]: 11,
    [constants.BROTLI_PARAM_LGWIN]: 24,
    [constants.BROTLI_PARAM_SIZE_HINT]: data.length,
  } });
  if (packed.length >= data.length * 0.95) { console.log(`skip ${name} (no gain)`); continue; }
  await writeFile(`${path}.br`, packed);
  before += data.length; after += packed.length;
  console.log(`${name}: ${(data.length / 1048576).toFixed(1)} MB -> ${(packed.length / 1048576).toFixed(1)} MB`);
}
console.log(`total ${(before / 1048576).toFixed(1)} MB -> ${(after / 1048576).toFixed(1)} MB`);
