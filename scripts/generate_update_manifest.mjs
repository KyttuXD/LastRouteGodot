import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const buildDirectory = join(projectDirectory, "builds");
const buildSource = readFileSync(join(projectDirectory, "src/config/build.gd"), "utf8");
const version = buildSource.match(/const VERSION := "(\d+(?:\.\d+){2,3})"/)?.[1];
if (!version) throw new Error("Could not read Build.VERSION");

const artifacts = {
  linux: "LastRoute-Linux-Debug.zip",
  windows: "LastRoute-Windows-Debug.zip",
  macos: "LastRoute-macOS-Debug.zip",
  web: "LastRoute-Web-Debug.zip",
  steamvr: "LastRoute-Windows-SteamVR-Debug.zip",
  quest: "LastRoute-Quest-Debug.apk",
};

const debug = {};
for (const [platform, file] of Object.entries(artifacts)) {
  const path = join(buildDirectory, file);
  if (!existsSync(path)) continue;
  debug[platform] = {
    version,
    file,
    sha256: createHash("sha256").update(readFileSync(path)).digest("hex"),
    notes: "Debug multiplayer and platform test build.",
    required: false,
  };
}

const output = join(buildDirectory, "updates.debug.json");
writeFileSync(output, `${JSON.stringify({ debug }, null, 2)}\n`);
console.log(`Wrote ${output} with ${Object.keys(debug).length} artifact(s)`);
