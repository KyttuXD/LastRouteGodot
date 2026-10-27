import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createDirectoryServer, createLastRouteServer, deploymentPorts } from "./server.mjs";

test("deployment separates legacy Pterodactyl HTTP and ENet allocations", () => {
  assert.deepEqual(deploymentPorts({ SERVER_PORT: "1105" }), {
    httpPort: 8105,
    relayPort: 1105,
  });
  assert.deepEqual(deploymentPorts({
    PORT: "1105",
    LASTROUTE_HTTP_PORT: "8105",
    LASTROUTE_RELAY_PORT: "1105",
  }), { httpPort: 8105, relayPort: 1105 });
  assert.deepEqual(deploymentPorts({ PORT: "8787" }), {
    httpPort: 8787,
    relayPort: 1105,
  });
});

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
  const app = await fixture({ relayAddress: "relay.test", relayPort: 1105 });
  try {
    let response = await fetch(`${app.url}/api/health`);
    assert.equal(response.status, 200);
    const health = await response.json();
    assert.equal(health.rooms, 0);
    assert.deepEqual(health.updates, {});

    response = await fetch(`${app.url}/api/enet/rooms/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        code: "ABCDE",
        port: 8421,
        players: 2,
      }),
    });
    assert.equal(response.status, 201);
    const registration = await response.json();
    assert.ok(registration.token);
    assert.equal(registration.room.address, "relay.test");
    assert.equal(registration.room.transport, "relay");

    response = await fetch(`${app.url}/api/enet/rooms/ABCDE`);
    const resolved = await response.json();
    assert.deepEqual(
      { address: resolved.room.address, port: resolved.room.port, players: resolved.room.players },
      { address: "relay.test", port: 1105, players: 2 },
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

test("a host can securely release a room for relay migration", async () => {
  const app = await fixture();
  try {
    let response = await fetch(`${app.url}/api/enet/rooms/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "M2GRT", port: 8421, players: 2 }),
    });
    const registration = await response.json();
    response = await fetch(`${app.url}/api/enet/rooms/release-host`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "M2GRT", token: "forged" }),
    });
    assert.equal(response.status, 403);
    response = await fetch(`${app.url}/api/enet/rooms/release-host`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "M2GRT", token: registration.token }),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).migrating, false,
      "a server without a live relay cannot promise migration");
    response = await fetch(`${app.url}/api/enet/rooms/M2GRT`);
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

    result = await post(app.url, "/api/account/register", { username: "RuNnEr_OnE", password: "another password" });
    assert.equal(result.response.status, 409, "case variants must resolve to one account");

    result = await post(app.url, "/api/account/session", { sessionToken });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.username, "RUNNER_ONE");

    result = await post(app.url, "/api/account/save", { sessionToken, progress: { depth: 7, relays: 3 } });
    assert.equal(result.response.status, 200);
    assert.deepEqual(result.body.progress, { depth: 7, relays: 3 });

    result = await post(app.url, "/api/account/session", { sessionToken });
    assert.equal(result.response.status, 200);
    assert.deepEqual(result.body.progress, { depth: 7, relays: 3 },
      "session restore must include the account checkpoint");
    const stored = await readFile(accountStorePath, "utf8");
    assert.equal(stored.includes("correct horse"), false);
    assert.equal(JSON.parse(stored).accounts[0].username, "RUNNER_ONE");
    await app.close();

    app = await fixtureWith(() => createLastRouteServer({ accountStorePath }));
    result = await post(app.url, "/api/account/session", { sessionToken });
    assert.equal(result.response.status, 200,
      "a 30-day account session must survive a backend restart");
    assert.deepEqual(result.body.progress, { depth: 7, relays: 3 });

	result = await post(app.url, "/api/account/rename", {
		sessionToken, username: "Runner_Two",
	});
	assert.equal(result.response.status, 200);
	assert.equal(result.body.username, "RUNNER_TWO");
	result = await post(app.url, "/api/account/session", { sessionToken });
	assert.equal(result.response.status, 200);
	assert.equal(result.body.username, "RUNNER_TWO",
		"renaming must update every persisted session owner");
	result = await post(app.url, "/api/account/login", {
		username: "runner_two", password: "correct horse",
	});
	assert.equal(result.response.status, 200);
	const otherSessionToken = result.body.sessionToken;

	result = await post(app.url, "/api/account/password", {
		sessionToken, password: "updated password",
	});
	assert.equal(result.response.status, 200);
	result = await post(app.url, "/api/account/session", {
		sessionToken: otherSessionToken,
	});
	assert.equal(result.response.status, 401,
		"password replacement must revoke every other persistent session");
	result = await post(app.url, "/api/account/session", { sessionToken });
	assert.equal(result.response.status, 200,
		"password replacement must preserve the session which authorized it");
	result = await post(app.url, "/api/account/login", {
		username: "runner_two", password: "correct horse",
	});
	assert.equal(result.response.status, 401, "old password still works after replacement");
	result = await post(app.url, "/api/account/login", {
		username: "RUNNER_TWO", password: "updated password",
	});
	assert.equal(result.response.status, 200);

    result = await post(app.url, "/api/account/login", { username: "rUnNeR_oNe", password: "correct horse" });
	assert.equal(result.response.status, 401);
    const persisted = JSON.parse(await readFile(accountStorePath, "utf8"));
    assert.equal(JSON.stringify(persisted).includes(sessionToken), false,
      "raw bearer session tokens must not be written to disk");
	assert.equal(JSON.stringify(persisted).includes("updated password"), false,
		"replacement password must not be written to disk");
    assert.equal(persisted.sessions.length >= 1, true);
  } finally {
    if (app?.server.listening) await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("only canonical KYTTU and AYTTU accounts receive owner identity", async () => {
  const directory = await mkdtemp(join(tmpdir(), "last-route-admin-"));
  const accountStorePath = join(directory, "accounts.json");
  const app = await fixtureWith(() => createLastRouteServer({
    accountStorePath,
    adminPassword: "server setup proof",
  }));
  try {
    let result = await post(app.url, "/api/account/register", {
      username: "Kyttu", password: "account password",
    });
    assert.equal(result.response.status, 403, "reserved admin account needs server proof");

    result = await post(app.url, "/api/account/register", {
      username: "kyttu_fan", password: "fan password",
    });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.username, "KYTTU_FAN");
    assert.equal(result.body.admin, false, "a username containing KYTTU is not an admin");

    result = await post(app.url, "/api/account/register", {
      username: "KytTU",
      password: "account password",
      adminProof: "server setup proof",
    });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.username, "KYTTU");
    assert.equal(result.body.admin, true);
	assert.equal(result.body.adminOwner, true);
	assert.deepEqual(result.body.adminPermissions,
		["hunters", "inventory", "player", "visual", "world"]);
	const adminSession = result.body.sessionToken;
	result = await post(app.url, "/api/account/rename", {
		sessionToken: adminSession, username: "Kyttu",
	});
	assert.equal(result.response.status, 200,
		"the authenticated KYTTU account cannot retain its canonical name");
	assert.equal(result.body.admin, true);

    result = await post(app.url, "/api/account/login", {
      username: "kYtTu", password: "account password",
    });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.username, "KYTTU");
    assert.equal(result.body.admin, true);

	result = await post(app.url, "/api/account/register", {
		username: "AYTTU", password: "second owner password",
		adminProof: "server setup proof",
	});
	assert.equal(result.response.status, 200);
	assert.equal(result.body.username, "AYTTU");
	assert.equal(result.body.adminOwner, true);
	const ayttuSession = result.body.sessionToken;

	result = await post(app.url, "/api/account/rename", {
		sessionToken: ayttuSession, username: "AYTTU_RENAMED",
	});
	assert.equal(result.response.status, 403,
		"a full owner could rename away the identity which grants owner access");
	assert.equal(result.body.code, "OWNER_IMMUTABLE");

    result = await post(app.url, "/api/dev/reload", {
      sessionToken: ayttuSession,
    });
    assert.equal(result.response.status, 200, "authenticated KYTTU session is developer proof");
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("owners grant scoped admin access while delegated admins cannot edit the roster", async () => {
  const directory = await mkdtemp(join(tmpdir(), "last-route-admin-roster-"));
  const accountStorePath = join(directory, "accounts.json");
  const app = await fixtureWith(() => createLastRouteServer({
    accountStorePath,
    adminPassword: "server setup proof",
  }));
  try {
    let result = await post(app.url, "/api/account/register", {
      username: "KYTTU", password: "owner password", adminProof: "server setup proof",
    });
    const ownerSession = result.body.sessionToken;
    result = await post(app.url, "/api/account/register", {
      username: "HELPER", password: "helper password",
    });
    const helperSession = result.body.sessionToken;

    result = await post(app.url, "/api/admin/roster/set", {
      sessionToken: helperSession, username: "HELPER", permissions: ["visual"],
    });
    assert.equal(result.response.status, 403,
      "an ordinary account edited its own admin record");

    result = await post(app.url, "/api/admin/roster/set", {
      sessionToken: ownerSession,
      username: "HELPER",
      permissions: ["visual", "hunters", "not-a-permission"],
    });
    assert.equal(result.response.status, 200);
    assert.deepEqual(result.body.entry.adminPermissions, ["hunters", "visual"]);

    result = await post(app.url, "/api/account/session", { sessionToken: helperSession });
    assert.equal(result.body.admin, true);
    assert.equal(result.body.adminOwner, false);
    assert.deepEqual(result.body.adminPermissions, ["hunters", "visual"]);

    result = await post(app.url, "/api/enet/rooms/register", {
      code: "SC2P3", port: 8421,
    });
    const hostToken = result.body.token;
    result = await post(app.url, "/api/enet/admin-tickets/issue", {
      code: "SC2P3", sessionToken: helperSession,
    });
    assert.equal(result.response.status, 201);
    assert.deepEqual(result.body.permissions, ["hunters", "visual"]);
    const delegatedTicket = result.body.ticket;
    result = await post(app.url, "/api/enet/admin-tickets/verify", {
      code: "SC2P3", ticket: delegatedTicket, hostToken,
    });
    assert.equal(result.response.status, 200);
    assert.deepEqual(result.body.permissions, ["hunters", "visual"],
      "room proof widened delegated permissions");

    result = await post(app.url, "/api/admin/roster", { sessionToken: helperSession });
    assert.equal(result.response.status, 403,
      "a delegated admin listed the owner-managed roster");
    result = await post(app.url, "/api/admin/roster", { sessionToken: ownerSession });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.roster.some((entry) => entry.username === "AYTTU"
      && entry.adminOwner), true);
    assert.equal(result.body.roster.some((entry) => entry.username === "HELPER"
      && entry.adminPermissions.join(",") === "hunters,visual"), true);

    result = await post(app.url, "/api/admin/roster/remove", {
      sessionToken: ownerSession, username: "HELPER",
    });
    assert.equal(result.response.status, 200);
    result = await post(app.url, "/api/enet/admin-tickets/verify", {
      code: "SC2P3", ticket: delegatedTicket, hostToken,
    });
    assert.equal(result.response.status, 403,
      "a revoked delegated admin retained an outstanding room ticket");
    result = await post(app.url, "/api/account/session", { sessionToken: helperSession });
    assert.equal(result.body.admin, false);
    assert.deepEqual(result.body.adminPermissions, []);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("room-bound admin tickets prove KYTTU without exposing an account session", async () => {
  const directory = await mkdtemp(join(tmpdir(), "last-route-admin-ticket-"));
  const accountStorePath = join(directory, "accounts.json");
  let current = 50_000;
  const app = await fixtureWith(() => createLastRouteServer({
    accountStorePath,
    adminPassword: "server setup proof",
    adminTicketTtlMs: 10_000,
    now: () => current,
  }));
  try {
    let result = await post(app.url, "/api/enet/rooms/register", {
      code: "T3ST5", port: 8421,
    });
    assert.equal(result.response.status, 201);
    const hostToken = result.body.token;

    result = await post(app.url, "/api/account/register", {
      username: "KYTTU", password: "account password", adminProof: "server setup proof",
    });
    assert.equal(result.response.status, 200);
    const sessionToken = result.body.sessionToken;

    result = await post(app.url, "/api/enet/admin-tickets/issue", {
      code: "T3ST5", sessionToken,
    });
    assert.equal(result.response.status, 201);
    assert.match(result.body.ticket, /^[A-Za-z0-9_-]{43}$/);
    assert.equal("sessionToken" in result.body, false,
      "a room proof must never echo the account bearer token");
    const ticket = result.body.ticket;

    result = await post(app.url, "/api/enet/admin-tickets/verify", {
      code: "T3ST5", ticket, hostToken: "forged",
    });
    assert.equal(result.response.status, 403,
      "only the room host may ask the backend to verify a guest proof");

    result = await post(app.url, "/api/enet/admin-tickets/verify", {
      code: "T3ST5", ticket, hostToken,
    });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.authorized, true);
	assert.deepEqual(result.body.permissions,
		["hunters", "inventory", "player", "visual", "world"]);

    current += 10_001;
    result = await post(app.url, "/api/enet/admin-tickets/verify", {
      code: "T3ST5", ticket, hostToken,
    });
    assert.equal(result.response.status, 403,
      "expired room proofs must not remain usable");

    result = await post(app.url, "/api/account/register", {
      username: "runner_two", password: "runner password",
    });
    result = await post(app.url, "/api/enet/admin-tickets/issue", {
      code: "T3ST5", sessionToken: result.body.sessionToken,
    });
    assert.equal(result.response.status, 403,
      "ordinary accounts may not mint release-admin authority");
  } finally {
    await app.close();
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

test("rate limits sensitive account endpoints per requester", async () => {
  let current = 10_000;
  const app = await fixtureWith(() => createLastRouteServer({
    now: () => current,
    rateLimitWindowMs: 10_000,
    accountRateLimitMax: 2,
    apiRateLimitMax: 20,
  }));
  try {
    let result = await post(app.url, "/api/account/login", {
      username: "NOBODY", password: "not the password",
    });
    assert.equal(result.response.status, 401);
    result = await post(app.url, "/api/account/login", {
      username: "NOBODY", password: "not the password",
    });
    assert.equal(result.response.status, 401);
    result = await post(app.url, "/api/account/login", {
      username: "NOBODY", password: "not the password",
    });
    assert.equal(result.response.status, 429);
    assert.equal(result.response.headers.get("retry-after"), "10");
    assert.equal(result.body.code, "RATE_LIMITED");

    current += 10_001;
    result = await post(app.url, "/api/account/login", {
      username: "NOBODY", password: "not the password",
    });
    assert.equal(result.response.status, 401,
      "the requester stayed blocked after its rate window elapsed");
  } finally {
    await app.close();
  }
});

test("serves validated debug/release update manifests", async () => {
  const sha256 = "a".repeat(64);
  const updateDirectory = await mkdtemp(join(tmpdir(), "last-route-updates-"));
  await writeFile(join(updateDirectory, "linux.zip"), "test-build");
  await writeFile(join(updateDirectory, "windows-legacy.zip"), "legacy-build");
  await writeFile(join(updateDirectory, "private.txt"), "not-published");
  const app = await fixtureWith(() => createLastRouteServer({
    updateDirectory,
    updates: {
      debug: {
        linux: { version: "0.0.1.0", revision: "c".repeat(40), file: "linux.zip", bytes: 10, sha256, notes: "Test route", required: true },
        windows_legacy: { version: "0.0.1.0", revision: "c".repeat(40), file: "windows-legacy.zip", sha256 },
      },
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
    assert.equal(payload.update.file, "linux.zip");
    assert.equal(payload.update.bytes, 10);
    assert.equal(payload.update.required, true);
    assert.equal(payload.update.url, "/api/updates/files/linux.zip");
    response = await fetch(`${app.url}/api/health`);
    const health = await response.json();
    assert.deepEqual(health.updates.debug, {
      version: "0.0.1.0",
      revision: "c".repeat(40),
      platforms: ["linux", "windows_legacy"],
    });
    response = await fetch(`${app.url}/api/updates/debug/windows_legacy`);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).update.file, "windows-legacy.zip");
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

test("rooms carry the game they belong to (missing or invalid means last_route)", async () => {
  const app = await fixture();
  try {
    const register = (code, game) => fetch(`${app.url}/api/enet/rooms/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(game === undefined ? { code, port: 8421 } : { code, port: 8421, game }),
    });
    assert.equal((await register("CTY22", "city")).status, 201);
    assert.equal((await register("LEGCY")).status, 201);
    assert.equal((await register("WERD2", "Bad Game!")).status, 201);
    const gameOf = async (code) => (await (await fetch(`${app.url}/api/enet/rooms/${code}`)).json()).room.game;
    assert.equal(await gameOf("CTY22"), "city");
    assert.equal(await gameOf("LEGCY"), "last_route");
    assert.equal(await gameOf("WERD2"), "last_route");
  } finally {
    await app.close();
  }
});
