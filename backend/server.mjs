import { createReadStream, existsSync, readFileSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { createAccountService } from "./account_service.mjs";
import { createRoomService } from "./room_service.mjs";

const ENET_CODE_PATTERN = /^[A-HJ-NP-Z2-9]{5}$/;
const MAX_BODY_BYTES = 64 * 1024;
const MIME_TYPES = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".mp3", "audio/mpeg"],
  [".ogg", "audio/ogg"],
  [".png", "image/png"],
  [".svg", "image/svg+xml; charset=utf-8"],
  [".wasm", "application/wasm"],
  [".wav", "audio/wav"],
  [".webm", "video/webm"],
]);

function responseHeaders() {
  return {
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, HEAD, POST, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}

function json(response, status, value) {
  if (status === 204) {
    response.writeHead(status, responseHeaders());
    response.end();
    return;
  }
  const body = JSON.stringify(value);
  response.writeHead(status, {
    ...responseHeaders(),
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  response.end(body);
}

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw Object.assign(new Error("REQUEST BODY TOO LARGE"), { status: 413 });
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  try {
    const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") throw new Error();
    return parsed;
  } catch {
    throw Object.assign(new Error("INVALID JSON BODY"), { status: 400 });
  }
}

function normalizeEnetCode(value) {
  const code = String(value || "").trim().toUpperCase();
  return ENET_CODE_PATTERN.test(code) ? code : "";
}

function cleanAddress(value) {
  const address = String(value || "").trim();
  if (address.startsWith("::ffff:")) return address.slice(7);
  if (address === "::1") return "127.0.0.1";
  return address;
}

function requesterAddress(request, trustProxy) {
  if (trustProxy) {
    const forwarded = String(request.headers["x-forwarded-for"] || "").split(",")[0].trim();
    if (forwarded) return cleanAddress(forwarded);
  }
  return cleanAddress(request.socket.remoteAddress);
}

function publicEnetRoom(room, timestamp) {
  return {
    code: room.code,
    address: room.address,
    port: room.port,
    players: room.players,
    sessionActive: room.sessionActive,
    expiresIn: Math.max(0, Math.ceil((room.expiresAt - timestamp) / 1000)),
  };
}

function publicUpdateManifest(updates, channel, platform) {
  const entry = updates?.[channel]?.[platform];
  if (!entry || typeof entry !== "object") return null;
  const version = String(entry.version || "").trim().replace(/^v/i, "");
  const url = String(entry.url || "").trim();
  const file = String(entry.file || "").trim();
  const sha256 = String(entry.sha256 || "").trim().toLowerCase();
  const relativeUrl = /^[A-Za-z0-9][A-Za-z0-9._-]{0,190}$/.test(file)
    ? `/api/updates/files/${encodeURIComponent(file)}`
    : "";
  if (!/^\d+(?:\.\d+){2,3}$/.test(version) || (!url.startsWith("https://") && !relativeUrl)) return null;
  if (!/^[a-f0-9]{64}$/.test(sha256)) return null;
  return {
    version,
    url: url.startsWith("https://") ? url : relativeUrl,
    sha256,
    notes: String(entry.notes || "").slice(0, 2000),
    required: Boolean(entry.required),
  };
}

function publishedUpdatePath(updates, encodedName) {
  let name;
  try {
    name = decodeURIComponent(encodedName);
  } catch {
    return "";
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,190}$/.test(name)) return "";
  for (const channel of ["debug", "release"]) {
    for (const platform of ["linux", "windows", "macos", "web", "steamvr", "quest"]) {
      const entry = updates?.[channel]?.[platform];
      if (entry?.file === name && publicUpdateManifest(updates, channel, platform)) {
        return `/${name}`;
      }
    }
  }
  return "";
}

function safeEqual(leftValue, rightValue) {
  const left = Buffer.from(String(leftValue || ""));
  const right = Buffer.from(String(rightValue || ""));
  const length = Math.max(left.length, right.length, 1);
  const paddedLeft = Buffer.alloc(length);
  const paddedRight = Buffer.alloc(length);
  left.copy(paddedLeft);
  right.copy(paddedRight);
  return timingSafeEqual(paddedLeft, paddedRight) && left.length === right.length;
}

function tryStaticFile(request, response, publicDirectory, pathname) {
  if (!publicDirectory || !new Set(["GET", "HEAD"]).has(request.method)) return false;
  let decoded;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return false;
  }
  const candidate = resolve(publicDirectory, `.${decoded === "/" ? "/index.html" : decoded}`);
  const relativePath = relative(publicDirectory, candidate);
  if (!relativePath || relativePath.startsWith(`..${sep}`) || relativePath === "..") return false;
  let filePath = candidate;
  try {
    if (statSync(filePath).isDirectory()) filePath = join(filePath, "index.html");
    if (!statSync(filePath).isFile()) return false;
  } catch {
    return false;
  }
  response.writeHead(200, {
    ...responseHeaders(),
    "content-type": MIME_TYPES.get(extname(filePath).toLowerCase()) || "application/octet-stream",
    "content-length": statSync(filePath).size,
  });
  if (request.method === "HEAD") response.end();
  else createReadStream(filePath).pipe(response);
  return true;
}

export function createLastRouteServer({
  enetRoomTtlMs = 60_000,
  roomTtlMs = 300_000,
  playerTtlMs = 120_000,
  accountStorePath = null,
  publicDirectory = null,
  updateDirectory = null,
  adminPassword = "",
  updates = {},
  trustProxy = false,
  now = Date.now,
  logger = console,
} = {}) {
  const enetRooms = new Map();
  const roomService = createRoomService({ now, roomTtlMs, playerTtlMs });
  const accountService = createAccountService({ storePath: accountStorePath, now, logger });
  const devTokens = new Set();
  let reloadId = 0;

  function pruneEnetRooms() {
    const timestamp = now();
    for (const [code, room] of enetRooms) if (room.expiresAt <= timestamp) enetRooms.delete(code);
  }

  function developerRequest(body) {
    if (body?.devToken && devTokens.has(String(body.devToken))) return true;
    if (adminPassword && safeEqual(body?.password, adminPassword)) return true;
    return /yttu/i.test(accountService.sessionUsername(body?.sessionToken) || "");
  }

  function issueDevToken() {
    const token = randomBytes(24).toString("hex");
    devTokens.add(token);
    return token;
  }

  const server = createServer(async (request, response) => {
    if (request.method === "OPTIONS") return json(response, 204, {});
    pruneEnetRooms();
    const url = new URL(request.url || "/", "http://last-route.invalid");

    if (request.method === "GET" && url.pathname === "/api/health") {
      return json(response, 200, {
        ok: true,
        runtime: "node",
        service: "last-route-backend",
        port: request.socket.localPort,
        rooms: enetRooms.size,
        webRooms: roomService.rooms.size,
        reloadId,
        now: new Date(now()).toISOString(),
      });
    }

    const updateLookup = url.pathname.match(/^\/api\/updates\/(debug|release)\/(linux|windows|macos|web|steamvr|quest)$/);
    if (request.method === "GET" && updateLookup) {
      const update = publicUpdateManifest(updates, updateLookup[1], updateLookup[2]);
      if (!update) return json(response, 404, { ok: false, error: "NO UPDATE PUBLISHED" });
      return json(response, 200, { ok: true, channel: updateLookup[1], platform: updateLookup[2], update });
    }

    const updateFile = url.pathname.match(/^\/api\/updates\/files\/([^/]+)$/);
    if (new Set(["GET", "HEAD"]).has(request.method) && updateFile) {
      const assetPath = publishedUpdatePath(updates, updateFile[1]);
      if (assetPath && tryStaticFile(request, response, updateDirectory, assetPath)) return;
      return json(response, 404, { ok: false, error: "UPDATE FILE NOT FOUND" });
    }

    const enetResolve = url.pathname.match(/^\/api\/enet\/rooms\/([^/]+)$/);
    if (request.method === "GET" && enetResolve) {
      const code = normalizeEnetCode(decodeURIComponent(enetResolve[1]));
      const room = code ? enetRooms.get(code) : null;
      if (!room) return json(response, 404, { ok: false, error: "ROOM NOT FOUND" });
      return json(response, 200, { ok: true, room: publicEnetRoom(room, now()) });
    }

    if (request.method !== "POST") {
      if (tryStaticFile(request, response, publicDirectory, url.pathname)) return;
      if (request.method === "GET" && url.pathname === "/") {
        return json(response, 200, { ok: true, service: "Last Route backend", health: "/api/health", staticFiles: Boolean(publicDirectory) });
      }
      return json(response, 404, { ok: false, code: "NOT_FOUND", error: "Not found" });
    }

    let body;
    try {
      body = await readJson(request);
    } catch (error) {
      return json(response, error.status || 400, { ok: false, error: error.message });
    }

    if (url.pathname === "/api/enet/rooms/register") {
      const code = normalizeEnetCode(body.code);
      const port = Number(body.port);
      if (!code) return json(response, 400, { ok: false, error: "INVALID ROOM CODE" });
      if (!Number.isInteger(port) || port < 1 || port > 65_535) return json(response, 400, { ok: false, error: "INVALID ENET PORT" });
      if (enetRooms.has(code)) return json(response, 409, { ok: false, error: "ROOM CODE ALREADY REGISTERED" });
      const token = randomBytes(24).toString("base64url");
      const room = {
        code,
        token,
        address: requesterAddress(request, trustProxy),
        port,
        players: Math.trunc(finitePlayers(body.players, 1)),
        sessionActive: Boolean(body.sessionActive),
        expiresAt: now() + enetRoomTtlMs,
      };
      enetRooms.set(code, room);
      return json(response, 201, { ok: true, token, room: publicEnetRoom(room, now()) });
    }

    if (url.pathname === "/api/enet/rooms/heartbeat") {
      const room = enetRooms.get(normalizeEnetCode(body.code));
      if (!room) return json(response, 404, { ok: false, error: "ROOM NOT FOUND" });
      if (!safeEqual(body.token, room.token)) return json(response, 403, { ok: false, error: "INVALID HOST TOKEN" });
      room.players = Math.trunc(finitePlayers(body.players, room.players));
      room.sessionActive = Boolean(body.sessionActive);
      room.expiresAt = now() + enetRoomTtlMs;
      return json(response, 200, { ok: true, room: publicEnetRoom(room, now()) });
    }

    if (url.pathname === "/api/enet/rooms/unregister") {
      const code = normalizeEnetCode(body.code);
      const room = enetRooms.get(code);
      if (!room) return json(response, 200, { ok: true, removed: false });
      if (!safeEqual(body.token, room.token)) return json(response, 403, { ok: false, error: "INVALID HOST TOKEN" });
      enetRooms.delete(code);
      return json(response, 200, { ok: true, removed: true });
    }

    if (url.pathname === "/api/dev/login") {
      if (!adminPassword) return json(response, 503, { ok: false, code: "DEV_LOGIN_DISABLED", error: "Developer login is not configured" });
      if (!safeEqual(body.password, adminPassword)) return json(response, 401, { ok: false, code: "INVALID_DEV_PASSWORD", error: "Invalid developer password" });
      return json(response, 200, { ok: true, developer: true, admin: true, devToken: issueDevToken() });
    }
    if (url.pathname === "/api/dev/reload") {
      if (!developerRequest(body)) return json(response, 401, { ok: false, code: "NOT_AUTHORIZED", error: "Developer proof required" });
      reloadId += 1;
      return json(response, 200, { ok: true, reloadId });
    }

    let result;
    if (url.pathname === "/api/rooms/join") result = roomService.joinRoom(body);
    else if (url.pathname === "/api/rooms/state") result = roomService.updateRoom(body);
    else if (url.pathname === "/api/rooms/settings") result = roomService.updateRoomSettings(body);
    else if (url.pathname === "/api/rooms/start") result = roomService.startRoomRound(body);
    else if (url.pathname === "/api/rooms/default-start") result = roomService.startDefaultRoute(body);
    else if (url.pathname === "/api/rooms/office-start") result = roomService.startOfficeSolo(body);
    else if (url.pathname === "/api/rooms/abandon") result = roomService.abandonRoute(body);
    else if (url.pathname === "/api/rooms/custom-map") result = roomService.setCustomMap(body);
    else if (url.pathname === "/api/rooms/dialog-start") result = roomService.startDialog(body);
    else if (url.pathname === "/api/rooms/dialog-advance") result = roomService.advanceDialog(body);
    else if (url.pathname === "/api/rooms/leave") result = roomService.leaveRoom(body);
    else if (url.pathname === "/api/account/register") {
      result = await accountService.register(body, { allowDeveloperNames: developerRequest(body) });
      if (result[1]?.ok && result[1].admin) result[1].devToken = issueDevToken();
    } else if (url.pathname === "/api/account/login") {
      result = await accountService.login(body);
      if (result[1]?.ok && result[1].admin) result[1].devToken = issueDevToken();
    } else if (url.pathname === "/api/account/password") result = await accountService.changePassword(body);
    else if (url.pathname === "/api/account/rename") result = accountService.rename(body, { allowDeveloperNames: developerRequest(body) });
    else if (url.pathname === "/api/account/save") result = accountService.save(body);
    else if (url.pathname === "/api/account/load") result = accountService.loadProgress(body);
    else if (url.pathname === "/api/account/logout") result = accountService.logout(body);
    else result = [404, { ok: false, code: "UNKNOWN_ENDPOINT", error: "Unknown endpoint" }];

    if (result[1]?.room && !Object.hasOwn(result[1], "ok")) result[1].reloadId = reloadId;
    return json(response, result[0], result[1]);
  });

  const timer = setInterval(() => {
    pruneEnetRooms();
    roomService.cleanup();
  }, Math.max(1000, Math.min(enetRoomTtlMs, playerTtlMs, 15_000)));
  timer.unref();
  server.on("close", () => clearInterval(timer));
  return server;
}

function finitePlayers(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(1, Math.min(16, number)) : fallback;
}

// Retain the old export name so existing Godot/backend smoke tests keep working.
export function createDirectoryServer({ roomTtlMs, ...options } = {}) {
  return createLastRouteServer({ ...options, enetRoomTtlMs: roomTtlMs ?? options.enetRoomTtlMs });
}

function environmentPath(name) {
  const value = String(process.env[name] || "").trim();
  return value ? resolve(process.cwd(), value) : null;
}

export function startLastRouteServerFromEnvironment() {
  const port = Number(process.env.PORT || process.env.SERVER_PORT) || 1101;
  const host = process.env.HOST || "0.0.0.0";
  const dataDirectory = environmentPath("LASTROUTE_DATA_DIR") || environmentPath("KYTTU_DATA_DIR") || resolve(process.cwd(), "data");
  const accountStorePath = environmentPath("LASTROUTE_ACCOUNT_STORE") || environmentPath("KYTTU_ACCOUNT_STORE_PATH") || join(dataDirectory, "accounts.json");
  const publicDirectory = environmentPath("LASTROUTE_PUBLIC_DIR");
  const updateManifestPath = environmentPath("LASTROUTE_UPDATE_MANIFEST");
  const updateDirectory = environmentPath("LASTROUTE_UPDATE_DIR");
  let updates = {};
  if (updateManifestPath && existsSync(updateManifestPath)) {
    try {
      updates = JSON.parse(readFileSync(updateManifestPath, "utf8"));
    } catch (error) {
      console.error(`Could not read update manifest ${updateManifestPath}: ${error.message}`);
    }
  }
  const enetRoomTtlMs = Math.max(15, Number(process.env.ENET_ROOM_TTL_SECONDS) || 60) * 1000;
  const server = createLastRouteServer({
    enetRoomTtlMs,
    accountStorePath,
    publicDirectory: publicDirectory && existsSync(publicDirectory) ? publicDirectory : null,
    updateDirectory: updateDirectory && existsSync(updateDirectory) ? updateDirectory : null,
    updates,
    adminPassword: String(process.env.LASTROUTE_ADMIN_PASSWORD || process.env.KYTTU_DEV_PASSWORD || ""),
    trustProxy: /^(1|true|yes|on)$/i.test(String(process.env.TRUST_PROXY || "")),
  });
  server.listen(port, host, () => loggerStartup(host, port, accountStorePath,
    publicDirectory, updateManifestPath, updateDirectory));
  const shutdown = (signal) => {
    console.log(`${signal}: closing Last Route backend`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.once("SIGINT", () => shutdown("SIGINT"));
  process.once("SIGTERM", () => shutdown("SIGTERM"));
  return server;
}

function loggerStartup(host, port, accountStorePath, publicDirectory, updateManifestPath, updateDirectory) {
  console.log(`Last Route backend listening on http://${host}:${port}`);
  console.log(`Account data: ${accountStorePath}`);
  if (publicDirectory) console.log(`Static files: ${publicDirectory}`);
  if (updateManifestPath) console.log(`Update manifest: ${updateManifestPath}`);
  if (updateDirectory) console.log(`Update files: ${updateDirectory}`);
}

const entry = process.argv[1] ? resolve(process.argv[1]) : "";
if (entry && fileURLToPath(import.meta.url) === entry) {
  startLastRouteServerFromEnvironment();
}
