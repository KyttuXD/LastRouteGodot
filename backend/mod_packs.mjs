// Mod pack index (VPS 3). Lists the mod packs the game may download, with a sha256 and size for every file, and lets an
// owner block a pack. The files themselves are NEVER served from here: they live on VPS 2 under
//   <LASTROUTE_MOD_DOWNLOAD_BASE>/<pack_id>/<version>/<file path>      (e.g. https://<vps2>/lr3d/mods/neon_halls/1.2.0/pack.json)
// and the client checks every downloaded file against the sha256 listed here before it loads anything.
// Packs are registered by scripts/deploy_mod_pack.mjs after it has copied and verified the files on VPS 2.
// Matches the DATA lane's pack.json (id, name, version, author, files); see backend/README.md "Mod packs".

import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export const MOD_PACK_ID_PATTERN = /^[a-z0-9][a-z0-9_-]{2,47}$/;
export const MOD_VERSION_PATTERN = /^[0-9A-Za-z][0-9A-Za-z.+-]{0,31}$/;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
// relative paths only: plain segments of safe characters, no "..", no leading slash, no backslashes
const FILE_PATH_PATTERN = /^(?:[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}\/){0,7}[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$/;

export const MOD_LIMITS = Object.freeze({
  maxFileBytes: 64 * 1024 * 1024,     // one file
  maxPackBytes: 256 * 1024 * 1024,    // all files of one version
  maxFiles: 500,                      // files per version
  maxPacks: 2000,                     // packs in the index
  maxVersionsKept: 5,                 // older versions drop out of the index (their files stay on VPS 2 until cleaned)
  maxText: 120,                       // name / author
  maxDescription: 1000,
});

function text(value, max) {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, max);
}

export function validatePackManifest(input, limits = MOD_LIMITS) {
  const manifest = input && typeof input === "object" ? input : {};
  const id = String(manifest.id || "");
  const version = String(manifest.version || "");
  if (!MOD_PACK_ID_PATTERN.test(id)) return { error: "INVALID_PACK_ID" };
  if (!MOD_VERSION_PATTERN.test(version) || version.includes("..")) return { error: "INVALID_PACK_VERSION" };
  const name = text(manifest.name, limits.maxText);
  const author = text(manifest.author, limits.maxText);
  if (!name) return { error: "PACK_NAME_REQUIRED" };
  if (!author) return { error: "PACK_AUTHOR_REQUIRED" };
  if (!Array.isArray(manifest.files) || manifest.files.length === 0) return { error: "PACK_FILES_REQUIRED" };
  if (manifest.files.length > limits.maxFiles) return { error: "TOO_MANY_FILES" };
  const seen = new Set();
  const files = [];
  let total = 0;
  for (const entry of manifest.files) {
    const path = String(entry?.path || "");
    const sha256 = String(entry?.sha256 || "").toLowerCase();
    const size = Number(entry?.size);
    if (!FILE_PATH_PATTERN.test(path) || path.split("/").some((part) => part === "." || part === "..")) {
      return { error: "INVALID_FILE_PATH", path };
    }
    if (seen.has(path.toLowerCase())) return { error: "DUPLICATE_FILE_PATH", path };
    seen.add(path.toLowerCase());
    if (!SHA256_PATTERN.test(sha256)) return { error: "INVALID_FILE_SHA256", path };
    if (!Number.isSafeInteger(size) || size < 0) return { error: "INVALID_FILE_SIZE", path };
    if (size > limits.maxFileBytes) return { error: "FILE_TOO_LARGE", path };
    total += size;
    files.push({ path, sha256, size });
  }
  if (total > limits.maxPackBytes) return { error: "PACK_TOO_LARGE" };
  if (!seen.has("pack.json")) return { error: "PACK_JSON_MISSING" };
  return {
    pack: {
      id, version, name, author,
      description: text(manifest.description, limits.maxDescription),
      gameVersion: text(manifest.game_version ?? manifest.gameVersion, 32),
      files: files.sort((a, b) => a.path.localeCompare(b.path)),
      totalBytes: total,
    },
  };
}

export function createModPacks({
  storePath = null,
  downloadBase = "",
  limits = MOD_LIMITS,
  now = Date.now,
  logger = console,
} = {}) {
  const base = String(downloadBase || "").replace(/\/+$/, "");
  const packs = new Map();   // id -> { id, blocked, blockedReason, blockedBy, blockedAt, versions: [newest first] }

  if (storePath) {
    try {
      const stored = JSON.parse(readFileSync(storePath, "utf8"));
      for (const value of Array.isArray(stored?.packs) ? stored.packs : []) {
        if (value && MOD_PACK_ID_PATTERN.test(String(value.id || "")) && Array.isArray(value.versions)) {
          packs.set(value.id, value);
        }
      }
    } catch (error) {
      if (error?.code !== "ENOENT") logger.error?.(`Mod pack store read failed: ${error?.message || error}`);
    }
  }

  function persist() {
    if (!storePath) return;
    try {
      mkdirSync(dirname(storePath), { recursive: true });
      const temporaryPath = `${storePath}.tmp`;
      writeFileSync(temporaryPath, JSON.stringify({ version: 1, packs: [...packs.values()] }));
      renameSync(temporaryPath, storePath);
    } catch (error) {
      logger.error?.(`Mod pack store write failed: ${error?.message || error}`);
    }
  }

  function publicView(record, version = null) {
    const chosen = version ? record.versions.find((v) => v.version === version) : record.versions[0];
    if (!chosen) return null;
    return {
      id: record.id,
      name: chosen.name,
      version: chosen.version,
      author: chosen.author,
      description: chosen.description,
      gameVersion: chosen.gameVersion,
      blocked: Boolean(record.blocked),
      blockedReason: record.blocked ? record.blockedReason || "" : "",
      files: chosen.files,
      totalBytes: chosen.totalBytes,
      downloadBase: base ? `${base}/${record.id}/${chosen.version}/` : "",
      registeredAt: chosen.registeredAt,
      versions: record.versions.map((v) => v.version),
    };
  }

  function list() {
    const items = [...packs.values()].map((record) => publicView(record)).filter(Boolean)
      .sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
    return [200, { ok: true, packs: items, downloadConfigured: Boolean(base) }];
  }

  function get(id, version = null) {
    const record = packs.get(String(id || ""));
    const view = record && publicView(record, version ? String(version) : null);
    if (!view) return [404, { ok: false, code: "PACK_NOT_FOUND", error: "No such mod pack" }];
    return [200, { ok: true, pack: view }];
  }

  function register(body, owner) {
    const checked = validatePackManifest(body?.pack, limits);
    if (checked.error) return [400, { ok: false, code: checked.error, error: checked.error, path: checked.path }];
    const pack = checked.pack;
    let record = packs.get(pack.id);
    if (!record) {
      if (packs.size >= limits.maxPacks) return [507, { ok: false, code: "INDEX_FULL", error: "Mod pack index is full" }];
      record = { id: pack.id, blocked: false, versions: [] };
    }
    if (record.versions.some((v) => v.version === pack.version) && !body?.replace) {
      return [409, { ok: false, code: "VERSION_EXISTS", error: "That version is already registered; bump the version" }];
    }
    const entry = { ...pack, registeredAt: new Date(now()).toISOString(), registeredBy: owner };
    record.versions = [entry, ...record.versions.filter((v) => v.version !== pack.version)].slice(0, limits.maxVersionsKept);
    packs.set(pack.id, record);
    persist();
    return [200, { ok: true, pack: publicView(record) }];
  }

  function setBlocked(body, owner, blocked) {
    const record = packs.get(String(body?.id || ""));
    if (!record) return [404, { ok: false, code: "PACK_NOT_FOUND", error: "No such mod pack" }];
    record.blocked = blocked;
    record.blockedReason = blocked ? text(body?.reason, 200) : "";
    record.blockedBy = blocked ? owner : "";
    record.blockedAt = blocked ? new Date(now()).toISOString() : "";
    persist();
    return [200, { ok: true, pack: publicView(record) }];
  }

  return {
    list,
    get,
    register,
    block: (body, owner) => setBlocked(body, owner, true),
    unblock: (body, owner) => setBlocked(body, owner, false),
    get size() { return packs.size; },
  };
}
