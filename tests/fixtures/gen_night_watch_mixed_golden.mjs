// Writes tests/fixtures/night_watch_mixed_golden.json from the 2D game's Mixed Shift rules (games/night-watch/src/modes/mixed/mixed-logic.js): whole shifts of
// every preset (QUIET, STEADY, RESTLESS, CHAOS, ENDLESS) played by a fixed, state-reading bot, as an event log and a final summary, plus the drawn rosters and the
// planned spikes of many seeds. tests/validate_night_watch_mixed.gd plays the same shifts with MixedLogic and demands the same logs.
//   node tests/fixtures/gen_night_watch_mixed_golden.mjs [path to games/night-watch]
import { pathToFileURL, fileURLToPath } from "node:url";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const root = process.argv[2];
if (!root) { console.error("usage: node " + process.argv[1] + " <path to games/night-watch>"); process.exit(1); }
const L = await import(pathToFileURL(join(root, "src/modes/mixed/mixed-logic.js")).href);
const D = await import(pathToFileURL(join(root, "src/modes/mixed/mixed-data.js")).href);
const { mulberry32 } = await import(pathToFileURL(join(root, "src/core/rng.js")).href);
const { createMixedGame } = L;

// The bot reads the state and answers with the setters, every step (never the same two runs differ).
const bot = (kind, g) => {
  const s = g.state;
  if (kind === "idle") return;
  const e = s.elapsed;
  for (const side of ["L", "R"]) g.setDoor(side, g.list().some((t) => t.armed && t.side === side && t.type !== "vent"));
  for (const key of ["L", "R", "T"]) g.setVent(key, g.list().some((t) => t.armed && t.type === "vent" && t.side === key));
  for (const key of ["L", "R", "T"]) g.lightVent(key);
  g.setMonitor(Math.floor(e / 9000) % 2 === 0);
  g.setRoom(D.CAM_ROOMS[Math.floor(e / 4000) % D.CAM_ROOMS.length]);
  const w = g.list().find((t) => t.type === "winder");
  g.setWind(!!w && w.tune < 0.6);
};
const num = (x) => (x === undefined || x === null || x === "" ? "" : typeof x === "number" ? String(Math.round(x)) : String(x));
const ev2s = (e) => [e.type, e.id, e.kind, e.room, e.side, e.how, e.mood, e.phase, e.tkind, e.key, e.a, e.beat, e.t, e.lead, e.next, e.gen, e.hour, e.to, e.added?.join(","), e.removed?.join(",")].map(num).join("|");
const f6 = (x) => Number(x.toFixed(6));

const cases = [];
for (let d = 0; d < 5; d++) for (const seed of [11, 4242]) cases.push({ diff: d, seed, kind: "bot", steps: d === 4 ? 4200 : 3000 });
for (let d = 0; d < 5; d++) cases.push({ diff: d, seed: 77, kind: "idle", steps: 3000 });
cases.push({ diff: 4, seed: 5, kind: "bot", steps: 6000 });
cases.push({ diff: 3, seed: 9, kind: "bot", steps: 3000 });

const runs = [];
for (const c of cases) {
  const g = createMixedGame({ seed: c.seed, difficulty: c.diff });
  const start = [...g.roster];
  const events = [];
  let steps = 0;
  while (!g.state.over && steps < c.steps) {
    bot(c.kind, g);
    for (const e of g.step(100)) if (e.type !== "cue") events.push(`${steps}|${ev2s(e)}`);
    steps++;
  }
  const s = g.state;
  runs.push({ ...c, ran: steps, roster: start, events, summary: { elapsed: f6(s.elapsed), over: s.over || "", by: s.by || "", beat: s.beat, tension: f6(s.tension), seal: f6(s.seal), ventSeal: f6(s.ventSeal), actSeq: s.actSeq, spikeIdx: s.spikeIdx } });
}
const rosters = [];
for (let seed = 1; seed <= 60; seed++) for (let d = 0; d < 5; d++) rosters.push({ seed, diff: d, roster: L.drawRoster(seed, d) });
const plans = [];
for (let seed = 1; seed <= 30; seed++) for (let d = 0; d < 4; d++) plans.push({ seed, diff: d, plan: L.planSpikes(mulberry32((seed ^ 0x44495243) >>> 0), d).map((p) => [p.at, p.len]) });
const here = dirname(fileURLToPath(import.meta.url));
writeFileSync(join(here, "night_watch_mixed_golden.json"), JSON.stringify({ source: "games/night-watch/src/modes/mixed/mixed-logic.js", dt: 100, runs, rosters, plans }, null, 0).replace(/\},\{/g, "},\n{") + "\n");
console.log(runs.map((r) => `${r.diff}/${r.seed}/${r.kind} ${r.summary.over}${r.summary.by ? ":" + r.summary.by : ""} ran ${r.ran} ${r.events.length} events [${r.roster}]`).join("\n"));
