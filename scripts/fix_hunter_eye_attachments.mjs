#!/usr/bin/env node

// Correct the two A-Z eye locator bones in both the editable Blockbench source
// and the checked-in GLB used by Godot. The face texture is the Minecraft 8x8
// front face: both checker irises occupy rows 13-14, whose centre is texture
// row 14 / Blockbench Y=100 on the shared 28-unit-tall hunter head.

import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CHARACTER_DIR = path.join(ROOT, "art", "props-3d", "characters");
const A_Z_IDS = [
  "aki", "briselle", "ceryth", "dovelle", "eirys", "ferryn", "glyra",
  "haelith", "ilyra", "jyvra", "kathy", "loxelle", "mavrine", "nyxie",
  "opalie", "porcelle", "quirith", "ravelle", "solyth", "thessine",
  "umbriel", "verrine", "wynelle", "xivvy", "ysolde", "zephyra",
];

const BB_Y = 100.0;
const BB_Z = -15.1;
const GLB_TRANSLATION = {
  "L-Eye-Attachment": [-0.1171875, 0.203125, -0.2515625],
  "R-Eye-Attachment": [0.1171875, 0.203125, -0.2515625],
};
const JSON_CHUNK = 0x4e4f534a;

function fixBlockbench(file) {
  const model = JSON.parse(fs.readFileSync(file, "utf8"));
  let count = 0;
  for (const group of Object.values(model.groups ?? {})) {
    if (!(group.name in GLB_TRANSLATION)) continue;
    const x = group.name.startsWith("L-") ? -7.5 : 7.5;
    group.origin = [x, BB_Y, BB_Z];
    count += 1;
  }
  if (count !== 2) throw new Error(`${file}: expected two eye attachment groups`);
  fs.writeFileSync(file, JSON.stringify(model));
}

function fixGlb(file) {
  const source = fs.readFileSync(file);
  if (source.readUInt32LE(0) !== 0x46546c67) throw new Error(`${file}: not a GLB`);
  const chunks = [];
  let offset = 12;
  let corrected = 0;
  while (offset < source.length) {
    const length = source.readUInt32LE(offset);
    const type = source.readUInt32LE(offset + 4);
    let data = source.subarray(offset + 8, offset + 8 + length);
    if (type === JSON_CHUNK) {
      const gltf = JSON.parse(data.toString("utf8").trimEnd());
      for (const node of gltf.nodes ?? []) {
        if (!(node.name in GLB_TRANSLATION)) continue;
        node.translation = GLB_TRANSLATION[node.name];
        corrected += 1;
      }
      const json = Buffer.from(JSON.stringify(gltf), "utf8");
      const paddedLength = (json.length + 3) & ~3;
      data = Buffer.alloc(paddedLength, 0x20);
      json.copy(data);
    } else {
      data = Buffer.from(data);
    }
    chunks.push({type, data});
    offset += 8 + length;
  }
  if (corrected !== 2) throw new Error(`${file}: expected two eye attachment nodes`);
  const totalLength = 12 + chunks.reduce((sum, chunk) => sum + 8 + chunk.data.length, 0);
  const output = Buffer.alloc(totalLength);
  output.writeUInt32LE(0x46546c67, 0);
  output.writeUInt32LE(2, 4);
  output.writeUInt32LE(totalLength, 8);
  offset = 12;
  for (const chunk of chunks) {
    output.writeUInt32LE(chunk.data.length, offset);
    output.writeUInt32LE(chunk.type, offset + 4);
    chunk.data.copy(output, offset + 8);
    offset += 8 + chunk.data.length;
  }
  fs.writeFileSync(file, output);
}

for (const id of A_Z_IDS) {
  fixBlockbench(path.join(CHARACTER_DIR, `${id}.bbmodel`));
  fixGlb(path.join(CHARACTER_DIR, `${id}.glb`));
}
console.log(`Corrected eye attachment bones for ${A_Z_IDS.length} A-Z hunters.`);
