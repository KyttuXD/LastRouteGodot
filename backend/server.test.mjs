import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createDirectoryServer, createLastRouteServer } from "./server.mjs";

async function fixture(options = {}) {
  const server = createDirectoryServer(options);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  return {
    server,
    url: `http://127.0.0.1:${address.port}`,
    close: async () => {
      server.close();
      await once(server, "close");
    },
  };
}

test("health, register, resolve, heartbeat and unregister", async () => {
  const app = await fixture();
  try {
    let response = await fetch(`${app.url}/api/health`);
    assert.equal(response.status, 200);
    const health = await response.json();
    assert.equal(health.rooms, 0);
    assert.deepEqual(health.updates, {});

    response = await fetch(`${app.url}/api/enet/rooms/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "ABCDE", port: 8421, players: 2 }),
    });
    assert.equal(response.status, 201);
    const registration = await response.json();
    assert.ok(registration.token);
    assert.equal(registration.room.address, "127.0.0.1");

    response = await fetch(`${app.url}/api/enet/rooms/ABCDE`);
    const resolved = await response.json();
    assert.deepEqual(
      { address: resolved.room.address, port: resolved.room.port, players: resolved.room.players },
      { address: "127.0.0.1", port: 8421, players: 2 },
    );
    assert.equal("token" in resolved.room, false);

    response = await fetch(`${app.url}/api/enet/rooms/heartbeat`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "ABCDE", token: registration.token, players: 3, sessionActive: true }),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).room.sessionActive, true);

    response = await fetch(`${app.url}/api/enet/rooms/unregister`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "ABCDE", token: registration.token }),
    });
    assert.equal(response.status, 200);
    response = await fetch(`${app.url}/api/enet/rooms/ABCDE`);
    assert.equal(response.status, 404);
  } finally {
    await app.close();
  }
});

test("rejects collisions, invalid input and forged host tokens", async () => {
  const app = await fixture();
  try {
    const register = () => fetch(`${app.url}/api/enet/rooms/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "Q2W3E", port: 8421 }),
    });
    let response = await register();
    assert.equal(response.status, 201);
    response = await register();
    assert.equal(response.status, 409);
    response = await fetch(`${app.url}/api/enet/rooms/heartbeat`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "Q2W3E", token: "forged" }),
    });
    assert.equal(response.status, 403);
    response = await fetch(`${app.url}/api/enet/rooms/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "O0I1L", port: 70000 }),
    });
    assert.equal(response.status, 400);
  } finally {
    await app.close();
  }
});

test("rooms expire without a heartbeat", async () => {
  let current = 10_000;
  const app = await fixture({ roomTtlMs: 1000, now: () => current });
  try {
    await fetch(`${app.url}/api/enet/rooms/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "ASDFG", port: 8421 }),
    });
    current += 1001;
    const response = await fetch(`${app.url}/api/enet/rooms/ASDFG`);
    assert.equal(response.status, 404);
  } finally {
    await app.close();
  }
});

async function post(url, path, body) {
  const response = await fetch(`${url}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return { response, body: await response.json() };
}

test("legacy room API joins players and enforces host/session ownership", async () => {
  const app = await fixture();
  try {
    let result = await post(app.url, "/api/rooms/join", { room: "ROUTE1", playerId: "host-1", name: "Host" });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.isHost, true);
    assert.equal(result.body.spawnIndex, 0);
    const hostToken = result.body.sessionToken;

    result = await post(app.url, "/api/rooms/join", { room: "ROUTE1", playerId: "guest-1", name: "Guest" });
    assert.equal(result.body.isHost, false);
    assert.equal(result.body.players[0].name, "HOST");
    const guestToken = result.body.sessionToken;

    result = await post(app.url, "/api/rooms/settings", {
      room: "ROUTE1", playerId: "guest-1", sessionToken: guestToken, settings: { difficulty: "nightmare" },
    });
    assert.equal(result.response.status, 403);
    assert.equal(result.body.code, "HOST_ONLY");

    result = await post(app.url, "/api/rooms/settings", {
      room: "ROUTE1", playerId: "host-1", sessionToken: hostToken, settings: { difficulty: "nightmare" },
    });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.settings.difficulty, "nightmare");

    result = await post(app.url, "/api/rooms/state", {
      room: "ROUTE1",
      playerId: "guest-1",
      sessionToken: guestToken,
      state: { x: 12.5, y: -4, mode: "walk", appearanceId: "ramen_noodles" },
      discoveryClaims: ["1,2", "1,2", "3,4"],
    });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.player.x, 12.5);
    assert.equal(result.body.player.appearanceId, "ramen_noodles");
    assert.deepEqual(result.body.discovered, ["1,2", "3,4"]);

    result = await post(app.url, "/api/rooms/leave", { room: "ROUTE1", playerId: "host-1", sessionToken: "forged" });
    assert.equal(result.response.status, 403);
    result = await post(app.url, "/api/rooms/leave", { room: "ROUTE1", playerId: "host-1", sessionToken: hostToken });
    assert.equal(result.response.status, 200);
    result = await post(app.url, "/api/rooms/state", { room: "ROUTE1", playerId: "guest-1", sessionToken: guestToken, state: {} });
    assert.equal(result.body.isHost, true);
  } finally {
    await app.close();
  }
});

test("account API hashes and persists one save slot across restarts", async () => {
  const directory = await mkdtemp(join(tmpdir(), "last-route-backend-"));
  const accountStorePath = join(directory, "accounts.json");
  let app;
  try {
    app = await fixtureWith(() => createLastRouteServer({ accountStorePath }));
    let result = await post(app.url, "/api/account/register", { username: "runner_one", password: "correct horse" });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.username, "RUNNER_ONE");
    const sessionToken = result.body.sessionToken;

    result = await post(app.url, "/api/account/save", { sessionToken, progress: { depth: 7, relays: 3 } });
    assert.equal(result.response.status, 200);
    const stored = await readFile(accountStorePath, "utf8");
    assert.equal(stored.includes("correct horse"), false);
    assert.equal(JSON.parse(stored).accounts[0].username, "RUNNER_ONE");
    await app.close();

    app = await fixtureWith(() => createLastRouteServer({ accountStorePath }));
    result = await post(app.url, "/api/account/login", { username: "runner_one", password: "correct horse" });
    assert.equal(result.response.status, 200);
    assert.deepEqual(result.body.progress, { depth: 7, relays: 3 });
  } finally {
    if (app?.server.listening) await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("trusted proxy address is used only when explicitly enabled", async () => {
  const app = await fixtureWith(() => createLastRouteServer({ trustProxy: true }));
  try {
    const response = await fetch(`${app.url}/api/enet/rooms/register`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": "203.0.113.25, 127.0.0.1" },
      body: JSON.stringify({ code: "Z8X7C", port: 8421 }),
    });
    assert.equal(response.status, 201);
    assert.equal((await response.json()).room.address, "203.0.113.25");
  } finally {
    await app.close();
  }
});

test("serves validated debug/release update manifests", async () => {
  const sha256 = "a".repeat(64);
  const updateDirectory = await mkdtemp(join(tmpdir(), "last-route-updates-"));
  await writeFile(join(updateDirectory, "linux.zip"), "test-build");
  await writeFile(join(updateDirectory, "private.txt"), "not-published");
  const app = await fixtureWith(() => createLastRouteServer({
    updateDirectory,
    updates: {
      debug: { linux: { version: "0.0.1.0", revision: "c".repeat(40), file: "linux.zip", sha256, notes: "Test route", required: true } },
      release: { windows: { version: "1.0.0", url: "http://insecure.invalid/game.zip" } },
    },
  }));
  try {
    let response = await fetch(`${app.url}/api/updates/debug/linux`);
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.update.version, "0.0.1.0");
    assert.equal(payload.update.revision, "c".repeat(40));
    assert.equal(payload.update.sha256, sha256);
    assert.equal(payload.update.required, true);
    assert.equal(payload.update.url, "/api/updates/files/linux.zip");
    response = await fetch(`${app.url}/api/health`);
    const health = await response.json();
    assert.deepEqual(health.updates.debug, {
      version: "0.0.1.0",
      revision: "c".repeat(40),
      platforms: ["linux"],
    });
    response = await fetch(`${app.url}${payload.update.url}`);
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "test-build");
    response = await fetch(`${app.url}/api/updates/files/private.txt`);
    assert.equal(response.status, 404);
    response = await fetch(`${app.url}/api/updates/release/windows`);
    assert.equal(response.status, 404);
  } finally {
    await app.close();
    await rm(updateDirectory, { recursive: true, force: true });
  }
});

test("reloads update metadata without restarting the backend", async () => {
  const sha256 = "d".repeat(64);
  let revision = "a".repeat(40);
  const app = await fixtureWith(() => createLastRouteServer({
    updatesProvider: () => ({
      debug: { linux: { version: "0.0.1.0", revision, url: "https://example.test/linux.zip", sha256 } },
    }),
  }));
  try {
    let response = await fetch(`${app.url}/api/updates/debug/linux`);
    assert.equal((await response.json()).update.revision, "a".repeat(40));
    revision = "b".repeat(40);
    response = await fetch(`${app.url}/api/updates/debug/linux`);
    assert.equal((await response.json()).update.revision, "b".repeat(40));
  } finally {
    await app.close();
  }
});

test("serves the Web export with browser-safe MIME types", async () => {
  const publicDirectory = await mkdtemp(join(tmpdir(), "last-route-web-"));
  await writeFile(join(publicDirectory, "index.html"), "<title>Last Route</title>");
  await writeFile(join(publicDirectory, "index.wasm"), "wasm-test");
  const app = await fixtureWith(() => createLastRouteServer({ publicDirectory }));
  try {
    let response = await fetch(`${app.url}/`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type"), /^text\/html/);
    response = await fetch(`${app.url}/index.wasm`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/wasm");
  } finally {
    await app.close();
    await rm(publicDirectory, { recursive: true, force: true });
  }
});

test("serves only safe PNG names from the custom-map directory", async () => {
  const customMapDirectory = await mkdtemp(join(tmpdir(), "last-route-maps-"));
  await writeFile(join(customMapDirectory, "test-map.png"), "png-test");
  await writeFile(join(customMapDirectory, "notes.txt"), "not public");
  const app = await fixtureWith(() => createLastRouteServer({ customMapDirectory }));
  try {
    let response = await fetch(`${app.url}/api/custom-maps/test-map.png`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "image/png");
    assert.equal(await response.text(), "png-test");
    response = await fetch(`${app.url}/api/custom-maps/notes.txt`);
    assert.equal(response.status, 404);
    response = await fetch(`${app.url}/api/custom-maps/..%2Fnotes.txt`);
    assert.equal(response.status, 404);
  } finally {
    await app.close();
    await rm(customMapDirectory, { recursive: true, force: true });
  }
});

async function fixtureWith(factory) {
  const server = factory();
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  return {
    server,
    url: `http://127.0.0.1:${address.port}`,
    close: async () => {
      server.close();
      await once(server, "close");
    },
  };
}
