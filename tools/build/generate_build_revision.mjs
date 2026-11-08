import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const explicit = String(process.env.LASTROUTE_BUILD_REVISION || "").trim().toLowerCase();
const revision = explicit || execFileSync("git", ["rev-parse", "HEAD"], {
  cwd: projectDirectory,
  encoding: "utf8",
}).trim().toLowerCase();

if (!/^[a-f0-9]{7,40}$/.test(revision)) throw new Error("Build revision must be a Git commit SHA");
if (!explicit && !/^(1|true|yes|on)$/i.test(String(process.env.LASTROUTE_ALLOW_DIRTY_BUILD || ""))) {
  const dirty = execFileSync("git", ["status", "--porcelain", "--untracked-files=no"], {
    cwd: projectDirectory,
    encoding: "utf8",
  }).trim();
  if (dirty) throw new Error("Commit tracked changes before exporting, or explicitly set LASTROUTE_ALLOW_DIRTY_BUILD=true");
}

// The build number (commits up to this revision) orders phone and Quest updates and becomes their Android versionCode
// in the publish copy (tools/android/build_apk.sh). Desktop builds ignore it. LASTROUTE_BUILD_NUMBER overrides it.
const explicitNumber = String(process.env.LASTROUTE_BUILD_NUMBER || "").trim();
let build = /^\d+$/.test(explicitNumber) ? Number(explicitNumber) : 0;
if (!build) {
  try {
    build = Number(execFileSync("git", ["rev-list", "--count", revision], {
      cwd: projectDirectory,
      encoding: "utf8",
    }).trim()) || 0;
  } catch {
    build = 0;
  }
}

const output = join(projectDirectory, "build_revision.json");
writeFileSync(output, `${JSON.stringify(build ? { revision, build } : { revision }, null, 2)}\n`);
console.log(`Stamped build revision ${revision}${build ? ` (build ${build})` : ""}`);
