import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { createHash } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createLastRouteServer } from "./server.mjs";
import { MOD_LIMITS, validatePackManifest } from "./mod_packs.mjs";
import { buildPack, deployPack, localTransport } from "./deploy_mod_pack.mjs";

const quiet = { error() {}, log() {}, warn() {} };
const sha = (text) => createHash("sha256").update(text).digest("hex");

async function fixture(options = {}) {
  const root = await mkdtemp(join(tmpdir(), "mod-packs-"));
  const make = () => createLastRouteServer({
    accountStorePath: join(root, "accounts.json"),
    moderationStorePath: join(root, "moderation.json"),
    modPackStorePath: join(root, "mod_packs.json"),
    modDownloadBase: "https://files.example.test/lr3d/mods/",
    adminPassword: "server setup proof",
    accountRateLimitMax: 10_000, apiRateLimitMax: 10_000, modRateLimitMax: 10_000,
    logger: quiet, ...options,
  });
  let server = make();
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const app = {
    root,
    url: `http://127.0.0.1:${server.address().port}`,
    async restart() {
      server.close(); await once(server, "close");
      server = make(); server.listen(0, "127.0.0.1"); await once(server, "listening");
      app.url = `http://127.0.0.1:${server.address().port}`;
    },
    async close() { server.close(); await once(server, "close"); await rm(root, { recursive: true }); },
  };
  return app;
}

async function post(url, path, body) {
  const response = await fetch(url + path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  return { status: response.status, body: await response.json() };
}

async function get(url, path) {
  const response = await fetch(url + path);
  return { status: response.status, body: await response.json() };
}

async function signUp(url, username, extra = {}) {
  const result = await post(url, "/api/account/register", { username, password: "correct horse battery", ...extra });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result.body.sessionToken;
}

function manifest(extra = {}) {
  return {
    id: "neon_halls", name: "Neon Halls", version: "1.0.0", author: "KT",
    files: [
      { path: "pack.json", sha256: sha("{}"), size: 2 },
      { path: "maps/hall.tscn", sha256: sha("hall"), size: 4 },
    ],
    ...extra,
  };
}

test("manifest validation refuses traversal, bad ids, missing pack.json and oversized packs", () => {
  assert.ok(validatePackManifest(manifest()).pack);
  assert.equal(validatePackManifest(manifest({ id: "../etc" })).error, "INVALID_PACK_ID");
  assert.equal(validatePackManifest(manifest({ version: "1/../2" })).error, "INVALID_PACK_VERSION");
  for (const path of ["../x.gd", "/abs.gd", "a/../b.gd", "a\\b.gd", ".hidden", "a//b"]) {
    const bad = manifest({ files: [{ path: "pack.json", sha256: sha("{}"), size: 2 }, { path, sha256: sha("x"), size: 1 }] });
    assert.equal(validatePackManifest(bad).error, "INVALID_FILE_PATH", path);
  }
  assert.equal(validatePackManifest(manifest({ files: [{ path: "a.gd", sha256: sha("a"), size: 1 }] })).error, "PACK_JSON_MISSING");
  assert.equal(validatePackManifest(manifest({ files: [{ path: "pack.json", sha256: "nothex", size: 2 }] })).error, "INVALID_FILE_SHA256");
  const dupe = manifest({ files: [{ path: "pack.json", sha256: sha("{}"), size: 2 }, { path: "PACK.json", sha256: sha("{}"), size: 2 }] });
  assert.equal(validatePackManifest(dupe).error, "DUPLICATE_FILE_PATH");
  const big = manifest({ files: [{ path: "pack.json", sha256: sha("{}"), size: MOD_LIMITS.maxFileBytes + 1 }] });
  assert.equal(validatePackManifest(big).error, "FILE_TOO_LARGE");
  const many = Array.from({ length: 5 }, (_, i) => ({ path: `f${i}.bin`, sha256: sha(String(i)), size: MOD_LIMITS.maxFileBytes }));
  assert.equal(validatePackManifest(manifest({ files: [{ path: "pack.json", sha256: sha("{}"), size: 2 }, ...many] })).error, "PACK_TOO_LARGE");
});

test("index: anyone lists and reads; only an owner registers, blocks and unblocks; data survives a restart", async () => {
  const app = await fixture();
  try {
    assert.deepEqual((await get(app.url, "/api/mods/packs")).body, { ok: true, packs: [], downloadConfigured: true });
    const owner = await signUp(app.url, "KYTTU", { adminProof: "server setup proof" });
    const player = await signUp(app.url, "PLAYER");

    assert.equal((await post(app.url, "/api/admin/mods/register", { pack: manifest() })).status, 403);
    assert.equal((await post(app.url, "/api/admin/mods/register", { sessionToken: player, pack: manifest() })).status, 403);
    const registered = await post(app.url, "/api/admin/mods/register", { sessionToken: owner, pack: manifest() });
    assert.equal(registered.status, 200, JSON.stringify(registered.body));
    assert.equal(registered.body.pack.downloadBase, "https://files.example.test/lr3d/mods/neon_halls/1.0.0/");

    const again = await post(app.url, "/api/admin/mods/register", { sessionToken: owner, pack: manifest() });
    assert.equal(again.status, 409);
    assert.equal(again.body.code, "VERSION_EXISTS");
    await post(app.url, "/api/admin/mods/register", { sessionToken: owner, pack: manifest({ version: "1.1.0", name: "Neon Halls+" }) });

    const listed = await get(app.url, "/api/mods/packs");
    assert.equal(listed.body.packs.length, 1);
    assert.equal(listed.body.packs[0].version, "1.1.0", "the newest version is listed");
    assert.deepEqual(listed.body.packs[0].versions, ["1.1.0", "1.0.0"]);
    assert.equal(listed.body.packs[0].files.find((f) => f.path === "maps/hall.tscn").sha256, sha("hall"));
    assert.equal((await get(app.url, "/api/mods/packs/neon_halls?version=1.0.0")).body.pack.name, "Neon Halls");
    assert.equal((await get(app.url, "/api/mods/packs/nope_pack")).status, 404);
    assert.equal((await get(app.url, "/api/mods/packs/..%2Fetc")).status, 404);

    assert.equal((await post(app.url, "/api/admin/mods/block", { sessionToken: player, id: "neon_halls" })).status, 403);
    const blocked = await post(app.url, "/api/admin/mods/block", { sessionToken: owner, id: "neon_halls", reason: "crashes hosts" });
    assert.equal(blocked.body.pack.blocked, true);
    assert.equal(blocked.body.pack.blockedReason, "crashes hosts");

    await app.restart();
    const after = (await get(app.url, "/api/mods/packs/neon_halls")).body.pack;
    assert.equal(after.blocked, true, "block survives a restart");
    assert.equal(after.version, "1.1.0");
    const unblocked = await post(app.url, "/api/admin/mods/unblock", { sessionToken: owner, id: "neon_halls" });
    assert.equal(unblocked.body.pack.blocked, false);
    assert.equal(unblocked.body.pack.blockedReason, "");
  } finally {
    await app.close();
  }
});

test("mod reads have their own rate-limit bucket and the big register body is owner-route only", async () => {
  const app = await fixture({ modRateLimitMax: 3 });
  try {
    for (let i = 0; i < 3; i += 1) assert.equal((await get(app.url, "/api/mods/packs")).status, 200);
    const limited = await fetch(app.url + "/api/mods/packs");
    assert.equal(limited.status, 429);
    assert.ok(Number(limited.headers.get("retry-after")) >= 1);
    assert.equal((await get(app.url, "/api/health")).status, 200, "gameplay/API calls are not starved by mod polling");

    const owner = await signUp(app.url, "KYTTU", { adminProof: "server setup proof" });
    const files = [{ path: "pack.json", sha256: sha("{}"), size: 2 },
      ...Array.from({ length: 499 }, (_, i) => ({ path: `assets/textures/highres/part_${String(i).padStart(3, "0")}_variant.res`, sha256: sha(String(i)), size: 10 }))];
    const body = { sessionToken: owner, pack: manifest({ files }) };
    assert.ok(JSON.stringify(body).length > 64 * 1024, "the manifest is over the normal 64 KB body cap");
    assert.equal((await post(app.url, "/api/admin/mods/register", body)).status, 200);
    assert.equal((await post(app.url, "/api/admin/flags", { ...body })).status, 413, "other routes keep the 64 KB cap");
  } finally {
    await app.close();
  }
});

test("deploy script: dry run touches nothing; apply copies, verifies on the file server, registers; versions are not overwritten", async () => {
  const app = await fixture();
  const work = await mkdtemp(join(tmpdir(), "mod-deploy-"));
  try {
    const owner = await signUp(app.url, "KYTTU", { adminProof: "server setup proof" });
    const packDir = join(work, "neon_halls");
    mkdirSync(join(packDir, "maps"), { recursive: true });
    writeFileSync(join(packDir, "pack.json"), JSON.stringify({ id: "neon_halls", name: "Neon Halls", version: "2.0.0", author: "KT" }));
    writeFileSync(join(packDir, "maps", "hall.tscn"), "hall");
    writeFileSync(join(packDir, ".DS_Store"), "junk");
    const files = join(work, "vps2");
    const logs = [];

    const dry = await deployPack({ directory: packDir, transport: localTransport(), remoteRoot: files, indexUrl: app.url,
      sessionToken: owner, log: (l) => logs.push(l) });
    assert.equal(dry.applied, false);
    assert.equal(existsSync(files), false, "dry run copies nothing");
    assert.equal((await get(app.url, "/api/mods/packs")).body.packs.length, 0, "dry run registers nothing");
    assert.deepEqual(dry.pack.files.map((f) => f.path), ["maps/hall.tscn", "pack.json"], "dotfiles are not part of a pack");

    await assert.rejects(deployPack({ directory: packDir, transport: localTransport(), remoteRoot: files, indexUrl: app.url,
      sessionToken: "", apply: true, log() {} }), /LASTROUTE_OWNER_SESSION/);

    const done = await deployPack({ directory: packDir, transport: localTransport(), remoteRoot: files, indexUrl: app.url,
      sessionToken: owner, apply: true, log() {} });
    assert.equal(done.applied, true);
    assert.deepEqual(readdirSync(join(files, "neon_halls", "2.0.0")).sort(), ["maps", "pack.json"]);
    assert.deepEqual(readdirSync(join(files, "neon_halls")), ["2.0.0"], "no staging folder left behind");
    const listed = (await get(app.url, "/api/mods/packs/neon_halls")).body.pack;
    assert.equal(listed.files.find((f) => f.path === "maps/hall.tscn").sha256, sha("hall"));

    await assert.rejects(deployPack({ directory: packDir, transport: localTransport(), remoteRoot: files, indexUrl: app.url,
      sessionToken: owner, apply: true, log() {} }), /already exists/);

    // a file server that hands back different bytes must stop the deploy before anything is promoted or registered
    writeFileSync(join(packDir, "pack.json"), JSON.stringify({ id: "neon_halls", name: "Neon Halls", version: "2.0.1", author: "KT" }));
    const corrupt = { ...localTransport(), hashes: (_dir, paths) => new Map(paths.map((p) => [p, "0".repeat(64)])) };
    await assert.rejects(deployPack({ directory: packDir, transport: corrupt, remoteRoot: files, indexUrl: app.url,
      sessionToken: owner, apply: true, log() {} }), /upload check failed/);
    assert.deepEqual(readdirSync(join(files, "neon_halls")), ["2.0.0"], "the bad upload was discarded");
    assert.deepEqual((await get(app.url, "/api/mods/packs/neon_halls")).body.pack.versions, ["2.0.0"]);
  } finally {
    await rm(work, { recursive: true });
    await app.close();
  }
});

test("buildPack: a pack.json that lists a wrong hash for a file is refused", async () => {
  const work = await mkdtemp(join(tmpdir(), "mod-build-"));
  try {
    writeFileSync(join(work, "a.gd"), "extends Node");
    writeFileSync(join(work, "pack.json"), JSON.stringify({ id: "tiny_pack", name: "Tiny", version: "0.1", author: "KT",
      files: [{ path: "a.gd", sha256: sha("something else") }] }));
    assert.throws(() => buildPack(work), /does not match/);
  } finally {
    await rm(work, { recursive: true });
  }
});
