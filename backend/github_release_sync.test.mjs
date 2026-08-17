import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { syncGithubRelease } from "./github_release_sync.mjs";

function response(value, init = {}) {
  return new Response(typeof value === "string" || Buffer.isBuffer(value)
    ? value : JSON.stringify(value), init);
}

test("mirrors and verifies a stable GitHub debug release", async () => {
  const directory = await mkdtemp(join(tmpdir(), "last-route-release-"));
  const artifact = Buffer.from("test-debug-build");
  const sha256 = createHash("sha256").update(artifact).digest("hex");
  const manifest = {
    debug: {
      linux: {
        version: "0.0.1.0",
        revision: "a".repeat(40),
        file: "LastRoute-Linux-Debug.zip",
        sha256,
        required: true,
      },
    },
  };
  const release = {
    assets: [
      { name: "updates.debug.json", url: "https://api.github.test/assets/manifest" },
      { name: "LastRoute-Linux-Debug.zip", url: "https://api.github.test/assets/linux" },
    ],
  };
  let artifactRequests = 0;
  const fetchImpl = async (url) => {
    if (String(url).endsWith("/releases/tags/debug")) return response(release);
    if (url === "https://api.github.test/assets/manifest") return response(manifest);
    if (url === "https://api.github.test/assets/linux") {
      artifactRequests += 1;
      return response(artifact);
    }
    return response("missing", { status: 404 });
  };
  const manifestPath = join(directory, "updates.debug.json");
  const messages = [];
  try {
    let result = await syncGithubRelease({
      repository: "KyttuXD/LastRouteGodot",
      updateDirectory: directory,
      manifestPath,
      fetchImpl,
      logger: { log(message) { messages.push(message); } },
    });
    assert.deepEqual({ downloaded: result.downloaded, reused: result.reused }, { downloaded: 1, reused: 0 });
    assert.equal(result.revision, "a".repeat(40));
    assert.match(messages[0], /sync ready @ a{12}/);
    assert.deepEqual(await readFile(join(directory, "LastRoute-Linux-Debug.zip")), artifact);
    assert.deepEqual(JSON.parse(await readFile(manifestPath, "utf8")), manifest);

    result = await syncGithubRelease({
      repository: "KyttuXD/LastRouteGodot",
      updateDirectory: directory,
      manifestPath,
      fetchImpl,
      logger: { log(message) { messages.push(message); } },
    });
    assert.deepEqual({ downloaded: result.downloaded, reused: result.reused }, { downloaded: 0, reused: 1 });
    assert.equal(artifactRequests, 1);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("does not publish a manifest when an artifact fails verification", async () => {
  const directory = await mkdtemp(join(tmpdir(), "last-route-release-bad-"));
  const manifest = {
    debug: {
      linux: {
        version: "0.0.1.0",
        revision: "b".repeat(40),
        file: "linux.zip",
        sha256: "f".repeat(64),
      },
    },
  };
  const fetchImpl = async (url) => {
    if (String(url).endsWith("/releases/tags/debug")) return response({ assets: [
      { name: "updates.debug.json", url: "manifest" },
      { name: "linux.zip", url: "linux" },
    ] });
    if (url === "manifest") return response(manifest);
    if (url === "linux") return response("corrupt");
    return response("missing", { status: 404 });
  };
  const manifestPath = join(directory, "updates.debug.json");
  try {
    await assert.rejects(syncGithubRelease({
      repository: "KyttuXD/LastRouteGodot",
      updateDirectory: directory,
      manifestPath,
      fetchImpl,
      logger: { log() {} },
    }), /SHA-256 verification/);
    await assert.rejects(readFile(manifestPath), /ENOENT/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
