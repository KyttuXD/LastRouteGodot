// Network smoke test for a running Last Route Godot 2 backend (no Godot needed).
//   node deploy/smoke.mjs http://127.0.0.1:8105
// Checks health, the room directory (register -> resolve -> unregister) and the PUBLIC route status.
const base = (process.argv[2] || "http://127.0.0.1:8105").replace(/\/$/, "");
let failed = 0;
const ok = (message) => console.log(`SMOKE OK   ${message}`);
const bad = (message) => { failed += 1; console.log(`SMOKE FAIL ${message}`); };

async function call(method, path, body) {
  const response = await fetch(base + path, {
    method,
    headers: body ? { "content-type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(8000),
  });
  let json = null;
  try { json = await response.json(); } catch { /* non-JSON */ }
  return { status: response.status, json };
}

try {
  const health = await call("GET", "/api/health");
  if (health.status === 200 && health.json?.ok) ok(`health (${JSON.stringify(health.json).slice(0, 160)})`);
  else bad(`health: HTTP ${health.status}`);

  const code = "S" + Math.random().toString(36).slice(2, 6).toUpperCase();
  const registered = await call("POST", "/api/enet/rooms/register", { code, port: 8421, players: 1 });
  if (registered.status !== 201 || !registered.json?.token) {
    bad(`register: HTTP ${registered.status} ${JSON.stringify(registered.json)}`);
  } else {
    ok(`register ${code}`);
    const found = await call("GET", `/api/enet/rooms/${code}`);
    if (found.status === 200 && found.json?.ok) ok(`resolve ${code} (${found.json.room?.transport || "direct"})`);
    else bad(`resolve: HTTP ${found.status}`);
    const removed = await call("POST", "/api/enet/rooms/unregister", { code, token: registered.json.token });
    if (removed.status === 200 && removed.json?.removed) ok("unregister");
    else bad(`unregister: HTTP ${removed.status}`);
    const gone = await call("GET", `/api/enet/rooms/${code}`);
    if (gone.status === 404 || gone.json?.ok === false) ok("room gone after unregister");
    else bad(`room still listed after unregister (HTTP ${gone.status})`);
  }

  const status = await call("GET", "/api/public/status");
  if (status.status === 200 && status.json?.code) ok(`PUBLIC route status (${status.json.code}, day ${status.json.day})`);
  else bad(`public status: HTTP ${status.status}`);
} catch (error) {
  bad(`request failed: ${error.message}`);
}
console.log(failed === 0 ? "smoke test OK" : `smoke test FAILED (${failed})`);
process.exit(failed === 0 ? 0 : 1);
