import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
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

const output = join(projectDirectory, "build_revision.json");
writeFileSync(output, `${JSON.stringify({ revision }, null, 2)}\n`);
console.log(`Stamped build revision ${revision}`);
