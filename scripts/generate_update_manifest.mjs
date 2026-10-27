import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const buildDirectory = join(projectDirectory, "builds");
const buildSource = readFileSync(join(projectDirectory, "src/config/build.gd"), "utf8");
const version = buildSource.match(/const VERSION := "(\d+(?:\.\d+){2,3})"/)?.[1];
if (!version) throw new Error("Could not read Build.VERSION");
const revisionSource = JSON.parse(readFileSync(join(projectDirectory, "build_revision.json"), "utf8"));
const revision = String(revisionSource.revision || "").trim().toLowerCase();
if (!/^[a-f0-9]{7,40}$/.test(revision)) throw new Error("Could not read the stamped Git revision");

const artifacts = {
  linux: "KyttusLab-Linux-Debug.zip",
  windows: "KyttusLab-Windows-Debug.zip",
  windows_legacy: "KyttusLab-Windows-Legacy-Debug.zip",
  macos: "KyttusLab-macOS-Debug.zip",
  web: "KyttusLab-Web-Debug.zip",
  steamvr: "KyttusLab-Windows-SteamVR-Debug.zip",
  quest: "KyttusLab-Quest-Debug.apk",
};

const debug = {};
for (const [platform, file] of Object.entries(artifacts)) {
  const path = join(buildDirectory, file);
  if (!existsSync(path)) continue;
  const bytes = readFileSync(path);
  debug[platform] = {
    version,
    revision,
    file,
    bytes: bytes.byteLength,
    sha256: createHash("sha256").update(bytes).digest("hex"),
    notes: "Debug multiplayer and platform test build.",
    required: true,
  };
}

const output = join(buildDirectory, "updates.debug.json");
writeFileSync(output, `${JSON.stringify({ debug }, null, 2)}\n`);
console.log(`Wrote ${output} with ${Object.keys(debug).length} artifact(s)`);
